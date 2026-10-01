import numpy as np, cv2
from tex_common import *


def _smooth1d(n, rng, sigma):
    v = rng.standard_normal(n)
    k = np.fft.rfft(v) * np.exp(-0.5 * (2 * np.pi * np.fft.rfftfreq(n) * sigma) ** 2)
    v = np.fft.irfft(k, n)
    return (v - v.mean()) / v.std()


def _specks(shape, rng, n, rmin, rmax, ys=None, xs=None, vals=(0.6, 1.0), mask=None):
    h, w = shape
    c = np.zeros((h * 4, w * 4), np.uint8)
    for i in range(n):
        y = ys[i] if ys is not None else rng.uniform(0, h)
        x = xs[i] if xs is not None else rng.uniform(0, w)
        if mask is not None and mask[int(np.clip(y, 0, h - 1)), int(np.clip(x, 0, w - 1))] < rng.random():
            continue
        cv2.circle(c, (int(x * 4), int(y * 4)), max(1, int(rng.uniform(rmin, rmax) * 4)), int(rng.uniform(*vals) * 255), -1, cv2.LINE_AA)
    return cv2.resize(c, (w, h), interpolation=cv2.INTER_AREA).astype(float) / 255


# ---------------------------------------------------------------- WALL WATER DAMAGE (1024 x 2048, top of wall = row 0)
def build_waterdamage(seed=6001):
    W, H = 1024, 2048
    rng = np.random.default_rng(seed)
    Y, X = np.mgrid[0:H, 0:W].astype(float)
    xn = X / W
    env = np.exp(-((xn - 0.5 + 0.06 * _smooth1d(W, rng, 90)[None, :].repeat(H, 0)[0:1, :]) / 0.28) ** 2)[0]  # (W,)
    env = env * (0.65 + 0.35 * ss(-1, 1, _smooth1d(W, rng, 40)))
    streak = gnoise((H, W), rng, 150, 22.0)
    streak2 = gnoise((H, W), rng, 55, 9.0)
    fine_st = gnoise((H, W), rng, 40, 2.2)
    boundary = 120 + 1050 * env[None, :] ** 0.9 + 170 * streak + 45 * streak2 + 14 * gnoise((H, W), rng, 9, 5.0)
    # drips: a few long thin runs
    drip = np.zeros((H, W))
    for i in range(7):
        x0 = rng.normal(W * 0.5, W * 0.16)
        L = rng.uniform(350, 1250)
        wd = rng.uniform(3, 8)
        wob = _smooth1d(H, rng, 120) * rng.uniform(4, 14)
        xc = x0 + wob
        prof = np.exp(-((X - xc[:, None]) / wd) ** 2)
        along = ss(L + 40, L - 20, Y[:, :1])
        bulb = 1 + 0.8 * np.exp(-((Y[:, :1] - (L - 14)) / 14) ** 2)
        drip = np.maximum(drip, prof * along * bulb * rng.uniform(0.5, 1.0))
    c = boundary - Y  # distance inside the stain (px), >0 inside
    soft = 55
    plume = ss(-soft * 0.4, soft, c)
    # tide lines: contours at several offsets; darkest right at the boundary
    rim = np.exp(-((c - 6) / 9) ** 2) * (c > -4)
    tide2 = np.exp(-((c - 95 - 25 * streak2) / 5) ** 2) * 0.55 * ss(-0.4, 0.6, streak2)
    tide3 = np.exp(-((c - 260 - 40 * streak) / 8) ** 2) * 0.45 * ss(-0.3, 0.7, streak)
    topdark = np.exp(-Y / 340) * 0.35
    body = plume * (0.26 + 0.14 * np.exp(-Y / 700)) * (0.86 + 0.08 * streak2 + 0.06 * fine_st) + topdark * plume
    a = np.clip(body + rim * 0.42 * plume.clip(0.2, 1) + tide2 + tide3 + drip * 0.55, 0, 0.88)
    sidew = ss(0, 0.10, xn) * ss(0, 0.10, 1 - xn)
    a *= sidew
    a *= ss(H, H - 40, Y)
    # mold specks near the top, gated by noise (clusters)
    gate = ss(0.3, 1.5, gnoise((H, W), rng, 22)) * ss(500, 20, Y)
    n = 900
    ys = rng.exponential(210, n).clip(2, H - 2)
    xs = rng.normal(W / 2, W * 0.2, n).clip(5, W - 5)
    mold = _specks((H, W), rng, n, 0.8, 3.6, ys, xs, mask=gate * (a > 0.2))
    mold = np.clip(mold + 0.4 * blur(mold, 2.5), 0, 1)
    brown = srgb2lin(rgb8(120, 86, 40)); dark = srgb2lin(rgb8(78, 52, 22)); light = srgb2lin(rgb8(150, 118, 64))
    t = np.clip(rim * 1.2 + tide2 + tide3 + drip * 0.4, 0, 1)[..., None]
    col = brown * (1 - t) + dark * t
    col = col * (1 - 0.5 * (c > 140)[..., None] * 0.0) + 0 * light
    mg = srgb2lin(rgb8(60, 62, 46))
    col = col * (1 - mold[..., None]) + mg * mold[..., None]
    a = np.clip(a + mold * 0.75 * (ss(0.05, 0.3, a)), 0, 0.92)
    a = np.where(mold > 0.02, np.maximum(a, mold * 0.8 * sidew), a)
    rgb = lin2srgb(col)
    save_rgba("decal_wall_waterdamage.png", rgb, a)
    return dict(max_alpha=float(a.max()), coverage_pct=round(100 * float((a > 0.1).mean()), 1))


# ---------------------------------------------------------------- WALL GRIME LOW (2048 x 512, bottom of wall = last row)
def build_grime_low(seed=6002):
    W, H = 2048, 512
    rng = np.random.default_rng(seed)
    Y, X = np.mgrid[0:H, 0:W].astype(float)
    up = (H - 1 - Y)  # height above the bottom edge (px)
    streak = gnoise((H, W), rng, 70, 10.0)
    blotch = gnoise((H, W), rng, 14, 30)
    scale = np.clip(62 + 42 * streak + 22 * blotch, 18, 200)
    g = np.exp(-up / scale)
    # vertical dirt runs
    run = np.zeros((H, W))
    for i in range(70):
        x0 = rng.uniform(0, W); L = rng.uniform(40, 230); wd = rng.uniform(1.5, 6)
        run = np.maximum(run, np.exp(-((X - x0) / wd) ** 2) * ss(L, L * 0.3, up) * rng.uniform(0.3, 0.8))
    # scuffs: short, thick, slightly diagonal smears near the bottom
    strokes = []
    for i in range(90):
        yy = H - 1 - abs(rng.normal(0, 70)) - 4
        x0 = rng.uniform(0, W)
        L = rng.uniform(25, 140)
        a = rng.normal(0.0, 0.10)
        strokes.append((x0, yy, x0 + L * np.cos(a), yy + L * np.sin(a), rng.choice([3, 5, 8, 12]), rng.uniform(0.15, 0.6)))
    scuff = blur(line_strokes((H, W), strokes, wrap_x=False), 3.0)
    grain = gnoise((H, W), rng, 1.2)
    a = np.clip(0.48 * g * (0.88 + 0.12 * grain) + 0.28 * run * ss(60, 0, up) * 0 + 0.18 * run + 0.30 * scuff * ss(170, 10, up), 0, 0.82)
    a *= ss(0, 0.02, X / W) * ss(0, 0.02, 1 - X / W)
    a *= ss(H, H - 40, 0.0 + Y) if False else 1.0
    a *= ss(-2, 22, up) * 0 + 1  # keep full strength at the very bottom
    c_hi = srgb2lin(rgb8(86, 72, 50)); c_lo = srgb2lin(rgb8(40, 33, 24))
    t = ss(0, 90, up)[..., None]
    col = c_lo * (1 - t) + c_hi * t
    col = col * (1 - 0.35 * scuff[..., None] * 0) * (1 + 0.10 * grain[..., None])
    save_rgba("decal_wall_grime_low.png", lin2srgb(col), a)
    return dict(max_alpha=float(a.max()))


# ---------------------------------------------------------------- FLOOR WET PATCH (1024 x 1024)
def build_wetpatch(seed=6003):
    N = 1024
    rng = np.random.default_rng(seed)
    Y, X = np.mgrid[0:N, 0:N].astype(float)
    wx = 70 * gnoise((N, N), rng, 70) + 28 * gnoise((N, N), rng, 22) + 8 * gnoise((N, N), rng, 6)
    wy = 70 * gnoise((N, N), rng, 70) + 28 * gnoise((N, N), rng, 22) + 8 * gnoise((N, N), rng, 6)
    ang = np.arctan2(Y - N / 2, X - N / 2)
    rad = np.hypot(X - N / 2 + wx, (Y - N / 2 + wy) * 1.12) / (0.40 * N)
    rad *= 1 + 0.10 * np.cos(3 * ang + 1.0) + 0.06 * np.cos(5 * ang + 2.0)
    core = ss(1.0, 0.45, rad)
    fibre = 0.85 + 0.15 * ss(-0.8, 1.2, gnoise((N, N), rng, 3.0))
    a = core * fibre
    a += 0.20 * np.exp(-((rad - 0.93) / 0.05) ** 2) * ss(1.05, 0.9, rad)  # darker damp rim
    a *= ss(1.0, 0.92, np.hypot(X - N / 2, Y - N / 2) / (0.5 * N))          # hard guarantee: zero at the borders
    a = np.clip(a * 0.62, 0, 0.7)
    wet = srgb2lin(rgb8(46, 34, 18)); edge = srgb2lin(rgb8(70, 52, 28))
    t = ss(0.5, 1.0, rad)[..., None]
    col = wet * (1 - t) + edge * t
    col = col * (1 + 0.12 * gnoise((N, N), rng, 2.0)[..., None])
    save_rgba("decal_floor_wetpatch.png", lin2srgb(col), a)
    return dict(max_alpha=float(a.max()))


# ---------------------------------------------------------------- CEILING STAIN (1024 x 1024)
def build_ceiling_stain(seed=6004):
    N = 1024
    rng = np.random.default_rng(seed)
    Y, X = np.mgrid[0:N, 0:N].astype(float)
    wx = 22 * gnoise((N, N), rng, 40) + 50 * gnoise((N, N), rng, 120)
    wy = 22 * gnoise((N, N), rng, 40) + 50 * gnoise((N, N), rng, 120)
    r = np.hypot(X + wx - N / 2, Y + wy - N / 2) / (0.34 * N)
    grain = gnoise((N, N), rng, 2.5)
    body = ss(1.0, 0.75, r) * 0.22 * (0.45 + 0.55 * ss(0.15, 0.85, r)) * (1 + 0.12 * grain)
    rim = np.exp(-((r - 0.96) / 0.035) ** 2) * ss(-1.2, 0.8, gnoise((N, N), rng, 30)) * (0.7 + 0.3 * gnoise((N, N), rng, 8))
    ring2 = np.exp(-((r - 0.68) / 0.03) ** 2) * 0.30 * ss(-0.4, 0.6, gnoise((N, N), rng, 40))
    outer = np.exp(-np.clip(r - 1.0, 0, None) / 0.12) * (r > 1.0) * 0.22
    a = np.clip(body + rim * 0.5 + ring2 + outer, 0, 0.85)
    a *= ss(1.0, 0.86, np.hypot(X - N / 2, Y - N / 2) / (0.5 * N))
    brown = srgb2lin(rgb8(122, 86, 40)); dark = srgb2lin(rgb8(78, 52, 22))
    t = np.clip(rim * 1.2 + ring2, 0, 1)[..., None]
    col = brown * (1 - t) + dark * t
    save_rgba("decal_ceiling_stain.png", lin2srgb(col), a)
    return dict(max_alpha=float(a.max()))


# ---------------------------------------------------------------- MOLD (1024 x 1024)
def build_mold(seed=6005):
    N = 1024
    rng = np.random.default_rng(seed)
    n_cl = 22
    cx = rng.uniform(90, N - 90, n_cl); cy = rng.uniform(90, N - 90, n_cl)
    cs = rng.uniform(25, 80, n_cl)
    ys, xs, rs = [], [], []
    for i in range(n_cl):
        k = int(rng.integers(60, 420) * (cs[i] / 60))
        ys += list(rng.normal(cy[i], cs[i], k)); xs += list(rng.normal(cx[i], cs[i], k))
        rs += list(np.abs(rng.normal(0.8, 0.9, k)) + 0.45)
    ys, xs, rs = np.clip(ys, 12, N - 12), np.clip(xs, 12, N - 12), np.array(rs)
    S = 4
    cvs = np.zeros((N * S, N * S), np.uint8)
    colimg = np.zeros((N * S, N * S, 3), np.uint8)
    base = np.array([58, 64, 50])
    for y, x, r in zip(ys, xs, rs):
        c = np.clip(base + rng.normal(0, 7, 3) + np.array([-6, 0, -8]) * rng.random(), 20, 110)
        cv2.circle(cvs, (int(x * S), int(y * S)), max(1, int(r * S)), int(rng.uniform(190, 255)), -1, cv2.LINE_AA)
        cv2.circle(colimg, (int(x * S), int(y * S)), max(1, int(r * S)), tuple(int(v) for v in c), -1, cv2.LINE_AA)
    a = cv2.resize(cvs, (N, N), interpolation=cv2.INTER_AREA).astype(float) / 255
    rgb = cv2.resize(colimg, (N, N), interpolation=cv2.INTER_AREA).astype(float) / 255
    cov = np.maximum(a, 1e-3)
    rgb = np.where(a[..., None] > 0.02, rgb / cov[..., None], base / 255.0)
    rgb = np.clip(rgb, 0, 1)
    halo = blur(a, 3.5) * 2.4
    alpha = np.clip(a * 0.92 + np.clip(halo, 0, 0.5) * 0.45, 0, 0.95)
    alpha *= ss(0, 14, np.minimum(np.minimum(*np.mgrid[0:N, 0:N]), np.minimum(N - 1 - np.mgrid[0:N, 0:N][0], N - 1 - np.mgrid[0:N, 0:N][1])).astype(float))
    halo_rgb = np.array([62, 66, 54]) / 255.0
    w = np.clip(a / np.maximum(alpha, 1e-3), 0, 1)[..., None]
    rgb = rgb * w + halo_rgb * (1 - w)
    save_rgba("decal_mold.png", rgb, alpha)
    return dict(clusters=n_cl, spots=int(len(rs)), max_alpha=float(alpha.max()))
