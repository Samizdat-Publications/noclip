"""Turntable contact sheet for Meshy occupant GLBs.
blender -b -P pipeline/blender/preview_entity_meshy.py -- <glb> <out_dir> <name>
Renders front, three-quarter, side, back + head close-up at 768x1152, prints stats as JSON line 'STATS {...}'.
"""
import bpy, sys, math, json, os
from mathutils import Vector

glb, outdir, name = sys.argv[sys.argv.index("--") + 1:][:3]
os.makedirs(outdir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
tris = 0; mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
for o in meshes:
    me = o.evaluated_get(dg).to_mesh()
    me.calc_loop_triangles(); tris += len(me.loop_triangles)
    for v in me.vertices:
        w = o.matrix_world @ v.co
        for i in range(3):
            mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
size = mx - mn
print("STATS", json.dumps({"tris": tris, "meshes": len(meshes), "bbox_m": [round(x, 3) for x in size], "min": [round(x, 3) for x in mn]}))
H = size.z; ctr = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z + H / 2))

sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 768, 1152
sc.render.image_settings.file_format = "PNG"
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.32, 0.32, 0.32, 1); bg.inputs[1].default_value = 1.0
# neutral grey backdrop via world colour
def light(kind, loc, energy, size=3.0):
    d = bpy.data.lights.new("l", kind); d.energy = energy
    if kind == "AREA": d.size = size
    o = bpy.data.objects.new("l", d); sc.collection.objects.link(o); o.location = loc
    return o
cam_d = bpy.data.cameras.new("c"); cam = bpy.data.objects.new("c", cam_d); sc.collection.objects.link(cam); sc.camera = cam
cam_d.lens = 60
tgt_empty = bpy.data.objects.new("t", None); sc.collection.objects.link(tgt_empty)
tc = cam.constraints.new("TRACK_TO"); tc.target = tgt_empty; tc.track_axis = "TRACK_NEGATIVE_Z"; tc.up_axis = "UP_Y"

def place_lights(yaw, d):
    # key, fill, rim relative to camera yaw (camera sits at -Y rotated by yaw)
    for o in [o for o in sc.objects if o.type == "LIGHT"]:
        bpy.data.objects.remove(o)
    def rot(x, y, z):
        c, s = math.cos(yaw), math.sin(yaw)
        return Vector((ctr.x + x * c - y * s, ctr.y + x * s + y * c, ctr.z + z))
    light("AREA", rot(-2 * d * .5, -d, H * .6), 900 * d * d / 9, 3 * d / 3)
    light("AREA", rot(d * .6, -d * .8, H * .1), 300 * d * d / 9, 3 * d / 3)
    light("AREA", rot(0, d * .9, H * .7), 700 * d * d / 9, 3 * d / 3)

def shot(yaw_deg, path, dist, focus_z, ortho_h=None):
    yaw = math.radians(yaw_deg)
    tgt_empty.location = (ctr.x, ctr.y, focus_z)
    cam.location = (ctr.x + math.sin(yaw) * dist, ctr.y - math.cos(yaw) * dist, focus_z)
    place_lights(yaw, dist)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)

# full body: fit height into 1152 frame at 60mm lens (sensor 36mm, vertical fit uses width -> sensor_fit auto)
dist = H * 2.25  # lens 60mm, fit is on the long (vertical) side: coverage = dist*0.6
paths = []
for label, yaw in (("front", 0), ("threeq", 40), ("side", 90), ("back", 180)):
    p = os.path.join(outdir, f"_{name}_{label}.png"); shot(yaw, p, dist, ctr.z); paths.append(p)
hz = mn.z + H * 0.86
p = os.path.join(outdir, f"_{name}_head.png"); shot(15, p, H * 0.5, hz); paths.append(p)
print("PATHS", json.dumps(paths))
