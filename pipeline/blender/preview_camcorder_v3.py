"""Preview sheet: camcorder_v2 (top row) vs camcorder_v3 (bottom row), side / 3-4 front / rear 3-4 (eyecup), one warm
fluorescent-like key plus a dim cool fill. Cycles on CPU, low samples.
  blender -b -P pipeline/blender/preview_camcorder_v3.py -- [--detail]   (--detail adds a close-up row of v3)
"""
import bpy, sys, math, numpy as np
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "pipeline/blender/previews"
TMP = OUT / "_tmp_cc3"
TMP.mkdir(parents=True, exist_ok=True)
W, H = 640, 520
ctr = Vector((0.022, 0.107, -0.019))
VIEWS = [("side", Vector((1.0, 0.05, 0.12)), 0.50), ("front34", Vector((0.75, 1.0, 0.45)), 0.50), ("rear34", Vector((-0.8, -1.0, 0.45)), 0.50)]
DETAIL = [("detail_body", Vector((1.0, 0.1, 0.1)), 0.22, Vector((0.025, 0.07, -0.02))),
          ("detail_lens", Vector((0.5, 1.0, 0.25)), 0.22, Vector((0.02, 0.18, -0.02))),
          ("detail_eye", Vector((-0.6, -1.0, 0.3)), 0.2, Vector((0.01, 0.0, -0.01)))]
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def render(glb, view, dist, name, target=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / glb))
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 48
    sc.cycles.use_denoising = True; sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.render.resolution_x, sc.render.resolution_y = W, H
    sc.view_settings.view_transform = "AgX" if False else "Standard"
    sc.world = bpy.data.worlds.new("w"); sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.012, 0.013, 0.015, 1); bg.inputs[1].default_value = 1.0
    # key: warm fluorescent troffer-like panel overhead and slightly front
    key = bpy.data.lights.new("key", "AREA"); key.energy = 18; key.size = 0.5; key.size_y = 0.3; key.color = (1.0, 0.88, 0.62)
    ko = bpy.data.objects.new("key", key); sc.collection.objects.link(ko)
    ko.location = (0.45, 0.25, 0.65); ko.rotation_euler = (Vector((0, 0, 0)) - ko.location + ctr).to_track_quat("-Z", "Y").to_euler()
    fill = bpy.data.lights.new("fill", "AREA"); fill.energy = 1.6; fill.size = 0.6; fill.color = (0.75, 0.85, 1.0)
    fo = bpy.data.objects.new("fill", fill); sc.collection.objects.link(fo)
    fo.location = (-0.6, 0.35, 0.1); fo.rotation_euler = ((ctr - fo.location)).to_track_quat("-Z", "Y").to_euler()
    # floor to catch the key (gives reflections something to read against)
    bpy.ops.mesh.primitive_plane_add(size=1.5, location=(0.02, 0.1, -0.075))
    fl = bpy.context.active_object; m = bpy.data.materials.new("fl"); m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.07, 0.07, 0.07, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    fl.data.materials.append(m)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.lens = 70
    c = target if target is not None else ctr
    d = view.normalized()
    cam.location = c + d * dist * 1.4
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = str(TMP / (name + ".png"))
    bpy.ops.render.render(write_still=True)
    return TMP / (name + ".png")


def load(p):
    im = bpy.data.images.load(str(p)); a = np.empty(W * H * 4, np.float32); im.pixels.foreach_get(a); bpy.data.images.remove(im)
    return a.reshape(H, W, 4)


def sheet(rows, out):
    arr = np.concatenate([np.concatenate([load(p) for p in r], axis=1) for r in rows[::-1]], axis=0)
    im = bpy.data.images.new("sheet", arr.shape[1], arr.shape[0]); im.pixels.foreach_set(arr.ravel()); im.update()
    im.filepath_raw = str(out); im.file_format = "PNG"; im.save()


rows = []
for glb, tag in (("game/assets/props/player/camcorder_v2.glb", "v2"), ("game/assets/props/player/camcorder_v3.glb", "v3")):
    rows.append([render(glb, v, d, f"{tag}_{n}") for n, v, d in VIEWS])
sheet(rows, OUT / "camcorder_v3.png")
if "--detail" in args:
    sheet([[render("game/assets/props/player/camcorder_v3.glb", v, d, f"v3_{n}", t) for n, v, d, t in DETAIL]], OUT / "camcorder_v3_detail.png")
print("PREVIEW DONE")
