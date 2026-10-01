"""Headless cleanup + preview for Level 0 props.
blender -b -P pipeline/blender/clean_props.py -- [--only chair,crt,box] [--variant-map chair=chair_v1,...]
Reads pipeline/meshes/cache/<key>.glb, writes game/assets/props/level0/<name>.glb,
previews to pipeline/meshes/previews/<name>.png, stats to pipeline/meshes/cache/clean_stats.json.
Steps: import, join meshes, apply transforms, scale to real-world height/size in meters, origin at bottom center,
decimate to triangle budget, clamp textures to 2048, export GLB (Y-up, embedded textures).
"""
import bpy, sys, json, math
from pathlib import Path
from mathutils import Vector

ROOT = Path(bpy.data.filepath or __file__).resolve()
ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "pipeline/meshes/cache"
OUT = ROOT / "game/assets/props/level0"
PREV = ROOT / "pipeline/meshes/previews"
# target size in meters (x, y_up, z) ; the largest-known dimension drives uniform scale
SPEC = {
    "chair": dict(name="prop_office_chair", tris=12000, height=0.95),
    "crt":   dict(name="prop_crt_monitor",  tris=6000,  dims=(0.38, 0.38, 0.42)),  # w, h, d
    "box":   dict(name="prop_cardboard_box", tris=6000, dims=(0.40, 0.30, 0.30)),  # w(long), h, d
}


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only, vm = list(SPEC), {}
    for i, t in enumerate(a):
        if t == "--only": only = a[i + 1].split(",")
        if t == "--variant-map": vm = dict(x.split("=") for x in a[i + 1].split(","))
    return only, vm


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def tri_count(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    m = obj.evaluated_get(dg).to_mesh()
    n = sum(len(p.vertices) - 2 for p in m.polygons)
    obj.evaluated_get(dg).to_mesh_clear()
    return n


def process(key, cfg, src):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))  # glTF import converts to Blender Z-up
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in meshes:
        o.parent = None
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = cfg["name"]
    # real-world scale (Blender Z is up here, X width, Y depth)
    mn, mx = bounds([obj]); d = mx - mn
    if "height" in cfg:
        s = cfg["height"] / d.z
    else:
        s = cfg["dims"][1] / d.z  # height drives uniform scale; width/depth are checked in the report
    obj.scale = (s, s, s)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    # origin at bottom center
    mn, mx = bounds([obj])
    c = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    obj.data.transform(__import__("mathutils").Matrix.Translation(-c))
    obj.location = (0, 0, 0)
    # decimate
    before = tri_count(obj)
    if before > cfg["tris"]:
        mod = obj.modifiers.new("dec", "DECIMATE"); mod.ratio = cfg["tris"] / before
        bpy.ops.object.modifier_apply(modifier=mod.name)
    after = tri_count(obj)
    # clamp textures to 2048
    for img in bpy.data.images:
        if img.size[0] > 2048 or img.size[1] > 2048:
            img.scale(min(img.size[0], 2048), min(img.size[1], 2048))
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / f"{cfg['name']}.glb"
    bpy.ops.export_scene.gltf(filepath=str(dst), export_format="GLB", export_yup=True,
                              export_apply=True, use_selection=False)
    mn, mx = bounds([obj]); d = mx - mn
    stats = dict(tris_before=before, tris=after, dims_m=dict(x=round(d.x, 3), y_up=round(d.z, 3), z=round(d.y, 3)),
                 glb=str(dst.relative_to(ROOT)).replace("\\", "/"), source=str(src.relative_to(ROOT)).replace("\\", "/"))
    preview(obj, PREV / f"{cfg['name']}.png")
    return stats


def preview(obj, path):
    sc = bpy.context.scene
    w = bpy.data.worlds.new("w"); w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.35, 0.35, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.world = w
    # gray floor
    bpy.ops.mesh.primitive_plane_add(size=6)
    fl = bpy.context.active_object
    fm = bpy.data.materials.new("fl"); fm.diffuse_color = (0.3, 0.3, 0.3, 1); fl.data.materials.append(fm)
    mn, mx = bounds([obj]); ctr = (mn + mx) / 2; size = max((mx - mn).length, 0.3)
    for loc, en in (((2, -2, 3), 250), ((-3, -1, 2), 120), ((0, 3, 2), 100)):
        l = bpy.data.lights.new("l", "AREA"); l.energy = en; l.size = 2
        lo = bpy.data.objects.new("l", l); lo.location = loc; sc.collection.objects.link(lo)
        tr = lo.constraints.new("TRACK_TO"); tr.target = obj; tr.track_axis = "TRACK_NEGATIVE_Z"; tr.up_axis = "UP_Y"
    cam = bpy.data.cameras.new("c"); cam.lens = 50
    co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
    dist = size * 2.4
    co.location = ctr + Vector((dist * 0.7, -dist * 0.7, dist * 0.45))
    tr = co.constraints.new("TRACK_TO")
    tgt = bpy.data.objects.new("t", None); tgt.location = ctr; sc.collection.objects.link(tgt)
    tr.target = tgt; tr.track_axis = "TRACK_NEGATIVE_Z"; tr.up_axis = "UP_Y"
    sc.render.engine = "CYCLES"; sc.cycles.samples = 48; sc.cycles.device = "CPU"
    sc.render.resolution_x = sc.render.resolution_y = 1024
    sc.render.filepath = str(path)
    PREV.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)


def main():
    only, vm = args()
    allstats = {}
    sp = CACHE / "clean_stats.json"
    if sp.exists(): allstats = json.loads(sp.read_text())
    for k in only:
        src = CACHE / f"{vm.get(k, k)}.glb"
        if not src.exists():
            print(f"missing {src}; skipping"); continue
        allstats[k] = process(k, SPEC[k], src)
        print(k, allstats[k])
    sp.write_text(json.dumps(allstats, indent=2))


main()
