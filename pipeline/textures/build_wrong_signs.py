"""Exit signs that almost read (VISION "Remembered wrong": text from a description). Same lamp,
same red, same dust as the real sign (build_story_decals.py exit_sign), but the word was copied
by someone who knew it only as a shape: a 1 for the I, a mirrored word, swapped
letters, a backwards E. Procedural and seeded; regenerate with:

    python pipeline/textures/build_wrong_signs.py

Outputs game/assets/textures/level0/exit_sign_wrong_<slug>_emission.png and a preview sheet.
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "assets", "textures", "level0")
PREV = os.path.join(ROOT, "pipeline", "textures", "previews")
SEED = 1997

# slug -> (text, mirrored)
VARIANTS = {
    "ex1t": ("EX1T", False),       # a 1 where the I should be (a lowercase l looked the same)
    "mirror": ("EXIT", True),      # the whole word mirrored, like a sign read from behind
    "eixt": ("EIXT", False),       # two letters swapped
    "backe": ("\u018eXIT", False),  # a backwards E
}


def sign(text, mirrored):
    w, h = 512, 256
    img = Image.new("RGB", (w, h), (24, 6, 5))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 150)
    except OSError:
        font = ImageFont.load_default()
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pos = ((w - tw) / 2 - bbox[0], (h - th) / 2 - bbox[1])
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    ImageDraw.Draw(glow).text(pos, text, fill=(255, 40, 25), font=font)
    img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(10)), 0.55)
    ImageDraw.Draw(img).text(pos, text, fill=(255, 70, 50), font=font)
    if mirrored:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    rng = np.random.default_rng(SEED)
    arr = np.asarray(img, dtype=np.float32)
    arr *= (0.85 + rng.random((h, w, 1)) * 0.15)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    sheet = Image.new("RGB", (512, 256 * len(VARIANTS)))
    files = []
    for i, (slug, (text, mirrored)) in enumerate(VARIANTS.items()):
        im = sign(text, mirrored)
        name = "exit_sign_wrong_%s_emission" % slug
        im.save(os.path.join(OUT, name + ".png"))
        files.append(name)
        sheet.paste(im, (0, 256 * i))
    sheet.save(os.path.join(PREV, "wrong_signs.png"))
    json.dump({"method": "procedural PIL/numpy (same lamp as build_story_decals.exit_sign)", "seed": SEED,
               "variants": {k: {"text": v[0], "mirrored": v[1]} for k, v in VARIANTS.items()},
               "files": files, "cost_usd": 0},
              open(os.path.join(ROOT, "pipeline", "manifests", "wrong_signs_level0.json"), "w"), indent=2)
    print("ok", files)


if __name__ == "__main__":
    main()
