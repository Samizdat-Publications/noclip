"""Shared helpers for the Level 0 texture pipeline (all procedural, numpy only).
Every noise field is built in the Fourier domain, so it is periodic (seamless) by construction."""
import os
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "assets", "textures", "level0")
PREV = os.path.join(ROOT, "pipeline", "textures", "previews")
os.makedirs(OUT, exist_ok=True)
os.makedirs(PREV, exist_ok=True)


def srgb2lin(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin2srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def rgb8(*v):
    return np.array(v, dtype=np.float64) / 255.0


def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def gnoise(shape, rng, sy, sx=None):
    """Periodic gaussian-filtered noise, zero mean, unit std. sy/sx = sigma in pixels."""
    sx = sy if sx is None else sx
    h, w = shape
    F = np.fft.rfft2(rng.standard_normal(shape))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    filt = np.exp(-0.5 * ((2 * np.pi * fy * sy) ** 2 + (2 * np.pi * fx * sx) ** 2))
    n = np.fft.irfft2(F * filt, s=shape)
    n -= n.mean()
    return n / (n.std() + 1e-12)


def fbm(shape, rng, sigmas, gain=0.55):
    out = np.zeros(shape)
    a = 1.0
    tot = 0.0
    for s in sigmas:
        out += a * gnoise(shape, rng, s)
        tot += a * a
        a *= gain
    return out / np.sqrt(tot)


def blur(a, s, wrap=True):
    return ndi.gaussian_filter(a, s, mode="wrap" if wrap else "nearest")


def periodic_conv(a, kernel_wrapped):
    return np.fft.irfft2(np.fft.rfft2(a) * np.fft.rfft2(kernel_wrapped), s=a.shape)


def wrapped_axes(shape):
    h, w = shape
    y = np.arange(h)
    x = np.arange(w)
    return np.minimum(y, h - y)[:, None].astype(float), np.minimum(x, w - x)[None, :].astype(float)


def normal_from_height(h, strength, wrap_y=True, wrap_x=True):
    """OpenGL convention (green = +Y up, Godot). h[row, col], row 0 is the top (+Y).
    n = (-dh/dx, +dh/drow, 1) normalised."""
    if wrap_x:
        dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    else:
        dx = np.gradient(h, axis=1)
    if wrap_y:
        dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    else:
        dy = np.gradient(h, axis=0)
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(h)
    L = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / L, ny / L, nz / L], -1)


def save_rgb(name, arr_srgb):
    Image.fromarray((np.clip(arr_srgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name))


def save_rgba(name, rgb_srgb, alpha):
    a = np.concatenate([np.clip(rgb_srgb, 0, 1), np.clip(alpha, 0, 1)[..., None]], -1)
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))


def save_gray(name, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(OUT, name))


def save_normal(name, n):
    save_rgb(name, n * 0.5 + 0.5)


def match_mean_srgb(lin, target_srgb255, iters=4, weights=None):
    """Return sRGB (0..1) image whose mean 8-bit colour equals target (per-channel gain in sRGB space)."""
    s = lin2srgb(lin)
    tgt = np.array(target_srgb255, dtype=float) / 255.0
    for _ in range(iters):
        m = s.mean(axis=(0, 1)) if weights is None else (s * weights[..., None]).sum((0, 1)) / weights.sum()
        s = np.clip(s * (tgt / m), 0, 1)
    return s


def line_strokes(shape, strokes, wrap_x=True, wrap_y=False):
    """strokes: list of (x0,y0,x1,y1,thickness,value0to1). Returns float canvas, periodic if asked."""
    import cv2
    h, w = shape
    c = np.zeros(shape, np.uint8)
    ox = (-w, 0, w) if wrap_x else (0,)
    oy = (-h, 0, h) if wrap_y else (0,)
    for (x0, y0, x1, y1, t, v) in strokes:
        for dx in ox:
            for dy in oy:
                cv2.line(c, (int(round((x0 + dx) * 8)), int(round((y0 + dy) * 8))),
                         (int(round((x1 + dx) * 8)), int(round((y1 + dy) * 8))),
                         int(v * 255), int(t), cv2.LINE_AA, 3)
    return c.astype(np.float64) / 255.0
