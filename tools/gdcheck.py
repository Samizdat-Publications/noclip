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
# Audio sanity (S03: a half-written breath loop played as a full-scale square wave in a capture).
try:
    import glob as _glob
    import numpy as _np
    import soundfile as _sf
    for _f in sorted(_glob.glob(os.path.join(paths.GAME, "assets", "audio", "**", "*.wav"), recursive=True)):
        _d, _sr = _sf.read(_f, always_2d=True)
        _rms = float(_np.sqrt((_d ** 2).mean())) if _d.size else 0.0
        _dc = float(abs(_d.mean())) if _d.size else 0.0
        _pk = float(_np.abs(_d).max()) if _d.size else 0.0
        # Loud with no crest (a square wave / stuck sample) or a DC offset: a broken file.
        if (_rms > 0.3 and _pk / max(_rms, 1e-9) < 1.2) or _rms > 0.7 or _dc > 0.05:
            bad.append(f"AUDIO SUSPECT {os.path.basename(_f)}: rms {_rms:.3f} dc {_dc:.3f}")
            print(bad[-1])
except ImportError:
    pass
print("gdcheck:", "FAIL" if bad else "ok", f"({len(bad)} error lines)")
sys.exit(1 if bad else 0)
