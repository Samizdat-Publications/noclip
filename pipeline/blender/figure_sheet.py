"""Assemble pipeline/blender/previews/figure_candidates.png from the _fig_<n>_{front,side}.png renders (PIL)."""
import sys, json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
P = Path(__file__).resolve().parent / "previews"
st = json.loads((P / "figure_stats.json").read_text())
ns = sorted(st)
W, H = 500, 800
sheet = Image.new("RGB", (W * 2 * len(ns) // 1, H + 60), (217, 217, 217))
d = ImageDraw.Draw(sheet)
try: f = ImageFont.truetype("arial.ttf", 22)
except Exception: f = ImageFont.load_default()
for i, n in enumerate(ns):
    for j, v in enumerate(("front", "side")):
        sheet.paste(Image.open(P / f"_fig_{n}_{v}.png").convert("RGB"), ((i * 2 + j) * W, 60))
    s = st[n]
    d.text((i * 2 * W + 10, 8), f"cand {n}: {s['tris']} tris, {s['bone_count']} bones, {s['size_m_x_y_z_yup'][1]} m", fill=(0, 0, 0), font=f)
    d.text((i * 2 * W + 10, 34), f"front | side", fill=(60, 60, 60), font=f)
sheet.save(P / "figure_candidates.png")
print(sheet.size)
