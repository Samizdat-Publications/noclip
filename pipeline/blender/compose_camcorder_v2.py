"""Compose camcorder_v2_candidates.png from the _cc_ renders (system python + PIL).
Columns: side (eye marker = red dot), 3/4 front, first person at raise 0.45 / 0.75 / 1.0 (game camcorder.gd poses, 70 deg vfov)."""
from pathlib import Path
from PIL import Image, ImageDraw
P = Path(__file__).resolve().parent / "previews"
names = [("camcorder", "CURRENT"), ("camcorder_v2_cand1", "CAND 1 Panasonic NV-G120 (VHS-C)"),
         ("camcorder_v2_cand2", "CAND 2 Handycam photoscan"), ("camcorder_v2_cand3", "CAND 3 Panasonic NV-M50 (shoulder VHS)")]
RH = 540
W = Image.new("RGB", (480 * 2 + 480 * 2, RH * len(names)), (30, 30, 30))
d = ImageDraw.Draw(W)
for r, (n, label) in enumerate(names):
    for c, v in enumerate(["side", "front"]):
        f = P / f"_cc_{n}_{v}.png"
        if f.exists(): W.paste(Image.open(f).convert("RGB"), (c * 480, r * RH))
    for c, t in enumerate(["fp45", "fp75", "fp100"]):
        f = P / f"_cc_{n}_{t}.png"
        if f.exists():
            W.paste(Image.open(f).convert("RGB"), (960 + (c % 2) * 480, r * RH + (c // 2) * 270))
    d.text((8, r * RH + 8), label, fill=(255, 255, 0))
W.save(P / "camcorder_v2_candidates.png")
