"""Generate Level 0 props with Meshy text-to-3D (preview -> refine), cache task ids and downloads.

Usage:
  python pipeline/meshes/build_props_level0.py [--props chair,crt,box] [--variant N] [--max-credits 300]
Re-runs reuse cache/state.json, so nothing is paid twice. --variant N (>=1) makes a NEW generation
for a prop (key becomes <prop>_vN) after a visual rejection; the script never auto-retries paid calls.
Key is read from MESHY_API_KEY (loaded from .env via python-dotenv); it is never printed.
"""
import argparse, json, os, sys, time
from pathlib import Path
import requests
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "pipeline" / "meshes" / "cache"
STATE = CACHE / "state.json"
API = "https://api.meshy.ai/openapi/v2/text-to-3d"

AI_MODEL = "meshy-7.1"   # current standard model per docs.meshy.ai (2026-10-01); "latest" resolves to it
STYLE = ("photorealistic, real-world scale, worn and aged, dusty, matte non-glossy surfaces, "
         "realistic proportions, not cartoon, not stylized, no logos, no text")
PROPS = {
    "chair": dict(
        name="prop_office_chair", polycount=12000,
        prompt=("A worn 1990s rolling office task chair, charcoal gray woven fabric seat and backrest with stains "
                "and flattened cushions, black molded plastic back shell and armrests, pneumatic gas lift column, "
                "black five-star plastic base with five swivel casters, backrest tilted slightly back, "
                "dusty and used office furniture. " + STYLE),
        texture_prompt=("worn charcoal gray fabric with dark stains and dirt, black scuffed plastic, "
                        "dull matte, flat even lighting, no baked shadows")),
    "crt": dict(
        name="prop_crt_monitor", polycount=6000,
        prompt=("An old beige CRT computer monitor from the 1990s, boxy tapered rear housing, yellowed discolored "
                "beige plastic, slightly bulging dark gray glass screen with a thick bezel, small vent slots, "
                "tilt-swivel base, short stub of a black cable coming out of the back. " + STYLE),
        texture_prompt=("yellowed aged beige plastic with grime, dark dusty glass screen, matte, "
                        "flat even lighting, no baked shadows")),
    "box": dict(
        name="prop_cardboard_box", polycount=6000,
        prompt=("A slightly crushed cardboard archive storage box with a separate lid, brown corrugated cardboard, "
                "handhold cutouts on the short sides, dented corners, water stained, darker damp bottom edge, "
                "warped sagging walls. No printing. " + STYLE),
        texture_prompt=("brown corrugated cardboard, water stains, darker damp brown bottom edge, mildew spots, "
                        "plain unprinted, matte, flat even lighting, no baked shadows")),
}


def load_state():
    return json.loads(STATE.read_text()) if STATE.exists() else {}


def save_state(s):
    CACHE.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(s, indent=2))


def post(session, body):
    r = session.post(API, json=body, timeout=60)
    if r.status_code >= 400:
        raise SystemExit(f"POST failed {r.status_code}: {r.text[:300]}")
    return r.json()["result"]


def wait(session, tid, label):
    t0 = time.time()
    while True:
        r = session.get(f"{API}/{tid}", timeout=60)
        r.raise_for_status()
        j = r.json()
        print(f"  [{label}] {j['status']} {j.get('progress')}%", flush=True)
        if j["status"] == "SUCCEEDED":
            return j
        if j["status"] in ("FAILED", "CANCELED"):
            raise SystemExit(f"{label} {j['status']}: {j.get('task_error')}")
        if time.time() - t0 > 1500:
            raise SystemExit(f"{label} timed out; task {tid} still cached, re-run to resume")
        time.sleep(10)


def download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    with requests.get(url, timeout=300, stream=True) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(1 << 16):
                f.write(chunk)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--props", default="chair,crt,box")
    ap.add_argument("--variant", type=int, default=0)
    ap.add_argument("--max-credits", type=int, default=300)
    a = ap.parse_args()
    load_dotenv(ROOT / ".env")
    key = os.environ.get("MESHY_API_KEY")
    if not key:
        raise SystemExit("MESHY_API_KEY missing")
    s = requests.Session()
    s.headers.update({"Authorization": f"Bearer {key}"})
    state = load_state()
    for p in a.props.split(","):
        cfg = PROPS[p]
        k = p if a.variant == 0 else f"{p}_v{a.variant}"
        e = state.setdefault(k, {"prompt": cfg["prompt"], "texture_prompt": cfg["texture_prompt"],
                                 "ai_model": AI_MODEL, "target_polycount": cfg["polycount"]})
        spent = sum(v.get("credits", 0) for v in state.values())
        if spent >= a.max_credits and "preview_id" not in e:
            print(f"credit cap reached ({spent}); skipping {k}")
            continue
        if "preview_id" not in e:
            body = {"mode": "preview", "prompt": cfg["prompt"], "ai_model": AI_MODEL,
                    "should_remesh": True, "topology": "triangle", "target_polycount": cfg["polycount"],
                    "target_formats": ["glb"], "auto_size": True, "origin_at": "bottom"}
            e["preview_params"] = body
            e["preview_id"] = post(s, body)
            save_state(state)
            print(f"{k}: preview task created")
        if "preview_credits" not in e:
            j = wait(s, e["preview_id"], f"{k} preview")
            e["preview_credits"] = j.get("consumed_credits", 0)
            e["preview_thumb"] = j.get("thumbnail_url")
            save_state(state)
        if "refine_id" not in e:
            body = {"mode": "refine", "preview_task_id": e["preview_id"], "enable_pbr": True,
                    "texture_resolution": "2k", "texture_prompt": cfg["texture_prompt"],
                    "remove_lighting": True, "target_formats": ["glb"]}
            e["refine_params"] = body
            e["refine_id"] = post(s, body)
            save_state(state)
            print(f"{k}: refine task created")
        glb = CACHE / f"{k}.glb"
        if not glb.exists():
            j = wait(s, e["refine_id"], f"{k} refine")
            e["refine_credits"] = j.get("consumed_credits", 0)
            e["credits"] = e["preview_credits"] + e["refine_credits"]
            e["refine_thumb"] = j.get("thumbnail_url")
            download(j["model_urls"]["glb"], glb)
            save_state(state)
        e["glb"] = str(glb.relative_to(ROOT)).replace("\\", "/")
        save_state(state)
        print(f"{k}: done, credits={e.get('credits')}, file={glb.name}")


if __name__ == "__main__":
    main()
