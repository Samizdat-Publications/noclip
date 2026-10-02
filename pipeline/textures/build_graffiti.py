"""Build the 14 Level 0 graffiti decals (marks left by earlier lost people).

Usage (from repo root):
  python pipeline/textures/build_graffiti.py                       # generate missing pieces (1 call each), then process
  python pipeline/textures/build_graffiti.py --gen slug,slug [--model M]   # add one NEW attempt for those slugs
  python pipeline/textures/build_graffiti.py --pick slug=N         # choose which cached attempt is final (default: latest)
  python pipeline/textures/build_graffiti.py --process-only        # rebuild PNGs, manifest, contact sheet; NO API calls
Key: GEMINI_API_KEY from .env via python-dotenv (never printed).
Cache: pipeline/textures/cache/graffiti/<slug>__aN.jpg (raw, JPEG q90) + attempts.json (model, prompt per attempt, choice).
"""
import argparse, io, json, os, datetime
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CACHE = os.path.join(ROOT, "pipeline", "textures", "cache", "graffiti")
OUT = os.path.join(ROOT, "game", "assets", "textures", "level0", "graffiti")
MANIFEST = os.path.join(ROOT, "pipeline", "manifests", "graffiti_level0.json")
PREVIEW = os.path.join(ROOT, "pipeline", "textures", "previews", "graffiti_contact.png")
ATTEMPTS = os.path.join(CACHE, "attempts.json")
DEFAULT_MODEL = "gemini-2.5-flash-image"
FALLBACK_MODEL = "gemini-3.1-flash-image"
PRICE = {"gemini-2.5-flash-image": 0.039, "gemini-3.1-flash-image": 0.067}

FIG = ("a tall, thin, faceless humanoid figure, blank head with no features, arms hanging down far past its knees, "
       "very long thin limbs")
CASS = "a VHS video cassette with an open eye drawn in its window"

# slug, medium, bg, text, width_m, aspect, prompt body
PIECES = [
 ("turn_around", "black permanent marker", "white", "TURN AROUND", 1.0, "4:3",
  'The words "TURN AROUND" in large, hurried, slanted block capital letters in black permanent marker, with a bent arrow below pointing back and around. Rough, fast, panicked handwriting.'),
 ("only_on_tape", "white chalk", "black", "IT'S ONLY ON THE TAPE", 1.0, "3:4",
  'The words "IT\'S ONLY ON THE TAPE" in rough white chalk capital letters at the top, and below them a crude chalk drawing of ' + FIG + '. Chalk on black, dusty and smudged.'),
 ("tally_copy", "black marker", "white", "COPY 31", 0.8, "4:3",
  'Dozens of tally marks in groups of five (four vertical strokes crossed by a diagonal) in black marker, arranged in rows, and under them the words "COPY 31" in black marker capitals.'),
 ("lights", "key scratches", "black", "DONT TRUST THE LIGHTS", 0.9, "4:3",
  'The words "DONT TRUST THE LIGHTS" scratched with a key: thin, pale, jagged gouged lines forming rough capital letters, uneven, shaky. Pale scratch lines on black.'),
 ("map_loop", "blue ballpoint pen", "white", "SAME HALL", 0.7, "1:1",
  'A hand-drawn sketch map in blue ballpoint pen: boxy rectangular corridors and rooms seen from above, and one corridor drawn as a loop with circling arrows going round and round, labelled "SAME HALL" in small blue pen capitals.'),
 ("sigil", "black marker", "white", "", 0.25, "1:1",
  'A small simple hand drawing in black marker of ' + CASS + ': a rectangle cassette with two reels and a window in which a single open eye is drawn. No text at all.'),
 ("exits", "black marker", "white", "EXITS DONT LINE UP", 1.0, "4:3",
  'The words "EXITS DONT LINE UP" in black marker capital letters, hurried, with a bold arrow beneath them pointing to the right.'),
 ("gaps_child", "reddish-brown wax crayon", "white", "IT STANDS IN THE GAPS", 0.9, "3:4",
  'A child-like frantic drawing in reddish-brown wax crayon of ' + FIG + ', scribbled over and over many times, messy crayon strokes, and the words "IT STANDS IN THE GAPS" written in shaky crayon capitals. Crayon only, no blood.'),
 ("days", "black marker", "white", "DAY 9 / 10? / 11? / ?", 0.6, "3:4",
  'A column of four lines written in black marker, each line crossed out with a strike: "DAY 9", "10?", "11?", "?". The later lines are shakier and more crooked. Handwritten, one under the other.'),
 ("we_are_copy", "black marker", "white", "WE ARE THE COPY", 1.1, "3:4",
  'The words "WE ARE THE COPY" written three times in a column in black marker capitals. Each repeated line is slightly more degraded, smeared and fuzzy than the one above, like a copy of a copy of a copy; the third line is barely legible but still the same words.'),
 ("handprints", "dirty water", "white", "", 0.7, "4:3",
  'Two or three smeared human hand prints in dark grey-brown dirty water, palm and fingers visible, smudged and dragged as if someone slid along a wall. Murky grey-brown, not red. No text.'),
 ("look_through", "white chalk", "black", "LOOK THROUGH IT", 0.9, "4:3",
  'A simple white chalk outline drawing of a camcorder (boxy body, lens, viewfinder, handgrip), with a chalk arrow pointing to it, and the words "LOOK THROUGH IT" in rough chalk capitals. Chalk on black.'),
 ("same", "black marker", "white", "SAME", 0.8, "1:1",
  'The word "SAME" written six times in black marker capitals, arranged in a spiral that winds inward, each repetition smaller than the last, getting tiny at the centre.'),
 ("was_here", "black ballpoint pen", "white", "R. WAS HERE 10/14/96", 0.3, "4:3",
  'Small, neat handwriting in black ballpoint pen: "R. WAS HERE 10/14/96", and right next to it a tiny neat sketch of ' + CASS + '.'),
]

COMMON = ("A flat, front-on, high-resolution scan of this marking alone, centered, filling most of the frame. "
          "No wall, no paper texture, no shadows, no perspective, no hands, no pens, no other objects. "
          "Do not add apostrophes or any punctuation that is not in the quoted text. ")


def full_prompt(p):
    slug, medium, bg, text, w, ar, body = p
    bgs = "on a PURE SOLID WHITE background" if bg == "white" else "on a PURE SOLID BLACK background"
    return (COMMON + "Medium: " + medium + ", " + bgs + ". " + body + " "
            "Spell any text exactly as quoted, in English capitals. Gritty, 1990s, unsettling mood. "
            "No blood, no pentagrams, no occult symbols, no skulls, no brands or logos.")


def load_att():
    if os.path.exists(ATTEMPTS):
        return json.load(open(ATTEMPTS))
    return {}


def save_att(a):
    json.dump(a, open(ATTEMPTS, "w"), indent=1)


def generate(slug, model):
    from dotenv import load_dotenv
    from google import genai
    from google.genai import types
    load_dotenv(os.path.join(ROOT, ".env"))
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    p = next(x for x in PIECES if x[0] == slug)
    prompt = full_prompt(p)
    cfg = types.GenerateContentConfig(response_modalities=["IMAGE"],
                                      image_config=types.ImageConfig(aspect_ratio=p[5]))
    r = client.models.generate_content(model=model, contents=prompt, config=cfg)
    for part in r.candidates[0].content.parts:
        if getattr(part, "inline_data", None) and part.inline_data.data:
            img = Image.open(io.BytesIO(part.inline_data.data)).convert("RGB")
            att = load_att()
            e = att.setdefault(slug, {"attempts": [], "choice": None})
            n = len(e["attempts"]) + 1
            fn = "%s__a%d.jpg" % (slug, n)
            img.save(os.path.join(CACHE, fn), quality=90)
            e["attempts"].append({"file": fn, "model": model, "prompt": prompt, "size": list(img.size),
                                  "cost_usd": PRICE.get(model, 0.07)})
            e["choice"] = n
            save_att(att)
            print("%s: attempt %d saved %s %s" % (slug, n, img.size, model))
            return True
    print(slug + ": no image returned")
    return False


def process_one(p, att):
    slug, medium, bg, text, w, ar, body = p
    e = att[slug]
    a = e["attempts"][e["choice"] - 1]
    im = np.asarray(Image.open(os.path.join(CACHE, a["file"])).convert("RGB")).astype(np.float32) / 255.0
    strength = (1.0 - im.max(axis=2)) if bg == "white" else im.max(axis=2)
    lo, hi = 0.10, 0.55
    alpha = np.clip((strength - lo) / (hi - lo), 0, 1)
    alpha = alpha * alpha * (3 - 2 * alpha)
    A = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    alpha = np.asarray(A).astype(np.float32) / 255.0
    # drop isolated specks (scanner noise) so they neither show nor skew the crop
    from scipy import ndimage
    lab, n = ndimage.label(alpha > 0.08, structure=np.ones((3, 3)))
    if n:
        area = ndimage.sum(np.ones_like(alpha), lab, index=np.arange(1, n + 1))
        keep = np.concatenate([[False], area >= 120])
        # border specks: small components touching the outer 4% margin are scanner noise
        m = int(0.04 * min(alpha.shape))
        edge = np.zeros(alpha.shape, bool)
        edge[:m, :] = edge[-m:, :] = edge[:, :m] = edge[:, -m:] = True
        touch = ndimage.maximum(edge.astype(np.uint8), lab, index=np.arange(1, n + 1)) > 0
        keep = keep & np.concatenate([[False], ~(touch & (area < 800))])
        alpha = alpha * keep[lab]
    ys, xs = np.where(alpha > 0.08)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    padx, pady = int(0.06 * (x1 - x0)), int(0.06 * (y1 - y0))
    H, W = alpha.shape
    box = (max(0, x0 - padx), max(0, y0 - pady), min(W, x1 + padx), min(H, y1 + pady))
    a3 = np.maximum(alpha, 1e-3)[..., None]
    if bg == "white":
        rgb = np.clip((im - (1 - a3)) / a3, 0, 1)
    else:
        rgb = np.clip(im / a3, 0, 1)
    strong = alpha > 0.5
    mean = rgb[strong].mean(axis=0) if strong.any() else rgb.reshape(-1, 3).mean(axis=0)
    t = np.clip(alpha * 2.0, 0, 1)[..., None]
    rgb = rgb * t + mean * (1 - t)
    rgba = np.dstack([rgb, alpha])
    out = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").crop(box)
    s = 1024 / max(out.size)
    return out.resize((max(1, round(out.width * s)), max(1, round(out.height * s))), Image.LANCZOS)


def process():
    att = load_att()
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    items, imgs = [], []
    for i, p in enumerate(PIECES, 1):
        slug = p[0]
        if slug not in att or not att[slug]["choice"]:
            print("missing", slug)
            continue
        im = process_one(p, att)
        fn = "graffiti_%02d_%s.png" % (i, slug)
        im.save(os.path.join(OUT, fn))
        e = att[slug]
        a = e["attempts"][e["choice"] - 1]
        items.append({"file": "game/assets/textures/level0/graffiti/" + fn, "slug": slug, "text": p[3],
                      "medium": p[1], "background": p[2], "prompt": a["prompt"], "model": a["model"],
                      "retries": len(e["attempts"]) - 1, "attempt_models": [x["model"] for x in e["attempts"]],
                      "chosen_attempt": e["choice"], "raw_cache": "pipeline/textures/cache/graffiti/" + a["file"],
                      "size_px": list(im.size), "wall_width_m": p[4]})
        imgs.append((slug, im))
    json.dump({"generated": datetime.date.today().isoformat(), "tool": "pipeline/textures/build_graffiti.py",
               "notes": "alpha from stroke strength (soft threshold 0.10-0.55), RGB = ink colour, crop +6% padding, longest side 1024",
               "decals": items}, open(MANIFEST, "w"), indent=1)
    cw, ch, cols = 480, 400, 4
    rows = (len(imgs) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cw, rows * ch), (196, 176, 96, 255))
    d = ImageDraw.Draw(sheet)
    for k, (slug, im) in enumerate(imgs):
        t = im.copy()
        t.thumbnail((cw - 30, ch - 50), Image.LANCZOS)
        cx, cy = (k % cols) * cw, (k // cols) * ch
        sheet.alpha_composite(t, (cx + (cw - t.width) // 2, cy + 8 + (ch - 40 - t.height) // 2))
        d.text((cx + 8, cy + ch - 20), "%02d %s" % (k + 1, slug), fill=(60, 40, 10, 255))
    sheet.convert("RGB").save(PREVIEW)
    print("processed", len(imgs), "->", OUT)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--process-only", action="store_true")
    ap.add_argument("--gen", default="")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--pick", default="")
    a = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    if a.pick:
        att = load_att()
        s, n = a.pick.split("=")
        att[s]["choice"] = int(n)
        save_att(att)
    if not a.process_only:
        att = load_att()
        todo = [s for s in a.gen.split(",") if s] or [p[0] for p in PIECES if p[0] not in att]
        for s in todo:
            generate(s, a.model)
    process()


if __name__ == "__main__":
    main()
