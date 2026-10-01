"""Top-down preview of a layout JSON (walls, doors, pillars, fixtures, interest points).

Usage: python tools/layout_preview.py game/data/level0_hero.json out.png
"""
import json
import sys

from PIL import Image, ImageDraw

S = 30  # pixels per meter


def main(src, out):
    L = json.load(open(src, encoding="utf-8"))
    w, h = L["size"]
    img = Image.new("RGB", (int(w * S) + 40, int(h * S) + 40), (30, 28, 20))
    d = ImageDraw.Draw(img)
    o = 20

    def p(x, z):
        return (o + x * S, o + z * S)

    d.rectangle([p(0, 0), p(w, h)], fill=(180, 165, 100))
    for zx in L.get("dark_zones", []):
        d.rectangle([p(zx[0], zx[1]), p(zx[2], zx[3])], fill=(120, 110, 70))
    fg = L["fixture_grid"]
    t = L["wall_thickness"] / 2
    for i in range(fg["nx"]):
        for j in range(fg["nz"]):
            cx, cz = fg["x0"] + i * fg["dx"], fg["z0"] + j * fg["dz"]
            d.rectangle([p(cx - fg["w"] / 2, cz - fg["l"] / 2), p(cx + fg["w"] / 2, cz + fg["l"] / 2)], outline=(250, 250, 220))
    for x0, z0, x1, z1 in L["walls"]:
        d.rectangle([p(min(x0, x1) - t, min(z0, z1) - t), p(max(x0, x1) + t, max(z0, z1) + t)], fill=(40, 30, 20))
    for x0, z0, x1, z1 in L["doors"]:
        d.rectangle([p(min(x0, x1) - t, min(z0, z1) - t), p(max(x0, x1) + t, max(z0, z1) + t)], fill=(200, 60, 40))
    for cx, cz, s in L["pillars"]:
        d.rectangle([p(cx - s / 2, cz - s / 2), p(cx + s / 2, cz + s / 2)], fill=(40, 30, 20))
    for it in L["interest"]:
        x, z = it["p"]
        d.ellipse([p(x - 0.25, z - 0.25), p(x + 0.25, z + 0.25)], fill=(60, 140, 220))
        d.text(p(x + 0.3, z - 0.3), it["name"], fill=(20, 40, 90))
    sx, sz, _ = L["spawn"]
    d.ellipse([p(sx - 0.35, sz - 0.35), p(sx + 0.35, sz + 0.35)], fill=(40, 200, 60))
    img.save(out)
    print("saved", out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
