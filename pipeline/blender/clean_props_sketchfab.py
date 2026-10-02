"""Headless cleanup + preview for Sketchfab-sourced Level 0 props.
blender -b -P pipeline/blender/clean_props_sketchfab.py -- --job name:uid:yaw_deg:tris:drive[:suffix] [--job ...] [--candidate]
  drive = h=0.38 | w=0.38 | d=0.42  (which real-world axis fixes the uniform scale: height, width(x), depth(y), meters;
          axes are measured in Blender Z-up space after yaw: x = width, y = depth, z = height)
  yaw_deg rotates about vertical so the front faces +Z in the exported (Y-up) glTF (= -Y in Blender).
  suffix defaults to _sf. With --candidate nothing is exported; only a preview goes to
  pipeline/meshes/sketchfab_cache/_candidates (used to pick model and yaw before the real export).
Steps: import, join meshes, apply transforms, yaw, uniform scale to meters, origin at bottom center (y=0),
decimate to budget, clamp textures to 2048, export GLB with embedded textures, Cycles 64spp preview 1024x1024.
Stats go to pipeline/meshes/sketchfab_cache/clean_stats.json.
"""
import bpy, sys, json, math
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "pipeline/meshes/sketchfab_cache"
OUT = ROOT / "game/assets/props/level0"
PREV = ROOT / "pipeline/meshes/previews"


def parse():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    jobs, cand = [], False
    for i, t in enumerate(a):
        if t == "--job": jobs.append(a[i + 1].split(":"))
        if t == "--candidate": cand = True
    return jobs, cand


def bounds(objs):
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]  # from vertices: bound_box can be stale
    return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))


def tri_count(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    m = obj.evaluated_get(dg).to_mesh()
    n = sum(len(p.vertices) - 2 for p in m.polygons)
    obj.evaluated_get(dg).to_mesh_clear()
    return n


def process(name, uid, yaw, tris, drive, suffix, cand):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = next((CACHE / uid).glob("*.glb"))
    bpy.ops.import_scene.gltf(filepath=str(src))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects: o.select_set(False)
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1: bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    for o in list(bpy.context.scene.objects):
        if o is not obj and o.type != "MESH": bpy.data.objects.remove(o)
    obj.name = name
    obj.data.transform(Matrix.Rotation(math.radians(float(yaw)), 4, "Z"))
    mn, mx = bounds([obj]); raw = mx - mn
    ax, val = drive.split("="); val = float(val)
    s = val / {"h": raw.z, "w": raw.x, "d": raw.y}[ax]
    obj.data.transform(Matrix.Scale(s, 4))
    mn, mx = bounds([obj])
    obj.data.transform(Matrix.Translation(-Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))))
    bpy.context.view_layer.update()
    before = tri_count(obj)
    if before > tris:
        mod = obj.modifiers.new("dec", "DECIMATE"); mod.ratio = tris / before
        bpy.ops.object.modifier_apply(modifier=mod.name)
    after = tri_count(obj)
    for img in bpy.data.images:
        if img.size[0] > 2048 or img.size[1] > 2048:
            img.scale(min(img.size[0], 2048), min(img.size[1], 2048))
    mn, mx = bounds([obj]); d = mx - mn
    vz = [v.co.z for v in obj.data.vertices]
    print("DEBUG minz", mn.z, min(vz), "loc", tuple(obj.location), "tris", after)
    stats = dict(uid=uid, tris_before=before, tris_after=after, raw_dims_blender_xyz=[round(v, 3) for v in raw],
                 dims_m=dict(x=round(d.x, 3), y_up=round(d.z, 3), z=round(d.y, 3)), yaw=float(yaw), drive=drive,
                 textures=[(i.name, list(i.size)) for i in bpy.data.images if i.users and i.name != "Render Result"])
    if not cand:
        OUT.mkdir(parents=True, exist_ok=True)
        dst = OUT / f"{name}{suffix}.glb"
        bpy.ops.export_scene.gltf(filepath=str(dst), export_format="GLB", export_yup=True, export_apply=True,
                                  use_selection=False)
        stats["glb"] = str(dst.relative_to(ROOT)).replace("\\", "/")
        pp = PREV / f"{name}{suffix}.png"
    else:
        pp = CACHE / "_candidates" / f"{name}_{uid[:6]}.png"
    preview(obj, pp)
    return stats


def preview(obj, path):
    sc = bpy.context.scene
    w = bpy.data.worlds.new("w"); w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.45, 0.45, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.4
    sc.world = w
    gm = bpy.data.materials.new("gray"); gm.use_nodes = True
    b = gm.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.35, 0.35, 0.35, 1); b.inputs["Roughness"].default_value = 0.9
    bpy.ops.mesh.primitive_plane_add(size=8); bpy.context.active_object.data.materials.append(gm)
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 2.5, 4), rotation=(math.pi / 2, 0, 0))
    bpy.context.active_object.data.materials.append(gm)
    mn, mx = bounds([obj]); ctr = (mn + mx) / 2; size = max((mx - mn).length, 0.3)
    l = bpy.data.lights.new("top", "AREA"); l.energy = 600; l.size = 1.2; l.color = (1.0, 0.97, 0.88)
    lo = bpy.data.objects.new("top", l); lo.location = (0.1, 0.0, 2.4); sc.collection.objects.link(lo)
    l2 = bpy.data.lights.new("fill", "AREA"); l2.energy = 60; l2.size = 3
    lo2 = bpy.data.objects.new("fill", l2); lo2.location = (-2, -2, 1.2); sc.collection.objects.link(lo2)
    lo2.rotation_euler = (math.radians(70), 0, math.radians(-40))
    cam = bpy.data.cameras.new("c"); cam.lens = 50
    co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
    dist = size * 2.3
    co.location = ctr + Vector((dist * 0.62, -dist * 0.72, dist * 0.42))  # front (-Y blender = +Z gltf), 3/4 from right
    tgt = bpy.data.objects.new("t", None); tgt.location = ctr; sc.collection.objects.link(tgt)
    tr = co.constraints.new("TRACK_TO"); tr.target = tgt; tr.track_axis = "TRACK_NEGATIVE_Z"; tr.up_axis = "UP_Y"
    sc.render.engine = "CYCLES"; sc.cycles.samples = 64; sc.cycles.device = "CPU"
    sc.render.resolution_x = sc.render.resolution_y = 1024
    path.parent.mkdir(parents=True, exist_ok=True)
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main():
    jobs, cand = parse()
    sp = CACHE / "clean_stats.json"
    allstats = json.loads(sp.read_text()) if sp.exists() else {}
    for j in jobs:
        name, uid, yaw, tris, drive = j[:5]
        suffix = j[5] if len(j) > 5 else "_sf"
        st = process(name, uid, yaw, int(tris), drive, suffix, cand)
        print("RESULT", name, json.dumps(st))
        if not cand: allstats[name + suffix] = st
    if not cand: sp.write_text(json.dumps(allstats, indent=2))


main()
