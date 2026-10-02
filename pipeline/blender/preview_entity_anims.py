"""Render 4 frames per clip (front 3/4 view, grey bg, camera tracks the hips) to <outdir>/<name>_<i>.png.
blender -b -P this.py -- <merged.glb> <outdir>"""
import bpy, sys, os, math
from mathutils import Vector
src, outdir = sys.argv[sys.argv.index("--") + 1:]
os.makedirs(outdir, exist_ok=True)
MAP = {"Basic_Jump": "lunge", "Cautious_Crouch_Walk_Forward": "crouch", "Crawl_and_Look_Back": "crawl", "Idle": "idle",
       "Injured_Walk": "walk", "Long_Breathe_and_Look_Around": "look", "Mummy_Stagger": "twitch", "RunFast": "run", "Zombie_Scream": "scream"}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
    if o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "TEXTURE"
sc.render.resolution_x, sc.render.resolution_y = 360, 480
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = False; w.color = (0.45, 0.45, 0.45)
sc.view_settings.view_transform = "Standard"
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.lens = 40
for aname, short in MAP.items():
    arm.animation_data.action = bpy.data.actions[aname]
    f0, f1 = bpy.data.actions[aname].frame_range
    for i in range(4):
        f = f0 + (f1 - f0) * i / 4.0
        sc.frame_set(int(f))
        hp = arm.matrix_world @ arm.pose.bones["Hips"].head
        # character faces -Y in Blender; camera sits in front (-Y) and to the side (+X)
        target = Vector((hp.x, hp.y, 1.1))
        cam.location = target + Vector((2.6, -4.6, 0.3))
        d = target - cam.location
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(outdir, f"{short}_{i}.png")
        bpy.ops.render.render(write_still=True)
print("DONE")
