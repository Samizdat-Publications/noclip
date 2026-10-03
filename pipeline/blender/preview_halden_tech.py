"""Render the rigged technician in A-pose and the last frame of the death clip.
blender -b -P this.py -- <tech_rigged.glb> <merged_animations.glb> <outdir>"""
import bpy, sys, os
from mathutils import Vector
model, death, outdir = sys.argv[sys.argv.index("--") + 1:][:3]
os.makedirs(outdir, exist_ok=True)


def setup():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 900, 900
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = False
    w.color = (0.5, 0.5, 0.5)
    sc.view_settings.view_transform = "Standard"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 40
    return sc, cam


def aim(cam, target, offset):
    cam.location = target + offset
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()


def dump_bones(arm):
    names = [b.name for b in arm.pose.bones]
    print("BONES", names)


# 1: A-pose
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=model)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
dump_bones(arm)
sc, cam = setup()
aim(cam, Vector((0, 0, 0.9)), Vector((0, -4.6, 0.1)))
sc.render.filepath = os.path.join(outdir, "halden_tech_model.png")
bpy.ops.render.render(write_still=True)

# 2: last frame of the death clip, from the merged animation glb (mesh + all actions)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=death)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
act = bpy.data.actions["dying_backwards"]
arm.animation_data.action = act
sc, cam = setup()
sc.frame_set(int(act.frame_range[1]))
bpy.context.view_layer.update()
hp = arm.matrix_world @ arm.pose.bones["Hips"].head
print("DEATH HIPS", hp, "HEAD", arm.matrix_world @ arm.pose.bones["Head"].head, "FEET", arm.matrix_world @ arm.pose.bones["LeftFoot"].head)
aim(cam, Vector((hp.x, hp.y, 0.3)), Vector((2.0, -2.6, 1.8)))
sc.render.filepath = os.path.join(outdir, "halden_tech_dead_pose.png")
bpy.ops.render.render(write_still=True)
