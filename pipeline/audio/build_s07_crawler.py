"""S07 crawler sound set (the huge pale crawling creature: palms, drag, breath, joints, tears, flinch, grab, lunge).

    python pipeline/audio/build_s07_crawler.py

Re-runnable: ElevenLabs takes are cached in pipeline/audio/cache/ (no re-pay) and outputs that already exist are skipped.
Writes game/assets/audio/descent/*.wav, game/assets/audio/halden/*.wav (48 kHz 16-bit mono), pipeline/manifests/audio_s07_crawler.json
and the preview sheet pipeline/audio/previews/s07_sheet.png. A failed check (duration within 20 percent of target, raw peak
above -30 dBFS, no clipping) triggers ONE retake with a different tag and prompt_influence.
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
from l0_lib import SR, PREVIEWS, ROOT

AUD = ROOT / "game" / "assets" / "audio"
MAN = ROOT / "pipeline" / "manifests" / "audio_s07_crawler.json"
NOSAY = " No roar, no growl, no voice, no words, no music."

SPECS = [
    ("crawler", 'crw_step_01', 0.7, False, -20, 'a single heavy bare palm slapping down flat on soaked carpet, then a dull knee thud, a huge person crawling, wet and deliberate, close. A slap.'),
    ("crawler", 'crw_step_02', 0.7, False, -20, 'a single heavy bare palm slapping down flat on soaked carpet, then a dull knee thud, a huge person crawling, wet and deliberate, close. A slap then a thud.'),
    ("crawler", 'crw_step_03', 0.7, False, -20, 'a single heavy bare palm slapping down flat on soaked carpet, then a dull knee thud, a huge person crawling, wet and deliberate, close. A knuckle drag.'),
    ("crawler", 'crw_step_04', 0.7, False, -20, 'a single heavy bare palm slapping down flat on soaked carpet, then a dull knee thud, a huge person crawling, wet and deliberate, close. Heavier.'),
    ("crawler", 'crw_step_05', 0.7, False, -20, 'a single heavy bare palm slapping down flat on soaked carpet, then a dull knee thud, a huge person crawling, wet and deliberate, close. Slower, wetter slap.'),
    ("crawler", 'crw_step_06', 0.7, False, -20, 'a single heavy bare palm slapping down flat on soaked carpet, then a dull knee thud, a huge person crawling, wet and deliberate, close. Heavy slap-thud, deeper.'),
    ("crawler", 'crw_drag_loop', 6.0, True, -26, 'slow continuous sound of bare skin dragging and squeaking along wallpapered walls and wet carpet, something huge crawling slowly, faint creaks of joints'),
    ("crawler", 'crw_breath_01', 3.0, False, -26, 'very slow deep breathing through the nose like someone asleep, huge chest, close and intimate, faint wet whistle'),
    ("crawler", 'crw_breath_02', 3.0, False, -26, 'very slow deep breathing through the nose like someone asleep, huge chest, close and intimate, faint wet whistle'),
    ("crawler", 'crw_notice_01', 1.8, False, -18, 'a sudden sharp deep intake of breath followed by a rapid series of loud joint cracks and knuckle pops, like a huge body tensing to pounce'),
    ("crawler", 'crw_notice_02', 1.8, False, -18, 'a sudden sharp deep intake of breath followed by a rapid series of loud joint cracks and knuckle pops, like a huge body tensing to pounce'),
    ("crawler", 'crw_tear_01', 1.2, False, -20, 'wallpaper and drywall plaster tearing and crumbling as something huge squeezes past, short.'),
    ("crawler", 'crw_tear_02', 1.2, False, -20, 'wallpaper and drywall plaster tearing and crumbling as something huge squeezes past, short. Mostly plaster crumbling.'),
    ("crawler", 'crw_tear_03', 1.2, False, -20, 'wallpaper and drywall plaster tearing and crumbling as something huge squeezes past, short. Mostly wallpaper ripping.'),
    ("crawler", 'crw_tear_04', 1.2, False, -20, 'wallpaper and drywall plaster tearing and crumbling as something huge squeezes past, short. A heavy crack and crumble.'),
    ("crawler", 'crw_flashed_01', 1.5, False, -18, 'a huge creature flinching from a bright flash: a startled wet gasp and a heavy body thumping back against a wall, no voice'),
    ("crawler", 'crw_flashed_02', 1.5, False, -18, 'a huge creature flinching from a bright flash: a startled wet gasp and a heavy body thumping back against a wall, no voice'),
    ("crawler", 'crw_grab_01', 2.5, False, -18, 'a huge hand clamping down hard on a person, fabric and body crushed, a heavy wet slap and a long slow exhale close to the microphone'),
    ("crawler", 'crw_lunge_01', 1.2, False, -18, 'a sudden heavy scrambling burst across wet carpet, palms slapping fast, a body sliding'),
]

manifest = {"asset": "audio_s07_crawler", "sample_rate": SR, "bit_depth": 16, "channels": 1,
            "elevenlabs": {"model_id": L.EL_MODEL, "endpoint": "POST /v1/sound-generation"},
            "files": {}, "paid_calls": [], "failed": []}
SEEN = set()


def paid(meta):
    if meta["tag"] in SEEN:
        return
    SEEN.add(meta["tag"])
    manifest["paid_calls"].append({k: meta[k] for k in
                                   ("tag", "params", "file", "format", "credits", "est_usd", "http_attempts", "date")})


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


def make_loop(x, target_s, xf_s=0.4, skip_s=0.15):
    n, xf, s = int(target_s * SR), int(xf_s * SR), int(skip_s * SR)
    assert len(x) >= s + n + xf, (len(x) / SR, target_s)
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


def checks(raw, final, target_s):
    pk = float(L.peak_db(raw))
    dur = len(final) / SR
    out = dict(raw_peak_dbfs=round(float(pk), 1), duration_s=round(dur, 3),
               clip_samples=int(np.sum(np.abs(raw) >= 0.999)))
    out["ok_duration"] = bool(abs(dur - target_s) <= 0.2 * target_s)
    out["ok_not_silent"] = bool(pk > -30.0)
    out["ok_no_clip"] = out["clip_samples"] < 3
    out["ok"] = out["ok_duration"] and out["ok_not_silent"] and out["ok_no_clip"]
    return out


def produce(folder, name, secs, loop, target, prompt, attempt):
    tag = f"s07c_{name}" + ("" if attempt == 1 else f"_r{attempt}")
    # identical prompts for _01/_02 variants must differ: the tag (and cache hash via influence) separate the takes
    infl = 0.5 + (0.1 if attempt == 2 else 0.0) + (0.05 if name.endswith("_02") else 0.0)
    req = secs + (2.0 if loop else 0.0)
    text = prompt + ("" if "no music" in prompt.lower() else NOSAY)
    if name.endswith("_02") and attempt == 1:
        text += " Slight variation."
    x, meta = L.eleven_sfx(tag, text, req, infl, loop)
    paid(meta)
    raw = x.copy()
    n = int(secs * SR)
    if loop:
        y = make_loop(L.butter(x, "high", 40, 2), secs)
    else:
        y = x[:n]
        if len(y) < n * 0.8:
            pass
    return raw, y, text, infl, tag


def finalize(y, target, loop):
    y = y - y.mean()
    if not loop:
        y = L.fade(y, 3, 60)
    y = norm_iter(y, target)
    for _ in range(10):
        if L.peak_db(y) <= -1.0:
            break
        th = 10 ** (-3.0 / 20)
        y = np.tanh(y / th) * th
        y = norm_iter(y, target)
    if L.peak_db(y) > -1.0:
        y = L.norm_peak(y, -1.2)
    return y


for folder, name, secs, loop, target, prompt in SPECS:
    out_dir = AUD / folder
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{name}.wav"
    if path.exists():
        print("skip (exists)", folder, name)
        info = sf.info(path)
        manifest["files"][f"{folder}/{name}.wav"] = dict(prompt=prompt, duration_s=round(info.duration, 3), loop=loop,
                                                          target_lufs=target, note="existed, not regenerated")
        continue
    result = None
    for attempt in (1, 2):
        raw, y, text, infl, tag = produce(folder, name, secs, loop, target, prompt, attempt)
        ck = checks(raw, y, secs)
        print(f"{name:20s} try {attempt} {ck}")
        result = (y, text, infl, tag, ck, attempt)
        if ck["ok"]:
            break
    y, text, infl, tag, ck, attempt = result
    if not ck["ok"]:
        manifest["failed"].append(dict(name=name, checks=ck))
    y = finalize(y, target, loop)
    sf.write(path, np.clip(y, -1, 1).astype(np.float32), SR, subtype="PCM_16")
    manifest["files"][f"{folder}/{name}.wav"] = dict(
        prompt=text, duration_s=round(len(y) / SR, 3), target_duration_s=secs, loop=loop, target_lufs=target,
        final_lufs=round(float(L.lufs(y)), 2), final_peak_dbfs=round(float(L.peak_db(y)), 2),
        prompt_influence=infl, model_id=L.EL_MODEL, cache_tag=tag, attempts=attempt, checks=ck,
        method="ElevenLabs take" + (", 40 Hz HP, 0.4 s equal-power crossfade loop cut" if loop else ", trimmed to target, 3 ms/60 ms fades")
               + ", loudness-normalised, peaks under -1 dBFS")
    print(f"  wrote {folder}/{name}.wav {len(y)/SR:.2f}s {L.lufs(y):.1f} LUFS pk {L.peak_db(y):.1f}")

# ------------------------------------------------------------ preview sheet
files = sorted(manifest["files"])
ncol = 4
nrow = -(-len(files) // ncol)
fig = plt.figure(figsize=(18, 2.3 * nrow))
gs = fig.add_gridspec(nrow, ncol, hspace=0.55, wspace=0.18)
for i, rel in enumerate(files):
    x, _ = sf.read(AUD / rel, dtype="float64")
    sub = gs[i // ncol, i % ncol].subgridspec(2, 1, hspace=0.05)
    a0 = fig.add_subplot(sub[0])
    a0.plot(np.arange(len(x)) / SR, x, lw=0.3)
    a0.set_ylim(-1, 1)
    a0.set_xticks([])
    a0.set_yticks([])
    a0.set_title(f"{rel[:-4]} {len(x)/SR:.1f}s {L.lufs(x):.0f}LU", fontsize=7)
    a1 = fig.add_subplot(sub[1])
    f, tt, S = signal.spectrogram(x, SR, nperseg=1024, noverlap=768)
    a1.pcolormesh(tt, f, 10 * np.log10(S + 1e-14), shading="auto", vmin=-130, vmax=-30)
    a1.set_ylim(0, 10000)
    a1.tick_params(labelsize=5)
sheet = PREVIEWS / "s07_crawler_sheet.png"
fig.savefig(sheet, dpi=60, bbox_inches="tight")
plt.close(fig)

manifest["cost"] = {"paid_calls": len(manifest["paid_calls"]),
                    "est_total_usd": round(sum(c["est_usd"] for c in manifest["paid_calls"]), 4),
                    "credits": sum(c["credits"] for c in manifest["paid_calls"])}
if MAN.exists():  # a re-run that skipped everything must not wipe the recorded paid calls
    old = json.loads(MAN.read_text())
    have = {c["tag"] for c in manifest["paid_calls"]}
    manifest["paid_calls"] += [c for c in old.get("paid_calls", []) if c["tag"] not in have]
    for k, v in old.get("files", {}).items():
        if manifest["files"].get(k, {}).get("note") == "existed, not regenerated":
            manifest["files"][k] = v
    manifest["cost"] = {"paid_calls": len(manifest["paid_calls"]),
                        "est_total_usd": round(sum(c["est_usd"] for c in manifest["paid_calls"]), 4),
                        "credits": sum(c["credits"] for c in manifest["paid_calls"])}
MAN.write_text(json.dumps(manifest, indent=1))
print("failed:", manifest["failed"])
print("paid:", manifest["cost"])
print("sheet:", sheet)
