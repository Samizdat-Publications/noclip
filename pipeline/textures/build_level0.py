"""Regenerate the whole Level 0 PBR texture set (deterministic, fixed seeds, no network, $0).

    python pipeline/textures/build_level0.py

Outputs: game/assets/textures/level0/*.png, pipeline/textures/previews/*.png,
         pipeline/manifests/textures_level0.json
Normal maps: OpenGL convention (green = +Y up, Godot). Albedo/emission sRGB; rough/AO/height linear grey.
"""
import os, sys, json, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, cv2
from PIL import Image
import mat_carpet_wall as cw
import mat_ceiling_etc as ce
import mat_decals as dc
from tex_common import OUT, PREV, ROOT
from previews import load, tile3, seam, over, tiled_to

SEEDS = dict(carpet=1001, wallpaper=2002, ceiling=3003, troffer=4004, baseboard=5005,
             waterdamage=6001, grime_low=6002, wetpatch=6003, ceiling_stain=6004, mold=6005)

t0 = time.time()
results = {
    "carpet": cw.build_carpet(SEEDS["carpet"]),
    "wallpaper": cw.build_wallpaper(SEEDS["wallpaper"]),
    "ceiling_tile": ce.build_ceiling(SEEDS["ceiling"]),
    "troffer_lens": ce.build_troffer(SEEDS["troffer"]),
    "baseboard": ce.build_baseboard(SEEDS["baseboard"]),
    "decal_wall_waterdamage": dc.build_waterdamage(SEEDS["waterdamage"]),
    "decal_wall_grime_low": dc.build_grime_low(SEEDS["grime_low"]),
    "decal_floor_wetpatch": dc.build_wetpatch(SEEDS["wetpatch"]),
    "decal_ceiling_stain": dc.build_ceiling_stain(SEEDS["ceiling_stain"]),
    "decal_mold": dc.build_mold(SEEDS["mold"]),
}

# ---- seam metric: wrap-around step vs typical neighbouring-pixel step (ratio ~1 = invisible seam)
def seam_ratio(name, axes=(0, 1)):
    a = load(name).astype(float)
    out = {}
    for ax in axes:
        wrap = np.abs(np.take(a, 0, ax) - np.take(a, -1, ax)).mean()
        mid = np.abs(np.take(a, a.shape[ax] // 2, ax) - np.take(a, a.shape[ax] // 2 + 1, ax)).mean()
        out["rows" if ax == 0 else "cols"] = round(float(wrap / max(mid, 1e-6)), 2)
    return out

seams = {}
for n in ["carpet_albedo", "carpet_normal", "carpet_roughness", "carpet_ao", "carpet_height",
          "wallpaper_albedo", "wallpaper_normal", "wallpaper_roughness", "wallpaper_ao"]:
    seams[n] = seam_ratio(n)
for n in ["baseboard_albedo", "baseboard_normal", "baseboard_roughness"]:
    seams[n] = seam_ratio(n, axes=(1,))

# ---- previews
for n in ["carpet_albedo", "carpet_normal", "wallpaper_albedo", "wallpaper_normal",
          "ceiling_tile_albedo", "ceiling_tile_normal", "ceiling_tile_stained_albedo",
          "troffer_lens_albedo", "troffer_lens_normal", "troffer_lens_emission",
          "carpet_roughness", "wallpaper_roughness"]:
    tile3(n)
    seam(n)
# baseboard tiled horizontally 4x, albedo + normal stacked
for n in ["baseboard_albedo", "baseboard_normal"]:
    im = load(n)
    Image.fromarray(np.tile(im, (1, 3, 1))).save(os.path.join(PREV, n + "_3x1.png"))

def comp(name, base, out):
    d = load(name)
    b = base.copy()
    over(b, d, 0, 0)
    Image.fromarray(b).save(os.path.join(PREV, out))
    return b

# decals composited over their matching base texture, one sheet
wall = tiled_to("wallpaper_albedo", 1024, 2048, 0.30)
wd = comp("decal_wall_waterdamage.png", wall, "comp_decal_wall_waterdamage.png")
gr = comp("decal_wall_grime_low.png", tiled_to("wallpaper_albedo", 2048, 512, 0.45), "comp_decal_wall_grime_low.png")
bb = np.zeros((512 + 96, 2048, 3), np.uint8)
bb[:512] = gr
bb[512:] = cv2.resize(np.tile(load("baseboard_albedo")[..., :3], (1, 2, 1)), (2048, 96), interpolation=cv2.INTER_AREA)
wet = comp("decal_floor_wetpatch.png", tiled_to("carpet_albedo", 1024, 1024, 0.5), "comp_decal_floor_wetpatch.png")
mold = comp("decal_mold.png", tiled_to("wallpaper_albedo", 1024, 1024, 0.45), "comp_decal_mold.png")
ct = cv2.resize(np.tile(load("ceiling_tile_albedo")[..., :3], (2, 2, 1)), (1024, 1024), interpolation=cv2.INTER_AREA)
cs = comp("decal_ceiling_stain.png", ct, "comp_decal_ceiling_stain.png")
row = np.concatenate([cv2.resize(x, (640, 640), interpolation=cv2.INTER_AREA) for x in (wet, mold, cs)], 1)
Image.fromarray(row).save(os.path.join(PREV, "comp_decals_floor_mold_ceiling.png"))
Image.fromarray(cv2.resize(bb, (1536, 456), interpolation=cv2.INTER_AREA)).save(os.path.join(PREV, "comp_decal_wall_grime_low_with_baseboard.png"))
Image.fromarray(cv2.resize(wd, (512, 1024), interpolation=cv2.INTER_AREA)).save(os.path.join(PREV, "comp_decal_wall_waterdamage_small.png"))

# ---- manifest
files = sorted(f for f in os.listdir(OUT) if f.endswith(".png"))
info = {f: dict(size=list(Image.open(os.path.join(OUT, f)).size), mode=Image.open(os.path.join(OUT, f)).mode) for f in files}
manifest = {
    "asset": "textures_level0",
    "generated_by": "pipeline/textures/build_level0.py (modules: tex_common, mat_carpet_wall, mat_ceiling_etc, mat_decals, previews)",
    "run_command": "python pipeline/textures/build_level0.py",
    "method": "Fully procedural (numpy/scipy/OpenCV). Every noise field is synthesised in the Fourier domain, so all tiling maps are periodic by construction. No image-generation model used: procedural gives guaranteed seamlessness, exact metric scale (pattern repeat = 7.5 cm columns, 3 mm loops) and is cheap to reproduce.",
    "paid_calls": [],
    "cost_usd": 0.0,
    "models_prompts": "none (no OpenAI/Gemini/Meshy calls made)",
    "conventions": {"normal": "OpenGL, green = +Y up (Godot)", "albedo": "sRGB 8-bit", "roughness_ao_height": "linear 8-bit grey", "emission": "sRGB 8-bit"},
    "seeds": SEEDS,
    "materials": {
        "carpet": dict(size="2048x2048", world_size_m=[1.0, 1.0], method="jittered hex-ish loop lattice (341x341 loops, ~6 px = ~3 mm pitch) splatted with an elliptical loop kernel by periodic FFT convolution; per-loop height and tint variance, dirt specks, faint low-contrast traffic matting; height -> normal(strength 4.2), AO from height, roughness 0.88-0.97", **results["carpet"]),
        "wallpaper": dict(size="2048x2048", world_size_m=[0.6, 0.6], method="analytic mask: double pinstripes every 256 px (7.5 cm), elongated diamond lozenges with centre dot + tiny interstitial dot, alternate columns offset half step; ochre ink 8.4% darker/more saturated; vinyl stipple and paper fibre; roll seam at x=0 (lifted lip + dark line, periodic); roughness 0.55-0.75", **results["wallpaper"]),
        "ceiling_tile": dict(size="1024x1024", world_size_m=[0.6, 0.6], method="thresholded-contour worm fissures + pinholes, 10 px (6 mm) bevel on all four edges (non-tiling by design); stained variant = irregular tide-line ring multiplied onto the clean albedo, bevel 40% stained", **results["ceiling_tile"]),
        "troffer_lens": dict(size="512x1024", world_size_m=[0.6, 1.2], method="square-pyramid prism grid in normal map, plain 14 px frame; emission with edge falloff, two faint tube bands, 22 insect silhouettes and dust concentrated at the bottom (long-axis) end. Pitch is 4 px (4.69 mm at this resolution) rather than 4 mm: an integer pixel pitch avoids aliasing; at 853 px/m a true 4 mm pitch would be 3.4 px.", **results["troffer_lens"]),
        "baseboard": dict(size="1024x128", world_size_m=[1.0, 0.1], method="cove-base profile height (lip, groove, face, toe) + periodic grain, line-stroke scuffs and grime gradient; tiles horizontally", **results["baseboard"]),
        "decals": {k: v for k, v in results.items() if k.startswith("decal_")},
    },
    "decal_notes": "RGBA, straight (non-premultiplied) alpha, transparent borders, not tiling. Optional decal normal maps skipped: they add nothing at decal scale. decal_wall_waterdamage: top of wall = row 0. decal_wall_grime_low: bottom of wall = last row.",
    "seam_check_note": "ratio of wrap-around pixel step to a normal neighbour step; ~1 = invisible. wallpaper_normal/ao cols are high on purpose: the roll seam line sits exactly at the left tile edge.",
    "seam_check_wrap_step_over_neighbour_step": seams,
    "output_files": info,
    "runtime_seconds": round(time.time() - t0, 1),
}
mp = os.path.join(ROOT, "pipeline", "manifests", "textures_level0.json")
os.makedirs(os.path.dirname(mp), exist_ok=True)
with open(mp, "w") as f:
    json.dump(manifest, f, indent=2, default=float)
print("done", round(time.time() - t0, 1), "s;", len(files), "files")
print(json.dumps(seams, indent=1))
