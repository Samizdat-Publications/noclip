"""S03b office leftovers (break up the long identical stretches), cleaned from Sketchfab CC0/CC-BY models.
  blender -b -P pipeline/blender/clean_props_s03b.py -- build            # export all GLBs to game/assets/props/level0
  blender -b -P pipeline/blender/clean_props_s03b.py -- preview [names]  # 3/4 renders of the exported GLBs -> previews/_fp_<name>.png
  blender -b -P pipeline/blender/clean_props_s03b.py -- views name       # 4 side views (front, +X, back, -X) -> previews/_v_<name>_<k>.png
Then: python pipeline/blender/props_s03b_sheet.py   -> previews/props_s03b.png (labeled sheet)
All outputs: meters, Y-up glTF, origin bottom-center, front (the side a person uses) toward +Z, transforms applied, merged.
  prop_water_cooler_sf   bottle-top water cooler with a dirty jug
  prop_filing_cabinet_sf 4-drawer steel cabinet, rusty, drawers left at different heights
  prop_step_ladder_sf    aluminium step ladder standing open (climbing side +Z)
  prop_mop_bucket_sf     janitor bucket with wringer and a flat mop leaning in it
  prop_cubicle_panel_sf  two fabric partition panels (1.47 x 1.5 m) on feet, cut from a cubicle set
  prop_office_desk_sf    worn wooden desk with two drawer pedestals, kneehole toward +Z
  prop_stack_chairs_sf   five aged plastic armchairs nested in a stack (built here from one chair model)
Stats (tris, dims) -> pipeline/blender/previews/props_s03b_stats.json
"""
import bpy, bmesh, sys, json, math, random
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "pipeline/meshes/sketchfab_cache"
OUT = ROOT / "game/assets/props/level0"
PREV = ROOT / "pipeline/blender/previews"
STATS = {}

U_COOLER = "52946497074c4c669d620ce5f431a3da"
U_CABINET = "619484b78fbe449ea5c0cdb68e8f2bd6"
U_LADDER = "670ef4373d544ea5ab577ef00161ffc3"
U_BUCKET = "54a8250e1de8426e9cf2bf35fd099a10"
U_MOP = "420bddb8730c4e3aa7653e5f7c5a5a7c"
U_CUBICLE = "18abda12d33b4231aa13f92a291c717e"
U_DESK = "2039a113435b47d585b2c51e4f3a096d"
U_CHAIR = "4a92b3b9964c446cb5ec9eff053d830c"

# yaw (degrees about Blender Z) applied after import so the front ends up at -Y Blender (= +Z glTF).
# Found by looking at the four-view renders (views mode).
YAW = dict(ladder=90.0, desk=0.0, bucket=0.0, cabinet=0.0)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def imp(path):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.context.scene.objects if o not in before]


def src(uid):
    return next((CACHE / uid).glob("*.glb"))


def select(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def flatten(objs):
    meshes = [o for o in objs if o.type == "MESH" and o.name in bpy.data.objects]
    select(meshes)
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")   # before deleting the empties: they carry the unit scale
    for o in objs:
        if o not in meshes and o.name in bpy.data.objects: bpy.data.objects.remove(o)
    select(meshes)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1: bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def pts(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def bounds(o):
    p = pts(o)
    return (Vector((min(q.x for q in p), min(q.y for q in p), min(q.z for q in p))),
            Vector((max(q.x for q in p), max(q.y for q in p), max(q.z for q in p))))


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def xform(o, M):
    o.data.transform(M)
    o.data.update()


def scale_to(o, axis, val):
    mn, mx = bounds(o)
    s = val / (mx - mn)["xyz".index(axis)]
    xform(o, Matrix.Scale(s, 4))
    return s


def ground_center(o, center=None):
    mn, mx = bounds(o)
    c = center if center is not None else Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, 0))
    xform(o, Matrix.Translation((-c.x, -c.y, -mn.z)))


def yaw(o, deg):
    xform(o, Matrix.Rotation(math.radians(deg), 4, "Z"))


def face_dir_to_neg_y(o, d):
    """Rotate so horizontal direction d points to -Y Blender (= +Z glTF). Returns degrees applied."""
    a = math.atan2(d.y, d.x)
    ang = -math.pi / 2 - a
    xform(o, Matrix.Rotation(ang, 4, "Z"))
    return math.degrees(ang)


def mat_verts_centroid(o, key):
    idx = [i for i, m in enumerate(o.data.materials) if m and key in m.name.lower()]
    vs = []
    for p in o.data.polygons:
        if p.material_index in idx:
            vs += [o.data.vertices[i].co.copy() for i in p.vertices]
    return sum(vs, Vector()) / len(vs)


def clamp_textures(maxs=1024):
    for im in bpy.data.images:
        if im.name != "Render Result" and (im.size[0] > maxs or im.size[1] > maxs):
            im.scale(min(im.size[0], maxs), min(im.size[1], maxs))


def purge():
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)


def export(name, objs):
    select(objs)
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / f"{name}.glb"
    bpy.ops.export_scene.gltf(filepath=str(dst), export_format="GLB", export_yup=True, use_selection=True, export_apply=True)
    return str(dst.relative_to(ROOT)).replace("\\", "/")


def stat(name, o, glb, **kw):
    mn, mx = bounds(o)
    d = mx - mn
    STATS[name] = dict(glb=glb, tris=tris(o), dims_m_xyz_yup=[round(d.x, 3), round(d.z, 3), round(d.y, 3)],
                       textures=[(i.name, list(i.size)) for i in bpy.data.images if i.users and i.name != "Render Result"], **kw)
    print("RESULT", name, json.dumps({k: v for k, v in STATS[name].items() if k != "textures"}))


# ---------------------------------------------------------------- assets
def build_cooler():
    reset()
    o = flatten(imp(src(U_COOLER))); o.name = "prop_water_cooler_sf"
    spouts = mat_verts_centroid(o, "water_spouts")
    mn, mx = bounds(o); c = (mn + mx) / 2
    a = face_dir_to_neg_y(o, Vector((spouts.x - c.x, spouts.y - c.y, 0)))
    s = scale_to(o, "z", 1.38)
    ground_center(o); clamp_textures()
    glb = export("prop_water_cooler_sf", [o])
    stat("prop_water_cooler_sf", o, glb, yaw_deg=round(a, 1), scale=round(s, 5), uid=U_COOLER)


def build_cabinet():
    reset()
    objs = imp(src(U_CABINET))
    body = next(o for o in objs if o.type == "MESH" and "cabinet_low" in o.name)
    bmn, bmx = bounds(body)
    o = flatten(objs); o.name = "prop_filing_cabinet_sf"
    yaw(o, YAW["cabinet"])
    # body-centered origin (the open drawers must not pull the origin)
    ctr = Vector(((bmn.x + bmx.x) / 2, (bmn.y + bmx.y) / 2, 0))
    if YAW["cabinet"]:
        ctr = Matrix.Rotation(math.radians(YAW["cabinet"]), 3, "Z") @ ctr
    mn, mx = bounds(o)
    s = 1.32 / (mx.z - mn.z)
    xform(o, Matrix.Scale(s, 4)); ctr *= s
    ground_center(o, ctr); clamp_textures()
    glb = export("prop_filing_cabinet_sf", [o])
    stat("prop_filing_cabinet_sf", o, glb, scale=round(s, 6), yaw_deg=YAW["cabinet"], uid=U_CABINET,
         origin="center of the cabinet body, bottom; bbox is deeper because drawers are left open")


def build_ladder():
    reset()
    o = flatten(imp(src(U_LADDER))); o.name = "prop_step_ladder_sf"
    # model is the A-frame along X; yaw so the climbing side faces -Y
    yaw(o, YAW["ladder"])
    s = scale_to(o, "z", 1.55)
    ground_center(o); clamp_textures()
    glb = export("prop_step_ladder_sf", [o])
    stat("prop_step_ladder_sf", o, glb, scale=round(s, 6), yaw_deg=YAW["ladder"], uid=U_LADDER)


def build_bucket():
    reset()
    # drop the cones: keep only the bucket object
    objs = imp(src(U_BUCKET))
    for o in list(objs):
        if o.type == "MESH" and "MopBucket" not in o.name:
            bpy.data.objects.remove(o); objs.remove(o)
    b = flatten([o for o in objs if o.name in bpy.data.objects]); b.name = "bucket"
    yaw(b, YAW["bucket"])
    s = 0.8
    xform(b, Matrix.Scale(s, 4))
    ground_center(b)
    bmn, bmx = bounds(b)
    # mop: leaning in the bucket, head down inside, handle toward the back (+Y Blender)
    m = flatten(imp(src(U_MOP))); m.name = "mop"
    ms = 1.30 / (bounds(m)[1].z - bounds(m)[0].z)
    xform(m, Matrix.Scale(ms, 4))
    mmn, mmx = bounds(m)
    xform(m, Matrix.Translation((-(mmn.x + mmx.x) / 2, -(mmn.y + mmx.y) / 2, -mmn.z)))
    lean = math.radians(MOP_LEAN)
    M = Matrix.Translation((MOP_X, MOP_Y, MOP_Z)) @ Matrix.Rotation(-lean, 4, "X")
    xform(m, M)
    j = flatten([b, m]); j.name = "prop_mop_bucket_sf"
    ground_center(j, Vector(((bmn.x + bmx.x) / 2, (bmn.y + bmx.y) / 2, 0)))
    clamp_textures()
    glb = export("prop_mop_bucket_sf", [j])
    stat("prop_mop_bucket_sf", j, glb, bucket_scale=round(s, 4), mop_scale=round(ms, 6), yaw_deg=YAW["bucket"],
         uid_bucket=U_BUCKET, uid_mop=U_MOP, origin="bottom center of the bucket body; mop handle leans out the back")


MOP_LEAN = 22.0
MOP_X, MOP_Y, MOP_Z = 0.0, 0.0, 0.12


def build_cubicle():
    reset()
    objs = imp(src(U_CUBICLE))
    keep = next(o for o in objs if o.type == "MESH" and o.name.startswith("02"))
    select([keep]); bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for o in list(objs):
        if o is not keep and o.name in bpy.data.objects: bpy.data.objects.remove(o)
    select([keep]); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new(); bm.from_mesh(keep.data)
    kill = []
    for f in bm.faces:
        ok = all(-2.45 <= v.co.y <= -2.39 and -1.85 <= v.co.x <= 0.80 for v in f.verts)
        if not ok: kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    lone = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=lone, context="VERTS")
    # the source atlas maps the back side to bare wood; put every big (+-Y) face on the blue-grey fabric patch of the atlas
    uvl = bm.loops.layers.uv.active
    for f in bm.faces:
        if abs(f.normal.y) > 0.9:
            for l in f.loops:
                l[uvl].uv = (0.53 + 0.25 * (l.vert.co.x + 1.796) / 2.592, 0.08 + 0.50 * l.vert.co.z / 2.65)
    bm.to_mesh(keep.data); bm.free()
    purge()
    # fabric is rough and non-metal: drop the packed ORM texture (it reads as frosted glass), use constants
    for m in keep.data.materials:
        nt = m.node_tree; pb = nt.nodes["Principled BSDF"]
        for k in ("Roughness", "Metallic"):
            for lk in list(pb.inputs[k].links): nt.links.remove(lk)
        pb.inputs["Roughness"].default_value = 0.93; pb.inputs["Metallic"].default_value = 0.0
        # the fabric patch is near-white; knock it down to a faded 90s grey (multiply the atlas by 0.74)
        bc = pb.inputs["Base Color"].links
        if bc and bc[0].from_node.type == "TEX_IMAGE":
            im = bc[0].from_node.image
            import numpy as np
            a = np.empty(len(im.pixels), dtype=np.float32); im.pixels.foreach_get(a)
            a = a.reshape(-1, 4); a[:, :3] *= 0.74
            im.pixels.foreach_set(a.ravel()); im.pack()
    o = keep; o.name = "panel"
    mn, mx = bounds(o)
    s = 1.5 / (mx.z - mn.z)
    xform(o, Matrix.Scale(s, 4))
    # panel plane is Y=const; wide along X. Face -Y (front) already.
    mn, mx = bounds(o)
    ground_center(o)
    mn, mx = bounds(o)
    # T feet at both ends
    fm = bpy.data.materials.new("panel_feet"); fm.use_nodes = True
    bsdf = fm.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.07, 0.07, 0.075, 1); bsdf.inputs["Roughness"].default_value = 0.55; bsdf.inputs["Metallic"].default_value = 0.6
    feet = []
    for x in (mn.x + 0.06, mx.x - 0.06):
        bpy.ops.mesh.primitive_cube_add(size=1)
        f = bpy.context.active_object
        f.scale = (0.045, 0.52, 0.03); f.location = (x, 0, 0.015)
        f.data.materials.append(fm); feet.append(f)
    select(feet); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    j = flatten([o] + feet); j.name = "prop_cubicle_panel_sf"
    ground_center(j); clamp_textures()
    glb = export("prop_cubicle_panel_sf", [j])
    stat("prop_cubicle_panel_sf", j, glb, scale=round(s, 6), uid=U_CUBICLE,
         note="two adjacent back-wall panel units cut out of the cubicle set (faces by bbox), plus two T feet built here")


def build_desk():
    reset()
    o = flatten(imp(src(U_DESK))); o.name = "prop_office_desk_sf"
    yaw(o, YAW["desk"])
    mn, mx = bounds(o); d = mx - mn
    # raw proportions are a low executive desk; stretch to office-desk proportions (non-uniform)
    sx, sy, sz = 1.60 / d.x, 0.80 / d.y, 0.75 / d.z
    xform(o, Matrix.Diagonal((sx, sy, sz, 1)))
    ground_center(o); clamp_textures()
    glb = export("prop_office_desk_sf", [o])
    stat("prop_office_desk_sf", o, glb, scale_xyz=[round(sx, 4), round(sy, 4), round(sz, 4)], yaw_deg=YAW["desk"], uid=U_DESK)


def overlap_count(a_obj, bvh_a, M):
    me = a_obj.data
    verts = [M @ v.co for v in me.vertices]
    bvh_b = BVHTree.FromPolygons(verts, [tuple(p.vertices) for p in me.polygons])
    return len(bvh_a.overlap(bvh_b))


def build_stack():
    reset()
    c = flatten(imp(src(U_CHAIR))); c.name = "chair"
    mn, mx = bounds(c); h = mx.z - mn.z; ctr = (mn + mx) / 2
    top = [q for q in pts(c) if q.z > mn.z + 0.88 * h]
    tc = sum(top, Vector()) / len(top)
    back = Vector((tc.x - ctr.x, tc.y - ctr.y, 0))
    a = face_dir_to_neg_y(c, -back)       # front = away from the backrest top
    ground_center(c)
    verts0 = [v.co.copy() for v in c.data.vertices]
    polys = [tuple(p.vertices) for p in c.data.polygons]
    bvh0 = BVHTree.FromPolygons(verts0, polys)
    # find the lowest nesting pitch with (almost) no interpenetration, trying a few forward/back shifts
    best = None
    for dy in (0.0, 0.03, 0.06, 0.09, -0.03, -0.06):
        for dz in [0.04 + 0.005 * i for i in range(0, 90)]:
            n = overlap_count(c, bvh0, Matrix.Translation((0, dy, dz)))
            if n <= 2:
                if best is None or dz < best[0]: best = (dz, dy, n)
                break
    print("NEST", best)
    dz, dy, _ = best
    rnd = random.Random(1996)
    N = 5
    parts = []
    for i in range(N):
        t = c.copy(); t.data = c.data.copy(); bpy.context.scene.collection.objects.link(t)
        jy = rnd.uniform(-0.008, 0.008) if i else 0.0
        jx = rnd.uniform(-0.012, 0.012) if i else 0.0
        ang = math.radians(rnd.uniform(-2.2, 2.2)) if i else 0.0
        t.matrix_world = Matrix.Translation((jx, i * dy + jy, i * dz)) @ Matrix.Rotation(ang, 4, "Z")
        parts.append(t)
    bpy.data.objects.remove(c)
    for p in parts:
        select([p]); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    j = flatten(parts); j.name = "prop_stack_chairs_sf"
    ground_center(j); clamp_textures()
    glb = export("prop_stack_chairs_sf", [j])
    stat("prop_stack_chairs_sf", j, glb, yaw_deg=round(a, 1), chairs=N, pitch_up_m=round(dz, 3), pitch_back_m=round(dy, 3), uid=U_CHAIR)


# ---------------------------------------------------------------- preview
def setup_scene(path):
    reset()
    objs = imp(path)
    sc = bpy.context.scene
    meshes = [o for o in objs if o.type == "MESH"]
    p = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    mn = Vector((min(q.x for q in p), min(q.y for q in p), min(q.z for q in p)))
    mx = Vector((max(q.x for q in p), max(q.y for q in p), max(q.z for q in p)))
    ctr = (mn + mx) / 2; size = max((mx - mn).length, 0.2)
    w = bpy.data.worlds.new("w"); w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.5, 0.5, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.world = w
    gm = bpy.data.materials.new("floor"); gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.33, 0.28, 1)
    bpy.ops.mesh.primitive_plane_add(size=8); bpy.context.active_object.data.materials.append(gm)
    l = bpy.data.lights.new("k", "AREA"); l.energy = 300 * max(size, 0.5) ** 2; l.size = 2
    lo = bpy.data.objects.new("k", l); lo.location = ctr + Vector((1.2, -1.5, 2.2)) * max(size, 0.6) / 1.5
    lo.rotation_euler = (math.radians(35), 0, math.radians(25)); sc.collection.objects.link(lo)
    cam = bpy.data.cameras.new("c"); cam.lens = 50
    co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
    t = bpy.data.objects.new("t", None); t.location = ctr; sc.collection.objects.link(t)
    tr = co.constraints.new("TRACK_TO"); tr.target = t; tr.track_axis = "TRACK_NEGATIVE_Z"; tr.up_axis = "UP_Y"
    sc.render.engine = "CYCLES"; sc.cycles.samples = 48; sc.cycles.device = "CPU"
    sc.render.resolution_x = sc.render.resolution_y = 560
    return sc, co, ctr, size


def preview_one(name, path):
    sc, co, ctr, size = setup_scene(path)
    co.location = ctr + Vector((0.55, -0.85, 0.35)) * size * 1.75  # front is -Y Blender (= +Z glTF), 3/4 from the right
    PREV.mkdir(parents=True, exist_ok=True)
    sc.render.filepath = str(PREV / f"_fp_{name}.png")
    bpy.ops.render.render(write_still=True)


def views_one(name, path):
    sc, co, ctr, size = setup_scene(path)
    sc.cycles.samples = 24; sc.render.resolution_x = sc.render.resolution_y = 400
    for k, (dx, dy) in enumerate([(0.2, -1.0), (1.0, 0.0), (0.2, 1.0), (-1.0, 0.0)]):
        co.location = ctr + Vector((dx, dy, 0.3)) * size * 1.6
        sc.render.filepath = str(PREV / f"_v_{name}_{k}.png")
        bpy.ops.render.render(write_still=True)


NAMES = ["prop_water_cooler_sf", "prop_filing_cabinet_sf", "prop_step_ladder_sf", "prop_mop_bucket_sf",
         "prop_cubicle_panel_sf", "prop_office_desk_sf", "prop_stack_chairs_sf"]


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    sp = PREV / "props_s03b_stats.json"
    if a[0] == "build":
        only = a[1:]
        fns = dict(prop_water_cooler_sf=build_cooler, prop_filing_cabinet_sf=build_cabinet, prop_step_ladder_sf=build_ladder,
                   prop_mop_bucket_sf=build_bucket, prop_cubicle_panel_sf=build_cubicle, prop_office_desk_sf=build_desk,
                   prop_stack_chairs_sf=build_stack)
        old = json.loads(sp.read_text()) if sp.exists() else {}
        for n, f in fns.items():
            if not only or n in only: f()
        old.update(STATS)
        PREV.mkdir(parents=True, exist_ok=True)
        sp.write_text(json.dumps(old, indent=1))
    elif a[0] == "preview":
        for n in (a[1:] or NAMES): preview_one(n, OUT / f"{n}.glb")
    elif a[0] == "views":
        for n in a[1:]: views_one(n, OUT / f"{n}.glb")


main()
