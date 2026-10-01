"""Write Godot .import presets for generated assets so a headless import gets them right:
textures get mipmaps and high-quality VRAM compression (normal maps as normal maps),
looping sounds loop. Only writes a preset when the .import file is missing or its params
differ; Godot fills in the rest on import.

Usage: python tools/import_presets.py [game_dir]
"""
import os
import sys

TEX_PARAMS = {
    "compress/mode": "2",
    "compress/high_quality": "true",
    "compress/lossy_quality": "0.7",
    "compress/uastc_level": "0",
    "compress/rdo_quality_loss": "0.0",
    "compress/hdr_compression": "1",
    "compress/normal_map": "0",
    "compress/channel_pack": "0",
    "mipmaps/generate": "true",
    "mipmaps/limit": "-1",
    "roughness/mode": "0",
    "roughness/src_normal": '""',
    "process/channel_remap/red": "0",
    "process/channel_remap/green": "1",
    "process/channel_remap/blue": "2",
    "process/channel_remap/alpha": "3",
    "process/fix_alpha_border": "true",
    "process/premult_alpha": "false",
    "process/normal_map_invert_y": "false",
    "process/hdr_as_srgb": "false",
    "process/hdr_clamp_exposure": "false",
    "process/size_limit": "0",
    "detect_3d/compress_to": "0",
}

WAV_PARAMS = {
    "force/8_bit": "false",
    "force/mono": "false",
    "force/max_rate": "false",
    "force/max_rate_hz": "44100",
    "edit/trim": "false",
    "edit/normalize": "false",
    "edit/loop_mode": "0",
    "edit/loop_begin": "0",
    "edit/loop_end": "-1",
    "compress/mode": "0",
}

LOOP_HINTS = ("hum_", "buzz_", "room_tone", "_loop")


def write_preset(path, importer, typ, params):
    imp = path + ".import"
    res = "res://" + os.path.relpath(path, GAME).replace("\\", "/")
    body = f'[remap]\n\nimporter="{importer}"\ntype="{typ}"\n\n[deps]\n\nsource_file="{res}"\n\n[params]\n\n'
    body += "".join(f"{k}={v}\n" for k, v in params.items())
    if os.path.exists(imp):
        old = open(imp, encoding="utf-8").read()
        if all(f"{k}={v}\n" in old for k, v in params.items()):
            return False
    with open(imp, "w", encoding="utf-8", newline="\n") as f:
        f.write(body)
    return True


def main():
    n = 0
    for root, _, files in os.walk(os.path.join(GAME, "assets")):
        for fn in files:
            p = os.path.join(root, fn)
            low = fn.lower()
            if low.endswith(".png"):
                prm = dict(TEX_PARAMS)
                if low.endswith("_normal.png"):
                    prm["compress/normal_map"] = "1"
                n += write_preset(p, "texture", "CompressedTexture2D", prm)
            elif low.endswith(".wav"):
                prm = dict(WAV_PARAMS)
                if any(h in low for h in LOOP_HINTS):
                    prm["edit/loop_mode"] = "2"
                n += write_preset(p, "wav", "AudioStreamWAV", prm)
    print(f"import presets written: {n}")


GAME = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "game"))

if __name__ == "__main__":
    main()
