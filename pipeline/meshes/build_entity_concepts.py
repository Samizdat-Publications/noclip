"""Concept images for the monster "the Occupant" (Gemini pro image, paid). Concept art only, no Meshy.

  python pipeline/meshes/build_entity_concepts.py            # generate missing images (paid), rebuild sheets, manifest
  python pipeline/meshes/build_entity_concepts.py --sheets   # sheets only (free)
Set A: model sheet, 8 images (A1_1..A1_4, A2_1..A2_4), 2:3, 2K.  Set B: mood, 4 images (B1_1, B1_2, B2_1, B2_2), 16:9, 2K.
Skips existing files. Key: GEMINI_API_KEY from .env via python-dotenv (never printed).
Records prompts and params in pipeline/manifests/entity_concepts.json and appends rows to docs/SPEND.md.
"""
import io, json, os, sys, datetime
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "pipeline", "meshes", "cache", "entity")
MANIFEST = os.path.join(ROOT, "pipeline", "manifests", "entity_concepts.json")
WALL = os.path.join(ROOT, "game", "assets", "textures", "level0", "wallpaper_v2_albedo.png")
SPEND = os.path.join(ROOT, "docs", "SPEND.md")
PRICE = 0.134

BODY = ("The creature is called the Occupant: a figure the building made out of its own materials, trying to copy a person. "
        "About 2.4 m tall, too thin, humanoid and bipedal with clearly separated arms and legs. Its entire body, head included, "
        "is papered in exactly the wallpaper shown in the reference image (pale mustard-yellow office wallpaper with thin vertical "
        "pinstripes and columns of small printed chevrons), hung in vertical strips with visible strip seams running down the body, "
        "water-stained with brown tide lines, peeling and curling at the elbows, knees, neck and fingertips to show dark wet grey "
        "plaster and torn drywall paper underneath. It has no face at all: the head is a smooth, slightly too-long papered oval where "
        "the wallpaper pattern jumps sideways in one horizontal band, like a misaligned seam. The neck is a little too long, the "
        "forearms and fingers are too long (fingers reach to mid-thigh), shoulders narrow and slightly sloped. No clothes, no hair, "
        "no mouth, no eyes, no horns, no claws, no smile, no glowing parts, no gore. It must not look like a person in a costume or a "
        "mummy: it looks like wall.")
SHEET = ("Full body character model sheet, single figure, front view, centered, standing in a relaxed A-pose (arms angled about 30 "
         "degrees away from the body, legs slightly apart), feet flat, the whole figure in frame with margin above and below, plain "
         "flat neutral mid-grey seamless background, soft even studio lighting with no harsh shadows and no cast shadow on the floor, "
         "orthographic-looking straight-on camera at chest height, no text, no watermark. ")
SCENE = ("Photograph-like still from a VHS camcorder (soft, a little noisy, slight tracking noise) in a dim 1990s office corridor: "
         "the same mustard wallpaper on the walls, damp beige carpet, drop ceiling with fluorescent panels, slight haze. No text, no watermark. ")
REF = "The reference image is the game's own wallpaper texture; use it exactly for the creature's paper and for the corridor walls. "

PROMPTS = {
 "A1": REF + SHEET + BODY + " Emphasis: the vertical strip seams running down the whole body and the horizontal pattern jump on the smooth oval head.",
 "A2": REF + SHEET + BODY + " Emphasis: the peeling, curling joints (elbows, knees, neck, fingertips) and the dark wet grey plaster and torn drywall paper showing through.",
 "B1": REF + SCENE + BODY + " Scene: the Occupant stands flat against the corridor wall about 6 m away from the camera, nearly invisible because its paper matches the wall; only the pattern jump on its head and its too-long fingers give it away.",
 "B2": REF + SCENE + BODY + " Scene: the Occupant stands in the middle of the corridor about 10 m away under a flickering fluorescent panel, head tilted slightly, the corridor wallpaper continuing behind it.",
}
JOBS = [("A1_%d" % i, "A1", "2:3") for i in (1, 2, 3, 4)] + [("A2_%d" % i, "A2", "2:3") for i in (1, 2, 3, 4)] + \
       [("B1_%d" % i, "B1", "16:9") for i in (1, 2)] + [("B2_%d" % i, "B2", "16:9") for i in (1, 2)]


def load_manifest():
    if os.path.exists(MANIFEST):
        return json.load(open(MANIFEST, encoding="utf-8"))
    return {"model": None, "reference": os.path.relpath(WALL, ROOT), "image_size": "2K", "price_per_image_usd": PRICE,
            "prompts": PROMPTS, "calls": []}


def save_manifest(m):
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(m, f, indent=1)


def generate_all():
    sys.path.insert(0, os.path.join(ROOT, "pipeline", "textures"))
    from build_graffiti_v2 import client_and_models
    from google.genai import types
    client, models = client_and_models()
    model = models[0]
    ref = Image.open(WALL).convert("RGB")
    ref.thumbnail((1024, 1024))
    buf = io.BytesIO(); ref.save(buf, "JPEG", quality=90)
    refpart = types.Part.from_bytes(data=buf.getvalue(), mime_type="image/jpeg")
    m = load_manifest(); m["model"] = model
    n_calls = 0
    for name, pk, ar in JOBS:
        fp = os.path.join(OUT, name + ".jpg")
        if os.path.exists(fp):
            continue
        cfg = types.GenerateContentConfig(response_modalities=["IMAGE"], temperature=1.0,
                                          image_config=types.ImageConfig(aspect_ratio=ar, image_size="2K"))
        for attempt in (1, 2):
            n_calls += 1
            ok = False
            try:
                r = client.models.generate_content(model=model, contents=[PROMPTS[pk], refpart], config=cfg)
                for part in (r.candidates[0].content.parts if r.candidates else []):
                    if getattr(part, "inline_data", None) and part.inline_data.data:
                        img = Image.open(io.BytesIO(part.inline_data.data)).convert("RGB")
                        img.save(fp, quality=92)
                        m["calls"].append({"file": name + ".jpg", "prompt_key": pk, "aspect": ar, "size": list(img.size),
                                           "attempt": attempt, "result": "image"})
                        print(name, img.size, flush=True); ok = True; break
            except Exception as ex:
                print(name, "error", type(ex).__name__, str(ex)[:120], flush=True)
            if ok:
                break
            m["calls"].append({"file": name + ".jpg", "prompt_key": pk, "attempt": attempt, "result": "no image"})
            print(name, "no image, attempt", attempt, flush=True)
        save_manifest(m)
    if n_calls:
        txt = open(SPEND, encoding="utf-8").read()
        with open(SPEND, "a", encoding="utf-8", newline="\n") as f:
            if "## Session 04" not in txt:
                f.write("\n## Session 04\n| Date | Session | Service | Purpose | Calls | Est. cost |\n|---|---|---|---|---|---|\n")
            f.write("| %s | S04 | Gemini (%s, 2K, with wallpaper reference) | Occupant monster concept images, sets A and B (build_entity_concepts.py) | %d | ~$%.2f ($%.3f each, list price estimate) |\n"
                    % (datetime.date.today().isoformat(), model, n_calls, n_calls * PRICE, PRICE))
    print("paid calls this run:", n_calls)


def sheet(names, cols, out, cell_w):
    ims = [(n, Image.open(os.path.join(OUT, n + ".jpg"))) for n in names if os.path.exists(os.path.join(OUT, n + ".jpg"))]
    if not ims:
        return
    ar = ims[0][1].height / ims[0][1].width
    cw, ch = cell_w, int(cell_w * ar); lab = 22
    rows = (len(ims) + cols - 1) // cols
    S = Image.new("RGB", (cols * cw, rows * (ch + lab)), (20, 20, 20))
    d = ImageDraw.Draw(S)
    for i, (n, im) in enumerate(ims):
        x, y = (i % cols) * cw, (i // cols) * (ch + lab)
        S.paste(im.resize((cw, ch), Image.LANCZOS), (x, y + lab))
        d.text((x + 6, y + 6), n + ".jpg", fill=(230, 230, 230))
    S.save(os.path.join(OUT, out), quality=90)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    if "--sheets" not in sys.argv:
        generate_all()
    sheet(["A1_1", "A1_2", "A1_3", "A1_4", "A2_1", "A2_2", "A2_3", "A2_4"], 4, "sheet_A.jpg", 480)
    sheet(["B1_1", "B1_2", "B2_1", "B2_2"], 2, "sheet_B.jpg", 960)
