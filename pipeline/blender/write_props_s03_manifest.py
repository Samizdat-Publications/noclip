"""Builds pipeline/manifests/props_s03.json and appends rows to docs/CREDITS.md from the cache meta + stats files."""
import json
from pathlib import Path
R = Path(__file__).resolve().parents[2]
meta = lambda u: json.loads((R / f"pipeline/meshes/sketchfab_cache/{u}/meta.json").read_text(encoding="utf-8"))
fs = json.loads((R / "pipeline/blender/previews/figure_stats.json").read_text())
ps = json.loads((R / "pipeline/blender/previews/props_s03_stats.json").read_text())
LIC = {"by": "CC Attribution (CC BY 4.0)", "cc0": "CC0"}
items, rows = [], []
def add(asset, glb, uid, tris, changes, extra=None):
    m = meta(uid)
    it = dict(asset=asset, glb=glb, uid=uid, title=m["title"], author=m["author"], license=LIC.get(m["license"], m["license"]),
              license_slug=m["license"], url=m["url"], tris=tris, changes=changes)
    it.update(extra or {}); items.append(it)
    rows.append(f"| {glb.split('/')[-1]} | {m['title']} | {m['author']} | {m['url']} | {LIC.get(m['license'], m['license'])} | {changes} |")
CH = "Uniform rescale to meters, origin to bottom center, yaw to face +Z, "
for n, s in sorted(fs.items()):
    add(f"figure_cand_{n}", s["glb"], s["uid"], s["tris"],
        "Rescaled to 1.8 m, origin at the feet, facing +Z, transforms applied, animations and shape keys dropped, textures replaced by one neutral material, parts joined, armature and skin weights kept, glTF re-export",
        dict(bones=s["bones"], bone_count=s["bone_count"], size_m_xyz_yup=s["size_m_x_y_z_yup"], scale=s["scale"], yaw_deg=s["yaw_deg"]))
t = ps["prop_tripod_sf"]; add("prop_tripod_sf", t["glb"], t["uid"], t["tris"], CH + "dropped the camera parts, kept the tripod legs only, one leg yawed toward +Z", dict(dims_m_xyz_yup=t["dims_m_xyz_yup"]))
t = ps["prop_tripod_camcorder"]; add("prop_tripod_camcorder", t["glb"], "cc324baf6dc548de965c3a47b87f1e27", t["tris"], "Tripod as above, with the game's own camcorder model (game/assets/props/player/camcorder.glb) mounted on the head, lens +Z, joined", dict(dims_m_xyz_yup=t["dims_m_xyz_yup"]))
t = ps["prop_vhs_tape_sf"]; add("prop_vhs_tape_sf", t["glb"], t["uid"], t["tris"], CH + "laid flat, scaled to 187 mm long (103 x 25 mm measured)", dict(dims_m_xyz_yup=t["dims_m_xyz_yup"]))
t = ps["prop_tape_crate"]; add("prop_tape_crate", t["glb"], t["crate_uid"], t["tris"], "Crate rescaled to 0.37 m wide, origin bottom center, joined with 10 copies of prop_vhs_tape_sf (uid 92de31c3...) standing upright with small lean/lift variations", dict(dims_m_xyz_yup=t["dims_m_xyz_yup"], cassette_uid=t["cassette_uid"], cassettes=10))
# second credit row for the cassette used in the crate
m = meta(ps["prop_tape_crate"]["cassette_uid"]); rows.append(f"| prop_tape_crate.glb (cassettes) | {m['title']} | {m['author']} | {m['url']} | {LIC.get(m['license'], m['license'])} | Ten copies standing in the crate |")
t = ps["prop_worklight_sf"]; add("prop_worklight_sf", t["glb"], t["uid"], t["tris"], CH + "yawed so the lamps face +Z, scaled to 1.75 m tall, origin on the pole (not the cable)", dict(dims_m_xyz_yup=t["dims_m_xyz_yup"], lamp_face_centers_m_xyz_yup=t["lamp_face_centers_m_xyz_yup"], lamp_normal_xyz_yup=t["lamp_normal_xyz_yup"]))
t = ps["prop_worklight_box_sf"]; add("prop_worklight_box_sf", t["glb"], t["uid"], t["tris"], CH + "scaled to 0.40 m tall", dict(dims_m_xyz_yup=t["dims_m_xyz_yup"], lamp_face_centers_m_xyz_yup=t["lamp_face_centers_m_xyz_yup"], lamp_normal_xyz_yup=t["lamp_normal_xyz_yup"]))
man = dict(tool="pipeline/meshes/sketchfab_fetch.py + pipeline/blender/clean_figure.py + pipeline/blender/clean_props_s03.py + pipeline/blender/write_props_s03_manifest.py",
           api="Sketchfab Data API v3", date="2026-10-02", cost_usd=0,
           previews=["pipeline/blender/previews/figure_candidates.png", "pipeline/blender/previews/field_props.png"],
           rejected=[dict(uid="598d1d1866df48f999fabadb017429d1", title="Basic Human Male", reason="blobby mannequin, no real silhouette"),
                     dict(uid="fc7d79e6ce5a463093e24925c7518c93", title="VHS Cassette (Brian Fox)", reason="label shows a real film title"),
                     dict(uid="ff0abe17dc64498191bb41c905d00ab0", note="used")], items=items)
(R / "pipeline/manifests/props_s03.json").write_text(json.dumps(man, indent=1), encoding="utf-8")
c = R / "docs/CREDITS.md"; txt = c.read_text(encoding="utf-8")
add_rows = [r for r in rows if r.split("|")[1].strip() not in txt]
if add_rows: c.write_text(txt.rstrip("\n") + "\n" + "\n".join(add_rows) + "\n", encoding="utf-8")
print(len(items), "items,", len(add_rows), "credit rows added")
