"""Find the external tools this project uses, without relying on PATH (see DECISIONS D002)."""
import glob
import os
import shutil

LOCAL = os.environ.get("LOCALAPPDATA", "")


def _first(cands):
    for c in cands:
        if c and os.path.exists(c):
            return c
    return None


def godot(console=True):
    name = "godot_console" if console else "godot"
    found = shutil.which(name)
    links = os.path.join(LOCAL, "Microsoft", "WinGet", "Links", name + ".exe")
    pk = glob.glob(os.path.join(LOCAL, "Microsoft", "WinGet", "Packages", "GodotEngine.GodotEngine*", "Godot_v4.7*_win64" + ("_console" if console else "") + ".exe"))
    p = _first([found, links] + sorted(pk, reverse=True))
    if not p:
        raise FileNotFoundError("Godot 4.7 not found (winget install GodotEngine.GodotEngine)")
    return p


def ffmpeg(tool="ffmpeg"):
    found = shutil.which(tool)
    links = os.path.join(LOCAL, "Microsoft", "WinGet", "Links", tool + ".exe")
    p = _first([found, links])
    if not p:
        raise FileNotFoundError(f"{tool} not found (winget install Gyan.FFmpeg)")
    return p


def blender():
    found = shutil.which("blender")
    pf = glob.glob(r"C:\Program Files\Blender Foundation\Blender *\blender.exe")
    p = _first([found] + sorted(pf, reverse=True))
    if not p:
        raise FileNotFoundError("Blender not found")
    return p


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GAME = os.path.join(ROOT, "game")
