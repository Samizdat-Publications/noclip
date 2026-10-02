"""Fast script sanity check: imports, runs the game headless for a few frames, prints any
script or engine errors (ignoring the known harmless invalid-UID warnings). Exit code 1 on errors.

    python tools/gdcheck.py [extra game args...]
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import paths  # noqa: E402

subprocess.run([paths.godot(), "--headless", "--path", paths.GAME, "--import"], capture_output=True, timeout=600)
r = subprocess.run([paths.godot(), "--headless", "--path", paths.GAME, "--quit-after", "40", "--", "--seed=1234", "--autoplay"]
                   + [f"--{a}" for a in sys.argv[1:]], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
out = (r.stdout or "") + (r.stderr or "")
lines = out.splitlines()
bad = []
for i, l in enumerate(lines):
    if ("ERROR" in l or "Parse Error" in l) and "invalid UID" not in l and "still in use" not in l and "leaked" not in l:
        nxt = lines[i + 1].strip() if i + 1 < len(lines) and lines[i + 1].strip().startswith("at:") else ""
        bad.append(l + ("  " + nxt if nxt else ""))
seen = set()
for l in bad:
    if l not in seen and len(seen) < 25:
        seen.add(l)
        print(l)
print("gdcheck:", "FAIL" if bad else "ok", f"({len(bad)} error lines)")
sys.exit(1 if bad else 0)
