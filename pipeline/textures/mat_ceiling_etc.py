import numpy as np, cv2
from tex_common import *


# ---------------------------------------------------------------- CEILING TILE
def _tile_stain_mult(bev_w, rng, N):
    """Multiplicative brown water-stain colour field (linear light) for the tile."""
    Y, X = np.mgrid[0:N, 0:N].astype(float)
    cx, cy, R = 0.72 * N, 0.40 * N, 0.33 * N
    wx = 14 * gnoise((N, N), rng, 30) + 30 * gnoise((N, N), rng, 110)
    wy = 14 * gnoise((N, N), rng, 30) + 30 * gnoise((N, N), rng, 110)
    r = np.hypot(X + wx - cx, Y + wy - cy) / R
    grain = gnoise((N, N), rng, 2.2)
    body = ss(1.02, 0.80, r) * 0.30 * (1 + 0.15 * grain)                                  # lighter centre, gentle tint
    rim = np.exp(-((r - 0.97) / 0.045) ** 2) * (0.75 + 0.25 * gnoise((N, N), rng, 12))    # darker tide line
    outer = np.exp(-np.clip(r - 1.0, 0, None) / 0.10) * (r > 1.0) * 0.28                  # soft halo outside
    ring2 = np.exp(-((r - 0.70) / 0.025) ** 2) * 0.28 * ss(-0.5, 0.6, gnoise((N, N), rng, 40))
    s_body = np.clip(body + outer + ring2, 0, 0.85)
    tint = np.array([0.66, 0.44, 0.22])
    dark = np.array([0.46, 0.28, 0.12])
    m = np.ones((N, N, 3))
    m = m * (1 - s_body[..., None]) + tint * s_body[..., None]
    m = m * (1 - rim[..., None] * 0.8) + dark * (rim[..., None] * 0.8)
    d = np.minimum(np.minimum(X, N - 1 - X), np.minimum(Y, N - 1 - Y))
    keep = np.where(d < bev_w, 0.4, 1.0)[..., None]  # keep bevel mostly like the clean tile
    return 1 + (m - 1) * keep


def build_ceiling(seed=3003):
    N = 1024
    rng = np.random.default_rng(seed)
    Y, X = np.mgrid[0:N, 0:N].astype(float)
    d = np.minimum(np.minimum(X + 0.5, N - X - 0.5), np.minimum(Y + 0.5, N - Y - 0.5))
    bw = 10.0  # ~6 mm at 1707 px/m
    # worm-like fissures: thin contour lines of noise, broken up by a second mask
    fiss = np.zeros((N, N))
    for sig, thr, dens in ((2.6, 0.24, 0.3), (4.0, 0.20, 0.5)):
        n1 = gnoise((N, N), rng, sig * 1.0, sig * 1.7)
        n2 = gnoise((N, N), rng, 7)
        fiss = np.maximum(fiss, np.exp(-(n1 / thr) ** 2) * ss(0.3 + dens, 0.9 + dens, n2))
    fiss = blur(fiss, 0.5)
    pin = np.zeros((N, N))
    dens = 0.0035 * (0.4 + 1.6 * ss(-1, 1, gnoise((N, N), rng, 60)))
    pts = rng.random((N, N)) < dens
    pin[pts] = rng.uniform(0.5, 1.0, pts.sum())
    pin = np.clip(blur(pin, 0.8) * 6, 0, 1)
    grain = gnoise((N, N), rng, 1.6)
    grain2 = gnoise((N, N), rng, 6)
    hsurf = 0.10 * grain + 0.08 * grain2 - 1.1 * fiss - 1.6 * pin
    bevel = -np.clip(bw - d, 0, bw) * 0.85
    hgt = blur(bevel, 0.9, wrap=False) + hsurf
    nrm = normal_from_height(hgt, 1.0, wrap_x=False, wrap_y=False)

    base = srgb2lin(rgb8(222, 216, 196))
    lum = 1 + 0.035 * grain + 0.02 * grain2 + 0.012 * gnoise((N, N), rng, 70)
    lum *= 1 - 0.30 * fiss - 0.40 * pin
    bev = ss(bw + 1.5, bw - 2.5, d)
    lum *= 1 - 0.14 * bev - 0.12 * ss(2.5, 0.5, d)
    lin = base * lum[..., None]
    lin *= (1 - 0.05 * bev[..., None] * np.array([0.0, 0.4, 1.0]))
    interior = (d > bw + 2).astype(float)
    alb = match_mean_srgb(lin, (222, 216, 196), weights=interior)
    ratio = alb / np.maximum(lin2srgb(lin), 1e-6)
    stained_lin = lin * _tile_stain_mult(bw, rng, N)
    alb_st = np.clip(lin2srgb(stained_lin) * ratio, 0, 1)
    rough = np.clip(0.935 + 0.015 * grain + 0.02 * pin - 0.01 * bev, 0.90, 0.97)
    ao = np.clip(1 - 0.55 * fiss - 0.5 * pin - 0.25 * bev, 0, 1)
    save_rgb("ceiling_tile_albedo.png", alb)
    save_rgb("ceiling_tile_stained_albedo.png", alb_st)
    save_normal("ceiling_tile_normal.png", nrm)
    save_gray("ceiling_tile_roughness.png", rough)
    save_gray("ceiling_tile_ao.png", ao)
    return dict(mean_albedo_interior=(alb[interior > 0].mean(0) * 255).round(1).tolist(), bevel_px=bw)


# ---------------------------------------------------------------- TROFFER LENS
def _ellipse_layer(shape, items, ss_=4):
    h, w = shape
    c = np.zeros((h * ss_, w * ss_), np.uint8)
    for cx, cy, ax, ay, ang, v in items:
        cv2.ellipse(c, (int(cx * ss_), int(cy * ss_)), (max(1, int(ax * ss_)), max(1, int(ay * ss_))), ang, 0, 360, int(v * 255), -1, cv2.LINE_8)
    return cv2.resize(c, (w, h), interpolation=cv2.INTER_AREA).astype(float) / 255


def build_troffer(seed=4004):
    W, H = 512, 1024
    rng = np.random.default_rng(seed)
    Y, X = np.mgrid[0:H, 0:W].astype(float)
    pitch = 4.0   # 4 px = 4.7 mm at 853 px/m; exact integer pitch avoids aliasing/moire
    fr = 14.0     # plain frame border (px)
    u = ((X % pitch) / pitch) - 0.5
    v = ((Y % pitch) / pitch) - 0.5
    pyr = 1 - 2 * np.maximum(np.abs(u), np.abs(v))
    dEdge = np.minimum(np.minimum(X, W - 1 - X), np.minimum(Y, H - 1 - Y))
    prism_mask = ss(fr - 1, fr + 2, dEdge)
    hgt = blur(2.0 * pyr * prism_mask, 0.35, wrap=False)
    nrm = normal_from_height(hgt, 0.75, wrap_x=False, wrap_y=False)

    ex = (X - W / 2) / (W / 2)
    ey = (Y - H / 2) / (H / 2)
    rr = np.sqrt(ex ** 2 + ey ** 2)
    fall = 1 - 0.12 * (np.clip(rr, 0, 1.4) ** 2.2) - 0.05 * ss(fr + 6, fr - 6, dEdge)
    bands = 1 + 0.018 * np.cos(2 * np.pi * (X / W) * 2 + 0.6)
    low = 1 + 0.012 * gnoise((H, W), rng, 40)
    emis_l = fall * bands * low / 1.04
    items = []
    for _ in range(22):
        cy = 1024 - abs(rng.normal(0, 120)) - 25
        cx = rng.uniform(40, W - 40)
        L = rng.uniform(4.5, 9)
        Wd = L * rng.uniform(0.28, 0.45)
        items.append((cx, cy, L, Wd, rng.uniform(0, 180), rng.uniform(0.55, 0.85)))
    body = _ellipse_layer((H, W), items)
    wings = []
    for cx, cy, L, Wd, ang, vv in items:
        if rng.random() < 0.6:
            a = np.radians(ang + 90)
            for sgn in (-1, 1):
                wings.append((cx + sgn * Wd * 1.6 * np.cos(a), cy + sgn * Wd * 1.6 * np.sin(a), L * 0.9, Wd * 0.8, ang + sgn * 18, vv * 0.30))
    wing = _ellipse_layer((H, W), wings)
    legs = np.zeros((H, W), np.uint8)
    for cx, cy, L, Wd, ang, vv in items:
        a = np.radians(ang)
        for k in (-0.5, 0, 0.5):
            for sgn in (-1, 1):
                x0, y0 = cx + k * L * np.cos(a), cy + k * L * np.sin(a)
                x1 = x0 - sgn * (L * 0.8) * np.sin(a)
                y1 = y0 + sgn * (L * 0.8) * np.cos(a)
                cv2.line(legs, (int(x0 * 8), int(y0 * 8)), (int(x1 * 8), int(y1 * 8)), 150, 1, cv2.LINE_AA, 3)
    legs = legs.astype(float) / 255
    dust = np.zeros((H, W))
    ny = 260
    ys = (1024 - np.abs(rng.normal(0, 220, ny))).astype(int).clip(0, H - 1)
    xs = rng.integers(0, W, ny)
    np.add.at(dust, (ys, xs), rng.uniform(0.3, 1.0, ny))
    dust = np.clip(blur(dust, 0.9, wrap=False) * 5, 0, 1)
    end_dirt = ss(H - 150, H - 8, Y) * (0.55 + 0.45 * ss(-1, 1, gnoise((H, W), rng, 14))) * 0.10
    edge_dirt = ss(fr + 10, 0, dEdge) * 0.07
    occl = np.clip(body + wing + legs * 0.35 + dust * 0.30, 0, 0.9)
    emis_l = emis_l * (1 - occl) * (1 - end_dirt - edge_dirt)
    emis = np.stack([emis_l * 0.99, emis_l * 0.992, emis_l * 0.95], -1)
    alb_l = 0.86 * (1 - 0.35 * occl) * (1 - 0.6 * end_dirt - 0.5 * edge_dirt - 0.02 * (1 - prism_mask))
    alb = np.stack([alb_l, alb_l * 0.995, alb_l * 0.955], -1)
    save_rgb("troffer_lens_albedo.png", lin2srgb(alb * 0.93))
    save_normal("troffer_lens_normal.png", nrm)
    save_rgb("troffer_lens_emission.png", np.clip(emis, 0, 1) * 0.985)
    return dict(prism_pitch_px=pitch, prism_pitch_mm=round(1000 * 0.6 / W * pitch, 2), insects=len(items))


# ---------------------------------------------------------------- BASEBOARD
def build_baseboard(seed=5005):
    W, H = 1024, 128
    rng = np.random.default_rng(seed)
    Y, X = np.mgrid[0:H, 0:W].astype(float)
    y = np.arange(H, dtype=float)
    prof = 1.0 * ss(0, 4, y) * ss(14, 8, y)
    prof -= 0.9 * np.exp(-((y - 15.5) / 1.4) ** 2)
    prof -= 0.8 * np.exp(-((y - 113.0) / 1.3) ** 2)
    prof += 1.1 * ss(113, 120, y) * ss(128, 121, y)
    prof += 0.15 * (np.cos((y - 16) / 100 * np.pi) - 1) * ss(16, 18, y) * ss(113, 110, y)
    hgt = np.tile(prof[:, None] * 2.5, (1, W))
    grain = gnoise((H, W), rng, 0.8)
    mott = gnoise((H, W), rng, 5.0, 14)
    hgt = hgt + 0.18 * grain + 0.35 * gnoise((H, W), rng, 1.2, 6)

    sc_dark, sc_light = [], []
    for i in range(55):
        yy = H * rng.beta(1.6, 1.3)
        x0 = rng.uniform(0, W)
        L = rng.uniform(10, 70)
        a = rng.normal(0, 0.10)
        x1, y1 = x0 + L * np.cos(a), yy + L * np.sin(a)
        (sc_dark if rng.random() < 0.6 else sc_light).append((x0, yy, x1, y1, rng.choice([1, 1, 1, 2]), rng.uniform(0.3, 0.8)))
    for i in range(18):
        x0 = rng.uniform(0, W)
        y0 = rng.uniform(40, 115)
        sc_dark.append((x0, y0, x0 + rng.normal(0, 3), y0 + rng.uniform(8, 30), rng.choice([2, 3, 4]), rng.uniform(0.2, 0.6)))
    dark = blur(line_strokes((H, W), sc_dark), 0.7)
    light = blur(line_strokes((H, W), sc_light), 0.6)
    dirt = ss(40, 126, Y) ** 1.3
    dirt = np.clip(dirt * (0.7 + 0.5 * ss(-1, 1, gnoise((H, W), rng, 6, 30))), 0, 1)

    base = srgb2lin(rgb8(122, 100, 72))
    lum = (1 + 0.04 * grain + 0.06 * mott) * (1 - 0.38 * dirt - 0.22 * dark + 0.14 * light)
    lum *= 1 + 0.12 * np.exp(-((Y - 2) / 2.5) ** 2)
    lum *= 1 - 0.30 * np.exp(-((Y - 15.5) / 1.8) ** 2) - 0.25 * np.exp(-((Y - 113) / 1.8) ** 2)
    lin = base * lum[..., None] * (1 + 0.03 * mott[..., None] * np.array([1, 0.2, -1]))
    alb = match_mean_srgb(lin, (122, 100, 72))
    rough = np.clip(0.60 + 0.03 * grain + 0.08 * dirt + 0.04 * dark - 0.12 * light - 0.06 * np.exp(-((Y - 2) / 3) ** 2), 0.5, 0.7)
    hgt = hgt - 0.3 * light - 0.1 * dark
    nrm = normal_from_height(hgt, 0.9, wrap_y=False, wrap_x=True)
    save_rgb("baseboard_albedo.png", alb)
    save_normal("baseboard_normal.png", nrm)
    save_gray("baseboard_roughness.png", rough)
    return dict(mean_albedo=(alb.mean((0, 1)) * 255).round(1).tolist())
