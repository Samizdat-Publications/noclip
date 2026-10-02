"""Graffiti v2: photographic marks (marker, chalk, paint, paper) for Level 0.

Run through build_graffiti.py --v2 (or directly):
  python pipeline/textures/build_graffiti.py --v2 --gen-all            # 2 attempts for every piece that has < 2 (paid)
  python pipeline/textures/build_graffiti.py --v2 --gen slug,slug      # add ONE attempt to those slugs (paid)
  python pipeline/textures/build_graffiti.py --v2 --pick slug=N        # choose final attempt (default: latest)
  python pipeline/textures/build_graffiti.py --v2 --process-only       # PNGs, manifest, graffiti.json, attempt sheets (free)
  --sheet-scale M   px per metre in the preview (default 420 = true relative scale; wallpaper tile = 0.6 m)
Key: GEMINI_API_KEY from .env via python-dotenv (never printed).
Cache: pipeline/textures/cache/graffiti/<slug>__v2aN.jpg + attempts_v2.json (v1 files untouched).
Models are chosen at runtime from client.models.list(): pieces with text use the pro image model, pieces
without text use the newest flash image model.
"""
import argparse, io, json, os, sys, zlib, datetime
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CACHE = os.path.join(ROOT, "pipeline", "textures", "cache", "graffiti")
OUT = os.path.join(ROOT, "game", "assets", "textures", "level0", "graffiti")
MANIFEST = os.path.join(ROOT, "pipeline", "manifests", "graffiti_level0.json")
GTABLE = os.path.join(ROOT, "game", "data", "graffiti.json")
PREV_DIR = os.path.join(ROOT, "pipeline", "textures", "previews")
WALL = os.path.join(ROOT, "game", "assets", "textures", "level0", "wallpaper_albedo.png")
ATT = os.path.join(CACHE, "attempts_v2.json")
WALL_TILE_M = 0.6
# USD per image (published list prices as known to this pipeline; verify against billing)
PRICE = {"pro": 0.134, "flash": 0.067}

# ---------------------------------------------------------------- prompt scaffolding
INK = ("Close-up straight-on photograph of real handwriting on plain white paper, shot perfectly flat from directly above, "
       "flat even diffuse lighting, no shadows, no perspective, sharp focus. The white paper fills the entire frame edge to edge, "
       "no paper edges, no desk. The ink is %s, soaked into the paper fibers: uneven pressure, thick and thin strokes, "
       "letters of uneven size, a drifting baseline, ink feathering slightly at the edges, dry-pen streaks where it ran out, "
       "small hesitations, a few rough corrections. It must look like genuine human handwriting in a photograph, "
       "NOT a font, NOT vector art, NOT a clean illustration, NOT digitally drawn. %s "
       "Spell any quoted text exactly, in English capitals. No apostrophes anywhere.")
CHALK = ("Close-up straight-on photograph of white chalk marks on a flat matte black slate chalkboard surface, shot perfectly flat, "
         "flat even diffuse lighting, no glare, sharp focus. The black slate fills the entire frame edge to edge. The chalk is "
         "dry and dusty, catching the grain of the surface so strokes break up and skip, uneven pressure, loose chalk dust around "
         "the lines, a few finger smudges, a faint ghost of an older rubbed-out stroke, hand-drawn and imperfect. It must look like "
         "genuine chalk photographed, NOT a font, NOT vector art, NOT a clean illustration. %s "
         "Spell any quoted text exactly, in English capitals. No apostrophes anywhere.")
OPAQ = ("Straight-on photograph of a real physical object lying flat on a plain pure black background, shot perfectly from "
        "directly above, flat even diffuse lighting, no cast shadows, sharp focus, the whole object fully visible with a wide "
        "black margin around it. %s Looks like a genuine photographed object, not an illustration, not a mockup. "
        "Spell any quoted text exactly, in English capitals. No apostrophes anywhere.")
PAINT = ("Close-up straight-on photograph of a spray-paint stencil mark on a plain pure black matte surface, shot perfectly "
         "flat, flat even lighting, sharp focus. The black surface fills the entire frame. The paint is fluorescent safety "
         "orange-red, with soft overspray mist around every edge, a few runs and drips, slightly uneven coverage where the "
         "stencil lifted. %s Genuine photograph, NOT a font, NOT vector art. Spell any quoted text exactly. No apostrophes.")

FIG = ("a tall, thin, faceless humanoid figure with a blank head, arms hanging far past its knees")
CASS = "a small VHS video cassette with an open eye drawn in its window"

# slug, mode, text, width_m, aspect_ratio, out_px, [variant A body, variant B body], scaffold-arg (ink medium)
M = "black permanent marker"
PIECES = [
 ("turn_around", "ink", "TURN AROUND", 1.0, "4:3", 1024, M,
  ['The words "TURN AROUND" written large and fast, slanted, letters of very different heights, the second word climbing uphill, with a rough bent arrow below pointing back and around. Panicked.',
   'A hurried scrawl: "TURN AROUND" in tall uneven capitals, the R and N overwritten twice, a streaky dry-marker D, and a sloppy curved arrow underneath looping back.']),
 ("only_on_tape", "chalk", "ITS ONLY ON THE TAPE", 1.0, "3:4", 1024, None,
  ['The words "ITS ONLY ON THE TAPE" in small wobbly chalk capitals along the top, and below them a crude chalk drawing of ' + FIG + ', drawn in a few shaky scratchy strokes.',
   'Chalk handwriting "ITS ONLY ON THE TAPE" in two lines, letters uneven and cramped, and under it a rough chalk sketch of ' + FIG + ', the lines doubled and smudged.']),
 ("tally_copy", "ink", "COPY 31", 0.8, "4:3", 1024, M,
  ['Rows of hand-drawn tally marks in groups of five (four vertical strokes struck through by a diagonal), each stroke a slightly different length and slant, the rows sagging and not aligned, and under them "COPY 31" scribbled in marker capitals.',
   'Many tally marks in uneven groups of five, ink pooling at stroke starts, one group miscounted and crossed over, and below, the words "COPY 31" in rough capitals with a dry-marker streak through the 3.']),
 ("lights", "chalk", "DONT TRUST THE LIGHTS", 0.9, "4:3", 1024, None,
  ['The words "DONT TRUST THE LIGHTS" scratched and scrawled in thin pale chalk-like lines, two lines of ragged capitals, shaky, the strokes thin and jagged, the baseline sagging.',
   '"DONT TRUST THE LIGHTS" written in white chalk, pressed hard, letters leaning, broken strokes, T and S overwritten, three stacked uneven lines.']),
 ("map_loop", "ink", "SAME HALL", 0.7, "1:1", 1024, "blue ballpoint pen",
  ['A hand-drawn sketch map in blue ballpoint pen: boxy rectangular corridors and rooms seen from above, wobbly ruled-by-hand lines, one corridor drawn as a loop with several circling arrows going round and round, scribbled over, labelled "SAME HALL" in small pen capitals.',
   'A quick biro floor-plan doodle, uneven lines that overshoot at corners, corridors and rooms from above, one long loop of corridor traced over and over with arrowheads, the label "SAME HALL" small and cramped beside it.']),
 ("sigil", "ink", "", 0.25, "1:1", 1024, M,
  ['A small hand drawing in black marker of ' + CASS + ': a wobbly rectangle with two reels and a window with one open eye in it, quick felt-tip lines, uneven. No text at all.',
   'A doodle of ' + CASS + ' drawn quickly in black marker, lopsided, lines overshooting, ink blotted at the corners, eye in the window. No text at all.']),
 ("exits", "ink", "EXITS DONT LINE UP", 1.0, "4:3", 1024, M,
  ['The words "EXITS DONT LINE UP" in two lines of hurried marker capitals, letters of uneven size, the second line drifting downhill, with a thick rough arrow beneath pointing right, the marker running dry along the arrow.',
   '"EXITS DONT LINE UP" scrawled fast, the letters leaning, a dried-out streaky stroke on the X, and a long sloppy arrow below pointing right.']),
 ("gaps_child", "ink", "IT STANDS IN THE GAPS", 0.9, "3:4", 1024, "reddish-brown wax crayon",
  ['A frantic, child-like crayon drawing of ' + FIG + ', scribbled over and over many times, waxy broken strokes with the paper tooth showing through, and below it "IT STANDS IN THE GAPS" in shaky crayon capitals. No blood.',
   'Layers of rough crayon scribbles forming ' + FIG + ', pressed hard, waxy grain, flakes of crayon, and underneath the words "IT STANDS IN THE GAPS" written wobbly in crayon capitals. No blood.']),
 ("days", "ink", "DAY 9 / 10? / 11? / ?", 0.6, "3:4", 1024, M,
  ['A column of four handwritten lines in marker, each crossed out with a hard strike: "DAY 9", "10?", "11?", "?". Each line is shakier, smaller and more crooked than the last, the strike-throughs hurried.',
   'Four lines one under the other in marker: "DAY 9" then "10?" then "11?" then "?", all struck through, the handwriting degrading line by line, the last question mark trembling.']),
 ("we_are_copy", "ink", "WE ARE THE COPY", 1.1, "3:4", 1024, M,
  ['The words "WE ARE THE COPY" written three times in a column in marker capitals. Each repetition is more degraded than the one above: the second is smudged by a dragged hand, the third is faint, blotted and barely legible but the same words.',
   '"WE ARE THE COPY" repeated three times, three separate handwritten lines, letters wobbling, the middle one smeared sideways by a finger, the last one fading to ghost strokes.']),
 ("handprints", "ink", "", 0.7, "4:3", 1024, "dirty grey-brown water",
  ['Two or three smeared human hand prints made with dirty water, palm and fingers partly visible, dragged and smudged as if someone slid along a wall, dribbles running downwards, murky grey-brown. No text.',
   'Handprints in muddy grey-brown water, one clear, one smeared into streaks, fingertips dripping, damp edges feathering into the paper. No text.']),
 ("look_through", "chalk", "LOOK THROUGH IT", 0.9, "4:3", 1024, None,
  ['A simple, rough chalk outline drawing of a camcorder (boxy body, lens, viewfinder, handgrip), with a hand-drawn chalk arrow pointing to it, and the words "LOOK THROUGH IT" in uneven chalk capitals.',
   'Chalk sketch of a camcorder with a wobbly lens circle, lines drawn twice, an arrow below pointing up at it, and the words "LOOK THROUGH IT" written below in thick dusty chalk letters.']),
 ("same", "ink", "SAME", 0.8, "1:1", 1024, M,
  ['The word "SAME" written six times in marker capitals, spiralling inward, each repetition smaller and shakier than the last, letters at different angles, the handwriting getting cramped at the centre.',
   '"SAME" written over and over in a hand-drawn inward spiral, six times, inconsistent letter shapes, ink skipping, the last few tiny and crowded.']),
 ("was_here", "ink", "R. WAS HERE 10/14/96", 0.3, "4:3", 1024, "black ballpoint pen",
  ['Small, quick handwriting in ballpoint pen: "R. WAS HERE 10/14/96" (with the period after the R) and next to it a tiny rough sketch of ' + CASS + '.',
   'A line of cramped biro handwriting reading "R. WAS HERE 10/14/96", the pen pressed hard on some letters and skipping on others, and a small scratchy cassette doodle beside it.']),
 # ---- new pieces
 ("chalk_door", "chalk", "HERE?", 1.3, "3:4", 2048, None,
  ['A crooked hand-traced white chalk outline of a doorway, a tall rectangle about 0.9 wide by 2.0 tall in proportion, the lines wobbly and doubled, corners overshooting, with a small chalk "HERE?" written beside it at shoulder height and a chalk arrow pointing into the outline.',
   'A rough chalk doorway outline (tall rectangle, roughly 9 to 20 proportion) drawn by hand along a wall, slightly lopsided, strokes broken and dusty, a small "HERE?" scrawled beside it at about shoulder height, and a short chalk arrow pointing into the outline.']),
 ("film_walls", "ink", "FILM THE WALLS", 0.9, "4:3", 1024, M,
  ['The words "FILM THE WALLS" in hurried marker capitals, slanted, letters uneven, underlined twice with two fast rough strokes.',
   '"FILM THE WALLS" scrawled quickly in two lines of marker, the pen running dry on WALLS, with a double underline of two sloppy wavy lines.']),
 ("hd_survey", "paint", "HD  G1  S-14", 0.7, "4:3", 1024, None,
  ['A neat professional spray-paint stencil survey mark: the code "HD  G1  S-14" in stencil capitals (letters with small bridge gaps), a stenciled arrow beside it, and a circled cross benchmark survey symbol, with overspray mist and a few drips.',
   'Stencil spray-paint survey marking in fluorescent orange-red: the line "HD  G1  S-14" in stencil lettering, a stencil arrow pointing left, and a circle with a cross inside it, soft overspray around the edges, two small drips.']),
 ("hd_tape_label", "opaque", "HD-4  REC  DO NOT REMOVE", 0.45, "21:9", 1024, None,
  ['A single strip of yellowed old masking tape, about four times as long as it is wide, torn ragged ends, a few wrinkles, hand-lettered in black marker on it: "HD-4  REC  DO NOT REMOVE" in cramped capitals, the lettering uneven.',
   'A strip of aged beige-yellow masking tape with torn uneven ends and slight curl, a hurried marker label written across it: "HD-4  REC  DO NOT REMOVE", the letters squeezed toward the right end.']),
 ("missing_flyer", "opaque", "MISSING", 0.216, "3:4", 2048, None,
  ['A faded, yellowed photocopied letter-size paper flyer, taped at its corners with clear tape, a curling corner, a faint coffee ring. At the top the big bold word "MISSING", in the middle a heavily photocopied, blown-out, smeared black-and-white photo of a person whose face is unrecognizable with crushed black photocopy shadows, and below short lines of text: "RAY M." and "LAST SEEN OCT 14 1996" and "IF YOU FIND THIS TAPE". Not a real or identifiable person.',
   'A worn photocopied missing-person style sheet of letter-size paper, yellowed, bits of clear tape at the corners, one corner curled, a coffee ring stain: huge bold "MISSING" heading, a degraded high-contrast photocopy of a faceless person, then the lines "RAY M." and "LAST SEEN OCT 14 1996" and "IF YOU FIND THIS TAPE", toner streaks. Not a real person.']),
 ("calendar_oct96", "opaque", "OCTOBER 1996", 0.3, "3:4", 1024, None,
  ['A torn-off wall calendar page headed "OCTOBER 1996", a printed grid of days where the 1st falls on a Tuesday, days 1 to 13 each crossed out with a red pen X, day 14 circled hard many times with red pen, the rest of the month scribbled over in red pen. One pushpin hole at the top center, slightly ragged torn edge.',
   'A yellowed wall calendar sheet "OCTOBER 1996", the month starting on a Tuesday, red pen crosses through the first thirteen days, the 14 circled over and over until the paper is nearly cut, the remaining days furiously scribbled out in red pen, a pin hole at the top, rough torn top edge.']),
 ("scrawl_small_1", "ink", "555-0143", 0.2, "1:1", 1024, "blue ballpoint pen",
  ['A phone number "555-0143" written small in blue ballpoint pen and crossed out with a firm scribble, one small neat line.',
   'Hasty handwriting in blue biro: "555-0143", struck through with two hard lines.']),
 ("scrawl_small_2", "ink", "NO", 0.15, "1:1", 1024, "black ballpoint pen",
  ['A small word "NO" in black ballpoint pen with a rough circle drawn around it, the circle gone round twice and not quite closing.',
   'A small hasty "NO" in pen, circled hard several times by a nervous hand.']),
 ("scrawl_small_3", "ink", "", 0.18, "1:1", 1024, "pencil",
  ['A short column of tally marks scratched in soft grey pencil, a few single strokes and one group of five, uneven, pressed lightly.',
   'A small pencil tally: seven or eight short vertical strokes with one diagonal across a group of five, faint and scratchy.']),
 ("scrawl_small_4", "ink", "?", 0.25, "1:1", 1024, "black ballpoint pen",
  ['A rough arrow drawn in black ballpoint pen pointing to the right with a single question mark written at its tip, small and quick.',
   'A scratchy pen arrow with a single question mark beside its head, line doubled over, the pen digging into the paper.']),
]

SCAFF = {"ink": lambda p, body: INK % (p[6], body), "chalk": lambda p, body: CHALK % body,
         "opaque": lambda p, body: OPAQ % body, "paint": lambda p, body: PAINT % body}


# ---------------------------------------------------------------- models
def pick_models(client):
    names = [m.name.replace("models/", "") for m in client.models.list()]
    imgs = [n for n in names if "image" in n]
    pro = [n for n in imgs if "pro-image" in n and "preview" not in n] or [n for n in imgs if "pro-image" in n]
    flash = [n for n in imgs if "flash-image" in n and "lite" not in n and "preview" not in n]
    # newest flash: highest version number
    flash.sort(key=lambda n: float(n.split("-")[1]) if n.split("-")[1].replace(".", "").isdigit() else 0)
    return pro[0], flash[-1]


def load_att():
    return json.load(open(ATT)) if os.path.exists(ATT) else {}


def save_att(a):
    json.dump(a, open(ATT, "w"), indent=1)


def client_and_models():
    from dotenv import load_dotenv
    from google import genai
    load_dotenv(os.path.join(ROOT, ".env"))
    c = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    return c, pick_models(c)


def scaffold(p, n):
    t = SCAFF[p[1]](p, p[7][(n - 1) % 2])
    if p[2] in ("", "?"):
        t = t.replace("Spell any quoted text exactly, in English capitals. No apostrophes anywhere.", "").replace(
            "Spell any quoted text exactly. No apostrophes.", "")
        t += " There is absolutely no writing, no letters and no words anywhere in the image." if not p[2] else " Apart from the arrow and one question mark there is no other writing at all."
    return t


def generate(client, models, slug):
    from google.genai import types
    p = next(x for x in PIECES if x[0] == slug)
    att = load_att()
    e = att.setdefault(slug, {"attempts": [], "choice": None})
    n = len(e["attempts"]) + 1
    kind = "pro" if p[2] else "flash"
    model = models[0] if kind == "pro" else models[1]
    prompt = scaffold(p, n)
    ic = {"aspect_ratio": p[4]}
    if kind == "pro":
        ic["image_size"] = "2K" if p[5] >= 2048 else "1K"
    cfg = types.GenerateContentConfig(response_modalities=["IMAGE"], temperature=1.0,
                                      image_config=types.ImageConfig(**ic))
    r = client.models.generate_content(model=model, contents=prompt, config=cfg)
    for part in (r.candidates[0].content.parts if r.candidates else []):
        if getattr(part, "inline_data", None) and part.inline_data.data:
            img = Image.open(io.BytesIO(part.inline_data.data)).convert("RGB")
            fn = "%s__v2a%d.jpg" % (slug, n)
            img.save(os.path.join(CACHE, fn), quality=92)
            e["attempts"].append({"file": fn, "model": model, "kind": kind, "prompt": prompt, "size": list(img.size),
                                  "image_size_req": ic.get("image_size"), "cost_usd": PRICE[kind]})
            e["choice"] = n
            save_att(att)
            print("%s: attempt %d %s %s" % (slug, n, img.size, model), flush=True)
            return PRICE[kind]
    print(slug + ": no image returned", flush=True)
    return 0.0


# ---------------------------------------------------------------- processing
def flatten_bg(im, mode):
    """Remove uneven lighting / gray vignette from the flat background so the key sees only marks."""
    H, W = im.shape[:2]
    k = 8
    sm = np.asarray(Image.fromarray((im * 255).astype(np.uint8)).resize((W // k, H // k), Image.BOX)).astype(np.float32) / 255.0
    if mode == "ink":  # paper = local bright level
        bg = ndimage.maximum_filter(sm, size=(9, 9, 1))
        bg = ndimage.gaussian_filter(bg, (6, 6, 0))
        bg = np.asarray(Image.fromarray((np.clip(bg, 0, 1) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)).astype(np.float32) / 255.0
        return np.clip(im / np.maximum(bg, 0.5), 0, 1)
    bg = ndimage.minimum_filter(sm, size=(9, 9, 1))
    bg = ndimage.gaussian_filter(bg, (6, 6, 0))
    bg = np.asarray(Image.fromarray((np.clip(bg, 0, 1) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)).astype(np.float32) / 255.0
    return np.clip((im - bg) / (1 - bg + 1e-3), 0, 1)


def process_one(p, fn):
    slug, mode = p[0], p[1]
    rng = np.random.default_rng(zlib.crc32(slug.encode()))
    im = np.asarray(Image.open(os.path.join(CACHE, fn)).convert("RGB")).astype(np.float32) / 255.0
    H, W = im.shape[:2]
    if mode in ("ink", "chalk", "paint"):
        im = flatten_bg(im, mode)
    if mode == "opaque":
        lum = im.max(axis=2)
        # background is dark navy/black with a lighting gradient: fit a quadratic surface to the outer frame
        fr = np.zeros((H, W), bool)
        b = int(0.05 * min(H, W))
        fr[:b, :] = fr[-b:, :] = fr[:, :b] = fr[:, -b:] = True
        fr &= lum < 0.4
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        yy /= H; xx /= W
        Aall = np.stack([np.ones_like(xx), xx, yy, xx * xx, yy * yy, xx * yy], -1)
        coef, *_ = np.linalg.lstsq(Aall[fr], lum[fr], rcond=None)
        bgm = Aall @ coef
        m = (lum - bgm) > 0.17
        m = ndimage.binary_closing(m, iterations=6)
        lab, n = ndimage.label(m)
        if n:
            area = ndimage.sum(m, lab, index=np.arange(1, n + 1))
            m = lab == (1 + int(np.argmax(area)))
        m = ndimage.binary_fill_holes(m)
        m = ndimage.binary_erosion(m, iterations=2)
        alpha = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) / 255.0
        rgb = im
        # clear tape / transparent corners: keep, they are part of the sheet
    else:
        strength = (1.0 - im.max(axis=2)) if mode == "ink" else im.max(axis=2)
        mg = int(0.045 * min(H, W))  # kill slate/paper edge frames and border junk
        strength[:mg, :] = strength[-mg:, :] = 0
        strength[:, :mg] = strength[:, -mg:] = 0
        if mode == "ink":
            # tint-aware: ink density = distance below paper white (use min of luminance and max channel)
            strength = np.clip(1.0 - im.max(axis=2), 0, 1)
        lo, hi = (0.05, 0.70) if mode == "ink" else (0.06, 0.60)
        alpha = np.clip((strength - lo) / (hi - lo), 0, 1) ** (1.15 if mode == "ink" else 1.0)
        # fiber breakup so it sits IN the wallpaper (alpha stays continuous)
        fine = ndimage.gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 0.9)
        fine /= fine.std() + 1e-6
        coarse = ndimage.gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 14)
        coarse /= coarse.std() + 1e-6
        amt = 0.20 if mode == "ink" else 0.30
        breakup = np.clip(1.0 - amt * (0.5 + 0.5 * np.tanh(fine * 0.9 - 0.2)) - 0.08 * (0.5 + 0.5 * np.tanh(coarse)), 0.45, 1.0)
        alpha = alpha * breakup
        alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))).astype(np.float32) / 255.0
        lab, n = ndimage.label(alpha > 0.08, structure=np.ones((3, 3)))
        if n:
            area = ndimage.sum(np.ones_like(alpha), lab, index=np.arange(1, n + 1))
            mm = int(0.03 * min(H, W))
            edge = np.zeros(alpha.shape, bool)
            edge[:mm, :] = edge[-mm:, :] = edge[:, :mm] = edge[:, -mm:] = True
            touch = ndimage.maximum(edge.astype(np.uint8), lab, index=np.arange(1, n + 1)) > 0
            keep = (area >= 60) & ~(touch & (area < 1500))
            alpha = alpha * np.concatenate([[False], keep])[lab]
        a3 = np.maximum(alpha, 1e-3)[..., None]
        base = np.clip(im - (1 - a3 if mode == "ink" else 0), 0, 1)
        # ink on white: im = (1-a)*1 + a*c  => c = (im-(1-a))/a ; chalk/paint on black: c = im/a
        rgb = np.clip((im - (1 - a3)) / a3, 0, 1) if mode == "ink" else np.clip(im / a3, 0, 1)
        strong = alpha > 0.5
        mean = rgb[strong].mean(axis=0) if strong.any() else rgb.reshape(-1, 3).mean(axis=0)
        t = np.clip(alpha * 2.0, 0, 1)[..., None]
        rgb = rgb * t + mean * (1 - t)
    ys, xs = np.where(alpha > 0.08)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    pad = 0.04 if mode != "opaque" else 0.01
    px, py = int(pad * (x1 - x0)), int(pad * (y1 - y0))
    box = (max(0, x0 - px), max(0, y0 - py), min(W, x1 + px), min(H, y1 + py))
    out = Image.fromarray((np.dstack([rgb, alpha]) * 255 + 0.5).astype(np.uint8), "RGBA").crop(box)
    lim = p[5]
    s = lim / max(out.size)
    return out.resize((max(1, round(out.width * s)), max(1, round(out.height * s))), Image.LANCZOS)


def over_wall(piece, p, wall_big, ppm, mode):
    """Composite piece over wallpaper crop at ppm pixels per metre. Returns RGB image."""
    w = max(8, int(p[3] * ppm))
    h = max(8, int(w * piece.height / piece.width))
    pc = piece.resize((w, h), Image.LANCZOS)
    pad = int(0.08 * ppm)
    cw, ch = w + 2 * pad, h + 2 * pad
    tile = int(WALL_TILE_M * ppm)
    wt = wall_big.resize((tile, tile), Image.LANCZOS)
    bg = Image.new("RGB", (cw, ch))
    for y in range(0, ch, tile):
        for x in range(0, cw, tile):
            bg.paste(wt, (x, y))
    bgf = np.asarray(bg).astype(np.float32) / 255.0
    a = np.zeros((ch, cw), np.float32)
    c = np.zeros((ch, cw, 3), np.float32)
    pa = np.asarray(pc).astype(np.float32) / 255.0
    a[pad:pad + h, pad:pad + w] = pa[..., 3]
    c[pad:pad + h, pad:pad + w] = pa[..., :3]
    a = a[..., None]
    if mode == "ink":
        out = bgf * (1 - a + a * c)  # multiply: dark ink soaks into the wallpaper
    else:
        out = bgf * (1 - a) + c * a
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def sheets(att, ppm, tag):
    wall = Image.open(WALL).convert("RGB")
    cells = []
    for p in PIECES:
        e = att.get(p[0])
        if not e:
            continue
        for i, a in enumerate(e["attempts"], 1):
            cells.append((p, i, a))
    CW = CH = 600
    cols, rows = 4, 5
    per = cols * rows
    outs = []
    for si in range(0, len(cells), per):
        sheet = Image.new("RGB", (cols * CW, rows * CH), (20, 20, 20))
        d = ImageDraw.Draw(sheet)
        for k, (p, i, a) in enumerate(cells[si:si + per]):
            piece = process_one(p, a["file"])
            sc = ppm
            comp = over_wall(piece, p, wall, sc, p[1])
            f = min(1.0, (CW - 20) / comp.width, (CH - 50) / comp.height)
            if f < 1.0:
                comp = comp.resize((max(1, int(comp.width * f)), max(1, int(comp.height * f))), Image.LANCZOS)
            x, y = (k % cols) * CW, (k // cols) * CH
            sheet.paste(comp, (x + (CW - comp.width) // 2, y + 6))
            note = "" if f >= 1 else " (shrunk %.0f%%)" % (f * 100)
            d.text((x + 8, y + CH - 36), "%s  attempt %d  %s%s" % (p[0], i, a["model"], note), fill=(255, 255, 255))
            d.text((x + 8, y + CH - 20), "%.2f m wide, %d px/m" % (p[3], ppm * f), fill=(190, 190, 190))
        fn = os.path.join(PREV_DIR, "graffiti_v2_attempts%s%s.png" % (tag, "" if si == 0 else "_%d" % (si // per + 1)))
        sheet.save(fn)
        outs.append(fn)
    return outs


def process(ppm):
    att = load_att()
    os.makedirs(OUT, exist_ok=True)
    items, table = [], {}
    for idx, p in enumerate(PIECES, 1):
        e = att.get(p[0])
        if not e or not e["choice"]:
            print("missing", p[0])
            continue
        a = e["attempts"][e["choice"] - 1]
        im = process_one(p, a["file"])
        fn = "graffiti_%02d_%s.png" % (idx, p[0])
        im.save(os.path.join(OUT, fn))
        table[p[0]] = {"tex": "graffiti/" + fn[:-4], "width": p[3], "aspect": round(im.height / im.width, 4)}
        items.append({"file": "game/assets/textures/level0/graffiti/" + fn, "slug": p[0], "text": p[2], "mode": p[1],
                      "model": a["model"], "prompt": a["prompt"], "attempts": len(e["attempts"]),
                      "chosen_attempt": e["choice"], "attempt_models": [x["model"] for x in e["attempts"]],
                      "attempt_cost_usd": [x["cost_usd"] for x in e["attempts"]],
                      "raw_cache": "pipeline/textures/cache/graffiti/" + a["file"],
                      "size_px": list(im.size), "wall_width_m": p[3]})
    json.dump(table, open(GTABLE, "w"), indent=1)
    json.dump({"generated": datetime.date.today().isoformat(), "tool": "pipeline/textures/build_graffiti_v2.py",
               "version": 2, "prices_usd_per_image": PRICE,
               "notes": "v2 photographic prompts; ink/chalk/paint keyed by luminance with continuous alpha plus fiber breakup; "
                        "opaque pieces (tape, flyer, calendar) keyed against black, largest component, holes filled. "
                        "Default choice = latest attempt; override with --pick.",
               "decals": items}, open(MANIFEST, "w"), indent=1)
    os.makedirs(PREV_DIR, exist_ok=True)
    outs = sheets(att, ppm, "")
    print("processed", len(items), "sheets", outs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--v2", action="store_true")
    ap.add_argument("--process-only", action="store_true")
    ap.add_argument("--gen", default="")
    ap.add_argument("--gen-all", action="store_true")
    ap.add_argument("--pick", default="")
    ap.add_argument("--sheet-scale", type=float, default=420)
    a = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    if a.pick:
        att = load_att()
        for kv in a.pick.split(","):
            s, n = kv.split("=")
            att[s]["choice"] = int(n)
        save_att(att)
    if not a.process_only and (a.gen or a.gen_all):
        c, models = client_and_models()
        print("models:", models, flush=True)
        att = load_att()
        todo = []
        if a.gen_all:
            for p in PIECES:
                have = len(att.get(p[0], {}).get("attempts", []))
                todo += [p[0]] * (2 - have)
        else:
            todo = [s for s in a.gen.split(",") if s]
        total = 0.0
        for s in todo:
            total += generate(c, models, s)
        print("spent est $%.2f" % total)
    process(a.sheet_scale)


if __name__ == "__main__":
    main()
