"""Append a critique's scores to review/scores.csv.

    python tools/scores.py CRITIQUE.md --build BUILD_ID --seed SEED --critic claude|gemini
"""
import argparse
import csv
import datetime as dt
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CSV = os.path.join(ROOT, "review", "scores.csv")
CATS = [
    ("first_impression", "first impression"), ("lighting", "lighting"), ("shadows_depth", "shadows"),
    ("materials", "materials"), ("atmosphere", "atmosphere"), ("camera_image", "camera"),
    ("surreal", "surreal"), ("monster", "monster"), ("sound", "sound"), ("pace_fun", "pace"),
    ("performance", "performance"), ("keep_playing", "keep playing"),
]
WB = chr(92) + "b"  # regex word boundary, spelled out so no tool mangles the escape


def parse(text):
    out = {}
    for line in text.splitlines():
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        name = cells[0].lower().replace("*", "")
        for key, needle in CATS:
            if key not in out and re.search(WB + re.escape(needle) + WB, name):
                m = re.search(r"(\d+(?:\.\d+)?)", cells[1])
                out[key] = m.group(1) if m else "NA"
                break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("critique")
    ap.add_argument("--build", required=True)
    ap.add_argument("--seed", required=True)
    ap.add_argument("--critic", required=True)
    a = ap.parse_args()
    s = parse(open(a.critique, encoding="utf-8").read())
    row = [a.build, dt.date.today().isoformat(), a.seed, a.critic] + [s.get(k, "NA") for k, _ in CATS]
    with open(CSV, "a", newline="", encoding="utf-8") as f:
        csv.writer(f, lineterminator="\n").writerow(row)
    print(",".join(row))


if __name__ == "__main__":
    main()
