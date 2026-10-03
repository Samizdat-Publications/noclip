"""Monster Lab round 2: 8 finalist concepts (H1 H2 C1 C2 G1 G2 E1 E2) painted into game frames with Gemini.

  python pipeline/monster_lab/concepts_r2.py [--only H1,C2] [--force H1]

Same approach as concepts_r1.py (re-runnable, skips existing outputs, 2 attempts per concept).
Outputs r2/<ID>.png (1920x1080), pipeline/manifests/monster_lab_r2.json, blind folder review/monster_lab/r2/option_1..8.png
(random.Random(7072) shuffle), pipeline/monster_lab/r2_key.json, r2/sheet.jpg (4x2, option numbers only).
"""
import argparse, datetime, io, json, os, random, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / "pipeline" / "monster_lab"
OUT = LAB / "r2"
BG = LAB / "bg"
MANIFEST = ROOT / "pipeline" / "manifests" / "monster_lab_r2.json"
BLIND = ROOT / "review" / "monster_lab" / "r2"
KEY = LAB / "r2_key.json"
PRICE = 0.134
sys.path.insert(0, str(ROOT / "pipeline" / "textures"))
sys.path.insert(0, str(LAB))
from concepts_r1 import to_1080  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", default="")
    a = ap.parse_args()
    load_dotenv(ROOT / ".env")
    briefs = json.loads((LAB / "briefs_r2.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    m = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {"round": 2, "concepts": {}}
    force = set(x for x in a.force.split(",") if x)
    only = set(x for x in a.only.split(",") if x)

    from google import genai
    from google.genai import types
    import build_graffiti_v2 as g
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    model = g.pick_models(client)[0]
    m["model"] = model
    print("model", model, flush=True)

    for L, c in briefs["concepts"].items():
        if only and L not in only:
            continue
        dst = OUT / (L + ".png")
        if dst.exists() and L not in force:
            print(L, "exists, skip", flush=True)
            continue
        prompt = briefs["common"] + " " + c["prompt"]
        bg = Image.open(BG / (c["bg"] + ".png")).convert("RGB")
        rec = m["concepts"].get(L, {})
        rec.update({"bg": c["bg"], "prompt": prompt, "model": model})
        rec.setdefault("calls", 0)
        rec.setdefault("cost_usd", 0.0)
        ok = False
        for attempt in range(2):
            try:
                cfg = types.GenerateContentConfig(response_modalities=["IMAGE"], temperature=1.0,
                                                  image_config=types.ImageConfig(aspect_ratio="16:9", image_size="2K"))
                r = client.models.generate_content(model=model, contents=[prompt, bg], config=cfg)
                rec["calls"] += 1
                rec["cost_usd"] = round(rec["cost_usd"] + PRICE, 3)
                for part in (r.candidates[0].content.parts if r.candidates else []):
                    if getattr(part, "inline_data", None) and part.inline_data.data:
                        to_1080(Image.open(io.BytesIO(part.inline_data.data))).save(dst)
                        ok = True
                        break
                if ok:
                    break
                print(L, "no image, attempt", attempt + 1, flush=True)
            except Exception as e:  # noqa: BLE001
                rec["calls"] += 1
                rec.setdefault("errors", []).append(str(e)[:300])
                print(L, "error", str(e)[:200], flush=True)
        rec["ok"] = ok
        rec["when"] = datetime.datetime.now().isoformat(timespec="seconds")
        m["concepts"][L] = rec
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(json.dumps(m, indent=2), encoding="utf-8", newline="\n")
        print(L, "ok" if ok else "FAILED", flush=True)

    ids = list(briefs["concepts"].keys())
    if not all((OUT / (L + ".png")).exists() for L in ids):
        print("not all concepts present; skipping blind folder")
        return
    order = ids[:]
    random.Random(7072).shuffle(order)
    BLIND.mkdir(parents=True, exist_ok=True)
    for f in BLIND.iterdir():
        f.unlink()
    key = {}
    for i, L in enumerate(order, 1):
        Image.open(OUT / (L + ".png")).convert("RGB").save(BLIND / ("option_%d.png" % i))
        key["option_%d" % i] = L
    KEY.write_text(json.dumps(key, indent=2), encoding="utf-8", newline="\n")
    tw, th = 640, 360
    sheet = Image.new("RGB", (tw * 4, th * 2), (0, 0, 0))
    try:
        font = ImageFont.truetype("arial.ttf", 44)
    except Exception:  # noqa: BLE001
        font = ImageFont.load_default()
    for i in range(1, 9):
        im = Image.open(BLIND / ("option_%d.png" % i)).resize((tw, th), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, 56, 58], fill=(0, 0, 0))
        d.text((12, 4), str(i), fill=(255, 255, 255), font=font)
        sheet.paste(im, (((i - 1) % 4) * tw, ((i - 1) // 4) * th))
    sheet.save(OUT / "sheet.jpg", quality=90)
    print("key", key)


if __name__ == "__main__":
    main()
