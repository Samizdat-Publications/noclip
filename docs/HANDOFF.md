# Handoff: session 05 to 06 (10/02/2026)

## State in one paragraph
Session 05 did M3.6 and started M4, in Stewart's order. The look moved toward his reference stills: a cleaner, more saturated mustard paper with the dirt gathered into a few stretches, a cream ceiling that glows from the lit floor, a light grid, brighter panels (D038). The hall behind each storeroom door became its own place: a palette per storeroom (cold white, pale green or yellow), columns painted over the paper, handle-less doors on its walls, its own haze, a sparse grid of stronger panels so the columns throw real shadows, and a far door that shows the lit room beyond with a warm lamp shining through it (D039, D043). Remembered wrong batch 1 is in as learned misunderstandings per block of 3 x 3 chunks (D040). The held camcorder had been built backwards since S03 (the "pistol"); it is turned round and has a flip-out screen (D041). M4: the Occupant is in the game, a figure made of strips of the level's own wallpaper on its Meshy rig, frozen mid-move on every frame skip; it is the tape encounter's body (on tape the gaps between its strips are dropout). The watchers: the tall room's high door stands open while you are not looking, with a papered head and hand in the gap, and a figure stands only at the edge of your sight (D042). It does not hunt yet. Final critics are split: Gemini Atmosphere 8, Surreal 8, Sound 9, Camera 8, but Lighting 4 and Monster 3; Claude 5 to 7 across the board. Both say the bright yellow level is lit too evenly and the Occupant fails when seen plainly.

## Playable now (exact run command)
- Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip`. Controls: WASD, mouse, Shift sprint, Ctrl crouch, Z crawl, walk into a ladder to climb, hold right mouse for the camcorder, F3 performance overlay, Esc pause (Q quits). Clean-checkout check this session: a fresh clone imports with 0 errors and runs 900 frames of autoplay with 0 script errors.
- Review capture: `python tools/capture/capture.py` (`--extra focus_first=watch` puts the two watcher shots first). Tests: `godot_console --headless --path game --script res://scripts/tests_gen_determinism.gd`, `tests_spawn_seam.gd`, `tests_closet.gd`, `tests_wrong.gd -- SEED [rules]`.
- Debug options: `--hall_palette=cold|green|yellow`, `--wrong=frames,floor_hole,category,signs,nohandle,chairs_wall,blind_panel` (force rules everywhere), `--focus_wrong`, `--focus_first=watch`, `--log-watch`, `--watch_now`, `--no_watchers`, `--old_figure`, `--occ_test` (the Occupant 3.5 m in front of you; `--occ_tape=1`, `--occ_clip=walk`, `--occ_t=0.4`, `--occ_plain`), `--vm_hold=0.5` (the camcorder frozen mid-lift), `--light_e`, `--hall_gain`, `--hall_fog`, `--far_range`, `--log-pool`, and the look knobs in level0_look.gd (`--wall_sat`, `--grime_zones`, `--ceil_bounce`...).

## Done this session (each with commit hash and evidence)
- Look toward the reference stills (D038, 5381c7d): progress 0165 (baseline) to 0169 (chosen), 0178 (level with new defaults).
- Storeroom halls (D039, 5381c7d; D043, 787061f; 9c5ed86): palettes (progress 0170 to 0175, cold 0218), lit far door from a still (0171 to 0174, hand-over 0173), sparse lights and column shadows (0201 s05-hall-sparse-lights; Claude 023 Shadows 7, "the columns cast real shadows"), per-palette haze, quiet switched-off panels, painted columns.
- Bugs fixed on the way: hall shaders shaded by world height (base_y) and read the fixture field in world axes in a rotated hall (field_to_local); one wrapping glow field per space, no beam at chunk edges (0203); the mop bucket's baked glow (L111, L121); the plenum glowing through missing tiles (L142); dead-tube orange in the ceiling bounce.
- Remembered wrong batch 1 (D040, 7331550): tests_wrong.gd on seed 4242, 169 chunks: 23 free-standing frames, 29 floor openings, 23 category objects and 8 bottle-less coolers, 86 handle-less doors, 35 chunks of misspelled signs, 26 blind panels. Pictures 0179, 0180 (signs), 0183, 0190 (floor opening).
- Camcorder turned the right way round with a flip-out screen (D041, 7331550): progress s05-camcorder-lift (0184 to 0187). Claude 024: "the flip-out screen is a nice touch"; no critic called it a pistol after it.
- The Occupant and the watchers (D042, 787061f, 9c5ed86): occupant strips 0206 to 0212, tape encounter 0216, 0217 (dropout), watchers 0204, 0205, 0208 to 0210. Logs: "[tape] figure shown / looked again / last look over", "[watch] door opened / door shut / edge figure at".
- Footsteps at a walking cadence with variation (L151), the hall's far end not black (L152) (c557d3d).
- Critic loops 021, 022, 023, 024 (final), Claude and Gemini each.

## Not done / known broken (be blunt)
- The yellow level is lit too evenly for both critics (L155): the brightness came from Stewart's reference stills (D038), and the critics want pools and dark. Unresolved tension; Stewart's play notes should decide.
- The Occupant fails in plain view (L156): by eye the edge figure can stand in good light and read as "a tan mannequin"; on tape it reads as "a stick figure of masking tape" (Gemini Monster 3). Only the dropout look on tape and the head in the high door work. It does not hunt, chase or kill. No Dropout entity, no death replay.
- The bot does not seek the watchers or the remembered-wrong things; captures show them only by chance or in the two watcher focus shots.
- Room colour variety in the level itself is unchanged (L138); the storeroom hall carries the colour, and a seed whose bot never enters it (024) shows only yellow.
- About 61 "invalid UID" warnings per launch (stale UIDs in prop and Occupant imports, L154). Debug options above stay in the code.
- The capture sometimes spends a motion sheet on nine frames of the tripod pocket (L153).

## Critic: latest scores and top open LEDGER items
Columns: First, Light, Shadow, Mater., Atmos., Camera, Surreal, Monster, Sound, Pace, Perf, Keep.
| Loop | Build | Critic | F | L | Sh | M | At | Ca | Su | Mo | So | Pa | Pe | K |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 020 (S04 final) | 173a660 | Claude | 7 | 7 | 6 | 6 | 6 | 7 | 8 | 6 | NA | NA | 7 | 6 |
| 020 (S04 final) | 173a660 | Gemini | 4 | 3 | 3 | 4 | 6 | 6 | 8 | 4 | 5 | 6 | 5 | 6 |
| 021 | 5381c7d | Claude | 7 | 7 | 6 | 6 | 6 | 7 | 7 | 5 | NA | NA | 8 | 7 |
| 021 | 5381c7d | Gemini | 6 | 4 | 3 | 4 | 8 | 8 | 8 | 5 | 6 | 7 | 8 | 7 |
| 022 | 7331550 | Claude | 6 | 6 | 5 | 6 | 6 | 7 | 7 | 4 | NA | 5 | 8 | 6 |
| 022 | 7331550 | Gemini | 5 | 4 | 4 | 5 | 7 | 6 | 6 | 3 | 8 | 6 | 8 | 5 |
| 023 | 64563d2 | Claude | 7 | 7 | 7 | 6 | 6 | 7 | 6 | 4 | NA | 5 | 8 | 6 |
| 023 | 64563d2 | Gemini | 6 | 5 | 6 | 4 | 7 | 8 | 7 | NA | 7 | 6 | 8 | 6 |
| 024 (S05 final) | c557d3d | Claude | 6 | 6 | 5 | 6 | 5 | 7 | 6 | 5 | NA | 5 | 9 | 5 |
| 024 (S05 final) | c557d3d | Gemini | 6 | 4 | 4 | 5 | 8 | 8 | 8 | 3 | 9 | 7 | 9 | 7 |
Seeds differ per loop: 023 (cold storeroom hall visited) scored best on light and shadows; 024's bot stayed in the yellow level. Performance 8 to 9 all session.
Top open LEDGER items: L155 the yellow level lit too evenly; L156 the Occupant in plain view; L138 colour variety in the level; L159 milky haze wall at hall ends; L160 the level's own pillar rooms washed out; L136/L145 carpet reads dry; L153 capture sheet choice.
Protected (from 021 to 024): the camcorder overlay and tape tears, the chalk door that tears open on tape, the tripod room, the high door on the tall wall and the knee-high doorway, the cold foggy column hall with real shadows and the warm EXIT door as a beacon, the lone folding chair, embossed wallpaper and stained tiles up close, the hum and the wet footsteps (Gemini Sound 9), performance.

## qa-auditor result (pass/fail per claim)
14 claims (docs/handoffs/s05_claims_draft.md); scratch in review/archive/qa/s05/.
1 gdcheck PASS. 2 tests PASS (numbers matched). 3 remembered wrong counts PASS (exact). 4 look defaults PASS (0165 vs 0169). 5 storeroom halls PASS, caveat: the far end very dark in 0218 (fixed after: L152). 6 hall shader fixes PASS (code; no baseline image of the old bug). 7 bucket PASS. 8 camcorder PARTIAL (code checked; QA did not open the pictures; I did, 0184 to 0187). 9 Occupant on tape PASS (logs and sheet, repeatable). 10 watchers PASS (log lines, image). 11 perf PARTIAL: true numbers but best average of 3 runs per build, different seeds, on the RTX 5070 Ti Laptop (CLAUDE.md names a 5070); 022 85.8 / 63.0, 023 84.8 / 56.8, 024 98.7 / 69.9; the laptop Medium 1080p target was not measured. 12 critic loops PASS. 13 no secrets or em dashes PASS. 14 progress copies PASS.
Also found: uncommitted docs (committed after), stale-UID warnings (L154), the tripod sheet (L153), the session total missing in SPEND.md (added), a dead old-figure path in tape_events.gd (harmless, used by --old_figure).

## Next milestone and the first 3 concrete steps
M4 continued (effort xhigh): make the Occupant work, then let it hunt.
1. Read Stewart's play notes first (the brightness question, L155). Then the Occupant's presentation (L156): by eye never standing lit in the open (the edge figure only in dim places or as a silhouette against light, a doorway, a dead stretch), on tape mostly dropout held together by a few strips, bigger, smeared between held poses; a filmed check of both before any critic loop.
2. Light the long halls and the level's own pillar rooms with the hall's idea (fewer, stronger, pooled panels, real dead stretches), keeping the bright clean offices Stewart chose (L155, L160).
3. The hunt: senses (hearing first: sprinting, the camcorder's beep), stalking along loops and through storeroom portals, the tells (hum dies, lights flicker toward it, footsteps not yours), a chase, and the VHS death replay.

## Gotchas learned
- Godot 4.7: the Meshy rig's skeleton works in centimeters under a 0.01-scaled Armature, so VERTEX in a skinned mesh's shader is not meters; pass a body frame from script (Occupant.shade sets to_body / from_body).
- Spot lights fade out by distance from the camera that draws them: a portal camera far from a room sees it dark. Take a still from close up instead (Portal.request_still).
- Setting Node3D.rotation.y on a node whose basis is already rotated replaces the whole yaw; compose bases instead.
- Every panel lit in a grid fills every column's shadow; readable shadows need one dominant light per patch of floor.
- A per-chunk glow texture makes a hard line at every chunk edge once the glow is wide; share one wrapping texture per space.
- Shaders that shade by world height break in spaces built off the level's floor (the halls under the level): pass the floor height (base_y).
- The Gemini critic script takes the session number from docs/HANDOFF.md; moving HANDOFF.md before the last critic run labels its SPEND row S01.
- Python on Windows writes CRLF in text mode; use newline="\n" when editing repo files from Python.

## Decisions made
D038 look toward the stills, D039 storeroom halls, D040 remembered wrong batch 1, D041 the camcorder turned round, D042 the Occupant and the watchers, D043 lighting for readable shadows and one glow field per space.
