# Handoff: session 03 to 04 (10/02/2026)

## State in one paragraph
Level 0 is now a place with its own tricks. Through the camcorder, some walls have a door that only the tape sees: walk through and you are in a sealed pocket where a survey crew left a camera on a tripod filming the wall under a warm work light (seams, D022). A real, scanned office worker copied slightly wrong appears only on tape at the end of long halls, stutters between held poses, comes closer each time you lower and raise the camera, and on the last look stands close, lit and twisted before it is gone and its light dies (D021). Rooms copied three times too tall have a door hung halfway up the wall and stairs that climb into the air (D023); some hall stretches have a ceiling that comes down low (D029); chairs and the crew's camcorders turn to face you while you are not looking (D025). The loop corridor's jump is verified invisible on video thanks to a 34 to 46 m horizon fade that also ends streaming pop-in (D020). Materials are photographic now (Gemini-made carpet and an original chevron-pinstripe wallpaper), with wall wear, a 24-piece graffiti set, office leftovers as small stories, and a new held camcorder model. Sound gained room reverb by size, positional squelchy steps, wall occlusion of hums, breathing tied to stamina and fear, a duck and drone when the figure is out, and fixed pitch for every generated sound (a decode bug had pitched them all an octave down). Performance went from 74 to about 96 fps average at 1440p. M2 closed after two failed gate attempts (Opus Surreal 6 both times, D028); M3 (sound) started and Gemini rates Sound 7 to 8.

## Playable now (exact run command)
- Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip`. Controls: WASD, mouse, Shift sprint, Ctrl crouch, hold right mouse for the camcorder, F3 performance overlay, Esc pause (Q quits).
- Or `godot --path game`; `-- --seed=N` reproduce, `-- --autoplay` bot, `-- --hero` S01 slice, `-- --log-stream` streaming/loop/rearrange log, `-- --tape-always --log-tape` force and log the tape figure.
- Debug walker for filmed checks: `-- --route=east [--route-stay] [--route-cam=1.5-7,8.5-12]`; `python tools/film.py OUT --frames N --times a,b,c -- <game args>` records a Movie Maker clip and pulls frames into a sheet.
- Review capture: `python tools/capture/capture.py` (about 12 to 15 minutes; perf runs wait for an idle GPU and keep the best of 2).
- Fast checks: `python tools/gdcheck.py` (scripts plus an audio sanity check), `godot_console --headless --path game --script res://scripts/tests_gen_determinism.gd`.

## Done this session
(fill from docs/handoffs/s03_running_notes.md and git log; each with commit and evidence)

## Not done / known broken (be blunt)
(fill)

## Critic: latest scores and top open LEDGER items
(fill table from review/scores.csv)

## qa-auditor result (pass/fail per claim)
(fill)

## Next milestone and the first 3 concrete steps
(fill)

## Gotchas learned
- Python on Windows writes CRLF in text mode: always open(..., newline='\n') when patching repo files.
- Never let an asset job write into game/ while a capture runs: the capture imports at start and once imported a half-written WAV (a full-scale square wave, +0.7 LUFS). gdcheck and capture.py now refuse such files.
- ElevenLabs pcm_48000 is interleaved stereo (l0_lib._decode fixed).
- Another project's overnight Blender render queue shares the RTX 5070 Ti; perf numbers taken during it are meaningless. capture.py waits for an idle GPU and keeps the best of 2 runs.
- Godot: a skinned mesh's VERTEX in vertex() is post-skinning; fog_disabled is needed for a dark figure to read against a hazy far end; StandardMaterial distance-fade dither glitters at distance (use plain.gdshader); Area3D reverb needs monitorable=true; Decals have layers (tape-only decals work).
- GDScript: `var x := cond ? a : null`-style ternaries and untyped Array elements need explicit types.

## Decisions made
D020 horizon, D021 figure, D022 seams, D023 tall rooms, D024 perf, D025 rearrangement, D026 sound architecture, D027 light in the air, D028 M2 closed, D029 halls and wallpaper.
