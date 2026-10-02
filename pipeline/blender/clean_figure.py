"""Headless cleanup + preview for the tape-figure base mesh candidates (Sketchfab, CC0/CC-BY).
  blender -b -P pipeline/blender/clean_figure.py -- clean <uid>:<n> [<uid>:<n> ...]
  blender -b -P pipeline/blender/clean_figure.py -- preview <n> [<n> ...]
clean: import cache/<uid>/model.glb, drop helper objects (the Sketchfab 'Icosphere' bounds sphere) and animations,
  reset the pose, bake object transforms into the mesh and armature (world space, meters), yaw so the toes point -Y
  Blender (= +Z glTF), scale uniformly so the body is 1.8 m tall, feet on y=0 with the origin between the hips,
  join all body parts into one mesh with ONE neutral material (source textures are dropped on purpose: the game renders
  the figure as a dark smeared silhouette), keep the armature and skin weights, export
  game/assets/props/tape/figure_cand_<n>.glb and print bone names. Stats to pipeline/blender/previews/figure_stats.json.
preview: re-import each exported GLB, grey material, front + side Cycles renders (CPU) to previews/_fig_<n>_{front,side}.png
  (the sheet is assembled by pipeline/blender/figure_sheet.py).
"""
import bpy, sys, json, math
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "pipeline/meshes/sketchfab_cache"
OUT = ROOT / "game/assets/props/tape"
PREV = ROOT / "pipeline/blender/previews"
HEIGHT = 1.8


def world_pts(objs):
    return [o.matrix_world @ v.co for o in objs for v in o.data.vertices]


def minmax(pts):
    return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))


def find_bone(arm, *subs):
    for b in arm.data.bones:
        nl = b.name.lower()
        if all(s in nl for s in subs):
            return b


def clean(uid, n):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(CACHE / uid / "model.glb"))
    sc = bpy.context.scene
    for o in list(sc.objects):
        if o.type not in ("MESH", "ARMATURE") or o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
    arm = next(o for o in sc.objects if o.type == "ARMATURE")
    meshes = [o for o in sc.objects if o.type == "MESH"]
    for a in list(bpy.data.actions): bpy.data.actions.remove(a)
    for o in sc.objects: o.animation_data_clear()
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()
    # shape keys (face blendshapes) off
    for o in meshes:
        if o.data.shape_keys:
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.shape_key_remove(all=True, apply_mix=False)
    # facing from the shoulder axis (more robust than toe splay): left arm - right arm = v, facing = (v.y, -v.x)
    la = find_bone(arm, "leftarm") or find_bone(arm, "upperarm_l")
    ra = find_bone(arm, "rightarm") or find_bone(arm, "upperarm_r")
    v = (arm.matrix_world @ la.head_local) - (arm.matrix_world @ ra.head_local)
    fv = Vector((v.y, -v.x, 0))
    yaw = -math.pi / 2 - math.atan2(fv.y, fv.x)
    print("FACING", uid, "facing", tuple(round(c, 3) for c in fv), "yaw_deg", round(math.degrees(yaw), 1))
    # bake: unparent meshes keeping world transform, apply, apply armature
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT"); arm.select_set(True); bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mn, mx = minmax(world_pts(meshes))
    rawh = mx.z - mn.z
    s = HEIGHT / rawh
    hips = find_bone(arm, "hips") or find_bone(arm, "hip")
    hp = arm.matrix_world @ hips.head_local
    M = Matrix.Scale(s, 4) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Translation((-hp.x, -hp.y, -mn.z))
    for o in meshes + [arm]:
        o.matrix_world = M @ o.matrix_world
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes + [arm]: o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in meshes:
        o.parent = arm; o.matrix_parent_inverse = arm.matrix_world.inverted()
        if not any(m.type == "ARMATURE" for m in o.modifiers):
            m = o.modifiers.new("Armature", "ARMATURE"); m.object = arm
    mat = bpy.data.materials.new("figure_base"); mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.18, 0.18, 0.18, 1); b.inputs["Roughness"].default_value = 0.85
    for o in meshes:
        o.data.materials.clear(); o.data.materials.append(mat)
    for im in list(bpy.data.images): bpy.data.images.remove(im)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1: bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "figure_body"; arm.name = "figure_armature"
    mn, mx = minmax(world_pts([body]))
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg).to_mesh()
    zs = [(body.matrix_world @ v.co).z for v in ev.vertices]
    body.evaluated_get(dg).to_mesh_clear()
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / f"figure_cand_{n}.glb"
    bpy.ops.export_scene.gltf(filepath=str(dst), export_format="GLB", export_yup=True, export_apply=False,
                              use_selection=False, export_animations=False, export_skins=True)
    bones = [b.name for b in arm.data.bones]
    print("BONES", n, json.dumps(bones))
    return dict(uid=uid, n=n, glb=str(dst.relative_to(ROOT)).replace("\\", "/"), tris=tris, verts=len(body.data.vertices),
                raw_height_units=round(rawh, 3), scale=round(s, 5), yaw_deg=round(math.degrees(yaw), 1),
                size_m_x_y_z_yup=[round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)],
                evaluated_height_m=round(max(zs) - min(zs), 3), feet_y=round(min(zs), 4), bone_count=len(bones), bones=bones)


def render_pair(n):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(OUT / f"figure_cand_{n}.glb"))
    sc = bpy.context.scene
    gm = bpy.data.materials.new("g"); gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    for o in sc.objects:
        if o.type == "MESH": o.data.materials.clear(); o.data.materials.append(gm)
    w = bpy.data.worlds.new("w"); w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.85, 0.85, 0.85, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sc.world = w
    l = bpy.data.lights.new("k", "AREA"); l.energy = 400; l.size = 3
    lo = bpy.data.objects.new("k", l); lo.location = (1.5, -2.5, 3)
    lo.rotation_euler = (math.radians(50), 0, math.radians(30)); sc.collection.objects.link(lo)
    cam = bpy.data.cameras.new("c"); cam.type = "ORTHO"; cam.ortho_scale = 2.1
    co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
    sc.render.engine = "CYCLES"; sc.cycles.samples = 24; sc.cycles.device = "CPU"
    sc.render.resolution_x, sc.render.resolution_y = 500, 800
    PREV.mkdir(parents=True, exist_ok=True)
    # front: camera at -Y (Blender) looking +Y sees the face that points -Y (= +Z glTF)
    for name, loc, rot in (("front", (0, -6, 0.9), (math.pi / 2, 0, 0)), ("side", (6, 0, 0.9), (math.pi / 2, 0, math.pi / 2))):
        co.location = loc; co.rotation_euler = rot
        sc.render.filepath = str(PREV / f"_fig_{n}_{name}.png")
        bpy.ops.render.render(write_still=True)


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    if a[0] == "clean":
        sp = PREV / "figure_stats.json"; PREV.mkdir(parents=True, exist_ok=True)
        st = json.loads(sp.read_text()) if sp.exists() else {}
        for j in a[1:]:
            uid, n = j.split(":")
            r = clean(uid, n); st[n] = r
            print("RESULT", json.dumps({k: v for k, v in r.items() if k != "bones"}))
        sp.write_text(json.dumps(st, indent=1))
    else:
        for n in a[1:]: render_pair(n)


main()
