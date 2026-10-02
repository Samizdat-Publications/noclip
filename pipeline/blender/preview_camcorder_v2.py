"""Preview sheet for camcorder viewmodel candidates (current + v2 candidates).
  blender -b -P pipeline/blender/preview_camcorder_v2.py
Writes pipeline/blender/previews/_cc_<name>_{side,front,fp}.png and composes camcorder_v2_candidates.png (PIL, system python).
Views: side (camera at +X, eye marker = red dot at origin), 3/4 front, first person from the game low pose
(camera at origin, 70 deg vertical FOV, model at Vector3(0.17,-0.34,-0.33), euler (-0.8,0.3,0.35) in Godot space).
"""
import bpy, math, sys
from pathlib import Path
from mathutils import Vector, Matrix, Euler, Quaternion

ROOT = Path(__file__).resolve().parents[2]
PREV = ROOT / "pipeline/blender/previews"
P = ROOT / "game/assets/props/player"
NAMES = ["camcorder"] + [f"camcorder_v2_cand{i}" for i in (1, 2, 3)]


def godot_to_blender():
    # gltf (x,y,z) -> blender (x,-z,y)
    return Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def render(name, view, view_r=0.0):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(P / f"{name}.glb"))
    sc = bpy.context.scene
    ms = [o for o in sc.objects if o.type == "MESH"]
    w = bpy.data.worlds.new("w"); w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.16, 0.16, 0.15, 1); bg.inputs[1].default_value = 0.5
    sc.world = w
    # warm fluorescent-ish overhead panel + weak fill, like the level
    l = bpy.data.lights.new("a", "AREA"); l.energy = 120; l.size = 1.5; l.color = (1.0, 0.95, 0.8)
    lo = bpy.data.objects.new("a", l); lo.location = (0.2, -0.3, 1.2); lo.rotation_euler = (0, 0, 0); sc.collection.objects.link(lo)
    l2 = bpy.data.lights.new("b", "AREA"); l2.energy = 40; l2.size = 2
    lo2 = bpy.data.objects.new("b", l2); lo2.location = (-1.5, -1.5, 0.6); lo2.rotation_euler = (math.radians(80), 0, math.radians(-45)); sc.collection.objects.link(lo2)
    cam = bpy.data.cameras.new("c"); co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
    sc.render.engine = "CYCLES"; sc.cycles.samples = 48; sc.cycles.device = "CPU"
    if view == "fp":
        cam.sensor_fit = "VERTICAL"; cam.angle = math.radians(70); cam.clip_start = 0.05
        sc.render.resolution_x, sc.render.resolution_y = 480, 270
        # exactly camcorder.gd _update_viewmodel for raise amount r (e = eased)
        e = 1.0 - (1.0 - view_r) ** 1.6
        low = Vector((0.17, -0.34, -0.33)); eyep = Vector((0, 0, 0.004))
        p = low.lerp(eyep, e) + Vector((0, math.sin(e * math.pi) * 0.06, math.sin(e * math.pi) * -0.05))
        # Godot Quaternion.from_euler is YXZ (R = Ry*Rx*Rz) = Blender euler order ZXY
        qlow = Euler((-0.8, 0.3, 0.35), "ZXY").to_quaternion()
        q = qlow.slerp(Quaternion((1, 0, 0, 0)), e ** 0.8)
        R = q.to_matrix()
        M = Matrix.Translation(p) @ R.to_4x4()
        C = godot_to_blender()
        MB = C @ M @ C.inverted()
        for o in ms: o.matrix_world = MB @ o.matrix_world
        co.location = (0, 0, 0); co.rotation_euler = (math.pi / 2, 0, 0)
        # sky light so we see it as in a dim room
        lo.location = (0, 0.3, 1.0); l.size = 3; l.energy = 250; bg.inputs[1].default_value = 1.2
    else:
        pts = [o.matrix_world @ v.co for o in ms for v in o.data.vertices]
        mn = Vector((min(q.x for q in pts), min(q.y for q in pts), min(q.z for q in pts)))
        mx = Vector((max(q.x for q in pts), max(q.y for q in pts), max(q.z for q in pts)))
        c = (mn + mx) / 2
        cam.lens = 70
        sc.render.resolution_x = sc.render.resolution_y = 480 if view in ('side', 'front') else 640
        d = {"side": Vector((1, 0.0, 0.08)), "front": Vector((0.6, 1.0, 0.45)), "left": Vector((-1, 0.0, 0.08)), "top": Vector((0.001, -0.1, 1)), "rear": Vector((-0.5, -1.0, 0.4))}[view]
        co.location = c + d.normalized() * 0.85
        t = bpy.data.objects.new("t", None); t.location = c; sc.collection.objects.link(t)
        tr = co.constraints.new("TRACK_TO"); tr.target = t; tr.track_axis = "TRACK_NEGATIVE_Z"; tr.up_axis = "UP_Y"
        lo.location = c + Vector((0.2, 0.3, 1.0))
        # eye marker
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.004, location=(0, 0, 0))
        m = bpy.data.materials.new("r"); m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1, 0, 0, 1)
        m.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1, 0, 0, 1)
        m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 5
        bpy.context.active_object.data.materials.append(m)
    tag = view if view != "fp" else f"fp{int(view_r * 100)}"
    sc.render.filepath = str(PREV / f"_cc_{name}_{tag}.png")
    bpy.ops.render.render(write_still=True)


for n in NAMES:
    if not (P / f"{n}.glb").exists(): continue
    render(n, "side"); render(n, "front")
    if "--logos" in sys.argv:
        for v in ("left", "top", "rear"): render(n, v)
        continue
    for r in (0.45, 0.75, 1.0):
        render(n, "fp", r)
