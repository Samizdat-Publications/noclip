"""Builder-only filmed checks (NOT for the critic): records a short Movie Maker run of the real
game and pulls frames at chosen times into one contact sheet.

    python tools/film.py OUT_DIR --frames 600 --times 3.5,5,10 [--res 1280x720] [--label L --note N]
        -- --seed=4242 --route=east --route-stay --route-cam=1.5-7 --tape-always

Everything after `--` goes to the game. Prints game log lines matching --grep.
"""
import argparse
import glob
import os
import subprocess
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import paths  # noqa: E402
import progress  # noqa: E402


def main():
    argv = sys.argv[1:]
    game_args = []
    if "--" in argv:
        i = argv.index("--")
        argv, game_args = argv[:i], argv[i + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--frames", type=int, default=600)
    ap.add_argument("--times", default="")
    ap.add_argument("--res", default="1280x720")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--grep", default=r"\[tape\]|\[loop\]|\[seam\]|SCRIPT ERROR")
    ap.add_argument("--label", default="")
    ap.add_argument("--note", default="")
    ap.add_argument("--keep", action="store_true", help="keep the AVI")
    a = ap.parse_args(argv)
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    for f in glob.glob(os.path.join(out, "t_*.png")):
        os.remove(f)
    avi = os.path.join(out, "film.avi")
    if os.path.exists(avi):
        os.remove(avi)
    cmd = [paths.godot(), "--path", paths.GAME, "--resolution", a.res, "--write-movie", avi, "--fixed-fps", "30",
           "--disable-vsync", "--quit-after", str(a.frames), "--"] + game_args
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=3600)
    import re
    pat = re.compile(a.grep)
    for l in (r.stdout + r.stderr).splitlines():
        if pat.search(l):
            print(l)
    times = [float(t) for t in a.times.split(",") if t.strip()]
    ff = paths.ffmpeg()
    shots = []
    for t in times:
        f = os.path.join(out, f"t_{t:07.2f}.png")
        subprocess.run([ff, "-loglevel", "error", "-y", "-ss", f"{t:.3f}", "-i", avi, "-frames:v", "1", f], check=False)
        if os.path.exists(f):
            shots.append(f)
    if shots:
        w, h = Image.open(shots[0]).size
        tw, th = 640, int(640 * h / w)
        rows = (len(shots) + a.cols - 1) // a.cols
        sheet = Image.new("RGB", (tw * a.cols, th * rows))
        for i, f in enumerate(shots):
            sheet.paste(Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS), ((i % a.cols) * tw, (i // a.cols) * th))
        sp = os.path.join(out, "sheet.png")
        sheet.save(sp)
        print("sheet:", sp)
        if a.label:
            progress.save(sheet, a.label, a.note or f"filmed check at t={a.times}")
    if not a.keep and os.path.exists(avi):
        os.remove(avi)


if __name__ == "__main__":
    main()
