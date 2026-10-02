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

## D007 (2026-10-01, S01) Lighting budget: 7 m light reach, medium soft shadows, 32-bit shadow atlas
- Profiling (tools/perfprobe.sh) showed overlapping shadowed lights were the cost: 13 m reach = 36 fps, 7 m reach + shadow filter quality 2 = 66 fps avg / 50 fps 1% low at 1440p. Shorter reach also gives real pools of light and darker gaps, which the critic asked for. The 16-bit shadow atlas caused stepped bands on walls at grazing angles, so the atlas is 32-bit (shadow bias 0.06, normal bias 2.6). OmniLight3D cube shadows were tried for shadow quality and rejected (31 fps).
- Revert: game args `--spot_range=13 --shadowq=3 --atlas16`.

## D008 (2026-10-01, S01) Props come from Sketchfab (CC0/CC-BY only) and procedural Blender; Meshy is saved for the monster
- Meshy had 3 credits. Everyday props are better as real-world-style models: Sketchfab CC0/CC-BY downloads via `pipeline/meshes/sketchfab_fetch.py` (credited in docs/CREDITS.md; NC/ND/SA/store licenses rejected), plus procedural Blender models where Sketchfab has nothing good. Meshy (300 free onboarding credits per Stewart) is reserved for the original monster in M4, where on-theme generation, rigging and animation matter.

## D009 (2026-10-01, S01) Core twist: the Backrooms are generation loss of recordings
- Stewart wants the film's general concept (spaces as distorted memories that lose fidelity with depth, furniture halfway through walls) with our own twist. Research (docs/reference/film_2026_research.md) showed the film's own premise is "the place copies the protagonist's furniture store", so that cannot be our twist.
- Choice: the Backrooms are made of recordings, like a VHS tape dubbed from a dub. Level 0 is a first-generation copy with splice errors (props clipped into walls and floors, looped-frame repeats, a sheared tracking band in a wall). Each level deeper is another generation: geometry shears in bands, color bleeds into materials, detail and text smear away. The camcorder sees the place for what it is. Your own death tapes become part of later runs. One `fidelity` value per level drives materials, props, light, text and sound.
- Alternatives: "copies of the store" (too close to the film), pure dream logic (no rules for the player to learn).
- Revert: VISION section "Generation loss"; nothing in code depends on it beyond the Level 0 splice-error props and the wall shear band.

## D010 (2026-10-01, S01) An ambiguous organization: Halden Duplicating (placeholder name)
- Stewart asked for suited people from the real world who work in the Backrooms, not quite on your side. The film's extraction team (a former MRI company) is its own organization, so ours is original and grows out of D009: a 1990s tape-duplication company whose clean-room crews (white suits, lab coats) study the place as a recording and hunt for the "master" deep down. They buy your recovered tapes (the hub trading loop, M5), but field teams also degauss sectors (lights and sound die, the Entity notices), sometimes leave supplies, sometimes lock doors behind you. Traces: tripod camcorders recording empty halls, labeled tape crates, chalk survey codes.
- Revert: drop the organization from VISION; nothing in code depends on it yet.
