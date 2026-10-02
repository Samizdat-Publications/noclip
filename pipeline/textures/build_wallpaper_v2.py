"""Wallpaper v2: photographic Gemini wallpaper -> seamless 2048 PBR set (wallpaper_v2c<N>_*, wallpaper_v2_* = pick).

  python pipeline/textures/build_wallpaper_v2.py --gen          # PAID: 4 candidates (cached, skipped if present)
  python pipeline/textures/build_wallpaper_v2.py --process      # free: period detect, crop to whole periods, seamless, maps, previews
  python pipeline/textures/build_wallpaper_v2.py --pick N       # candidate copied to wallpaper_v2_*
Key: GEMINI_API_KEY via python-dotenv from .env (never printed). Writes only new wallpaper_v2* files.
"""
import argparse, io, json, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
sys.path.insert(0, os.path.dirname(__file__))
from tex_common import srgb2lin, lin2srgb, normal_from_height, gnoise, ROOT, OUT, PREV
from build_carpet_v2 import flatten, make_seamless, save_maps

CACHE = os.path.join(ROOT, "pipeline", "textures", "cache", "wallpaper_v2")
MANIFEST = os.path.join(ROOT, "pipeline", "manifests", "wallpaper_v2.json")
N = 2048
OLD = os.path.join(OUT, "wallpaper_albedo.png")

BASE = ("Straight-on flat scan-like photograph of a piece of 1990s commercial office vinyl wallpaper, pale mustard-cream colour, "
        "filling the whole frame edge to edge, camera exactly perpendicular to the wall, no perspective, no vignette, perfectly even soft diffuse lighting, "
        "no shadows, no light gradient. The frame covers about 60 cm of wall. The design is a subtle, slightly irregular vertical pattern: "
        "thin broken vertical pinstripes in a slightly darker ochre, running perfectly vertically and spaced about 7 cm apart (so about eight stripes across the frame), "
        "with a small repeating motif in each gap between stripes %s, printed very slightly off-register so the ink sits a little crooked and uneven. "
        "Low contrast, pattern only a few percent darker than the paper. Real paper and vinyl grain visible, faint yellowing, very slight sheen variation, tiny flecks. "
        "No wall edges, no seams, no corners, no baseboard, no objects, no text, no borders. A real photograph, not an illustration or a 3D render.")
CANDS = [
    BASE % "(a column of tiny chevrons, about 5 mm across, stacked every 2 cm)",
    BASE % "(a column of tiny round dots, about 3 mm across, spaced every 1.5 cm)",
    BASE % "(small dashes and tiny diamonds alternating, about 4 mm, spaced every 2.5 cm)",
    BASE % "(a column of tiny chevrons, about 4 mm across, stacked every 1.5 cm), with the pinstripes thinner and more broken up",
]
PRICE = 0.134


def gen():
    from dotenv import load_dotenv
    from google import genai
    from google.genai import types
    load_dotenv(os.path.join(ROOT, ".env"))
    c = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    names = [m.name.replace("models/", "") for m in c.models.list()]
    pro = "gemini-3-pro-image" if "gemini-3-pro-image" in names else [n for n in names if "pro-image" in n][0]
    log = os.path.join(CACHE, "gen_log.json")
    L = json.load(open(log)) if os.path.exists(log) else {}
    for i, prompt in enumerate(CANDS, 1):
        fn = os.path.join(CACHE, "cand%d.png" % i)
        if os.path.exists(fn):
            continue
        cfg = types.GenerateContentConfig(response_modalities=["IMAGE"], temperature=1.0,
                                          image_config=types.ImageConfig(aspect_ratio="1:1", image_size="2K"))
        for attempt in range(2):
            r = c.models.generate_content(model=pro, contents=prompt, config=cfg)
            ok = False
            for part in (r.candidates[0].content.parts if r.candidates else []):
                if getattr(part, "inline_data", None) and part.inline_data.data:
                    img = Image.open(io.BytesIO(part.inline_data.data)).convert("RGB")
                    img.save(fn)
                    L[str(i)] = dict(model=pro, prompt=prompt, size=list(img.size), cost_usd=PRICE)
                    print("cand", i, pro, img.size, flush=True)
                    ok = True
                    break
            if ok:
                break
            print("cand", i, "no image", flush=True)
        json.dump(L, open(log, "w"), indent=1)


# ------------------------------------------------------------------ period detection and crop
def autocorr_period(sig, lo, hi):
    """Dominant period (px, subpixel) of 1D signal via autocorrelation peak in [lo,hi]."""
    s = sig - sig.mean()
    n = len(s)
    f = np.fft.rfft(s, 2 * n)
    ac = np.fft.irfft(f * np.conj(f))[:n]
    ac /= ac[0] + 1e-12
    seg = ac[lo:hi]
    k = int(np.argmax(seg)) + lo
    if 1 <= k < n - 1:
        a, b, c = ac[k - 1], ac[k], ac[k + 1]
        d = (a - c) / (2 * (a - 2 * b + c) + 1e-12)
        return k + float(np.clip(d, -0.5, 0.5)), float(ac[k])
    return float(k), float(ac[k])


def detect(lum):
    colp = lum.mean(0)       # stripes vary along x
    px, sx = autocorr_period(colp, 60, 600)
    xs = np.argsort(colp)[:60]               # darkest columns (ink)
    prof = lum[:, xs].mean(1)
    py, sy = autocorr_period(prof, 12, 700)
    return px, py, sx, sy


def crop_periods(a, px, py, nx, ny, off=(0, 0)):
    """Crop nx*px by ny*py px region (subpixel) and resample to NxN. a: HxWx3 float."""
    W, H = nx * px, ny * py
    yy, xx = np.meshgrid(np.arange(N), np.arange(N), indexing="ij")
    sy = off[0] + (yy + 0.5) * H / N - 0.5
    sx = off[1] + (xx + 0.5) * W / N - 0.5
    out = np.empty((N, N, 3))
    for k in range(3):
        out[..., k] = ndi.map_coordinates(a[..., k], [sy, sx], order=3, mode="reflect")
    return out


def build_set(idx, rng, info):
    src = Image.open(os.path.join(CACHE, "cand%d.png" % idx)).convert("RGB")
    s = min(src.size)
    src = src.crop(((src.width - s) // 2, (src.height - s) // 2, (src.width + s) // 2, (src.height + s) // 2))
    a = srgb2lin(np.asarray(src).astype(np.float64) / 255.0)
    a = flatten(a, 90)
    L = a @ np.array([0.2126, 0.7152, 0.0722])
    hp = np.log(np.maximum(L, 1e-4)); hp = hp - ndi.gaussian_filter(hp, 30)
    px, py, sx, sy = detect(hp)
    H = a.shape[0]
    nx = max(1, int(H // px)); ny = max(1, int(H // py))
    off = ((H - ny * py) / 2, (H - nx * px) / 2)
    info.update(period_x_px=round(px, 2), period_y_px=round(py, 2), strength_x=round(sx, 3), strength_y=round(sy, 3), nx=nx, ny=ny)
    b = crop_periods(a, px, py, nx, ny, off)
    b = flatten(b, 120)
    b = make_seamless(b, rng)
    old = np.asarray(Image.open(OLD).convert("RGB")).astype(np.float64).reshape(-1, 3).mean(0)
    for _ in range(6):
        cur = lin2srgb(np.clip(b, 0, None)).reshape(-1, 3).mean(0) * 255
        b = b * (srgb2lin(old / 255.0) / np.maximum(srgb2lin(cur / 255.0), 1e-5))
    alb = np.clip(lin2srgb(np.clip(b, 0, 1)), 0, 1)
    Lm = (alb * np.array([0.2126, 0.7152, 0.0722])).sum(-1)
    hpl = Lm - ndi.gaussian_filter(Lm, 30, mode="wrap")
    h = ndi.gaussian_filter(hpl, 0.9, mode="wrap")
    hn = np.clip((h - np.percentile(h, 0.5)) / (np.percentile(h, 99.5) - np.percentile(h, 0.5)), 0, 1)
    nrm = normal_from_height(hn, 1.6)
    ink = np.clip(-ndi.gaussian_filter(hpl, 1.5, mode="wrap") / (hpl.std() * 2.0), 0, 1)
    grain = ndi.gaussian_filter(hpl, 1.0, mode="wrap"); grain = grain / (grain.std() + 1e-9)
    rough = np.clip(0.64 + 0.04 * ink + 0.015 * grain, 0.55, 0.75)
    ao = np.clip(1 - 0.5 * np.clip(ndi.gaussian_filter(hn, 3, mode="wrap") - hn, 0, 1) * 3, 0.6, 1)
    return alb, nrm, rough, ao, hn


def shade(alb, nrm):
    Ld = np.array([0.88, -0.30, 0.36]); Ld /= np.linalg.norm(Ld)
    d = np.clip((nrm * Ld).sum(-1), 0, 1)
    return np.clip(alb * (0.25 + 0.95 * d[..., None]), 0, 1)


def pattern_contrast_view(alb):
    """Approximates the shader's tex_mean + (alb - tex_mean) * 2.4 (done in linear, about the texture mean)."""
    lin = srgb2lin(alb); m = lin.reshape(-1, 3).mean(0)
    return lin2srgb(np.clip(m + (lin - m) * 2.4, 0, 1))


def process(pick):
    idxs = sorted(int(f[4]) for f in os.listdir(CACHE) if f.startswith("cand") and f.endswith(".png"))
    stats = {}
    cw, ch = 1000, 667
    sheet = Image.new("RGB", (len(idxs) * (cw + 8), ch * 3 + 8 * 3 + 40), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for j, i in enumerate(idxs):
        rng = np.random.default_rng(8100 + i)
        info = {}
        alb, nrm, rough, ao, hn = build_set(i, rng, info)
        save_maps("wallpaper_v2c%d" % i, alb, nrm, rough, ao, hn)
        t = np.tile(alb, (2, 3, 1))
        def im(x): return Image.fromarray((np.clip(x, 0, 1) * 255).astype(np.uint8)).resize((cw, ch), Image.LANCZOS)
        x0 = j * (cw + 8)
        sheet.paste(im(t), (x0, 30)); sheet.paste(im(pattern_contrast_view(t)), (x0, 30 + 8 + ch))
        sheet.paste(im(shade(t, np.tile(nrm, (2, 3, 1)))), (x0, 30 + 2 * (8 + ch)))
        mean = (alb.reshape(-1, 3).mean(0) * 255).round(1).tolist()
        dr.text((x0 + 4, 6), "cand %d  tiled 3x2 (1.8x1.2 m)  mean %s  period px %s" % (i, mean, (info["period_x_px"], info["period_y_px"])), fill=(255, 255, 255))
        dr.text((x0 + 4, 30 + ch + 1), "same, shader contrast x2.4", fill=(255, 255, 255))
        dr.text((x0 + 4, 30 + 2 * (8 + ch) + 1), "grazing light from normal", fill=(255, 255, 255))
        Lm = (alb * np.array([0.2126, 0.7152, 0.0722])).sum(-1)
        stats[i] = dict(mean_srgb=mean, lum_std_pct=round(float(Lm.std() / Lm.mean() * 100), 2),
                        rough_p5_p95=[round(float(np.percentile(rough, 5)), 3), round(float(np.percentile(rough, 95)), 3)], **info)
        if i == pick:
            save_maps("wallpaper_v2", alb, nrm, rough, ao, hn)
            t3 = np.tile(alb, (3, 3, 1))
            Image.fromarray((t3 * 255).astype(np.uint8)).resize((2048, 2048), Image.LANCZOS).save(os.path.join(PREV, "wallpaper_v2_tile3x3.png"))
    sheet.save(os.path.join(PREV, "wallpaper_v2_candidates.png"))
    old = (np.asarray(Image.open(OLD).convert("RGB")).reshape(-1, 3).mean(0)).round(1).tolist()
    Lg = json.load(open(os.path.join(CACHE, "gen_log.json")))
    json.dump(dict(asset="wallpaper_v2", script="pipeline/textures/build_wallpaper_v2.py", pick=pick, old_mean_srgb=old, generation=Lg,
                   processing=dict(steps="flatten (gaussian 90px) -> autocorrelation period detect (stripes x, motif y) -> subpixel crop of whole periods resampled to 2048 -> flatten 120 -> half-offset min-cut seamless -> per-channel mean match to old wallpaper_albedo",
                                   normal="OpenGL (+Y up), strength 1.6 on high-passed luminance", roughness="0.64 + ink/grain, clamp 0.55-0.75", seeds="8100+candidate"),
                   candidates=stats), open(MANIFEST, "w"), indent=1)
    print("old mean", old); print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--gen", action="store_true"); ap.add_argument("--process", action="store_true"); ap.add_argument("--pick", type=int, default=1)
    a = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    if a.gen: gen()
    if a.process: process(a.pick)
