"""Sketchfab Data API v3 helper (search / info / download). Token from .env (SKETCHFAB_TOKEN), never printed.
  python pipeline/meshes/sketchfab_fetch.py search "crt monitor" [--max-faces 50000] [--count 24]
  python pipeline/meshes/sketchfab_fetch.py info <uid>
  python pipeline/meshes/sketchfab_fetch.py download <uid> [<uid> ...]   -> sketchfab_cache/<uid>/ (skips if cached)
Only licenses cc0 and by are ever listed or downloaded (by-sa, NC, ND, store licenses rejected).
"""
import os, sys, json, argparse, zipfile, io
from pathlib import Path
import requests
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path(__file__).resolve().parent / "sketchfab_cache"
API = "https://api.sketchfab.com/v3"
OK_LICENSES = ("cc0", "by")
load_dotenv(ROOT / ".env")


def headers():
    t = os.environ.get("SKETCHFAB_TOKEN")
    if not t:
        sys.exit("SKETCHFAB_TOKEN missing from environment/.env")
    return {"Authorization": f"Token {t}"}


def detail(uid):
    r = requests.get(f"{API}/models/{uid}", headers=headers(), timeout=30)
    r.raise_for_status()
    return r.json()


def lic(m):
    l = m.get("license") or {}
    return l.get("slug") if isinstance(l, dict) else l


def summarize(m):
    g = (m.get("archives") or {}).get("glb") or {}
    l = m.get("license") or {}
    return dict(uid=m["uid"], title=m["name"], author=(m.get("user") or {}).get("displayName"),
                license=l.get("slug") if isinstance(l, dict) else l,
                license_label=l.get("label") if isinstance(l, dict) else None,
                faces=m.get("faceCount"), glb_tex_max=g.get("textureMaxResolution"),
                glb_mb=round((g.get("size") or 0) / 1e6, 1), url=m.get("viewerUrl"),
                thumb=next((t["url"] for t in sorted((m.get("thumbnails") or {}).get("images",[]),key=lambda t:abs(t["width"]-400))),None), likes=m.get("likeCount"), views=m.get("viewCount"))


def search(q, max_faces, count):
    seen = {}
    for lc in OK_LICENSES:
        r = requests.get(f"{API}/search", headers=headers(), timeout=30, params=dict(
            type="models", q=q, downloadable="true", license=lc, sort_by="-likeCount",
            max_face_count=max_faces, archives_flavours="false", count=count))
        r.raise_for_status()
        for m in r.json()["results"]:
            s = summarize(m)
            if s["license"] is None: s["license"] = lc  # filtered by license param
            seen[s["uid"]] = s
    return list(seen.values())


def download(uid):
    d = CACHE / uid
    if d.exists() and any(d.rglob("*.gl*")):
        print(f"{uid}: cached"); return d
    m = detail(uid)
    if lic(m) not in OK_LICENSES:
        sys.exit(f"{uid}: license {lic(m)} not allowed")
    r = requests.get(f"{API}/models/{uid}/download", headers=headers(), timeout=30)
    r.raise_for_status()
    info = r.json()
    fmt = "glb" if "glb" in info else "gltf"
    url = info[fmt]["url"]
    d.mkdir(parents=True, exist_ok=True)
    data = requests.get(url, timeout=300).content  # temporary signed URL; no auth header
    if fmt == "gltf":
        zipfile.ZipFile(io.BytesIO(data)).extractall(d)
    else:
        (d / "model.glb").write_bytes(data)
    (d / "meta.json").write_text(json.dumps(summarize(m), indent=2))
    print(f"{uid}: downloaded {fmt} ({len(data)/1e6:.1f} MB)")
    return d


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("search"); s.add_argument("q"); s.add_argument("--max-faces", type=int, default=50000); s.add_argument("--count", type=int, default=24)
    i = sp.add_parser("info"); i.add_argument("uid")
    dl = sp.add_parser("download"); dl.add_argument("uids", nargs="+")
    a = ap.parse_args()
    if a.cmd == "search":
        for s_ in search(a.q, a.max_faces, a.count):
            print(json.dumps(s_))
    elif a.cmd == "info":
        print(json.dumps(summarize(detail(a.uid)), indent=1))
    else:
        for u in a.uids: download(u)
