import time, sys
import mat_decals as m
from previews import *
for f in (m.build_waterdamage, m.build_grime_low, m.build_wetpatch, m.build_ceiling_stain, m.build_mold):
    t = time.time(); print(f.__name__, f(), round(time.time() - t, 1))

def comp_sheet(name, base, size=None):
    d = load(name)
    b = base.copy()
    over(b, d, 0, 0)
    Image.fromarray(b).save(PREV + "/comp_" + name.replace(".png", "") + ".png")
    return b

# water damage over wallpaper (wall 1 m wide: 1024 px -> wallpaper 3413 px/m -> scale 0.3)
wall = tiled_to("wallpaper_albedo", 1024, 2048, 1024 / 3413 * 3.413 * 0.3 if False else 0.30)
b = comp_sheet("decal_wall_waterdamage.png", wall)
Image.fromarray(cv2.resize(b, (512, 1024), interpolation=cv2.INTER_AREA)).save(PREV + "/comp_waterdamage_small.png")

# remaining decal composites
def fit(name, w, h, scale):
    return tiled_to(name, w, h, scale)
b = comp_sheet("decal_wall_grime_low.png", fit("wallpaper_albedo", 2048, 512, 0.45))
bb = np.zeros((512 + 96, 2048, 3), np.uint8)
bb[:512] = b
base = load("baseboard_albedo")[..., :3]
bb[512:] = cv2.resize(np.tile(base, (1, 2, 1)), (2048, 96), interpolation=cv2.INTER_AREA)
Image.fromarray(cv2.resize(bb, (1536, 456), interpolation=cv2.INTER_AREA)).save(PREV + "/comp_grime_low_small.png")
c = comp_sheet("decal_floor_wetpatch.png", fit("carpet_albedo", 1024, 1024, 0.5))
comp_sheet("decal_mold.png", fit("wallpaper_albedo", 1024, 1024, 0.45))
ct = np.tile(load("ceiling_tile_albedo")[..., :3], (2, 2, 1))
ct = cv2.resize(ct, (1024, 1024), interpolation=cv2.INTER_AREA)
comp_sheet("decal_ceiling_stain.png", ct)
sheet = np.zeros((1024, 1024 * 3, 3), np.uint8)
for i, n in enumerate(["decal_floor_wetpatch", "decal_mold", "decal_ceiling_stain"]):
    sheet[:, i * 1024:(i + 1) * 1024] = np.asarray(Image.open(PREV + "/comp_" + n + ".png").convert("RGB"))
Image.fromarray(cv2.resize(sheet, (1800, 600), interpolation=cv2.INTER_AREA)).save(PREV + "/comp_decals_misc.png")
