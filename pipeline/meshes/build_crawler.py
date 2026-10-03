"""The Crawler (depth 1 monster): Gemini concept -> Meshy 7.1 image-to-3D -> rig -> 9 clips -> clip glbs -> preview grid.

  python pipeline/meshes/build_crawler.py [--stage concept|all|files|preview] [--max-credits 75]

Same structure as build_halden_tech.py: every stage is skipped when its output / task id already exists in
pipeline/manifests/crawler_meshy.json (a Meshy task is never re-submitted). Keys come from .env via python-dotenv
(never printed). Output: game/assets/crawler/crawler_rigged.glb and game/assets/crawler/anims/<clip>.glb.
The clip splitter is the generic pipeline/blender/split_halden_anims.py; the preview is pipeline/blender/preview_clips_grid.py.
"""
import argparse, base64, datetime, io, json, os, shutil, subprocess, sys, time
from pathlib import Path
import requests
from PIL import Image
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline" / "meshes"))
sys.path.insert(0, str(ROOT / "pipeline" / "textures"))
sys.path.insert(0, str(ROOT / "tools"))
from build_entity_meshy import req, download, _unsign  # noqa: E402

BASE = "https://api.meshy.ai/openapi/v1"
MANIFEST = ROOT / "pipeline" / "manifests" / "crawler_meshy.json"
CACHE = ROOT / "pipeline" / "meshes" / "cache" / "crawler"
LIB = ROOT / "pipeline" / "meshes" / "cache" / "entity" / "meshy" / "animation_library.json"
GAME = ROOT / "game" / "assets" / "crawler"
REF = ROOT / "pipeline" / "monster_lab" / "r2" / "H1.png"
CONCEPT = CACHE / "concept_1.jpg"
HEIGHT = 1.9
GEMINI_PRICE = 0.134

PROMPT = (
    "Full body character model sheet for 3D modelling: a single enormous, gaunt-but-heavy, hairless adult humanoid, front view, "
    "centered, standing upright in a relaxed A-pose (arms angled about 30 degrees down from horizontal, away from the body, legs "
    "slightly apart), feet flat, the whole figure in frame from the crown of the head to the soles of the feet with margin above "
    "and below, plain flat light grey seamless background, even neutral light, no harsh shadows and no cast shadow on the floor, "
    "straight-on camera at chest height, no text, no watermark. Realistic and photographic, not stylized, not a cartoon. "
    "The attached reference image shows the creature: keep ITS face, bald head and skin, but pose it standing for a model sheet. "
    "Skin: smooth, dry, grey-beige, slightly waxy, like an old shop mannequin that has grown, with faint fine moulding seams running "
    "down the upper arms and down both sides of the torso, and a faint seam round the neck and the wrists. Body: EMACIATED and very tall "
    "and lean like a starved thin person scaled up: sunken belly, visible ribs and collarbones, narrow chest, thin soft limbs, NO visible abs, NO defined pecs, NO muscle definition, absolutely NOT athletic or a bodybuilder; a slightly too-long neck, long "
    "arms reaching to the knees, hands and fingers FAR too long (fingers nearly as long as the palm and forearm-thin) with long grey nails. Face: calm, slack, human-ish, eyes CLOSED (lids "
    "shut), mouth relaxed. Unclothed like a bare shop mannequin: completely smooth plastic-like groin with no genitals and no "
    "underwear, no nipples detail beyond a faint mould mark. No clothes, no hair, no eyebrows, no tattoos, no wounds, no gore, no "
    "armor, no props, no horns, no extra limbs; it is a plain eerie mannequin-like giant.")

BODY = {"ai_model": "meshy-7.1", "pose_mode": "a-pose", "should_texture": True, "enable_pbr": True,
        "texture_resolution": "2k", "should_remesh": True, "topology": "triangle", "target_polycount": 30000,
        "origin_at": "bottom", "target_formats": ["glb", "fbx"], "image_enhancement": True,
        "remove_lighting": True, "moderation": False}

# short name -> (action_id, why). Library: pipeline/meshes/cache/entity/meshy/animation_library.json (678 actions).
# The library has only two true crawl clips (340, 549); nothing is a forward all-fours scramble or a head-to-floor listen.
ACTIONS = {
    "crawl_slow": (340, "Crawl and Look Back: the only forward crawl in the library, on hands and knees with a glance back"),
    "crawl_fast": (549, "Crawl Backward: the only other true crawl; it travels BACKWARD, so play it with a negative speed_scale "
                        "(or reversed) for a faster forward scramble; no forward fast crawl exists"),
    "crawl_idle": (329, "Push Up: hands and feet on the floor, body bobbing; nearest to a still, breathing all-fours hold"),
    "look": (258, "CrouchLookAroundBow: crouched, head turning to scan (bow aim in the hands is an unavoidable extra)"),
    "lunge": (402, "Run and Leap: a forward leap, the nearest to a pounce"),
    "listen": (404, "Crouch and Step Back: a crouch; no head-to-the-floor clip exists in the library"),
    "crouch_walk": (524, "Cautious Crouch Walk Forward: low sneaking walk, forward"),
    "turn": (576, "Idle Turn Left: standing turn in place; no all-fours turn exists, so it is a standing turn"),
    "grab": (372, "Prone Reach Help: lying prone on the floor and reaching an arm forward"),
}


def load():
    return json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}


def save(m):
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with open(MANIFEST, "w", newline="\n") as f:
        json.dump(_unsign(m), f, indent=2)


def log_spend(service, purpose, calls, cost):
    sp = ROOT / "docs" / "SPEND.md"
    s = sp.read_text(encoding="utf-8")  # re-read right before writing; append only
    row = "| %s | S07 | %s | %s | %d | %s |\n" % (datetime.date.today().isoformat(), service, purpose, calls, cost)
    if "## Session 07" not in s:
        s = s.rstrip("\n") + "\n\n## Session 07\n| Date | Session | Service | Purpose | Calls | Est. cost |\n|---|---|---|---|---|---|\n"
    s = s.rstrip("\n") + "\n" + row
    sp.write_text(s, encoding="utf-8", newline="\n")


def stage_concept(m):
    c = m.setdefault("concept", {"prompt": PROMPT, "reference": "pipeline/monster_lab/r2/H1.png", "attempts": []})
    if CONCEPT.exists():
        return
    if len(c["attempts"]) >= 2:
        raise SystemExit("concept: 2 attempts already used, report instead")
    from google import genai
    from google.genai import types
    import build_graffiti_v2 as g
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    model = g.pick_models(client)[0]
    cfg = types.GenerateContentConfig(response_modalities=["IMAGE"], temperature=1.0,
                                      image_config=types.ImageConfig(aspect_ratio="2:3", image_size="2K"))
    ref = Image.open(REF).convert("RGB")
    ref.thumbnail((1280, 1280), Image.LANCZOS)
    r = client.models.generate_content(model=model, contents=[ref, PROMPT], config=cfg)
    ok = False
    for part in (r.candidates[0].content.parts if r.candidates else []):
        if getattr(part, "inline_data", None) and part.inline_data.data:
            CACHE.mkdir(parents=True, exist_ok=True)
            Image.open(io.BytesIO(part.inline_data.data)).convert("RGB").save(CONCEPT, quality=93)
            ok = True
            break
    c["attempts"].append({"model": model, "ok": ok, "when": datetime.datetime.now().isoformat(timespec="seconds"), "cost_usd": GEMINI_PRICE})
    c["model"] = model
    save(m)
    log_spend("Gemini (%s, 2K, 1 reference image)" % model, "Crawler concept model sheet (build_crawler.py)", 1, "~$%.2f" % GEMINI_PRICE)
    if not ok:
        raise SystemExit("concept: no image returned")
    subprocess.run([sys.executable, str(ROOT / "tools" / "progress.py"), str(CONCEPT), "s07-crawler-concept",
                    "--note", "Crawler concept model sheet (Gemini, front A-pose)"], check=False)


def poll(s, kind, tid, limit=1500):
    t0 = time.time()
    while time.time() - t0 < limit:
        j = req(s, "GET", f"{BASE}/{kind}/{tid}").json()
        print(kind, tid[:8], j["status"], j.get("progress"), flush=True)
        if j["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
            return j
        time.sleep(10)
    return None


def stage_model(s, m, cap):
    t = m.setdefault("model", {})
    if "task_id" not in t:
        im = Image.open(CONCEPT).convert("RGB")
        im.thumbnail((1536, 1536), Image.LANCZOS)
        b = io.BytesIO()
        im.save(b, "JPEG", quality=92)
        uri = "data:image/jpeg;base64," + base64.b64encode(b.getvalue()).decode()
        r = req(s, "POST", BASE + "/image-to-3d", json=dict(BODY, image_url=uri))
        if r.status_code >= 400:
            t["error"] = f"{r.status_code} {r.text[:300]}"
            save(m)
            raise SystemExit("model POST failed " + t["error"])
        t.update(request_body=dict(BODY, image_url=f"<concept_1.jpg, sent as {im.size[0]}x{im.size[1]} JPEG base64>"),
                 task_id=r.json()["result"], status="PENDING")
        save(m)
    if t.get("status") not in ("SUCCEEDED", "FAILED", "CANCELED"):
        j = poll(s, "image-to-3d", t["task_id"])
        if j:
            t.update(status=j["status"], consumed_credits=j.get("consumed_credits"), task_error=j.get("task_error"),
                     model_urls=j.get("model_urls"), texture_urls=j.get("texture_urls"), thumbnail_url=j.get("thumbnail_url"))
            save(m)
    if t.get("status") != "SUCCEEDED":
        raise SystemExit("model not succeeded: %s" % t.get("status"))
    files = t.setdefault("files", {})
    d = CACHE / "model"
    for fmt in ("glb", "fbx"):
        u = (t.get("model_urls") or {}).get(fmt)
        if u and fmt not in files:
            download(u, d / f"crawler.{fmt}")
            files[fmt] = f"pipeline/meshes/cache/crawler/model/crawler.{fmt}"
    for i, tex in enumerate(t.get("texture_urls") or []):
        for k, u in tex.items():
            if u and f"tex{i}_{k}" not in files:
                download(u, d / f"crawler_tex{i}_{k}.png")
                files[f"tex{i}_{k}"] = f"pipeline/meshes/cache/crawler/model/crawler_tex{i}_{k}.png"
    save(m)


def stage_rig_anims(s, m, cap):
    t = m["model"]
    rig = m.setdefault("rig", {})
    if "task_id" not in rig:
        body = {"input_task_id": t["task_id"], "height_meters": HEIGHT}
        r = req(s, "POST", BASE + "/rigging", json=body)
        if r.status_code >= 400:
            rig["error"] = r.text[:300]
            save(m)
            raise SystemExit("rig POST failed " + rig["error"])
        rig.update(request_body=body, task_id=r.json()["result"], status="PENDING")
        save(m)
    if rig.get("status") not in ("SUCCEEDED", "FAILED", "CANCELED"):
        j = poll(s, "rigging", rig["task_id"])
        if j:
            rig.update(status=j["status"], task_error=j.get("task_error"), result=j.get("result"), consumed_credits=j.get("consumed_credits"))
            save(m)
    if rig.get("status") != "SUCCEEDED":
        raise SystemExit("rig not succeeded: %s" % rig.get("status"))
    files = rig.setdefault("files", {})
    res = rig.get("result") or {}
    u = res.get("rigged_character_glb_url")
    if u and "rigged_character_glb_url" not in files:
        download(u, CACHE / "rig" / "rigged_character_glb_url.glb")
        files["rigged_character_glb_url"] = "pipeline/meshes/cache/crawler/rig/rigged_character_glb_url.glb"
    save(m)
    an = m.setdefault("anims", {})
    an["chosen"] = {k: {"action_id": v[0], "why": v[1]} for k, v in ACTIONS.items()}
    if "task_id" not in an:
        spent = (t.get("consumed_credits") or 30) + (rig.get("consumed_credits") or 5)
        if spent + 3 * len(ACTIONS) > cap:
            raise SystemExit("cap would be exceeded by animations")
        body = {"rig_task_id": rig["task_id"], "action_ids": [v[0] for v in ACTIONS.values()]}
        r = req(s, "POST", BASE + "/animations", json=body)
        if r.status_code >= 400:
            an["error"] = r.text[:300]
            save(m)
            raise SystemExit("anim POST failed " + an["error"])
        an.update(request_body=body, task_id=r.json()["result"], status="PENDING")
        save(m)
    if an.get("status") not in ("SUCCEEDED", "FAILED", "CANCELED"):
        j = poll(s, "animations", an["task_id"])
        if j:
            an.update(status=j["status"], task_error=j.get("task_error"), result=j.get("result"), consumed_credits=j.get("consumed_credits"))
            save(m)
    if an.get("status") != "SUCCEEDED":
        raise SystemExit("anims not succeeded: %s" % an.get("status"))
    af = an.setdefault("files", {})
    u = (an.get("result") or {}).get("animation_glb_url")
    if u and "glb" not in af:
        download(u, CACHE / "anims" / "merged_animations.glb")
        af["glb"] = "pipeline/meshes/cache/crawler/anims/merged_animations.glb"
    save(m)


def stage_files(m):
    GAME.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / m["rig"]["files"]["rigged_character_glb_url"], GAME / "crawler_rigged.glb")
    lib = {a["action_id"]: a for a in json.load(open(LIB))}
    amap = {lib[v[0]]["key"]: k for k, v in ACTIONS.items()}
    mapf = CACHE / "anims" / "map.json"
    mapf.parent.mkdir(parents=True, exist_ok=True)
    mapf.write_text(json.dumps(amap, indent=1), encoding="utf-8")
    from paths import blender
    cmd = [blender(), "-b", "-P", str(ROOT / "pipeline" / "blender" / "split_halden_anims.py"), "--",
           str(ROOT / m["anims"]["files"]["glb"]), str(GAME / "anims"), str(mapf)]
    out = subprocess.run(cmd, capture_output=True, text=True)
    print(out.stdout[-1500:], out.stderr[-500:])
    m["anims"]["clips"] = json.loads((GAME / "anims" / "clips.json").read_text())
    (GAME / "anims" / "clips.json").replace(CACHE / "anims" / "clips.json")
    save(m)


def stage_preview(m):
    """Workbench grid: the rigged mesh posed by each clip glb (one side-view frame mid-clip), 3x3, copied to progress."""
    from paths import blender
    out = CACHE / "preview"
    out.mkdir(parents=True, exist_ok=True)
    cmd = [blender(), "-b", "-P", str(ROOT / "pipeline" / "blender" / "preview_clips_grid.py"), "--",
           str(GAME / "crawler_rigged.glb"), str(GAME / "anims"), str(out), ",".join(ACTIONS)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    print(r.stdout[-1500:], r.stderr[-500:])
    from PIL import ImageDraw
    names = list(ACTIONS)
    tiles = [(n, out / f"{n}.png") for n in names if (out / f"{n}.png").exists()]
    if not tiles:
        raise SystemExit("preview: no tiles rendered")
    w, h = Image.open(tiles[0][1]).size
    sheet = Image.new("RGB", (w * 3, h * 3), (40, 40, 44))
    d = ImageDraw.Draw(sheet)
    for i, (n, p) in enumerate(tiles):
        x, y = (i % 3) * w, (i // 3) * h
        sheet.paste(Image.open(p).convert("RGB"), (x, y))
        d.text((x + 8, y + 6), n, fill=(255, 255, 255))
    sp = out / "clips_grid.png"
    sheet.save(sp)
    subprocess.run([sys.executable, str(ROOT / "tools" / "progress.py"), str(sp), "s07-crawler-clips",
                    "--note", "Crawler 9 clips, mid-clip frame each (Workbench)"], check=False)
    print("preview", sp)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-credits", type=int, default=75)
    ap.add_argument("--stage", default="all", choices=["concept", "all", "files", "preview"])
    a = ap.parse_args()
    load_dotenv(ROOT / ".env")
    m = load()
    if a.stage == "preview":
        stage_preview(m)
        return
    stage_concept(m)
    if a.stage == "concept":
        return
    s = requests.Session()
    s.headers["Authorization"] = "Bearer " + os.environ["MESHY_API_KEY"]
    if "balance_before" not in m:
        m["balance_before"] = req(s, "GET", BASE + "/balance").json()["balance"]
        save(m)
    stage_model(s, m, a.max_credits)
    stage_rig_anims(s, m, a.max_credits)
    m["balance_after"] = req(s, "GET", BASE + "/balance").json()["balance"]
    m["credits_spent"] = m["balance_before"] - m["balance_after"]
    save(m)
    if not (GAME / "anims" / "crawl_slow.glb").exists():
        stage_files(m)
    if not m.get("spend_logged"):
        mc, rc, ac = m["model"].get("consumed_credits"), m["rig"].get("consumed_credits"), m["anims"].get("consumed_credits")
        log_spend("Meshy (meshy-7.1 image-to-3D)", "Crawler model, 30k tris, 2k PBR (build_crawler.py)", 1, "%s credits" % mc)
        log_spend("Meshy (rigging)", "Crawler rig, 1.9 m", 1, "%s credits" % rc)
        log_spend("Meshy (animations, 9 action_ids in one task)", "Crawler clips: " + " ".join(ACTIONS) + "; balance %s to %s" % (m["balance_before"], m["balance_after"]), 1, "%s credits" % ac)
        m["spend_logged"] = True
        save(m)
    print("balance", m["balance_before"], "->", m["balance_after"])
    stage_preview(m)


if __name__ == "__main__":
    main()
