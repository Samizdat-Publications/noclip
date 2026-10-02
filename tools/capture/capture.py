"""One-command review capture.

    python tools/capture/capture.py            (random seed, logged)
    python tools/capture/capture.py --seed 4242 --duration 95

What it does:
 1. Picks a random seed (or uses --seed) and a build id.
 2. Imports assets (headless).
 3. Movie Maker run of the real game at 2560x1440 / 30 fps with game audio: the autoplay
    bot plays; the game saves stills and 9-frame motion bursts at seeded moments; after
    the bot run it takes a few focus shots (at most 25% of the frames).
 4. A separate realtime run measures performance (perf.json).
 5. Wipes review/inbox and refills it with neutral names only:
       frames/frame_NN.png, sheets/sheet_NN.png, video/clip.mp4, perf.json, store_page.md,
       previous/ (frames from the last reviewed build, unlabeled)
 6. Archives the build locally (review/archive/builds/<id>/, git-ignored) and writes a
    small committed contact sheet (review/archive/thumbs/<id>.jpg).
"""
import argparse
import datetime as dt
import glob
import json
import os
import random
import shutil
import subprocess
import sys
import time

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import paths  # noqa: E402
import progress  # noqa: E402

ROOT = paths.ROOT
REVIEW = os.path.join(ROOT, "review")
INBOX = os.path.join(REVIEW, "inbox")
ARCH = os.path.join(REVIEW, "archive", "builds")
THUMBS = os.path.join(REVIEW, "archive", "thumbs")
RAW = os.path.join(REVIEW, "archive", "raw")


def log(*a):
    print("[capture]", *a, flush=True)


def run(cmd, timeout, label):
    t = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace")
    out = (r.stdout or "") + (r.stderr or "")
    bad = [l for l in out.splitlines() if ("SCRIPT ERROR" in l or "ERROR:" in l) and "leaked" not in l and "still in use" not in l]
    log(f"{label}: exit {r.returncode} in {time.time() - t:.0f}s" + (f", {len(bad)} error lines" if bad else ""))
    for l in bad[:15]:
        log("   ", l.strip())
    return r, out


def git_hash():
    try:
        return subprocess.check_output(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], text=True).strip()
    except Exception:
        return "nogit"


def sheet_from(files, out, w=2560, h=1440):
    cw, ch = w // 3, h // 3
    img = Image.new("RGB", (w, h), (0, 0, 0))
    for i, f in enumerate(files[:9]):
        im = Image.open(f).convert("RGB").resize((cw, ch), Image.LANCZOS)
        img.paste(im, ((i % 3) * cw, (i // 3) * ch))
    img.save(out)


def contact(files, out, cols=5, w=512, h=288):
    rows = (len(files) + cols - 1) // cols
    img = Image.new("RGB", (cols * w, rows * h))
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB").resize((w, h), Image.LANCZOS)
        img.paste(im, ((i % cols) * w, (i // cols) * h))
    img.save(out, quality=85)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--duration", type=float, default=120.0)
    ap.add_argument("--stills", type=int, default=16)
    ap.add_argument("--sheets", type=int, default=4)
    ap.add_argument("--focus", default="auto",
                    help="focus shot list (res:// path), or 'auto' to let the level pick its landmarks; max 25%% of frames are used")
    ap.add_argument("--perf-seconds", type=float, default=40.0)
    ap.add_argument("--skip-perf", action="store_true")
    ap.add_argument("--extra", nargs="*", default=[], help="extra game args, e.g. preset=medium")
    ap.add_argument("--label", default="review-build", help="progress picture label")
    ap.add_argument("--note", default="", help="progress picture note")
    a = ap.parse_args()

    seed = a.seed if a.seed is not None else random.SystemRandom().randint(1, 999999)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    build_id = f"{stamp}-{git_hash()}"
    raw = os.path.join(RAW, build_id)
    os.makedirs(raw, exist_ok=True)
    log(f"build {build_id} seed {seed}")
    extra = [f"--{e}" for e in a.extra]

    # 1. Import.
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "import_presets.py")], check=True)
    run([paths.godot(), "--headless", "--path", paths.GAME, "--import"], 600, "import")

    # 2. Movie Maker run (deterministic, with audio).
    focus_path = a.focus
    focus_local = os.path.join(paths.GAME, focus_path.replace("res://", "")) if focus_path.startswith("res://") else focus_path
    n_focus = 0
    if focus_path == "auto":
        n_focus = a.stills // 3
    elif os.path.exists(focus_local):
        shots = json.load(open(focus_local, encoding="utf-8"))
        n_focus = min(len(shots), a.stills // 3)  # focus <= 25% of all frames
        if n_focus < len(shots):
            rnd = random.Random(seed)
            shots = rnd.sample(shots, n_focus)
            trimmed = os.path.join(raw, "focus.json")
            json.dump(shots, open(trimmed, "w", encoding="utf-8"))
            focus_path = trimmed.replace("\\", "/")
    movie = os.path.join(raw, "movie.avi")
    frames_total = int((a.duration + 3.0 * n_focus + 4.0) * 30)
    cmd = [paths.godot(), "--path", paths.GAME, "--resolution", "2560x1440", "--write-movie", movie,
           "--fixed-fps", "30", "--disable-vsync", "--quit-after", str(frames_total), "--",
           f"--seed={seed}", f"--capture={raw}", f"--duration={a.duration}", f"--stills={a.stills}",
           f"--sheets={a.sheets}"] + ([f"--focus={focus_path}", f"--focus_n={n_focus}"] if n_focus else []) + extra
    r, out = run(cmd, 3600, "movie run")
    open(os.path.join(raw, "movie_log.txt"), "w", encoding="utf-8").write(out)
    stills = sorted(glob.glob(os.path.join(raw, "stills", "s_*.png")))
    focus = sorted(glob.glob(os.path.join(raw, "focus", "f_*.png")))
    if not stills or not os.path.exists(movie):
        sys.exit("capture failed: no stills or no movie (see movie_log.txt)")

    # 3. Realtime perf run.
    perf = os.path.join(raw, "perf.json")
    if not a.skip_perf:
        perf_extra = [e for e in extra if not e.startswith(("--track", "--dump-scene"))]
        cmd = [paths.godot(), "--path", paths.GAME, "--resolution", "2560x1440", "--",
               f"--seed={seed}", f"--perf={perf}", f"--duration={a.perf_seconds + 6.0}"] + perf_extra
        run(cmd, 600, "perf run")

    # 4. Video: trim to the bot run, H.264 + AAC.
    clip = os.path.join(raw, "clip.mp4")
    ff = paths.ffmpeg()
    subprocess.run([ff, "-y", "-loglevel", "error", "-i", movie, "-t", f"{a.duration:.2f}",
                    "-vf", "scale=1920:1080:flags=lanczos", "-c:v", "libx264", "-preset", "slow", "-crf", "19",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", clip], check=True)
    loud = subprocess.run([ff, "-hide_banner", "-nostats", "-i", clip, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"],
                          capture_output=True, text=True, encoding="utf-8", errors="replace").stderr
    lufs = [l.strip() for l in loud.splitlines() if l.strip().startswith(("I:", "Peak:"))]
    log("audio loudness:", " / ".join(lufs[-2:]))

    # 5. Inbox (neutral names only).
    if os.path.exists(INBOX):
        shutil.rmtree(INBOX)
    for d in ("frames", "sheets", "video"):
        os.makedirs(os.path.join(INBOX, d))
    # Interleave focus shots among the gameplay stills at seeded positions.
    order = list(stills)
    rnd = random.Random(seed * 7 + 1)
    for f in focus:
        order.insert(rnd.randint(1, len(order)), f)
    for i, f in enumerate(order):
        shutil.copy(f, os.path.join(INBOX, "frames", f"frame_{i + 1:02d}.png"))
    bursts = sorted({os.path.basename(p)[:3] for p in glob.glob(os.path.join(raw, "sheets", "k*_f*.png"))})
    for i, k in enumerate(bursts):
        fs = sorted(glob.glob(os.path.join(raw, "sheets", f"{k}_f*.png")))
        if len(fs) == 9:
            sheet_from(fs, os.path.join(INBOX, "sheets", f"sheet_{i + 1:02d}.png"))
    shutil.copy(clip, os.path.join(INBOX, "video", "clip.mp4"))
    if os.path.exists(perf):
        shutil.copy(perf, os.path.join(INBOX, "perf.json"))
    shutil.copy(os.path.join(REVIEW, "store_page.md"), os.path.join(INBOX, "store_page.md"))
    prev_builds = sorted(d for d in glob.glob(os.path.join(ARCH, "*")) if os.path.isdir(d))
    if prev_builds:
        pf = sorted(glob.glob(os.path.join(prev_builds[-1], "frames", "*.png")))
        if pf:
            os.makedirs(os.path.join(INBOX, "previous"))
            step = max(1, len(pf) // 6)
            for i, f in enumerate(pf[::step][:6]):
                shutil.copy(f, os.path.join(INBOX, "previous", f"prev_{i + 1:02d}.png"))

    # 6. Archive.
    arch = os.path.join(ARCH, build_id)
    shutil.copytree(os.path.join(INBOX, "frames"), os.path.join(arch, "frames"))
    shutil.copytree(os.path.join(INBOX, "sheets"), os.path.join(arch, "sheets"))
    if os.path.exists(perf):
        shutil.copy(perf, arch)
    os.makedirs(THUMBS, exist_ok=True)
    contact(sorted(glob.glob(os.path.join(arch, "frames", "*.png"))), os.path.join(THUMBS, f"{build_id}.jpg"))
    progress.save(Image.open(os.path.join(THUMBS, f"{build_id}.jpg")), f"{a.label}-frames",
                  (a.note + " | " if a.note else "") + f"all review frames, build {build_id}, seed {seed}")
    sheets_now = sorted(glob.glob(os.path.join(arch, "sheets", "*.png")))
    if sheets_now:
        progress.save(progress.grid(sheets_now), f"{a.label}-motion-sheets", f"motion sheets (3x3, 0.4 s apart), build {build_id}")
    meta = {"build_id": build_id, "seed": seed, "git": git_hash(), "date": stamp, "duration": a.duration,
            "stills": len(stills), "focus": len(focus), "sheets": len(bursts), "audio": lufs[-2:], "extra": a.extra}
    json.dump(meta, open(os.path.join(arch, "meta.json"), "w", encoding="utf-8"), indent=2)
    # Raw movie is large; keep only the last two raw folders.
    raws = sorted(d for d in glob.glob(os.path.join(RAW, "*")) if os.path.isdir(d))
    for d in raws[:-2]:
        shutil.rmtree(d, ignore_errors=True)
    for f in glob.glob(os.path.join(raw, "*.avi")):
        os.remove(f)
    perf_txt = open(perf).read() if os.path.exists(perf) else "{}"
    log("perf:", json.dumps({k: v for k, v in json.loads(perf_txt).items() if k in ("avg_fps", "low_1pct_fps", "p99_frame_ms", "resolution", "gpu")}))
    log(f"inbox ready: {len(order)} frames, {len(bursts)} sheets, clip {os.path.getsize(clip) / 1e6:.1f} MB")
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
