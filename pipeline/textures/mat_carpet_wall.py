import numpy as np
from tex_common import *

# ---------------------------------------------------------------- CARPET
def build_carpet(seed=1001):
    N = 2048
    rng = np.random.default_rng(seed)
    cells = 341  # ~6 px pitch at 2048 px / m  => ~3 mm loops
    cell = N / cells
    ii, jj = np.meshgrid(np.arange(cells), np.arange(cells), indexing="ij")
    py = (ii + 0.5 + rng.uniform(-0.30, 0.30, ii.shape)) * cell
    px = (jj + 0.5 * (ii % 2) + rng.uniform(-0.30, 0.30, ii.shape)) * cell
    yi = np.round(py).astype(int) % N
    xi = np.round(px).astype(int) % N
    amp = rng.lognormal(0, 0.16, ii.shape)
    tint = rng.standard_normal(ii.shape)
    imp = np.zeros((N, N)); impt = np.zeros((N, N))
    np.add.at(imp, (yi, xi), amp)
    np.add.at(impt, (yi, xi), amp * tint)
    yy, xx = wrapped_axes((N, N))
    r2 = (yy / 3.2) ** 2 + (xx / 3.7) ** 2
    k = np.where(r2 < 1, np.clip(1 - r2, 0, None) ** 0.9, 0.0) - 0.32 * np.exp(-r2 / 0.09) * (r2 < 1)
    H = periodic_conv(imp, k)
    T = np.clip(periodic_conv(impt, k) / np.maximum(periodic_conv(imp, k * 0 + (r2 < 1)), 0.6), -2.5, 2.5)
    fine = gnoise((N, N), rng, 0.8)
    mat_n = gnoise((N, N), rng, 70)  # traffic matting, very faint, mid-scale
    mat = ss(0.9, 2.2, mat_n) * 0.5 + ss(1.4, 2.6, gnoise((N, N), rng, 28)) * 0.25  # kept faint, see lum/rough use
    Hh = H + 0.12 * fine
    Hh = Hh * (1 - 0.12 * mat)
    Hn = np.clip((Hh - np.percentile(Hh, 0.5)) / (np.percentile(Hh, 99.7) - np.percentile(Hh, 0.5)), 0, 1)

    # specks / grit
    speck = np.zeros((N, N))
    ys, xs = rng.integers(0, N, 2600), rng.integers(0, N, 2600)
    np.add.at(speck, (ys, xs), rng.uniform(0.4, 1.0, 2600))
    speck = np.clip(blur(speck, 1.3) * 9, 0, 1)
    grit = ss(2.5, 3.5, gnoise((N, N), rng, 1.6)) * 0.25

    base = srgb2lin(rgb8(138, 116, 68))
    lum = (0.70 + 0.30 * Hn ** 0.8)
    lum *= 1 + 0.11 * T + 0.045 * fine
    lum *= 1 - 0.55 * speck - grit - 0.025 * mat
    hue = np.stack([1 + 0.035 * T, 1 + 0.0 * T, 1 - 0.07 * T], -1)  # lighter loops drift a bit warmer
    lin = base * lum[..., None] * hue
    alb = match_mean_srgb(lin, (138, 116, 68))

    rough = 0.935 + 0.022 * fine + 0.012 * gnoise((N, N), rng, 3) - 0.02 * Hn - 0.05 * mat + 0.02 * speck
    rough = np.clip(rough, 0.80, 0.985)
    ao = np.clip(0.38 + 0.62 * Hn ** 0.65, 0, 1) * (1 - 0.15 * speck)
    nrm = normal_from_height(Hn, 4.2)
    save_rgb("carpet_albedo.png", alb)
    save_normal("carpet_normal.png", nrm)
    save_gray("carpet_roughness.png", rough)
    save_gray("carpet_ao.png", ao)
    save_gray("carpet_height.png", Hn)
    return dict(mean_albedo=(alb.mean((0, 1)) * 255).round(1).tolist(),
                rough_p5_p95=[float(np.percentile(rough, 5)), float(np.percentile(rough, 95))])


# ---------------------------------------------------------------- WALLPAPER
def build_wallpaper(seed=2002):
    N = 2048
    rng = np.random.default_rng(seed)
    Y, X = np.mgrid[0:N, 0:N].astype(float)
    X += 0.5; Y += 0.5
    # layout: 7.5 cm = 256 px columns. stripes at x=64 (+-5 px), lozenge column at x=192, seam at x=0.
    def pdist(x, c, per):
        return np.abs(((x - c + per / 2) % per) - per / 2)
    stripe = np.zeros((N, N))
    for c in (64 - 5.5, 64 + 5.5):
        d = pdist(X, c, 256)
        stripe = np.maximum(stripe, np.clip((2.1 - d) / 1.1 + 0.5, 0, 1))
    k = np.floor(X / 256).astype(int)
    xc = 256 * k + 192
    dx = X - xc
    off = 64 * (k % 2)
    dy = ((Y - off + 64) % 128) - 64
    edge_n = gnoise((N, N), rng, 1.2)
    d = np.abs(dx) / 11.5 + np.abs(dy) / 31.0 + 0.025 * edge_n
    # soften diamond corners a bit
    loz = np.clip((1 - d) / 0.10, 0, 1)
    dot = np.clip((3.6 - np.hypot(dx, dy)) / 1.0 + 0.5, 0, 1)
    dot2 = np.clip((2.1 - np.hypot(dx, dy - 64 * np.sign(dy + 1e-9))) / 1.0 + 0.5, 0, 1) * (np.abs(dy) > 32)
    ink = np.maximum(np.maximum(stripe * 0.95, loz * 0.85), np.maximum(dot * 1.0, dot2 * 0.8))
    ink = ink * (0.92 + 0.08 * ss(-1.5, 1.5, gnoise((N, N), rng, 0.9)))  # uneven print coverage

    base = srgb2lin(rgb8(201, 183, 112))
    inkc = base * np.array([0.93, 0.915, 0.78])  # darker, more saturated ochre
    lin = base * (1 - ink[..., None]) + inkc * ink[..., None]
    fiber = gnoise((N, N), rng, 0.6, 3.0) * 0.6 + gnoise((N, N), rng, 3.0, 0.6) * 0.6 + gnoise((N, N), rng, 0.7) * 0.5
    lin *= (1 + 0.020 * fiber + 0.005 * gnoise((N, N), rng, 55))[..., None]

    # roll seam, periodic around x = 0
    s = np.where(X < N / 2, X, X - N)  # signed distance from seam
    seam_line = np.exp(-(s / 1.1) ** 2)
    seam_wide = np.exp(-(s / 7.0) ** 2)
    lin *= (1 - 0.07 * seam_line - 0.035 * seam_wide)[..., None]

    stip = gnoise((N, N), rng, 1.5)
    hgt = 0.30 * stip + 0.08 * fiber - 0.55 * blur(ink, 1.0) \
        + (0.55 * np.exp(-(s / 6.0) ** 2) * np.where(s >= 0, 1.0, 0.25) - 0.55 * np.exp(-(s / 1.0) ** 2))
    nrm = normal_from_height(hgt, 0.95)
    alb = match_mean_srgb(lin, (201, 183, 112), weights=1 - ink)  # mean over base paper
    rough = np.clip(0.62 + 0.035 * stip + 0.02 * fiber + 0.05 * ink + 0.10 * seam_line, 0.55, 0.75)
    ao = np.clip(1 - 0.35 * np.clip(blur(hgt, 2.0) - hgt, 0, 1) - 0.25 * seam_line, 0, 1)
    save_rgb("wallpaper_albedo.png", alb)
    save_normal("wallpaper_normal.png", nrm)
    save_gray("wallpaper_roughness.png", rough)
    save_gray("wallpaper_ao.png", ao)
    Y_ = lambda c: 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    return dict(mean_albedo=(alb.mean((0, 1)) * 255).round(1).tolist(),
                ink_luminance_drop_pct=round(100 * (1 - Y_(inkc) / Y_(base)), 2),
                stripe_period_px=256, lozenge_step_px=128)
