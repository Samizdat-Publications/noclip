"""Bake a worn 1990s ABS-plastic PBR texture set onto the camcorder_v2 mesh and export camcorder_v3.glb.
  "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b -P pipeline/blender/texture_camcorder_v3.py -- [--res 2048] [--samples 48]
Geometry, pivot, axes, scale: untouched (only a new non-overlapping UV layer is added, the old UVs are dropped).
Passes (Cycles, CPU only, so it never fights a GPU render queue):
  pre-pass  edge (bevel), narrow AO, wide AO, pointiness  -> float images
  shading   base color, roughness, metallic, occlusion    -> EMIT bakes of one procedural shader graph
  normal    tangent-space, OpenGL (+Y), from the shader bump (molded grain, scratches)
Outputs: pipeline/textures/camcorder_v3/*.png, game/assets/props/player/camcorder_v3.glb (materials camcorder_body, camcorder_glass).
Source of the mesh: Sketchfab CC-BY "Panasonic NV-G120 VHS-C CAMERA" by PetyaPetr (see manifests/camcorder_v2.json).
"""
import bpy, sys, json, math, time
import numpy as np
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "game/assets/props/player/camcorder_v2.glb"
DST = ROOT / "game/assets/props/player/camcorder_v3.glb"
TEX = ROOT / "pipeline/textures/camcorder_v3"
STATS = ROOT / "pipeline/blender/previews/camcorder_v3_stats.json"
SEED = 3

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RES = int(args[args.index("--res") + 1]) if "--res" in args else 2048
SAMPLES = int(args[args.index("--samples") + 1]) if "--samples" in args else 48

# v2 material index -> role
#  0 body plastic  1 red (REC lamp)  2 rubber (grip/eyecup)  3 silver button  4 glass  5 light grey bits
#  6 lens barrel   7 focus ring      8 small rubber
GLASS_IDX = 4
CLASS_PARAMS = {
    #       base linear color            rough  metal wear  scr   grainAmp worn_col            worn_r
    0: dict(col=(0.0215, 0.0220, 0.0235), r=0.56, m=0.0, wear=1.0, scr=1.0, ga=0.55, wc=(0.090, 0.092, 0.095), wr=0.30),
    1: dict(col=(0.42, 0.018, 0.012), r=0.28, m=0.0, wear=0.3, scr=0.3, ga=0.08, wc=(0.30, 0.06, 0.05), wr=0.25),
    2: dict(col=(0.0120, 0.0122, 0.0128), r=0.84, m=0.0, wear=0.25, scr=0.2, ga=1.0, wc=(0.040, 0.040, 0.042), wr=0.62),
    3: dict(col=(0.50, 0.51, 0.53), r=0.34, m=0.80, wear=0.5, scr=0.7, ga=0.10, wc=(0.72, 0.72, 0.74), wr=0.22),
    4: dict(col=(0.0215, 0.0220, 0.0235), r=0.56, m=0.0, wear=1.0, scr=1.0, ga=0.55, wc=(0.090, 0.092, 0.095), wr=0.30),
    5: dict(col=(0.115, 0.118, 0.122), r=0.52, m=0.0, wear=0.9, scr=0.9, ga=0.45, wc=(0.20, 0.20, 0.21), wr=0.34),
    6: dict(col=(0.0165, 0.0170, 0.0185), r=0.46, m=0.0, wear=1.1, scr=1.1, ga=0.40, wc=(0.095, 0.097, 0.100), wr=0.26),
    7: dict(col=(0.034, 0.035, 0.038), r=0.44, m=0.0, wear=1.3, scr=1.2, ga=0.30, wc=(0.12, 0.12, 0.125), wr=0.26),
    8: dict(col=(0.0120, 0.0122, 0.0128), r=0.88, m=0.0, wear=0.4, scr=0.2, ga=1.0, wc=(0.040, 0.040, 0.042), wr=0.62),
}


# ---------------------------------------------------------------- node helpers
class G:
    def __init__(s, nt):
        s.nt = nt

    def node(s, t, **kw):
        n = s.nt.nodes.new(t)
        for k, v in kw.items():
            setattr(n, k, v)
        return n

    def put(s, sock, v):
        if isinstance(v, bpy.types.NodeSocket):
            s.nt.links.new(v, sock)
        elif v is not None:
            sock.default_value = v

    def math(s, op, a, b=None, c=None, clamp=False):
        n = s.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        s.put(n.inputs[0], a)
        if b is not None: s.put(n.inputs[1], b)
        if c is not None: s.put(n.inputs[2], c)
        return n.outputs[0]

    def mixf(s, fac, a, b):
        n = s.node("ShaderNodeMix", data_type="FLOAT")
        s.put(n.inputs[0], fac); s.put(n.inputs[2], a); s.put(n.inputs[3], b)
        return n.outputs[0]

    def mixc(s, fac, a, b):
        n = s.node("ShaderNodeMix", data_type="RGBA")
        s.put(n.inputs[0], fac)
        s.put(n.inputs[6], a if isinstance(a, bpy.types.NodeSocket) else (*a, 1))
        s.put(n.inputs[7], b if isinstance(b, bpy.types.NodeSocket) else (*b, 1))
        return n.outputs[2]

    def mulc(s, a, f):  # color * float/socket
        n = s.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
        s.put(n.inputs[0], 1.0)
        s.put(n.inputs[6], a if isinstance(a, bpy.types.NodeSocket) else (*a, 1))
        if isinstance(f, bpy.types.NodeSocket):
            c = s.node("ShaderNodeCombineColor"); [s.nt.links.new(f, c.inputs[i]) for i in range(3)]
            s.put(n.inputs[7], c.outputs[0])
        else:
            s.put(n.inputs[7], (f, f, f, 1))
        return n.outputs[2]

    def mr(s, v, a, b, ta=0.0, tb=1.0, smooth=False, clamp=True):
        n = s.node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP" if smooth else "LINEAR", clamp=clamp)
        s.put(n.inputs[0], v); s.put(n.inputs[1], a); s.put(n.inputs[2], b); s.put(n.inputs[3], ta); s.put(n.inputs[4], tb)
        return n.outputs[0]

    def noise(s, vec, scale, detail=3.0, rough=0.5, distort=0.0):
        n = s.node("ShaderNodeTexNoise", noise_dimensions="3D")
        s.put(n.inputs["Vector"], vec); n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail; n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = distort
        return n.outputs["Fac"]

    def mapping(s, vec, scale=(1, 1, 1), rot=(0, 0, 0), loc=(0, 0, 0)):
        n = s.node("ShaderNodeMapping", vector_type="POINT")
        s.put(n.inputs["Vector"], vec)
        n.inputs["Location"].default_value = loc; n.inputs["Rotation"].default_value = rot; n.inputs["Scale"].default_value = scale
        return n.outputs[0]

    def voro_edge(s, vec, scale):
        n = s.node("ShaderNodeTexVoronoi", feature="DISTANCE_TO_EDGE", voronoi_dimensions="3D")
        s.put(n.inputs["Vector"], vec); n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = 1.0
        return n.outputs["Distance"]

    def class_mix(s, masks, per_class, default, color=False):
        """chain: start from default, override with each class value where its mask is 1"""
        cur = default
        for k, m in masks.items():
            v = per_class[k]
            cur = s.mixc(m, cur, v) if color else s.mixf(m, cur, v)
        return cur


def look_target(nt, img_node_name, image):
    n = nt.nodes.new("ShaderNodeTexImage")
    n.name = img_node_name; n.image = image
    nt.nodes.active = n
    n.select = True
    return n


def new_image(name, res, colorspace, float_buf=False, fill=(0, 0, 0, 1)):
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    im = bpy.data.images.new(name, res, res, alpha=False, float_buffer=float_buf)
    im.colorspace_settings.name = colorspace
    im.generated_color = fill
    return im


def save_png(im, path, depth=8):
    path.parent.mkdir(parents=True, exist_ok=True)
    sc = bpy.context.scene
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.image_settings.color_depth = str(depth)
    sc.render.image_settings.compression = 15
    im.save_render(str(path), scene=sc)


# ---------------------------------------------------------------- main
t0 = time.time()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SRC))
sc = bpy.context.scene
ob = [o for o in sc.objects if o.type == "MESH"][0]
me = ob.data
orig_mat_idx = np.array([p.material_index for p in me.polygons], dtype=np.int32)
co0 = np.array([v.co[:] for v in me.vertices], dtype=np.float64)
bmin0, bmax0 = co0.min(axis=0), co0.max(axis=0)
tris = sum(len(p.vertices) - 2 for p in me.polygons)
print("v2 bounds (blender Z-up)", bmin0, bmax0, "tris", tris)
ob.name = "camcorder_v3"; me.name = "camcorder_v3"

# per-corner class code
attr = me.color_attributes.new("mclass", "FLOAT_COLOR", "CORNER")
data = np.zeros((len(me.loops), 4), dtype=np.float32)
for p in me.polygons:
    for li in p.loop_indices:
        data[li] = (orig_mat_idx[p.index] * 0.1, 0, 0, 1)
attr.data.foreach_set("color", data.ravel())

# fresh non-overlapping UVs
for u in list(me.uv_layers):
    pass
uv = me.uv_layers.new(name="BakeUV")
me.uv_layers.active = uv
for l in me.uv_layers:
    l.active_render = (l.name == "BakeUV")
bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
bpy.context.view_layer.objects.active = ob
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(80), island_margin=0.002, area_weight=0.5, correct_aspect=True, scale_to_bounds=False)
bpy.ops.uv.select_all(action="SELECT")
bpy.ops.uv.pack_islands(rotate=True, margin=0.002)
bpy.ops.object.mode_set(mode="OBJECT")
for l in list(me.uv_layers):
    if l.name != "BakeUV":
        me.uv_layers.remove(l)
uvs = np.zeros((len(me.loops), 2), dtype=np.float32)
me.uv_layers["BakeUV"].data.foreach_get("uv", uvs.ravel())
# coverage of the unit square (rasterised polygons are not needed; area sum vs 1 gives texel use)
area = 0.0
for p in me.polygons:
    pts = [uvs[li] for li in p.loop_indices]
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]; x1, y1 = pts[(i + 1) % len(pts)]
        a += x0 * y1 - x1 * y0
    area += abs(a) / 2
print("UV area coverage %.3f  uv range %s %s" % (area, uvs.min(axis=0), uvs.max(axis=0)))

# ---- cycles setup (CPU)
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.use_denoising = False
sc.cycles.samples = SAMPLES
sc.cycles.seed = SEED
sc.render.bake.margin = 10
sc.render.bake.margin_type = "EXTEND"
sc.render.bake.use_clear = True
sc.render.bake.normal_space = "TANGENT"
sc.render.bake.normal_r, sc.render.bake.normal_g, sc.render.bake.normal_b = "POS_X", "POS_Y", "POS_Z"
sc.render.bake.target = "IMAGE_TEXTURES"
sc.render.bake.use_selected_to_active = False
sc.view_settings.view_transform = "Standard"

# single bake slot
me.materials.clear()
bm = bpy.data.materials.new("bake_mat"); bm.use_nodes = True
me.materials.append(bm)
for p in me.polygons:
    p.material_index = 0
me.update()


def reset_tree(mat):
    nt = mat.node_tree
    nt.nodes.clear()
    return nt


def bake(mat, target_img, btype="EMIT", samples=None):
    nt = mat.node_tree
    for n in nt.nodes:
        n.select = False
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = target_img
    nt.nodes.active = tn
    tn.select = True
    if samples: sc.cycles.samples = samples
    t = time.time()
    bpy.ops.object.bake(type=btype)
    print("  baked %s in %.1fs" % (target_img.name, time.time() - t))
    nt.nodes.remove(tn)
    sc.cycles.samples = SAMPLES


# ---- pre-pass: edge / ao / pointiness
pre_a = new_image("cc3_pre_a", RES, "Non-Color", True)
pre_b = new_image("cc3_pre_b", RES, "Non-Color", True)
nt = reset_tree(bm); g = G(nt)
geo = g.node("ShaderNodeNewGeometry")
bev = g.node("ShaderNodeBevel", samples=12)
bev.inputs["Radius"].default_value = 0.0009
vd = g.node("ShaderNodeVectorMath", operation="DOT_PRODUCT")
nt.links.new(bev.outputs["Normal"], vd.inputs[0]); nt.links.new(geo.outputs["Normal"], vd.inputs[1])
edge_b = g.mr(g.math("SUBTRACT", 1.0, vd.outputs["Value"]), 0.0, 0.35)
ao_n = g.node("ShaderNodeAmbientOcclusion", samples=16); ao_n.inputs["Distance"].default_value = 0.005
ao_w = g.node("ShaderNodeAmbientOcclusion", samples=16); ao_w.inputs["Distance"].default_value = 0.03
comb = g.node("ShaderNodeCombineColor")
nt.links.new(edge_b, comb.inputs[0]); nt.links.new(ao_n.outputs["AO"], comb.inputs[1]); nt.links.new(ao_w.outputs["AO"], comb.inputs[2])
em = g.node("ShaderNodeEmission"); out = g.node("ShaderNodeOutputMaterial")
nt.links.new(comb.outputs[0], em.inputs["Color"]); nt.links.new(em.outputs[0], out.inputs["Surface"])
print("pre-pass A")
bake(bm, pre_a, samples=96)
nt = reset_tree(bm); g = G(nt)
geo = g.node("ShaderNodeNewGeometry")
em = g.node("ShaderNodeEmission"); out = g.node("ShaderNodeOutputMaterial")
nt.links.new(geo.outputs["Pointiness"], em.inputs["Color"]); nt.links.new(em.outputs[0], out.inputs["Surface"])
print("pre-pass B")
bake(bm, pre_b, samples=8)

# ---- main procedural shader
nt = reset_tree(bm); g = G(nt)
tc = g.node("ShaderNodeTexCoord")
obj = tc.outputs["Object"]
uvn = g.node("ShaderNodeUVMap", uv_map="BakeUV")
ta = g.node("ShaderNodeTexImage", image=pre_a, interpolation="Linear", extension="EXTEND")
tb = g.node("ShaderNodeTexImage", image=pre_b, interpolation="Linear", extension="EXTEND")
nt.links.new(uvn.outputs[0], ta.inputs["Vector"]); nt.links.new(uvn.outputs[0], tb.inputs["Vector"])
sa = g.node("ShaderNodeSeparateColor"); nt.links.new(ta.outputs["Color"], sa.inputs[0])
sb = g.node("ShaderNodeSeparateColor"); nt.links.new(tb.outputs["Color"], sb.inputs[0])
edge_b, ao_n, ao_w = sa.outputs[0], sa.outputs[1], sa.outputs[2]
point = sb.outputs[0]

# class masks
at = g.node("ShaderNodeAttribute", attribute_type="GEOMETRY", attribute_name="mclass")
sc_ = g.node("ShaderNodeSeparateColor"); nt.links.new(at.outputs["Color"], sc_.inputs[0])
idx = g.math("MULTIPLY", sc_.outputs[0], 10.0)
masks = {}
for k in CLASS_PARAMS:
    if k == GLASS_IDX: continue
    masks[k] = g.math("LESS_THAN", g.math("ABSOLUTE", g.math("SUBTRACT", idx, float(k))), 0.5)

P = lambda key: {k: v[key] for k, v in CLASS_PARAMS.items()}

# noises (object space, metres)
n_grain_a = g.noise(g.mapping(obj, scale=(1, 1, 1)), 1300.0, 3.0, 0.55)
n_grain_b = g.noise(g.mapping(obj, loc=(3.1, 1.7, 9.2)), 520.0, 2.0, 0.5)
grain = g.mr(g.mixf(0.35, n_grain_a, n_grain_b), 0.3, 0.7)
mott = g.noise(obj, 38.0, 4.0, 0.55)
mott_f = g.mr(mott, 0.3, 0.7)
big = g.noise(g.mapping(obj, loc=(5.0, 2.0, 7.0)), 9.0, 2.0, 0.5)
fine_var = g.noise(g.mapping(obj, loc=(8.0, 3.0, 1.0)), 260.0, 4.0, 0.6)

# wear from edge masks
edge_p = g.mr(point, 0.53, 0.66)
is_rub = g.math("MAXIMUM", masks[2], masks[8])
edge = g.math("MAXIMUM", edge_b, g.math("MULTIPLY", edge_p, g.math("SUBTRACT", 1.0, is_rub)))
wn = g.noise(g.mapping(obj, loc=(1.0, 6.0, 3.0)), 150.0, 6.0, 0.62)
w0 = g.math("MULTIPLY", edge, g.math("ADD", 0.30, g.math("MULTIPLY", wn, 1.5)))
wear_raw = g.mr(w0, 0.30, 0.62, smooth=True)
wear_k = g.class_mix(masks, P("wear"), 0.0)
wear = g.math("MULTIPLY", wear_raw, wear_k, clamp=True)

# scratches: sparse thin lines, two orientations/scales
v1 = g.mapping(obj, scale=(70, 70, 420), rot=(0.55, 1.05, 0.35))
v2 = g.mapping(obj, scale=(190, 600, 190), rot=(1.2, 0.3, 0.9), loc=(2, 4, 1))
line1 = g.math("SUBTRACT", 1.0, g.mr(g.voro_edge(v1, 1.0), 0.010, 0.040, smooth=True))
line2 = g.math("SUBTRACT", 1.0, g.mr(g.voro_edge(v2, 1.0), 0.012, 0.050, smooth=True))
gate1 = g.mr(g.noise(g.mapping(obj, loc=(4, 1, 2)), 22.0, 2.0, 0.5), 0.58, 0.70)
gate2 = g.mr(g.noise(g.mapping(obj, loc=(7, 5, 3)), 30.0, 2.0, 0.5), 0.60, 0.72)
scr_raw = g.math("MAXIMUM", g.math("MULTIPLY", line1, gate1), g.math("MULTIPLY", line2, g.math("MULTIPLY", gate2, 0.8)))
scr_k = g.class_mix(masks, P("scr"), 0.0)
scratch = g.math("MULTIPLY", scr_raw, scr_k, clamp=True)

# scuffs: soft matte lighter patches
scuff_raw = g.math("MULTIPLY", g.mr(g.noise(g.mapping(obj, loc=(9, 9, 1)), 60.0, 4.0, 0.6), 0.56, 0.72),
                   g.mr(g.noise(g.mapping(obj, loc=(2, 8, 4)), 450.0, 2.0, 0.5), 0.35, 0.65))
scuff = g.math("MULTIPLY", scuff_raw, g.mr(big, 0.35, 0.6), clamp=True)

# grime from cavity AO
cav = g.mr(g.math("SUBTRACT", 1.0, ao_n), 0.05, 0.55, smooth=True)
broad = g.math("ADD", 0.50, g.math("MULTIPLY", ao_w, 0.50))

# base colour
base = g.class_mix(masks, {k: v["col"] for k, v in CLASS_PARAMS.items()}, (0.02, 0.02, 0.02), color=True)
base = g.mulc(base, g.mr(mott, 0.25, 0.75, 0.8, 1.35))
base = g.mulc(base, broad)
grime_col = g.mulc(base, 0.42)
col = g.mixc(g.math("MULTIPLY", cav, 0.85), base, grime_col)
worn_col = g.class_mix(masks, {k: v["wc"] for k, v in CLASS_PARAMS.items()}, (0.09, 0.09, 0.09), color=True)
col = g.mixc(g.mr(wear, 0.0, 1.0, 0.0, 0.92), col, worn_col)
col = g.mixc(g.math("MULTIPLY", scuff, 0.55), col, g.mulc(worn_col, 0.55))
col = g.mixc(g.math("MULTIPLY", scratch, 0.85), col, g.mulc(worn_col, 1.25))

# roughness
rough = g.class_mix(masks, P("r"), 0.55)
rough = g.math("ADD", rough, g.math("MULTIPLY", g.math("SUBTRACT", fine_var, 0.5), 0.35))
rough = g.math("ADD", rough, g.math("MULTIPLY", g.math("SUBTRACT", mott, 0.5), 0.25))
rough = g.math("ADD", rough, g.math("MULTIPLY", cav, 0.22))
worn_r = g.class_mix(masks, P("wr"), 0.3)
rough = g.mixf(wear, rough, worn_r)
rough = g.mixf(g.math("MULTIPLY", scuff, 0.6), rough, 0.78)
rough = g.mixf(g.math("MULTIPLY", scratch, 0.8), rough, 0.30)
rough = g.math("MINIMUM", g.math("MAXIMUM", rough, 0.08), 0.98)

# metallic
metal = g.class_mix(masks, P("m"), 0.0)
metal = g.math("MULTIPLY", metal, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", cav, 0.3)))

# occlusion (broad AO, a bit of cavity)
occ = g.math("MULTIPLY", ao_w, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", cav, 0.35)), clamp=True)

# height for bump
ga = g.class_mix(masks, P("ga"), 0.4)
h = g.math("MULTIPLY", g.math("SUBTRACT", grain, 0.5), g.math("MULTIPLY", ga, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", wear, 0.85))))
h = g.math("SUBTRACT", h, g.math("MULTIPLY", scratch, 0.45))
h = g.math("SUBTRACT", h, g.math("MULTIPLY", scuff, 0.06))
h = g.math("ADD", h, g.math("MULTIPLY", g.math("SUBTRACT", fine_var, 0.5), 0.10))
h = g.math("ADD", h, 0.5)
bump = g.node("ShaderNodeBump", invert=False)
bump.inputs["Strength"].default_value = 1.0
bump.inputs["Distance"].default_value = 0.0007
nt.links.new(h, bump.inputs["Height"])
bsdf = g.node("ShaderNodeBsdfPrincipled")
nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
nt.links.new(col, bsdf.inputs["Base Color"])
emi = g.node("ShaderNodeEmission")
outn = g.node("ShaderNodeOutputMaterial")


def route(sock):
    for l in list(outn.inputs["Surface"].links): nt.links.remove(l)
    for l in list(emi.inputs["Color"].links): nt.links.remove(l)
    nt.links.new(sock, emi.inputs["Color"])
    nt.links.new(emi.outputs[0], outn.inputs["Surface"])


bc = new_image("camcorder_v3_basecolor", RES, "sRGB")
rg = new_image("cc3_rough", RES, "Non-Color")
mt = new_image("cc3_metal", RES, "Non-Color")
ao = new_image("cc3_occ", RES, "Non-Color")
nm = new_image("camcorder_v3_normal", RES, "Non-Color", fill=(0.5, 0.5, 1.0, 1))
print("shading bakes")
for im, sock in ((bc, col), (rg, rough), (mt, metal), (ao, occ)):
    route(sock)
    bake(bm, im, samples=6)
for l in list(outn.inputs["Surface"].links): nt.links.remove(l)
nt.links.new(bsdf.outputs[0], outn.inputs["Surface"])
bake(bm, nm, btype="NORMAL", samples=6)

# ---- pack ORM
def px(im):
    a = np.empty(RES * RES * 4, dtype=np.float32); im.pixels.foreach_get(a); return a.reshape(RES, RES, 4)
orm_a = np.ones((RES, RES, 4), dtype=np.float32)
orm_a[..., 0] = px(ao)[..., 0]; orm_a[..., 1] = px(rg)[..., 0]; orm_a[..., 2] = px(mt)[..., 0]
orm = new_image("camcorder_v3_orm", RES, "Non-Color")
orm.pixels.foreach_set(orm_a.ravel()); orm.update()
for im, nme in ((bc, "camcorder_v3_basecolor"), (nm, "camcorder_v3_normal"), (orm, "camcorder_v3_orm")):
    save_png(im, TEX / (nme + ".png"))
    im.filepath_raw = str(TEX / (nme + ".png")); im.source = "FILE"; im.reload() if False else None
    im.pack()
# debug helper images (not exported)
save_png(ao, TEX / "_debug_occlusion.png"); save_png(rg, TEX / "_debug_roughness.png"); save_png(mt, TEX / "_debug_metallic.png")
pa = px(pre_a); print("pre-pass A mean", pa[..., :3].mean(axis=(0, 1)), "edge>0.2 frac", (pa[..., 0] > 0.2).mean())
bc_a = px(bc)
print("basecolor mean (srgb-ish stored)", bc_a[..., :3].mean(axis=(0, 1)))

# ---- final materials
body = bpy.data.materials.new("camcorder_body"); body.use_nodes = True
nt = body.node_tree; nt.nodes.clear(); g = G(nt)
pb = g.node("ShaderNodeBsdfPrincipled"); o2 = g.node("ShaderNodeOutputMaterial")
nt.links.new(pb.outputs[0], o2.inputs["Surface"])
t_bc = g.node("ShaderNodeTexImage", image=bc); nt.links.new(t_bc.outputs["Color"], pb.inputs["Base Color"])
t_orm = g.node("ShaderNodeTexImage", image=orm)
sp = g.node("ShaderNodeSeparateColor"); nt.links.new(t_orm.outputs["Color"], sp.inputs[0])
nt.links.new(sp.outputs[1], pb.inputs["Roughness"]); nt.links.new(sp.outputs[2], pb.inputs["Metallic"])
t_n = g.node("ShaderNodeTexImage", image=nm)
nmn = g.node("ShaderNodeNormalMap"); nmn.uv_map = "BakeUV"
nt.links.new(t_n.outputs["Color"], nmn.inputs["Color"]); nt.links.new(nmn.outputs[0], pb.inputs["Normal"])
grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
grp.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
gn = nt.nodes.new("ShaderNodeGroup"); gn.node_tree = grp
nt.links.new(sp.outputs[0], gn.inputs["Occlusion"])

glass = bpy.data.materials.new("camcorder_glass"); glass.use_nodes = True
gb = glass.node_tree.nodes["Principled BSDF"]
gb.inputs["Base Color"].default_value = (0.020, 0.008, 0.032, 1)   # deep purple coating tint
gb.inputs["Metallic"].default_value = 0.35
gb.inputs["Roughness"].default_value = 0.045
gb.inputs["Coat Weight"].default_value = 0.8
gb.inputs["Coat Roughness"].default_value = 0.02

me.materials.clear()
me.materials.append(body); me.materials.append(glass)
for p in me.polygons:
    p.material_index = 1 if orig_mat_idx[p.index] == GLASS_IDX else 0
me.color_attributes.remove(me.color_attributes["mclass"])
me.update()

# bounds check on the mesh we export
co1 = np.array([v.co[:] for v in me.vertices], dtype=np.float64)
assert np.abs(co1 - co0).max() == 0.0, "vertex positions changed"
bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True); bpy.context.view_layer.objects.active = ob
DST.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(DST), export_format="GLB", export_yup=True, export_apply=False, use_selection=True,
                          export_image_format="AUTO", export_materials="EXPORT")
print("exported", DST, "%.1fs total" % (time.time() - t0))
STATS.parent.mkdir(parents=True, exist_ok=True)
STATS.write_text(json.dumps(dict(res=RES, samples=SAMPLES, tris=tris, uv_area_coverage=round(float(area), 3),
                                 v2_bounds_blender=[bmin0.tolist(), bmax0.tolist()], seconds=round(time.time() - t0, 1)), indent=1))
