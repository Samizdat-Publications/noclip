"""Look-dev renders for the builder (NOT for the critic): renders the fixed poses in
game/data/focus_level0.json and tiles them into one contact image.

Usage: python tools/lookdev.py OUT_DIR [--seed N] [--extra key=value ...]
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
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--seed", default="1234")
    ap.add_argument("--focus", default="res://data/focus_level0.json")
    ap.add_argument("--extra", nargs="*", default=[])
    ap.add_argument("--cols", type=int, default=2)
    ap.add_argument("--label", default="lookdev", help="progress picture label")
    ap.add_argument("--note", default="", help="progress picture note (what changed)")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    for f in glob.glob(os.path.join(out, "focus", "*.png")):
        os.remove(f)
    cmd = [paths.godot(), "--path", paths.GAME, "--resolution", "2560x1440", "--",
           f"--seed={a.seed}", f"--capture={out}", "--duration=0.5", "--stills=0", "--sheets=0",
           f"--focus={a.focus}"] + [f"--{e}" for e in a.extra]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    errs = [l for l in (r.stdout + r.stderr).splitlines() if "ERROR" in l or "SCRIPT" in l or "WARNING" in l]
    for l in errs[:30]:
        print(l)
    shots = sorted(glob.glob(os.path.join(out, "focus", "f_*.png")))
    if not shots:
        sys.exit("no shots rendered")
    w, h = 1280, 720
    cols = a.cols
    rows = (len(shots) + cols - 1) // cols
    sheet = Image.new("RGB", (w * cols, h * rows))
    for i, s in enumerate(shots):
        im = Image.open(s).convert("RGB")
        sheet.paste(im.resize((w, h), Image.LANCZOS), ((i % cols) * w, (i // cols) * h))
    sheet.save(os.path.join(out, "lookdev.jpg"), quality=88)
    progress.save(sheet, a.label, a.note or ("look-dev poses " + " ".join(a.extra)).strip())
    print("sizes:", Image.open(shots[0]).size, "shots:", len(shots), "->", os.path.join(out, "lookdev.jpg"))


if __name__ == "__main__":
    main()
