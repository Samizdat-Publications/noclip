# Handoff: session 02 to 03 (10/02/2026)

## State in one paragraph
The game now plays an infinite, generated Level 0 instead of the 30 x 30 m hero slice. Level0Gen builds 24 x 24 m chunks from the world seed: BSP rooms on a 1.2 m module grid, corridors, pillar halls (some with cross-shaped columns), free-standing L/T partitions and wall fins, dark rooms, and generation-loss splices (chair pushed into a wall, looped chairs, a chair standing upside down on the ceiling, a troffer on a wall or set into the floor, stairs into the ceiling, sheared wallpaper). Chunk edges are hashed so neighbors always agree and every edge has a gap. "Highways" are long straight halls through many chunks with one global line of lights (the vanishing-point hall from Stewart's art direction); the run starts looking down one. On some highways a four-chunk run is built from identical sealed copies, and you are silently moved back one copy until you look back or walk back (the loop corridor). Raising the camcorder down a long view can show a tall faceless figure standing under a light far down the hall, visible only on tape (render layer 11), while the panel above it stutters to the naked eye. Fourteen graffiti decals from "earlier lost people" (Gemini image model) carry the story and fair hints (TURN AROUND before a loop, LOOK THROUGH IT near the start, COPY 31 tally marks inside the loop). Lighting was reworked for the M1 gate (panels slid clear of walls, pooled cones, ceiling glow field, darker fill, firmer shadows, readable exit signs, damp carpet with soft panel reflections), and the camcorder is now a physical model lifted to your eye. M1 closed after two failed gate attempts (D019); M2 is well under way.

## Playable now (exact run command)
- Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip` (the infinite level). Controls: WASD, mouse, Shift sprint, Ctrl crouch, hold right mouse for the camcorder, F3 performance overlay, Esc pause (Q quits).
- Or: `godot --path game`; add `-- --seed=N` to reproduce, `-- --autoplay` to watch the bot, `-- --hero` for the S01 hero slice, `-- --log-stream` to log chunk streaming, the loop and positions, `-- --tape-always` to force the tape figure.
- Review capture: `python tools/capture/capture.py` (about 14 minutes, random seed, 120 s run, the level picks its own focus shots).
- Fast checks: `python tools/gdcheck.py` (scripts compile and run), `godot_console --headless --path game --script res://scripts/tests_gen_determinism.gd` (generator determinism and shared edges).

## Done this session (each with commit hash and evidence)
- M1 gate fixes L021 to L029 (84cf7cc, 2729a89): lighting (D013, progress/0038 to 0045), stairs and chair splices (D014, 0046 to 0047), camcorder viewmodel (pipeline/blender/build_camcorder.py, 0039, 0048), exit glow, damp carpet, loudness -26.5 to -19.9 LUFS (capture log).
- M1 gate attempt 2 (96a4c26): 007_claude_opus_gate.md (Lighting 6, Atmosphere 5) and 007_gemini.md (4 / 6). Not passed; D019 closes M1 and rolls the causes into M2.
- Found why S01 QA and the 007 packet measured low performance: a stuck S01 perfprobe Godot had been rendering since 8:17 PM (killed), plus an unrelated Blender render on the GPU. perfprobe now always passes --quit-after.
- M2 (96a4c26, 2ea5e51, 9200e2f, 631ea3f): Level0Gen, Level0Chunk (the old hero builder, layout-driven, built in nine steps), Level0World (streaming within 40 m, freeing beyond 58 m, one build step per frame, cross-chunk bot paths), FixturePool (112 lights and the hum lent to the nearest panels), Level0Director, highways, loop corridor (D017), tape-only figure (D018), graffiti (14 decals, $0.96 for 21 Gemini image calls, pipeline/textures/build_graffiti.py), layout language (D016), auto focus shots, prop cache. Evidence: progress/0051 to 0060; generator test PASS; chunk build steps mostly under 10 ms but with occasional 16 to 24 ms spikes (QA, seed 777); loop log in the QA run: repeats at 86, 101, 127 and 163 s, released at 168 s; tape figure pair progress/0055.
- Critic loop on the generated level (008): Claude First 6, Lighting 6, Shadows 6, Materials 6, Atmosphere 6, Camera 7, Surreal 5, Monster 6, Pace 5, Perf 6, Keep 6. Gemini: First 6, Lighting 7, Shadows 5, Materials 4, Atmosphere 7, Camera 6, Surreal 8, Monster 3, Sound 5, Pace 7, Perf 4, Keep 6 (first time Lighting and Atmosphere reach 7 on either critic). Perf at 2560x1440 on the RTX 5070 Ti Laptop GPU: 75.4 fps average and 56.6 fps 1% low in the capture run (review/archive/builds/20261002-004334-9200e2f/perf.json); the QA auditor re-probe gave 68.9 / 52.4 (26 s, GPU idle, 74 C). Both clear 60 / 50, the 1% low only just.

## Not done / known broken (be blunt)
- The loop jump has not been verified on video. The frame-diff probe was inconclusive (it reads alternating viewport buffers). Temporal effects (TAA history, fog reprojection, SDFGI cascade scroll) may show for a frame or two. Fog reprojection is reset for two frames at the jump. If it shows, switch to moving the world instead of the camera (D017 fallback).
- In capture 008 the bot reached the loop entrance and turned back, so the critics never saw a repeat. The bot needs a nudge to commit to a hall.
- Dead rooms can still read nearly black from inside (L045). The layout-language change (cross columns, partitions, fins; 631ea3f) was rendered once (progress/0060) but not critic-reviewed. Cross-shaped columns collide as their full square.
- Streaming hitches: some chunk build steps take 16 to 24 ms (a dropped frame); split the first geometry step and the props/decals steps further.
- The bot explores slowly (3 chunk changes in 15000 frames on seed 777): it commits to halls and loops, rarely branches off.
- One yellow everywhere (L039). The tape figure is a stiff mannequin (L040). Blank walls (L041). Evenly filled lit rooms (L042).
- Not built yet: portals and Seams (exits), overlapping spaces, unobserved rearrangement, impossible stairs, the four-right-turns loop, scale-error rooms, chunk-corner wall posts. Bot navigation is a per-chunk grid plus a chunk-graph route, not a navmesh.
- Graffiti text: "DON'T TRUST THE LIGHTS" kept its apostrophe; "R WAS HERE" lost its period.
- 27 invalid-UID warnings at launch (harmless). Sound is still S01-level (M3).

## Critic: latest scores and top open LEDGER items
| Loop | Build | Critic | First | Light | Shadow | Mater. | Atmos. | Camera | Surreal | Monster | Sound | Pace | Perf | Keep |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4 gate (S01) | 212858 hero | Claude Opus | 6 | 6 | 6 | 5 | 6 | 7 | 5 | n/a | n/a | 4 | 6 | 5 |
| 4 gate (S01) | 212858 hero | Gemini | 4 | 3 | 2 | 3 | 4 | 5 | 4 | n/a | 4 | 4 | 2 | 3 |
| 5 gate 2 (S02) | 225950 hero | Claude Opus | 6 | 6 | 5 | 7 | 5 | 6 | 5 | n/a | n/a | 4 | 5 | 5 |
| 5 gate 2 (S02) | 225950 hero | Gemini | 4 | 4 | 3 | 4 | 6 | 6 | 5 | n/a | n/a | 5 | 3 | 4 |
| 6 (S02) | 004334 generated | Claude | 6 | 6 | 6 | 6 | 6 | 7 | 5 | 6 | n/a | 5 | 6 | 6 |
| 6 (S02) | 004334 generated | Gemini | 6 | 7 | 5 | 4 | 7 | 6 | 8 | 3 | 5 | 7 | 4 | 6 |

Top open items: L040 and L046 (the tape figure reads as a mannequin: Gemini Monster 3), L047 (dry footsteps and carpet), L048 (camcorder lift too quick to register on video), L031 (camcorder reveals: started with the figure; Seams next), L039 palette, L040 figure, L041 walls, L042 lit rooms, L043 loop legibility, L045 crushed blacks. Protected: the long hall with receding panels and fog, the camcorder overlay, the tape figure idea, the dark dead-tube hall, the column room, chalk graffiti, wallpaper and carpet up close, the red exit sign, stained ceiling tiles.

## qa-auditor result (pass/fail per claim)
qa-auditor ran every check itself (logs in review/archive/qa/). GPU idle before measuring.
1. Boots into the generated level, `--hero` still works, no script errors: PASS.
2. gdcheck (both modes): PASS (note: only 40 headless frames, not a full runtime check).
3. Generator determinism and shared edges: PASS.
4. Streaming: PARTIAL. Crosses chunks, but the claimed 9 ms max step was false: spikes of 17.9 to 24 ms. Recorded under "Not done".
5. Loop corridor: PASS (repeats from 86 s, released at 168 s after 4 repeats; wording corrected).
6. Tape-only figure only on tape: PASS (code and progress/0055 checked).
7. Graffiti: PARTIAL. Files, manifest and --process-only are fine; the cost is $0.96 not $1.11 (corrected).
8. Gate attempt 2 records: PASS.
9. Performance: PASS as quoted (75.4 / 56.6); the re-probe gave 68.9 / 52.4 (both stated above).
10. Progress pictures 0038 to 0060 with S02 rows: PASS.
11. No secrets: PASS.
12. Working tree committed: PASS. A spend row mislabeled S03 was fixed: tools/critic_gemini/critic.py takes the session number from HANDOFF.md, so after the handoff is rewritten it reads the next session. Run end-of-session critiques before rewriting HANDOFF.

## Next milestone and the first 3 concrete steps
Continue M2 (effort xhigh): exit = a 10 minute bot walk with no seams, hitches or pops, critic Surreal 7+, perf held.
1. Verify and harden the loop: capture the Movie Maker frames around a "[loop] repeat" (the capture log has the time) and judge them by eye; if the jump shows, move the world instead of the camera. Make the bot commit to a hall it enters, so captures include a repeat.
2. Tape-only Seams: exits drawn only on tape (render layer 11), walkable through the wall, leading to a portal or a new region; then one more toolkit piece (the four-right-turns loop or a scale-error room whose ceiling is three times too high).
3. Fix L039 to L045 (palette accents, figure motion and placement, wall detail, uneven lit rooms, no fully black rooms), then a critic loop on the generated level.

## Gotchas learned (engine quirks, API quirks, paths, Windows issues)
- New `class_name` scripts are unknown until `godot --headless --path game --import` runs (lookdev.py and gdcheck.py do it).
- Node3D already has `translate()`; a method with that name in a Node3D subclass fails to compile.
- GDScript cannot infer a type from an untyped Array element (`var x := arr[i]`); write `var x: float = arr[i]`.
- A Godot run without --quit-after can hang for hours and eat the GPU: check `nvidia-smi` before any perf run; other projects' Blender renders may also be running.
- `get_viewport().get_texture().get_image()` in `_process` returns an older frame; consecutive grabs alternate buffers.
- Movie Maker PNG output at 720p runs at about 1 to 2 fps; prefer capture-director stills or the AVI.
- SDFGI voxelizes only when a cascade scrolls; with min cell 0.1 and 3 cascades its reach is about 26 m, so stream chunks in before 26 m (LOAD_R 40).
- Bash heredocs mangle backslashes: write patch scripts to the scratchpad and run them.
- The critic guard still blocks the critic's hand-back; always run tools/critic_extract.py.
- Gemini once claimed the clip had no audio (it does; ffprobe shows AAC).
- AStarGrid2D.fill_solid_region / fill_weight_scale_region are far faster than per-cell loops.

## Decisions made (links to DECISIONS.md entries)
D013 fixture lighting, D014 deliberate splices, D015 infinite Level 0 and streaming, D016 layout language from Stewart's reference, D017 the loop corridor, D018 tape-only layer, D019 M1 closed after two failed gate attempts.
