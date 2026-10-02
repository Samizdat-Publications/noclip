"""Occupant C_4 phase 2: Meshy rigging + animation clips. Re-runnable, never re-submits an existing task.

Usage: python pipeline/meshes/build_entity_rig.py [--max-credits 50]
State lives in pipeline/manifests/entity_meshy.json under "rig" and "anims". Key from MESHY_API_KEY (python-dotenv).
"""
import argparse, json, os, shutil, sys, time
from pathlib import Path
import requests
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent))
from build_entity_meshy import MANIFEST, OUT, BASE, ROOT, load, save, req, download

MODEL_TASK = "01a0fdbc-cb93-75eb-8d9d-b0886ed92af3"  # C_4 image-to-3d
HEIGHT = 2.35
CAP_DEFAULT = 50
D = OUT / "C_4"
GAME = ROOT / "game" / "assets" / "entity"
# short name -> (action_id, why). Library: pipeline/meshes/cache/entity/meshy/animation_library.json
ACTIONS = {
    "idle": (0, "Idle: plain standing idle, least motion"),
    "walk": (111, "Injured Walk: slow, wrong, dragging stalk"),
    "run": (16, "Run Fast: chase"),
    "lunge": (86, "Jump Attack: forward lunge, no fists"),
    "look": (336, "Long Breathe and Look Around: slow head searching"),
    "twitch": (113, "Mummy Stagger: stiff unnatural lurch used as the twitch beat"),
    "crouch": (524, "Cautious Crouch Walk Forward: crouched creep"),
    "crawl": (340, "Crawl and Look Back: crawl forward on all fours"),
    "scream": (386, "Zombie Scream: the one scream/death beat"),
}


def poll(s, kind, tid, limit=1500):
    t0 = time.time()
    while time.time() - t0 < limit:
        j = req(s, "GET", f"{BASE}/{kind}/{tid}").json()
        print(kind, tid[:8], j["status"], j.get("progress"), flush=True)
        if j["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
            return j
        time.sleep(10)
    return None


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--max-credits", type=int, default=CAP_DEFAULT)
    a = ap.parse_args()
    load_dotenv(ROOT / ".env")
    s = requests.Session(); s.headers["Authorization"] = "Bearer " + os.environ["MESHY_API_KEY"]
    m = load()
    m.setdefault("phase2_balance_before", req(s, "GET", BASE + "/balance").json()["balance"]); save(m)
    rig = m.setdefault("rig", {})
    if "task_id" not in rig:
        body = {"input_task_id": MODEL_TASK, "height_meters": HEIGHT}
        r = req(s, "POST", BASE + "/rigging", json=body)
        if r.status_code >= 400:
            print("rig POST failed", r.status_code, r.text[:300]); rig["error"] = r.text[:300]; save(m); return
        rig.update(request_body=body, task_id=r.json()["result"], status="PENDING"); save(m)
    if rig.get("status") not in ("SUCCEEDED", "FAILED", "CANCELED"):
        j = poll(s, "rigging", rig["task_id"])
        if j:
            rig["status"] = j["status"]; rig["task_error"] = j.get("task_error"); rig["result"] = j.get("result"); rig["consumed_credits"] = j.get("consumed_credits"); save(m)
    if rig.get("status") != "SUCCEEDED":
        print("rig not succeeded", rig.get("status")); return
    res = rig.get("result") or {}
    files = rig.setdefault("files", {})
    flat = dict(res); flat.update({"basic_" + k: v for k, v in (res.get("basic_animations") or {}).items()})
    for k, u in flat.items():
        if isinstance(u, str) and u.startswith("http") and k not in files:
            ext = ".glb" if "glb" in k else ".fbx" if "fbx" in k else Path(u.split("?")[0]).suffix
            dest = D / "rig" / f"{k}{ext}"; download(u, dest); files[k] = str(dest.relative_to(ROOT)).replace("\\", "/")
    save(m)
    # animations: one task with all action ids (3 credits each)
    an = m.setdefault("anims", {})
    an["chosen"] = {k: {"action_id": v[0], "why": v[1]} for k, v in ACTIONS.items()}
    if "task_id" not in an:
        if 3 * len(ACTIONS) + (rig.get("consumed_credits") or 5) > a.max_credits:
            print("cap would be exceeded"); return
        body = {"rig_task_id": rig["task_id"], "action_ids": [v[0] for v in ACTIONS.values()]}
        r = req(s, "POST", BASE + "/animations", json=body)
        if r.status_code >= 400:
            print("anim POST failed", r.status_code, r.text[:300]); an["error"] = r.text[:300]; save(m); return
        an.update(request_body=body, task_id=r.json()["result"], status="PENDING"); save(m)
    if an.get("status") not in ("SUCCEEDED", "FAILED", "CANCELED"):
        j = poll(s, "animations", an["task_id"])
        if j:
            an["status"] = j["status"]; an["task_error"] = j.get("task_error"); an["result"] = j.get("result"); an["consumed_credits"] = j.get("consumed_credits"); save(m)
    ares = an.get("result") or {}
    af = an.setdefault("files", {})
    for k in ("animation_glb_url", "animation_fbx_url"):
        u = ares.get(k)
        if u and k not in af:
            dest = D / "anims" / ("merged_animations" + (".glb" if "glb" in k else ".fbx")); download(u, dest)
            af[k] = str(dest.relative_to(ROOT)).replace("\\", "/")
    # signed URLs expire and are noise: keep only the path part in the manifest
    def strip(o):
        if isinstance(o, dict): return {k: strip(v) for k, v in o.items()}
        if isinstance(o, str) and o.startswith("http"): return o.split("?")[0]
        return o
    rig["result"] = strip(rig.get("result")); an["result"] = strip(an.get("result")); save(m)
    m["phase2_balance_after"] = req(s, "GET", BASE + "/balance").json()["balance"]; save(m)
    print("balance", m["phase2_balance_before"], "->", m["phase2_balance_after"])


if __name__ == "__main__":
    main()
