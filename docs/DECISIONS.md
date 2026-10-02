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

## D011 (2026-10-01, S01) Engine: Godot 4.7.2 Forward+ (bake-off won)
- Blind A/B, same scene dump, same seed 4242, same camera track and frame times, camcorder off, judged separately by player-critic with the identical prompt (review/critiques/003_claude_bakeoff_A.md, 004_claude_bakeoff_B.md; side by side in progress/0026):
  Build A (Godot, the early build 20261001-191043): First 5, Lighting 6, Shadows 5, Materials 6, Atmosphere 4, Camera 4, Surreal 4, Pace 3, Perf 4, Keep 4.
  Build B (three.js r186 WebGPU, 67 + 25 min spike): First 5, Lighting 5, Shadows 4, Materials 5, Atmosphere 4, Camera 4, Surreal 4, Pace 4, Perf 4, Keep 5.
- Godot wins all three look categories that decide this milestone (Lighting, Shadows, Materials). Perf at the time: A 39 fps, B 38 fps (idle GPU); Godot is now 66 fps after D007. Practical factors also favor Godot: real-time GI (SDFGI) and real shadow maps on procedural geometry (B needed a baked 2D irradiance map and 2D wall masks, which cannot handle stairs, portals, props or a monster's shadow), volumetric fog, Movie Maker deterministic capture with audio, native build.
- Cost: no play-in-browser URL; the shareable link is an itch.io download page (M7). The spike stays in spike/threejs/ for reference.
- Revert: only if a later three.js release gets real GI and shadows that beat Godot in a new blind test.

## D012 (2026-10-01, S01) Screen-space reflections off by default
- SSR reflected the very bright troffer lenses as milky white blobs on wet and flooded carpet (critique 005, progress/0031) and cost about 2 fps. Wet carpet is rendered as darker and only slightly less rough instead. Re-enable with `--ssr` when a reflection setup that clamps emissive brightness exists (needed for The Pools in M6).

## D013 (2026-10-01, S02) Fixture lighting: panels kept clear of walls, pooled cones, ceiling glow field
- Problem (critique 006, L021): every panel is a point spot light; panels placed on a fixed grid sat right against walls and painted bright curved arcs on them ("sideways spotlights").
- Choice: (1) the fixture grid slides each panel by whole ceiling tiles to the spot with the most wall clearance (`_place_fixture`), like a real reflected-ceiling plan; (2) cone falloff 1.25 to 1.5 and distance falloff 1.4 to 1.7, so light pools under each panel; (3) less GI bounce (SDFGI energy 1.7 to 1.0, feedback 0.95 to 0.6), more SSAO (3.0), AgX contrast 1.3, auto exposure 0.36, haze density 0.016; (4) more dead panels (18 percent, four dead clusters) so lit pools alternate with gloom; (5) a tiny "fixture field" texture (one texel per tile, live flicker level) that the ceiling shader blurs into the glow a lit panel throws on its neighbors, and that lights the troffer reveal (`scripts/level0/fixture_field.gd`, `shaders/housing.gdshader`).
- Alternatives tried: virtual light source above the ceiling (rejected: SDFGI ray-marches light occlusion through the SDF, so the ceiling would block all bounce), cosine-profile 89 degree cones (rejected: spot shadow maps use a 2x angle perspective, so shadow resolution collapses).
- Revert: game args `--spot_cone=1.25 --spot_atten=1.4 --gi=1.7 --gi_fb=0.95 --dead_rate=0.06 --clusters=2 --halo=0` (look switches in level0_look.gd and level0_hero.gd), and skip `_place_fixture`.

## D014 (2026-10-01, S02) Splice errors must read as deliberate
- Opus gate: the chair cut through its seat and the chair sunk into the carpet read as broken assets (L023). Choice: the cut chair now faces into the wall with only its front buried (column, back and base stay whole) and a dark splice seam on the wallpaper; the sunk chair became a chair standing upside down on the ceiling (a flipped copy). The stairs into the ceiling are now built from the level's own wallpaper, carpet, vinyl nosing, skirt board and a handrail, and climb through an open gap in the tiles into the dark plenum (L022).
- Revert: `splices` and `stairs` entries in game/data/level0_hero.json; `_build_stairs` in level0_hero.gd.

## D015 (2026-10-01, S02) Infinite Level 0: 24 m chunks, BSP rooms, hash-shared edges, stepped streaming
- Choice: Level0Gen makes each 24 x 24 m chunk from (world seed, chunk coordinate): boundary edges get walls and gaps from a hash of the edge alone, so both neighbors agree and every edge has at least one gap; the interior is a BSP on a 1.2 m module grid where every split wall has at least one door or opening, so the maze is always connected. Corridors, open-plan splits, wall stubs, pillar halls, dark rooms and generation-loss splices are seeded per chunk. Level0Chunk (the old hero builder, now layout-driven) builds a chunk in seven steps; Level0World runs one step per frame (count-based, so Movie Maker captures stay deterministic), keeps chunks within 40 m and frees them beyond 58 m. 40 m is beyond SDFGI's largest cascade (about 26 m with min cell 0.1 and 3 cascades), which only voxelizes geometry when a cascade scrolls over it. Only panels within 23 m get a real light and hum (FixturePool, 112 lights).
- Alternatives: one big navmesh (NavigationServer3D, rejected for now: async baking is not frame-deterministic), WFC (harder to guarantee connectivity), building on a thread (non-deterministic timing).
- Revert: `-- --hero` runs the S01 hero slice; main.gd picks the space.

## D016 (2026-10-01, S02) Layout language from Stewart's floor-plan reference, not its layout
- Stewart shared a hand-drawn floor plan from the film's promotional material. We use only general design language (stepped walls, plus-shaped columns, T/L partitions, fins, perimeter corridors, service cores, dead ends), never its layout or landmarks (CLAUDE.md IP rule). Notes: docs/reference/map_inspiration_s02.md.

## D017 (2026-10-02, S02) The loop corridor: identical sealed copies plus a silent one-copy jump
- Choice: on some highway rows a run of four chunks is built from one template (same layout, same random streams, wallpaper UVs and shader patterns offset back to the template). The run is sealed except for the hall. Walking on in the direction you entered, Level0World moves the player back one copy (24 m) when they step into the third copy; lights and hum lent to the panels around them are carried to the twin panels so they do not restart. Looking back down the hall for 1.5 s, or walking back 6 m, after at least one repeat releases the loop. The way in is always open, so it can never trap anyone. "TURN AROUND" graffiti sits just before each run (a fair hint); tally marks reading COPY 31 and a spiral of SAME repeat in every copy.
- Alternatives: render-to-texture portals (Godot 4.7 has no oblique near plane, double tonemapping and fog to solve), moving the world instead of the camera (keeps temporal effects stable but every streamed position and shader pattern must carry a global offset; the fallback if the jump shows in review).
- Known risk: temporal effects (TAA history, volumetric fog reprojection, SDFGI cascade scroll) can show for a frame or two at the jump; fog reprojection is disabled for two frames as mitigation. Verify on video.
- Revert: Level0Gen.loop_start returns 1 << 20.

## D018 (2026-10-02, S02) Things that exist only on tape: render layer 11
- The player camera draws render layer 11 only while the camcorder is up. The first tenant is the figure at the end of the hall (TapeEvents): it appears under a lit panel 12 to 22 m down a long open view, at most three times a run, gone when the camera comes down or you walk toward it; the only naked-eye tell is the panel above it stuttering. This answers the top complaint of both gate critics (L031) and VISION's "the camera sees what you can't". The Entity proper is still M4; this figure must stay an absence (black, faceless, glitching), never a chasing monster.
- Revert: remove TapeEvents from Level0World.

## D019 (2026-10-02, S02) M1 gate: two honest attempts failed; remaining issues roll into M2
- Gate attempt 2 (build 20261001-225950, critiques 007): Opus Lighting 6 / Atmosphere 5, Gemini 4 / 6 (attempt 1: 6/6 and 3/4). Per CLAUDE.md the milestone ends after two honest failed attempts. The causes both critics named (nothing happens, the camcorder shows nothing, the 30 m slice repeats, flat fill) are M2 work (generated level, tape-only figure, loops, darker fill) and are judged again in the M2 critic loops; the hero slice stays as a reference scene (`--hero`).
