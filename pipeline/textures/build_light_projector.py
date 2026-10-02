"""Troffer light projector (LEDGER L101): a soft rounded rectangle that a ceiling SpotLight3D
projects, so the pool under a 2 x 4 ft panel is longer along the panel than across it instead of
a perfect circle. Godot maps a spot projector over the whole cone, +-tan(spot_angle) on each axis,
so the shape is laid out in tangent space: (tan x, tan y) = (offset / height).

Output: game/assets/textures/level0/troffer_projector.png (u = the panel's long axis).
Run: python pipeline/textures/build_light_projector.py [--angle 82]
"""
import argparse
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def build(angle_deg: float, n: int, long_t: float, short_t: float, floor: float, power: float) -> np.ndarray:
    t = math.tan(math.radians(angle_deg))
    c = (np.arange(n) + 0.5) / n * 2.0 - 1.0
    tx, ty = np.meshgrid(c * t, c * t)          # tx along columns (u), ty along rows (v)
    r = (np.abs(tx / long_t) ** power + np.abs(ty / short_t) ** power) ** (1.0 / power)
    x = np.clip((r - 0.45) / (1.3 - 0.45), 0.0, 1.0)
    core = 1.0 - x * x * (3.0 - 2.0 * x)
    return floor + (1.0 - floor) * core


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--angle", type=float, default=82.0, help="spot_angle of the ceiling lights (fixture.gd)")
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--long", type=float, default=0.85, help="half extent along the panel, in tan units (x height)")
    ap.add_argument("--short", type=float, default=0.55, help="half extent across the panel")
    ap.add_argument("--floor", type=float, default=0.6, help="light kept outside the pool (walls)")
    ap.add_argument("--power", type=float, default=4.0, help="superellipse power: 2 round, higher boxier")
    ap.add_argument("--out", default=os.path.join(ROOT, "game", "assets", "textures", "level0", "troffer_projector.png"))
    a = ap.parse_args()
    m = build(a.angle, a.size, a.long, a.short, a.floor, a.power)
    Image.fromarray(np.clip(m * 255.0 + 0.5, 0, 255).astype(np.uint8), "L").convert("RGB").save(a.out)
    print("wrote", a.out)
