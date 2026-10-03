# Session 06 claims for the qa-auditor (draft)

Check each claim against the repository and by running the game. Commands assume `C:\Users\stewa\ClaudeProjects\Noclip`; Godot via `python -c "import sys;sys.path.insert(0,'tools');import paths;print(paths.godot())"`.

1. Scripts are clean: `python tools/gdcheck.py` prints `gdcheck: ok (0 error lines)`.
2. Existing tests pass: `godot_console --headless --path game --script res://scripts/tests_gen_determinism.gd` (PASS), `tests_spawn_seam.gd`, `tests_closet.gd`, `tests_wrong.gd -- 4242`.
3. The Occupant hunts: `godot_console --headless --path game --fixed-fps 30 --quit-after 3600 -- --seed=4242 --autoplay --hunt_at=15 --no_scares --log-hunt` logs, in order, `absent -> stalk`, `right behind you`, a notice (`noticed you`), `notice -> chase`, and either `caught you` / `the tape ends (death 1)` or a `search`/`leave`; after a death, `gone (hunt 1 over)`.
4. The close beat is filmed in some seeds: the same command on seeds 90210 and 5150 logs `filmed up close: it screams`.
5. The death replay records and plays: a windowed run (not headless) of claim 3 with `--capture=<dir> --stills=0 --sheets=0 --duration=100` logs `[replay] start: 240 frames (16.0 s), 16.0 s of sound` and `[replay] over`.
6. The found tape: adding `--found_test` to claim 5 logs `[replay] the dropped camcorder's tape: 240 frames` after the death (progress 0240 shows it).
7. The dragged body: a windowed run with `--seed=4242 --drag_at=5 --no_hunt --log-scare --capture=<dir> --stills=0 --sheets=0 --duration=40` logs `a body at`, `he is about to go`, `dragged`, `gone round the corner` (progress 0232 shows it).
8. The head round a doorway: a windowed seed 4242 run with `--log-watch` logs `[watch] corner figure at` and `drew back` (progress 0233, frames 49 to 50 s).
9. The Catalogue: after any run with filming, `user://catalogue_bot.json` (autoplay) holds a `shelf` with entries; the end-of-tape card reads `ON THE SHELF n / 14` (progress 0240).
10. The level is lit in pools: `Level0Gen._pooled_run`, `_sparse_hall`, the "pools" room mood exist and are called; progress 0231, 0244.
11. The held camcorder is not shown unless `--show_vm`; the lift is the eyecup (eyecup.gdshader); progress 0241 row 3.
12. Storeroom halls varied (`PortalRoom._variety`): `--log-hall` on seed 4242 prints the placements; progress 0245 shows the cold patch, the wall with a doorway, the lit chair, the collapse.
13. Critic loops 025, 026, 027 and the final loop ran; critiques saved in review/critiques, scores in review/scores.csv.
14. Paid spend logged in docs/SPEND.md: Meshy 62 credits (balance 1292 to 1230), ElevenLabs 1029 credits, Gemini concept and critic calls.
15. Every generated image has a copy in progress/ with an INDEX.md line (0221 onward).
16. No em dashes and no secrets in files changed this session.
