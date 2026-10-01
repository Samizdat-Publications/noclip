import os, cv2, numpy as np
from PIL import Image
from tex_common import OUT, PREV

def load(n):
    n = n if n.endswith(".png") else n + ".png"
    return np.asarray(Image.open(os.path.join(OUT, n)).convert("RGBA" if n.startswith("decal") else "RGB"))

def tile3(name, out_w=1536):
    im = load(name)
    t = np.tile(im, (3, 3, 1))
    s = out_w / t.shape[1]
    t = cv2.resize(t, (out_w, int(t.shape[0] * s)), interpolation=cv2.INTER_AREA)
    Image.fromarray(t).save(os.path.join(PREV, name.replace(".png", "") + "_3x3.png"))

def seam(name, size=900):
    im = load(name)
    h, w = im.shape[:2]
    r = np.roll(im, (h // 2, w // 2), (0, 1))
    cy, cx = h // 2, w // 2
    hh, ww = min(size, h) // 2, min(size, w) // 2
    Image.fromarray(r[cy - hh:cy + hh, cx - ww:cx + ww]).save(os.path.join(PREV, name.replace(".png", "") + "_seam.png"))

def over(base, rgba, x0, y0):
    h, w = rgba.shape[:2]
    reg = base[y0:y0 + h, x0:x0 + w].astype(float)
    a = rgba[..., 3:4].astype(float) / 255
    base[y0:y0 + h, x0:x0 + w] = (reg * (1 - a) + rgba[..., :3] * a).astype(np.uint8)

def tiled_to(name, w, h, scale):
    im = load(name)[..., :3]
    im = cv2.resize(im, (int(im.shape[1] * scale), int(im.shape[0] * scale)), interpolation=cv2.INTER_AREA)
    ny, nx = -(-h // im.shape[0]), -(-w // im.shape[1])
    return np.tile(im, (ny, nx, 1))[:h, :w].copy()
