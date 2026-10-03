"""Render one Workbench side-view frame (mid-clip) of the rigged mesh posed by each clip glb.
blender -b -P this.py -- <rigged.glb> <anims_dir> <out_dir> <comma-separated clip names>
Writes <out_dir>/<clip>.png (400x400) and <out_dir>/report.json (per clip: lowest/highest bone height, bounding box)."""
import bpy, sys, os, json, math
from mathutils import Vector

rig, anims, out, names = sys.argv[sys.argv.index("--") + 1:][:4]
names = names.split(",")
names = [names[0]] + names  # the first clip imported evaluates as the rest pose; render it twice, the second is right
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=rig)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
if arm.animation_data:
    arm.animation_data.action = None
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.render.resolution_x = sc.render.resolution_y = 400
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "TEXTURE"
sc.world = bpy.data.worlds.new("w")
sc.world.color = (0.55, 0.55, 0.58)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
bpy.context.collection.objects.link(cam)
cam.data.type = "ORTHO"
sc.camera = cam
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
report = {}
for n in names:
    path = os.path.join(anims, n + ".glb")
    if not os.path.exists(path):
        continue
    before = set(bpy.data.actions)
    before_obj = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [a for a in bpy.data.actions if a not in before]
    for o in [o for o in bpy.data.objects if o not in before_obj]:
        bpy.data.objects.remove(o, do_unlink=True)
    if not new:
        continue
    act = new[0]
    arm.animation_data_create()
    arm.animation_data.action = act
    f0, f1 = act.frame_range
    sc.frame_set(int(f0))
    bpy.context.view_layer.update()
    sc.frame_set(int((f0 + f1) / 2))
    bpy.context.view_layer.update()
    zs = [(arm.matrix_world @ b.head).z for b in arm.pose.bones]
    ys = [(arm.matrix_world @ b.head).y for b in arm.pose.bones]
    xs = [(arm.matrix_world @ b.head).x for b in arm.pose.bones]
    head_z = max(zs)
    report[n] = {"bone_min_z": round(min(zs), 2), "bone_max_z": round(max(zs), 2), "x_span": round(max(xs) - min(xs), 2), "y_span": round(max(ys) - min(ys), 2)}
    cx = (max(xs) + min(xs)) / 2
    cam.location = (cx + 6, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2)  # side view along -X
    cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    cam.data.ortho_scale = 1.35 * max(max(zs) - min(zs), max(ys) - min(ys), 1.0) + 0.4
    sc.render.filepath = os.path.join(out, n + ".png")
    bpy.ops.render.render(write_still=True)
    bpy.data.actions.remove(act)
json.dump(report, open(os.path.join(out, "report.json"), "w"), indent=1)
print("PREVIEW", json.dumps(report))
