"""Carpet v2: photographic Gemini carpet -> seamless 2048 PBR set (carpet_v2c<N>_* and carpet_v2_* = pick).

  python pipeline/textures/build_carpet_v2.py --gen          # PAID: 3 pro + 1 flash candidates (cached, skipped if present)
  python pipeline/textures/build_carpet_v2.py --process      # free: seamless + maps + previews
  python pipeline/textures/build_carpet_v2.py --pick N       # which candidate is copied to carpet_v2_* (default 2)
Key: GEMINI_API_KEY via python-dotenv from .env (never printed). Writes only new carpet_v2* files.
"""
import argparse, io, json, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
sys.path.insert(0, os.path.dirname(__file__))
from tex_common import srgb2lin, lin2srgb, normal_from_height, gnoise, ROOT, OUT, PREV

CACHE = os.path.join(ROOT, "pipeline", "textures", "cache", "carpet_v2")
MANIFEST = os.path.join(ROOT, "pipeline", "manifests", "carpet_v2.json")
N = 2048
TARGET_MEAN = np.array([138.0, 116.0, 68.0])  # measured mean of the current carpet_albedo.png

BASE = ("Photograph of old commercial office carpet, a wide flat view looking perfectly straight down from directly above, "
        "covering about one square metre of floor, so each individual loop is tiny (about 3 to 4 mm) and hundreds of loops are visible "
        "across the frame. Short dense loop-pile berber, dirty mustard-ochre and tan from decades of use in a 1990s office, "
        "fine multi-tone flecks of brown, cream and olive yarn, faint rows in the loop structure, lightly matted and flattened "
        "in places, a couple of very faint old stains. Perfectly even soft flat lighting, no shadows, no gradient, no vignette, "
        "no perspective, sharp focus over the entire frame. The carpet fills the whole frame edge to edge. No objects, no seams, "
        "no borders, no text. A real photograph, not an illustration or a 3D render.")
CANDS = [
    ("pro", BASE),
    ("pro", BASE + " Slightly more worn and darker olive-brown in the flecks, tighter berber weave."),
    ("pro", BASE + " Warmer yellow-tan overall, a coarser looped weave with visible lengthwise rows."),
    ("flash", BASE),
]
PRICE = {"pro": 0.134, "flash": 0.067}


def gen():
    from dotenv import load_dotenv
    from google import genai
    from google.genai import types
    load_dotenv(os.path.join(ROOT, ".env"))
    c = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    names = [m.name.replace("models/", "") for m in c.models.list()]
    pro = "gemini-3-pro-image" if "gemini-3-pro-image" in names else [n for n in names if "pro-image" in n][0]
    flash = "gemini-3.1-flash-image" if "gemini-3.1-flash-image" in names else [n for n in names if "flash-image" in n][-1]
    log = os.path.join(CACHE, "gen_log.json")
    L = json.load(open(log)) if os.path.exists(log) else {}
    for i, (kind, prompt) in enumerate(CANDS, 1):
        fn = os.path.join(CACHE, "cand%d.png" % i)
        if os.path.exists(fn):
            continue
        model = pro if kind == "pro" else flash
        ic = {"aspect_ratio": "1:1", "image_size": "2K"}
        cfg = types.GenerateContentConfig(response_modalities=["IMAGE"], temperature=1.0, image_config=types.ImageConfig(**ic))
        for attempt in range(2):
            r = c.models.generate_content(model=model, contents=prompt, config=cfg)
            ok = False
            for part in (r.candidates[0].content.parts if r.candidates else []):
                if getattr(part, "inline_data", None) and part.inline_data.data:
                    img = Image.open(io.BytesIO(part.inline_data.data)).convert("RGB")
                    img.save(fn)
                    L[str(i)] = dict(model=model, prompt=prompt, size=list(img.size), cost_usd=PRICE[kind])
                    print("cand", i, model, img.size, flush=True)
                    ok = True
                    break
            if ok:
                break
            print("cand", i, "no image", flush=True)
        json.dump(L, open(log, "w"), indent=1)


# ------------------------------------------------------------------ seamless
def flatten(a, sigma):
    """a: float linear RGB. Divide out low-frequency tone/colour so macro variation is gone (game adds its own)."""
    lp = np.stack([ndi.gaussian_filter(a[..., k], sigma, mode="reflect") for k in range(3)], -1)
    return a / np.maximum(lp, 1e-4) * a.reshape(-1, 3).mean(0)


def mincut_path(cost, start):
    """cost[h, w]; vertical path, one column per row, |dx|<=1, forced to start at `start` and end near it (cyclic)."""
    h, w = cost.shape
    INF = 1e18
    D = np.full((h, w), INF); D[0, start] = cost[0, start]
    B = np.zeros((h, w), np.int8)
    for y in range(1, h):
        p = D[y - 1]
        l = np.r_[INF, p[:-1]]; r = np.r_[p[1:], INF]
        st = np.stack([l, p, r]); k = st.argmin(0)
        D[y] = st.min(0) + cost[y]; B[y] = k - 1
    lo, hi = max(0, start - 1), min(w, start + 2)
    x = lo + int(np.argmin(D[-1, lo:hi]))
    path = np.zeros(h, int)
    for y in range(h - 1, -1, -1):
        path[y] = x
        x = x + int(B[y, x])
    return path


def patch_vertical_band(R, S, x0, x1, ov, rng):
    """Replace columns [x0,x1) of R by S's same columns, joined to R with a min-cut at each edge (overlap +-ov px)."""
    H = R.shape[0]
    out = R.copy()
    out[:, x0:x1] = S[:, x0:x1]
    for side in (0, 1):
        edge = x0 if side == 0 else x1
        a0 = edge - ov
        a1 = edge + ov
        A, Bm = R[:, a0:a1], S[:, a0:a1]
        d = ((A - Bm) ** 2).sum(-1)
        d = ndi.uniform_filter(d, 3)
        best = None
        for st in rng.choice(np.arange(ov // 2, 2 * ov - ov // 2), 6, replace=False):
            pth = mincut_path(d, int(st))
            c = d[np.arange(H), pth].sum() + 1e3 * abs(pth[0] - pth[-1])
            if best is None or c < best[0]:
                best = (c, pth)
        pth = best[1]
        cols = np.arange(2 * ov)[None, :]
        m = np.clip((cols - pth[:, None]) / 2.0 + 0.5, 0, 1)  # 0 left of path, 1 right (soft 2 px)
        if side == 0:   # left R, right S
            blend = A * (1 - m[..., None]) + Bm * m[..., None]
        else:           # left S, right R
            blend = Bm * (1 - m[..., None]) + A * m[..., None]
        out[:, a0:a1] = blend
    return out


def make_seamless(a, rng):
    H = a.shape[0]
    R = np.roll(a, (H // 2, H // 2), (0, 1))          # seam cross is now at the centre
    band, ov = 576, 224
    c = H // 2
    S = np.roll(R, H // 4 + int(rng.integers(0, 64)), 1)
    R = patch_vertical_band(R, S, c - band // 2, c + band // 2, ov, rng)
    Rt = np.transpose(R, (1, 0, 2)).copy()
    St = np.roll(Rt, H // 4 + int(rng.integers(0, 64)), 1)
    Rt = patch_vertical_band(Rt, St, c - band // 2, c + band // 2, ov, rng)
    return np.transpose(Rt, (1, 0, 2)).copy()


def periodic_warp(a, rng, amp, sigma):
    H, W = a.shape[:2]
    dy = gnoise((H, W), rng, sigma); dx = gnoise((H, W), rng, sigma)
    dy = dy / dy.std() * amp; dx = dx / dx.std() * amp
    yy, xx = np.meshgrid(np.arange(H), np.arange(W), indexing="ij")
    out = np.empty_like(a)
    for k in range(a.shape[2]):
        out[..., k] = ndi.map_coordinates(a[..., k], [(yy + dy) % H, (xx + dx) % W], order=1, mode="grid-wrap")
    return out


def build_set(idx, rng):
    src = Image.open(os.path.join(CACHE, "cand%d.png" % idx)).convert("RGB")
    s = min(src.size)
    src = src.crop(((src.width - s) // 2, (src.height - s) // 2, (src.width + s) // 2, (src.height + s) // 2))
    T = N
    a = srgb2lin(np.asarray(src.resize((T, T), Image.LANCZOS)).astype(np.float64) / 255.0)
    a = flatten(a, 40)
    lg = np.log(np.maximum(a, 1e-4)); lg = lg + 0.35 * (lg - ndi.gaussian_filter(lg, (7, 7, 0), mode='wrap'))  # local contrast so loops read
    a = np.exp(lg)
    a = make_seamless(a, rng)
    big = a  # unique 2048 content, no repetition inside the 1 m tile
    tone = gnoise((N, N), rng, 260); tone = tone / tone.std()
    big = big * (1 + 0.05 * tone)[..., None]
    for _ in range(6):
        cur = lin2srgb(np.clip(big, 0, None)).reshape(-1, 3).mean(0) * 255
        big = big * (srgb2lin(TARGET_MEAN / 255.0) / np.maximum(srgb2lin(cur / 255.0), 1e-5))
    alb = np.clip(lin2srgb(np.clip(big, 0, 1)), 0, 1)
    L = (alb * np.array([0.2126, 0.7152, 0.0722])).sum(-1)
    hp = L - ndi.gaussian_filter(L, 24, mode="wrap")
    h = ndi.gaussian_filter(hp, 0.8, mode="wrap")
    hn = np.clip((h - np.percentile(h, 0.5)) / (np.percentile(h, 99.5) - np.percentile(h, 0.5)), 0, 1)
    mat = ndi.gaussian_filter(L, 40, mode="wrap"); mat = (mat - mat.mean()) / mat.std()
    nrm = normal_from_height(hn, 6.0)
    rough = np.clip(0.93 - 0.05 * (hn - 0.5) - 0.02 * np.clip(-mat, 0, 2), 0.82, 0.975)
    ao = np.clip(0.30 + 0.70 * hn ** 0.8, 0, 1)
    ao = np.clip(ao * (1 - 1.2 * ndi.gaussian_filter(np.clip(-hp, 0, None), 3, mode="wrap")), 0, 1)
    return alb, nrm, rough, ao, hn


def save_maps(prefix, alb, nrm, rough, ao, hn):
    def s8(a): return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8))
    s8(alb).save(os.path.join(OUT, prefix + "_albedo.png"))
    s8(nrm * 0.5 + 0.5).save(os.path.join(OUT, prefix + "_normal.png"))
    for n, a in (("roughness", rough), ("ao", ao), ("height", hn)):
        s8(a).convert("L").save(os.path.join(OUT, "%s_%s.png" % (prefix, n)))


def shade(alb, nrm):
    Ld = np.array([0.88, -0.30, 0.36]); Ld /= np.linalg.norm(Ld)
    d = np.clip((nrm * Ld).sum(-1), 0, 1)
    return np.clip(alb * (0.25 + 0.95 * d[..., None]), 0, 1)


def process(pick):
    idxs = sorted(int(f[4]) for f in os.listdir(CACHE) if f.startswith("cand") and f.endswith(".png"))
    stats = {}
    sheet = Image.new("RGB", (len(idxs) * 1100, 1100 * 2 + 60), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for j, i in enumerate(idxs):
        rng = np.random.default_rng(7000 + i)
        alb, nrm, rough, ao, hn = build_set(i, rng)
        save_maps("carpet_v2c%d" % i, alb, nrm, rough, ao, hn)
        mean = (alb.reshape(-1, 3).mean(0) * 255).round(1).tolist()
        stats[i] = dict(mean_srgb=mean, rough_p5_p95=[float(np.percentile(rough, 5)), float(np.percentile(rough, 95))])
        tile = Image.fromarray((np.tile(alb, (2, 2, 1)) * 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS)
        sh = Image.fromarray((shade(np.tile(alb, (2, 2, 1)), np.tile(nrm, (2, 2, 1))) * 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS)
        sheet.paste(tile, (j * 1100, 30)); sheet.paste(sh, (j * 1100, 1100 + 30))
        dr.text((j * 1100 + 6, 6), "cand %d albedo 2x2 tiled  mean %s" % (i, mean), fill=(255, 255, 255))
        dr.text((j * 1100 + 6, 1106), "cand %d grazing-light from normal" % i, fill=(255, 255, 255))
        if i == pick:
            save_maps("carpet_v2", alb, nrm, rough, ao, hn)
            t3 = np.tile(alb, (3, 3, 1))
            Image.fromarray((t3 * 255).astype(np.uint8)).resize((2048, 2048), Image.LANCZOS).save(os.path.join(PREV, "carpet_v2_tile3x3.png"))
            Image.fromarray((shade(t3, np.tile(nrm, (3, 3, 1))) * 255).astype(np.uint8)).resize((2048, 2048), Image.LANCZOS).save(os.path.join(PREV, "carpet_v2_tile3x3_shaded.png"))
    sheet.save(os.path.join(PREV, "carpet_v2_candidates.png"))
    L = json.load(open(os.path.join(CACHE, "gen_log.json")))
    json.dump(dict(asset="carpet_v2", script="pipeline/textures/build_carpet_v2.py", pick=pick, target_mean_srgb=TARGET_MEAN.tolist(),
                   generation=L,
                   processing=dict(flatten_gaussian_sigma_px=40, local_contrast='log-domain +35% over 7px', working_tile=2048, note='loop pitch ~15px = ~7mm per 1m tile; uv scale 2 gives ~3.5mm',
                                   final_layout="single unique seamless 2048 tile + 5% periodic tone",
                                   seamless="half-offset, min-cut patch of 576px band (overlap 224) vertical then horizontal",
                                   normal="OpenGL (+Y up), strength 6.0 on high-passed luminance", seeds="7000+candidate"),
                   candidates=stats), open(MANIFEST, "w"), indent=1)
    print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--gen", action="store_true"); ap.add_argument("--process", action="store_true"); ap.add_argument("--pick", type=int, default=2)
    a = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    if a.gen: gen()
    if a.process: process(a.pick)
