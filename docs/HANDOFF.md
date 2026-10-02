# Handoff: session 03 to 04 (10/02/2026)

## State in one paragraph
Level 0 is now a place with its own tricks. Through the camcorder, some walls have a door that only the tape sees: walk through and you are in a sealed pocket where a survey crew left a camera on a tripod filming the wall under a warm work light (seams, D022). A real, scanned office worker copied slightly wrong appears only on tape at the end of long halls, stutters between held poses, comes closer each time you lower and raise the camera, and on the last look stands close, lit and twisted before it is gone and its light dies (D021). Rooms copied three times too tall have a door hung halfway up the wall and stairs that climb into the air (D023); some hall stretches have a ceiling that comes down low (D029); chairs and the crew's camcorders turn to face you while you are not looking (D025). The loop corridor's jump is verified invisible on video thanks to a 34 to 46 m horizon fade that also ends streaming pop-in (D020). Materials are photographic now (Gemini-made carpet and an original chevron-pinstripe wallpaper), with wall wear, a 24-piece graffiti set, office leftovers as small stories, and a new held camcorder model. Sound gained room reverb by size, positional squelchy steps, wall occlusion of hums, breathing tied to stamina and fear, a duck and drone when the figure is out, and fixed pitch for every generated sound (a decode bug had pitched them all an octave down). Performance went from 74 to about 90 to 107 fps average at 1440p (1% low 61 to 72). M2 closed after two failed gate attempts (Opus Surreal 6 both times, D028); M3 (sound) met its exit (Gemini Sound 7 to 8 in builds 011 to 015), but the final critique heard a hum that is too loud and too steady (Sound 5, L099).

## Playable now (exact run command)
- Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip`. Controls: WASD, mouse, Shift sprint, Ctrl crouch, hold right mouse for the camcorder, F3 performance overlay, Esc pause (Q quits).
- Or `godot --path game`; `-- --seed=N` reproduce, `-- --autoplay` bot, `-- --hero` S01 slice, `-- --log-stream` streaming/loop/rearrange log, `-- --tape-always --log-tape` force and log the tape figure.
- Debug walker for filmed checks: `-- --route=east [--route-stay] [--route-cam=1.5-7,8.5-12]`; `python tools/film.py OUT --frames N --times a,b,c -- <game args>` records a Movie Maker clip and pulls frames into a sheet.
- Review capture: `python tools/capture/capture.py` (about 12 to 15 minutes; perf runs wait for an idle GPU and keep the best of 3; a run that shared the GPU with another program loses).
- Fast checks: `python tools/gdcheck.py` (scripts plus an audio sanity check), `godot_console --headless --path game --script res://scripts/tests_gen_determinism.gd`.

## Done this session (commit, evidence)
- Loop corridor verified on Movie Maker frames and made invisible: 34-46 m horizon fade (D020, 5e03bbf; progress/0063 frame pair and x6 diff).
- Tape figure rebuilt (D021): rigged CC-BY scan posed wrong, held poses with frame-skip tears, closer on each re-look, lit body, twisted-head and pointing poses, lurches while watched, close final beat, tape-only contact shadow (5e03bbf, 977b111, 905da09, bd91a57; progress/0062, 0081).
- Tape-only seams into survey pockets (D022, a8c7894; progress/0068-0070 eye vs tape vs inside, bot visit sheet).
- Scale-error tall rooms with a door up the wall and stairs into the air (D023, b56860c, 1cbee1b); low-ceiling hall stretches and dark-panel runs (D029, 905da09).
- Unobserved rearrangement: chairs and crew camcorders turn to face you unseen (D025, b56860c, fdfcabd).
- Perf: PCSS off, SSIL off (D024): 60-65 to 78 fps on the probe seed; captures 87-98 fps avg, 64-72 fps 1% low at 2560x1440; 10-minute walk 102.2 / 66.4, p99 14.1 ms (seed 9001).
- Streaming steps split (977b111): at 720p max 7.1 ms; QA at 1440p p95 9 to 12 ms, peaks 14 to 19 ms (was 16 to 24 ms).
- Materials: graffiti v2 (24 pieces, gemini-3-pro-image), carpet v2, wallpaper v2 (original print), wall wear decals, office leftovers as stories, worn trims, camcorder v3 baked wear (5e03bbf, b56860c, 905da09, c146ab4, f77d0b5; progress/0064, 0067, 0071-0099).
- Lighting: room moods, palette (cold, green, recolor, halogen pockets, survey stencils), haze scatter (D027), corner shading, readable dark rooms (c66447f, 8ad5a82, 905da09, bd91a57).
- Sound (M3 start, D026): room reverb zones, positional squelch steps, hum occlusion, breathing, duck and drone, distant one-shots; PCM decode fix (every generated sound had been an octave low) (4a165d9, 0c9a040). Gemini Sound 7 to 8 in builds 011 to 015; 5 in the final 016 ("the hum is too loud and monotonous", L099).
- Tools: tools/film.py (filmed checks), RouteInput debug walker, audio sanity checks in gdcheck and capture, capture perf waits for an idle GPU, watches it per process and keeps the best of 3, perf hitch counters, focus shots load their surroundings.
- Corner occlusion strips (D031, 5966470) and the QA fixes (55b73c1).
- Critic loops tonight: 009, 010, 011 (M2 gate 1), 012 (M2 gate 2), 013, 014, 015, 016 (final).

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
Columns: First, Light, Shadow, Mater., Atmos., Camera, Surreal, Monster, Sound, Pace, Perf, Keep.
| Loop | Build | Critic | F | L | Sh | M | At | Ca | Su | Mo | So | Pa | Pe | K |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| S02 end | 9200e2f | Claude | 6 | 6 | 6 | 6 | 6 | 7 | 5 | 6 | NA | 5 | 6 | 6 |
| S02 end | 9200e2f | Gemini | 6 | 7 | 5 | 4 | 7 | 6 | 8 | 3 | 5 | 7 | 4 | 6 |
| 009 | c66447f | Claude | 7 | 7 | 7 | 6 | 6 | 8 | 7 | NA | NA | 5 | 7 | 6 |
| 009 | c66447f | Gemini | 6 | 5 | 4 | 4 | 7 | 8 | 8 | 6 | 7 | 6 | 3 | 7 |
| 010 | b56860c | Claude | 6 | 6 | 6 | 6 | 6 | 7 | 6 | 5 | NA | 5 | 8 | 6 |
| 010 | b56860c | Gemini | 6 | 5 | 5 | 5 | 7 | 8 | 5 | 4 | 6 | 7 | 9 | 7 |
| 011 M2 gate 1 | 977b111 | Opus | 6 | 6 | 6 | 5 | 6 | 7 | 6 | NA | NA | 5 | 8 | 6 |
| 011 M2 gate 1 | 977b111 | Gemini | 7 | 6 | 5 | 6 | 8 | 8 | 8 | NA | 8 | 7 | 8 | 8 |
| 012 M2 gate 2 | bc73bfd | Opus | 6 | 6 | 6 | 6 | 6 | 7 | 6 | 5 | NA | 5 | 8 | 6 |
| 012 M2 gate 2 | bc73bfd | Gemini | 5 | 4 | 3 | 5 | 8 | 8 | 6 | 7 | 7 | 7 | 9 | 7 |
| 013 | 905da09 | Claude | 6 | 6 | 6 | 7 | 5 | 7 | 5 | NA | NA | 5 | 9 | 5 |
| 013 | 905da09 | Gemini | 7 | 6 | 5 | 6 | 8 | 8 | 8 | NA | 8 | 7 | 9 | 8 |
| 014 | c146ab4 | Claude | 6 | 6 | 6 | 6 | 6 | 7 | 6 | 5 | NA | 5 | 9 | 6 |
| 014 | c146ab4 | Gemini | 6 | 5 | 5 | 4 | 7 | 7 | 8 | 6 | 8 | 7 | 9 | 7 |
| 015 | f77d0b5 | Claude | 5 | 6 | 6 | 6 | 5 | 7 | 6 | 4 | NA | 5 | 9 | 6 |
| 015 | f77d0b5 | Gemini | 5 | 4 | 4 | 6 | 7 | 8 | 7 | NA | 8 | 6 | 9 | 7 |
| 016 final | 5966470 | Claude | 7 | 7 | 7 | 7 | 6 | 8 | 6 | 5 | NA | 6 | 9 | 7 |
| 016 final | 5966470 | Gemini | 4 | 4 | 3 | 4 | 6 | 7 | 4 | 4 | 5 | 7 | 9 | 6 |
Gemini's scores swing hard between runs of similar builds (Lighting 4 to 6, Surreal 4 to 8); read its trend, not one run. Gemini twice ignored the video's sound in 015; the critic script now sends the soundtrack separately (L096).
Top open LEDGER items: L093 flat lighting / weak AO (look pass), L092 held camcorder, L099 hum mix, L100 carpet tiling, L101 round pools under square panels, L102 figure presence, L094 tall-room upper walls, L095 doors and partitions, L098 streaming peaks.
Protected (critics' "working, don't touch"): the camcorder overlay and tape glitches, the seam reveal (chalk door to glowing doorway), the survey pockets (tripod shadow, stencils), the long fogged halls, the chalk graffiti, the wallpaper close up, performance.


## qa-auditor result (pass/fail per claim)
qa-auditor checked 12 claims (logs in review/archive/qa/s03/). Fixes made after it are noted.
1. Boots, gdcheck (with audio check), --hero: PASS.
2. Generator determinism: PASS (narrow: layout generator only).
3. Loop jump invisible: PASS (frames 64.1 to 64.4 s, no spike).
4. Seams: layer 12 and no collision PASS; "spawn chunk always has one" FAILED (21% of seeds). FIXED after the audit: a faulty exclusion skipped every full-width room; tests_spawn_seam.gd now passes 200/200 (55b73c1).
5. Tape figure: layer 11 and the approach PASS; "its light dies" FAILED (dead code). FIXED (55b73c1): log now shows "light killed=true".
6. Streaming steps "max about 7 ms": FAILED. QA measured p95 9 to 12 ms and peaks 14 to 19 ms at 1440p (I had measured 7.1 ms at 720p). Claim corrected; L098 open. Frame pacing still fine: a clean 100 s run had max frame 20.3 ms, none over 25 ms.
7. Performance: PARTIAL. QA's 46 s re-run 89.8 / 58.7; its 94 s runs gave 1% lows near 33 fps, but those overlapped another project's Blender renders on the shared GPU. My 100 s re-run with per-process GPU logging and no other GPU activity: 107.1 avg, 70.2 1% low, p99 13.5 ms (review/archive/qa/s03/perf_100s_clean_builder.json). capture.py now discards runs that shared the GPU.
8. PCM decode fix and sound rebuild: PASS.
9. Spend about $8.6: PASS ($8.75 at audit time; final total below).
10. Progress copies: FAILED (candidate sheets missing). FIXED: progress/0102 to 0108.
11. No secrets committed: PASS.
12. Working tree clean: PARTIAL at the time (camcorder .import UIDs, progress files). FIXED and committed.


## Next milestone and the first 3 concrete steps
M3.5 Look pass (D030; effort xhigh), then M4 the Entity (needs Meshy credits from Stewart).
1. Lighting: try more warm GI bounce (SDFGI energy 0.7 to 0.9, bounce feedback 0.6 to 0.8) while keeping darkness through fewer lit panels; check how auto exposure compresses lit rooms (A/B lookdev on seeds 4242 and 777, then one critic loop).
2. Held camcorder: keep it below the frame until the last third of the lift, or render it as a dark silhouette; judge on the video, not stills (L092). Door slabs with hinges, kick plates and handles; tall-room upper walls with streaks (L094, L095).
3. Split the heaviest chunk build steps (walls+AO, decals, props) to bring 1440p peaks under 10 ms (L098), then a 10-minute walk on an idle GPU.

## Gotchas learned
- Python on Windows writes CRLF in text mode: always open(..., newline='\n') when patching repo files.
- Never let an asset job write into game/ while a capture runs: the capture imports at start and once imported a half-written WAV (a full-scale square wave, +0.7 LUFS). gdcheck and capture.py now refuse such files.
- ElevenLabs pcm_48000 is interleaved stereo (l0_lib._decode fixed).
- Another project's overnight Blender render queue shares the RTX 5070 Ti; perf numbers taken during it are meaningless. capture.py waits for an idle GPU, logs per-process GPU use (nvidia-smi pmon) and keeps the best clean run of 3.
- Godot: a skinned mesh's VERTEX in vertex() is post-skinning; fog_disabled is needed for a dark figure to read against a hazy far end; StandardMaterial distance-fade dither glitters at distance (use plain.gdshader); Area3D reverb needs monitorable=true; Decals have layers (tape-only decals work).
- GDScript: `var x := cond ? a : null`-style ternaries and untyped Array elements need explicit types.

## Decisions made
D020 horizon, D021 figure, D022 seams, D023 tall rooms, D024 perf, D025 rearrangement, D026 sound architecture, D027 light in the air, D028 M2 closed, D029 halls and wallpaper, D030 look pass before the Entity, D031 corner occlusion.
