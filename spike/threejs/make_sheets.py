# Compose 3x3 contact sheets (2560x1440, cells 853x480, LANCZOS) from rendered cells.
import json, os, sys
from PIL import Image

spec = json.load(open(sys.argv[1]))
os.makedirs(spec["out"], exist_ok=True)
CW, CH = 853, 480
for name, files in spec["sheets"].items():
    sheet = Image.new("RGB", (2560, 1440), (0, 0, 0))
    for k, f in enumerate(files[:9]):
        im = Image.open(f).convert("RGB").resize((CW, CH), Image.LANCZOS)
        sheet.paste(im, ((k % 3) * CW, (k // 3) * CH))
    sheet.save(os.path.join(spec["out"], name))
    print("sheet", name, len(files))
