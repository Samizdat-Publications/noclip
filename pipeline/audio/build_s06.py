"""S06 sound set: the Occupant (steps, rustle, tears, breath, shriek), chase drone, kill tape, body drag, VCR replay, peeks, wall knock.

    python pipeline/audio/build_s06.py

ElevenLabs outputs are cached in pipeline/audio/cache/ (re-runs are free). Writes game/assets/audio/entity/*.wav,
pipeline/manifests/audio_s06.json and previews pipeline/audio/previews/s06_*.png.
"""
import json
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundfile as sf
from scipy import signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

import l0_lib as L
from l0_lib import SR, PREVIEWS, ROOT

OUT = ROOT / "game" / "assets" / "audio" / "entity"
OUT.mkdir(parents=True, exist_ok=True)


def _decode_stereo_aware(path, fmt):
    """ElevenLabs pcm_48000 is INTERLEAVED STEREO; fold both channels (see build_m3.py)."""
    if fmt.startswith("pcm"):
        x = np.frombuffer(path.read_bytes(), dtype="<i2").astype(np.float64) / 32768
        return x[: len(x) // 2 * 2].reshape(-1, 2).mean(1)
    return _orig_decode(path, fmt)


_orig_decode = L._decode
L._decode = _decode_stereo_aware

manifest = {"asset": "audio_s06", "sample_rate": SR, "bit_depth": 16,
            "elevenlabs": {"model_id": L.EL_MODEL, "endpoint": "POST /v1/sound-generation"},
            "files": {}, "paid_calls": []}
SEAM = {}
SEEN = set()


def paid(meta):
    if meta["tag"] in SEEN:
        return
    SEEN.add(meta["tag"])
    manifest["paid_calls"].append({k: meta[k] for k in
                                   ("tag", "params", "file", "format", "credits", "est_usd", "http_attempts", "date")})


def gen(tag, text, dur, infl=0.5, loop=False):
    x, meta = L.eleven_sfx(f"s06_{tag}", text, dur, infl, loop)
    paid(meta)
    return x


# ---------------------------------------------------------------- helpers
def envelope(x, ms=6):
    n = max(1, int(ms * SR / 1000))
    return np.maximum(signal.fftconvolve(np.abs(x), np.ones(n) / n, mode="same"), 0)


def norm_iter(x, target, iters=8):
    x = L.norm_peak(x, -12.0)
    for _ in range(iters):
        x = L.norm_lufs(x, target)
        if abs(L.lufs(x) - target) < 0.05:
            break
    return x


def trim_lead(x, thresh=0.04, back_ms=8):
    env = envelope(x, 5)
    idx = np.where(env > thresh * env.max())[0]
    s = max(0, (idx[0] if len(idx) else 0) - int(back_ms * SR / 1000))
    return x[s:]


def spec_centroid(x):
    f, p = signal.welch(x, SR, nperseg=min(len(x), 4096))
    return float((f * p).sum() / (p.sum() + 1e-18))


def make_loop(x, target_s, xf_s=0.35, skip_s=0.15):
    """Cut target_s from x and equal-power crossfade the following xf_s of source onto the head: seamless loop."""
    n = int(target_s * SR)
    xf = int(xf_s * SR)
    s = int(skip_s * SR)
    assert len(x) >= s + n + xf, (len(x) / SR, target_s)
    # choose the window with the steadiest level (a take can contain a dropout; a loop must not)
    env = envelope(x, 100)
    best = None
    for st in range(s, len(x) - n - xf + 1, int(0.1 * SR)):
        w = env[st:st + n + xf]
        sc = np.percentile(w, 2) / (np.median(w) + 1e-9)
        if best is None or sc > best[0]:
            best = (sc, st)
    s = best[1]
    seg = x[s:s + n + xf].copy()
    loop = seg[:n].copy()
    t = np.linspace(0, np.pi / 2, xf)
    loop[:xf] = loop[:xf] * np.sin(t) + seg[n:n + xf] * np.cos(t)
    return loop - loop.mean()


def circ_vibrato(x, rate_cycles, depth_ms, phase=0.0, rate2=None, depth2_ms=0.0):
    """Tape warble: periodic (integer cycles over the clip) delay modulation, so a loop stays a loop."""
    n = len(x)
    t = np.arange(n) / n
    d = depth_ms * SR / 1000 * np.sin(2 * np.pi * rate_cycles * t + phase)
    if rate2:
        d += depth2_ms * SR / 1000 * np.sin(2 * np.pi * rate2 * t + 1.3)
    pos = np.arange(n) + d
    i0 = np.floor(pos).astype(int)
    fr = pos - i0
    return x[i0 % n] * (1 - fr) + x[(i0 + 1) % n] * fr


def vibrato(x, rate_hz, depth_ms, phase=0.0):
    n = len(x)
    pos = np.clip(np.arange(n) + depth_ms * SR / 1000 * np.sin(2 * np.pi * rate_hz * np.arange(n) / SR + phase), 0, n - 1.001)
    i0 = pos.astype(int)
    fr = pos - i0
    return x[i0] * (1 - fr) + x[i0 + 1] * fr


def slow(x, ratio):
    """Play at `ratio` speed (<1 slower and lower)."""
    return signal.resample(x, int(len(x) / ratio))


def reverb_ir(rt, seed, lp=2500):
    rng = np.random.default_rng(seed)
    n = int(rt * SR)
    t = np.arange(n) / SR
    ir = L.butter(rng.standard_normal(n) * np.exp(-6.9 * t / rt), "low", lp, 2)
    ir[:int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    return ir / np.sqrt(np.sum(ir ** 2))


def slice_events(x, min_gap, min_len, max_len, pre_ms=10, height=0.2, end_frac=0.06):
    env = envelope(x, 8)
    mx = env.max()
    pk, _ = signal.find_peaks(env, height=height * mx, distance=int(min_gap * SR))
    out = []
    for i, p in enumerate(pk):
        lo = max(0, p - int(0.12 * SR))
        below = np.where(env[lo:p] < 0.12 * env[p])[0]
        on = lo + (below[-1] if len(below) else 0)
        s = max(0, on - int(pre_ms * SR / 1000))
        nxt = pk[i + 1] if i + 1 < len(pk) else len(x)
        end = min(s + int(max_len * SR), nxt - int(0.06 * SR), len(x))
        q = np.where(env[p:end] < end_frac * env[p])[0]
        if len(q):
            end = p + q[0] + int(0.03 * SR)
        end = max(end, s + int(min_len * SR))
        end = min(end, len(x))
        if end - s < int(min_len * 0.8 * SR):
            continue
        pre = env[max(0, s - int(0.15 * SR)):s]
        iso = float((pre.max() if len(pre) else 0) / env[p])
        out.append(dict(start=s, end=end, peak=float(env[p] / mx), iso=iso, audio=x[s:end].copy()))
    return out


def pick(cands, n):
    """Best n by loudness-relative strength and isolation, spread across takes, returned in take order."""
    cands = sorted(cands, key=lambda c: -(c["peak"] - 1.5 * c["iso"]))
    chosen, per = [], {}
    for c in cands:
        if per.get(c["take"], 0) >= (n + 1) // 2 + 1 and len(cands) > 2 * n:
            continue
        chosen.append(c)
        per[c["take"]] = per.get(c["take"], 0) + 1
        if len(chosen) == n:
            break
    assert len(chosen) == n, f"only {len(chosen)} of {n} usable"
    return sorted(chosen, key=lambda c: (c["take"], c["start"]))


def emit(name, x, target, fin_ms=6, fout_ms=40, loop=False, **info):
    x = x - x.mean()
    if not loop:
        x = L.fade(x, fin_ms, fout_ms)
    x = norm_iter(x, target)
    for _ in range(10):                                  # peaks never above -1 dBFS: soft-limit, re-level
        if L.peak_db(x) <= -1.0:
            break
        th = 10 ** (-3.0 / 20)
        x = np.tanh(x / th) * th
        x = norm_iter(x, target)
        if L.peak_db(x) > -1.0 and target > -20:
            break
    note = ""
    if L.peak_db(x) > -1.0:
        x = L.norm_peak(x, -1.2)
        note = f"peak-limited, loudness fell to {L.lufs(x):.1f} LUFS"
    if loop:
        typ = np.sqrt(np.mean(np.diff(x) ** 2))
        pred = x[-1] + (x[-1] - x[-2])
        SEAM[name] = round(float(abs(x[0] - pred) / typ), 2)
    L.write_wav(name, x) if False else sf.write(OUT / name, np.clip(x, -1, 1).astype(np.float32), SR, subtype="PCM_16")
    manifest["files"][name] = dict(channels=1, target_lufs=target, duration_s=round(len(x) / SR, 3),
                                   spectral_centroid_hz=round(spec_centroid(x)), note=note, **info)
    print(f"{name:24s} {len(x)/SR:5.2f}s  {L.lufs(x):6.1f} LUFS  pk {L.peak_db(x):5.1f}  cen {spec_centroid(x):5.0f}  {note}")
    return x


NOSAY = " No speech, no music."
CLOSE = " Close microphone, dry, no room echo." + NOSAY
STEP_LUFS = L.lufs(sf.read(ROOT / "game/assets/audio/level0/step_carpet_soggy_01.wav", dtype="float64")[0])
print("player step reference LUFS", round(STEP_LUFS, 2))


# ============================================================ 1. occ_step_01..06
txt = ("A series of single slow barefoot steps on soaking wet carpet, each one a loud wet slap of flesh on sodden carpet "
       "followed by a long squelching squish as water is squeezed out. Wet, splashy and bright, with a heavy weight behind it. "
       "About two seconds of silence between each step." + CLOSE)
cands = []
for tk in (1, 2, 3):
    x = L.butter(gen(f"occ_step_v2_t{tk}", txt + ("" if tk == 1 else " Slightly slower." if tk == 2 else " Heavier, wetter squelch." if tk == 3 else " Louder splashy squelch."), 12.0, 0.6), "high", 50, 4)
    for c in slice_events(x, 0.9, 0.7, 1.0, height=0.25):
        fq, pw = signal.welch(c["audio"], SR, nperseg=2048)
        pw = pw / pw.sum()
        if pw[fq < 150].sum() > 0.6 or pw[(fq > 400) & (fq < 6000)].sum() < 0.25:   # skip sub-only thumps without squelch
            continue
        c["take"] = tk
        cands.append(c)
print("occ_step pool", len(cands))
for k, c in enumerate(pick(cands, 6), 1):
    a = c["audio"][:int(0.95 * SR)]
    a = slow(a, 0.82)                       # heavier and lower: something large
    a = L.butter(a, "low", 8000, 2)
    a = a[:int(1.0 * SR)]
    a = np.concatenate([a, np.zeros(max(0, int(0.8 * SR) - len(a)))])
    emit(f"occ_step_{k:02d}.wav", a, STEP_LUFS, 6, 200, method="ElevenLabs take sliced at onsets (sub-only thumps rejected), 50 Hz HP, slowed to 0.82x for weight, 8 kHz LP",
         take=c["take"], src_start_s=round(c["start"] / SR, 3), prompt=txt)

# ============================================================ 2. occ_rustle_loop
txt = "Loose strips of old dry wallpaper rustling and fluttering softly in a slow draft, dry paper crinkle, continuous, steady." + CLOSE
x = L.butter(gen("occ_rustle", txt, 8.0, 0.55, loop=True), "high", 120, 2)
emit("occ_rustle_loop.wav", make_loop(x, 6.0, 0.4), -24.0, loop=True, method="ElevenLabs loop take, 120 Hz HP, 0.4 s equal-power crossfade loop cut", prompt=txt)

# ============================================================ 3. occ_tear_01..04
txt = ("A series of separate short sharp tears of old brittle wallpaper, a strip of paper ripped off a wall, each one a quick rrrip. "
       "About one second of silence between each tear." + CLOSE)
cands = []
for tk in (1, 2):
    x = L.butter(gen(f"occ_tear_t{tk}", txt + ("" if tk == 1 else " Faster, harsher rips."), 8.0, 0.6), "high", 150, 2)
    for c in slice_events(x, 0.5, 0.4, 0.8, pre_ms=5, height=0.25):
        c["take"] = tk
        cands.append(c)
print("occ_tear pool", len(cands))
for k, c in enumerate(pick(cands, 4), 1):
    emit(f"occ_tear_{k:02d}.wav", c["audio"][:int(0.8 * SR)], -20.0, 3, 60, method="ElevenLabs take sliced at onsets, 150 Hz HP",
         take=c["take"], src_start_s=round(c["start"] / SR, 3), prompt=txt)

# ============================================================ 4. occ_breath_01..02 (reversed + slowed inhale)
txt = "A slow, deep, wet inhale through an open throat, a long wet rasping breath in, close, unsettling." + CLOSE
for k in (1, 2):
    x = gen(f"occ_breath_t{k}", txt + ("" if k == 1 else " Even deeper and wetter."), 3.0, 0.55)
    x = trim_lead(L.butter(x, "high", 60, 2), 0.05)
    x = slow(x[::-1], 0.8)
    x = L.butter(x, "low", 5500, 2)
    x = trim_lead(x, 0.05)
    x = x[:int(2.0 * SR)]
    emit(f"occ_breath_{k:02d}.wav", x, -24.0, 60, 350, method="ElevenLabs inhale, reversed, slowed to 0.8x (pitch and speed), 5.5 kHz LP, cut to 2 s", prompt=txt)

# ============================================================ 5. chase_drone_loop
txt = ("A low rising distorted synthesizer drone, dark and gritty, horror chase tension, one sustained evolving pad, no melody, no drums, no voice.")
raw = gen("chase_drone", txt, 12.0, 0.5, loop=True)
d = make_loop(L.butter(raw, "high", 25, 2), 8.0, 0.6)
d = circ_vibrato(d, 5, 0.9, 0.3, rate2=17, depth2_ms=0.25)                       # tape warble, integer cycles per 8 s
d = L.softclip(d / np.max(np.abs(d)), 2.2)
hb = np.zeros(len(d))
for b in range(10):                                                              # 75 bpm, double thump, exactly 10 beats in 8 s
    for off, amp in ((0.0, 1.0), (0.24, 0.65)):
        tt = np.arange(int(0.45 * SR)) / SR
        th = np.sin(2 * np.pi * (42 * tt + 18 * (1 - np.exp(-tt * 14)) / 14 * 0 + 0) * 1.0 + 0) * 0  # placeholder replaced below
        f = 62 * np.exp(-tt * 5.5) + 34
        ph = 2 * np.pi * np.cumsum(f) / SR
        th = np.sin(ph) * np.exp(-tt * 9) * amp
        L.circ_conv_add(hb, int((b * 0.8 + off) * SR), th)
d = d / np.sqrt(np.mean(d ** 2)) + 1.1 * hb / np.sqrt(np.mean(hb ** 2))
d = L.butter(np.tile(d, 3), "low", 7000, 2)[len(d):2 * len(d)]
d = d * (1 + 0.15 * np.sin(2 * np.pi * np.arange(len(d)) / len(d)))             # one slow swell per loop
emit("chase_drone_loop.wav", d, -24.0, loop=True, method="ElevenLabs loop take + loop cut, circular tape warble (5 and 17 cycles/8 s), soft clip, procedural 75 bpm sub heartbeat added (periodic)", prompt=txt, seed=None)

# ============================================================ 6. occ_shriek_01..02
txt = "A loud distorted human scream, raw terrifying shriek, a single sustained scream."
for k in (1, 2):
    x = gen(f"occ_shriek_t{k}", txt + ("" if k == 1 else " Higher pitched, more strained."), 3.0, 0.6)
    x = trim_lead(L.butter(x, "high", 120, 2), 0.05)
    x = slow(x[::-1], 0.75)
    x = vibrato(x, 5.5 + k, 3.0, 0.4)                                            # damaged tape wow
    x = vibrato(x, 0.9, 9.0, 1.1)
    rng = np.random.default_rng(600 + k)
    t = np.arange(len(x)) / SR
    gate = np.ones(len(x))
    pos = 0
    while pos < len(x):                                                          # chopped: random dropouts
        ln = int(rng.uniform(0.04, 0.16) * SR)
        if rng.random() < 0.35:
            gate[pos:pos + ln] = rng.uniform(0.0, 0.25)
        pos += ln
    gate = signal.fftconvolve(gate, np.ones(int(0.004 * SR)) / int(0.004 * SR), mode="same")
    hiss = L.butter(rng.standard_normal(len(x)), "band", 0, 1) if False else L.butter(rng.standard_normal(len(x)), "high", 3000, 2)
    x = x * gate + 0.01 * np.abs(x).max() * hiss * (1 - gate * 0.5)
    x = L.butter(L.butter(x, "high", 250, 2), "low", 5200, 4)
    x = x[:int(2.8 * SR)]
    emit(f"occ_shriek_{k:02d}.wav", x, -16.0, 20, 500, method="ElevenLabs scream, reversed, 0.75x slow, tape wow vibrato, random dropout chopping, 250 Hz-5.2 kHz band limit", prompt=txt)

# ============================================================ 7. kill_tape_01
txt = ("A VHS tape mechanism jamming in a VCR: a loud crunching mechanical chew as the tape is chewed and snapped, a high squeal, "
       "then abrupt dead silence.")
x = trim_lead(gen("kill_tape", txt, 2.5, 0.6), 0.05)
x = x[:int(1.5 * SR)]
x = np.concatenate([x, np.zeros(int(1.5 * SR) - len(x))])
e = envelope(x, 20)
last = np.where(e > 0.15 * e.max())[0][-1]
cut = min(last + int(0.06 * SR), len(x) - int(0.12 * SR))
x[cut:] = 0
x[max(0, cut - int(0.05 * SR)):cut] *= np.linspace(1, 0, min(int(0.05 * SR), cut))
emit("kill_tape_01.wav", x, -16.0, 3, 0, method="ElevenLabs take, trimmed to 1.5 s, hard-gated to dead silence after the last event", prompt=txt)
# emit applied a fade out of 0 ms which is a no-op; trailing region is exact zeros.

# ============================================================ 8. body_drag_01..02
txt = ("A heavy human body in a plastic coverall dragged very fast across wet carpet, loud plastic and fabric scraping and squelching, "
       "rushing past and moving away into the distance.")
for k in (1, 2):
    x = trim_lead(gen(f"body_drag_t{k}", txt + ("" if k == 1 else " Faster, more plastic crackle."), 2.5, 0.55), 0.05)
    x = x[:int(1.8 * SR)]
    g = np.linspace(0, 1, len(x)) ** 1.2
    far = L.butter(L.butter(x, "low", 1400, 2), "low", 1400, 2)
    x = (x * (1 - g) + far * g) * (1.0 - 0.85 * g)                               # moving away: dulls and fades
    emit(f"body_drag_{k:02d}.wav", x, -20.0, 5, 450, method="ElevenLabs take, trimmed to 1.8 s, progressive lowpass + level fall (moving away)", prompt=txt)

# ============================================================ 9. body_thud_01
txt = "A single heavy muffled thump of a heavy body hitting a wall in the next room, dull deep impact, then silence."
x = trim_lead(gen("body_thud", txt, 2.0, 0.6), 0.05)
x = L.butter(x, "low", 700, 4)
x = x[:int(1.0 * SR)]
x = np.concatenate([x, np.zeros(max(0, int(1.0 * SR) - len(x)))])
emit("body_thud_01.wav", x, -18.0, 2, 350, method="ElevenLabs take, 700 Hz LP (through a wall), cut to 1 s", prompt=txt)

# ============================================================ 10. vcr_rewind_loop
txt = "A 1990s VCR fast-rewinding a videotape, high whirring electric motor whine, mechanical whir, faint tape hiss, steady and continuous." + NOSAY
x = gen("vcr_rewind", txt, 4.5, 0.55, loop=True)
emit("vcr_rewind_loop.wav", make_loop(L.butter(x, "high", 80, 2), 3.0, 0.4), -24.0, loop=True, method="ElevenLabs loop take, 80 Hz HP, 0.4 s crossfade loop cut", prompt=txt)

# ============================================================ 11. vcr_play_01
txt = "A VCR play button being pressed: a mechanical clunk, tape heads engaging with a click, then a soft motor starting up and humming." + NOSAY
x = trim_lead(gen("vcr_play", txt, 2.0, 0.55), 0.05)[:int(1.5 * SR)]
emit("vcr_play_01.wav", x, -22.0, 3, 250, method="ElevenLabs take trimmed to 1.5 s", prompt=txt)

# ============================================================ 12. vcr_eject_01
txt = "A VHS cassette being ejected from a VCR: a plastic clunk, a spring release and the cassette popping out." + NOSAY
x = trim_lead(gen("vcr_eject", txt, 2.0, 0.55), 0.05)[:int(1.2 * SR)]
emit("vcr_eject_01.wav", x, -22.0, 3, 200, method="ElevenLabs take trimmed to 1.2 s", prompt=txt)

# ============================================================ 13. peek_rustle_01..03
txt = ("A series of soft quick rustles of dry paper, as something slides and pulls back out of sight around a corner, each rustle brief and gentle. "
       "About one second of silence between each.") + CLOSE
cands = []
for tk in (1, 2):
    x = L.butter(gen(f"peek_rustle_t{tk}", txt + ("" if tk == 1 else " Quieter, softer."), 6.0, 0.55), "high", 150, 2)
    for c in slice_events(x, 0.6, 0.5, 0.8, pre_ms=10, height=0.2):
        c["take"] = tk
        cands.append(c)
print("peek pool", len(cands))
for k, c in enumerate(pick(cands, 3), 1):
    emit(f"peek_rustle_{k:02d}.wav", c["audio"][:int(0.8 * SR)], -28.0, 8, 150, method="ElevenLabs take sliced at onsets, 150 Hz HP",
         take=c["take"], src_start_s=round(c["start"] / SR, 3), prompt=txt)

# ============================================================ 14. distant_drag_01
txt = ("Something very heavy dragged slowly across carpet in another room, a long low scraping drag, heard far away through walls, muffled." + NOSAY)
x = L.butter(gen("distant_drag", txt, 4.0, 0.55), "high", 50, 2)
y = L.butter(x, "low", 1500, 4)
wet = np.convolve(y, reverb_ir(1.6, zlib.crc32(b"distant_drag") % 1000), mode="full")[:len(y)]
z = L.butter(0.6 * y + 0.8 * wet, "low", 1800, 2)[:int(3.0 * SR)]
emit("distant_drag_01.wav", z, -30.0, 60, 500, method="ElevenLabs take, 1.5 kHz LP, synthetic 1.6 s reverb, 3 s cut", prompt=txt)

# ============================================================ 15. wall_knock_01
txt = "Three slow hollow knocks from inside a wall, like knuckles on drywall, evenly spaced about half a second apart, then silence." + NOSAY
txt = "Three quick hollow knocks in a row from inside a wall, knock, knock, knock, about half a second between each, like knuckles on drywall." + NOSAY
x = trim_lead(L.butter(gen("wall_knock_v2", txt, 3.0, 0.85), "high", 60, 2), 0.05)
x = L.butter(x, "low", 2500, 2)[:int(2.0 * SR)]
x = np.concatenate([x, np.zeros(max(0, int(2.0 * SR) - len(x)))])
emit("wall_knock_01.wav", x, -26.0, 2, 300, method="ElevenLabs take, 60 Hz HP, 2.5 kHz LP, cut to 2 s", prompt=txt)

# ============================================================ 16. tape_static_loop
txt = "VHS videotape noise: blank tape hiss with a low electrical hum, as on a TV tuned to a blank VCR channel. Steady, continuous, no music."
x = gen("tape_static", txt, 5.5, 0.5, loop=True)
s = make_loop(L.butter(x, "high", 40, 2), 4.0, 0.5)
t = np.arange(len(s)) / SR
hum = 0.04 * np.sin(2 * np.pi * 60 * t) + 0.02 * np.sin(2 * np.pi * 120 * t + 0.7)  # 60 Hz is 240 whole cycles in 4 s: periodic
s = s / np.sqrt(np.mean(s ** 2)) + hum / np.sqrt(np.mean(hum ** 2)) * 0.35
emit("tape_static_loop.wav", s, -24.0, loop=True, method="ElevenLabs loop take + loop cut, plus procedural 60/120 Hz hum (periodic)", prompt=txt)

# ============================================================ verification and previews
verif = {}
names = sorted(manifest["files"])
for name in names:
    x, sr = sf.read(OUT / name, dtype="float64")
    assert sr == SR and x.ndim == 1, name
    verif[name] = dict(seconds=round(len(x) / SR, 3), lufs=round(L.lufs(x), 2), peak_dbfs=round(L.peak_db(x), 2),
                       centroid_hz=round(spec_centroid(x)))
    if name in SEAM:
        verif[name]["seam_step_ratio"] = SEAM[name]
    assert verif[name]["peak_dbfs"] <= -0.95, name

ncol = 4
nrow = -(-len(names) // ncol)
fig = plt.figure(figsize=(18, 2.3 * nrow))
gs = fig.add_gridspec(nrow, ncol, hspace=0.55, wspace=0.18)
for i, name in enumerate(names):
    x, _ = sf.read(OUT / name, dtype="float64")
    sub = gs[i // ncol, i % ncol].subgridspec(2, 1, hspace=0.05)
    a0 = fig.add_subplot(sub[0])
    a0.plot(np.arange(len(x)) / SR, x, lw=0.3)
    a0.set_ylim(-1, 1)
    a0.set_xticks([])
    a0.set_yticks([])
    a0.set_title(f"{name[:-4]} {verif[name]['seconds']}s {verif[name]['lufs']}LU", fontsize=7)
    a1 = fig.add_subplot(sub[1])
    f, tt, S = signal.spectrogram(x, SR, nperseg=1024, noverlap=768)
    a1.pcolormesh(tt, f, 10 * np.log10(S + 1e-14), shading="auto", vmin=-130, vmax=-30)
    a1.set_ylim(0, 10000)
    a1.tick_params(labelsize=5)
sheet = PREVIEWS / "s06_sheet.png"
fig.savefig(sheet, dpi=60, bbox_inches="tight")
plt.close(fig)

manifest["verification"] = verif
manifest["notes"] = ["Player step reference (step_carpet_soggy_01) LUFS: %.2f; occ_step_* target matched to it." % STEP_LUFS,
                     "Loops are cut from longer ElevenLabs takes with an equal-power crossfade; seam step ratio ~1 means no click.",
                     "ElevenLabs pcm_48000 is interleaved stereo and is folded to mono (as in build_m3.py)."]
manifest["cost"] = {"paid_calls": len(manifest["paid_calls"]),
                    "est_total_usd": round(sum(c["est_usd"] for c in manifest["paid_calls"]), 4),
                    "credits": sum(c["credits"] for c in manifest["paid_calls"])}
(ROOT / "pipeline" / "manifests" / "audio_s06.json").write_text(json.dumps(manifest, indent=1))
print(json.dumps(verif, indent=1))
print("paid:", manifest["cost"])
