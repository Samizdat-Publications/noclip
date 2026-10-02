"""S03 sound additions for Level 0 (soggy steps, work light hum, wall draft, tape dropouts, reversed breath, light death).

    python pipeline/audio/build_s03.py

ElevenLabs outputs are cached in pipeline/audio/cache/ (so re-runs are free). Everything else is seeded and procedural.
Only ADDS new files to game/assets/audio/level0/. Writes pipeline/manifests/audio_s03.json and previews s03_*.png.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundfile as sf
from scipy import signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

import l0_lib as L
from l0_lib import SR, OUT, PREVIEWS, ROOT

manifest = {"asset": "audio_s03", "sample_rate": SR, "bit_depth": 16,
            "elevenlabs": {"model_id": L.EL_MODEL, "endpoint": "POST /v1/sound-generation"},
            "files": {}, "paid_calls": []}


def reg(name, **info):
    manifest["files"][name] = info


def paid(meta):
    manifest["paid_calls"].append({k: meta[k] for k in
                                   ("tag", "params", "file", "format", "credits", "est_usd", "http_attempts", "date")})


def envelope(x, ms=6):
    n = max(1, int(ms * SR / 1000))
    return np.convolve(np.abs(x), np.ones(n) / n, mode="same")


def slice_steps(x, min_gap=0.30, max_len=0.60):
    env = envelope(x, 8)
    mx = env.max()
    pk, _ = signal.find_peaks(env, height=0.2 * mx, distance=int(min_gap * SR))
    cands = []
    for i, p in enumerate(pk):
        lo = max(0, p - int(0.10 * SR))
        seg = env[lo:p]
        below = np.where(seg < 0.12 * env[p])[0]
        on = lo + (below[-1] if len(below) else 0)
        start = max(0, on - int(0.008 * SR))
        nxt = pk[i + 1] if i + 1 < len(pk) else len(x)
        end = min(start + int(max_len * SR), nxt - int(0.05 * SR), len(x))
        tail = env[p:end]
        quiet = np.where(tail < 0.05 * env[p])[0]
        if len(quiet):
            end = p + quiet[0] + int(0.03 * SR)
        if end - start < int(0.25 * SR):
            end = min(start + int(0.27 * SR), len(x))
            if end - start < int(0.25 * SR):
                continue
        pre = env[max(0, start - int(0.12 * SR)):start]
        iso = (pre.max() if len(pre) else 0) / env[p]
        cands.append(dict(start=start, end=end, peak_t=p / SR, iso=float(iso)))
    return cands


def body_eq(a):
    """Extra low-mid body: +4 dB peaking around 280 Hz, gentle 9 kHz lowpass (no hard heel click)."""
    f0, q, g = 280.0, 0.9, 4.0
    A = 10 ** (g / 40)
    w0 = 2 * np.pi * f0 / SR
    al = np.sin(w0) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w0), 1 - al * A]
    aa = [1 + al / A, -2 * np.cos(w0), 1 - al / A]
    a = signal.lfilter(b, aa, a)
    return L.butter(a, "low", 9000, 2)


# measured peak of existing step_carpet_wet_*.wav: about -3.0 to -4.2 dBFS (median -3.1)
STEP_PEAK_DB = -3.2
SOGGY_BASE = ("Single person in soft-soled sneakers walking{pace} on thick, waterlogged commercial office carpet, close "
              "microphone, completely dry room with no echo, no other sounds, no voices, no music. Each footstep is a "
              "muffled low thud followed by a wet squelch as water is pressed out of the sodden carpet, and a small "
              "squish as the foot lifts. No hard heel click. Clean separate footsteps with silence between them.")


def make_steps(prefix, pace, dur, count, seed, takes, min_gap):
    rng = np.random.default_rng(seed)
    pool = []
    for tk in range(takes):
        txt = SOGGY_BASE.format(pace=pace) + ("", " Varied gait.", " Heavier steps.", " Lighter steps.",
                                              " More squelch.", " Longer squelch.")[tk]
        x, meta = L.eleven_sfx(f"{prefix}_take{tk + 1}", txt, dur, 0.6)
        paid(meta)
        x = L.butter(x, "high", 60, 4)   # the raw takes carry sub-100 Hz rumble that fools onset detection
        for c in slice_steps(x, min_gap=min_gap):
            a_ = x[c["start"]:c["end"]]
            fq, pw = signal.welch(a_, SR, nperseg=min(len(a_), 2048))
            pw = pw / pw.sum()
            crest = np.abs(a_).max() / np.sqrt(np.mean(a_ ** 2))
            if pw[fq < 100].sum() > 0.35 or crest > 13 or (fq * pw).sum() < 150:
                continue                     # rumble-only slices and hard clicks are rejected
            c["audio"] = a_.copy()
            cen = (fq * pw).sum()
            e2 = a_ ** 2
            compact = e2[:int(0.18 * SR)].sum() / e2.sum()          # one event, not a slab or a flurry
            en = envelope(a_, 8)
            later = en[int(0.14 * SR):].max() / en.max() if len(en) > int(0.15 * SR) else 0
            if compact < 0.72 or later > 0.35 or crest < 5.5:
                continue
            c["score"] = L.lufs(a_) / 3 - abs(cen - 1300) / 500 + 2 * compact
            c["take"] = tk + 1
            pool.append(c)
    pool.sort(key=lambda c: -(c["score"] - 6 * c["iso"]))   # loud, mid-heavy, isolated squelches first
    sel = sorted(pool[:count], key=lambda c: (c["take"], c["peak_t"]))
    outs = []
    for k, c in enumerate(sel, 1):
        a = c["audio"] - np.mean(c["audio"])
        r = float(rng.uniform(0.95, 1.05))
        a = signal.resample(a, int(len(a) / r))
        a = body_eq(a)
        a = L.fade(a, 10, 10)
        a = L.norm_peak(a, STEP_PEAK_DB)
        outs.append((f"{prefix}_{k:02d}.wav", a, dict(take=c["take"], src_start_s=round(c["start"] / SR, 3),
                                                       pitch_ratio=round(r, 3), length_s=round(len(a) / SR, 3))))
    return outs, len(pool)


steps, npool = make_steps("step_carpet_soggy", " slowly and steadily", 10.0, 8, 9101, 6, 0.45)
runs, npool_r = make_steps("step_carpet_soggy_run", " at a fast run", 8.0, 4, 9202, 4, 0.25)
for outs in (steps, runs):
    for name, a, info in outs:
        L.write_wav(name, a)
        reg(name, method="ElevenLabs sound effects take(s), onset-sliced, +/-5% pitch resample, +4 dB body at 280 Hz, "
            "9 kHz lowpass, 10 ms fades, peak -3.2 dBFS", channels=1, **info)
manifest["step_pool"] = dict(walk=npool, run=npool_r)


# ============================================================ loops (procedural, periodic)
def rms_norm(x):
    return x / np.sqrt(np.mean(x ** 2))


def worklight_hum(dur=8.0, seed=4404):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for h, amp in ((120, 1.0), (240, 0.42), (360, 0.15), (480, 0.06)):   # integer cycles in dur -> seamless
        x += amp * np.sin(2 * np.pi * h * t + rng.uniform(0, 6.28))
    x *= 1 + 0.06 * np.sin(2 * np.pi * (2 / dur) * t + 1.1) + 0.03 * np.sin(2 * np.pi * (5 / dur) * t)
    whine = np.sin(2 * np.pi * 2800 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * (3 / dur) * t + 0.4))
    x += 0.025 * whine
    x += 0.10 * L.pnoise(n, L.band(60, 900, 12), rng)
    n0 = len(x)
    return L.butter(np.tile(x, 3), "low", 3500, 2)[n0:2 * n0]


def seam_draft(dur=10.0, seed=6606):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    breath = L.pnoise(n, L.band(500, 3500, 12), rng)
    swell = 0.55 + 0.30 * np.sin(2 * np.pi * (1 / dur) * t + 0.7) + 0.15 * np.sin(2 * np.pi * (3 / dur) * t + 2.0)
    x = breath * swell
    low = L.pnoise(n, L.band(80, 400, 12), rng) * (0.45 + 0.25 * np.sin(2 * np.pi * (2 / dur) * t + 1.9))
    x = x + 0.5 * low
    hiss = L.pnoise(n, L.band(4500, 12000, 6), rng)
    x = rms_norm(x) + 0.10 * hiss
    return x


# NOTE: butter lowpass on a loop leaves a tiny seam transient; both loops are re-made periodic by
# filtering a 3x tiled copy and keeping the middle repeat.
def periodic_filter(fn, x):
    n = len(x)
    y = fn(np.tile(x, 3))
    return y[n:2 * n]


w = L.norm_lufs(worklight_hum(), -29.0)
L.write_wav("worklight_hum.wav", w)
reg("worklight_hum.wav", method="procedural: integer-cycle 120/240/360/480 Hz sines, slow level drift, 2.8 kHz filament "
    "whine (-32 dB), FFT-periodic warm noise, 3.5 kHz lowpass", seed=4404, duration_s=8.0, channels=1,
    target_lufs=-29, note="hum_fixture_a is -23 LUFS, so this is 6 dB quieter")
d = L.norm_lufs(seam_draft(), -40.0)
L.write_wav("seam_draft.wav", d)
reg("seam_draft.wav", method="procedural: FFT-periodic breath noise 0.5-3.5 kHz with 0.1/0.3 Hz swells, 80-400 Hz "
    "air, tape hiss 4.5-12 kHz at -20 dB; no tonal components", seed=6606, duration_s=10.0, channels=1, target_lufs=-40)


# ============================================================ tape dropouts
def tape_dropout(seed, dur):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for pos, amp in ((0.004, 1.0), (0.004 + rng.uniform(0.006, 0.02), 0.6), (0.004 + rng.uniform(0.025, 0.05), 0.35)):
        i = int(pos * SR)
        m = min(int(0.006 * SR), n - i)
        x[i:i + m] += amp * rng.standard_normal(m) * np.exp(-np.arange(m) / (0.0012 * SR))
    env = np.exp(-t / (dur * 0.45)) * (0.6 + 0.4 * (rng.random(n) > 0.5))
    env = np.convolve(env, np.ones(int(0.002 * SR)) / int(0.002 * SR), mode="same")
    burst = L.butter(rng.standard_normal(n), "high", 1500, 2) * env
    x = x * 1.3 + 0.55 * burst
    f = 5200 * np.exp(-t / 0.03) + 900
    x += 0.18 * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.05)
    x = L.butter(L.butter(x, "high", 500, 2), "low", 7000, 2)
    x = L.softclip(x / np.max(np.abs(x)), 1.6)
    return L.fade(x, 1, 15)


for k, (seed, dur) in enumerate(((7701, 0.12), (7702, 0.20), (7703, 0.09)), 1):
    a = L.norm_peak(tape_dropout(seed, dur), -6.0)
    L.write_wav(f"tape_dropout_{k:02d}.wav", a)
    reg(f"tape_dropout_{k:02d}.wav", method="procedural: 3 noise clicks, ragged HF hiss burst, downward chirp, "
        "500 Hz-7 kHz camcorder speaker band, soft clip", seed=seed, duration_s=dur, channels=1, peak_dbfs=-6)


# ============================================================ reversed breath (ElevenLabs + python)
BREATH = ("A single slow human breath, one long soft inhale through the nose and mouth then a slow exhale, close "
          "microphone, breathy, intimate, completely dry with no room echo, no speech, no words, no music, no other sounds.")


def wow(x, depth_ms=1.6, rate_hz=0.8, seed=0):
    rng = np.random.default_rng(seed)
    n = len(x)
    t = np.arange(n) / SR
    d = (depth_ms / 1000 * SR) * (np.sin(2 * np.pi * rate_hz * t + rng.uniform(0, 6)) +
                                  0.4 * np.sin(2 * np.pi * rate_hz * 2.7 * t + rng.uniform(0, 6)))
    return np.interp(np.arange(n) + d, np.arange(n), x)


for k, (st, txt_extra) in enumerate(((-3, ""), (-4, " Deeper.")), 1):
    x, meta = L.eleven_sfx(f"breath_{k}", BREATH + txt_extra, 3.0, 0.55)
    paid(meta)
    ratio = 2 ** (st / 12)
    env = envelope(x, 30)
    act = np.where(env > 0.08 * env.max())[0]
    es = envelope(x, 250)
    pk = int(np.argmax(es))                       # loudest part of the breath, keep a ~1.9 s window around it
    win = int(1.9 * ratio * SR)
    a0 = int(np.clip(pk - 0.55 * win, 0, max(0, len(x) - win)))
    x = x[a0:a0 + win]
    x = x[::-1].copy()
    y = signal.resample(x, int(len(x) / ratio))
    y = wow(y, seed=k)
    y = L.butter(y, "high", 70, 2)
    y = L.butter(y, "low", 7500, 2)
    hiss = 0.01 * np.random.default_rng(88 + k).standard_normal(len(y))
    y = y + L.butter(hiss, "high", 3000, 2)
    y = L.fade(y, 450, 300)
    y = L.norm_peak(y, -12.0)
    L.write_wav(f"figure_breath_rev_{k:02d}.wav", y)
    reg(f"figure_breath_rev_{k:02d}.wav", method="ElevenLabs breath, 1.9 s window around the loudest part, reversed, 450 ms in / 300 ms out, pitch down "
        f"{abs(st)} semitones by resample, tape wow ~0.8 Hz / 1.6 ms, faint HF hiss, 70 Hz-7.5 kHz",
        channels=1, peak_dbfs=-12, length_s=round(len(y) / SR, 3), prompt=BREATH + txt_extra)


# ============================================================ fluorescent tube dying
def light_die(seed, dur):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    t0 = int(0.03 * SR)
    tt = np.arange(n - t0) / SR
    for f, a, dec in ((2350 + rng.uniform(-80, 80), 1.0, 0.018), (3710, 0.6, 0.012), (5480, 0.35, 0.008), (1180, 0.4, 0.03)):
        x[t0:] += a * np.sin(2 * np.pi * f * tt + rng.uniform(0, 6)) * np.exp(-tt / dec)
    cut_t = dur * rng.uniform(0.55, 0.7)
    hum = sum(a * np.sin(2 * np.pi * h * t + rng.uniform(0, 6)) for h, a in ((120, 1), (240, 0.5), (360, 0.3), (600, 0.15)))
    flick = 0.55 + 0.45 * (np.sin(2 * np.pi * 23 * t) > rng.uniform(-0.3, 0.3))
    hum_env = np.where(t < cut_t, 1.0, np.exp(-(t - cut_t) / 0.012)) * flick
    hum_env *= np.clip((t - 0.03) / 0.08, 0, 1)
    x += 0.28 * hum * hum_env
    nclk = 70
    pos = np.sort(rng.beta(1.0, 2.2, nclk)) * (cut_t + 0.08)
    for p in pos:
        i = int((0.03 + p) * SR)
        m = min(int(rng.uniform(0.0004, 0.003) * SR), n - i)
        if m > 4:
            x[i:i + m] += rng.uniform(0.2, 1.0) * rng.choice([-1, 1]) * rng.standard_normal(m) * np.exp(-np.arange(m) / (0.0006 * SR))
    x += 0.10 * L.butter(rng.standard_normal(n), "high", 2500, 2) * hum_env * (rng.random(n) > 0.6)
    x = L.butter(x, "high", 60, 2)
    x = L.softclip(x / np.max(np.abs(x)), 1.3)
    x = x[:int((cut_t + 0.12) * SR)]
    return L.fade(x, 2, 60)


for k, (seed, dur) in enumerate(((8801, 1.0), (8802, 1.3)), 1):
    a = L.norm_peak(light_die(seed, dur), -4.0)
    L.write_wav(f"light_die_{k:02d}.wav", a)
    reg(f"light_die_{k:02d}.wav", method="procedural: ballast tink (inharmonic damped partials), struggling 120 Hz hum "
        "that cuts off, Poisson crackle, HF sizzle", seed=seed, duration_s=dur, channels=1, peak_dbfs=-4)


# ============================================================ verification
NEW_LOOPS = ["worklight_hum.wav", "seam_draft.wav"]
ONE = sorted(manifest["files"])
verif = {}
for name in ONE:
    x, sr = sf.read(OUT / name, dtype="float64")
    assert sr == SR and x.ndim == 1
    r = dict(seconds=round(len(x) / SR, 3), lufs=round(L.lufs(x), 2), peak_dbfs=round(L.peak_db(x), 2))
    if name in NEW_LOOPS:
        typ = np.sqrt(np.mean(np.diff(x) ** 2))
        pred = x[-1] + (x[-1] - x[-2])
        r["seam_step_over_rms_step"] = round(float(abs(x[0] - pred) / typ), 2)
        wd = int(0.5 * SR)
        seam = np.concatenate([x[-wd:], x[:wd]])
        fig, ax = plt.subplots(2, 1, figsize=(12, 6))
        ax[0].plot((np.arange(2 * wd) - wd) / SR, seam, lw=0.5)
        ax[0].axvline(0, color="r", ls="--")
        ax[0].set_title(f"{name} seam: last 0.5 s | first 0.5 s (red = loop point), step ratio {r['seam_step_over_rms_step']}")
        f, tt, S = signal.spectrogram(np.tile(x, 2), SR, nperseg=2048)
        ax[1].pcolormesh(tt, f, 10 * np.log10(S + 1e-14), shading="auto", vmin=-120, vmax=-40)
        ax[1].set_ylim(0, 12000)
        ax[1].axvline(len(x) / SR, color="r", ls="--")
        ax[1].set_title("spectrogram, two repeats")
        plt.tight_layout()
        plt.savefig(PREVIEWS / f"s03_seam_{name[:-4]}.png", dpi=80)
        plt.close()
    verif[name] = r

groups = {"steps": [n for n in ONE if n.startswith("step_carpet_soggy_0")],
          "runs": [n for n in ONE if n.startswith("step_carpet_soggy_run")],
          "tape": [n for n in ONE if n.startswith("tape_dropout")],
          "breath_die": [n for n in ONE if n.startswith(("figure_breath", "light_die"))],
          "loops": NEW_LOOPS}
for g, names in groups.items():
    fig, axs = plt.subplots(len(names), 2, figsize=(14, 1.8 * len(names)), squeeze=False)
    for i, name in enumerate(names):
        x, _ = sf.read(OUT / name, dtype="float64")
        axs[i][0].plot(np.arange(len(x)) / SR, x, lw=0.4)
        axs[i][0].set_ylim(-1, 1)
        axs[i][0].set_title(f"{name}  {verif[name]['lufs']} LUFS, pk {verif[name]['peak_dbfs']}", fontsize=8)
        f, tt, S = signal.spectrogram(x, SR, nperseg=1024, noverlap=768)
        axs[i][1].pcolormesh(tt, f, 10 * np.log10(S + 1e-14), shading="auto", vmin=-120, vmax=-30)
        axs[i][1].set_ylim(0, 12000)
    plt.tight_layout()
    plt.savefig(PREVIEWS / f"s03_{g}.png", dpi=70)
    plt.close()

manifest["verification"] = verif
total = round(sum(c["est_usd"] for c in manifest["paid_calls"]), 4)
manifest["cost"] = {"paid_calls": len(manifest["paid_calls"]), "est_total_usd": total,
                    "credits": sum(c["credits"] for c in manifest["paid_calls"])}
(ROOT / "pipeline" / "manifests" / "audio_s03.json").write_text(json.dumps(manifest, indent=1))
print(json.dumps(verif, indent=1))
print("paid calls:", manifest["cost"])
