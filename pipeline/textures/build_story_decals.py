"""Story decals for Level 0: chalk marks left by earlier visitors, wet sneaker prints, and the
face of an exit sign. Procedural and seeded; regenerate with:

    python pipeline/textures/build_story_decals.py

Outputs to game/assets/textures/level0/ and a preview sheet to pipeline/textures/previews/.
"""
import json
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "assets", "textures", "level0")
PREV = os.path.join(ROOT, "pipeline", "textures", "previews")
SEED = 1997


def wobbly(draw, pts, rnd, width, jitter=2.5, steps=14):
    out = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        for k in range(steps):
            t = k / steps
            out.append((x0 + (x1 - x0) * t + rnd.uniform(-jitter, jitter), y0 + (y1 - y0) * t + rnd.uniform(-jitter, jitter)))
    out.append(pts[-1])
    for a, b in zip(out, out[1:]):
        w = max(2, int(width * rnd.uniform(0.75, 1.15)))
        draw.line([a, b], fill=255, width=w)
        draw.ellipse([b[0] - w / 2, b[1] - w / 2, b[0] + w / 2, b[1] + w / 2], fill=255)


def chalkify(mask, rnd, color=(232, 230, 220)):
    """Turn a stroke mask into broken, grainy chalk with soft edges."""
    m = np.asarray(mask.filter(ImageFilter.GaussianBlur(1.2)), dtype=np.float32) / 255.0
    h, w = m.shape
    rng = np.random.default_rng(rnd.randint(0, 10 ** 9))
    grain = rng.random((h, w)).astype(np.float32)
    coarse = np.asarray(Image.fromarray((rng.random((h // 8, w // 8)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
    a = m * np.clip((grain * 0.6 + coarse * 0.7) - 0.25, 0, 1) * 1.35
    a = np.clip(a, 0, 0.92)
    rgb = np.zeros((h, w, 3), dtype=np.float32)
    rgb[:] = np.array(color, dtype=np.float32) / 255.0
    img = np.dstack([rgb, a])
    return Image.fromarray((img * 255).astype(np.uint8), "RGBA")


def chalk_arrow(rnd):
    m = Image.new("L", (1024, 512), 0)
    d = ImageDraw.Draw(m)
    wobbly(d, [(120, 270), (820, 250)], rnd, 16)
    wobbly(d, [(700, 150), (840, 250), (690, 360)], rnd, 16)
    wobbly(d, [(150, 330), (160, 300)], rnd, 10)
    return chalkify(m, rnd)


def chalk_tally(rnd):
    m = Image.new("L", (1024, 512), 0)
    d = ImageDraw.Draw(m)
    x = 110
    for group in range(2):
        xs = []
        for i in range(4):
            wobbly(d, [(x, 140 + rnd.uniform(-8, 8)), (x + rnd.uniform(-8, 8), 370 + rnd.uniform(-8, 8))], rnd, 13)
            xs.append(x)
            x += 58
        wobbly(d, [(xs[0] - 30, 330), (xs[-1] + 35, 175)], rnd, 13)
        x += 70
    for i in range(3):
        wobbly(d, [(x, 150), (x + rnd.uniform(-6, 6), 360)], rnd, 13)
        x += 58
    return chalkify(m, rnd)


def chalk_x(rnd):
    m = Image.new("L", (1024, 1024), 0)
    d = ImageDraw.Draw(m)
    wobbly(d, [(300, 290), (720, 740)], rnd, 18)
    wobbly(d, [(720, 280), (310, 730)], rnd, 18)
    pts = []
    r0 = 330
    a0 = rnd.uniform(0, 6.28)
    for k in range(40):
        a = a0 + k / 38 * 6.6
        r = r0 * (1 + rnd.uniform(-0.04, 0.04))
        pts.append((512 + math.cos(a) * r, 512 + math.sin(a) * r * 0.95))
    wobbly(d, pts, rnd, 14, jitter=1.5, steps=3)
    return chalkify(m, rnd)


def footprint(rnd, left=True):
    w, h = 512, 1024
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    # Sneaker outsole: broad forefoot, narrow waist, round heel.
    d.ellipse([86, 60, 430, 520], fill=255)
    d.polygon([(120, 380), (400, 380), (360, 700), (160, 700)], fill=255)
    d.ellipse([140, 620, 380, 960], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(14))
    sole = np.asarray(m, dtype=np.float32) / 255.0
    rng = np.random.default_rng(rnd.randint(0, 10 ** 9))
    # Damp carpet only shows a soft, uneven shape: faint tread, patchy, darker at the toe and heel.
    tread = np.ones_like(sole)
    for y in range(80, 960, 34):
        tread[y:y + 12, :] *= 0.82
    coarse = np.asarray(Image.fromarray((rng.random((h // 16, w // 16)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
    yy = np.linspace(0, 1, h)[:, None]
    press = 0.75 + 0.25 * (np.exp(-((yy - 0.2) / 0.15) ** 2) + np.exp(-((yy - 0.8) / 0.12) ** 2))
    a = np.clip(sole * 1.3 - 0.15, 0, 1) * tread * press * np.clip(0.45 + coarse * 0.8, 0, 1)
    a *= np.clip(0.8 + rng.random(sole.shape) * 0.3, 0, 1)
    img = np.zeros((h, w, 4), dtype=np.float32)
    img[..., 0], img[..., 1], img[..., 2] = 0.15, 0.11, 0.06
    img[..., 3] = np.clip(a * 0.6, 0, 0.55)
    im = Image.fromarray((img * 255).astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(3))
    return im if left else im.transpose(Image.FLIP_LEFT_RIGHT)


def exit_sign():
    w, h = 512, 256
    img = Image.new("RGB", (w, h), (24, 6, 5))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 150)
    except OSError:
        font = ImageFont.load_default()
    bbox = d.textbbox((0, 0), "EXIT", font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.text(((w - tw) / 2 - bbox[0], (h - th) / 2 - bbox[1]), "EXIT", fill=(255, 40, 25), font=font)
    glow_b = glow.filter(ImageFilter.GaussianBlur(10))
    img = Image.blend(img, glow_b, 0.55)
    d = ImageDraw.Draw(img)
    d.text(((w - tw) / 2 - bbox[0], (h - th) / 2 - bbox[1]), "EXIT", fill=(255, 70, 50), font=font)
    # Dust and two dead pixels of light at one corner.
    rng = np.random.default_rng(SEED)
    arr = np.asarray(img, dtype=np.float32)
    arr *= (0.85 + rng.random((h, w, 1)) * 0.15)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def contact_shadow(n=512):
    """Soft dark blob under props so they sit on the carpet."""
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    r = np.sqrt(x ** 2 + y ** 2)
    a = np.clip(1 - r, 0, 1) ** 1.8 * 0.85
    img = np.zeros((n, n, 4), dtype=np.float32)
    img[..., 0], img[..., 1], img[..., 2], img[..., 3] = 0.05, 0.04, 0.03, a
    return Image.fromarray((img * 255).astype(np.uint8), "RGBA")


def main():
    rnd = random.Random(SEED)
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    made = {
        "decal_chalk_arrow": chalk_arrow(rnd),
        "decal_chalk_tally": chalk_tally(rnd),
        "decal_chalk_x": chalk_x(rnd),
        "decal_footprint_l": footprint(rnd, True),
        "decal_footprint_r": footprint(rnd, False),
        "exit_sign_emission": exit_sign(),
        "decal_contact": contact_shadow(),
    }
    for k, im in made.items():
        im.save(os.path.join(OUT, k + ".png"))
    # Preview over the wallpaper and carpet.
    wall = Image.open(os.path.join(OUT, "wallpaper_albedo.png")).convert("RGBA").resize((1024, 1024))
    carpet = Image.open(os.path.join(OUT, "carpet_albedo.png")).convert("RGBA").resize((1024, 1024))
    sheet = Image.new("RGB", (3072, 1024))
    w1 = wall.copy()
    w1.alpha_composite(made["decal_chalk_arrow"].resize((1024, 512)), (0, 0))
    w1.alpha_composite(made["decal_chalk_tally"].resize((1024, 512)), (0, 512))
    sheet.paste(w1.convert("RGB"), (0, 0))
    c1 = carpet.copy()
    c1.alpha_composite(made["decal_footprint_l"].resize((256, 512)), (300, 80))
    c1.alpha_composite(made["decal_footprint_r"].resize((256, 512)), (520, 420))
    sheet.paste(c1.convert("RGB"), (1024, 0))
    w2 = wall.copy()
    w2.alpha_composite(made["decal_chalk_x"].resize((768, 768)), (128, 0))
    w2.paste(made["exit_sign_emission"].resize((512, 256)), (256, 768))
    sheet.paste(w2.convert("RGB"), (2048, 0))
    sheet.save(os.path.join(PREV, "story_decals.png"))
    json.dump({"method": "procedural PIL/numpy", "seed": SEED, "files": list(made.keys()), "cost_usd": 0},
              open(os.path.join(ROOT, "pipeline", "manifests", "story_decals_level0.json"), "w"), indent=2)
    print("ok", list(made.keys()))


if __name__ == "__main__":
    main()
