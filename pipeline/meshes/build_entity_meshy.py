"""Occupant (monster) image-to-3D with Meshy. Phase 1: mesh + PBR texture, no rig.

Usage: python pipeline/meshes/build_entity_meshy.py [--only C_2] [--max-credits 90]
Re-runnable: task ids are cached in pipeline/manifests/entity_meshy.json; an existing task is never re-submitted.
Key comes from MESHY_API_KEY (python-dotenv); never printed.
"""
import argparse, base64, io, json, os, shutil, sys, time
from pathlib import Path
import requests
from PIL import Image
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "pipeline" / "manifests" / "entity_meshy.json"
SRC = ROOT / "pipeline" / "meshes" / "cache" / "entity"
OUT = SRC / "meshy"
GAME = ROOT / "game" / "assets" / "entity"
BASE = "https://api.meshy.ai/openapi/v1"
NAMES = ["C_2", "C_4"]
BODY = {"ai_model": "meshy-7.1", "pose_mode": "a-pose", "should_texture": True, "enable_pbr": True,
        "texture_resolution": "2k", "should_remesh": True, "topology": "triangle", "target_polycount": 40000,
        "origin_at": "bottom", "target_formats": ["glb", "fbx"], "image_enhancement": True,
        "remove_lighting": True, "moderation": False}


def load():
    return json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {"tasks": {}}


def save(m):
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with open(MANIFEST, "w", newline="\n") as f:
        json.dump(m, f, indent=2)


def data_uri(path):
    im = Image.open(path).convert("RGB")
    im.thumbnail((1536, 1536), Image.LANCZOS)
    b = io.BytesIO()
    im.save(b, "JPEG", quality=92)
    return "data:image/jpeg;base64," + base64.b64encode(b.getvalue()).decode(), im.size


def req(s, method, url, **kw):
    for _ in range(6):
        r = s.request(method, url, timeout=120, **kw)
        if r.status_code == 429:
            time.sleep(int(r.headers.get("Retry-After", 20)))
            continue
        if r.status_code == 402:
            raise SystemExit("402 insufficient credits, stopping")
        return r
    raise SystemExit("too many 429s")


def download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    with requests.get(url, timeout=300, stream=True) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for c in r.iter_content(1 << 16):
                f.write(c)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--max-credits", type=int, default=90)
    a = ap.parse_args()
    load_dotenv(os.path.join(ROOT, ".env"))
    s = requests.Session()
    s.headers["Authorization"] = "Bearer " + os.environ["MESHY_API_KEY"]
    m = load()
    names = [a.only] if a.only else NAMES
    m.setdefault("balance_before", req(s, "GET", BASE + "/balance").json()["balance"]); save(m)
    # submit both (queue allows it), skipping any that exist
    for n in names:
        t = m["tasks"].setdefault(n, {})
        if "task_id" in t:
            continue
        spent = sum(v.get("credits", 30) for v in m["tasks"].values() if "task_id" in v)
        if spent + 30 > a.max_credits:
            print("credit cap would be exceeded, skipping", n); continue
        uri, size = data_uri(SRC / f"{n}.jpg")
        body = dict(BODY, image_url=uri)
        r = req(s, "POST", BASE + "/image-to-3d", json=body)
        if r.status_code >= 400:
            print("POST failed", n, r.status_code, r.text[:300]); t["error"] = f"{r.status_code} {r.text[:300]}"; save(m); continue
        t["request_body"] = dict(BODY, image_url=f"<{n}.jpg, sent downscaled to {size[0]}x{size[1]} JPEG base64>")
        t["task_id"] = r.json()["result"]; t["status"] = "PENDING"; save(m)
        print(n, "submitted", t["task_id"])
    # poll
    t0 = time.time()
    pending = [n for n in names if "task_id" in m["tasks"][n] and m["tasks"][n].get("status") not in ("SUCCEEDED", "FAILED", "CANCELED")]
    while pending and time.time() - t0 < 1200:
        for n in list(pending):
            t = m["tasks"][n]
            j = req(s, "GET", f"{BASE}/image-to-3d/{t['task_id']}").json()
            t["status"] = j["status"]; print(n, j["status"], j.get("progress"), flush=True)
            if j["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
                t["credits"] = j.get("consumed_credits"); t["task_error"] = j.get("task_error")
                t["model_urls"] = j.get("model_urls"); t["texture_urls"] = j.get("texture_urls"); t["thumbnail_url"] = j.get("thumbnail_url")
                pending.remove(n)
            save(m)
        if pending:
            time.sleep(15)
    if pending:
        print("timed out waiting for", pending)
    # downloads
    for n in names:
        t = m["tasks"].get(n, {})
        if t.get("status") != "SUCCEEDED":
            continue
        d = OUT / n; files = t.setdefault("files", {})
        for fmt in ("glb", "fbx", "pre_remeshed_glb"):
            u = (t.get("model_urls") or {}).get(fmt)
            if u and fmt not in files:
                dest = d / f"{n}.{fmt if fmt != 'pre_remeshed_glb' else 'pre_remeshed.glb'}"
                download(u, dest); files[fmt] = str(dest.relative_to(ROOT)).replace("\\", "/")
        for i, tex in enumerate(t.get("texture_urls") or []):
            for k, u in tex.items():
                key = f"tex{i}_{k}"
                if u and key not in files:
                    dest = d / f"{n}_tex{i}_{k}.png"; download(u, dest); files[key] = str(dest.relative_to(ROOT)).replace("\\", "/")
        if t.get("thumbnail_url") and "thumb" not in files:
            dest = d / f"{n}_thumb.png"; download(t["thumbnail_url"], dest); files["thumb"] = str(dest.relative_to(ROOT)).replace("\\", "/")
        GAME.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / files["glb"], GAME / f"occupant_{n}_raw.glb")
        files["game_glb"] = f"game/assets/entity/occupant_{n}_raw.glb"
        save(m)
    m["balance_after"] = req(s, "GET", BASE + "/balance").json()["balance"]; save(m)
    print("balance before/after", m["balance_before"], m["balance_after"])


if __name__ == "__main__":
    main()
