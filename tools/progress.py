"""Progress pictures: a permanent visual record of development (Stewart's rule, 2026-10-01).

Every time a PNG is generated (look-dev renders, captures, critic packets, previews), a copy
goes into progress/ with a running number so the history sorts in order:

    progress/0001_2026-10-01_1830_s01_first-autoplay-stills.jpg

and a line is added to progress/INDEX.md (number, date, session, what it shows, git commit).
Copies are high-quality JPEG at full resolution to keep the repo light.

Usage:
    python tools/progress.py SRC.png "short-label" [--note "what it shows"] [--session 1] [--when "2026-10-01 18:30"]
    python tools/progress.py --grid OUT_LABEL SRC1.png SRC2.png ... [--note ...]   (tiles several into one)
"""
import argparse
import datetime as dt
import glob
import os
import re
import subprocess

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PROG = os.path.join(ROOT, "progress")
INDEX = os.path.join(PROG, "INDEX.md")
DEFAULT_SESSION = 1


def _next_number():
    nums = [int(m.group(1)) for f in glob.glob(os.path.join(PROG, "*.jpg")) if (m := re.match(r"(\d{4})_", os.path.basename(f)))]
    return max(nums, default=0) + 1


def _slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:60]


def _git():
    try:
        return subprocess.check_output(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "-"


def save(img, label, note="", session=DEFAULT_SESSION, when=None):
    os.makedirs(PROG, exist_ok=True)
    t = dt.datetime.strptime(when, "%Y-%m-%d %H:%M") if when else dt.datetime.now()
    n = _next_number()
    name = f"{n:04d}_{t:%Y-%m-%d_%H%M}_s{session:02d}_{_slug(label)}.jpg"
    img.convert("RGB").save(os.path.join(PROG, name), quality=92)
    if not os.path.exists(INDEX):
        with open(INDEX, "w", encoding="utf-8", newline="\n") as f:
            f.write("# Progress pictures\n\nA visual record of NOCLIP from the first render onward, oldest first. "
                    "Each image is a copy of something generated while building the game.\n\n"
                    "| # | When | Session | Image | What it shows | Commit |\n|---|---|---|---|---|---|\n")
    with open(INDEX, "a", encoding="utf-8", newline="\n") as f:
        f.write(f"| {n:04d} | {t:%Y-%m-%d %H:%M} | S{session:02d} | [{name}]({name}) | {note or label} | {_git()} |\n")
    print("progress:", name)
    return name


def grid(paths, cols=None, cell=(1280, 720)):
    cols = cols or (2 if len(paths) <= 4 else 3)
    rows = (len(paths) + cols - 1) // cols
    g = Image.new("RGB", (cell[0] * cols, cell[1] * rows))
    for i, p in enumerate(paths):
        g.paste(Image.open(p).convert("RGB").resize(cell, Image.LANCZOS), ((i % cols) * cell[0], (i // cols) * cell[1]))
    return g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="*")
    ap.add_argument("--label", default=None)
    ap.add_argument("--grid", default=None, help="tile all SRC images into one picture with this label")
    ap.add_argument("--note", default="")
    ap.add_argument("--session", type=int, default=DEFAULT_SESSION)
    ap.add_argument("--when", default=None)
    a = ap.parse_args()
    if a.grid:
        save(grid(a.src), a.grid, a.note, a.session, a.when)
    else:
        src, label = a.src[0], (a.label or (a.src[1] if len(a.src) > 1 else os.path.splitext(os.path.basename(a.src[0]))[0]))
        save(Image.open(src), label, a.note, a.session, a.when)


if __name__ == "__main__":
    main()
