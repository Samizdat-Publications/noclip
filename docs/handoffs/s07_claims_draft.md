# Session 07 claims for the qa-auditor

Check each against the working tree at the latest commit. Headless runs: Godot via `python -c "import sys;sys.path.insert(0,'tools');import paths;print(paths.godot())"`, `--headless --path game --fixed-fps 30 --quit-after N -- --seed=S --autoplay ...`.

1. gdcheck: `python tools/gdcheck.py` reports 0 error lines.
2. The Descent, stairwell: on seed 4242 with `--log-run --descend_at=20 --hunt_at=300` the log shows "down the stairs to depth 2" then "built depth 2", then depth 3 at 40 s; each depth logs a stairwell chunk.
3. The bot finds the stairwell by itself: seed 41311 with `--log-run --kit=flash:1,flares:1 --bot_stairs_after=40` shows "down the stairs to depth 2" before 90 s with no "SCRIPT ERROR" lines.
4. The kit works against the hunt: seed 12 with `--log-hunt --hunt_at=20 --kit=flash:2,flares:2` (seed 4242's bot misses its flash, then escapes) shows "[kit] ... flash ... PINNED it", "pinned by the flash", "the flash let go: it has lost you", and "[kit] ... flare thrown".
5. Caught means Halden drags you back and pays: seed 21 with `--log-run --log-hunt --hunt_at=15` (no kit) shows "the tape ends (death 1)" is followed by "[run] ... run over: +N salvage" with N > 0, then "built depth 1" and "new run at depth 1 (salvage N ...".
6. Progress is saved between runs: after a human-mode run the file user://progress.json exists with keys salvage, deepest, kit, world_seed, deaths (the autoplay bot uses progress_bot.json and wipes it each run unless --keep_progress).
7. Kit levels are gated by depth reached: core/progress.gd KIT lists each level's depth requirement; `can_buy` checks deepest >= the requirement.
8. The Crawler is the hunt's body on depth 1 (D052): game/assets/crawler/crawler_rigged.glb and 9 clip glbs exist; OccupantHunter creates a CrawlerRig unless --occupant_hunts; look-dev pictures progress/0264 to 0266 and 0274 show it in engine.
9. Monster Lab (D051): review/monster_lab/r1 (9 options), r2 (8), r3 (6) hold only option images; keys in pipeline/monster_lab/r1_key.json and r2_key.json; critiques review/critiques/monster_r1_{claude,gemini}.md, monster_r2_*, monster_r3_*.
10. Halden last stand (L204): seed 4242 with `--log-halden --halden_at=12 --hunt_at=200 --bot_stairs_after=300` logs "a last stand", "the flares are dying", "it took one of them", "the scene is over".
11. The Landing: on seed 4242 the start has a lift cage, a locker, two tape crates and a work light (progress/0271_2026-10-03_1713_s07_s07-landing-4.jpg).
12. Critic loops: review/critiques/030_claude.md (and 031 after the final loop) saved; scores in review/scores.csv.
13. Spend: docs/SPEND.md has a Session 07 section with the Gemini concept images, ElevenLabs sounds, Meshy credits for the Crawler and the critic calls; total well under $40.
14. Progress copies: every generated image this session has a copy in progress/ from 0253 on.
15. No em dashes in any file written this session (verbatim critiques excepted); no secrets committed.
