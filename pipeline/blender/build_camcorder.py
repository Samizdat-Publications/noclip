"""First-person camcorder viewmodel: mid-1990s generic Hi8 / VHS-C handheld (no brands, no logos).

Fully procedural, reproducible, no downloads and no paid APIs:
  "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b -P pipeline/blender/build_camcorder.py -- [--res 1024] [--samples 64] [--bake-samples 24] [--no-bake] [--no-preview] [--verify-only]

Pipeline: bmesh/modifier modelling in meters -> join -> smooth by angle -> smart UV project + pack ->
bake procedural shaders (Cycles) to base color / ORM (AO, roughness, metallic) / tangent normal (OpenGL +Y) ->
one clean Principled "camcorder_body" material from the baked PNGs + separate "lens_glass" and "tally" materials ->
export GLB (Y-up, textures embedded) -> re-import in a clean scene, report bounds / tris, render the preview.

Axes: authored in Blender Z-up with the lens pointing +Y; the glTF exporter (Y-up) turns that into the engine
convention: lens toward -Z, +Y up, +X is the operator's right. ORIGIN = centre of the eyecup's back opening
(where the eye goes). The model extends forward from there, body offset right (+X) and below (-Y in glTF).
Units are meters. All transforms applied.
"""
import bpy, bmesh, math, random, sys, json, struct
from pathlib import Path
import numpy as np
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/props/player/camcorder.glb"
PREV = ROOT / "pipeline/blender/previews/camcorder_preview.png"
PREV_EXTRA = ROOT / "pipeline/blender/previews/camcorder_preview_left.png"
BAKED = ROOT / "pipeline/meshes/baked_camcorder"
MANIFEST = ROOT / "pipeline/manifests/camcorder.json"
SEED = 9404

# materials in the baked atlas (slot order)
M_PLASTIC, M_KNURL, M_RUBBER, M_FABRIC, M_SILVER, M_DARK = range(6)


def parse_args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(res=1024, samples=64, bake_samples=24, bake=True, preview=True, verify_only=False)
    i = 0
    while i < len(a):
        if a[i] == "--res": o["res"] = min(1024, int(a[i + 1])); i += 1
        elif a[i] == "--samples": o["samples"] = int(a[i + 1]); i += 1
        elif a[i] == "--bake-samples": o["bake_samples"] = int(a[i + 1]); i += 1
        elif a[i] == "--no-bake": o["bake"] = False
        elif a[i] == "--no-preview": o["preview"] = False
        elif a[i] == "--verify-only": o["verify_only"] = True
        i += 1
    return o


# ---------------------------------------------------------------------------------------------- mesh helpers
def to_obj(name, bm, mat_index=0, mat_list=None):
    me = bpy.data.meshes.new(name)
    if mat_list is None:
        for f in bm.faces:
            f.material_index = mat_index
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def apply_mods(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)


def add_bevel(ob, width, seg=3, angle=35):
    m = ob.modifiers.new("bev", "BEVEL")
    m.width = width
    m.segments = seg
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    apply_mods(ob)


def box(name, size, loc, mat, rot=(0, 0, 0), bevel=0.0, seg=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    ob = to_obj(name, bm, mat)
    ob.location = loc
    ob.rotation_euler = rot
    if bevel:
        add_bevel(ob, bevel, seg)
        tag_wear(ob)
    return ob


def revolve(name, prof, segs, mats, cx=0.0, cz=0.0, y_axis=True):
    """Surface of revolution around an axis parallel to Y through (cx, cz).
    prof = [(r, y), ...]; r == 0 makes a single apex vertex (closing cap). mats = material index per profile segment."""
    bm = bmesh.new()
    rings = []
    for r, y in prof:
        if r < 1e-7:
            rings.append([bm.verts.new((cx, y, cz))])
        else:
            rings.append([bm.verts.new((cx + r * math.cos(2 * math.pi * k / segs), y, cz + r * math.sin(2 * math.pi * k / segs))) for k in range(segs)])
    faces = []
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(segs):
            k2 = (k + 1) % segs
            try:
                if len(a) == 1:
                    f = bm.faces.new((a[0], b[k2], b[k]))
                elif len(b) == 1:
                    f = bm.faces.new((a[k], a[k2], b[0]))
                else:
                    f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
                f.material_index = mats[i]
            except ValueError:
                pass
    for ring, first in ((rings[0], True), (rings[-1], False)):   # open ends get flat caps
        if len(ring) > 1:
            f = bm.faces.new(ring if not first else ring[::-1])
            f.material_index = mats[0] if first else mats[-1]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # make sure the normals point away from the axis on the first full-width segment
    return to_obj(name, bm, mat_list=True)


def knurl_loft(name, r_out, r_in, teeth, y0, y1, cx, cz, mat):
    bm = bmesh.new()
    n = teeth * 2
    rings = []
    for y in (y0, y1):
        ring = []
        for k in range(n):
            t = 2 * math.pi * k / n
            # flat-topped trapezoid-ish teeth: two verts per half tooth pair
            r = r_out if (k % 2 == 0) else r_in
            ring.append(bm.verts.new((cx + r * math.cos(t), y, cz + r * math.sin(t))))
        rings.append(ring)
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((rings[0][k], rings[0][k2], rings[1][k2], rings[1][k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return to_obj(name, bm, mat)


def frames(pts, side):
    out = []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        t = (Vector(b) - Vector(a)).normalized()
        w = (Vector(side) - t * Vector(side).dot(t)).normalized()
        out.append((Vector(p), w, t.cross(w).normalized()))
    return out


def chamfer_rect(c, w, h, ww, hh, ch=0.4):
    a, b = ww / 2, hh / 2
    k = min(a, b) * ch
    pts = [(a, -(b - k)), (a, b - k), (a - k, b), (-(a - k), b), (-a, b - k), (-a, -(b - k)), (-(a - k), -b), (a - k, -b)]
    return [c + w * x + h * y for x, y in pts]


def beam(name, pts, widths, heights, side, mat, bevel=0.0):
    bm = bmesh.new()
    vs = []
    for (p, w, h), ww, hh in zip(frames(pts, side), widths, heights):
        vs.append([bm.verts.new(q) for q in chamfer_rect(p, w, h, ww, hh)])
    n = len(vs[0])
    for i in range(len(vs) - 1):
        for j in range(n):
            k = (j + 1) % n
            bm.faces.new((vs[i][j], vs[i][k], vs[i + 1][k], vs[i + 1][j]))
    bm.faces.new(vs[0][::-1])
    bm.faces.new(vs[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = to_obj(name, bm, mat)
    if bevel:
        add_bevel(ob, bevel, 1, 30)
    return ob


def tag_wear(ob):
    """Face attribute 'wear': 1 for bevel facets whose normal is off every axis (rounded edges), else 0."""
    me = ob.data
    me.attributes.new("wear", "FLOAT", "FACE")
    vals = [1.0 if max(abs(p.normal.x), abs(p.normal.y), abs(p.normal.z)) < 0.985 else 0.0 for p in me.polygons]
    me.attributes["wear"].data.foreach_set("value", vals)


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def join(objs, name):
    bpy.context.view_layer.update()
    for o in objs:
        o.data.transform(o.matrix_world.copy())
        o.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = name
    return ob


# ---------------------------------------------------------------------------------------------- procedural shaders
class Sh:
    def __init__(self, mat, seed):
        self.mat = mat
        mat.use_nodes = True
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.rng = random.Random(seed)
        self.tc = self.nt.nodes.new("ShaderNodeTexCoord")
        self.geo = self.nt.nodes.new("ShaderNodeNewGeometry")
        self.obj = self.tc.outputs["Object"]
        self.pt = self.geo.outputs["Pointiness"]
        sn = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.geo.outputs["Normal"], sn.inputs[0])
        self.nz = sn.outputs[2]

    def put(self, sock, v):
        if isinstance(v, bpy.types.NodeSocket):
            self.nt.links.new(v, sock)
        elif isinstance(v, (tuple, list)):
            vv = list(v)
            if sock.type == "RGBA" and len(vv) == 3:
                vv.append(1.0)
            sock.default_value = vv
        else:
            sock.default_value = v

    def noise(self, scale, detail=3.0, rough=0.5, aniso=(1, 1, 1)):
        mp = self.nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Location"].default_value = tuple(self.rng.uniform(-50, 50) for _ in range(3))
        mp.inputs["Scale"].default_value = aniso
        self.nt.links.new(self.obj, mp.inputs["Vector"])
        n = self.nt.nodes.new("ShaderNodeTexNoise")
        n.noise_dimensions = "3D"
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        self.nt.links.new(mp.outputs[0], n.inputs["Vector"])
        return n.outputs["Fac"]

    def checker(self, scale):
        n = self.nt.nodes.new("ShaderNodeTexChecker")
        n.inputs["Scale"].default_value = scale
        self.nt.links.new(self.obj, n.inputs["Vector"])
        return n.outputs["Fac"]

    def math(self, op, a, b=None):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        self.put(n.inputs[0], a)
        if b is not None:
            self.put(n.inputs[1], b)
        return n.outputs[0]

    def sstep(self, x, lo, hi):
        n = self.nt.nodes.new("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP"
        n.clamp = True
        self.put(n.inputs["Value"], x)
        self.put(n.inputs["From Min"], lo)
        self.put(n.inputs["From Max"], hi)
        n.inputs["To Min"].default_value = 0.0
        n.inputs["To Max"].default_value = 1.0
        return n.outputs["Result"]

    def remap(self, x, lo, hi, a=0.0, b=1.0):
        n = self.nt.nodes.new("ShaderNodeMapRange")
        n.clamp = True
        self.put(n.inputs["Value"], x)
        self.put(n.inputs["From Min"], lo)
        self.put(n.inputs["From Max"], hi)
        n.inputs["To Min"].default_value = a
        n.inputs["To Max"].default_value = b
        return n.outputs["Result"]

    def mix(self, fac, a, b):
        n = self.nt.nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        n.clamp_factor = True
        self.put(n.inputs[0], fac)
        self.put(n.inputs[6], a)
        self.put(n.inputs[7], b)
        return n.outputs[2]

    def mixf(self, fac, a, b):
        n = self.nt.nodes.new("ShaderNodeMix")
        n.data_type = "FLOAT"
        n.clamp_factor = True
        self.put(n.inputs[0], fac)
        self.put(n.inputs[2], a)
        self.put(n.inputs[3], b)
        return n.outputs[0]

    def bump(self, height, strength, dist):
        n = self.nt.nodes.new("ShaderNodeBump")
        n.inputs["Strength"].default_value = strength
        n.inputs["Distance"].default_value = dist
        self.nt.links.new(height, n.inputs["Height"])
        return n.outputs["Normal"]

    def finish(self, base, rough, metal=0.0, normal=None):
        pb = self.nt.nodes.new("ShaderNodeBsdfPrincipled")
        self.put(pb.inputs["Base Color"], base)
        self.put(pb.inputs["Roughness"], rough)
        self.put(pb.inputs["Metallic"], metal)
        if normal is not None:
            self.nt.links.new(normal, pb.inputs["Normal"])
        out = self.nt.nodes.new("ShaderNodeOutputMaterial")
        self.nt.links.new(pb.outputs["BSDF"], out.inputs["Surface"])


def wear(s, base, edge_col, edge_amt=0.8):
    """Lighter scuffed edges: a per-face 'wear' mask (1 on bevel facets, 0 on flats, see tag_wear) broken up by noise."""
    n = s.nt.nodes.new("ShaderNodeAttribute")
    n.attribute_type = "GEOMETRY"
    n.attribute_name = "wear"
    chip = s.remap(s.noise(160.0, 5.0, 0.6), 0.3, 0.7, 0.25, 1.0)
    edge = s.math("MULTIPLY", n.outputs["Fac"], chip)
    base = s.mix(s.math("MULTIPLY", edge, edge_amt), base, edge_col)
    return base, edge


def mat_plastic(seed):
    m = bpy.data.materials.new("src_plastic")
    s = Sh(m, seed)
    fine, mid, big = s.noise(700.0, 2.0), s.noise(30.0, 4.0, 0.6), s.noise(4.0, 3.0)
    base = s.mix(s.sstep(big, 0.3, 0.7), (0.040, 0.040, 0.042), (0.052, 0.052, 0.054))
    scuff = s.sstep(s.noise(70.0, 6.0, 0.65, aniso=(1, 6, 1)), 0.62, 0.8)
    base = s.mix(s.math("MULTIPLY", scuff, 0.55), base, (0.095, 0.095, 0.10))
    base, edge = wear(s, base, (0.14, 0.14, 0.145), 0.5)
    dust = s.math("MULTIPLY", s.sstep(s.nz, 0.4, 0.95), s.remap(mid, 0.2, 0.8, 0.1, 0.9))
    base = s.mix(s.math("MULTIPLY", dust, 0.3), base, (0.14, 0.135, 0.125))
    rough = s.mixf(s.sstep(mid, 0.3, 0.7), 0.48, 0.64)
    rough = s.mixf(s.math("MAXIMUM", scuff, edge), rough, 0.8)
    nrm = s.bump(s.math("ADD", s.math("MULTIPLY", fine, 0.6), s.math("MULTIPLY", mid, 0.4)), 0.3, 0.0008)
    s.finish(base, rough, 0.0, nrm)
    return m


def mat_knurl(seed):
    m = bpy.data.materials.new("src_knurl")
    s = Sh(m, seed)
    mid, fine = s.noise(40.0, 4.0, 0.6), s.noise(500.0, 2.0)
    base = s.mix(s.sstep(mid, 0.3, 0.7), (0.016, 0.016, 0.017), (0.026, 0.026, 0.028))
    base, edge = wear(s, base, (0.11, 0.11, 0.115), 0.7)
    rough = s.mixf(edge, s.remap(mid, 0.2, 0.8, 0.42, 0.58), 0.7)
    s.finish(base, rough, 0.0, s.bump(fine, 0.2, 0.0006))
    return m


def mat_rubber(seed):
    m = bpy.data.materials.new("src_rubber")
    s = Sh(m, seed)
    mid, fine = s.noise(35.0, 4.0, 0.6), s.noise(350.0, 3.0)
    base = s.mix(s.sstep(mid, 0.3, 0.7), (0.014, 0.014, 0.015), (0.026, 0.025, 0.025))
    dust = s.math("MULTIPLY", s.sstep(s.nz, 0.1, 0.9), s.remap(fine, 0.3, 0.7, 0.2, 1.0))
    base = s.mix(s.math("MULTIPLY", dust, 0.35), base, (0.09, 0.085, 0.08))
    s.finish(base, s.remap(mid, 0.2, 0.8, 0.86, 0.97), 0.0, s.bump(fine, 0.5, 0.0008))
    return m


def mat_fabric(seed):
    m = bpy.data.materials.new("src_fabric")
    s = Sh(m, seed)
    chk, grain, mid = s.checker(620.0), s.noise(900.0, 1.0), s.noise(30.0, 4.0, 0.6)
    base = s.mix(s.sstep(mid, 0.3, 0.7), (0.020, 0.021, 0.024), (0.040, 0.041, 0.045))
    base = s.mix(chk, base, (0.016, 0.016, 0.018))
    base, edge = wear(s, base, (0.10, 0.10, 0.105), 0.55)
    dust = s.math("MULTIPLY", s.sstep(s.nz, 0.3, 0.95), s.remap(mid, 0.2, 0.8, 0.2, 1.0))
    base = s.mix(s.math("MULTIPLY", dust, 0.35), base, (0.12, 0.115, 0.10))
    h = s.math("ADD", s.math("MULTIPLY", chk, 0.7), s.math("MULTIPLY", grain, 0.3))
    s.finish(base, s.remap(mid, 0.2, 0.8, 0.9, 0.98), 0.0, s.bump(h, 0.6, 0.0007))
    return m


def mat_silver(seed):
    m = bpy.data.materials.new("src_silver")
    s = Sh(m, seed)
    streak, mid = s.noise(120.0, 4.0, 0.6, aniso=(1, 18, 1)), s.noise(30.0, 4.0, 0.6)
    base = s.mix(s.sstep(streak, 0.35, 0.7), (0.30, 0.30, 0.315), (0.43, 0.43, 0.445))
    base, edge = wear(s, base, (0.6, 0.6, 0.61), 0.5)
    s.finish(base, s.remap(mid, 0.2, 0.8, 0.32, 0.5), 0.35, s.bump(streak, 0.15, 0.0003))
    return m


def mat_dark(seed):
    m = bpy.data.materials.new("src_dark")
    s = Sh(m, seed)
    mid = s.noise(40.0, 4.0, 0.6)
    base = s.mix(s.sstep(mid, 0.3, 0.7), (0.022, 0.022, 0.023), (0.034, 0.034, 0.036))
    base, edge = wear(s, base, (0.12, 0.12, 0.125), 0.6)
    s.finish(base, s.remap(mid, 0.2, 0.8, 0.35, 0.5), 0.0, s.bump(s.noise(500.0, 2.0), 0.15, 0.0005))
    return m


# ---------------------------------------------------------------------------------------------- model
# Blender coords while authoring: +Y forward (lens), +Z up, +X operator's right. Origin = eyecup back opening centre.
def build_model():
    P = []
    body_x, body_z = 0.045, -0.0695          # body centre (x right, z below the eye axis)
    lens_x, lens_z = 0.045, -0.062           # lens barrel axis
    top = -0.012                              # body top surface

    # --- body: rounded box + rear battery block + front chin
    body = box("body", (0.110, 0.120, 0.115), (body_x, 0.120, body_z), M_PLASTIC, bevel=0.008, seg=3)
    battery = box("battery", (0.092, 0.058, 0.100), (0.050, 0.047, -0.070), M_PLASTIC, bevel=0.007, seg=3)
    P += [body, battery]
    # viewfinder mount block that blends the tube into the body top
    P.append(box("vf_mount", (0.040, 0.052, 0.014), (0.002, 0.046, top - 0.002), M_PLASTIC, bevel=0.004, seg=2))
    # shallow lens-mount collar plate on the front face
    P.append(box("front_plate", (0.092, 0.006, 0.098), (body_x, 0.1815, body_z), M_DARK, bevel=0.002, seg=1))

    # --- viewfinder: soft rubber eyecup + tube, origin at the back-opening centre, tilted up 3 degrees
    prof = [(0.0, 0.016), (0.0095, 0.016), (0.0105, 0.004), (0.0118, 0.0006), (0.0142, 0.0), (0.0185, 0.0008),
            (0.0205, 0.006), (0.0195, 0.012), (0.0168, 0.0175),
            (0.0153, 0.0205), (0.0153, 0.066), (0.0165, 0.0675), (0.0165, 0.070), (0.0, 0.070)]
    mats = [M_RUBBER] * 9 + [M_PLASTIC] * 4
    mats = mats[:len(prof) - 1] + [M_PLASTIC] * max(0, len(prof) - 1 - len(mats))
    vf = revolve("viewfinder", prof, 28, mats)
    vf.rotation_euler = (math.radians(3.0), 0, 0)
    P.append(vf)

    # --- lens barrel (axis along Y at lens_x, lens_z): collar, knurled focus ring, hood lip, recessed glass
    collar = revolve("lens_collar", [(0.0, 0.172), (0.0335, 0.172), (0.0335, 0.1825), (0.0300, 0.1845), (0.0285, 0.1865),
                                     (0.0285, 0.190), (0.0, 0.190)], 40, [M_PLASTIC] * 6, cx=lens_x, cz=lens_z)
    P.append(collar)
    P.append(knurl_loft("lens_knurl", 0.0278, 0.0267, 44, 0.190, 0.222, lens_x, lens_z, M_KNURL))
    hood = revolve("lens_hood", [(0.0, 0.222), (0.0278, 0.222), (0.0278, 0.2285), (0.0292, 0.2285), (0.0292, 0.240),
                                 (0.0238, 0.240), (0.0238, 0.229), (0.0, 0.229)], 40, [M_KNURL] * 7, cx=lens_x, cz=lens_z)
    P.append(hood)
    gl = revolve("glass", [(0.0, 0.2292), (0.0228, 0.2292), (0.0228, 0.2312), (0.0165, 0.2326), (0.0085, 0.2335), (0.0, 0.2338)],
                 40, [0] * 5, cx=lens_x, cz=lens_z)
    # a small inner element ring so the glass reads as multi-coated
    P.append(gl)
    inner = revolve("lens_inner_ring", [(0.0, 0.2290), (0.0236, 0.2290), (0.0236, 0.2296), (0.0, 0.2296)], 40, [M_DARK] * 3, cx=lens_x, cz=lens_z)
    P.append(inner)

    # --- tally lamp: red dome, front top right
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=0.0042)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.0003], context="VERTS")
    tally = to_obj("tally", bm, 0)
    tally.rotation_euler = (math.radians(-90), 0, 0)   # dome faces +Y
    tally.location = (0.083, 0.1815, -0.030)
    P.append(tally)
    P.append(revolve("tally_bezel", [(0.0058, 0.1805), (0.0058, 0.1830), (0.0046, 0.1830), (0.0046, 0.1805)], 16, [M_DARK] * 3,
                     cx=0.083, cz=-0.030))

    # --- REC button (silver-grey) on the rear face of the battery block, right side
    P.append(box("rec_button", (0.019, 0.0075, 0.011), (0.078, 0.0185, -0.050), M_SILVER, bevel=0.0018, seg=2))
    P.append(box("rec_bezel", (0.025, 0.002, 0.017), (0.078, 0.0205, -0.050), M_DARK, bevel=0.002, seg=1))

    # --- tiny top buttons + zoom rocker
    for i, x in enumerate((0.040, 0.054, 0.068)):
        P.append(revolve(f"btn{i}", [(0.0, 0.0), (0.0042, 0.0), (0.0042, 0.0032), (0.0034, 0.0038), (0.0, 0.0038)], 14, [M_DARK] * 4,
                         cx=0, cz=0))
        P[-1].location = (x, 0.115, top)
        P[-1].rotation_euler = (math.radians(90), 0, 0)   # revolve axis Y -> world Z (up)
    P.append(box("zoom_rocker", (0.016, 0.034, 0.0045), (0.086, 0.100, top + 0.0012), M_DARK, bevel=0.0016, seg=2))
    P.append(box("zoom_ridge", (0.012, 0.002, 0.003), (0.086, 0.100, top + 0.0038), M_SILVER, bevel=0.0006, seg=1))

    # --- cassette door seam on the LEFT side (raised hairline frame) + latch
    sx = -0.010
    y0, y1, z0, z1, t, h = 0.088, 0.168, -0.117, -0.030, 0.0012, 0.0006
    for nm, size, loc in (("seam_t", (h, y1 - y0, t), (sx, (y0 + y1) / 2, z1)), ("seam_b", (h, y1 - y0, t), (sx, (y0 + y1) / 2, z0)),
                          ("seam_f", (h, t, z1 - z0), (sx, y1, (z0 + z1) / 2)), ("seam_r", (h, t, z1 - z0), (sx, y0, (z0 + z1) / 2))):
        P.append(box(nm, size, (loc[0] - h / 2, loc[1], loc[2]), M_PLASTIC))
    P.append(box("door_latch", (0.0035, 0.014, 0.006), (sx - 0.0012, 0.158, -0.108), M_SILVER, bevel=0.001, seg=1))
    # speaker / mic grille slits on the front face, above the lens
    for i in range(5):
        P.append(box(f"grille{i}", (0.0022, 0.002, 0.020), (0.012 + i * 0.0048, 0.1845, -0.0645), M_DARK))

    # --- padded hand strap on the right side (stands about 1.5 cm off the body), front to back
    path = [(0.058, 0.1000), (0.064, 0.1075), (0.074, 0.1130), (0.090, 0.1160), (0.108, 0.1165), (0.126, 0.1165), (0.142, 0.1160),
            (0.158, 0.1130), (0.168, 0.1075), (0.174, 0.1000)]
    pts = [Vector((x, y, -0.066)) for y, x in path]
    n = len(pts)
    wid = [0.012, 0.030, 0.045, 0.048, 0.048, 0.048, 0.048, 0.045, 0.030, 0.012]
    thk = [0.006, 0.010, 0.012, 0.012, 0.012, 0.012, 0.012, 0.012, 0.010, 0.006]
    # beam() takes (width along `side`, height across); path travels in +Y so side=Z gives the band's 4.8 cm height
    P.append(beam("strap", pts, wid, thk, (0, 0, 1), M_FABRIC, bevel=0.0015))
    for y in (0.060, 0.172):
        P.append(box("strap_mount", (0.005, 0.014, 0.036), (0.1015, y, -0.066), M_DARK, bevel=0.0012, seg=1))

    return P


# ---------------------------------------------------------------------------------------------- uv / bake / material
def smooth(ob, angle=40):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))


def unwrap(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(margin=0.003, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def setup_cycles(sc, samples):
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.cycles.device = "CPU"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for t in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = t
                prefs.get_devices()
                devs = [d for d in prefs.devices if d.type == t]
                if devs:
                    for d in prefs.devices:
                        d.use = d.type == t
                    sc.cycles.device = "GPU"
                    break
            except Exception:
                continue
    except Exception:
        pass


def bake_pass(ob, mats, img, btype):
    sc = bpy.context.scene
    for m in mats:
        nt = m.node_tree
        n = nt.nodes.get("BAKE_TARGET") or nt.nodes.new("ShaderNodeTexImage")
        n.name = "BAKE_TARGET"
        n.image = img
        for o in nt.nodes:
            o.select = False
        n.select = True
        nt.nodes.active = n
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bk = sc.render.bake
    bk.use_selected_to_active = False
    bk.margin = 16
    bk.margin_type = "EXTEND"
    bk.use_clear = True
    bk.target = "IMAGE_TEXTURES"
    bk.normal_space = "TANGENT"
    bk.use_pass_direct = False
    bk.use_pass_indirect = False
    bk.use_pass_color = True
    bpy.ops.object.bake(type=btype)


def bake_all(ob, res, samples):
    sc = bpy.context.scene
    setup_cycles(sc, samples)
    mats = [s.material for s in ob.material_slots if s.material]
    BAKED.mkdir(parents=True, exist_ok=True)
    name = "camcorder"

    def newimg(tag, nc):
        im = bpy.data.images.new(f"{name}_{tag}", res, res, alpha=False, float_buffer=False)
        im.colorspace_settings.name = "Non-Color" if nc else "sRGB"
        return im

    base = newimg("basecolor", False); bake_pass(ob, mats, base, "DIFFUSE")
    rough = newimg("rough", True); bake_pass(ob, mats, rough, "ROUGHNESS")
    nrm = newimg("normal", True); sc.cycles.samples = 4; bake_pass(ob, mats, nrm, "NORMAL")
    ao = newimg("ao", True); sc.cycles.samples = max(samples, 32); bake_pass(ob, mats, ao, "AO")
    metal = newimg("metal", True); sc.cycles.samples = 1
    saved = []
    for m in mats:
        nt = m.node_tree
        pb = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        src = out.inputs["Surface"].links[0].from_socket
        em = nt.nodes.new("ShaderNodeEmission")
        v = pb.inputs["Metallic"].default_value
        em.inputs["Color"].default_value = (v, v, v, 1)
        nt.links.new(em.outputs[0], out.inputs["Surface"])
        saved.append((nt, out, src, em))
    bake_pass(ob, mats, metal, "EMIT")
    for nt, out, src, em in saved:
        nt.links.new(src, out.inputs["Surface"])
        nt.nodes.remove(em)

    def px(im):
        a = np.empty(res * res * 4, dtype=np.float32)
        im.pixels.foreach_get(a)
        return a.reshape(res, res, 4)

    a_, r_, m_ = px(ao)[..., 0], px(rough)[..., 0], px(metal)[..., 0]
    orm = bpy.data.images.new(f"{name}_orm", res, res, alpha=False)
    orm.colorspace_settings.name = "Non-Color"
    orm.pixels.foreach_set(np.stack([a_, r_, m_, np.ones_like(a_)], axis=-1).reshape(-1))
    paths = {}
    for tag, im in (("basecolor", base), ("normal", nrm), ("orm", orm)):
        p = BAKED / f"{name}_{tag}.png"
        im.filepath_raw = str(p)
        im.file_format = "PNG"
        im.save()
        paths[tag] = p
    stats = dict(rough_mean=round(float(r_.mean()), 3), ao_mean=round(float(a_.mean()), 3), metal_max=round(float(m_.max()), 3))
    return base, nrm, orm, paths, stats


def body_material(base_img, nrm_img, orm_img):
    m = bpy.data.materials.new("camcorder_body")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    L = nt.links
    pb = nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    L.new(pb.outputs["BSDF"], out.inputs["Surface"])
    tb = nt.nodes.new("ShaderNodeTexImage"); tb.image = base_img
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = nrm_img
    to = nt.nodes.new("ShaderNodeTexImage"); to.image = orm_img
    nm = nt.nodes.new("ShaderNodeNormalMap")
    sp = nt.nodes.new("ShaderNodeSeparateColor")
    L.new(tb.outputs["Color"], pb.inputs["Base Color"])
    L.new(tn.outputs["Color"], nm.inputs["Color"])
    L.new(nm.outputs["Normal"], pb.inputs["Normal"])
    L.new(to.outputs["Color"], sp.inputs["Color"])
    L.new(sp.outputs["Green"], pb.inputs["Roughness"])
    L.new(sp.outputs["Blue"], pb.inputs["Metallic"])
    ng = bpy.data.node_groups.get("glTF Material Output")
    if ng is None:
        ng = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        ng.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    g = nt.nodes.new("ShaderNodeGroup")
    g.node_tree = ng
    L.new(sp.outputs["Red"], g.inputs["Occlusion"])
    return m


def glass_material():
    m = bpy.data.materials.new("lens_glass")
    m.use_nodes = True
    pb = m.node_tree.nodes["Principled BSDF"]
    pb.inputs["Base Color"].default_value = (0.012, 0.016, 0.060, 1)   # dark, slight blue-violet coating
    pb.inputs["Roughness"].default_value = 0.05
    pb.inputs["Metallic"].default_value = 0.0
    return m


def tally_material():
    m = bpy.data.materials.new("tally")
    m.use_nodes = True
    pb = m.node_tree.nodes["Principled BSDF"]
    pb.inputs["Base Color"].default_value = (0.35, 0.01, 0.005, 1)
    pb.inputs["Roughness"].default_value = 0.25
    pb.inputs["Emission Color"].default_value = (1.0, 0.08, 0.05, 1)
    pb.inputs["Emission Strength"].default_value = 2.0
    return m


def export_glb(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True,
                              export_image_format="AUTO", export_materials="EXPORT", export_texcoords=True,
                              export_normals=True, export_tangents=False, export_cameras=False, export_lights=False,
                              export_apply=False)


def glb_info(path):
    data = path.read_bytes()
    jl = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20:20 + jl])
    tris, mn, mx = 0, [1e9] * 3, [-1e9] * 3
    for n in j["nodes"]:
        if "mesh" in n:
            for pr in j["meshes"][n["mesh"]]["primitives"]:
                tris += j["accessors"][pr["indices"]]["count"] // 3
                a = j["accessors"][pr["attributes"]["POSITION"]]
                for i in range(3):
                    mn[i] = min(mn[i], a["min"][i]); mx[i] = max(mx[i], a["max"][i])
    mats = []
    for m in j.get("materials", []):
        mats.append(dict(name=m["name"], emissive=m.get("emissiveFactor"), ext=list(m.get("extensions", {}))))
    imgs = [(i.get("mimeType"), i.get("name")) for i in j.get("images", [])]
    return dict(tris=tris, gltf_bounds_min=[round(v, 4) for v in mn], gltf_bounds_max=[round(v, 4) for v in mx],
                size_xyz_m=[round(mx[i] - mn[i], 4) for i in range(3)], materials=mats, images=imgs, bytes=path.stat().st_size,
                extensions=j.get("extensionsUsed", []))


# ---------------------------------------------------------------------------------------------- preview
def render_view(cam_loc, target, out_path, res=(1100, 820), lens=55, samples=64):
    sc = bpy.context.scene
    setup_cycles(sc, samples)
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("_pv_world")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.32, 0.32, 0.32, 1)
    bg.inputs["Strength"].default_value = 0.35
    sc.world = w

    def area(name, size, energy, loc):
        ld = bpy.data.lights.new(name, "AREA")
        ld.shape, ld.size, ld.energy = "SQUARE", size, energy
        lo = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = (Vector(target) - Vector(loc)).normalized().to_track_quat("-Z", "Y").to_euler()
    t = Vector(target)
    c = Vector(cam_loc)
    fwd = (t - c).normalized()
    right = fwd.cross(Vector((0, 0, 1))).normalized()
    area("_pv_key", 0.7, 20, c + right * -0.25 + Vector((0, 0, 0.35)))
    area("_pv_fill", 1.2, 8, c + right * 0.5 + Vector((0, 0, 0.1)) + fwd * 0.1)
    area("_pv_rim", 0.5, 12, t - fwd * -0.3 + Vector((0, 0, 0.25)) + right * 0.25)
    cd = bpy.data.cameras.new("_pv_cam")
    cd.lens = lens
    cam = bpy.data.objects.new("_pv_cam", cd)
    sc.collection.objects.link(cam)
    cam.location = c
    cam.rotation_euler = (t - c).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = str(out_path)
    sc.render.image_settings.file_format = "PNG"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    for n in [o for o in bpy.data.objects if o.name.startswith("_pv_")]:
        bpy.data.objects.remove(n)


def side_by_side(paths, out):
    ims = [bpy.data.images.load(str(p)) for p in paths]
    arrs = []
    for im in ims:
        w, h = im.size
        a = np.empty(w * h * 4, dtype=np.float32)
        im.pixels.foreach_get(a)
        arrs.append(a.reshape(h, w, 4))
    H = max(a.shape[0] for a in arrs)
    sep = np.full((H, 6, 4), 0.1, dtype=np.float32)
    sep[..., 3] = 1
    row = np.concatenate([arrs[0], sep, arrs[1]], axis=1)
    img = bpy.data.images.new("_sbs", row.shape[1], row.shape[0], alpha=False)
    img.pixels.foreach_set(row.reshape(-1))
    img.filepath_raw = str(out)
    img.file_format = "PNG"
    img.save()


def reimport():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(OUT))
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def report_import(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    tris = sum(tri_count(o) for o in objs)
    print(f"[reimport] blender-space (z-up, lens=+Y) min={tuple(round(v, 4) for v in mn)} max={tuple(round(v, 4) for v in mx)} tris={tris}")
    return mn, mx, tris


# ---------------------------------------------------------------------------------------------- main
def main():
    A = parse_args()
    if A["verify_only"]:
        objs = reimport()
        report_import(objs)
        print("[glb]", json.dumps(glb_info(OUT)))
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(SEED)
    parts = build_model()
    srcs = [mat_plastic(SEED + 1), mat_knurl(SEED + 2), mat_rubber(SEED + 3), mat_fabric(SEED + 4), mat_silver(SEED + 5), mat_dark(SEED + 6)]
    glass_obj = next(o for o in parts if o.name == "glass")
    tally_obj = next(o for o in parts if o.name == "tally")
    atlas_parts = [o for o in parts if o not in (glass_obj, tally_obj)]
    for o in atlas_parts:
        for m in srcs:
            o.data.materials.append(m)
    for o in atlas_parts:
        if "wear" not in o.data.attributes:
            o.data.attributes.new("wear", "FLOAT", "FACE")
    ob = join(atlas_parts, "camcorder")
    smooth(ob)
    unwrap(ob)
    for o in (glass_obj, tally_obj):
        smooth(o)
    bake_info = None
    if A["bake"]:
        base, nrm, orm, paths, bake_info = bake_all(ob, A["res"], A["bake_samples"])
        body_m = body_material(base, nrm, orm)
    else:
        body_m = bpy.data.materials.new("camcorder_body")
    ob.data.materials.clear()
    ob.data.materials.append(body_m)           # slot 0; all atlas faces
    for p in ob.data.polygons:
        p.material_index = 0
    glass_obj.data.materials.clear(); glass_obj.data.materials.append(glass_material())
    tally_obj.data.materials.clear(); tally_obj.data.materials.append(tally_material())
    final = join([ob, glass_obj, tally_obj], "camcorder")
    tris = tri_count(final)
    print(f"[camcorder] tris={tris} slots={[s.material.name for s in final.material_slots]}")
    export_glb(final, OUT)
    gi = glb_info(OUT)
    print("[glb]", json.dumps(gi))

    objs = reimport()
    mn, mx, rt = report_import(objs)
    if A["preview"]:
        ctr = (mn + mx) / 2
        # 1: 3/4 rear view from over the operator's shoulder (rear, a little right and above)
        render_view((0.20, -0.30, 0.13), (0.05, 0.10, -0.05), PREV.with_name("_tmp_rear.png"), samples=A["samples"])
        # 2: 3/4 front view from the front right, slightly above (lens, tally lamp, strap)
        render_view((0.36, 0.52, 0.12), (0.06, 0.10, -0.06), PREV.with_name("_tmp_front.png"), samples=A["samples"])
        # extra (self-check only): rear-left to see the cassette seam and viewfinder
        render_view((-0.22, -0.20, 0.08), (0.04, 0.10, -0.06), PREV_EXTRA, samples=A["samples"])
        side_by_side([PREV.with_name("_tmp_rear.png"), PREV.with_name("_tmp_front.png")], PREV)
        for t in ("_tmp_rear.png", "_tmp_front.png"):
            PREV.with_name(t).unlink()

    manifest = dict(
        asset="camcorder_viewmodel", ticket="L025",
        script="pipeline/blender/build_camcorder.py",
        command='"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b -P pipeline/blender/build_camcorder.py -- --res 1024 --samples 64 --bake-samples 24',
        blender="5.1", seed=SEED, generator="fully procedural (bmesh + modifiers + Cycles bake), no downloads, no paid APIs, no cost",
        output="game/assets/props/player/camcorder.glb",
        textures_dir="pipeline/meshes/baked_camcorder", texture_res=A["res"] if A["bake"] else None,
        textures_embedded_in_glb=True,
        tri_count=gi["tris"], bounds_gltf_min=gi["gltf_bounds_min"], bounds_gltf_max=gi["gltf_bounds_max"], size_m_xyz=gi["size_xyz_m"],
        glb_bytes=gi["bytes"],
        axes=dict(forward="-Z (lens)", up="+Y", right="+X (operator's right)", units="meters",
                  origin="centre of the eyecup back opening (eye position); model extends into -Z",
                  body_offset_m="body centre about +0.045 X, -0.07 Y (glTF); see notes", viewfinder_tilt_deg_front_up=3.0),
        materials=[
            dict(name="camcorder_body", note="one baked atlas: base color / normal (OpenGL +Y) / ORM; plastic base ~0.045 rough ~0.55, knurled matte black ring, rubber eyecup r~0.9, fabric strap r~0.95, silver REC button, edge wear from curvature, fine grain bump"),
            dict(name="lens_glass", base_color_linear=[0.012, 0.016, 0.060], roughness=0.05, metallic=0.0),
            dict(name="tally", base_color_linear=[0.35, 0.01, 0.005], emissive_color=[1.0, 0.08, 0.05], emissive_strength=2.0),
        ],
        parts=dict(body_lwh_m=[0.16, 0.11, 0.115], lens_barrel_dia_m=0.055, lens_barrel_len_m=0.06, viewfinder_dia_m=0.030,
                   viewfinder_len_m=0.070, strap_standoff_m=0.015, knurl_teeth=44, bevel_m=0.008),
        bake=bake_info, glb=gi,
        preview="pipeline/blender/previews/camcorder_preview.png",
    )
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(manifest, indent=2))
    print("[done]")


main()
