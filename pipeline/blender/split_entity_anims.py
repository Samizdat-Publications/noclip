"""Split Meshy merged animation GLB into one armature-only GLB per clip.
blender -b -P this.py -- <merged.glb> <outdir>   (names from pipeline/meshes/build_entity_rig.py ACTIONS)"""
import bpy, sys, json, os
args = sys.argv[sys.argv.index("--") + 1:]
src, outdir = args
os.makedirs(outdir, exist_ok=True)
MAP = {"Basic_Jump": "lunge", "Cautious_Crouch_Walk_Forward": "crouch", "Crawl_and_Look_Back": "crawl", "Idle": "idle",
       "Injured_Walk": "walk", "Long_Breathe_and_Look_Around": "look", "Mummy_Stagger": "twitch", "RunFast": "run", "Zombie_Scream": "scream"}
info = {}
for aname, short in MAP.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for o in list(bpy.data.objects):
        if o.type != "ARMATURE":
            bpy.data.objects.remove(o, do_unlink=True)
    act = bpy.data.actions[aname]
    arm.animation_data.action = act
    for a in list(bpy.data.actions):
        if a != act:
            bpy.data.actions.remove(a)
    # hips travel (root motion) over the clip, in meters
    f0, f1 = act.frame_range
    hips = arm.pose.bones["Hips"]
    def pos(f):
        bpy.context.scene.frame_set(int(f)); return (arm.matrix_world @ hips.matrix @ hips.bone.head_local * 0 + arm.matrix_world @ hips.head)
    p0, p1 = pos(f0), pos(f1)
    info[short] = {"action": aname, "frames": [f0, f1], "fps": bpy.context.scene.render.fps, "seconds": round((f1 - f0) / bpy.context.scene.render.fps, 2),
                   "hips_travel_m": [round(v, 3) for v in (p1 - p0)]}
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True); bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=os.path.join(outdir, short + ".glb"), export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="ACTIVE_ACTIONS", export_force_sampling=True)
json.dump(info, open(os.path.join(outdir, "clips.json"), "w", newline="\n"), indent=1)
print("CLIPS", json.dumps(info))
