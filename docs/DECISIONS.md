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

## D020 (2026-10-02, S03) The horizon: every surface fades into the haze between 34 and 46 m
- Verified the loop corridor on Movie Maker frames (tools/film.py, progress/0063): at the 24 m jump the far end of the hall changed, because more of the level was loaded ahead after the jump than before. Choice: all level shaders (shaders/horizon.gdshaderinc), the plain materials (dithered distance fade) and props (visibility range fade) fade to the black void between 34 and 46 m, which is what the haze already showed past the loaded area. The loop copies ahead are identical out to 48 m, so the jump is now invisible (only TAA noise on the carpet changes for a frame), and streamed chunks can never pop into view anywhere. The jump also only fires while facing on down the hall.
- Alternatives: moving the world instead of the camera (still needed the far end to match), hiding chunks per loop (pops move elsewhere), a longer loop run (streaming radius still differs).
- Revert: HZ_BEGIN/HZ_END in shaders/horizon.gdshaderinc (set to 1000), Level0Look.horizon(), PropCache visibility range.

## D021 (2026-10-02, S03) The tape figure becomes a real person copied wrong, and it comes closer when you look again
- Critique 008: "a stiff, aliased mannequin" (Claude), "a low-poly default mannequin painted black, Monster 3" (Gemini). Choice: a rigged CC-BY scan of an ordinary office worker (Sketchfab, credited) posed from code with arms hanging too long, a long neck and a small head; a fog-free dark material whose outline fizzes into noise, whose head smears sideways in bands, with tape drop-out streaks; it jumps between four held poses with a tracking tear (a frame skip, never smooth motion); it stands off to one side near a wall, under a light when possible. Lower the camcorder and raise it again within 9 s while facing that way, and it stands 3.6 m closer; the third time (or under 9 m) it is gone and the panel it stood under dies. Walking toward it ends it. Three encounters per run, nearer each time.
- Still an absence to the naked eye (render layer 11, panel stutter tell). M4 designs the Entity proper; this stays a tape-only presence.
- Revert: git history of scripts/level0/tape_events.gd and shaders/tape_figure.gdshader (the capsule figure).

## D022 (2026-10-02, S03) Seams: a door-sized patch of wall that only the eye sees
- VISION's exits ("a patch of wall you can noclip through", "the camera shows the seam that is an exit") and LEDGER L031. About one chunk in three (always the spawn chunk) has a 3.6 m block standing in a room with clearance all round, like a service core. One 1.2 x 2.15 m patch of its wall is built on render layer 12, which the player camera stops drawing while the camcorder is up, and has no collision. On tape the patch is a torn doorway (shaders/seam_tear.gdshader on layer 11) into a sealed pocket where a survey crew left a camcorder on a tripod filming the wall, a crate of tapes and a halogen work light (the one warm, hard light in the Yellow: a palette break for L039). Tells for the eye: the wallpaper on the patch is slipped 3.4 cm (a splice), and often someone traced the doorway in chalk ("HERE?") or the crew sprayed a survey mark beside it. Inside, the eye sees a sealed room; raise the camera to see the way out.
- Alternatives: render-to-texture portals (no oblique near plane in 4.7, double fog/tonemap), sealing an existing BSP room (can disconnect the maze), a seam in a highway wall (needs the pocket to fit the room behind it).
- The pockets are not exits to another level yet (M5/M6 put the way down behind some of them). The bot visits seams like a player who knows the trick.
- Revert: Level0Gen._pick_pocket_room returns without marking a room.

## D023 (2026-10-02, S03) Scale errors: rooms copied three times too tall
- Art direction #3 (scale incongruity) and critique 008's ask for "one unmistakable that-is-wrong frame" (L043). About one chunk in five (never the spawn chunk) has an ordinary room whose walls and ceiling grid go on up to 7.8 m over normal doors; the plenum is cut open above it, its panels hang at 7.8 m with longer, stronger lights (range and energy scale with height), and the wall's ceiling-grime band stays at 2.6 m like a tide line where the ceiling should be. Where the room is open plan, the neighbor's ceiling shows as a ledge. The bot stops and looks up.
- Revert: Level0Gen._pick_tall_room returns early.

## D024 (2026-10-02, S03) Performance: plain filtered panel shadows, no SSIL
- Gemini scored performance 3 at 73.7 fps; a probe on seed 4242 measured 60 to 65 fps average and 47.6 to 51.7 fps 1% low at 2560x1440 (below the 50 target). Cost by switch: shadows about 19 to 24 fps, SDFGI 9 to 14, SSIL 4 to 8, fog 2 to 6, SSAO 0 to 4; SDFGI light-update and convergence settings changed nothing. Choice: panel light_size 0.7 to 0 (PCSS blocker search off: +8 fps) and SSIL off (+5): 78.2 avg / 60.7 1% low on the same seed. A/B lookdev (progress, ab-base vs ab-fast) shows the same shadows and slightly less flat fill, which the critics asked for anyway (L059).
- Revert: game args --light_size=0.7 --ssil.

## D025 (2026-10-02, S03) Unobserved rearrangement: chairs turn to face you while unseen
- VISION toolkit ("rooms change only when outside the frustum and occluded, double-checked with raycasts") and critique 009's ask for small wrongness ("a chair that has moved", L052). A Rearranger tracks the chairs in loaded chunks; one you have clearly seen (in the camera frustum with a clear ray from the eye) that has then been out of sight for 6 s, while you are 3.5 to 14 m away, turns to face where you are now, re-checked at that moment. At most one change per 25 s, six per run, each chair once. Loop copies and splices never change.
- Revert: remove the Rearranger node in Level0World.build.

## D026 (2026-10-02, S03) Sound architecture for M3 (started)
- Room acoustics: every generated room gets an Area3D that sends the sounds made inside it to one of three reverb buses by size (RevSmall offices, RevCorridor, RevLarge for pillar halls, tall rooms and big open rooms). Footsteps became positional (at the feet) so they pick up the room. Occlusion: one ray per active hum and buzz from the listener's head every 0.2 s; behind a wall they lose their highs (900 Hz cutoff) and 7 dB. A global fear value (Game.fear) drives three breathing loops (calm, winded from stamina, shaky when afraid); a duck value pulls the whole world bus down by up to 10 dB while the tape figure is out there ("the hum dies near it", VISION) and a low drone swells in. The director's distant one-shots gained doors, a rolling chair, a ballast, steps that are not yours, knocks in a wall.
- Alternatives: HRTF via a Steam Audio GDExtension (rejected for now: native plugin, build risk, Godot's panning is adequate at this stage; revisit in M7), per-source reverb sends (Godot routes reverb by Area3D natively).
- Revert: remove _build_audio_zones, the occlusion pass in FixturePool, and the breath players in Player.

## D027 (2026-10-02, S03) Light in the air: more haze scatter, bloom and tighter pools
- Every Gemini critique calls the lighting flat ("panels are white rectangles, no haze catching the light"). A/B lookdev (progress light-ab-base vs light-ab-scatter, seed 4242): haze density 0.016 to 0.021, per-light fog energy 1.3 to 2.6, fog anisotropy 0.45 to 0.62 (forward glow when looking toward a panel), bloom 0.1 to 0.17, spot cone falloff 1.5 to 2.0. Panels now hang in a soft halo of lit air, halls fade into brighter haze, tall rooms lose their ceilings in it; pools are a little tighter. Cost: negligible.
- Revert: --fog=0.016 --fog_light=1.3 --fog_aniso=0.45 --bloom=0.1 --spot_cone=1.5.

## D028 (2026-10-02, S03) M2 closed after two failed gate attempts; on into M3
- Exit criteria: 10-minute bot walk with no seams, hitches or pops: MET (seed 9001: 102.2 fps avg, 66.4 1% low, p99 14.1 ms, ~60 chunks streamed, loop repeated 8 times, no errors; horizon fade D020 rules out pops; loop jump verified on frames). Perf held: MET (gate builds 87.0/63.7 and 98.2/68.8 at 1440p). Surreal 7+: NOT MET at the gate (attempt 1, build 977b111: Opus 6, Gemini 8; attempt 2, build bc73bfd: Opus 6, Gemini 6; it reached 7 and 8 in loop 1).
- Per CLAUDE.md the milestone ends after two honest failed attempts. Causes both critics name: halls lit too evenly and too bright (the dark gaps were lost), flat corners and trims, long stretches of identical corridor between the set pieces, the figure never comes close. Those roll into the next loops alongside M3 (sound), which Stewart asked to continue into.
