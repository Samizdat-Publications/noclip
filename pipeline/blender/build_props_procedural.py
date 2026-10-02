"""Procedural Level 0 props: office chair, CRT monitor, archive box.

One command regenerates all three (fixed seeds, no paid APIs):
  "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b -P pipeline/blender/build_props_procedural.py -- [--only chair,crt,box] [--res 2048] [--samples 64] [--no-bake] [--no-preview]

Pipeline per prop: model with bmesh/modifiers (meters, Blender Z-up, front = -Y) -> join -> smooth by angle ->
smart-project UV + pack -> bake procedural shaders (Cycles) to base color / ORM (AO,roughness,metal) / tangent normal ->
rebuild one clean Principled material from the baked PNGs -> export GLB (Y-up, textures embedded) ->
re-import the GLB in a clean scene and render a Cycles preview.
"""
import bpy, bmesh, math, random, sys, os, json, struct
from pathlib import Path
import numpy as np
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/props/level0"
PREV = ROOT / "pipeline/meshes/previews"
BAKED = ROOT / "pipeline/meshes/baked_props_level0"
MANIFEST = ROOT / "pipeline/manifests/props_level0.json"

SPEC = {
    "chair": dict(name="prop_office_chair", tris=12000, tex=2048, seed=1101),
    "crt": dict(name="prop_crt_monitor", tris=6000, tex=1024, seed=2202),
    "box": dict(name="prop_cardboard_box", tris=4000, tex=2048, seed=3303),
}


def parse_args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(only=list(SPEC), res=None, samples=64, bake=True, preview=True, bake_samples=24)
    i = 0
    while i < len(a):
        if a[i] == "--only": o["only"] = a[i + 1].split(","); i += 1
        elif a[i] == "--res": o["res"] = int(a[i + 1]); i += 1
        elif a[i] == "--samples": o["samples"] = int(a[i + 1]); i += 1
        elif a[i] == "--bake-samples": o["bake_samples"] = int(a[i + 1]); i += 1
        elif a[i] == "--no-bake": o["bake"] = False
        elif a[i] == "--no-preview": o["preview"] = False
        i += 1
    return o


# ----------------------------------------------------------------------------------------------
# scene / mesh helpers
# ----------------------------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene


def to_obj(name, bm, mat=None, mat_index=0):
    me = bpy.data.meshes.new(name)
    for f in bm.faces:
        f.material_index = mat_index
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    mats = mat if isinstance(mat, (list, tuple)) else ([mat] if mat else [])
    for m in mats:
        me.materials.append(m)
    return ob


def apply_mods(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return ob


def add_bevel(ob, width, seg=2, angle=35):
    m = ob.modifiers.new("bev", "BEVEL")
    m.width = width
    m.segments = seg
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    apply_mods(ob)


def deform(ob, fn):
    me = ob.data
    for v in me.vertices:
        v.co = fn(v.co.copy())
    me.update()


def round_plan(p, ax, ay, n, i0="x", i1="y"):
    """Pull the corners of a rectangular plan outline into a superellipse (rounded corners), smooth through the interior."""
    u, v = getattr(p, i0) / ax, getattr(p, i1) / ay
    m = max(abs(u), abs(v))
    nn = (abs(u) ** n + abs(v) ** n) ** (1.0 / n)
    if nn > 1e-6 and m > 1e-6:
        f = m / nn
        setattr(p, i0, getattr(p, i0) * f)
        setattr(p, i1, getattr(p, i1) * f)
    return p


def smoothstep(a, b, x):
    if a == b:
        return 0.0 if x < a else 1.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def box_obj(name, size, loc, mat, rot=(0, 0, 0), bevel=0.0, seg=2, cuts=0, angle=35, mat_index=0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if cuts:
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    ob = to_obj(name, bm, mat, mat_index)
    ob.location = loc
    ob.rotation_euler = rot
    if bevel:
        add_bevel(ob, bevel, seg, angle)
    return ob


def cyl_obj(name, r1, r2, h, loc, mat, segs=16, rot=(0, 0, 0), bevel=0.0, seg=1, angle=35):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    ob = to_obj(name, bm, mat)
    ob.location = loc
    ob.rotation_euler = rot
    if bevel:
        add_bevel(ob, bevel, seg, angle)
    return ob


def loft(name, rings, mat, caps=(True, True)):
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for i in range(len(rings) - 1):
        for j in range(n):
            k = (j + 1) % n
            bm.faces.new((vs[i][j], vs[i][k], vs[i + 1][k], vs[i + 1][j]))
    if caps[0]:
        bm.faces.new(vs[0][::-1])
    if caps[1]:
        bm.faces.new(vs[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return to_obj(name, bm, mat)


def frames(pts, side):
    out = []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        t = (Vector(b) - Vector(a)).normalized()
        w = (Vector(side) - t * Vector(side).dot(t)).normalized()
        h = t.cross(w).normalized()
        out.append((Vector(p), w, h))
    return out


def chamfer_rect(c, w, h, ww, hh, ch=0.35):
    a, b = ww / 2, hh / 2
    k = min(a, b) * ch
    pts = [(a, -(b - k)), (a, b - k), (a - k, b), (-(a - k), b), (-a, b - k), (-a, -(b - k)), (-(a - k), -b), (a - k, -b)]
    return [c + w * x + h * y for x, y in pts]


def beam(name, pts, widths, heights, side, mat, bevel=0.0, seg=1, ch=0.35):
    rings = []
    for (p, w, h), ww, hh in zip(frames(pts, side), widths, heights):
        rings.append(chamfer_rect(p, w, h, ww, hh, ch))
    ob = loft(name, rings, mat)
    if bevel:
        add_bevel(ob, bevel, seg, 30)
    return ob


def tube(name, pts, radii, up, mat, segs=8):
    rings = []
    for (p, w, h), r in zip(frames(pts, up), radii):
        rings.append([p + (w * math.cos(2 * math.pi * k / segs) + h * math.sin(2 * math.pi * k / segs)) * r for k in range(segs)])
    return loft(name, rings, mat)


def se_ring(cx, y, zc, hw, hh, n=4.0, count=28):
    pts = []
    for k in range(count):
        t = 2 * math.pi * k / count
        c, s = math.cos(t), math.sin(t)
        pts.append(Vector((cx + hw * math.copysign(abs(c) ** (2 / n), c), y, zc + hh * math.copysign(abs(s) ** (2 / n), s))))
    return pts


def boolean_diff(target, cutters):
    # join cutters (they keep their own materials -> new cut faces take the cutter's material)
    bpy.ops.object.select_all(action="DESELECT")
    for c in cutters:
        c.select_set(True)
    bpy.context.view_layer.objects.active = cutters[0]
    if len(cutters) > 1:
        bpy.ops.object.join()
    cut = bpy.context.view_layer.objects.active
    m = target.modifiers.new("bool", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.solver = "EXACT"
    m.object = cut
    m.use_self = True
    apply_mods(target)
    bpy.data.objects.remove(cut)


def join(objs, name):
    bpy.context.view_layer.update()
    for o in objs:   # bake every transform into the mesh so the joined origin is the world origin
        mw = o.matrix_world.copy()
        o.data.transform(mw)
        if os.environ.get("PROP_DEBUG"):
            print("PART", o.name, sum(len(q.vertices) - 2 for q in o.data.polygons))
            zs = [v.co.z for v in o.data.vertices]
            if zs and min(zs) < -0.001:
                print("DEBUG below floor:", o.name, round(min(zs), 4))
        o.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def world_bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))


# ----------------------------------------------------------------------------------------------
# procedural shader builder
# ----------------------------------------------------------------------------------------------
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
        self.nrm = self.geo.outputs["Normal"]
        self.pt = self.geo.outputs["Pointiness"]
        sep = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.obj, sep.inputs[0])
        self.x, self.y, self.z = sep.outputs[0], sep.outputs[1], sep.outputs[2]
        sn = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self.nt.links.new(self.nrm, sn.inputs[0])
        self.nx, self.ny, self.nz = sn.outputs[0], sn.outputs[1], sn.outputs[2]

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

    def node(self, typ, **ins):
        n = self.nt.nodes.new(typ)
        for k, v in ins.items():
            self.put(n.inputs[k], v)
        return n

    def noise(self, scale, detail=3.0, rough=0.5, dist=0.0, aniso=(1, 1, 1), lac=2.0, vec=None):
        mp = self.nt.nodes.new("ShaderNodeMapping")
        off = (self.rng.uniform(-50, 50), self.rng.uniform(-50, 50), self.rng.uniform(-50, 50))
        mp.inputs["Location"].default_value = off
        mp.inputs["Scale"].default_value = aniso
        self.nt.links.new(vec if vec is not None else self.obj, mp.inputs["Vector"])
        n = self.nt.nodes.new("ShaderNodeTexNoise")
        n.noise_dimensions = "3D"
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = dist
        n.inputs["Lacunarity"].default_value = lac
        self.nt.links.new(mp.outputs[0], n.inputs["Vector"])
        return n.outputs["Fac"]

    def math(self, op, a, b=None, c=None, clamp=False):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        self.put(n.inputs[0], a)
        if b is not None:
            self.put(n.inputs[1], b)
        if c is not None:
            self.put(n.inputs[2], c)
        return n.outputs[0]

    def sstep(self, x, lo, hi):
        # smoothstep that also works when lo > hi (inverse ramp)
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
        n.blend_type = "MIX"
        n.clamp_factor = True
        self.put(n.inputs[0], fac)
        self.put(n.inputs[6], a)
        self.put(n.inputs[7], b)
        return n.outputs[2]

    def mul(self, a, b, fac=1.0):
        n = self.nt.nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        n.blend_type = "MULTIPLY"
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

    def ramp(self, fac, stops):
        n = self.nt.nodes.new("ShaderNodeValToRGB")
        cr = n.color_ramp
        cr.elements[0].position = stops[0][0]
        cr.elements[0].color = stops[0][1]
        cr.elements[1].position = stops[-1][0]
        cr.elements[1].color = stops[-1][1]
        for pos, col in stops[1:-1]:
            e = cr.elements.new(pos)
            e.color = col
        self.nt.links.new(fac, n.inputs[0])
        return n.outputs[0]

    def checker(self, scale):
        n = self.nt.nodes.new("ShaderNodeTexChecker")
        n.inputs["Scale"].default_value = scale
        self.nt.links.new(self.obj, n.inputs["Vector"])
        return n.outputs["Fac"]

    def voronoi(self, scale, feature="F1", out="Distance", rnd=1.0):
        mp = self.nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Location"].default_value = (self.rng.uniform(-50, 50),) * 3
        self.nt.links.new(self.obj, mp.inputs["Vector"])
        n = self.nt.nodes.new("ShaderNodeTexVoronoi")
        n.voronoi_dimensions = "3D"
        n.feature = feature
        n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = rnd
        self.nt.links.new(mp.outputs[0], n.inputs["Vector"])
        return n.outputs[out]

    def bump(self, height, strength=0.3, dist=0.001):
        n = self.nt.nodes.new("ShaderNodeBump")
        n.inputs["Strength"].default_value = strength
        n.inputs["Distance"].default_value = dist
        self.nt.links.new(height, n.inputs["Height"])
        return n.outputs["Normal"]

    def finish(self, base, rough, metal=0.0, normal=None, emission=None):
        pb = self.nt.nodes.new("ShaderNodeBsdfPrincipled")
        self.put(pb.inputs["Base Color"], base)
        self.put(pb.inputs["Roughness"], rough)
        pb.inputs["Metallic"].default_value = float(metal) if not isinstance(metal, bpy.types.NodeSocket) else 0.0
        if isinstance(metal, bpy.types.NodeSocket):
            self.nt.links.new(metal, pb.inputs["Metallic"])
        if normal is not None:
            self.nt.links.new(normal, pb.inputs["Normal"])
        out = self.nt.nodes.new("ShaderNodeOutputMaterial")
        self.nt.links.new(pb.outputs["BSDF"], out.inputs["Surface"])
        return pb


def new_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m


def mat_fabric(seed):
    m = new_mat("fabric_charcoal")
    s = Sh(m, seed)
    chk = s.checker(240.0)
    grain = s.noise(900.0, 1.0)
    mid = s.noise(45.0, 5.0, 0.55)
    big = s.noise(5.0, 3.0)
    blot = s.noise(11.0, 4.0, 0.6)
    base = s.mix(s.sstep(big, 0.3, 0.72), (0.036, 0.039, 0.045), (0.085, 0.087, 0.092))
    base = s.mul(base, s.mix(grain, (0.75, 0.75, 0.78), (1.2, 1.2, 1.2)))
    base = s.mul(base, s.mix(chk, (0.82, 0.82, 0.82), (1.12, 1.12, 1.12)), 0.9)
    # seat front edge faded lighter (seat only: z below the backrest)
    front = s.math("MULTIPLY", s.sstep(s.y, -0.11, -0.24), s.math("MULTIPLY", s.sstep(s.z, 0.56, 0.5), 1.0))
    front = s.math("MULTIPLY", front, s.remap(mid, 0.2, 0.8, 0.55, 1.0))
    base = s.mix(s.math("MULTIPLY", front, 0.9), base, (0.185, 0.186, 0.19))
    # centre-of-seat wear (shiny, lighter)
    r2 = s.math("ADD", s.math("MULTIPLY", s.x, s.x), s.math("MULTIPLY", s.math("ADD", s.y, 0.02), s.math("ADD", s.y, 0.02)))
    wear = s.math("MULTIPLY", s.sstep(r2, 0.045, 0.0), s.sstep(s.z, 0.56, 0.5))
    base = s.mix(s.math("MULTIPLY", wear, 0.45), base, (0.115, 0.118, 0.122))
    # backrest lumbar wear and top-edge hand wear
    wb = s.math("MULTIPLY", s.sstep(s.math("ADD", s.math("MULTIPLY", s.x, s.x), s.math("MULTIPLY", s.math("SUBTRACT", s.z, 0.72), s.math("SUBTRACT", s.z, 0.72))), 0.03, 0.0), s.sstep(s.z, 0.56, 0.6))
    base = s.mix(s.math("MULTIPLY", wb, 0.3), base, (0.12, 0.122, 0.125))
    # stains: brown blotches + a pale dried splash
    st = s.sstep(blot, 0.60, 0.70)
    base = s.mix(s.math("MULTIPLY", st, 0.8), base, (0.030, 0.023, 0.017))
    sp = s.sstep(s.noise(23.0, 4.0, 0.6), 0.64, 0.72)
    base = s.mix(s.math("MULTIPLY", sp, 0.55), base, (0.135, 0.125, 0.105))
    # dust on up-facing surfaces
    dust = s.math("MULTIPLY", s.sstep(s.nz, 0.35, 0.95), s.remap(mid, 0.2, 0.8, 0.2, 0.9))
    base = s.mix(s.math("MULTIPLY", dust, 0.4), base, (0.19, 0.185, 0.17))
    # upholstery seams
    seam_dist = s.math("ABSOLUTE", s.math("SUBTRACT", s.math("ABSOLUTE", s.x), 0.085))
    seam_b = s.math("MULTIPLY", s.sstep(seam_dist, 0.0022, 0.0006), s.sstep(s.z, 0.575, 0.585))
    seat_d = s.math("ABSOLUTE", s.math("SUBTRACT", s.math("ABSOLUTE", s.x), 0.125))
    seam_s = s.math("MULTIPLY", s.sstep(seat_d, 0.0022, 0.0006), s.sstep(s.z, 0.52, 0.49))
    seam_s = s.math("MULTIPLY", seam_s, s.sstep(s.nz, 0.3, 0.7))
    seam = s.math("MAXIMUM", seam_b, seam_s)
    base = s.mul(base, (0.40, 0.40, 0.42), seam)
    cav = s.sstep(s.pt, 0.49, 0.40)
    base = s.mul(base, (0.6, 0.6, 0.6), cav)
    h = s.math("ADD", s.math("MULTIPLY", chk, 0.55), s.math("MULTIPLY", grain, 0.45))
    h = s.math("SUBTRACT", h, s.math("MULTIPLY", seam, 1.4))
    nrm = s.bump(h, 0.7, 0.0012)
    rough = s.remap(mid, 0.2, 0.8, 0.78, 0.97)
    rough = s.mixf(s.math("MAXIMUM", wear, front), rough, 0.62)
    s.finish(base, rough, 0.0, nrm)
    return m


def mat_plastic_black(seed):
    m = new_mat("plastic_black")
    s = Sh(m, seed)
    mid = s.noise(30.0, 4.0, 0.6)
    fine = s.noise(500.0, 2.0)
    big = s.noise(4.0, 3.0)
    base = s.mix(s.sstep(big, 0.3, 0.7), (0.020, 0.020, 0.021), (0.034, 0.034, 0.036))
    scuff = s.sstep(s.noise(60.0, 6.0, 0.65, aniso=(1, 1, 6)), 0.6, 0.78)
    base = s.mix(s.math("MULTIPLY", scuff, 0.7), base, (0.075, 0.075, 0.078))
    edge = s.sstep(s.pt, 0.505, 0.58)
    base = s.mix(s.math("MULTIPLY", edge, 0.8), base, (0.085, 0.085, 0.09))
    cav = s.sstep(s.pt, 0.495, 0.42)
    base = s.mix(s.math("MULTIPLY", cav, 0.5), base, (0.10, 0.095, 0.085))
    dust = s.math("MULTIPLY", s.sstep(s.nz, 0.3, 0.95), s.remap(mid, 0.2, 0.8, 0.15, 1.0))
    base = s.mix(s.math("MULTIPLY", dust, 0.5), base, (0.15, 0.145, 0.135))
    rough = s.mixf(s.sstep(mid, 0.3, 0.7), 0.36, 0.62)
    rough = s.mixf(s.math("MAXIMUM", scuff, dust), rough, 0.75)
    nrm = s.bump(s.math("ADD", s.math("MULTIPLY", fine, 0.6), s.math("MULTIPLY", mid, 0.4)), 0.25, 0.0008)
    s.finish(base, rough, 0.0, nrm)
    return m


def mat_rubber(seed):
    m = new_mat("rubber_gray")
    s = Sh(m, seed)
    mid = s.noise(35.0, 4.0, 0.6)
    fine = s.noise(400.0, 2.0)
    base = s.mix(s.sstep(mid, 0.3, 0.7), (0.030, 0.030, 0.032), (0.060, 0.058, 0.055))
    dust = s.math("MULTIPLY", s.sstep(s.nz, 0.1, 0.9), s.remap(fine, 0.3, 0.7, 0.2, 1.0))
    base = s.mix(s.math("MULTIPLY", dust, 0.4), base, (0.14, 0.135, 0.125))
    nrm = s.bump(fine, 0.3, 0.0008)
    s.finish(base, s.remap(mid, 0.2, 0.8, 0.6, 0.85), 0.0, nrm)
    return m


def mat_steel(seed):
    m = new_mat("steel_worn")
    s = Sh(m, seed)
    mid = s.noise(40.0, 5.0, 0.6)
    streak = s.noise(120.0, 4.0, 0.6, aniso=(1, 1, 18))
    rust = s.sstep(s.noise(14.0, 5.0, 0.65), 0.58, 0.72)
    base = s.mix(s.sstep(streak, 0.35, 0.7), (0.38, 0.38, 0.39), (0.58, 0.58, 0.60))
    base = s.mix(s.math("MULTIPLY", rust, 0.85), base, (0.22, 0.09, 0.04))
    rough = s.remap(s.math("ADD", s.math("MULTIPLY", streak, 0.6), s.math("MULTIPLY", mid, 0.4)), 0.2, 0.8, 0.28, 0.62)
    rough = s.mixf(rust, rough, 0.85)
    nrm = s.bump(streak, 0.15, 0.0004)
    s.finish(base, rough, s.mixf(rust, 1.0, 0.25), nrm)
    return m


def mat_beige(seed):
    m = new_mat("plastic_beige_aged")
    s = Sh(m, seed)
    big = s.noise(3.0, 4.0, 0.6)
    mid = s.noise(22.0, 5.0, 0.62)
    grain = s.noise(260.0, 2.0)
    fine = s.noise(420.0, 2.0)
    streak = s.noise(16.0, 4.0, 0.62, aniso=(1.6, 1.6, 0.10))
    base = s.mix(s.sstep(big, 0.25, 0.75), (0.36, 0.285, 0.165), (0.52, 0.405, 0.215))
    base = s.mul(base, s.mix(grain, (0.9, 0.9, 0.9), (1.1, 1.1, 1.1)))
    # sun/age yellowing, worse on top faces and at the front
    yel = s.math("MULTIPLY", s.sstep(s.z, 0.14, 0.37), s.remap(mid, 0.2, 0.8, 0.3, 1.0))
    base = s.mix(s.math("MULTIPLY", yel, 0.65), base, (0.47, 0.31, 0.11))
    # grime: heavy near the bottom and at the rear, blotchy
    grime = s.math("MAXIMUM", s.sstep(s.z, 0.20, 0.04), s.math("MULTIPLY", s.sstep(s.y, -0.02, 0.16), 0.6))
    base = s.mix(s.math("MULTIPLY", grime, s.remap(mid, 0.2, 0.8, 0.35, 0.95)), base, (0.17, 0.13, 0.075))
    # dirty run marks / handling smudges
    sm = s.sstep(streak, 0.52, 0.74)
    base = s.mix(s.math("MULTIPLY", sm, 0.65), base, (0.21, 0.155, 0.08))
    # grease smudges where hands touch (chin, top edges)
    hand = s.math("MULTIPLY", s.sstep(s.noise(40.0, 3.0), 0.55, 0.72), s.sstep(s.z, 0.14, 0.09))
    base = s.mix(s.math("MULTIPLY", hand, 0.6), base, (0.25, 0.19, 0.10))
    edge = s.sstep(s.pt, 0.505, 0.58)
    base = s.mix(s.math("MULTIPLY", edge, 0.45), base, (0.56, 0.46, 0.29))
    cav = s.sstep(s.pt, 0.495, 0.42)
    base = s.mix(s.math("MULTIPLY", cav, 0.75), base, (0.10, 0.07, 0.04))
    dust = s.math("MULTIPLY", s.sstep(s.nz, 0.4, 0.95), s.remap(mid, 0.2, 0.8, 0.15, 1.0))
    base = s.mix(s.math("MULTIPLY", dust, 0.5), base, (0.45, 0.41, 0.33))
    rough = s.mixf(s.sstep(mid, 0.3, 0.7), 0.36, 0.66)
    rough = s.mixf(s.math("MAXIMUM", sm, dust), rough, 0.85)
    rough = s.mixf(hand, rough, 0.3)
    nrm = s.bump(s.math("ADD", s.math("MULTIPLY", fine, 0.7), s.math("MULTIPLY", mid, 0.3)), 0.25, 0.0007)
    s.finish(base, rough, 0.0, nrm)
    return m


def mat_glass(seed):
    m = new_mat("crt_glass_dusty")
    s = Sh(m, seed)
    mid = s.noise(22.0, 5.0, 0.6)
    fine = s.noise(300.0, 3.0)
    smear = s.noise(9.0, 4.0, 0.6, aniso=(1.0, 1.0, 2.5))
    rr = s.math("ADD", s.math("MULTIPLY", s.math("DIVIDE", s.x, 0.15), s.math("DIVIDE", s.x, 0.15)),
                s.math("MULTIPLY", s.math("DIVIDE", s.math("SUBTRACT", s.z, 0.2275), 0.12), s.math("DIVIDE", s.math("SUBTRACT", s.z, 0.2275), 0.12)))
    base = s.mix(s.sstep(rr, 0.0, 1.6), (0.040, 0.054, 0.047), (0.022, 0.031, 0.027))
    dust = s.math("ADD", s.math("MULTIPLY", s.sstep(smear, 0.45, 0.85), 0.40), s.math("MULTIPLY", s.sstep(rr, 0.9, 2.0), 0.35))
    dust = s.math("MULTIPLY", dust, s.remap(fine, 0.3, 0.7, 0.55, 1.0))
    base = s.mix(s.math("MULTIPLY", dust, 0.8), base, (0.19, 0.185, 0.165))
    rough = s.mixf(s.math("MINIMUM", dust, 1.0), 0.045, 0.55)
    s.finish(base, rough, 0.0, None)
    return m


def mat_led(seed):
    m = new_mat("led_green")
    s = Sh(m, seed)
    pb = s.finish((0.03, 0.18, 0.05), 0.2, 0.0, None)
    return m


def mat_cardboard_outer(seed):
    m = new_mat("cardboard_outer")
    s = Sh(m, seed)
    mid = s.noise(30.0, 5.0, 0.6)
    fibre = s.noise(260.0, 3.0, 0.6, aniso=(1.0, 1.0, 0.25))
    fibre2 = s.noise(90.0, 4.0, 0.6, aniso=(1.0, 1.0, 0.2))
    big = s.noise(3.5, 3.0)
    flute = s.math("SINE", s.math("MULTIPLY", s.math("ADD", s.x, s.y), 2 * math.pi / 0.008))
    base = s.mix(s.sstep(big, 0.25, 0.75), (0.36, 0.235, 0.12), (0.52, 0.365, 0.19))
    base = s.mul(base, s.mix(fibre, (0.8, 0.8, 0.8), (1.15, 1.15, 1.15)))
    base = s.mul(base, s.mix(fibre2, (0.88, 0.88, 0.88), (1.1, 1.1, 1.1)))
    # faded, sun/dust-bleached upper half
    base = s.mix(s.math("MULTIPLY", s.sstep(s.z, 0.12, 0.3), 0.35), base, (0.55, 0.43, 0.26))
    # faded one-colour print frame on the long front face (no text)
    fx = s.math("ABSOLUTE", s.math("SUBTRACT", s.math("ABSOLUTE", s.x), 0.14))
    fz = s.math("ABSOLUTE", s.math("SUBTRACT", s.z, 0.175))
    fz2 = s.math("ABSOLUTE", s.math("SUBTRACT", fz, 0.0))
    frame_v = s.math("MULTIPLY", s.sstep(fx, 0.0026, 0.0012), s.sstep(fz, 0.062, 0.058))
    frame_h = s.math("MULTIPLY", s.sstep(s.math("ABSOLUTE", s.math("SUBTRACT", fz, 0.06)), 0.0026, 0.0012), s.sstep(s.math("ABSOLUTE", s.x), 0.142, 0.138))
    frame = s.math("MAXIMUM", frame_v, frame_h)
    frame = s.math("MULTIPLY", frame, s.math("MULTIPLY", s.sstep(s.y, -0.13, -0.15), s.remap(mid, 0.25, 0.75, 0.25, 0.8)))
    base = s.mix(s.math("MULTIPLY", frame, 0.7), base, (0.17, 0.10, 0.06))
    # scuffs and abrasion: lighter fibres where edges rub
    edge = s.sstep(s.pt, 0.51, 0.6)
    base = s.mix(s.math("MULTIPLY", edge, 0.6), base, (0.62, 0.50, 0.32))
    # water damage: wobbling tide line, 6..10 cm up the sides
    tide = s.math("ADD", 0.055, s.math("ADD", s.math("MULTIPLY", s.remap(s.noise(7.0, 3.0, 0.5, aniso=(1.0, 1.0, 0.3)), 0.3, 0.7), 0.04),
                                       s.math("MULTIPLY", s.remap(s.noise(55.0, 3.0, 0.5, aniso=(1.0, 1.0, 0.4)), 0.3, 0.7), 0.012)))
    wet = s.sstep(s.z, s.math("ADD", tide, 0.006), s.math("SUBTRACT", tide, 0.012))
    deep = s.sstep(s.z, tide, 0.0)
    base = s.mix(s.math("MULTIPLY", wet, 0.85), base, (0.26, 0.155, 0.075))
    base = s.mix(s.math("MULTIPLY", deep, 0.55), base, (0.14, 0.08, 0.04))
    line = s.sstep(s.math("ABSOLUTE", s.math("SUBTRACT", s.z, tide)), 0.0050, 0.0008)
    line = s.math("MULTIPLY", line, s.remap(mid, 0.2, 0.8, 0.4, 1.0))
    base = s.mix(s.math("MULTIPLY", line, 0.75), base, (0.13, 0.075, 0.035))
    halo = s.math("MULTIPLY", s.sstep(s.math("ABSOLUTE", s.math("SUBTRACT", s.z, s.math("ADD", tide, 0.014))), 0.014, 0.0), 0.35)
    base = s.mix(halo, base, (0.50, 0.36, 0.16))
    # mould specks and dark grime in the damp zone
    mold = s.math("MULTIPLY", s.sstep(s.voronoi(170.0, "F1", "Distance"), 0.09, 0.03), wet)
    mold = s.math("MULTIPLY", mold, s.sstep(s.noise(25.0, 3.0), 0.5, 0.7))
    base = s.mix(s.math("MULTIPLY", mold, 0.85), base, (0.040, 0.046, 0.032))
    # general dust / grime on up-facing parts
    dust = s.math("MULTIPLY", s.sstep(s.nz, 0.5, 0.95), s.remap(mid, 0.2, 0.8, 0.3, 1.0))
    base = s.mix(s.math("MULTIPLY", dust, 0.25), base, (0.50, 0.46, 0.38))
    h = s.math("ADD", s.math("MULTIPLY", fibre, 0.5), s.math("ADD", s.math("MULTIPLY", flute, 0.05), s.math("MULTIPLY", fibre2, 0.35)))
    nrm = s.bump(h, 0.45, 0.0007)
    rough = s.mixf(wet, s.remap(mid, 0.2, 0.8, 0.8, 0.95), 0.7)
    s.finish(base, rough, 0.0, nrm)
    return m


def mat_cardboard_inner(seed):
    m = new_mat("cardboard_inner")
    s = Sh(m, seed)
    mid = s.noise(30.0, 5.0, 0.6)
    fibre = s.noise(240.0, 3.0, 0.6, aniso=(1.0, 1.0, 0.3))
    big = s.noise(4.0, 3.0)
    base = s.mix(s.sstep(big, 0.3, 0.7), (0.56, 0.42, 0.25), (0.62, 0.48, 0.30))
    base = s.mul(base, s.mix(fibre, (0.86, 0.86, 0.86), (1.1, 1.1, 1.1)))
    tide = s.math("ADD", 0.05, s.math("MULTIPLY", s.remap(s.noise(8.0, 3.0, 0.5), 0.3, 0.7), 0.04))
    wet = s.sstep(s.z, s.math("ADD", tide, 0.004), s.math("SUBTRACT", tide, 0.006))
    base = s.mix(s.math("MULTIPLY", wet, 0.8), base, (0.26, 0.17, 0.09))
    line = s.sstep(s.math("ABSOLUTE", s.math("SUBTRACT", s.z, tide)), 0.004, 0.0005)
    base = s.mix(s.math("MULTIPLY", line, 0.6), base, (0.15, 0.09, 0.045))
    mold = s.math("MULTIPLY", s.sstep(s.voronoi(120.0, "F1", "Distance"), 0.09, 0.03), wet)
    base = s.mix(s.math("MULTIPLY", mold, 0.7), base, (0.05, 0.055, 0.04))
    nrm = s.bump(fibre, 0.3, 0.0006)
    s.finish(base, s.remap(mid, 0.2, 0.8, 0.85, 0.96), 0.0, nrm)
    return m


def mat_cardboard_edge(seed):
    """Cut edge of corrugated board: liner / flute / liner seen end-on (rim faces, handle-hole faces)."""
    m = new_mat("cardboard_edge")
    s = Sh(m, seed)
    mid = s.noise(30.0, 4.0, 0.6)
    fibre = s.noise(500.0, 2.0)
    fac = s.sstep(s.math("ABSOLUTE", s.y), 0.1, 0.14)
    along = s.mixf(fac, s.y, s.x)
    across = s.mixf(fac, s.math("ABSOLUTE", s.x), s.math("ABSOLUTE", s.y))
    t = s.math("MODULO", across, 0.004)
    wave = s.math("MULTIPLY", s.math("SINE", s.math("MULTIPLY", along, 2 * math.pi / 0.0075)), 0.0011)
    centre = s.math("ADD", 0.002, wave)
    paper = s.sstep(s.math("ABSOLUTE", s.math("SUBTRACT", t, centre)), 0.0009, 0.0004)
    liner = s.math("MAXIMUM", s.sstep(t, 0.0011, 0.0006), s.sstep(t, 0.0029, 0.0034))
    solid = s.math("MAXIMUM", paper, liner)
    base = s.mix(solid, (0.18, 0.105, 0.05), (0.50, 0.37, 0.20))
    base = s.mul(base, s.mix(fibre, (0.85, 0.85, 0.85), (1.1, 1.1, 1.1)))
    wet = s.sstep(s.z, 0.1, 0.06)
    base = s.mix(s.math("MULTIPLY", wet, 0.7), base, (0.18, 0.11, 0.055))
    nrm = s.bump(s.math("ADD", solid, s.math("MULTIPLY", fibre, 0.2)), 0.8, 0.0015)
    s.finish(base, s.remap(mid, 0.2, 0.8, 0.85, 0.97), 0.0, nrm)
    return m


# ----------------------------------------------------------------------------------------------
# PROP 1: office chair (front = -Y, floor z=0, Blender Z-up)
# ----------------------------------------------------------------------------------------------
def build_chair(seed):
    rng = random.Random(seed)
    fab = mat_fabric(seed + 1)
    pla = mat_plastic_black(seed + 2)
    rub = mat_rubber(seed + 3)
    ste = mat_steel(seed + 4)
    parts = []

    # five-star base
    hub = cyl_obj("hub", 0.052, 0.044, 0.056, (0, 0, 0.112), pla, 20, bevel=0.005, seg=2)
    parts.append(hub)
    for k in range(5):
        a = math.radians(90 + 72 * k)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        prof = [(0.030, 0.113, 0.064, 0.042), (0.095, 0.105, 0.058, 0.035), (0.185, 0.094, 0.048, 0.030),
                (0.255, 0.086, 0.040, 0.027), (0.312, 0.080, 0.036, 0.025)]
        pts = [d * r + Vector((0, 0, z)) for r, z, _, _ in prof]
        arm = beam(f"arm{k}", pts, [p[2] for p in prof], [p[3] for p in prof], side, pla, bevel=0.003, seg=2)
        parts.append(arm)
        # caster at arm tip
        tip = d * 0.312
        heading = a + math.radians(rng.uniform(-70, 70))
        hd = Vector((math.cos(heading), math.sin(heading), 0))
        hs = Vector((-hd.y, hd.x, 0))
        parts.append(cyl_obj(f"stem{k}", 0.0065, 0.0065, 0.030, (tip.x, tip.y, 0.072), ste, 10))
        parts.append(cyl_obj(f"cap{k}", 0.0175, 0.0155, 0.014, (tip.x, tip.y, 0.0615), pla, 14, bevel=0.002, seg=1))
        for sgn in (-1, 1):
            plate = box_obj(f"fork{k}{sgn}", (0.0035, 0.030, 0.036), Vector((tip.x, tip.y, 0.0415)) + hs * (0.0165 * sgn) + hd * 0.004, pla,
                            rot=(0, 0, heading + math.pi / 2), bevel=0.0012, seg=1)
            parts.append(plate)
            wc = Vector((tip.x, tip.y, 0.0262)) + hs * (0.0075 * sgn) + hd * 0.013
            wh = cyl_obj(f"wheel{k}{sgn}", 0.0262, 0.0262, 0.0105, wc, rub, 12, rot=(0, math.pi / 2, heading + math.pi / 2), bevel=0.0018, seg=1)
            parts.append(wh)
        ax = Vector((tip.x, tip.y, 0.0262)) + hd * 0.013
        parts.append(cyl_obj(f"axle{k}", 0.0035, 0.0035, 0.040, ax, ste, 8, rot=(0, math.pi / 2, heading + math.pi / 2)))

    # gas lift column
    parts.append(cyl_obj("skirt", 0.045, 0.031, 0.175, (0, 0, 0.2225), pla, 22, bevel=0.003, seg=1))
    parts.append(cyl_obj("tele", 0.0245, 0.0245, 0.060, (0, 0, 0.315), pla, 18, bevel=0.002, seg=1))
    parts.append(cyl_obj("piston", 0.0155, 0.0155, 0.075, (0, 0, 0.3675), ste, 14))
    # seat mechanism / pan
    parts.append(box_obj("mech", (0.21, 0.20, 0.036), (0, 0.02, 0.389), pla, bevel=0.007, seg=2))
    pan = box_obj("pan", (0.440, 0.410, 0.026), (0, -0.012, 0.420), pla, bevel=0.010, seg=3, cuts=3)
    deform(pan, lambda p: round_plan(p, 0.22, 0.205, 3.6))
    parts.append(pan)
    parts.append(cyl_obj("tiltknob", 0.019, 0.017, 0.032, (-0.05, -0.095, 0.386), pla, 14, rot=(math.pi / 2, 0, 0), bevel=0.002, seg=1))
    lever = tube("lever", [Vector(p) for p in [(0.10, 0.03, 0.384), (0.15, 0.03, 0.384), (0.178, 0.03, 0.372), (0.185, 0.03, 0.345)]],
                 [0.0045] * 4, (0, 1, 0), pla, 8)
    parts.append(lever)
    parts.append(cyl_obj("leverknob", 0.0085, 0.0085, 0.030, (0.186, 0.03, 0.335), pla, 10, bevel=0.002, seg=1))

    # seat cushion
    cush = box_obj("seat", (0.490, 0.460, 0.074), (0, -0.015, 0.462), fab, bevel=0.020, seg=4, cuts=7, angle=30)

    def seat_fn(p):
        p = round_plan(p, 0.245, 0.23, 4.2)
        w = (p.z + 0.037) / 0.074
        crown = 0.011 * (1 - (p.x / 0.245) ** 2) * (1 - (p.y / 0.23) ** 2) * w
        p.z += max(crown, 0)
        t = smoothstep(-0.12, -0.23, p.y)
        p.z -= 0.026 * t * t * (0.35 + 0.65 * w)
        p.y -= 0.004 * t
        p.z -= 0.006 * smoothstep(0.17, 0.23, abs(p.x)) * w
        return p
    deform(cush, seat_fn)
    parts.append(cush)

    # backrest (cushion + rear shell) tilted back 5.7 degrees
    tilt = math.radians(-5.7)
    centre = Vector((0, 0.235, 0.765))
    back = box_obj("backrest", (0.450, 0.048, 0.335), (0, 0, 0), fab, bevel=0.016, seg=4, cuts=10, angle=30)
    shell = box_obj("backshell", (0.470, 0.020, 0.355), (0, 0.0155, 0), pla, bevel=0.007, seg=3, cuts=5, angle=30)

    def wrap(p, edge=0.030):
        p.y -= edge * (p.x / 0.235) ** 2
        return p

    def back_fn(p):
        p = round_plan(p, 0.225, 0.1675, 3.6, "x", "z")
        p = wrap(p)
        if p.y < 0.004:
            p.y -= 0.012 * (1 - (p.x / 0.225) ** 2) * (1 - (p.z / 0.168) ** 2) * (1 - smoothstep(0.0, -0.025, p.y) * 0.0)
        p.y -= 0.010 * math.exp(-((p.z + 0.04) / 0.07) ** 2) * (1 - (p.x / 0.225) ** 2) * (1 if p.y < 0.004 else 0)  # lumbar
        return p
    deform(back, back_fn)
    deform(shell, lambda p: wrap(round_plan(p, 0.235, 0.1775, 3.6, "x", "z")))
    for o in (back, shell):
        o.location = centre
        o.rotation_euler = (tilt, 0, 0)
        parts.append(o)
    # support arm: gooseneck from under the seat up to the backrest
    path = [(0, 0.080, 0.386), (0, 0.160, 0.384), (0, 0.235, 0.395), (0, 0.272, 0.425), (0, 0.292, 0.48), (0, 0.298, 0.545),
            (0, 0.290, 0.615), (0, 0.268, 0.675), (0, 0.250, 0.710)]
    n = len(path)
    arm = beam("support", [Vector(p) for p in path], [0.052] * n, [0.017, 0.016, 0.015, 0.015, 0.015, 0.015, 0.015, 0.016, 0.016], (1, 0, 0), pla, bevel=0.002, seg=1, ch=0.25)
    parts.append(arm)
    plate = box_obj("backplate", (0.095, 0.006, 0.135), (0, 0, 0), pla, bevel=0.0025, seg=1)
    plate.location = centre + Vector((0, 0.0, 0)) + Matrix.Rotation(tilt, 3, "X") @ Vector((0, 0.0285, -0.075))
    plate.rotation_euler = (tilt, 0, 0)
    parts.append(plate)
    for sx in (-0.03, 0.03):
        b = cyl_obj("bolt", 0.006, 0.006, 0.004, centre + Matrix.Rotation(tilt, 3, "X") @ Vector((sx, 0.0335, -0.045)), ste, 8, rot=(tilt + math.pi / 2, 0, 0))
        parts.append(b)

    ob = join(parts, "prop_office_chair")
    return ob


# ----------------------------------------------------------------------------------------------
# PROP 2: CRT monitor
# ----------------------------------------------------------------------------------------------
def build_crt(seed):
    bei = mat_beige(seed + 1)
    gla = mat_glass(seed + 2)
    pla = mat_plastic_black(seed + 3)
    led = mat_led(seed + 4)
    rub = mat_rubber(seed + 5)
    parts = []
    zc = 0.2125
    # tilt/swivel base
    parts.append(box_obj("foot", (0.30, 0.31, 0.020), (0, -0.04, 0.010), bei, bevel=0.0075, seg=3))
    parts.append(cyl_obj("dish", 0.105, 0.088, 0.024, (0, -0.02, 0.032), bei, 28, bevel=0.004, seg=2))
    # front shell
    shell = box_obj("shell", (0.380, 0.120, 0.335), (0, -0.150, zc), bei, bevel=0.016, seg=4, angle=30)
    # pocket cutter for the recessed screen + chin groove
    sw, sh, sz = 0.300, 0.235, 0.2275
    r0 = [Vector(p) for p in se_ring(0, -0.2205, sz, sw / 2, sh / 2, 5.0, 40)]
    r1 = [Vector((p.x, -0.192, p.z)) for p in r0]
    pocket = loft("pocket", [r0, r1], bei, caps=(True, True))
    groove = box_obj("groove", (0.25, 0.012, 0.0022), (-0.045, -0.2105, 0.0985), pla)
    boolean_diff(shell, [pocket, groove])
    add_bevel(shell, 0.0030, 2, 40)
    parts.append(shell)
    # curved glass (convex, recessed)
    nx, nz = 34, 26
    a, b = sw / 2, sh / 2
    bm = bmesh.new()
    grid = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            u, v = -1 + 2 * i / nx, -1 + 2 * j / nz
            m = max(abs(u), abs(v))
            nn = (abs(u) ** 5 + abs(v) ** 5) ** 0.2
            f = (m / nn) if nn > 1e-6 else 0
            x, z = u * f * a, v * f * b
            nu = (abs(x / a) ** 5 + abs(z / b) ** 5) ** 0.2
            y = -0.1915 - 0.0125 * (1 - min(nu, 1.0) ** 2.2)
            row.append(bm.verts.new((x, y, sz + z)))
        grid.append(row)
    for j in range(nz):
        for i in range(nx):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            if f.normal.y > 0:
                f.normal_flip()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.y > 0:
            f.normal_flip()
    glass = to_obj("glass", bm, gla)
    parts.append(glass)
    # tapered rear housing
    L = 0.275
    ys = [-0.100 + L * (k / 10) for k in range(11)]
    rings = []
    for k, y in enumerate(ys):
        u = k / 10
        hw = 0.172 * (1 - 0.58 * u ** 1.5)
        top = 0.352 - 0.095 * u ** 1.3
        bot = 0.062 + 0.040 * u
        rings.append(se_ring(0, y, (top + bot) / 2, hw, (top - bot) / 2, 4.0, 28))
    rear = loft("rear", rings, bei)
    # vent slots on top + slanted side vents
    cutters = []
    for i in range(-7, 8):
        c = box_obj("slot", (0.0045, 0.075, 0.030), (i * 0.0085, 0.040, 0.318), pla)
        cutters.append(c)
    for sx in (-1, 1):
        for i in range(5):
            c = box_obj("sslot", (0.040, 0.0045, 0.040), (sx * 0.125, 0.0 + i * 0.0085, 0.205), pla)
            cutters.append(c)
    boolean_diff(rear, cutters)
    parts.append(rear)
    # buttons / LED / knobs on the chin
    parts.append(box_obj("power", (0.024, 0.010, 0.012), (0.115, -0.2065, 0.0745), bei, bevel=0.0022, seg=2))
    parts.append(cyl_obj("led", 0.0028, 0.0028, 0.003, (0.088, -0.2105, 0.0745), led, 10, rot=(math.pi / 2, 0, 0)))
    parts.append(cyl_obj("bezel_led", 0.0045, 0.0045, 0.0012, (0.088, -0.2095, 0.0745), pla, 12, rot=(math.pi / 2, 0, 0)))
    for i, x in enumerate((-0.12, -0.093)):
        parts.append(cyl_obj(f"knob{i}", 0.0075, 0.0065, 0.008, (x, -0.2065, 0.0745), bei, 14, rot=(math.pi / 2, 0, 0), bevel=0.0012, seg=1))
    # rear panel + cable stub
    parts.append(box_obj("backpanel", (0.095, 0.008, 0.040), (0.0, 0.1745, 0.135), pla, bevel=0.0018, seg=1))
    cpts = [Vector(p) for p in [(0.03, 0.167, 0.135), (0.03, 0.183, 0.134), (0.03, 0.1955, 0.128), (0.03, 0.2015, 0.112), (0.03, 0.2015, 0.092)]]
    cable = tube("cable", cpts, [0.0085, 0.0070, 0.0062, 0.0062, 0.0062], (1, 0, 0), rub, 8)
    parts.append(cable)
    ob = join(parts, "prop_crt_monitor")
    return ob


# ----------------------------------------------------------------------------------------------
# PROP 3: archive box (body + separate lid)
# ----------------------------------------------------------------------------------------------
def build_box(seed):
    rng = random.Random(seed)
    mo = mat_cardboard_outer(seed + 1)
    mi = mat_cardboard_inner(seed + 2)
    me_ = mat_cardboard_edge(seed + 3)
    mats = [mo, mi, me_]
    W, D, H, T = 0.400, 0.300, 0.280, 0.0040

    def shell_obj(name, w, d, h, zc, cuts, open_top, dfn):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(w, d, h), verts=bm.verts)
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
        bm.faces.ensure_lookup_table()
        kill = [f for f in bm.faces if (f.calc_center_median().z > h / 2 - 1e-6 if open_top else f.calc_center_median().z < -h / 2 + 1e-6) and abs(f.normal.z) > 0.9]
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        ob = to_obj(name, bm, mats)
        ob.location = (0, 0, zc)
        deform(ob, dfn)
        add_bevel(ob, 0.0065, 1, 40)    # softened folded corners
        sol = ob.modifiers.new("solid", "SOLIDIFY")
        sol.thickness = T
        sol.offset = -1.0
        sol.use_rim = True
        sol.material_offset = 1
        sol.material_offset_rim = 2
        apply_mods(ob)
        return ob

    # corner crushed at (+x, -y) top
    cx, cy = W / 2, -D / 2

    def body_fn(p):
        z = p.z + H / 2          # 0..H
        # sag/bulge: walls bow slightly outward at the middle, bottom swollen by water
        if abs(p.x) > W / 2 - 1e-4:
            p.x += math.copysign(0.0035 * math.sin(math.pi * (p.y / D + 0.5)) * (0.4 + 0.6 * math.sin(math.pi * z / H)) + 0.003 * smoothstep(0.1, 0.0, z), p.x)
        if abs(p.y) > D / 2 - 1e-4:
            p.y += math.copysign(0.0030 * math.sin(math.pi * (p.x / W + 0.5)) * (0.4 + 0.6 * math.sin(math.pi * z / H)) + 0.003 * smoothstep(0.1, 0.0, z), p.y)
        # crushed corner: top of the corner collapses inward and down
        dd = math.hypot(p.x - cx, p.y - cy)
        k = smoothstep(0.17, 0.0, dd) * smoothstep(0.08, 0.26, z)
        p.x -= 0.050 * k * (1 if p.x > 0 else 0.0)
        p.y += 0.050 * k * (1 if p.y < 0 else 0.0)
        p.z -= 0.042 * k * smoothstep(0.18, 0.28, z) + 0.010 * k
        # crumple noise
        p.x += 0.0075 * k * math.sin(p.y * 83 + p.z * 41) * math.sin(p.z * 23 + 1.0)
        p.y += 0.0075 * k * math.sin(p.x * 77 + p.z * 53) * math.sin(p.z * 19 + 2.0)
        # general worn waviness of the rim
        if z > 0.26:
            p.z += 0.0022 * math.sin(p.x * 31 + 1.3) * math.cos(p.y * 27)
        return p

    body = shell_obj("prop_cardboard_box", W, D, H, H / 2, 8, True, body_fn)

    LW, LD, LH = W + 0.016, D + 0.016, 0.056

    def lid_fn(p):
        z = p.z + LH / 2
        if p.z > LH / 2 - 1e-4:   # top face dips slightly, sags toward the crushed corner
            dd = math.hypot(p.x - LW / 2, p.y + LD / 2)
            p.z -= 0.0035 * math.sin(math.pi * (p.x / LW + 0.5)) * math.sin(math.pi * (p.y / LD + 0.5)) + 0.004 * smoothstep(0.2, 0.0, dd)
        p.x += 0.0 if abs(p.x) < LW / 2 - 1e-4 else math.copysign(0.0025 * math.sin(math.pi * (p.y / LD + 0.5)), p.x)
        p.z += 0.0015 * math.sin(p.x * 29) * (1 if z < 0.01 else 0)
        return p

    lid = shell_obj("prop_cardboard_box_lid", LW, LD, LH, 0, 5, False, lid_fn)
    # lid rests slightly askew: dropped toward the crushed corner, turned a few degrees
    lid.location = (0.010, 0.013, 0.2345 + LH / 2)
    lid.rotation_euler = (math.radians(1.3), math.radians(3.1), math.radians(-2.6))
    # hand-hole ovals through both short ends: 0.10 wide (y) x 0.028 tall (z)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=20, radius1=1.0, radius2=1.0, depth=1.0)
    bmesh.ops.scale(bm, vec=(0.014, 0.050, 0.60), verts=bm.verts)
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=bm.verts)
    cut = to_obj("hand", bm, me_)
    cut.location = (0, 0, 0.185)
    boolean_diff(body, [cut])
    return [body, lid]


BUILDERS = {"chair": build_chair, "crt": build_crt, "box": build_box}


# ----------------------------------------------------------------------------------------------
# UV + bake + final material + export
# ----------------------------------------------------------------------------------------------
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


def smooth(ob, angle=38):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))


def setup_cycles(sc, samples, use_gpu=True):
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.cycles.device = "CPU"
    if use_gpu:
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
    """Bake btype into img for all material slots (each material gets an active image node)."""
    sc = bpy.context.scene
    for m in mats:
        nt = m.node_tree
        n = nt.nodes.get("BAKE_TARGET")
        if n is None:
            n = nt.nodes.new("ShaderNodeTexImage")
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


def bake_prop(ob, key, res, samples):
    sc = bpy.context.scene
    setup_cycles(sc, samples)
    mats = [s.material for s in ob.material_slots if s.material]
    outdir = BAKED / key
    outdir.mkdir(parents=True, exist_ok=True)
    name = SPEC[key]["name"]
    imgs = {}

    def newimg(tag, nc):
        im = bpy.data.images.new(f"{name}_{tag}", res, res, alpha=False, float_buffer=False)
        im.colorspace_settings.name = "Non-Color" if nc else "sRGB"
        return im

    imgs["base"] = newimg("basecolor", False)
    bake_pass(ob, mats, imgs["base"], "DIFFUSE")
    imgs["rough"] = newimg("rough", True)
    bake_pass(ob, mats, imgs["rough"], "ROUGHNESS")
    imgs["normal"] = newimg("normal", True)
    sc.cycles.samples = 4
    bake_pass(ob, mats, imgs["normal"], "NORMAL")
    imgs["ao"] = newimg("ao", True)
    sc.cycles.samples = max(samples, 32)
    bake_pass(ob, mats, imgs["ao"], "AO")
    # metallic via the emission trick
    imgs["metal"] = newimg("metal", True)
    sc.cycles.samples = 1
    saved = []
    for m in mats:
        nt = m.node_tree
        pb = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        src = out.inputs["Surface"].links[0].from_socket
        em = nt.nodes.new("ShaderNodeEmission")
        if pb.inputs["Metallic"].is_linked:
            nt.links.new(pb.inputs["Metallic"].links[0].from_socket, em.inputs["Color"])
        else:
            v = pb.inputs["Metallic"].default_value
            em.inputs["Color"].default_value = (v, v, v, 1)
        nt.links.new(em.outputs[0], out.inputs["Surface"])
        saved.append((nt, out, src, em))
    bake_pass(ob, mats, imgs["metal"], "EMIT")
    for nt, out, src, em in saved:
        nt.links.new(src, out.inputs["Surface"])
        nt.nodes.remove(em)

    def px(im):
        a = np.empty(res * res * 4, dtype=np.float32)
        im.pixels.foreach_get(a)
        return a.reshape(res, res, 4)

    ao, ro, me = px(imgs["ao"])[..., 0], px(imgs["rough"])[..., 0], px(imgs["metal"])[..., 0]
    orm = np.stack([ao, ro, me, np.ones_like(ao)], axis=-1)
    paths = {}
    orm_img = bpy.data.images.new(f"{name}_orm", res, res, alpha=False)
    orm_img.colorspace_settings.name = "Non-Color"
    orm_img.pixels.foreach_set(orm.reshape(-1))
    for tag, im in (("basecolor", imgs["base"]), ("normal", imgs["normal"]), ("orm", orm_img)):
        p = outdir / f"{name}_{tag}.png"
        im.filepath_raw = str(p)
        im.file_format = "PNG"
        im.save()
        paths[tag] = p
    stats = dict(metal_max=round(float(me.max()), 3), rough_mean=round(float(ro.mean()), 3), ao_mean=round(float(ao.mean()), 3))
    return imgs["base"], imgs["normal"], orm_img, paths, stats


def glTF_output_group():
    ng = bpy.data.node_groups.get("glTF Material Output")
    if ng is None:
        ng = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        ng.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return ng


def final_material(name, base_img, nrm_img, orm_img):
    m = bpy.data.materials.new(name)
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
    g = nt.nodes.new("ShaderNodeGroup")
    g.node_tree = glTF_output_group()
    L.new(sp.outputs["Red"], g.inputs["Occlusion"])
    return m


def led_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    pb = m.node_tree.nodes["Principled BSDF"]
    pb.inputs["Base Color"].default_value = (0.02, 0.10, 0.03, 1)
    pb.inputs["Roughness"].default_value = 0.25
    pb.inputs["Emission Color"].default_value = (0.15, 1.0, 0.25, 1)
    pb.inputs["Emission Strength"].default_value = 2.0
    return m


def export_glb(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
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
    return dict(tris=tris, bounds_min=[round(v, 4) for v in mn], bounds_max=[round(v, 4) for v in mx],
                size_xyz_yup=[round(mx[i] - mn[i], 4) for i in range(3)], images=len(j.get("images", [])),
                materials=[m["name"] for m in j.get("materials", [])], bytes=path.stat().st_size,
                extensions=j.get("extensionsUsed", []), uv_sets=sorted({k for me in j["meshes"] for pr in me["primitives"] for k in pr["attributes"]}))


# ----------------------------------------------------------------------------------------------
# preview render
# ----------------------------------------------------------------------------------------------
def render_preview(objs, out_path, azimuth_deg=-38, elev_deg=20, samples=64, res=1024, dist_mul=1.0):
    sc = bpy.context.scene
    setup_cycles(sc, samples)
    sc.cycles.use_denoising = True
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    mn, mx = world_bounds(objs)
    ctr = (mn + mx) / 2
    R = (mx - mn).length / 2
    fm = bpy.data.materials.new("_pv_floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.30, 0.30, 0.30, 1)
    fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
    fl = bpy.context.active_object
    fl.name = "_pv_floor"
    fl.data.materials.append(fm)
    w = bpy.data.worlds.new("_pv_world")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.30, 0.30, 0.30, 1)
    bg.inputs["Strength"].default_value = 0.12
    sc.world = w

    def area(name, size, energy, loc):
        ld = bpy.data.lights.new(name, "AREA")
        ld.shape = "SQUARE"
        ld.size = size
        ld.energy = energy
        lo = bpy.data.objects.new(name, ld)
        bpy.context.scene.collection.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = (Vector(ctr) - Vector(loc)).normalized().to_track_quat("-Z", "Y").to_euler()
        return lo

    area("_pv_key", 1.6, 85, (ctr.x + 0.25, ctr.y - 0.2, 2.5))
    area("_pv_fill", 2.5, 14, (ctr.x + 1.6, ctr.y - 1.8, 0.9))
    cd = bpy.data.cameras.new("_pv_cam")
    cd.lens = 50
    cam = bpy.data.objects.new("_pv_cam", cd)
    bpy.context.scene.collection.objects.link(cam)
    d = R * 1.22 / math.tan(math.atan(18 / 50)) * dist_mul
    el, az = math.radians(elev_deg), math.radians(azimuth_deg)
    pos = Vector((ctr.x + d * math.cos(el) * math.sin(az), ctr.y - d * math.cos(el) * math.cos(az), ctr.z + d * math.sin(el)))
    cam.location = pos
    cam.rotation_euler = (ctr - pos).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = str(out_path)
    sc.render.image_settings.file_format = "PNG"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    for n in [o for o in bpy.data.objects if o.name.startswith("_pv_")]:
        bpy.data.objects.remove(n)


# ----------------------------------------------------------------------------------------------
def main():
    A = parse_args()
    report = {}
    exported = {}
    for key in A["only"]:
        cfg = SPEC[key]
        res = A["res"] or cfg["tex"]
        reset_scene()
        built = BUILDERS[key](cfg["seed"])
        ob = join(built, "tmp_box") if key == "box" else built
        bpy.context.view_layer.update()
        zmin = min(v.co.z for v in ob.data.vertices)
        for v in ob.data.vertices:
            v.co.z -= zmin           # sit exactly on the floor (y=0 in glTF)
        ob.data.update()
        smooth(ob)
        unwrap(ob)
        mn, mx = world_bounds([ob])
        tris = tri_count(ob)
        print(f"[{key}] tris={tris} bbox min={tuple(round(v, 4) for v in mn)} max={tuple(round(v, 4) for v in mx)}")
        info = dict(tris_blender=tris, bbox_blender_min=[round(v, 4) for v in mn], bbox_blender_max=[round(v, 4) for v in mx])
        if not A["bake"]:
            ob.name = cfg["name"]
            if A["preview"]:
                render_preview([ob], PREV / f"{cfg['name']}_nobake.png", samples=A["samples"])
                render_preview([ob], PREV / f"{cfg['name']}_nobake_back.png", azimuth_deg=150, samples=A["samples"])
            report[key] = info
            continue
        base_img, nrm_img, orm_img, paths, bstats = bake_prop(ob, key, res, A["bake_samples"])
        info["bake"] = bstats
        fm = final_material(f"mat_{cfg['name']}", base_img, nrm_img, orm_img)
        led_idx = None
        if key == "crt":
            led_idx = next(i for i, s in enumerate(ob.material_slots) if s.material and s.material.name.startswith("led_green"))
        lm = led_material("mat_crt_led") if key == "crt" else None
        led_faces = [p.index for p in ob.data.polygons if led_idx is not None and p.material_index == led_idx]
        ob.data.materials.clear()
        ob.data.materials.append(fm)
        if lm:
            ob.data.materials.append(lm)
        for i in led_faces:
            ob.data.polygons[i].material_index = 1
        print("[%s] led faces: %d of %d" % (key, len(led_faces), len(ob.data.polygons)))
        ob.name = cfg["name"]
        ob.data.name = cfg["name"]
        objs = [ob]
        if key == "box":
            bpy.ops.object.select_all(action="DESELECT")
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.mesh.separate(type="LOOSE")
            bpy.ops.object.mode_set(mode="OBJECT")
            parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
            lid = max(parts, key=lambda o: sum(v.co.z for v in o.data.vertices) / len(o.data.vertices))
            body = next(o for o in parts if o is not lid)
            body.name = cfg["name"]; body.data.name = cfg["name"]
            lid.name = cfg["name"] + "_lid"; lid.data.name = cfg["name"] + "_lid"
            lid.parent = body
            objs = [body, lid]
            info["parts"] = {o.name: tri_count(o) for o in objs}
        out = OUT / f"{cfg['name']}.glb"
        export_glb(objs, out)
        gi = glb_info(out)
        info["glb"] = gi
        info["textures"] = {k: str(v.relative_to(ROOT)).replace("\\", "/") for k, v in paths.items()}
        info["tex_res"] = res
        print(f"[{key}] exported {out} {gi}")
        exported[key] = out
        report[key] = info
    if A["bake"] and A["preview"]:
        for key, path in exported.items():
            reset_scene()
            bpy.ops.import_scene.gltf(filepath=str(path))
            objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
            nm = SPEC[key]["name"]
            render_preview(objs, PREV / f"{nm}.png", azimuth_deg=-38, elev_deg=20, samples=A["samples"])
            render_preview(objs, PREV / f"{nm}_back.png", azimuth_deg=140, elev_deg=25, samples=A["samples"])
    rp = ROOT / "pipeline/meshes/props_procedural_report.json"
    existing = json.loads(rp.read_text()) if rp.exists() else {}
    existing.update(report)
    rp.write_text(json.dumps(existing, indent=2))


main()
