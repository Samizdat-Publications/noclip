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

## D005 (2026-10-01, S01) Progress pictures for every generated image (Stewart's rule)
- Every generated PNG (look-dev renders, review captures, critic packets, previews) gets a copy in `progress/` named `NNNN_YYYY-MM-DD_HHMM_sSS_label.jpg`, indexed in `progress/INDEX.md` with what it shows and the git commit. `tools/progress.py` does it; `tools/lookdev.py` and `tools/capture/capture.py` call it automatically. Copies are full-resolution JPEG (quality 92) so the repo stays light; full PNG frames are kept locally in `review/archive/builds/`.

## D006 (2026-10-01, S01) Fluorescent panels are shadowed spot lights, not AreaLight3D (for now)
- AreaLight3D (new in 4.7) gives correct rectangular lighting, but its shadows draw large curved projection artifacts on floors and walls (progress/0007). Without shadows, light leaks through walls and kills the dark rooms. Choice: SpotLight3D per panel (82 degree cone, soft PCSS via light_size), and the rectangular lens reflections come from SSR of the real emissive lens mesh.
- Revert: run with `--arealights`, or flip the default in level0_hero.gd once Godot fixes area-light shadows.
