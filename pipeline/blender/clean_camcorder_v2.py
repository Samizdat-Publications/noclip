"""Clean Sketchfab camcorder candidates into engine-ready viewmodels (same contract as build_camcorder.py).
  "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b -P pipeline/blender/clean_camcorder_v2.py -- [--only 1]
Contract (matches game/assets/props/player/camcorder.glb): meters, glTF Y-up export, ORIGIN = centre of the eyecup back
opening, lens pointing -Z (glTF) = +Y in Blender Z-up, up = +Y glTF, +X = operator right, transforms applied.
Per candidate: import, join, apply, yaw (lens to +Y), uniform scale (length along lens axis), delete decal/logo
meshes, inpaint baked-in logo text in the atlas, move eye point to origin, export GLB (textures <= 2048).
Eye point is given as fractions of the post-scale bounding box (fx, fy, fz) plus optional metre nudges.
"""
import bpy, bmesh, sys, json, math
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "pipeline/meshes/sketchfab_cache"
OUT = ROOT / "game/assets/props/player"
STATS = ROOT / "pipeline/blender/previews/camcorder_v2_stats.json"

# rects are (x0, y0, x1, y1) in top-down pixel coords of the 1024 atlas as saved by Blender (origin top-left).
JOBS = {
    1: dict(name="camcorder_v2_cand1", uid="802d634fb1f745f2b528109661acd2c9", title="Panasonic NV-G120 VHS-C CAMERA",
            author="PetyaPetr", yaw=180, length=0.215,
            eye=dict(xz_obj="Cylinder.035_Glass_0", y_obj="Cylinder.035_Material.008_0", y_pick="max"), nudge=(0, 0, 0),
            drop_materials=["G120_LOGO", "LOGO1", "WIDE"], paint={}),
    2: dict(name="camcorder_v2_cand2", uid="b45dcfaa8dc0433ea3cac820d7f55edc", title="Sony Handycam Photoscan Low Poly",
            author="EFX", yaw=0, length=0.20,
            eye=dict(uv=(665 / 1024, 1 - 585 / 1024), radius=0.06, y_pick="min"), nudge=(0, 0, 0), drop_materials=[],
            paint={"Image_0": [(770, 20, 815, 125), (705, 15, 765, 165), (640, 30, 690, 115), (630, 110, 775, 365),
                               (800, 245, 875, 365), (180, 140, 240, 172), (355, 150, 385, 265), (300, 350, 335, 425),
                               (335, 465, 500, 525), (895, 415, 1024, 695), (0, 785, 65, 905), (195, 660, 365, 725),
                               (150, 100, 215, 150), (500, 580, 525, 600)]}),
    3: dict(name="camcorder_v2_cand3", uid="c26aa02a870c411a92628e624372d017", title="Panasonic NV-M50 VHS Video Camera",
            author="EmmyAngulo", yaw=180, length=0.28,
            eye=dict(xz_obj="Visor_Low_1002_0", y_obj="Visor_Low_1002_0", y_pick="max"), nudge=(0, 0, 0), drop_materials=[],
            paint={"Image_3": [(235, 15, 312, 330), (75, 525, 305, 630), (483, 262, 542, 320), (855, 740, 885, 770)],
                   "Image_0": [(878, 645, 925, 775), (880, 590, 915, 650)]}),
}


def inpaint(img, rects):
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rng = np.random.default_rng(7)
    for (x0, y0, x1, y1) in rects:
        r0, r1 = h - y1, h - y0  # top-down -> blender rows (bottom-up)
        pad = 8
        R0, R1, C0, C1 = max(r0 - pad, 0), min(r1 + pad, h), max(x0 - pad, 0), min(x1 + pad, w)
        blk = a[R0:R1, C0:C1, :3].copy()
        m = np.zeros(blk.shape[:2], bool)
        m[r0 - R0:r1 - R0, x0 - C0:x1 - C0] = True
        blk[m] = blk[~m].mean(axis=0)
        for _ in range(300):
            p = np.pad(blk, ((1, 1), (1, 1), (0, 0)), mode="edge")
            avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4
            blk[m] = avg[m]
        blk[m] += rng.normal(0, 0.004, blk[m].shape)
        a[R0:R1, C0:C1, :3] = np.clip(blk, 0, 1)
    img.pixels[:] = a.ravel()
    img.update()
    img.pack()


def bounds(ob):
    pts = [v.co for v in ob.data.vertices]
    return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))


def find_eye(meshes, spec):
    """Eyepiece back-opening centre in pre-yaw world coords (blender Z-up)."""
    if "uv" in spec:
        ob = meshes[0]
        uvl = ob.data.uv_layers.active.data
        u0, v0 = spec["uv"]
        vs = set()
        for poly in ob.data.polygons:
            for li in poly.loop_indices:
                u, v = uvl[li].uv
                if (u - u0) ** 2 + (v - v0) ** 2 < spec["radius"] ** 2:
                    vs.add(ob.data.loops[li].vertex_index)
        pts = [ob.matrix_world @ ob.data.vertices[i].co for i in vs]
        assert pts, "no verts near uv"
        x = sum(p.x for p in pts) / len(pts); z = sum(p.z for p in pts) / len(pts)
        y = (min if spec["y_pick"] == "min" else max)(p.y for p in pts)
        return Vector((x, y, z))
    def pts_of(sub):
        o = next(o for o in meshes if sub in o.name)
        return [o.matrix_world @ v.co for v in o.data.vertices]
    p = pts_of(spec["xz_obj"])
    x = (min(q.x for q in p) + max(q.x for q in p)) / 2; z = (min(q.z for q in p) + max(q.z for q in p)) / 2
    q = pts_of(spec["y_obj"])
    y = (min if spec["y_pick"] == "min" else max)(a.y for a in q)
    return Vector((x, y, z))


def process(k, job):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(CACHE / job["uid"] / "model.glb"))
    sc = bpy.context.scene
    meshes = [o for o in sc.objects if o.type == "MESH"]
    for o in sc.objects: o.select_set(False)
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    eye_pre = find_eye(meshes, job["eye"])
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for o in list(sc.objects):
        if o is not ob: bpy.data.objects.remove(o)
    ob.name = job["name"]
    tris_before = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if job["drop_materials"]:
        idx = [i for i, m in enumerate(ob.data.materials) if m and m.name in job["drop_materials"]]
        bm = bmesh.new(); bm.from_mesh(ob.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in idx], context="FACES")
        bm.to_mesh(ob.data); bm.free()
    ob.data.transform(Matrix.Rotation(math.radians(job["yaw"]), 4, "Z"))
    mn, mx = bounds(ob)
    s = job["length"] / (mx.y - mn.y)
    ob.data.transform(Matrix.Scale(s, 4))
    mn, mx = bounds(ob)
    eye = Matrix.Scale(s, 4) @ Matrix.Rotation(math.radians(job["yaw"]), 4, "Z") @ eye_pre + Vector(job["nudge"])
    ob.data.transform(Matrix.Translation(-eye))
    ob.data.update()
    for name, rects in job["paint"].items():
        inpaint(bpy.data.images[name], rects)
    for im in bpy.data.images:
        if im.name != "Render Result" and max(im.size) > 2048:
            im.scale(2048, 2048)
    used = {p.material_index for p in ob.data.polygons}
    mn, mx = bounds(ob)
    dst = OUT / f"{job['name']}.glb"
    for o in sc.objects: o.select_set(o is ob)
    bpy.ops.export_scene.gltf(filepath=str(dst), export_format="GLB", export_yup=True, export_apply=True, use_selection=True)
    st = dict(glb=str(dst.relative_to(ROOT)).replace("\\", "/"), source_uid=job["uid"], title=job["title"], author=job["author"],
              tris_before=tris_before, tris=sum(len(p.vertices) - 2 for p in ob.data.polygons), scale=round(s, 5),
              gltf_min=[round(mn.x, 3), round(mn.z, 3), round(-mx.y, 3)], gltf_max=[round(mx.x, 3), round(mx.z, 3), round(-mn.y, 3)],
              dims_m=[round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)],
              materials=[m.name for i, m in enumerate(ob.data.materials) if m and i in used],
              textures=[(i.name, list(i.size)) for i in bpy.data.images if i.users and i.name != "Render Result"],
              yaw=job["yaw"], eye_spec=job["eye"], nudge=job["nudge"], dropped=job["drop_materials"],
              painted={k_: len(v) for k_, v in job["paint"].items()})
    print("RESULT", k, json.dumps(st))
    return st


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = int(a[a.index("--only") + 1]) if "--only" in a else None
    stats = json.loads(STATS.read_text()) if STATS.exists() else {}
    for k, job in JOBS.items():
        if only and k != only: continue
        stats[job["name"]] = process(k, job)
    STATS.parent.mkdir(parents=True, exist_ok=True)
    STATS.write_text(json.dumps(stats, indent=1))


main()
