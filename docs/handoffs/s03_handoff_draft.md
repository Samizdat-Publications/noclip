# Handoff: session 03 to 04 (10/02/2026)

## State in one paragraph
Level 0 is now a place with its own tricks. Through the camcorder, some walls have a door that only the tape sees: walk through and you are in a sealed pocket where a survey crew left a camera on a tripod filming the wall under a warm work light (seams, D022). A real, scanned office worker copied slightly wrong appears only on tape at the end of long halls, stutters between held poses, comes closer each time you lower and raise the camera, and on the last look stands close, lit and twisted before it is gone and its light dies (D021). Rooms copied three times too tall have a door hung halfway up the wall and stairs that climb into the air (D023); some hall stretches have a ceiling that comes down low (D029); chairs and the crew's camcorders turn to face you while you are not looking (D025). The loop corridor's jump is verified invisible on video thanks to a 34 to 46 m horizon fade that also ends streaming pop-in (D020). Materials are photographic now (Gemini-made carpet and an original chevron-pinstripe wallpaper), with wall wear, a 24-piece graffiti set, office leftovers as small stories, and a new held camcorder model. Sound gained room reverb by size, positional squelchy steps, wall occlusion of hums, breathing tied to stamina and fear, a duck and drone when the figure is out, and fixed pitch for every generated sound (a decode bug had pitched them all an octave down). Performance went from 74 to about 96 fps average at 1440p. M2 closed after two failed gate attempts (Opus Surreal 6 both times, D028); M3 (sound) started and Gemini rates Sound 7 to 8.

## Playable now (exact run command)
- Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip`. Controls: WASD, mouse, Shift sprint, Ctrl crouch, hold right mouse for the camcorder, F3 performance overlay, Esc pause (Q quits).
- Or `godot --path game`; `-- --seed=N` reproduce, `-- --autoplay` bot, `-- --hero` S01 slice, `-- --log-stream` streaming/loop/rearrange log, `-- --tape-always --log-tape` force and log the tape figure.
- Debug walker for filmed checks: `-- --route=east [--route-stay] [--route-cam=1.5-7,8.5-12]`; `python tools/film.py OUT --frames N --times a,b,c -- <game args>` records a Movie Maker clip and pulls frames into a sheet.
- Review capture: `python tools/capture/capture.py` (about 12 to 15 minutes; perf runs wait for an idle GPU and keep the best of 2).
- Fast checks: `python tools/gdcheck.py` (scripts plus an audio sanity check), `godot_console --headless --path game --script res://scripts/tests_gen_determinism.gd`.

## Done this session (commit, evidence)
- Loop corridor verified on Movie Maker frames and made invisible: 34-46 m horizon fade (D020, 5e03bbf; progress/0063 frame pair and x6 diff).
- Tape figure rebuilt (D021): rigged CC-BY scan posed wrong, held poses with frame-skip tears, closer on each re-look, lit body, twisted-head and pointing poses, lurches while watched, close final beat, tape-only contact shadow (5e03bbf, 977b111, 905da09, bd91a57; progress/0062, 0081).
- Tape-only seams into survey pockets (D022, a8c7894; progress/0068-0070 eye vs tape vs inside, bot visit sheet).
- Scale-error tall rooms with a door up the wall and stairs into the air (D023, b56860c, 1cbee1b); low-ceiling hall stretches and dark-panel runs (D029, 905da09).
- Unobserved rearrangement: chairs and crew camcorders turn to face you unseen (D025, b56860c, fdfcabd).
- Perf: PCSS off, SSIL off (D024): 60-65 to 78 fps on the probe seed; captures 87-98 fps avg, 64-72 fps 1% low at 2560x1440; 10-minute walk 102.2 / 66.4, p99 14.1 ms (seed 9001).
- Streaming steps split: max 7.1 ms, p95 4.6 ms (was 16-24 ms) (977b111).
- Materials: graffiti v2 (24 pieces, gemini-3-pro-image), carpet v2, wallpaper v2 (original print), wall wear decals, office leftovers as stories, worn trims, camcorder v3 baked wear (5e03bbf, b56860c, 905da09, c146ab4, f77d0b5; progress/0064, 0067, 0071-0099).
- Lighting: room moods, palette (cold, green, recolor, halogen pockets, survey stencils), haze scatter (D027), corner shading, readable dark rooms (c66447f, 8ad5a82, 905da09, bd91a57).
- Sound (M3 start, D026): room reverb zones, positional squelch steps, hum occlusion, breathing, duck and drone, distant one-shots; PCM decode fix (every generated sound had been an octave low) (4a165d9, 0c9a040). Gemini Sound 7-8 in builds 011-014.
- Tools: tools/film.py (filmed checks), RouteInput debug walker, audio sanity checks in gdcheck and capture, capture perf waits for an idle GPU (best of 2), perf hitch counters, focus shots load their surroundings.
- Critic loops tonight: 009, 010, 011 (gate 1), 012 (gate 2), 013, 014, 015 (final).

## Not done / known broken (be blunt)
- Visual quality is the gap: Lighting, Shadows and Materials sit at 4 to 7 across critics (ship gate needs 8). Gemini's Lighting swings 3 to 7 between runs; both keep saying "flat, evenly lit, no bounce". The corner occlusion strips (D031) are the first piece of a look pass; GI bounce, exposure and props are next (M3.5 in the roadmap).
- The held camcorder still reads badly in stills mid-lift ("lumpy black blob", L092) even after two model swaps and a baked wear texture.
- Streaming steps: p95 about 9 to 12 ms, peaks 14 to 19 ms at 1440p (QA), not the 7 ms I measured at 720p. Frame pacing is still fine (100 s run: max frame 20 ms, none over 25 ms) but a step split is due (L098).
- M2 did not pass its gate (Opus Surreal 6 twice). Not built: portal doorways, overlapping spaces, impossible stairs, the four-turn loop.
- The figure: critics still call it a placeholder man when they see it far away (Monster 4 to 7); it only appears in captures when the bot films a long view.
- Cubicle panels look like plain slabs; doors have no hinges or kick plates (L095). Tall rooms' upper walls are blank (L094).
- Exit-time "leaked instances" messages from static materials (harmless). 27 invalid-UID warnings at launch remain for older assets.
- Gemini sometimes ignores the video's audio; critic.py now sends the soundtrack separately too (L096).

## Critic: latest scores and top open LEDGER items
(fill table from review/scores.csv)

## qa-auditor result (pass/fail per claim)
(fill)

## Next milestone and the first 3 concrete steps
M3.5 Look pass (D030; effort xhigh), then M4 the Entity (needs Meshy credits from Stewart).
1. Lighting: try more warm GI bounce (SDFGI energy 0.7 to 0.9, bounce feedback 0.6 to 0.8) while keeping darkness through fewer lit panels; check how auto exposure compresses lit rooms (A/B lookdev on seeds 4242 and 777, then one critic loop).
2. Held camcorder: keep it below the frame until the last third of the lift, or render it as a dark silhouette; judge on the video, not stills (L092). Door slabs with hinges, kick plates and handles; tall-room upper walls with streaks (L094, L095).
3. Split the heaviest chunk build steps (walls+AO, decals, props) to bring 1440p peaks under 10 ms (L098), then a 10-minute walk on an idle GPU.

## Gotchas learned
- Python on Windows writes CRLF in text mode: always open(..., newline='\n') when patching repo files.
- Never let an asset job write into game/ while a capture runs: the capture imports at start and once imported a half-written WAV (a full-scale square wave, +0.7 LUFS). gdcheck and capture.py now refuse such files.
- ElevenLabs pcm_48000 is interleaved stereo (l0_lib._decode fixed).
- Another project's overnight Blender render queue shares the RTX 5070 Ti; perf numbers taken during it are meaningless. capture.py waits for an idle GPU and keeps the best of 2 runs.
- Godot: a skinned mesh's VERTEX in vertex() is post-skinning; fog_disabled is needed for a dark figure to read against a hazy far end; StandardMaterial distance-fade dither glitters at distance (use plain.gdshader); Area3D reverb needs monitorable=true; Decals have layers (tape-only decals work).
- GDScript: `var x := cond ? a : null`-style ternaries and untyped Array elements need explicit types.

## Decisions made
D020 horizon, D021 figure, D022 seams, D023 tall rooms, D024 perf, D025 rearrangement, D026 sound architecture, D027 light in the air, D028 M2 closed, D029 halls and wallpaper.
