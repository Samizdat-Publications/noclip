"""Build sheet_<name>.jpg for a Meshy occupant: runs the Blender preview then tiles 5 views."""
import json, subprocess, sys, os
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
BL = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
name = sys.argv[1]
out = ROOT / "pipeline" / "meshes" / "cache" / "entity" / "meshy"
glb = out / name / f"{name}.glb"
r = subprocess.run([BL, "-b", "-P", str(ROOT / "pipeline/blender/preview_entity_meshy.py"), "--", str(glb), str(out / name), name],
                   capture_output=True, text=True)
print([l for l in r.stdout.splitlines() if l.startswith("STATS")], r.stderr[-300:] if r.returncode else "")
paths = json.loads([l for l in r.stdout.splitlines() if l.startswith("PATHS")][0][6:])
sheet = Image.new("RGB", (768 * 5, 1152), (80, 80, 80))
for i, p in enumerate(paths):
    sheet.paste(Image.open(p).convert("RGB"), (768 * i, 0))
dest = out / f"sheet_{name}.jpg"
sheet.save(dest, quality=90); print(dest)
