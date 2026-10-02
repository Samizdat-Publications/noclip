"""Compose pipeline/blender/previews/props_s03b.png from the _fp_<name>.png renders + props_s03b_stats.json.
  python pipeline/blender/props_s03b_sheet.py
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw

P = Path(__file__).resolve().parent / "previews"
stats = json.loads((P / "props_s03b_stats.json").read_text())
names = ["prop_water_cooler_sf", "prop_filing_cabinet_sf", "prop_step_ladder_sf", "prop_mop_bucket_sf",
         "prop_cubicle_panel_sf", "prop_office_desk_sf", "prop_stack_chairs_sf"]
W = 520; cols = 4; rows = 2
sheet = Image.new("RGB", (cols * W, rows * (W + 44)), (30, 30, 30))
d = ImageDraw.Draw(sheet)
for i, n in enumerate(names):
    x, y = (i % cols) * W, (i // cols) * (W + 44)
    t = Image.open(P / f"_fp_{n}.png").convert("RGB").resize((W, W))
    sheet.paste(t, (x, y + 44))
    s = stats[n]; dx, dh, dz = s["dims_m_xyz_yup"]
    d.text((x + 8, y + 6), n, fill=(255, 255, 120))
    d.text((x + 8, y + 24), f"{s['tris']} tris   W {dx:.2f} x H {dh:.2f} x D {dz:.2f} m", fill=(220, 220, 220))
sheet.save(P / "props_s03b.png")
print("wrote", P / "props_s03b.png")
