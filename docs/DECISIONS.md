# DECISIONS

Newest at the bottom. Each entry: choice, alternatives, why, how to revert.

## D001 (2026-10-01, S01) Project lives at C:\Users\stewa\ClaudeProjects\Noclip, not C:\dev\noclip
- Choice: keep the repo where Stewart created it (`C:\Users\stewa\ClaudeProjects\Noclip`, outside OneDrive). START_HERE.md and CLAUDE.md mention `C:\dev\noclip`; the launch command in every handoff uses the real path.
- Alternatives: move to C:\dev\noclip (would break Stewart's desktop-app session folder).
- Revert: move the folder and update the launch block in CLAUDE.md and HANDOFF.md.

## D002 (2026-10-01, S01) Tool paths resolved by script, not by editing the system PATH
- Choice: winget put Godot and FFmpeg in `%LOCALAPPDATA%\Microsoft\WinGet\Links` (already on the user PATH for new shells). Blender 5.1.2 is at `C:\Program Files\Blender Foundation\Blender 5.1`. Tools use `tools/paths.py` to find binaries instead of changing PATH.
- Why: changing system settings is out of bounds; resolving paths in code is more reliable anyway.
- Revert: delete tools/paths.py usage and rely on PATH.

## D003 (2026-10-01, S01) Hardware note: the dev PC GPU is an RTX 5070 Ti Laptop GPU (12 GB)
- `nvidia-smi` reports "NVIDIA GeForce RTX 5070 Ti Laptop GPU", driver 610.71. CLAUDE.md says "RTX 5070". The perf targets stay as written (1440p 60 fps High); perf.json records the real GPU name so the numbers are honest.

## D004 (2026-10-01, S01) Critic reviews are recovered from the critic's transcript
- Problem found while proving the guard: `.claude/hooks/critic_guard.mjs` blocks every tool except Read and Glob, which includes the harness tool the critic needs to hand its report back. Result: the guard works (CLAUDE.md, VISION.md and repo globs are all blocked, evidence in review/archive/S01_guard_test.md) but every review would be lost.
- Choice: do not touch the guard (settings deny it and CLAUDE.md forbids it). `tools/critic_extract.py` pulls the critic's review verbatim out of its own transcript. Optional one-line fix for Stewart is in NEEDS_STEWART.
- Alternatives: edit the guard (forbidden), write a second critic agent (would weaken blindness guarantees).
- Revert: once the guard allows the handback tool, use the critic's reply directly; the extractor still works as a fallback.
