# S03 running notes (builder scratch; folded into HANDOFF.md at session end)

## Done so far (commit: what, evidence)
- 5e03bbf: loop jump verified on Movie Maker frames (tools/film.py, progress/0063) and made invisible with the horizon fade 34-46 m (D020); tape figure rework (D021, progress/0062); wall wear decals (progress/0064); graffiti v2 with gemini-3-pro-image, 24 pieces, picks recorded (progress/0067); field props; figure candidates (0065) and props (0066).
- a8c7894: tape-only seams into survey pockets (D022, progress/0068-0070); bot explores (7 chunk changes in 120 s vs 3 in 500 s), visits seams, re-looks at the figure, keeps walking in loops.
- c66447f: room moods, tints, recolor, exit signs, dead rooms keep a tube, camcorder lift 0.52 s, wet steps.
- Critic loop 1 (009, build 20261002-015916-c66447f): Claude 7/7/7/6/6/8/7/NA/NA/5/7/6, Gemini 6/5/4/4/7/8/8/6/7/6/3/7.
- b56860c: tall rooms (D023), PCSS off + SSIL off (+13 fps, D024), rearrangement (D025), carpet v2, camcorder v2, door trim, contact shadows, wrong pillars, seam rooms lit, cathode spill, S03 sound set.
- Critic loop 2 (010, build 20261002-024249-b56860c, perf 93.2/72.3): Claude 6/6/6/6/6/7/6/5/NA/5/8/6, Gemini 6/5/5/5/7/8/5/4/6/7/9/7.
- 977b111: figure v4 (lit, poses, lurch), streaming steps split (max 7.1 ms, p95 4.6 ms, was 16 ms), focus shots load surroundings, survey camcorders in halls, denser seams/tall rooms.
- 10-minute bot walk (seed 9001, 2560x1440, realtime): 102.2 fps avg, 66.4 fps 1% low, p99 14.1 ms, 61,320 frames, 19 chunk changes, ~60 chunks streamed, loop repeated 8 times (released once), no script errors. Log: scratchpad walk10.log (not kept).
- M2 gate attempt 1 (011, build 20261002-030447-977b111, perf 87.0/63.7): Opus 6/6/6/5/6/7/6/NA/NA/5/8/6; Gemini 7/6/5/6/8/8/8/NA/8/7/8/8. Not passed (Opus Surreal 6).
- 4a165d9: M3 start (D026): reverb zones, positional steps, occlusion, breathing, duck + drone.
- Gate-2 fixes commit (after 4a165d9): trim paint, dark rooms tube + ambient, tall room cues, tints, seam tear, worklight shadow, camcorder smaller, bot films long views.

## Open / next
- Gate attempt 2 capture running (s03-m2-gate2). Then apply patch_seamcross (L068).
- M3 assets job (breath loops, drone, distant one-shots, squish steps) was running; check files exist before relying on them (code tolerates missing files).
- Spend so far: graffiti v2 ~$6.37, carpet v2 ~$0.60, sound ~$0.16 + M3 job, Gemini critic calls ~$0.09 each.

## Audio incident (03:24-03:45)
- Gate-2 capture 20261002-032422-1cbee1b is INVALID: its import step ran while the M3 sound job was still writing WAVs; breath_calm_loop.wav was a full-scale square wave at import time, so the clip measured +0.7 LUFS / +12.9 dBFS, and the job's CPU work dragged the perf run to 61.9/50.5. Rule from now on: no asset job may write into game/ while a capture runs.
- Fixes: gdcheck and capture.py refuse square-wave/DC audio files. l0_lib._decode read ElevenLabs stereo PCM as mono (every generated sound an octave low, twice as long) -> fixed, S01 and S03 sounds rebuilt from cache (0c9a040).
- Clean recapture 20261002-034413-bc73bfd: perf 98.2/68.8, -18.6 LUFS. Gate attempt 2 critiques 012 running.

## After the M2 gate (04:00 onward)
- Gate attempt 2 (012, build 20261002-034413-bc73bfd, perf 98.2/68.8): Opus 6/6/6/6/6/7/6/5/NA/5/8/6; Gemini 5/4/3/5/8/8/6/7/7/7/9/7. M2 closed after two attempts (D028, de1e535). Stewart (mid-session message): keep going until he wakes (~6 h), compact once if needed and continue.
- 8ad5a82 D027 haze scatter/bloom/tighter cones. 905da09 D029: wallpaper v2 (original print), hall dead runs, low-ceiling stretches (ceil_zones), SSAO 4.2/0.68, ambient 0.017, plain.gdshader for trims (no dither glitter), steady dim tube in dark rooms, figure close final beat, lighter glitches.
- Loop 6 capture 20261002-040513-905da09 (seed 73214): frames valid; perf.json CONTAMINATED (props job's Blender preview render at 96% GPU) -> re-measure with the same seed on an idle GPU, replace review/inbox/perf.json and the archive copy, then run critics 013.
- Pending patch (not applied): scratchpad patch_m3c.py = carpet water-bead glints (L081) + camcorder viewmodel materials (L073). Apply AFTER the perf re-measure.
- Props job running: water cooler, filing cabinet, step ladder, mop bucket, cubicle panel, desk, stacked chairs -> place them in rooms/halls to break sameness (L074).
- RULE: never run a capture or perf probe while an asset job renders or writes into game/.
