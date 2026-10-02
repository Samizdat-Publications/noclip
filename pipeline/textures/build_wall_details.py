"""Wall detail decals for Level 0 (S03): poster ghosts, tape, scuffs, holes, desk ghost, tide line,
crayon trail, outlet grime, damp bloom. Procedural only (numpy, PIL, cv2). Seeded and reproducible.
Run: python pipeline/textures/build_wall_details.py
Writes RGBA PNGs (+ _normal, OpenGL) to game/assets/textures/level0/walldetail/, the manifest
pipeline/manifests/wall_details_level0.json, the table game/data/wall_details.json, and previews."""
import os, sys, json
import numpy as np, cv2
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(__file__))
import tex_common as tc
from tex_common import ss, gnoise, blur, normal_from_height

DETAIL = os.path.join(tc.ROOT, "game", "assets", "textures", "level0", "walldetail")
os.makedirs(DETAIL, exist_ok=True)
WALLPAPER = os.path.join(tc.OUT, "wallpaper_albedo.png")
tc.OUT = DETAIL
MANIFEST = os.path.join(tc.ROOT, "pipeline", "manifests", "wall_details_level0.json")
TABLE = os.path.join(tc.ROOT, "game", "data", "wall_details.json")
PREV = tc.PREV
manifest = {}
table = {}


def C(r, g, b):
    return np.array([r, g, b], float) / 255.0


class Cv:
    """Canvas in meters, top-left origin, Y grows downward."""
    def __init__(self, wm, hm, long_px=1024, ppm=None):
        self.ppm = ppm if ppm else long_px / max(wm, hm)
        self.W = int(round(wm * self.ppm)); self.H = int(round(hm * self.ppm))
        self.wm, self.hm = self.W / self.ppm, self.H / self.ppm
        y, x = np.mgrid[0:self.H, 0:self.W].astype(float)
        self.X = (x + 0.5) / self.ppm; self.Y = (y + 0.5) / self.ppm
        self.shape = (self.H, self.W)
        self.rgb = np.zeros((self.H, self.W, 3)); self.a = np.zeros(self.shape)
        self.h = np.zeros(self.shape)  # height in meters (for normals)

    def n(self, rng, sm, sxm=None):  # periodic gaussian noise, sigma in meters
        return gnoise(self.shape, rng, max(sm * self.ppm, 0.4), None if sxm is None else max(sxm * self.ppm, 0.4))

    def over(self, col, a):
        a = np.clip(a, 0, 1)
        col = np.asarray(col, float)
        if col.ndim == 1:
            col = col[None, None, :]
        oa = a + self.a * (1 - a)
        w = np.where(oa > 1e-6, 1.0 / np.maximum(oa, 1e-6), 0)
        self.rgb = (col * a[..., None] + self.rgb * (self.a * (1 - a))[..., None]) * w[..., None] \
            + self.rgb * (oa <= 1e-6)[..., None]
        self.a = oa

    def fill_empty(self, col):
        self.rgb[self.a < 1e-4] = col

    def save(self, name, normal=None, gain=1.0):
        tc.save_rgba(name + ".png", np.clip(self.rgb, 0, 1), self.a)
        if normal:
            nrm = normal_from_height(self.h * self.ppm * gain, 1.0, False, False)
            tc.save_normal(name + "_normal.png", nrm)
        return self.W, self.H


def sdf_box(X, Y, cx, cy, hw, hh):
    dx = np.abs(X - cx) - hw; dy = np.abs(Y - cy) - hh
    return np.hypot(np.maximum(dx, 0), np.maximum(dy, 0)) + np.minimum(np.maximum(dx, dy), 0)


def sdf_rbox(X, Y, cx, cy, hw, hh, ang):
    c, s = np.cos(ang), np.sin(ang)
    u = (X - cx) * c + (Y - cy) * s; v = -(X - cx) * s + (Y - cy) * c
    return sdf_box(u, v, 0, 0, hw, hh), u, v


def per1d(n, rng, sigma_px):
    v = rng.standard_normal(n)
    k = np.fft.rfft(v) * np.exp(-0.5 * (2 * np.pi * np.fft.rfftfreq(n) * sigma_px) ** 2)
    v = np.fft.irfft(k, n)
    return (v - v.mean()) / (v.std() + 1e-9)


def pin_hole(cv, x, y, r, rng, rust=True):
    rr = np.hypot(cv.X - x, cv.Y - y)
    cv.over(C(70, 58, 40), 0.55 * np.exp(-(rr / (r * 2.2)) ** 2))
    cv.over(C(28, 22, 16), 0.85 * ss(r * 1.1, r * 0.5, rr))
    cv.h -= 0.0008 * np.exp(-(rr / r) ** 2)
    cv.h += 0.00025 * np.exp(-((rr - r * 1.7) / (r * 0.6)) ** 2)  # raised crumb rim
    if rust:
        sx = np.exp(-((cv.X - x) / (r * 0.7)) ** 2) * ss(-r, r * 0.5, cv.Y - y) * ss(r * 9, 0, cv.Y - y)
        cv.over(C(150, 98, 52), 0.22 * sx)


# ------------------------------------------------------------------ 1. poster ghosts
def ghost(name, pw, ph, seed, pins, board=False, tape_corners=(1, 1, 1, 1)):
    rng = np.random.default_rng(seed)
    m = 0.15
    cv = Cv(pw + 2 * m, ph + 2 * m)
    cx, cy = cv.wm / 2, cv.hm / 2
    d = sdf_box(cv.X, cv.Y, cx, cy, pw / 2, ph / 2)
    d = d + 0.0004 * cv.n(rng, 0.004) + 0.0014 * cv.n(rng, 0.05)
    inside = ss(0.0030, -0.0030, d)
    mott = 0.80 + 0.20 * ss(-1.5, 1.5, cv.n(rng, 0.03) * 0.7 + cv.n(rng, 0.006) * 0.3)
    # outside halo: dust collects around the paper, heavier along the top edge, runs down in streaks
    out = ss(-0.001, 0.0025, d)
    top = 1 + 0.9 * ss(cy - ph * 0.05, cy - ph / 2, cv.Y)
    streak = 0.5 + 0.5 * ss(-1.2, 1.2, cv.n(rng, 0.05, 0.004))
    dpos = np.maximum(d, 0)
    halo = np.exp(-dpos / 0.022) * out * top * streak
    tight = np.exp(-dpos / 0.0045) * out
    grime = C(112, 92, 58)
    cv.over(grime, np.clip(0.30 * halo + 0.16 * tight, 0, 0.45) * ss(0.15, 0.10, dpos))
    # the protected rectangle: cleaner, less yellowed paper (cream at partial alpha)
    cv.over(C(242, 233, 200), 0.27 * inside * mott)
    cv.over(C(128, 106, 66), 0.10 * np.exp(-((d - 0.0015) / 0.0016) ** 2) * (d > -0.001))
    # tape residue at the corners
    corners = [(cx - pw / 2, cy - ph / 2), (cx + pw / 2, cy - ph / 2), (cx - pw / 2, cy + ph / 2), (cx + pw / 2, cy + ph / 2)]
    for (px, py), on in zip(corners, tape_corners):
        if not on:
            continue
        ang = rng.uniform(-0.5, 0.5) + (np.pi / 4 if rng.random() < 0.5 else 0)
        hw, hh = rng.uniform(0.016, 0.024), rng.uniform(0.009, 0.014)
        dd, u, v = sdf_rbox(cv.X, cv.Y, px + rng.normal(0, 0.004), py + rng.normal(0, 0.004), hw, hh, ang)
        dd = dd + 0.0025 * cv.n(rng, 0.004) + 0.001 * cv.n(rng, 0.0012)
        res = ss(0.001, -0.002, dd) * (0.6 + 0.4 * ss(-1, 1, cv.n(rng, 0.004)))
        cv.over(C(206, 172, 84), 0.42 * res)
        cv.over(C(150, 118, 54), 0.28 * np.exp(-(dd / 0.0015) ** 2) * ss(0.2, 1.0, cv.n(rng, 0.004)))
        cv.h += 0.00018 * res
    # nail / pin / screw holes
    for (fx, fy, r) in pins:
        x, y = cx + fx * pw / 2, cy + fy * ph / 2
        pin_hole(cv, x, y, r, rng, rust=(r < 0.004 or board))
        if board:  # dust ring around a screw head that once sat here
            rr = np.hypot(cv.X - x, cv.Y - y)
            cv.over(C(100, 86, 62), 0.28 * ss(0.017, 0.010, rr) * ss(0.004, 0.009, rr) * (0.6 + 0.4 * ss(-1, 1, cv.n(rng, 0.004))))
    info = {}
    if board:  # torn paper fragment under the top-left screw
        fx, fy, r = pins[0]
        sx, sy = cx + fx * pw / 2, cy + fy * ph / 2
        pts = np.array([[0.0, 0.0], [0.034, 0.002], [0.046, 0.020], [0.040, 0.047], [0.027, 0.064], [0.018, 0.055],
                        [0.011, 0.070], [0.0, 0.050], [-0.004, 0.026]])
        pts = pts + rng.normal(0, 0.0022, pts.shape) + np.array([sx - 0.006, sy + 0.002])
        s4 = 4
        canvas = np.zeros((cv.H * s4, cv.W * s4), np.uint8)
        cv2.fillPoly(canvas, [(pts * cv.ppm * s4).astype(np.int32)], 255, cv2.LINE_AA)
        pm = cv2.resize(canvas, (cv.W, cv.H), interpolation=cv2.INTER_AREA).astype(float) / 255
        edge = pm - blur(pm, 0.0012 * cv.ppm, False)
        fib = ss(-0.5, 0.6, cv.n(rng, 0.0012) * 0.7 + 0.5)
        pm2 = np.clip(pm * (1 - 0.7 * (1 - ss(0.7, 0.2, blur(pm, 0.002 * cv.ppm, False))) * (1 - fib)), 0, 1)
        shadow = blur(np.roll(np.roll(pm, int(0.0015 * cv.ppm), 0), int(0.0012 * cv.ppm), 1), 0.0022 * cv.ppm, False)
        cv.over(C(40, 30, 20), 0.32 * shadow * (1 - pm))
        cv.over(C(226, 220, 200), 0.96 * pm2)
        for k in range(3):
            yy = sy + 0.014 + k * 0.014
            bar = ss(0.0012, 0, np.abs(cv.Y - yy)) * ss(sx - 0.008, sx - 0.004, cv.X) * ss(sx + 0.026 - 0.005 * k, sx + 0.020 - 0.005 * k, cv.X)
            cv.over(C(92, 92, 96), 0.55 * bar * pm2)
        cv.over(C(190, 160, 96), 0.35 * pm2 * ss(0.4, 0.95, 1 - blur(pm, 0.003 * cv.ppm, False)))
        cv.h += 0.0006 * pm2 + 0.0002 * edge
        pin_hole(cv, sx, sy, 0.0055, rng, rust=True)
        info["fragment"] = True
    cv.fill_empty(grime)
    W, H = cv.save(name, normal=True, gain=1.6)
    manifest[name] = dict(seed=seed, size_m=[round(cv.wm, 3), round(cv.hm, 3)], paper_m=[pw, ph], px=[W, H], pins=len(pins), board=board, **info)
    table[name] = dict(tex="walldetail/" + name, w=round(cv.wm, 3), h=round(cv.hm, 3), y=[1.3, 1.6], normal=True, tile=False, kind="ghost")


# ------------------------------------------------------------------ 2. tape scraps
def tape_piece(cv, rng, cx, cy, length, width, ang, curl=False):
    d, u, v = sdf_rbox(cv.X, cv.Y, cx, cy, length / 2, width / 2, ang)
    jag = 0.0045 * cv.n(rng, 0.0016, 0.0016) + 0.002 * cv.n(rng, 0.0005)  # torn fibrous ends
    ue = np.abs(u) - length / 2 + jag
    ve = np.abs(v) - width / 2 + 0.0004 * cv.n(rng, 0.002)
    dd = np.maximum(ue, ve)
    fray = ss(0.0012, -0.0012, dd)
    fray_fib = ss(-0.9, 0.5, cv.n(rng, 0.0006, 0.004) + 0.4 * cv.n(rng, 0.0003))
    mask = fray * np.where(ue > -0.0035, 0.55 + 0.45 * fray_fib, 1.0)
    fib = 0.5 + 0.5 * np.tanh(cv.n(rng, 0.0004, 0.02))  # fibres along the tape
    cv.over(C(214, 192, 128), mask * (0.50 + 0.18 * fib))
    edge = ss(-0.0018, 0.0, ve) * mask
    dirt = ss(0.2, 1.4, cv.n(rng, 0.004)) * mask
    cv.over(C(168, 134, 66), 0.35 * edge)
    cv.over(C(98, 82, 58), 0.35 * dirt)
    hl = ss(0.0, -0.0014, ve) * ss(-0.003, -0.0014, ve) * mask
    cv.over(C(244, 232, 190), 0.30 * hl)
    if curl:  # curled end: a shaded wedge with a bright fold line
        cend = ss(-0.016, -0.002, ue) * (u > 0) * mask
        cv.over(C(120, 94, 50), 0.38 * cend)
        cv.over(C(250, 238, 200), 0.35 * np.exp(-((ue + 0.018) / 0.0016) ** 2) * mask * (u > 0))
    cv.h += 0.00022 * mask * (0.6 + 0.4 * ss(-0.003, 0, -ve))


def tape_scraps():
    rng = np.random.default_rng(3101)
    for i, (size, items) in enumerate([
        (0.14, [(0.0, 0.0, 0.115, 0.024, 0.18, False)]),
        (0.15, [(-0.005, -0.012, 0.095, 0.022, 0.30, True), (0.006, 0.020, 0.085, 0.022, -0.62, False)]),
        (0.095, [(0.0, 0.0, 0.07, 0.021, -0.9, False)]),
    ], start=1):
        name = "tape_scraps_%d" % i
        cv = Cv(size, size)
        for (ox, oy, L, Wd, ang, curl) in items:
            tape_piece(cv, rng, cv.wm / 2 + ox, cv.hm / 2 + oy, L, Wd, ang, curl)
        cv.fill_empty(C(214, 192, 128))
        W, H = cv.save(name, normal=True, gain=1.2)
        manifest[name] = dict(seed=3101, size_m=[round(cv.wm, 3), round(cv.hm, 3)], pieces=len(items), px=[W, H])
        table[name] = dict(tex="walldetail/" + name, w=round(cv.wm, 3), h=round(cv.hm, 3), y=[1.2, 1.9], normal=True, tile=False, kind="tape")


# ------------------------------------------------------------------ 3. scuffs
def scuff(name, wm, hm, seed, strokes, col, strength, dots=()):
    rng = np.random.default_rng(seed)
    cv = Cv(wm, hm)
    s4 = 4
    canvas = np.zeros((cv.H * s4, cv.W * s4), np.float32)
    for (x0, y0, x1, y1, bow, thick, val) in strokes:
        n = 64
        t = np.linspace(0, 1, n)
        xs = x0 + (x1 - x0) * t
        ys = y0 + (y1 - y0) * t + bow * (1 - (2 * t - 1) ** 2)
        for k in range(n - 1):
            env = np.sin(np.pi * ((t[k] + t[k + 1]) / 2)) ** 0.5
            th = max(1, int(thick * (0.55 + 0.45 * env) * cv.ppm * s4))
            cv2.line(canvas, (int(xs[k] * cv.ppm * s4), int(ys[k] * cv.ppm * s4)),
                     (int(xs[k + 1] * cv.ppm * s4), int(ys[k + 1] * cv.ppm * s4)), float(val * env ** 0.7), th, cv2.LINE_AA)
    st = cv2.resize(canvas, (cv.W, cv.H), interpolation=cv2.INTER_AREA).astype(float)
    st = np.clip(blur(st, 0.0012 * cv.ppm, False) * 1.4, 0, 1)
    grain = ss(-0.9, 0.7, cv.n(rng, 0.0012, 0.05) * 0.8 + cv.n(rng, 0.0008) * 0.5)
    skip = ss(-0.2, 0.6, cv.n(rng, 0.004, 0.03))
    alpha = np.clip(st * grain * (0.35 + 0.65 * skip) * strength, 0, 0.7)
    cv.over(col, alpha)
    smear = blur(st, 0.006 * cv.ppm, False) * ss(-0.7, 0.8, cv.n(rng, 0.01, 0.06))
    cv.over(np.clip(col * 1.5, 0, 1), np.clip(smear * strength * 0.35, 0, 0.3))
    for (x, y, r) in dots:
        rr = np.hypot(cv.X - x, (cv.Y - y) * 1.3) + 0.002 * cv.n(rng, 0.003)
        cv.over(col, strength * 0.9 * ss(r, r * 0.3, rr) * (0.7 + 0.3 * ss(-1, 1, cv.n(rng, 0.002))))
    cv.fill_empty(col)
    W, H = cv.save(name, normal=False)
    manifest[name] = dict(seed=seed, size_m=[round(cv.wm, 3), round(cv.hm, 3)], px=[W, H], strokes=len(strokes), strength=strength)
    table[name] = dict(tex="walldetail/" + name, w=round(cv.wm, 3), h=round(cv.hm, 3), y=[0.1, 0.5], normal=False, tile=False, kind="scuff")


def scuffs():
    rubber = C(42, 40, 38); grey = C(100, 96, 90)
    scuff("scuffs_1", 1.2, 0.15, 3201, [
        (0.05, 0.05, 1.10, 0.04, 0.01, 0.006, 0.9), (0.15, 0.075, 0.95, 0.07, 0.008, 0.009, 1.0),
        (0.30, 0.095, 1.15, 0.10, 0.006, 0.005, 0.8), (0.10, 0.115, 0.70, 0.12, 0.004, 0.012, 0.9),
        (0.55, 0.06, 1.05, 0.065, 0.01, 0.004, 0.7)], rubber, 0.62)
    scuff("scuffs_2", 0.8, 0.18, 3202, [
        (0.04, 0.15, 0.76, 0.04, -0.07, 0.007, 1.0), (0.10, 0.16, 0.70, 0.07, -0.06, 0.010, 0.9),
        (0.20, 0.165, 0.65, 0.10, -0.045, 0.005, 0.8)], grey, 0.75, dots=[(0.62, 0.12, 0.006)])
    scuff("scuffs_3", 0.5, 0.15, 3203, [
        (0.04, 0.10, 0.46, 0.05, -0.012, 0.016, 1.0), (0.08, 0.12, 0.40, 0.085, -0.008, 0.010, 0.9)],
        rubber, 0.75, dots=[(0.40, 0.04, 0.005), (0.05, 0.12, 0.004), (0.45, 0.07, 0.003)])
    scuff("scuffs_4", 1.0, 0.2, 3204, [
        (0.05, 0.07, 0.95, 0.04, 0.012, 0.006, 0.9), (0.12, 0.10, 0.85, 0.07, 0.01, 0.009, 1.0),
        (0.45, 0.17, 0.62, 0.03, -0.015, 0.006, 0.8), (0.20, 0.14, 0.50, 0.16, 0.0, 0.004, 0.6)],
        grey, 0.68, dots=[(0.82, 0.045, 0.006), (0.86, 0.075, 0.004)])


# ------------------------------------------------------------------ 4. holes
def torn_hole(name, size, seed, r0, flaps, depth, crumbs):
    rng = np.random.default_rng(seed)
    cv = Cv(size, size)
    cx = cy = cv.wm / 2
    dx, dy = cv.X - cx, cv.Y - cy
    r = np.hypot(dx, dy); th = np.arctan2(dy, dx)
    k = np.arange(1, 9)
    ph = rng.uniform(0, 2 * np.pi, k.size); am = rng.normal(0, 1, k.size) / k ** 0.9
    ang_noise = sum(am[i] * np.sin(k[i] * th + ph[i]) for i in range(k.size))
    ang_noise /= (np.std(ang_noise) + 1e-9)
    ph2 = rng.uniform(0, 2 * np.pi, 8)
    ang_f = sum(np.sin((20 + 3 * i) * th + ph2[i]) for i in range(8)) / 3
    R = r0 * (1 + 0.20 * ang_noise + 0.02 * ang_f)
    rn = r / R  # 1 at the hole edge
    cv.over(C(70, 58, 40), 0.30 * np.exp(-((rn - 0.9) / 1.2) ** 2) * ss(2.6, 0.6, rn))
    for _ in range(6):  # cracks radiating
        a = rng.uniform(0, 2 * np.pi); L = rng.uniform(1.4, 2.4)
        t = np.clip(((dx * np.cos(a) + dy * np.sin(a)) / (R * L)), 0, 1)
        perp = (-dx * np.sin(a) + dy * np.cos(a)) + 0.004 * cv.n(rng, 0.01) * (size / 0.18)
        crack = np.exp(-(perp / 0.0012) ** 2) * ss(1.0, 0.1, t) * ss(0.0, 0.4, t) * ss(0.2, 1.1, rn)
        cv.over(C(48, 40, 30), 0.32 * crack)
    ring = ss(1.9, 1.0, rn) * ss(0.7, 1.0, rn)  # crushed paper ring
    fibrous = ss(-1.0, 0.7, cv.n(rng, 0.0015) + 0.5 * cv.n(rng, 0.0006))
    cv.over(C(206, 196, 168), 0.55 * ring * (0.5 + 0.5 * fibrous))
    cv.h += 0.0008 * ring * fibrous - 0.0035 * ss(1.9, 0.9, rn)
    paper = C(196, 176, 108)
    for (a0, spread, ln) in flaps:  # flaps of torn wallpaper
        da = np.angle(np.exp(1j * (th - a0)))
        tip = ln * R * (1 - (np.abs(da) / spread) ** 1.4)
        wedge = (np.abs(da) < spread) * ss(1.0, 1.1, rn) * ss(0.0, -0.05, r - R - tip)
        wedge = wedge * ss(0.0, 0.08, 1 - np.abs(da) / spread)
        sh = blur(wedge, 0.0035 * cv.ppm, False)
        cv.over(C(25, 20, 14), 0.5 * sh * (1 - wedge))
        cv.over(paper[None, None, :] * (0.82 + 0.18 * ss(1.0, 1.8, rn))[..., None], 0.97 * wedge)
        cv.h += 0.0020 * wedge * ss(1.0, 2.0, rn)
    inner = ss(1.03, 0.92, rn)  # dark gypsum core
    cv.over(C(92, 86, 74)[None, None, :] * (0.55 + 0.45 * ss(-1, 1, cv.n(rng, 0.002)))[..., None], inner)
    cv.over(C(30, 26, 22), 0.93 * ss(0.78, 0.15, rn))
    rim = np.exp(-((rn - 0.97) / 0.07) ** 2)
    cv.over(C(226, 218, 190), 0.55 * rim * (0.4 + 0.6 * fibrous))  # chalky broken edge
    cv.h -= depth * ss(1.05, 0.0, rn)
    for _ in range(crumbs):  # plaster crumbs below the hole
        x = cx + rng.normal(0, r0 * 0.7); y = cy + r0 * rng.uniform(1.1, 2.3)
        rr = np.hypot(cv.X - x, cv.Y - y) + 0.0008 * cv.n(rng, 0.001)
        cv.over(C(214, 206, 184), 0.65 * ss(0.0035, 0.0012, rr))
    cv.fill_empty(C(92, 86, 74))
    W, H = cv.save(name, normal=True, gain=1.7)
    manifest[name] = dict(seed=seed, size_m=[round(cv.wm, 3), round(cv.hm, 3)], px=[W, H], hole_radius_m=r0)


def holes():
    torn_hole("hole_knob", 0.18, 3301, 0.034, [(-1.2, 0.5, 0.55), (0.35, 0.45, 0.50), (2.5, 0.42, 0.40), (1.7, 0.30, 0.35)], 0.020, 6)
    table["hole_knob"] = dict(tex="walldetail/hole_knob", w=0.18, h=0.18, y=[0.9, 1.05], normal=True, tile=False, kind="damage")
    torn_hole("hole_punch", 0.12, 3302, 0.017, [(-0.6, 0.40, 0.45), (2.3, 0.35, 0.40)], 0.014, 4)
    table["hole_punch"] = dict(tex="walldetail/hole_punch", w=0.12, h=0.12, y=[0.6, 1.4], normal=True, tile=False, kind="damage")


# ------------------------------------------------------------------ 5. desk ghost
def desk_ghost():
    name = "desk_ghost"
    rng = np.random.default_rng(3401)
    cv = Cv(1.6, 0.8)
    line = 0.24 + 0.003 * cv.n(rng, 0.15) + 0.0012 * cv.n(rng, 0.01)
    below = ss(-0.0015, 0.0015, cv.Y - line)
    above = ss(0.0015, -0.0015, cv.Y - line)
    sidew = ss(0.0, 0.05, 0.76 - np.abs(cv.X - 0.8) + 0.02 * cv.n(rng, 0.05))
    fade_bot = ss(cv.hm, cv.hm - 0.12, cv.Y)
    mott = 0.80 + 0.20 * ss(-1.5, 1.5, cv.n(rng, 0.05) * 0.6 + cv.n(rng, 0.01) * 0.4)
    gl = np.exp(-np.maximum(line - cv.Y, 0) / 0.016) * above * sidew  # grime above the desk line
    gl *= 0.6 + 0.4 * ss(-1, 1.4, cv.n(rng, 0.02, 0.2))
    cv.over(C(104, 86, 54), np.clip(0.24 * gl, 0, 0.4))
    cv.over(C(98, 80, 50), 0.16 * np.exp(-((cv.Y - line - 0.004) / 0.004) ** 2) * sidew * (cv.Y > line - 0.002) * ss(-1, 0.8, cv.n(rng, 0.03, 0.2)))
    cv.over(C(240, 230, 196), 0.22 * below * sidew * mott * fade_bot)  # lighter, less dirty paper under the desk
    for x0 in (0.52, 1.08):  # chair-back scuff dots
        xx = x0 + rng.normal(0, 0.01); yy = 0.47 + rng.normal(0, 0.01)
        rr = np.hypot((cv.X - xx) / 1.5, cv.Y - yy) + 0.004 * cv.n(rng, 0.008)
        cv.over(C(70, 62, 52), 0.32 * ss(0.032, 0.006, rr) * (0.6 + 0.4 * ss(-1, 1, cv.n(rng, 0.004))))
        cv.over(C(40, 36, 32), 0.30 * ss(0.012, 0.002, rr) * ss(-1, 0.8, cv.n(rng, 0.003)))
    cv.fill_empty(C(104, 86, 54))
    W, H = cv.save(name, normal=False)
    manifest[name] = dict(seed=3401, size_m=[1.6, 0.8], px=[W, H], desk_line_from_top_m=0.24,
                          note="at the default center y=0.55 the line sits near 0.71 m above floor")
    table[name] = dict(tex="walldetail/" + name, w=1.6, h=0.8, y=[0.55, 0.55], normal=False, tile=False, kind="ghost")


# ------------------------------------------------------------------ 6. water line (tileable in x)
def water_line():
    name = "water_line"
    rng = np.random.default_rng(3501)
    cv = Cv(2.4, 0.5, long_px=2048)
    W = cv.W
    line = (0.15 + 0.012 * per1d(W, rng, 0.08 * cv.ppm)[None, :] + 0.004 * per1d(W, rng, 0.012 * cv.ppm)[None, :]
            + 0.0012 * per1d(W, rng, 0.002 * cv.ppm)[None, :])
    dd = cv.Y - line  # >0 below the line
    streak = cv.n(rng, 0.25, 0.006)
    streak2 = cv.n(rng, 0.08, 0.003)
    fadebot = ss(0.49, 0.18, cv.Y + 0.05 * streak)
    band = ss(-0.0015, 0.004, dd) * fadebot * (0.55 + 0.12 * ss(-1.2, 1.2, streak) + 0.15 * ss(-1, 1, streak2))
    nearline = np.exp(-np.maximum(dd, 0) / 0.06) * ss(-0.0015, 0.003, dd)
    rim = np.exp(-((dd - 0.0015) / 0.0045) ** 2) * (0.6 + 0.4 * ss(-1, 1, cv.n(rng, 0.01, 0.05)))
    rim2 = np.exp(-((dd + 0.014) / 0.003) ** 2) * ss(0.0, 1.0, cv.n(rng, 0.02, 0.1)) * 0.5
    above = np.exp(-np.maximum(-dd, 0) / 0.012) * ss(0.002, -0.001, dd) * 0.5
    cv.over(C(142, 112, 64), 0.15 * band)
    cv.over(C(120, 90, 48), 0.20 * nearline * band)
    cv.over(C(112, 82, 40), np.clip(0.44 * rim, 0, 0.55))
    cv.over(C(126, 98, 56), 0.20 * rim2 + 0.10 * above)
    for _ in range(18):  # drips (wrap in x)
        x0 = rng.uniform(0, 2.4); Lm = rng.uniform(0.04, 0.26); wd = rng.uniform(0.0025, 0.006)
        dxw = np.abs(cv.X - x0); dxw = np.minimum(dxw, 2.4 - dxw)
        cv.over(C(116, 86, 44), 0.14 * np.exp(-(dxw / (wd * 1.6)) ** 2) * ss(Lm + 0.01, Lm - 0.03, dd) * ss(-0.002, 0.01, dd))
    fl = ss(1.0, 1.9, cv.n(rng, 0.0015)) * np.exp(-(dd / 0.015) ** 2)  # salt flecks
    cv.over(C(222, 214, 184), 0.35 * fl)
    cv.fill_empty(C(120, 90, 48))
    Wp, Hp = cv.save(name, normal=False)
    manifest[name] = dict(seed=3501, size_m=[2.4, 0.5], px=[Wp, Hp], tileable_x=True, tide_line_from_top_m=0.15, note="2048 px wide")
    table[name] = dict(tex="walldetail/" + name, w=2.4, h=0.5, y=[0.3, 0.3], normal=False, tile=True, kind="stain")


# ------------------------------------------------------------------ 7. crayon trail (tileable in x)
def crayon_trail():
    name = "crayon_trail"
    rng = np.random.default_rng(3601)
    cv = Cv(2.4, 0.06, long_px=4096)
    W, H = cv.W, cv.H
    cy = (H / 2 + 0.0085 * cv.ppm * per1d(W, rng, 0.12 * cv.ppm)[None, :] * 0.5
          + 0.0025 * cv.ppm * per1d(W, rng, 0.02 * cv.ppm)[None, :] * 0.5)
    wid = (0.0034 + 0.0009 * per1d(W, rng, 0.05 * cv.ppm)[None, :]) * cv.ppm
    press = ss(-1.4, 0.9, per1d(W, rng, 0.1 * cv.ppm))[None, :]
    yy = np.arange(H)[:, None] + 0.5
    prof = ss(1.0, 0.45, np.abs(yy - cy) / wid)
    core = ss(1.0, 0.15, np.abs(yy - cy) / wid)
    tooth = cv.n(rng, 0.0005, 0.0012)
    tooth2 = cv.n(rng, 0.0003)
    grain = ss(-1.0, 0.8, tooth * 0.7 + tooth2 * 0.5)
    alpha = prof * (0.30 + 0.50 * core) * grain * (0.35 + 0.65 * press)
    brk = np.ones(W)
    xs = np.arange(W)
    for _ in range(11):  # breaks where the wallpaper texture skipped
        x0 = rng.uniform(0, W); ln = rng.uniform(0.008, 0.045) * cv.ppm
        dxw = np.abs(xs - x0); dxw = np.minimum(dxw, W - dxw)
        brk *= 1 - ss(ln * 0.55 + 0.003 * cv.ppm, ln * 0.35, dxw) * rng.uniform(0.6, 1.0)
    alpha = np.clip(alpha * brk[None, :] * 1.5, 0, 0.9)
    base = C(138, 62, 46)
    cv.over(base, alpha)
    cv.over(C(104, 44, 34), 0.35 * alpha * ss(0.0, 1.2, tooth))
    cv.over(C(170, 92, 70), 0.30 * alpha * ss(0.8, 1.8, tooth2))
    cv.fill_empty(base)
    cv.save(name, normal=False)
    manifest[name] = dict(seed=3601, size_m=[2.4, 0.06], px=[W, H], tileable_x=True, colour_srgb=[138, 62, 46], note="4096 px wide so the 8 mm line is ~14 px")
    table[name] = dict(tex="walldetail/" + name, w=2.4, h=0.06, y=[1.0, 1.2], normal=False, tile=True, kind="trail")


# ------------------------------------------------------------------ 8. outlet grime
def outlet_grime():
    name = "outlet_grime"
    rng = np.random.default_rng(3701)
    cv = Cv(0.2, 0.2)
    dx, dy = cv.X - 0.1, cv.Y - 0.1
    r = np.hypot(dx, dy)
    cloud = 0.55 + 0.45 * ss(-1.2, 1.2, cv.n(rng, 0.012))
    cv.over(C(104, 88, 62), 0.18 * np.exp(-(np.maximum(r - 0.03, 0) / 0.05) ** 2) * cloud * ss(0.095, 0.05, r))
    for _ in range(7):  # finger smears
        a = rng.uniform(0.15, np.pi - 0.15) if rng.random() < 0.6 else rng.uniform(0, 2 * np.pi)
        L = rng.uniform(0.04, 0.075); w = rng.uniform(0.007, 0.012)
        ux, uy = np.cos(a), np.sin(a)
        t = dx * ux + dy * uy
        p = -dx * uy + dy * ux + 0.002 * cv.n(rng, 0.01)
        sm = ss(0.02, 0.035, t) * ss(L, L - 0.02, t) * np.exp(-(p / w) ** 2)
        rid = 0.65 + 0.35 * np.sin(p / 0.0011 + rng.uniform(0, 6)) * ss(-0.6, 0.8, cv.n(rng, 0.003))
        cv.over(C(92, 76, 52), 0.20 * sm * rid)
    cv.over(C(80, 66, 46), 0.06 * np.exp(-((r - 0.036) / 0.006) ** 2) * ss(-0.8, 1.0, cv.n(rng, 0.006)))
    cv.fill_empty(C(104, 88, 62))
    W, H = cv.save(name, normal=False)
    manifest[name] = dict(seed=3701, size_m=[0.2, 0.2], px=[W, H])
    table[name] = dict(tex="walldetail/" + name, w=0.2, h=0.2, y=[0.3, 1.4], normal=False, tile=False, kind="stain")


# ------------------------------------------------------------------ 9. damp bloom
def damp_bloom():
    name = "damp_bloom"
    rng = np.random.default_rng(3801)
    cv = Cv(1.2, 1.0)
    cx, cy = 0.6, 0.45
    rad = np.hypot((cv.X - cx) / 0.42, (cv.Y - cy) / 0.34)
    f = 1.0 - rad + 0.30 * cv.n(rng, 0.09) + 0.14 * cv.n(rng, 0.03) + 0.05 * cv.n(rng, 0.008)
    f += 0.22 * np.exp(-((cv.X - cx - 0.05) / 0.10) ** 2) * ss(0.4, 0.8, cv.Y)  # wick tongue downward
    win = ss(0.0, 0.16, np.minimum(np.minimum(cv.X, cv.wm - cv.X), np.minimum(cv.Y, cv.hm - cv.Y)))
    f = f - 0.6 * (1 - win)
    body = ss(0.0, 0.32, f)
    mottle = 0.55 + 0.45 * ss(-1.2, 1.4, cv.n(rng, 0.05) * 0.7 + cv.n(rng, 0.012) * 0.3)
    cv.over(C(148, 124, 72), 0.17 * body * mottle)
    cv.over(C(122, 100, 58), 0.10 * ss(0.25, 0.7, f) * mottle)
    for off, a in ((0.20, 0.10), (0.42, 0.07)):  # earlier wet extents
        cv.over(C(116, 94, 52), a * np.exp(-((f - off) / 0.014) ** 2) * ss(-0.6, 0.8, cv.n(rng, 0.03)))
    edge = np.exp(-((f - 0.02) / 0.030) ** 2) * (0.35 + 0.65 * ss(-0.5, 1.2, cv.n(rng, 0.01)))
    cv.over(C(226, 220, 196), 0.24 * edge)  # mineral bloom rim
    edge2 = np.exp(-((f - 0.012) / 0.011) ** 2) * ss(0.2, 1.4, cv.n(rng, 0.004))
    cv.over(C(238, 234, 214), 0.20 * edge2)
    cv.over(C(108, 90, 56), 0.10 * np.exp(-((f + 0.03) / 0.02) ** 2) * ss(-0.5, 1, cv.n(rng, 0.01)))
    cv.fill_empty(C(148, 124, 72))
    W, H = cv.save(name, normal=False)
    manifest[name] = dict(seed=3801, size_m=[1.2, 1.0], px=[W, H])
    table[name] = dict(tex="walldetail/" + name, w=1.2, h=1.0, y=[1.8, 2.1], normal=False, tile=False, kind="stain")


# ------------------------------------------------------------------ previews
def load(name):
    im = np.array(Image.open(os.path.join(DETAIL, name + ".png")).convert("RGBA")).astype(float) / 255
    nrm = None
    p = os.path.join(DETAIL, name + "_normal.png")
    if os.path.exists(p):
        nrm = np.array(Image.open(p).convert("RGB")).astype(float) / 255 * 2 - 1
    return im, nrm


def wall_patch(w_m, h_m, ppm):
    """Real wallpaper at true scale: one texture tile = 0.6 m (wall.gdshader uniform tile)."""
    tp = int(round(0.6 * ppm))
    wp = np.array(Image.open(WALLPAPER).convert("RGB").resize((tp, tp), Image.LANCZOS)).astype(float) / 255
    W, H = int(w_m * ppm), int(h_m * ppm)
    return np.tile(wp, (H // tp + 2, W // tp + 2, 1))[:H, :W].copy()


LIGHT = np.array([-0.55, 0.55, 0.63]); LIGHT /= np.linalg.norm(LIGHT)


def place(base, ppm, name, cx_m, cy_floor_m, h_wall=2.6):
    im, nrm = load(name)
    t = table[name]
    wpx, hpx = int(round(t["w"] * ppm)), int(round(t["h"] * ppm))
    if wpx < 1 or hpx < 1:
        return
    a = cv2.resize(im[..., 3], (wpx, hpx), interpolation=cv2.INTER_AREA)
    rgb = cv2.resize(im[..., :3] * im[..., 3:], (wpx, hpx), interpolation=cv2.INTER_AREA) / np.maximum(a[..., None], 1e-4)
    x0 = int(round(cx_m * ppm - wpx / 2)); y0 = int(round((h_wall - cy_floor_m) * ppm - hpx / 2))
    H, W = base.shape[:2]
    xa, ya = max(x0, 0), max(y0, 0); xb, yb = min(x0 + wpx, W), min(y0 + hpx, H)
    if xb <= xa or yb <= ya:
        return
    sl = (slice(ya - y0, yb - y0), slice(xa - x0, xb - x0))
    rgb, a = rgb[sl], a[sl]
    dst = base[ya:yb, xa:xb]
    if nrm is not None:
        n = cv2.resize(nrm, (wpx, hpx), interpolation=cv2.INTER_AREA)[sl]
        n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
        sh = (n @ LIGHT) / LIGHT[2]
        dst = dst * (1 + (sh[..., None] - 1) * np.clip(a[..., None] * 1.6, 0, 1) * 0.9)
    base[ya:yb, xa:xb] = dst * (1 - a[..., None]) + rgb * a[..., None]


def label(img, text, xy=(8, 6)):
    pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(pil)
    d.rectangle([xy[0] - 3, xy[1] - 2, xy[0] + 6 * len(text) + 4, xy[1] + 13], fill=(0, 0, 0))
    d.text(xy, text, fill=(255, 255, 255))
    return np.array(pil).astype(float) / 255


def save_img(path, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(path)


def preview():
    ppm = 330
    layouts = [
        ("ghosts", [("poster_ghost_a", 0.55, 1.45), ("poster_ghost_b", 1.45, 1.45), ("poster_ghost_c", 2.30, 1.45),
                    ("outlet_grime", 0.45, 0.35), ("tape_scraps_1", 1.2, 0.8), ("scuffs_1", 1.5, 0.12)]),
        ("low wear", [("desk_ghost", 0.9, 0.55), ("scuffs_2", 2.35, 0.3), ("scuffs_3", 0.5, 0.2), ("scuffs_4", 1.5, 0.16),
                      ("water_line", 1.5, 0.3), ("crayon_trail", 1.5, 1.1), ("scuffs_1", 2.4, 0.12)]),
        ("damage", [("hole_knob", 0.6, 0.97), ("hole_punch", 1.15, 1.0), ("tape_scraps_2", 1.7, 1.5), ("tape_scraps_3", 2.1, 1.7),
                    ("damp_bloom", 1.5, 2.0), ("outlet_grime", 2.5, 0.8), ("tape_scraps_1", 0.4, 1.6)]),
    ]
    patches = []
    for title, items in layouts:
        base = wall_patch(3.0, 2.6, ppm)
        fl = int(0.1 * ppm)
        base[-fl:] = np.array([0.30, 0.28, 0.22]); base[-fl - 5:-fl] = np.array([0.55, 0.52, 0.45])
        for (nm, x, y) in items:
            place(base, ppm, nm, x, y)
        patches.append(label(base, title + " (3 x 2.6 m, true scale)"))
    save_img(os.path.join(PREV, "wall_details_preview.png"), np.concatenate(patches, axis=1))
    for i, p in enumerate(patches, 1):
        save_img(os.path.join(PREV, "wall_details_preview_%d.png" % i), p)

    ppm2 = 900
    tiles = []
    for nm in ["poster_ghost_a", "poster_ghost_c", "tape_scraps_1", "tape_scraps_2", "hole_knob", "hole_punch", "scuffs_3", "outlet_grime"]:
        t = table[nm]
        b = wall_patch(t["w"], t["h"], ppm2)
        place(b, ppm2, nm, t["w"] / 2, t["h"] / 2, h_wall=t["h"])
        sc = min(1.0, 600 / max(b.shape))
        tiles.append(label(cv2.resize(b, (max(1, int(b.shape[1] * sc)), max(1, int(b.shape[0] * sc))), interpolation=cv2.INTER_AREA), nm))

    def row(ts):
        hh = max(t.shape[0] for t in ts)
        return np.concatenate([np.pad(t, ((0, hh - t.shape[0]), (4, 4), (0, 0))) for t in ts], axis=1)
    r1, r2 = row(tiles[:4]), row(tiles[4:])
    Wd = max(r1.shape[1], r2.shape[1])
    pad = lambda r: np.pad(r, ((0, 0), (0, Wd - r.shape[1]), (0, 0)))
    save_img(os.path.join(PREV, "wall_details_closeups.png"), np.concatenate([pad(r1), pad(r2)], 0))

    ppm3 = 300
    rows = []
    for nm in ("water_line", "crayon_trail"):
        t = table[nm]
        im, _ = load(nm)
        reps = np.tile(im, (1, 3, 1))
        wpx = int(round(t["w"] * 3 * ppm3)); hpx = int(round(t["h"] * ppm3))
        base = wall_patch(t["w"] * 3, max(t["h"] + 0.1, 0.2), ppm3)
        a = cv2.resize(reps[..., 3], (wpx, hpx), interpolation=cv2.INTER_AREA)
        rgb = cv2.resize(reps[..., :3] * reps[..., 3:], (wpx, hpx), interpolation=cv2.INTER_AREA) / np.maximum(a[..., None], 1e-4)
        y0 = (base.shape[0] - hpx) // 2
        base[y0:y0 + hpx, :wpx] = base[y0:y0 + hpx, :wpx] * (1 - a[..., None]) + rgb * a[..., None]
        for k in (1, 2):
            base[0:6, int(k * t["w"] * ppm3) - 1:int(k * t["w"] * ppm3) + 1] = np.array([0.0, 0.6, 1.0])
            base[-6:, int(k * t["w"] * ppm3) - 1:int(k * t["w"] * ppm3) + 1] = np.array([0.0, 0.6, 1.0])
        rows.append(label(base, nm + " tiled 3x, blue ticks mark the seams"))
    save_img(os.path.join(PREV, "wall_details_tiling.png"), np.concatenate(rows, 0))

    zs = []
    for nm in ("water_line", "crayon_trail"):  # native-resolution seam: end of strip next to start of strip
        im, _ = load(nm)
        seam = np.concatenate([im[:, -400:], im[:, :400]], 1)
        comp = np.ones_like(seam[..., :3]) * np.array([0.78, 0.71, 0.44]) * (1 - seam[..., 3:]) + seam[..., :3] * seam[..., 3:]
        if comp.shape[0] < 150:
            comp = np.repeat(comp, 4, axis=0)
        comp[:, 399:401] = comp[:, 399:401] * 0.5 + np.array([0.0, 0.6, 1.0]) * 0.5 if False else comp[:, 399:401]
        zs.append(label(comp, nm + " seam is the centre of this image"))
    Wd = max(z.shape[1] for z in zs)
    save_img(os.path.join(PREV, "wall_details_seams.png"), np.concatenate([np.pad(z, ((0, 4), (0, Wd - z.shape[1]), (0, 0))) for z in zs], 0))


def main():
    ghost("poster_ghost_a", 0.6, 0.9, 3001, pins=[(0.0, -0.96, 0.0032)], tape_corners=(1, 1, 0, 1))
    ghost("poster_ghost_b", 0.45, 0.6, 3002, pins=[(-0.88, -0.90, 0.0030), (0.88, -0.90, 0.0030)], tape_corners=(0, 0, 1, 1))
    ghost("poster_ghost_c", 1.2, 0.8, 3003, pins=[(-0.92, -0.86, 0.0055), (0.92, -0.86, 0.0055), (-0.92, 0.86, 0.0055), (0.92, 0.86, 0.0055)],
          board=True, tape_corners=(0, 0, 0, 0))
    tape_scraps(); scuffs(); holes(); desk_ghost(); water_line(); crayon_trail(); outlet_grime(); damp_bloom()
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True); os.makedirs(os.path.dirname(TABLE), exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump(dict(script="pipeline/textures/build_wall_details.py", normal_convention="OpenGL (Y up)", assets=manifest), f, indent=1)
    with open(TABLE, "w") as f:
        json.dump(table, f, indent=1)
    preview()
    print("done", len(table), "assets")


if __name__ == "__main__":
    main()
