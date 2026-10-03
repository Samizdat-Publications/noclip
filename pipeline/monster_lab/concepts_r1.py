"""Monster Lab round 1: paint 8 monster directions into real game frames with Gemini image editing.

  python pipeline/monster_lab/concepts_r1.py [--only A,B] [--force A]

Re-runnable: a concept whose r1/<LETTER>.png exists is skipped. Up to 2 attempts per concept per run.
Concept I is the control (copy of bg/control_current.png, no API call).
Outputs: r1/<L>.png (1920x1080), pipeline/manifests/monster_lab_r1.json, blind folder review/monster_lab/r1/option_N.png
(shuffled with random.Random(7071)), pipeline/monster_lab/r1_key.json, r1/sheet.jpg. Key from .env via python-dotenv.
"""
import argparse, datetime, io, json, os, random, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / "pipeline" / "monster_lab"
OUT = LAB / "r1"
BG = LAB / "bg"
MANIFEST = ROOT / "pipeline" / "manifests" / "monster_lab_r1.json"
BLIND = ROOT / "review" / "monster_lab" / "r1"
KEY = LAB / "r1_key.json"
PRICE = 0.134
sys.path.insert(0, str(ROOT / "pipeline" / "textures"))


def load_manifest():
    return json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {"round": 1, "concepts": {}}


def save_manifest(m):
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(m, indent=2), encoding="utf-8", newline="\n")


def to_1080(img):
    img = img.convert("RGB")
    if img.size != (1920, 1080):
        # keep 16:9: center-crop to 16:9 if needed, then resize
        w, h = img.size
        tw = int(h * 16 / 9)
        if tw < w:
            x = (w - tw) // 2
            img = img.crop((x, 0, x + tw, h))
        elif tw > w:
            th = int(w * 9 / 16)
            y = (h - th) // 2
            img = img.crop((0, y, w, y + th))
        img = img.resize((1920, 1080), Image.LANCZOS)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", default="", help="comma letters to regenerate even if output exists")
    a = ap.parse_args()
    load_dotenv(ROOT / ".env")
    briefs = json.loads((LAB / "briefs_r1.json").read_text(encoding="utf-8"))
    common = briefs["common"]
    OUT.mkdir(parents=True, exist_ok=True)
    m = load_manifest()
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
        if L == "I":
            if not dst.exists():
                to_1080(Image.open(BG / "control_current.png")).save(dst)
            m["concepts"]["I"] = {"name": c["name"], "bg": "control_current", "prompt": None, "calls": 0, "cost_usd": 0.0,
                                  "when": datetime.datetime.now().isoformat(timespec="seconds"), "ok": True}
            continue
        if dst.exists() and L not in force:
            print(L, "exists, skip", flush=True)
            continue
        prompt = common + " " + c["prompt"]
        bg = Image.open(BG / (c["bg"] + ".png")).convert("RGB")
        rec = m["concepts"].get(L, {})
        rec.update({"name": c["name"], "bg": c["bg"], "prompt": prompt, "model": model})
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
        save_manifest(m)
        print(L, "ok" if ok else "FAILED", flush=True)
    save_manifest(m)

    # blind folder + key + sheet (only when all nine exist)
    letters = list("ABCDEFGHI")
    if not all((OUT / (L + ".png")).exists() for L in letters):
        print("not all concepts present; skipping blind folder")
        return
    order = letters[:]
    random.Random(7071).shuffle(order)
    BLIND.mkdir(parents=True, exist_ok=True)
    for f in BLIND.iterdir():
        f.unlink()
    key = {}
    for i, L in enumerate(order, 1):
        Image.open(OUT / (L + ".png")).convert("RGB").save(BLIND / ("option_%d.png" % i))
        key["option_%d" % i] = L
    KEY.write_text(json.dumps(key, indent=2), encoding="utf-8", newline="\n")
    tw, th = 640, 360
    sheet = Image.new("RGB", (tw * 3, th * 3), (0, 0, 0))
    try:
        font = ImageFont.truetype("arial.ttf", 44)
    except Exception:  # noqa: BLE001
        font = ImageFont.load_default()
    for i in range(1, 10):
        im = Image.open(BLIND / ("option_%d.png" % i)).resize((tw, th), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, 56, 58], fill=(0, 0, 0))
        d.text((12, 4), str(i), fill=(255, 255, 255), font=font)
        sheet.paste(im, (((i - 1) % 3) * tw, ((i - 1) // 3) * th))
    sheet.save(OUT / "sheet.jpg", quality=90)
    print("key", key)


if __name__ == "__main__":
    main()
