"""Shared helpers for the Level 0 sound set (procedural synthesis, loudness, ElevenLabs cache)."""
import hashlib
import json
import os
import time
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
import requests
import soundfile as sf
from scipy import signal

SR = 48000
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CACHE = HERE / "cache"
OUT = ROOT / "game" / "assets" / "audio" / "level0"
PREVIEWS = HERE / "previews"
for d in (CACHE, OUT, PREVIEWS):
    d.mkdir(parents=True, exist_ok=True)

_meter = pyln.Meter(SR)


# ---------------------------------------------------------------- loudness
def lufs(x):
    """Integrated LUFS of mono (n,) or stereo (n,2) float array. Pads to >=0.5 s."""
    y = x if x.ndim == 2 else x[:, None]
    if len(y) < int(0.5 * SR):
        y = np.vstack([y, np.zeros((int(0.5 * SR) - len(y), y.shape[1]))])
    return float(_meter.integrated_loudness(y))


def peak_db(x):
    return 20 * np.log10(max(np.max(np.abs(x)), 1e-12))


def norm_lufs(x, target=-23.0):
    return x * 10 ** ((target - lufs(x)) / 20)


def norm_peak(x, target_db=-3.0):
    return x * 10 ** ((target_db - peak_db(x)) / 20)


def write_wav(name, x):
    path = OUT / name
    sf.write(path, np.clip(x, -1, 1).astype(np.float32), SR, subtype="PCM_16")
    return path


# ---------------------------------------------------------------- periodic synthesis
def tvec(n):
    return np.arange(n) / SR


def pnoise(n, shape, rng):
    """Perfectly periodic (length n) noise: random phase, magnitude from shape(freq_hz). RMS 1."""
    f = np.fft.rfftfreq(n, 1 / SR)
    mag = shape(f)
    mag[0] = 0
    ph = rng.uniform(0, 2 * np.pi, len(f))
    ph[-1] = 0
    x = np.fft.irfft(mag * np.exp(1j * ph), n)
    return x / np.sqrt(np.mean(x ** 2))


def band(lo, hi, slope=24.0):
    """Magnitude shape: flat between lo/hi, rolling off at `slope` dB/octave outside."""
    def fn(f):
        f = np.maximum(f, 1e-3)
        g = np.ones_like(f)
        lo_m = f < lo
        hi_m = f > hi
        g[lo_m] = 10 ** (-slope * np.log2(lo / f[lo_m]) / 20)
        g[hi_m] = 10 ** (-slope * np.log2(f[hi_m] / hi) / 20)
        return g
    return fn


def tilt(f_lo, f_hi, db_per_oct):
    """1/f style tilt between f_lo and f_hi, steep rolloff outside."""
    def fn(f):
        f = np.maximum(f, 1e-3)
        g = (np.clip(f, f_lo, f_hi) / f_lo) ** (db_per_oct / 6.02)
        g = g * np.where(f < f_lo, 10 ** (-24 * np.log2(f_lo / f) / 20), 1.0)
        g = g * np.where(f > f_hi, 10 ** (-24 * np.log2(f / f_hi) / 20), 1.0)
        return g
    return fn


def softclip(x, k=1.0):
    return np.tanh(x * k) / np.tanh(k)


def circ_conv_add(buf, pos, ev):
    """Add short event `ev` at index `pos` into `buf` with wrap-around (keeps loops seamless)."""
    n = len(buf)
    idx = (pos + np.arange(len(ev))) % n
    np.add.at(buf, idx, ev)


# ---------------------------------------------------------------- one-shot helpers
def fade(x, fin_ms=0, fout_ms=0):
    x = x.copy()
    a = int(fin_ms * SR / 1000)
    b = int(fout_ms * SR / 1000)
    if a:
        x[:a] *= np.linspace(0, 1, a) ** 1.0
    if b:
        x[-b:] *= np.linspace(1, 0, b) ** 1.5
    return x


def resample_to_sr(x, sr):
    if sr == SR:
        return x
    from math import gcd
    g = gcd(SR, sr)
    return signal.resample_poly(x, SR // g, sr // g)


def butter(x, kind, fc, order=4):
    sos = signal.butter(order, fc, btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x)


# ---------------------------------------------------------------- ElevenLabs (cached)
EL_URL = "https://api.elevenlabs.io/v1/sound-generation"
EL_MODEL = "eleven_text_to_sound_v2"
USD_PER_CREDIT = 0.0003  # conservative (Creator tier is roughly 0.00022)


def _key():
    from dotenv import load_dotenv
    load_dotenv(ROOT / ".env")
    k = os.environ.get("ELEVENLABS_API_KEY")
    if not k:
        raise RuntimeError("ELEVENLABS_API_KEY missing from environment/.env")
    return k


def eleven_sfx(tag, text, duration, prompt_influence=0.5, loop=False):
    """Return (float mono array at 48 kHz, meta dict). Cached on disk by parameter hash; never re-pays."""
    params = dict(text=text, duration_seconds=duration, prompt_influence=prompt_influence,
                  model_id=EL_MODEL, loop=loop)
    h = hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()[:12]
    meta_p = CACHE / f"{tag}_{h}.json"
    if meta_p.exists():
        meta = json.loads(meta_p.read_text())
        raw = CACHE / meta["file"]
        return _decode(raw, meta["format"]), meta

    key = _key()
    body = dict(text=text, duration_seconds=duration, prompt_influence=prompt_influence,
                model_id=EL_MODEL, loop=loop)
    attempts = 0
    r = None
    for fmt in ("pcm_48000", "mp3_44100_128"):
        for _ in range(3):  # 1 try + max 2 retries (transient errors only)
            attempts += 1
            try:
                r = requests.post(EL_URL, params={"output_format": fmt},
                                  headers={"xi-api-key": key}, json=body, timeout=180)
            except requests.RequestException as e:
                print(f"  [{tag}] network error: {type(e).__name__}")
                time.sleep(3)
                continue
            if r.status_code == 200:
                break
            if r.status_code >= 500:
                time.sleep(3)
                continue
            break
        if r is not None and r.status_code == 200:
            break
        if r is not None and r.status_code in (400, 402, 403, 422) and fmt == "pcm_48000":
            print(f"  [{tag}] pcm_48000 refused ({r.status_code}); trying mp3_44100_128")
            continue
        break
    if r is None or r.status_code != 200:
        code = None if r is None else r.status_code
        detail = "" if r is None else r.text[:300]
        raise RuntimeError(f"ElevenLabs failed for {tag}: status={code} {detail}")
    ext = "pcm" if fmt.startswith("pcm") else "mp3"
    raw = CACHE / f"{tag}_{h}.{ext}"
    raw.write_bytes(r.content)
    cost_hdr = r.headers.get("character-cost")
    credits = float(cost_hdr) if cost_hdr else 20.0 * (duration or 5)
    meta = dict(tag=tag, params=params, file=raw.name, format=fmt, credits=credits,
                est_usd=round(credits * USD_PER_CREDIT, 4), credits_from_header=bool(cost_hdr),
                http_attempts=attempts, date=time.strftime("%Y-%m-%d"))
    meta_p.write_text(json.dumps(meta, indent=1))
    return _decode(raw, fmt), meta


def _decode(path, fmt):
    if fmt.startswith("pcm"):
        x = np.frombuffer(path.read_bytes(), dtype="<i2").astype(np.float64) / 32768
        return x
    x, sr = sf.read(path, dtype="float64")
    if x.ndim == 2:
        x = x.mean(1)
    return resample_to_sr(x, sr)
