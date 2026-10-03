# Session 05 draft claims (for qa-auditor)

Repo: C:\Users\stewa\ClaudeProjects\Noclip, HEAD 9c5ed86 (and later commits of this session). Godot 4.7.2 at tools/paths.py godot().

1. Scripts compile: `python tools/gdcheck.py` prints "gdcheck: ok".
2. Tests pass: `godot_console --headless --path game --script res://scripts/tests_gen_determinism.gd` (gen tests: PASS), `tests_spawn_seam.gd` (0 of 200 seeds without a seam), `tests_closet.gd` (2 of 200 seeds without a storeroom in chunk 1,0).
3. Remembered wrong batch 1 (D040): `tests_wrong.gd -- 4242` over 169 chunks gives 23 free-standing frames, 29 floor openings, 23 category objects plus 8 bottle-less coolers, 86 handle-less doors, 35 chunks with misspelled exit signs, 26 blind panels; rules are per 3 x 3 block of chunks (Level0Gen.wrong_rules), the start block has frames, category and signs.
4. The look moved toward the reference stills (D038): defaults in game/scripts/level0/level0_look.gd: wall_sat 1.25, wall_contrast 1.8, grime_zones 1, wall_tint 1.03/0.97/0.86, halo 1.3, ceil_bounce 3.0, lens_e 3.0, ae 0.42. Evidence: progress/0165 (baseline) vs progress/0169 and later lookdev pictures.
5. Storeroom halls (D039, D043): palette per storeroom (cold 45, green 25, yellow 30 percent; PortalRoom.PALETTES), painted columns, handle-less doors on the long walls, own haze volume (FogVolume, per-palette colour), lit by a sparse grid of stronger panels so columns throw shadows, switched-off panels without orange ends; the far door shows a still of the lit room beyond 7 m and the live view within 7 m (Portal.request_still, range 7); a warm lamp shines through it.
6. Two old hall bugs fixed: hall shaders shaded by world height (base_y now passed) and read the fixture field in world axes while the hall is rotated (field_to_local); one wrapping glow field per space (FixtureField.wrap) so there is no hard line at chunk edges.
7. The mop bucket no longer glows (PropCache drops baked emission maps).
8. The held camcorder is turned the right way round (lens away) with an open flip-out screen and is hidden for the first fifth of the lift (player.gd _add_flip_screen, camcorder.gd). Evidence progress s05-camcorder-lift.
9. The Occupant (D042): occupant_rigged.glb with nine clips (scripts/level0/occupant.gd, shaders/occupant_strips.gdshader) is the tape encounter's body; on tape its strip gaps are dropout. Run with `--tape-always --route=east --route-stay --route-cam=1.2-7,8.2-13 --log-tape` on seed 4242: "[tape] figure shown", "looked again", "last look over". Evidence progress s05-tape-occupant-dropout.
10. Watchers (D042, scripts/level0/watchers.gd): the tall room's high door opens (40 degrees) with a papered head and hand in the gap and shuts after you look away; a figure only at the edge of sight (eye-only layer) that fades as you turn to it. `--log-watch` prints "[watch] door opened", "door shut", "edge figure at". Evidence progress s05-watchers.
11. Performance in the review captures (2560x1440, high): 022 build 85.8 fps avg / 63.0 1% low, 023 build 84.8 / 56.8 (perf.json in review/archive/raw/<build>/).
12. Critic loops this session: 021, 022, 023 (Claude and Gemini each), saved in review/critiques and review/scores.csv; Gemini spend logged in docs/SPEND.md.
13. No secrets or .env in the commits of this session; no em dashes in files written this session other than the Gemini critiques (verbatim).
14. Every generated image of this session has a copy in progress/ (0165 onward) listed in progress/INDEX.md.
