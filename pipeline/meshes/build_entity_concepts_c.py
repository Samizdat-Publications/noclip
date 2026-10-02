"""Round 2 of the Occupant concept (D035): the creature from mood shot B2_2 (picked by the lead:
gaunt, hanging paper flaps, the best silhouette) redrawn as a clean front A-pose model sheet for
Meshy image-to-3D. Round 1 model sheets read as smooth mannequins in a bodysuit.

  python pipeline/meshes/build_entity_concepts_c.py [--n 4]     # paid, skips existing files
Set C: C_1..C_n, 2:3, 2K, gemini pro image. References: B2_2.jpg (the creature) and the game's
wallpaper. Key from .env via python-dotenv (never printed). Logs to the manifest and docs/SPEND.md.
"""
import argparse, datetime, io, json, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_entity_concepts as base  # noqa: E402

PROMPT = (
    "The first reference image shows a creature called the Occupant standing in a corridor. The second reference image is "
    "the game's own wallpaper texture. Draw exactly the same creature as a full body character model sheet for 3D modelling: "
    "single figure, front view, centered, standing in a relaxed A-pose (arms angled about 30 degrees away from the body, legs "
    "slightly apart), feet flat, the whole figure in frame with margin above and below, plain flat neutral mid-grey seamless "
    "background, soft even studio lighting with no harsh shadows and no cast shadow on the floor, orthographic-looking "
    "straight-on camera at chest height, no text, no watermark. "
    "Keep what makes the creature in the first image frightening, and push it further: it is gaunt and bony, about 2.4 m "
    "tall and too thin, with a slightly too long neck, narrow sloped shoulders, forearms and fingers far too long (the "
    "fingertips hang to the middle of the thigh), knobbly knees and elbows. It is not a smooth mannequin and not a person in "
    "a bodysuit: its whole body, head included, is papered in exactly the wallpaper of the second image, hung in overlapping "
    "vertical strips with clear seams, lumpy and wrinkled where the paper was pasted over bone, with air bubbles, brown water "
    "stains and tide lines. Long loose flaps of torn wallpaper hang off the shoulders, ribs, hips and forearms, curling away "
    "from the body, and the tears show dark wet grey plaster and torn drywall underneath. The pinstripes and chevrons of the "
    "wallpaper are clearly visible all over the body. No face at all: the head is a slightly too long papered oval where the "
    "wallpaper pattern jumps sideways in one horizontal band like a misaligned seam. No clothes, no hair, no mouth, no eyes, "
    "no claws, no glowing parts, no gore.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=4)
    a = ap.parse_args()
    from dotenv import load_dotenv
    from google import genai
    from google.genai import types
    load_dotenv(os.path.join(base.ROOT, ".env"))
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    sys.path.insert(0, os.path.join(base.ROOT, "pipeline", "textures"))
    import build_graffiti_v2 as g  # noqa: E402
    model = g.pick_models(client)[0]

    def jpeg_part(path, px):
        im = Image.open(path).convert("RGB")
        im.thumbnail((px, px))
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=90)
        return types.Part.from_bytes(data=buf.getvalue(), mime_type="image/jpeg")

    ref_c = jpeg_part(os.path.join(base.OUT, "B2_2.jpg"), 1280)
    ref_w = jpeg_part(base.WALL, 1024)
    m = base.load_manifest()
    log = m.setdefault("calls", [])
    m.setdefault("prompts", {})["C"] = PROMPT
    spent = 0
    for k in range(1, a.n + 1):
        fn = os.path.join(base.OUT, "C_%d.jpg" % k)
        if os.path.exists(fn):
            continue
        cfg = types.GenerateContentConfig(response_modalities=["IMAGE"], temperature=1.0,
                                          image_config=types.ImageConfig(aspect_ratio="2:3", image_size="2K"))
        r = client.models.generate_content(model=model, contents=[PROMPT, ref_c, ref_w], config=cfg)
        spent += 1
        ok = False
        for part in (r.candidates[0].content.parts if r.candidates else []):
            if getattr(part, "inline_data", None) and part.inline_data.data:
                Image.open(io.BytesIO(part.inline_data.data)).convert("RGB").save(fn, quality=93)
                ok = True
                break
        log.append({"file": os.path.basename(fn), "model": model, "set": "C", "ok": ok,
                    "when": datetime.datetime.now().isoformat(timespec="seconds"), "cost_usd": base.PRICE})
        print(os.path.basename(fn), "ok" if ok else "no image", flush=True)
    base.save_manifest(m)
    if spent:
        row = "| %s | S04 | Gemini (%s, 2K) | Occupant concept round 2: B2_2 redrawn as a front A-pose model sheet for Meshy (build_entity_concepts_c.py) | %d | ~$%.2f |\n" % (
            datetime.date.today().isoformat(), model, spent, spent * base.PRICE)
        s = open(base.SPEND, encoding="utf-8").read()
        marker = "## Session 04"
        i = s.index(marker)
        # append at the end of the Session 04 table (the next blank line after its header)
        j = s.find("\n\n", i)
        j = len(s) if j < 0 else j + 1
        s = s[:j] + row + s[j:]
        open(base.SPEND, "w", encoding="utf-8", newline="\n").write(s)
    base.sheet(["C_%d" % k for k in range(1, a.n + 1)], 4, "sheet_C.jpg", 450)


if __name__ == "__main__":
    main()
