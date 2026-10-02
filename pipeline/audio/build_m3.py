"""M3 sound additions for Level 0: player breathing loops, dread drone, distant one-shots, squishy soaked-carpet steps.

    python pipeline/audio/build_m3.py

ElevenLabs outputs are cached in pipeline/audio/cache/ (re-runs are free). Everything else is seeded/procedural.
Only ADDS new files to game/assets/audio/level0/. Writes pipeline/manifests/audio_m3.json and previews m3_*.png.
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
from l0_lib import SR, OUT, PREVIEWS, ROOT

def _decode_stereo_aware(path, fmt):
    """ElevenLabs pcm_48000 comes back as INTERLEAVED STEREO (2.0x the expected sample count). l0_lib._decode reads it as
    mono, which doubles the length and drops the pitch an octave. Fold the two channels properly here."""
    if fmt.startswith("pcm"):
        x = np.frombuffer(path.read_bytes(), dtype="<i2").astype(np.float64) / 32768
        return x[: len(x) // 2 * 2].reshape(-1, 2).mean(1)
    return _orig_decode(path, fmt)


_orig_decode = L._decode
L._decode = _decode_stereo_aware

manifest = {"asset": "audio_m3", "sample_rate": SR, "bit_depth": 16,
            "elevenlabs": {"model_id": L.EL_MODEL, "endpoint": "POST /v1/sound-generation"},
            "files": {}, "paid_calls": []}
SEAM = {}


def reg(name, **info):
    manifest["files"][name] = info


def paid(meta):
    manifest["paid_calls"].append({k: meta[k] for k in
                                   ("tag", "params", "file", "format", "credits", "est_usd", "http_attempts", "date")})


def envelope(x, ms=6):
    n = max(1, int(ms * SR / 1000))
    return np.convolve(np.abs(x), np.ones(n) / n, mode="same")


# ============================================================ breathing loops
def find_loop(x, lo_s, hi_s, xf_s=0.30):
    """Pick two breath-gap minima lo..hi seconds apart with matching level; return (loop array, info, cost)."""
    env = envelope(x, 120)
    env = env / (np.percentile(env, 90) + 1e-9)
    mn, _ = signal.find_peaks(-env, distance=int(0.35 * SR))
    mn = [m for m in mn if m > int(0.4 * SR) and m < len(x) - int((xf_s + 0.1) * SR)]
    thr = np.percentile(env, 55)
    mn = [m for m in mn if env[m] < thr]
    best = None
    xf = int(xf_s * SR)
    for i in mn:
        for j in mn:
            d = (j - i) / SR
            if d < lo_s or d > hi_s or j + xf > len(x):
                continue
            cost = abs(env[i] - env[j]) + 0.5 * (env[i] + env[j]) + 0.02 * abs(d - 0.5 * (lo_s + hi_s))
            if best is None or cost < best[0]:
                best = (cost, i, j)
    if best is None:
        return None, None, 1e9
    cost, i, j = best
    seg = x[i:j + xf].copy()
    n = j - i
    loop = seg[:n].copy()
    t = np.linspace(0, np.pi / 2, xf)
    loop[:xf] = loop[:xf] * np.sin(t) + seg[n:n + xf] * np.cos(t)   # equal-power crossfade of the tail onto the head
    return loop, dict(start_s=round(i / SR, 3), end_s=round(j / SR, 3), crossfade_s=xf_s), cost


def seam_report(name, x):
    typ = np.sqrt(np.mean(np.diff(x) ** 2))
    pred = x[-1] + (x[-1] - x[-2])
    step = float(abs(x[0] - pred) / typ)
    wd = int(0.5 * SR)
    both = np.concatenate([x[-wd:], x[:wd]])
    env = envelope(both, 50)
    SEAM[name] = dict(step_ratio=round(step, 2), env_at_seam_vs_rms=round(float(env[wd] / (np.sqrt(np.mean(x ** 2)) + 1e-9)), 2))
    fig, ax = plt.subplots(2, 1, figsize=(12, 6))
    ax[0].plot((np.arange(2 * wd) - wd) / SR, both, lw=0.5)
    ax[0].axvline(0, color="r", ls="--")
    ax[0].set_title(f"{name} seam: last 0.5 s | first 0.5 s, step ratio {step:.2f}")
    f, tt, S = signal.spectrogram(np.tile(x, 2), SR, nperseg=2048)
    ax[1].pcolormesh(tt, f, 10 * np.log10(S + 1e-14), shading="auto", vmin=-130, vmax=-40)
    ax[1].set_ylim(0, 8000)
    ax[1].axvline(len(x) / SR, color="r", ls="--")
    plt.tight_layout()
    plt.savefig(PREVIEWS / f"m3_seam_{name[:-4]}.png", dpi=75)
    plt.close()


COMMON = " Close microphone, intimate, completely dry with no room echo, no speech, no words, no voice, no music, no other sounds."
BREATHS = {
    "breath_calm_loop.wav": dict(
        txt="A person breathing very slowly and quietly at rest through the nose, soft gentle inhale then slow soft exhale with a calm pause between, steady and even, relaxed." + COMMON,
        dur=24.0, rng=(12.0, 16.0), lufs=-32.0, hp=90, lp=6000),
    "breath_heavy_loop.wav": dict(
        txt="A person winded and out of breath after sprinting, heavy fast mouth breathing, open-mouth panting with loud rasping inhales and exhales, no coughing." + COMMON,
        dur=16.0, rng=(8.0, 12.0), lufs=-26.0, hp=90, lp=9000),
    "breath_fear_loop.wav": dict(
        txt="A frightened person hiding and trying to stay silent, shaky trembling breathing, short shuddering inhales, breath held then released in unsteady quiet exhales, no whimpering, no crying." + COMMON,
        dur=22.0, rng=(10.0, 14.0), lufs=-28.0, hp=90, lp=8000),
}
for name, b in BREATHS.items():
    best = None
    for tk in (1, 2):
        txt = b["txt"] + ("" if tk == 1 else " Different rhythm.")
        x, meta = L.eleven_sfx(f"m3_{name[:-4]}_t{tk}", txt, b["dur"], 0.55)
        paid(meta)
        x = L.butter(x, "high", b["hp"], 4)
        x = L.butter(x, "low", b["lp"], 2)
        loop, info, cost = find_loop(x, *b["rng"])
        print(name, "take", tk, "cost", round(cost, 3), info)
        if loop is not None and (best is None or cost < best[0]):
            best = (cost, loop, info, tk, txt)
    assert best, f"no loop for {name}"
    cost, loop, info, tk, txt = best
    loop = L.norm_lufs(loop - loop.mean(), b["lufs"])
    L.write_wav(name, loop)
    seam_report(name, loop)
    reg(name, method="ElevenLabs take, high-pass/low-pass, loop cut between two breath-gap minima, 0.3 s equal-power crossfade",
        take=tk, prompt=txt, channels=1, target_lufs=b["lufs"], duration_s=round(len(loop) / SR, 3), **info)


# ============================================================ dread drone (procedural, periodic)
def drone(dur=24.0, seed=3030):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    # all frequencies and modulators are integer cycles per `dur`, so the loop is exactly periodic
    wow_ph = 0.0045 * np.sin(2 * np.pi * (19 / dur) * t + 0.8) + 0.0025 * np.sin(2 * np.pi * (53 / dur) * t + 2.1)

    def osc(k, amp, ph0, harm):
        f = k / dur
        y = np.zeros(n)
        for h, a in harm:
            y += a * np.sin(2 * np.pi * h * f * t + ph0 * h + h * 60 * wow_ph)
        return amp * y

    x = osc(990, 1.0, 0.3, ((1, 1.0), (2, 0.35), (3, 0.16), (5, 0.05)))      # 41.25 Hz
    x += osc(998, 0.9, 1.9, ((1, 1.0), (2, 0.30), (3, 0.14), (5, 0.04)))     # 41.58 Hz, beats 0.33 Hz
    x += osc(1486, 0.28, 0.7, ((1, 1.0), (2, 0.2)))                          # 61.9 Hz
    x += osc(1498, 0.26, 4.0, ((1, 1.0), (2, 0.2)))                          # 62.4 Hz, beats 0.5 Hz
    x *= 1 + 0.12 * np.sin(2 * np.pi * (2 / dur) * t + 1.0) + 0.05 * np.sin(2 * np.pi * (7 / dur) * t + 0.2)
    x = x / np.sqrt(np.mean(x ** 2))
    air = L.pnoise(n, L.band(120, 1800, 12), rng) * (0.05 + 0.025 * np.sin(2 * np.pi * (3 / dur) * t + 0.4))
    hiss = L.pnoise(n, L.band(2500, 9000, 6), rng) * 0.006
    x = x + air + hiss
    x = L.softclip(x / np.max(np.abs(x)), 1.4)
    return L.butter(np.tile(x, 3), "low", 900, 2)[n:2 * n]      # filter a 3x tile, keep the middle: stays periodic


d = drone()
d = L.norm_lufs(d - d.mean(), -30.0)
L.write_wav("drone_dread_loop.wav", d)
seam_report("drone_dread_loop.wav", d)
reg("drone_dread_loop.wav", method="procedural: two detuned ~41.25 Hz harmonic oscillators beating at 0.33 Hz, a quieter pair near 62 Hz "
    "beating 0.5 Hz, tape wow as periodic phase modulation (0.79 Hz and 2.2 Hz), slow level breathing, FFT-periodic dark air, soft clip, "
    "900 Hz lowpass; all integer cycles per 24 s so the loop is exact", seed=3030, duration_s=24.0, channels=1, target_lufs=-30)


# ============================================================ distant one-shots
def reverb_ir(rt, seed, lp=2500):
    rng = np.random.default_rng(seed)
    n = int(rt * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-6.9 * t / rt)
    ir = L.butter(ir, "low", lp, 2)
    ir[:int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    return ir / np.sqrt(np.sum(ir ** 2))


FAR = " Heard from far away through several walls in an empty building: very muffled, distant, quiet, with long dull room reverb. No voices, no music."
DISTANT = {
    "distant_door_01.wav": ("A heavy office door closing with a solid dull thud and latch click, one time, in another part of a large empty building." + FAR, 4.0),
    "distant_chair_01.wav": ("An office chair with plastic wheels rolling a short way across a hard floor then stopping, in another room." + FAR, 4.0),
    "distant_ballast_01.wav": ("A fluorescent light ballast buzzing and humming up with a stuttering electrical buzz, then cutting out abruptly to silence." + FAR, 4.0),
    "distant_steps_01.wav": ("Three or four slow heavy footsteps on soaked wet carpet, slow irregular pace, then silence." + FAR, 5.0),
    "distant_knock_01.wav": ("Two dull knocks from inside a wall, slow, hollow, like knuckles on drywall, then silence." + FAR, 3.0),
    "distant_hum_drop_01.wav": ("The steady electrical hum of a large fluorescent lighting system suddenly dropping out with a soft low electrical thunk, then near silence." + FAR, 4.0),
}
for name, (txt, dur) in DISTANT.items():
    x, meta = L.eleven_sfx(f"m3_{name[:-4]}", txt, dur, 0.55)
    paid(meta)
    x = L.butter(x, "high", 50, 2)
    y = L.butter(x, "low", 1800, 4)                                   # through walls
    wet = np.convolve(y, reverb_ir(2.0, seed=zlib.crc32(name.encode()) % 1000), mode="full")[:len(y) + int(1.2 * SR)]
    dry = np.concatenate([y, np.zeros(len(wet) - len(y))])
    z = L.butter(0.55 * dry + 0.9 * wet, "low", 2200, 2)
    env = envelope(z, 30)
    act = np.where(env > 0.04 * env.max())[0]
    s = max(0, act[0] - int(0.05 * SR))
    e = min(len(z), act[-1] + int(0.15 * SR))
    z = z[s:e][:int(4.8 * SR)]
    if len(z) < int(1.6 * SR):
        z = np.concatenate([z, np.zeros(int(1.6 * SR) - len(z))])
    z = L.fade(z, 8, 450)
    z = L.norm_lufs(z - z.mean(), -30.0)
    L.write_wav(name, z)
    reg(name, method="ElevenLabs take, 1.8 kHz 4th-order lowpass (through walls), synthetic 2 s reverb IR convolved, trimmed to activity, "
        "8 ms in / 450 ms out", prompt=txt, channels=1, target_lufs=-30, duration_s=round(len(z) / SR, 3))


# ============================================================ soaked carpet squish steps
def slice_steps(x, min_gap=0.40, max_len=0.65):
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
            end = p + quiet[0] + int(0.04 * SR)
        if end - start < int(0.25 * SR):
            end = min(start + int(0.30 * SR), len(x))
            if end - start < int(0.25 * SR):
                continue
        pre = env[max(0, start - int(0.12 * SR)):start]
        iso = (pre.max() if len(pre) else 0) / env[p]
        cands.append(dict(start=start, end=end, peak_t=p / SR, iso=float(iso)))
    return cands


def eq_notch_box(a):
    """Cut the 150-400 Hz box: -4 dB peaking at 260 Hz, wide."""
    f0, q, g = 260.0, 0.7, -4.0
    A = 10 ** (g / 40)
    w0 = 2 * np.pi * f0 / SR
    al = np.sin(w0) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w0), 1 - al * A]
    aa = [1 + al / A, -2 * np.cos(w0), 1 - al / A]
    return signal.lfilter(b, aa, a)


SQ = ("Close-miked footsteps of one person in soft rubber-soled sneakers walking slowly on soaked, waterlogged thick office carpet. "
      "Each step is a soft muffled thump with a loud wet squelch and squish as water squeezes out of the sodden pile, then a small suck "
      "as the foot lifts. No heel click, no wooden knock, no hollow boom. Dry room, no echo, no voices, no music. Silence between steps.")
VARS = ("", " Slightly heavier steps.", " Lighter steps, more squishing water.", " Very wet, long squelch.",
        " Slower pace.", " Steady medium pace.")
pool = []
for tk in range(6):
    x, meta = L.eleven_sfx(f"m3_squish_t{tk + 1}", SQ + VARS[tk], 10.0, 0.6)
    paid(meta)
    x = L.butter(x, "high", 60, 4)
    for c in slice_steps(x):
        a_ = x[c["start"]:c["end"]]
        fq, pw = signal.welch(a_, SR, nperseg=min(len(a_), 2048))
        pw = pw / pw.sum()
        crest = np.abs(a_).max() / np.sqrt(np.mean(a_ ** 2))
        cen = (fq * pw).sum()
        if pw[fq < 100].sum() > 0.35 or crest > 13 or cen < 150:
            continue
        e2 = a_ ** 2
        compact = e2[:int(0.22 * SR)].sum() / e2.sum()
        en = envelope(a_, 8)
        later = en[int(0.18 * SR):].max() / en.max() if len(en) > int(0.2 * SR) else 0
        if compact < 0.65 or later > 0.45 or crest < 4.5:
            continue
        hf = pw[(fq > 1500) & (fq < 6000)].sum()      # squelch/water content
        c.update(audio=a_.copy(), take=tk + 1, cen=float(cen), hf=float(hf),
                 score=2 * compact + 6 * hf - 3 * c["iso"] - abs(cen - 1100) / 700)
        pool.append(c)
print("squish pool", len(pool))
pool.sort(key=lambda c: -c["score"])
chosen, takes_used = [], {}
for c in pool:                                   # spread across takes where possible
    if takes_used.get(c["take"], 0) >= 2 and len(pool) > 12:
        continue
    chosen.append(c)
    takes_used[c["take"]] = takes_used.get(c["take"], 0) + 1
    if len(chosen) == 8:
        break
chosen.sort(key=lambda c: (c["take"], c["peak_t"]))
assert len(chosen) == 8, f"only {len(chosen)} usable squish steps"
rng = np.random.default_rng(1303)
squish_names = []
for k, c in enumerate(chosen, 1):
    a = c["audio"] - np.mean(c["audio"])
    r = float(rng.uniform(0.96, 1.04))
    a = signal.resample(a, int(len(a) / r))
    a = eq_notch_box(a)
    a = L.butter(a, "low", 9000, 2)
    a = L.fade(a, 8, 25)
    a = L.norm_lufs(a, -26.0)
    if L.peak_db(a) > -3.0:                      # peak over budget: bring the peak down (loudness then lands a touch lower)
        a = L.norm_peak(a, -3.0)
    name = f"step_carpet_squish_{k:02d}.wav"
    L.write_wav(name, a)
    squish_names.append(name)
    reg(name, method="ElevenLabs soaked-carpet take, 60 Hz high-pass, onset slice (squelch-weighted selection), +/-4% pitch, "
        "-4 dB at 260 Hz (box cut, no body boost), 9 kHz lowpass, 8 ms in / 25 ms out, -26 LUFS", channels=1, take=c["take"],
        src_start_s=round(c["start"] / SR, 3), pitch_ratio=round(r, 3), length_s=round(len(a) / SR, 3),
        spectral_centroid_hz=round(c["cen"]), target_lufs=-26)


# ============================================================ verification and previews
verif = {}
for name in sorted(manifest["files"]):
    x, sr = sf.read(OUT / name, dtype="float64")
    assert sr == SR and x.ndim == 1, name
    verif[name] = dict(seconds=round(len(x) / SR, 3), lufs=round(L.lufs(x), 2), peak_dbfs=round(L.peak_db(x), 2))
    if name in SEAM:
        verif[name]["seam"] = SEAM[name]

groups = {"breath": [n for n in verif if n.startswith("breath")] + ["drone_dread_loop.wav"],
          "distant": [n for n in verif if n.startswith("distant")],
          "squish": squish_names}
for g, names in groups.items():
    fig, axs = plt.subplots(len(names), 2, figsize=(14, 1.8 * len(names)), squeeze=False)
    for i, name in enumerate(names):
        x, _ = sf.read(OUT / name, dtype="float64")
        axs[i][0].plot(np.arange(len(x)) / SR, x, lw=0.4)
        axs[i][0].set_ylim(-1, 1)
        axs[i][0].set_title(f"{name}  {verif[name]['lufs']} LUFS, pk {verif[name]['peak_dbfs']}", fontsize=8)
        f, tt, S = signal.spectrogram(x, SR, nperseg=1024, noverlap=768)
        axs[i][1].pcolormesh(tt, f, 10 * np.log10(S + 1e-14), shading="auto", vmin=-130, vmax=-30)
        axs[i][1].set_ylim(0, 12000 if g != "breath" else 8000)
    plt.tight_layout()
    plt.savefig(PREVIEWS / f"m3_{g}.png", dpi=70)
    plt.close()

manifest["verification"] = verif
manifest["cost"] = {"paid_calls": len(manifest["paid_calls"]),
                    "est_total_usd": round(sum(c["est_usd"] for c in manifest["paid_calls"]), 4),
                    "credits": sum(c["credits"] for c in manifest["paid_calls"])}
(ROOT / "pipeline" / "manifests" / "audio_m3.json").write_text(json.dumps(manifest, indent=1))
print(json.dumps(verif, indent=1))
print("paid:", manifest["cost"])
