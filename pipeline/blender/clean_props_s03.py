"""S03 field-team props (a tape-duplication survey crew's leftovers), cleaned from Sketchfab CC0/CC-BY models.
  blender -b -P pipeline/blender/clean_props_s03.py -- build        # export all GLBs to game/assets/props/level0
  blender -b -P pipeline/blender/clean_props_s03.py -- preview      # re-import each GLB, render pipeline/blender/previews/_fp_<name>.png
Assets (all meters, Y-up glTF, origin bottom-center, front/lamp face toward +Z):
  prop_tripod_sf            tripod legs only (the camera that came with the Sketchfab model is dropped)
  prop_tripod_camcorder     same tripod + game camcorder (game/assets/props/player/camcorder.glb) on the head, lens +Z
  prop_vhs_tape_sf          one VHS cassette 187 x 103 x 25 mm lying flat, long edge along X
  prop_tape_crate           milk-crate with 10 cassettes standing in a row (built here from the two models above)
  prop_worklight_sf         twin halogen head work light on a yellow tripod, lamp faces +Z
  prop_worklight_box_sf     single halogen box work light with wire guard, lamp face +Z
Stats (tris, dims, lamp face positions) -> pipeline/blender/previews/props_s03_stats.json
"""
import bpy, sys, json, math, random
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "pipeline/meshes/sketchfab_cache"
OUT = ROOT / "game/assets/props/level0"
PREV = ROOT / "pipeline/blender/previews"
CAMC = ROOT / "game/assets/props/player/camcorder.glb"
STATS = {}


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
    """Keep meshes, bake world transforms into them, drop everything else, join. Returns the single mesh."""
    meshes = [o for o in objs if o.type == "MESH" and o.name in bpy.data.objects]
    for o in objs:
        if o not in meshes and o.name in bpy.data.objects: bpy.data.objects.remove(o)
    select(meshes)
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
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


def glass_info(o, key):
    """Faces whose material name contains `key`: area-weighted normal and vertex set (Blender coords)."""
    idx = [i for i, m in enumerate(o.data.materials) if m and key in m.name.lower()]
    n = Vector(); vs = []
    for p in o.data.polygons:
        if p.material_index in idx:
            n += p.normal * p.area
            vs += [o.data.vertices[i].co.copy() for i in p.vertices]
    return n.normalized(), vs


def yaw_face_to_neg_y(o, n):
    """Rotate mesh so that horizontal direction n points to -Y (Blender) = +Z glTF."""
    a = math.atan2(n.y, n.x)
    xform(o, Matrix.Rotation(-math.pi / 2 - a, 4, "Z"))
    return math.degrees(-math.pi / 2 - a)


def scale_to(o, axis, val):
    mn, mx = bounds(o)
    s = val / (mx - mn)["xyz".index(axis)]
    xform(o, Matrix.Scale(s, 4))
    return s


def ground_center(o, center=None):
    mn, mx = bounds(o)
    c = center if center is not None else Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, 0))
    xform(o, Matrix.Translation((-c.x, -c.y, -mn.z)))


def clamp_textures(maxs=2048):
    for im in bpy.data.images:
        if im.size[0] > maxs or im.size[1] > maxs:
            im.scale(min(im.size[0], maxs), min(im.size[1], maxs))


def export(name, objs):
    select(objs)
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / f"{name}.glb"
    bpy.ops.export_scene.gltf(filepath=str(dst), export_format="GLB", export_yup=True, use_selection=True, export_apply=True)
    return str(dst.relative_to(ROOT)).replace("\\", "/")


def to_gltf(v):  # Blender Z-up -> glTF Y-up
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


def stat(name, o, glb, **kw):
    mn, mx = bounds(o)
    d = mx - mn
    STATS[name] = dict(glb=glb, tris=tris(o), dims_m_xyz_yup=[round(d.x, 3), round(d.z, 3), round(d.y, 3)],
                       textures=[(i.name, list(i.size)) for i in bpy.data.images if i.users and i.name != "Render Result"], **kw)
    print("RESULT", name, json.dumps(STATS[name]))


# ---------------------------------------------------------------- assets
def foot_yaw(o):
    """Rotate so the lowest leg tip points toward -Y (one tripod leg forward, toward +Z glTF)."""
    p = pts(o); low = min(p, key=lambda q: q.z)
    cx = sum(q.x for q in p) / len(p); cy = sum(q.y for q in p) / len(p)
    a = math.atan2(low.y - cy, low.x - cx)
    xform(o, Matrix.Rotation(-math.pi / 2 - a, 4, "Z"))
    return math.degrees(-math.pi / 2 - a)


def build_tripod():
    reset()
    objs = imp(src("cc324baf6dc548de965c3a47b87f1e27"))
    keep = [o for o in objs if o.type == "MESH" and o.data.materials and o.data.materials[0].name == "hitam"]
    for o in objs:
        if o not in keep and o.name in bpy.data.objects: bpy.data.objects.remove(o)
    t = flatten(keep); t.name = "prop_tripod_sf"
    yaw = foot_yaw(t)
    s = scale_to(t, "z", 1.5)
    ground_center(t)
    clamp_textures()
    glb = export("prop_tripod_sf", [t])
    stat("prop_tripod_sf", t, glb, yaw_deg=round(yaw, 1), scale=round(s, 5), uid="cc324baf6dc548de965c3a47b87f1e27")
    top = bounds(t)[1].z
    # --- camcorder on the head (re-import the cleaned tripod to keep it independent)
    cam = flatten(imp(CAMC)); cam.name = "camcorder"
    xform(cam, Matrix.Rotation(math.pi, 4, "Z"))             # lens +Y (-Z glTF) -> -Y Blender (+Z glTF)
    mn, mx = bounds(cam)
    # centre the body over the head: x on the bbox centre, y on the body (not the lens barrel) centre
    xform(cam, Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2 + 0.0, top - mn.z - 0.005)))
    cam.name = "camcorder"
    j = flatten([t, cam]); j.name = "prop_tripod_camcorder"
    glb = export("prop_tripod_camcorder", [j])
    stat("prop_tripod_camcorder", j, glb, camcorder_bottom_on_tripod_top_m=round(top, 3))


def build_vhs():
    reset()
    o = flatten(imp(src("92de31c367ca4f5794f8fb12dce68111"))); o.name = "prop_vhs_tape_sf"
    mn, mx = bounds(o); d = mx - mn
    if d.x < d.y: xform(o, Matrix.Rotation(math.pi / 2, 4, "Z"))   # long edge along X
    s = scale_to(o, "x", 0.187)
    mn, mx = bounds(o); d = mx - mn
    if d.z > d.y: xform(o, Matrix.Rotation(math.pi / 2, 4, "X"))   # lie flat: thinnest axis (25 mm) vertical
    ground_center(o)
    clamp_textures()
    glb = export("prop_vhs_tape_sf", [o])
    stat("prop_vhs_tape_sf", o, glb, scale=round(s, 5), uid="92de31c367ca4f5794f8fb12dce68111")
    return o


def build_crate():
    reset()
    crate = flatten(imp(src("7b9426222f0c4838bfbc13850095bb3f"))); crate.name = "crate"
    mn, mx = bounds(crate)
    if (mx - mn).z > (mx - mn).x:  # sanity: z should be the shorter axis for a milk crate
        pass
    s = scale_to(crate, "x", 0.37)
    ground_center(crate)
    cmn, cmx = bounds(crate)
    # one cassette source, imported fresh
    base = flatten(imp(OUT / "prop_vhs_tape_sf.glb")); base.name = "tape"
    xform(base, Matrix.Rotation(math.pi / 2, 4, "Y"))   # long edge vertical (187 tall), thickness along X
    bmn, bmx = bounds(base)
    xform(base, Matrix.Translation((-(bmn.x + bmx.x) / 2, -(bmn.y + bmx.y) / 2, -bmn.z)))
    th = bmx.x - bmn.x; wid = bmx.y - bmn.y; hh = bmx.z - bmn.z
    rnd = random.Random(1996)
    inner_floor = 0.012          # milk crate floor thickness
    parts = [crate]
    n = 10
    x0 = -(n - 1) * (th * 1.04) / 2
    for i in range(n):
        t = base.copy(); t.data = base.data.copy(); bpy.context.scene.collection.objects.link(t)
        lean = math.radians(rnd.uniform(-5, 5)) if i not in (0, n - 1) else math.radians(-9 if i == 0 else 9)
        lift = rnd.choice([0, 0, 0.006, 0.02, 0.045]) if i not in (0, n - 1) else 0
        dy = rnd.uniform(-0.012, 0.012)
        t.matrix_world = Matrix.Translation((x0 + i * th * 1.04, dy, inner_floor + lift)) @ Matrix.Rotation(lean, 4, "Y")
        parts.append(t)
    bpy.data.objects.remove(base)
    # bake and join (the cassette material is shared, textures are embedded once)
    for p in parts:
        select([p]); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    j = flatten(parts); j.name = "prop_tape_crate"
    clamp_textures()
    glb = export("prop_tape_crate", [j])
    stat("prop_tape_crate", j, glb, crate_scale=round(s, 5), crate_uid="7b9426222f0c4838bfbc13850095bb3f",
         cassette_uid="92de31c367ca4f5794f8fb12dce68111", cassettes=n, cassette_height_m=round(hh, 3))


def build_worklight(name, uid, glass_key, height, clusters, center_mode):
    reset()
    o = flatten(imp(src(uid))); o.name = name
    n, vs = glass_info(o, glass_key)
    nh = Vector((n.x, n.y, 0)).normalized()
    yaw = yaw_face_to_neg_y(o, nh)
    s = scale_to(o, "z", height)
    # xy centre on the stand, not the cable: median xy of the mid-height vertices (tripod) or bbox centre (box)
    mn, mx = bounds(o)
    if center_mode == "pole":
        h = mx.z - mn.z
        mid = [q for q in pts(o) if mn.z + 0.25 * h < q.z < mn.z + 0.55 * h]
        xs = sorted(q.x for q in mid); ys = sorted(q.y for q in mid)
        c = Vector((xs[len(xs) // 2], ys[len(ys) // 2], 0))
    else:
        c = None
    ground_center(o, c)
    clamp_textures()
    # lamp face positions (glass faces) after all transforms
    n2, vs2 = glass_info(o, glass_key)
    vs2 = [v for v in vs2]
    lamps = []
    if clusters == 1:
        groups = [vs2]
    else:
        xs = sorted(v.x for v in vs2); mid = (xs[0] + xs[-1]) / 2
        groups = [[v for v in vs2 if v.x < mid], [v for v in vs2 if v.x >= mid]]
    for g in groups:
        ctr = sum(g, Vector()) / len(g)
        lamps.append(to_gltf(ctr))
    glb = export(name, [o])
    nn = n2
    stat(name, o, glb, yaw_deg=round(yaw, 1), scale=round(s, 5), uid=uid,
         lamp_face_centers_m_xyz_yup=lamps, lamp_normal_xyz_yup=[round(nn.x, 3), round(nn.z, 3), round(-nn.y, 3)],
         origin="bottom center of the stand/body, lamps face +Z")


# ---------------------------------------------------------------- preview
def preview_one(name, path):
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
    co.location = ctr + Vector((0.55, -0.85, 0.35)) * size * 1.75  # front is -Y Blender (= +Z glTF), 3/4 from the right
    t = bpy.data.objects.new("t", None); t.location = ctr; sc.collection.objects.link(t)
    tr = co.constraints.new("TRACK_TO"); tr.target = t; tr.track_axis = "TRACK_NEGATIVE_Z"; tr.up_axis = "UP_Y"
    sc.render.engine = "CYCLES"; sc.cycles.samples = 48; sc.cycles.device = "CPU"
    sc.render.resolution_x = sc.render.resolution_y = 560
    PREV.mkdir(parents=True, exist_ok=True)
    sc.render.filepath = str(PREV / f"_fp_{name}.png")
    bpy.ops.render.render(write_still=True)


NAMES = ["prop_tripod_sf", "prop_tripod_camcorder", "prop_vhs_tape_sf", "prop_tape_crate", "prop_worklight_sf", "prop_worklight_box_sf"]


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    sp = PREV / "props_s03_stats.json"
    if a[0] == "build":
        build_tripod(); build_vhs(); build_crate()
        build_worklight("prop_worklight_sf", "ff0abe17dc64498191bb41c905d00ab0", "transparent", 1.75, 2, "pole")
        build_worklight("prop_worklight_box_sf", "278dd26f90d544a8941d347bef0ebf40", "glass", 0.40, 1, "bbox")
        PREV.mkdir(parents=True, exist_ok=True)
        sp.write_text(json.dumps(STATS, indent=1))
    else:
        for n in (a[1:] or NAMES): preview_one(n, OUT / f"{n}.glb")


main()
