"""Regenerates the whole Level 0 sound set.

    python pipeline/audio/build_level0.py

Procedural parts use fixed seeds. ElevenLabs outputs are cached in pipeline/audio/cache/ (keyed by a hash of
prompt + parameters) so re-runs cost nothing. Writes game/assets/audio/level0/*.wav (48 kHz, 16-bit),
pipeline/manifests/audio_level0.json and verification images in pipeline/audio/previews/.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np
import soundfile as sf
from scipy import signal

import l0_lib as L
import l0_procedural as P
from l0_lib import SR, OUT, PREVIEWS, ROOT

manifest = {"asset": "audio_level0", "engine_target": "Godot 4.7", "sample_rate": SR, "bit_depth": 16,
            "elevenlabs": {"model_id": L.EL_MODEL, "endpoint": "POST /v1/sound-generation",
                           "output_format_requested": "pcm_48000 (fallback mp3_44100_128 + resample)",
                           "doc_checked": "2026-10-01 elevenlabs.io/docs/api-reference/text-to-sound-effects/convert"},
            "files": {}, "paid_calls": []}
report = {}


def reg(name, **info):
    manifest["files"][name] = info


def paid(meta):
    manifest["paid_calls"].append({k: meta[k] for k in
                                   ("tag", "params", "file", "format", "credits", "est_usd", "http_attempts", "date")})


# ============================================================ 1. loops (procedural)
loops = {}
for v in ("a", "b"):
    x = P.hum(v)
    x = L.norm_lufs(x, -23.0)
    loops[f"hum_fixture_{v}.wav"] = x
    p = P.HUM_PARAMS[v]
    reg(f"hum_fixture_{v}.wav", method="procedural (integer-cycle sines + FFT-periodic noise)", seed=p["seed"],
        harmonics_hz_amp=p["harm"], buzz_level=p["buzz"], buzz_band_hz=p["buzz_band"],
        wobble_depth_cycles_per_8s=list(p["wobble"]), duration_s=8.0, channels=1, target_lufs=-23)

x = L.norm_lufs(P.failing_buzz(), -23.0)
loops["buzz_failing.wav"] = x
reg("buzz_failing.wav", method="procedural (120 Hz harmonic stack, gated HF sizzle, wrapped Poisson crackle)",
    seed=3003, duration_s=6.0, channels=1, target_lufs=-23)

x = L.norm_lufs(P.cam_motor(), -23.0)
loops["cam_motor_loop.wav"] = x
reg("cam_motor_loop.wav", method="procedural (motor harmonics, flutter, FM servo whine, periodic noise)",
    seed=5005, duration_s=4.0, channels=1, target_lufs=-23)

rt = P.room_tone()
rt = L.norm_lufs(rt, -23.0)
loops["room_tone.wav"] = rt
reg("room_tone.wav", method="procedural (FFT-periodic noise: shared 22-75 Hz rumble, 90-520 Hz HVAC, faint air; "
    "decorrelated stereo; whole-cycle slow breathing). ElevenLabs loop not used: procedural has zero events.",
    seed=4004, duration_s=30.0, channels=2, target_lufs=-23)

for name, x in loops.items():
    pk = L.peak_db(x)
    if pk > -1.0:  # pointwise soft limit keeps the seam exact
        x = L.softclip(x * 0.8, 1.0) * 1.0
        x = L.norm_lufs(x, -23.0)
        loops[name] = x
    L.write_wav(name, loops[name])

# ============================================================ 2. tube ticks (procedural)
ticks = [P.tube_tick(7100 + i) for i in range(1, 5)]
ticks = [L.norm_peak(t, -3.0) for t in ticks]
for i, t in enumerate(ticks, 1):
    L.write_wav(f"tube_tick_{i:02d}.wav", t)
    reg(f"tube_tick_{i:02d}.wav", method="procedural (inharmonic metallic modes + contact click + AM zap)",
        seed=7100 + i, channels=1, peak_dbfs=-3)

# ============================================================ 3. camcorder beep
beep = L.norm_peak(P.cam_beep(), -3.0)
L.write_wav("cam_rec_beep.wav", beep)
reg("cam_rec_beep.wav", method="procedural (2.8 kHz band-limited square + 5.6 kHz resonance, 140 ms)", channels=1,
    peak_dbfs=-3)


# ============================================================ 4. footsteps (ElevenLabs, sliced)
def envelope(x, ms=6):
    n = max(1, int(ms * SR / 1000))
    return np.convolve(np.abs(x), np.ones(n) / n, mode="same")


def slice_steps(x, min_gap=0.30, max_len=0.50):
    env = envelope(x)
    mx = env.max()
    pk, _ = signal.find_peaks(env, height=0.18 * mx, distance=int(min_gap * SR))
    cands = []
    for i, p in enumerate(pk):
        # walk back to onset: first point before peak where env drops under 12% of peak value
        lo = max(0, p - int(0.08 * SR))
        seg = env[lo:p]
        below = np.where(seg < 0.12 * env[p])[0]
        on = lo + (below[-1] if len(below) else 0)
        start = max(0, on - int(0.006 * SR))
        nxt = pk[i + 1] if i + 1 < len(pk) else len(x)
        nxt_on = nxt - int(0.05 * SR)
        end = min(start + int(max_len * SR), nxt_on, len(x))
        # tail trim: where env stays < 4% of peak
        tail = env[p:end]
        quiet = np.where(tail < 0.04 * env[p])[0]
        if len(quiet):
            end = p + quiet[0] + int(0.02 * SR)
        if end - start < int(0.12 * SR):
            continue
        pre = env[max(0, start - int(0.12 * SR)):start]
        iso = (pre.max() if len(pre) else 0) / env[p]
        cands.append(dict(start=start, end=end, peak_t=p / SR, iso=float(iso), pk=float(env[p])))
    return cands


def make_steps(tag, text, dur, influence, count, name_prefix, seed, takes):
    rng = np.random.default_rng(seed)
    pool = []
    for tk in range(takes):
        take_tag = f"{tag}_take{tk + 1}"
        txt = text if tk == 0 else text + " Slightly different gait."
        x, meta = L.eleven_sfx(take_tag, txt, dur, influence)
        paid(meta)
        for c in slice_steps(x):
            c["audio"] = x[c["start"]:c["end"]].copy()
            c["take"] = tk + 1
            pool.append(c)
    # prefer clean (isolated) slices, mid-level (not the loudest outliers)
    pool.sort(key=lambda c: c["iso"])
    keep = pool[: max(count, int(len(pool) * 0.8))]
    # choose `count` by spreading across takes/time; then order by take, time
    keep.sort(key=lambda c: (c["take"], c["peak_t"]))
    idx = np.linspace(0, len(keep) - 1, count).round().astype(int)
    sel = [keep[i] for i in idx]
    outs = []
    for k, c in enumerate(sel, 1):
        a = c["audio"]
        a = a - np.mean(a)
        # light pitch variation (+/-5 %) by resampling, deterministic
        r = float(rng.uniform(0.95, 1.05))
        a = signal.resample(a, int(len(a) / r))
        a = L.fade(a, 6, 35)
        a = L.norm_peak(a, -3.0)
        outs.append((f"{name_prefix}_{k:02d}.wav", a, dict(take=c["take"], src_start_s=round(c["start"] / SR, 3),
                                                            pitch_ratio=round(r, 3), length_s=round(len(a) / SR, 3))))
    return outs, len(pool)


STEP_BASE = ("Single person in sneakers walking at a slow steady pace on damp commercial office carpet, close "
             "microphone, no room echo, no other sounds, no voices, no music. ")
steps_damp, n_pool_d = make_steps(
    "steps_damp", STEP_BASE + "Each footstep is a soft muffled thud with a faint wet squish as the damp carpet "
    "compresses. Clean isolated footsteps with silence between them.", 10.0, 0.6, 8,
    "step_carpet_damp", 8101, takes=2)
steps_wet, n_pool_w = make_steps(
    "steps_wet", STEP_BASE + "The carpet is soaked: each footstep makes a noticeable wet squelch, squishing water "
    "out of the sodden carpet, with a soft heavy thud. Clean isolated footsteps with silence between them.",
    10.0, 0.6, 6, "step_carpet_wet", 8202, takes=2)
for outs, fam in ((steps_damp, "damp"), (steps_wet, "wet")):
    for name, a, info in outs:
        L.write_wav(name, a)
        reg(name, method="ElevenLabs sound effects walking take, onset-sliced, +/-5% pitch resample, fades 6/35 ms",
            channels=1, peak_dbfs=-3, **info)
report["step_pool"] = dict(damp=n_pool_d, wet=n_pool_w)

# ============================================================ 5. distant thuds (ElevenLabs + muffling)
THUD_PROMPTS = [
    "A single heavy object shifting and thudding on a concrete floor far away inside a large building, heard "
    "through several thick walls, extremely muffled, deep and low, a short faint rumble afterwards, no voices, "
    "no music, very quiet.",
    "Something very heavy being dragged a short distance then dropped, far away in an enormous empty building, "
    "heard through concrete walls, muffled and hollow, low frequency only, no voices, no music.",
    "A deep slow dull boom of a large heavy mass settling, distant, inside the walls of an abandoned office "
    "building, heavily muffled low thump with a faint creak, no voices, no music.",
]
thuds = []
for i, pr in enumerate(THUD_PROMPTS, 1):
    x, meta = L.eleven_sfx(f"thud_{i}", pr, 4.0, 0.55)
    paid(meta)
    x = L.butter(x, "low", 520, 4)            # walls eat everything above ~500 Hz
    x = L.butter(x, "high", 25, 2)
    env = envelope(x, 20)
    on = int(np.argmax(env > 0.05 * env.max()))
    start = max(0, on - int(0.03 * SR))
    # end where level has died away (below 3% for good), min 1 s, max 3.2 s
    after = env[start:]
    loud = np.where(after > 0.03 * after.max())[0]
    end = start + int(np.clip(loud[-1] + 0.15 * SR, 1.0 * SR, 3.2 * SR))
    a = x[start:end]
    a = L.fade(a, 25, 350)
    a = L.norm_peak(a, -3.0)
    L.write_wav(f"distant_thud_{i:02d}.wav", a)
    thuds.append(a)
    reg(f"distant_thud_{i:02d}.wav", method="ElevenLabs sound effects 4 s, then 4th-order lowpass 520 Hz + highpass "
        "25 Hz (wall muffling), trimmed, 25 ms fade in / 350 ms out", prompt=pr, channels=1, peak_dbfs=-3,
        length_s=round(len(a) / SR, 3))

# ============================================================ 6. verification
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

verif = {}
for name in loops:
    x, sr = sf.read(OUT / name, dtype="float64")
    assert sr == SR
    m = x if x.ndim == 1 else x
    mono = x if x.ndim == 1 else x[:, 0]
    chs = [x] if x.ndim == 1 else [x[:, 0], x[:, 1]]
    worst = 0.0
    for c in chs:
        jump = abs(c[0] - c[-1])
        typ = np.sqrt(np.mean(np.diff(c) ** 2))
        # also compare with the longer-run slope: predicted next sample vs actual first sample
        pred = c[-1] + (c[-1] - c[-2])
        worst = max(worst, abs(c[0] - pred) / max(typ, 1e-9))
    seconds = len(mono) / SR
    verif[name] = dict(seconds=round(seconds, 4), samples=len(mono), channels=1 if x.ndim == 1 else 2,
                       lufs=round(L.lufs(x), 2), peak_dbfs=round(L.peak_db(x), 2),
                       seam_jump_over_rms_step=round(float(worst), 2))
    # image: 40 ms either side of the seam, and 2 loops
    fig, ax = plt.subplots(2, 1, figsize=(12, 6))
    w = int(0.02 * SR)
    seam = np.concatenate([mono[-w:], mono[:w]])
    tt = (np.arange(2 * w) - w) / SR * 1000
    ax[0].plot(tt, seam, lw=0.8)
    ax[0].axvline(0, color="r", ls="--", lw=0.8)
    ax[0].set_title(f"{name}  seam at 0 ms (last 20 ms | first 20 ms), seam-step/typical-step = {worst:.2f}")
    two = np.concatenate([mono, mono])
    dec = max(1, len(two) // 6000)
    ax[1].plot(np.arange(0, len(two), dec) / SR, two[::dec], lw=0.5)
    ax[1].axvline(len(mono) / SR, color="r", ls="--", lw=0.8)
    ax[1].set_title("two consecutive repeats")
    plt.tight_layout()
    plt.savefig(PREVIEWS / f"seam_{name[:-4]}.png", dpi=80)
    plt.close()

# ---- per-family loudness equalisation: match integrated loudness to the family median, peaks capped at -3 dBFS
def equalise(prefix):
    fs = sorted(OUT.glob(f"{prefix}_*.wav"))
    data = [sf.read(f, dtype="float64")[0] for f in fs]
    ls = [L.lufs(d) for d in data]
    target = float(np.median(ls))
    for f, d, l in zip(fs, data, ls):
        g = 10 ** ((target - l) / 20)
        pk = L.peak_db(d) + 20 * np.log10(g)
        if pk > -3.0:
            g *= 10 ** ((-3.0 - pk) / 20)
        L.write_wav(f.name, d * g)
    return target


manifest["family_target_lufs"] = {}
for prefix in ("step_carpet_damp", "step_carpet_wet", "tube_tick", "distant_thud"):
    manifest["family_target_lufs"][prefix] = round(equalise(prefix), 2)

# one-shot families: loudness spread
fam = {}
for prefix in ("step_carpet_damp", "step_carpet_wet", "tube_tick", "distant_thud"):
    vals = []
    for f in sorted(OUT.glob(f"{prefix}_*.wav")):
        x, _ = sf.read(f, dtype="float64")
        vals.append(dict(file=f.name, ms=round(len(x) / SR * 1000), lufs=round(L.lufs(x), 1),
                         peak=round(L.peak_db(x), 1), first_sample=float(abs(x[0]))))
    fam[prefix] = vals

# contact sheet of one-shots
files = sorted(list(OUT.glob("step_carpet_*.wav")) + list(OUT.glob("tube_tick_*.wav"))
               + list(OUT.glob("distant_thud_*.wav")) + [OUT / "cam_rec_beep.wav"])
cols = 4
rows = int(np.ceil(len(files) / cols))
fig, axs = plt.subplots(rows, cols, figsize=(16, 2.0 * rows))
for ax, f in zip(axs.ravel(), files):
    x, _ = sf.read(f, dtype="float64")
    ax.plot(np.arange(len(x)) / SR * 1000, x, lw=0.5)
    ax.set_ylim(-1, 1)
    ax.set_title(f.stem, fontsize=8)
    ax.tick_params(labelsize=6)
for ax in axs.ravel()[len(files):]:
    ax.axis("off")
plt.tight_layout()
plt.savefig(PREVIEWS / "oneshots_sheet.png", dpi=80)
plt.close()

# spectrograms: room tone, hum a/b, failing buzz, a damp + wet step
specs = ["room_tone.wav", "hum_fixture_a.wav", "hum_fixture_b.wav", "buzz_failing.wav",
         "step_carpet_damp_01.wav", "step_carpet_wet_01.wav"]
fig, axs = plt.subplots(3, 2, figsize=(14, 9))
for ax, nm in zip(axs.ravel(), specs):
    x, _ = sf.read(OUT / nm, dtype="float64")
    x = x if x.ndim == 1 else x[:, 0]
    ax.specgram(x, NFFT=2048, Fs=SR, noverlap=1536, cmap="magma", vmin=-130, vmax=-30)
    ax.set_ylim(0, 8000 if "step" not in nm else 6000)
    ax.set_title(nm, fontsize=9)
plt.tight_layout()
plt.savefig(PREVIEWS / "spectrograms.png", dpi=80)
plt.close()

manifest["verification"] = {"loops": verif, "oneshot_families": fam, **report}
total = round(sum(c["est_usd"] for c in manifest["paid_calls"]), 4)
manifest["cost"] = {"paid_calls": len(manifest["paid_calls"]), "est_total_usd": total,
                    "note": "est_usd uses character-cost header credits x $0.0003/credit (conservative); "
                            "cached re-runs cost 0. Lead consolidates into docs/SPEND.md."}
(ROOT / "pipeline" / "manifests" / "audio_level0.json").write_text(json.dumps(manifest, indent=1))
print(json.dumps(manifest["verification"], indent=1))
print("paid calls:", len(manifest["paid_calls"]), "est USD:", total)
