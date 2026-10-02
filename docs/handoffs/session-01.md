# Handoff: session 01 to 02 (10/01/2026)

## State in one paragraph
Milestone 1 (foundation and look-dev) is built. The engine is Godot 4.7.2 Forward+, chosen by a blind bake-off against a three.js WebGPU version of the same scene (D011). The Level 0 hero slice is a fixed 30 x 30 m layout (game/data/level0_hero.json) built entirely from code: wallpaper walls with world-space water damage, damp carpet with wet patches and one soaked stretch, a drop ceiling with stained, sagging, missing and fallen tiles, about 110 fluorescent troffers as shadowed spot lights with real failure patterns (starter struggle, pulse, dropout, dead with glowing ends), SDFGI bounce, SSAO/SSIL, volumetric haze, AgX, slow auto exposure, lens grain and vignette, and a 1990s camcorder view (hold right mouse). Story and "generation loss" details: chalk marks, a wet footprint trail that ends at a door that does not open, a red exit sign, props (procedural and Sketchfab CC-BY), stairs that climb into the ceiling, a ceiling troffer installed sideways on a wall, a chair cut by a wall, three identical chairs in a row, a slipped wallpaper band, a corridor of cold mismatched tubes. One dread beat per run: the lights ahead die one by one toward you and later stutter back. An autoplay bot plays like a person; one command captures a full review packet (video with sound, stills, motion sheets, perf). The creative direction now has its own twist (generation loss of recordings, D009) and an ambiguous organization (Halden Duplicating, D010), both in VISION.

## Playable now (exact run command)
- Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip`. Controls: WASD, mouse, Shift sprint, Ctrl crouch, hold right mouse for the camcorder, F3 performance overlay, Esc pause (Q quits).
- Or: `godot --path game` (Godot from `%LOCALAPPDATA%\Microsoft\WinGet\Links`). Add `-- --seed=N` to reproduce a level, `-- --autoplay` to watch the bot.
- Review capture: `python tools/capture/capture.py` (about 10 minutes, random seed, fills review/inbox).

## Done this session (each with commit hash and evidence)
- Environment: Godot 4.7.2, FFmpeg 9.0.2 installed via winget; Blender 5.1.2, git, LFS, Node 24, Python 3.14, gh present. Godot renders on the NVIDIA RTX 5070 Ti Laptop GPU (Vulkan) (log line in every run). Commit c3947e9.
- Repo: git + LFS, private GitHub repo Samizdat-Publications/noclip, layout per CLAUDE.md. Commit c3947e9.
- Critic guard proven: reads of CLAUDE.md, VISION.md and repo globs blocked (review/archive/S01_guard_test.md). The guard also blocks the critic's hand-back, so reviews are recovered with tools/critic_extract.py (D004).
- Godot hero slice, player controller, autoplay bot, camcorder, capture harness: commits 96a370f onward. Evidence: progress/0004 to 0035.
- Engine bake-off: Godot vs three.js, blind, same scene and camera path: review/critiques/003_claude_bakeoff_A.md, 004_claude_bakeoff_B.md, progress/0026, D011. Commit 6df8853.
- Critic loops on the hero slice, with scores in review/scores.csv and every issue triaged in review/LEDGER.md (L001 to L030). The gate build is commit 07fc162.
  - 001 (loop 1).
  - 002 (loop 2).
  - 005 (loop 3).
  - 006 (loop 4, the milestone gate): 006_claude_opus_gate.md with the Opus critic, and 006_gemini.md, the first video-and-sound critique.
- Performance went from 36 fps to 56 to 72 fps average at 1440p High through profiling (D007, D012).
  - The gate capture measured 71.6 fps average and 52.8 fps 1% low (review/archive/builds/20261001-212858-07fc162/perf.json).
  - The QA auditor measured 56 to 58 average and 44 to 46 1% low while the GPU was contended.
- Progress pictures: every generated image has a numbered copy in progress/ (Stewart's rule, D005), 35+ so far, indexed in progress/INDEX.md.
- Assets: procedural textures and story decals (pipeline/textures), sound set (pipeline/audio, ElevenLabs about $0.09), procedural Blender props and Sketchfab CC-BY props (pipeline/blender, pipeline/meshes, docs/CREDITS.md).
- Creative: film research (docs/reference/film_2026_research.md), generation-loss twist (D009), Halden Duplicating (D010), The Store section reconstructed in VISION, ROADMAP updated. Commit 0732328.

## Not done / known broken (be blunt)
- **M1 gate not passed.** The milestone needs Lighting and Atmosphere at 7 or higher. Loop 3 reached 7 / 6; the gate review gave 6 / 6 (Opus) and 3 / 4 (Gemini, on video). See LEDGER L021 to L030.
- Performance is 56 to 72 fps average with a 1% low of 44 to 53, depending on GPU load. The target is 60 / 50, so the 1% low is not reliably met. The laptop "Medium" preset and FSR are not set up.
- 27 "invalid UID" warnings appear at launch, from the procedural prop .glb files and their extracted textures. They are harmless but noisy. "Resources still in use" lines appear at exit.
- The Gemini critic ran once, at the very end, after Stewart added the key. It uses gemini-3.1-pro-preview at about $0.08 per run: `python tools/critic_gemini/critic.py review/critiques/NNN_gemini.md`.
- No real non-euclidean spaces yet (M2). The "impossible" things are static set dressing.
- No monster (M4), no store hub (M5), no menus or settings (M5). Reduced-flicker mode exists only as a command-line flag.
- Mirror-like standing water was tried and parked (white blobs); SSR is off (D012).
- AreaLight3D is not used because its shadows draw curved artifacts in 4.7.2 (D006).
- The capture video is 1080p, about 190 MB; the Movie Maker AVI is large (deleted after encoding).
- Audio loudness of the captured mix is about -26.5 LUFS (quiet); not tuned by ear.

## Critic: latest scores and top open LEDGER items
| Loop | Build | Critic | First | Light | Shadow | Mater. | Atmos. | Camera | Surreal | Sound | Perf | Keep |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 185732 | Claude | 6 | 6 | 5 | 6 | 5 | 6 | 4 | n/a | 4 | 5 |
| 2 | 195213 | Claude | 6 | 6 | 6 | 6 | 5 | 7 | 4 | n/a | 5 | 5 |
| 3 | 210709 | Claude | 6 | 7 | 6 | 6 | 6 | 7 | 5 | n/a | 5 | 6 |
| 4 gate | 212858 | Claude Opus | 6 | 6 | 6 | 5 | 6 | 7 | 5 | n/a | 6 | 5 |
| 4 gate | 212858 | Gemini (video) | 4 | 3 | 2 | 3 | 4 | 5 | 4 | 4 | 2 | 3 |

Bake-off (camcorder off, early build), First/Light/Shadow/Materials/Atmosphere: Godot 5/6/5/6/4, three.js 5/5/4/5/4.

**M1 gate NOT passed** (needs Lighting and Atmosphere 7+). One honest gate attempt failed; the reasons are L021 to L030.

Top open items (review/LEDGER.md):
- L021: fixtures light walls with sideways spotlight arcs, and the scene looks flat in motion (biggest).
- L022: the impossible stairs look unfinished. Build them from wallpaper and carpet.
- L023: the chairs read as broken assets.
- L024: the wide FOV and camera tilt stretch the walls.
- L025: the camcorder needs a raise and lower animation.
- L026: the exit glow is too saturated.
- L027: the carpet should look damp without the blobs.
- L028: 1% lows.

Protected (do not break):
- the camcorder look
- the red exit beat
- the ceiling tiles and stains
- the footprints and chalk
- the three identical chairs
- the dark room seen from a lit hall
- the pillar hall's scale

## qa-auditor result (pass/fail per claim)
1. **Launch without script errors:** PASS. The .bat launches the game for a human; it does not run the autoplay command.
2. **One-command packet:** PASS on the current inbox contents. The auditor did not re-run the capture, by instruction.
3. **Determinism:** PASS. Seed 777 run twice: the capture logs are byte-identical and frames differ by under 0.02/255 on average.
4. **Performance:** FAIL as first claimed. The auditor measured 56 to 58 fps average and 44 to 46 1% low, with other apps on the GPU, against 71.6 / 52.8 in the capture. The wording is corrected under "Not done".
5. **Critic guard:** PARTIAL. The evidence file is present, but the guard was not re-tested live.
6. **Bake-off:** PASS.
7. **Three critic loops:** PASS after saving 006, which was still missing when the audit ran.
8. **Progress pictures:** PASS.
9. **Secrets:** PASS.
10. **LFS and push:** PASS after the final push. HEAD was 1 commit ahead at audit time.
11. **Gemini honesty:** PASS, now superseded because Stewart added the key and it ran.
12. **Reproducible assets and credits:** PASS.
13. **Spend log:** PASS.

## Next milestone and the first 3 concrete steps
Session 2 finishes the M1 gate first, as a short focused pass, then starts M2: Infinite Level 0 and the non-euclidean toolkit (effort xhigh).
0. Do the M1 gate fixes in this order:
   - L021: how the fixtures light the walls (the biggest fix).
   - L024: FOV 70 and no camera roll.
   - L022: build the stairs from the real wall and floor materials.
   - L023: redo the chair splices with the Sketchfab chair.
   - L025: add the camcorder raise and lower animation.
   - L026 and L027.

   Then re-run the gate with the Opus critic plus Gemini. The target is Lighting and Atmosphere at 7.
1. Turn the hero-slice builder (scripts/level0/level0_hero.gd) into a seeded chunk generator: 30 x 30 m chunks on a grid, a room grammar that produces corridors, halls, dead-light zones, landmarks and generation-loss splice errors, with chunk streaming and SDFGI kept stable while streaming.
2. Build the first two toolkit pieces with seamless crossings: a portal doorway (render-to-texture with oblique near plane, recursion 1) and the corridor loop that repeats until you turn around. The bot must path through them.
3. Run the critic loop with a generated level (not the hero slice) and keep Lighting at 7 or higher while adding "Surreal" wow.

## Gotchas learned (engine quirks, API quirks, paths, Windows issues)
- The critic guard blocks SubagentHandback; always run tools/critic_extract.py after a critic run.
- A GDScript parse error makes main.gd fail to compile and the game then idles forever instead of quitting: always pass --quit-after to Godot runs in tools.
- Godot 4.7.2 AreaLight3D shadows draw curved projection artifacts; use SpotLight3D (D006).
- The 16-bit positional shadow atlas causes stepped bands on walls at grazing angles; use 32-bit (D007).
- StandardMaterial3D emission texture: the default ADD operator adds the emission color on top (a white EXIT sign); use EMISSION_OP_MULTIPLY.
- A 2x4 troffer spans two ceiling tiles; do not run a T-bar across its middle.
- Movie Maker: the capture director saves get_viewport().get_texture(), which is the previous frame (render_frame = frame - 1).
- Perf runs are invalid when anything else uses the GPU (other agents, Blender bakes, browser renders). Keep the GPU idle.
- The Bash tool can mangle backslash escapes in Python heredocs (\b, \U); write patch scripts to a file instead.
- capture.py --extra args go to the movie run; --track and --dump-scene are filtered out of the perf run.
- .env: GEMINI_API_KEY and OPENAI_API_KEY are empty; ELEVENLABS_API_KEY comes from the Windows user environment; Meshy had 3 credits; SKETCHFAB_TOKEN works.
- Switching the window to borderless keeps the old outer size; set get_window().size explicitly (main.gd).
- three.js WebGPU: when rendering many frames inside one script call, advance renderer._nodes.nodeFrame each frame or temporal passes reuse the first frame (spike/threejs/README.md).

## Decisions made (links to DECISIONS.md entries)
D001 project path, D002 tool paths, D003 hardware, D004 critic extraction, D005 progress pictures, D006 spot lights not area lights, D007 lighting budget, D008 props sources, D009 generation loss, D010 Halden Duplicating, D011 engine Godot, D012 SSR off.
