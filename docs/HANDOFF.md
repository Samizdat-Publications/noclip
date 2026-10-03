# Handoff: session 07 to 08 (10/03/2026)

## State in one paragraph
Session 07 answered Stewart's two asks. Progression (D050, VISION "Progression: The Descent"): every run starts at the Landing, Halden's post (a locker, tape crates, a work light, a lift cage with no shaft); each depth has a stairwell (a lit EXIT sign with an arrow pointing down, red lamp, concrete stairs into the dark, a draft you can hear) that takes you one depth down; depths 1 to 4 (the Yellow, the Cold Rooms, the Green, the Red Halls, then darker repeats) each with their own palette, panel colour, light level, haze and layout kept between runs, and the hunt sooner and faster; when it catches you Halden drags you back and pays salvage for the tape (shown on the END OF TAPE card: distance, depths, firsts, footage, flash pins; 60 percent when caught), a lift cage pays it all; salvage buys permanent kit at the locker, each level gated by the deepest depth reached (flashbulb F pins the hunter for 3.6 s, road flares G burn red 40 s and it will not enter red light, overshoes, better tape stock; radio and crowbar listed but not built); the Landing's lift goes straight down to any depth reached. The monster (D051, D052): the Monster Lab ran three blind panel rounds (Claude persona plus Gemini) on 8 original directions painted into game frames plus the old monster as a hidden control; both judges rejected the old paper Occupant; the giant crawler won the first rooms (fear 9 and 9), the ceiling hanger is for deeper, the fixture spider after it. The Crawler (Meshy) is now the hunt's body: 2.8 times a person, crawling, squeezing narrower through doorways, solid and lit by eye with contact shadows, held in frame skips on tape where its face is always turned to the lens, lifting its calm closed-eyed face to you when you look, and opening black eyes at the end of a catch. Halden's last stand (L204): two technicians holding it off with flares, the flares die, it takes one and drags him off. Final critics: Claude 6/6/5/6/6, camera 8, monster 4, keep 6; Gemini monster 7 ("the ceiling crawl is terrifying"), surreal 8, sound 8, keep 7, but lighting 3 and performance 2.

## Playable now (exact run command)
- Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip`. WASD, mouse, Shift sprint, Ctrl crouch, Z crawl, hold right mouse for the camcorder, F flashbulb (camcorder up), G throw a flare, E use (locker, lift cage, your dropped camcorder), Esc pause, F3 performance overlay. In the locker: W and S choose, E buys, Esc closes.
- Clean checkout (bdedc96): fresh clone plus `git lfs pull` imports with 0 errors and runs 900 frames of autoplay on seed 4242 with no script errors.
- Review capture: `python tools/capture/capture.py --extra kit=flash:1,flares:1 bot_stairs_after=40 halden_at=30`. Never edit game/ or tools/ while it runs. Shrink inbox/video/clip.mp4 to 720p before tools/critic_gemini/critic.py (a 199 MB clip timed out uploading).
- Builder options added: `--depth=N --no_descent --kit=flash:2,flares:1 --deepest=N --salvage=N --fresh_progress --keep_progress --descend_at=S --stair_ring=N --bot_stairs_after=S --halden_at=S --no_halden --occupant_hunts --log-run --log-halden --log-kit`.
- Monster Lab: `python tools/monster_panel.py review/monster_lab/rN OUT.md --prompt pipeline/monster_lab/panel_prompt_rN.md` (Gemini judge); the Claude judge is a general-purpose Sonnet agent told to read the prompt file and only that folder.

## Done this session (each with commit hash and evidence)
- The Descent (D050; e73859b, d8baa74): headless seed 4242 `--descend_at=20` goes down to depth 9 at 20 s steps, each depth built in 1.6 to 4 s behind the stairs card; the bot walks into the stairwell on its own (seed 41311, 58.9 s). Pictures: the stairwell 0267, 0270; the Landing 0268, 0271.
- Kit (e73859b): seed 12 pins the hunter with the flash and lets go 3.6 s later (QA); flares thrown; overshoes change stamina and step loudness.
- Salvage and the loop (e73859b): seed 21 caught at 116 s, "+110 salvage", rebuilt at depth 1, "new run at depth 1 (salvage 110" (QA claim 5).
- Monster Lab (D051): rounds 1 to 3, progress 0253, 0255, 0266; critiques review/critiques/monster_r1_*, monster_r2_*, monster_r3_*.
- The Crawler (D052; e73859b, d8baa74): pipeline/meshes/build_crawler.py (62 Meshy credits); look-dev 0264, 0265, 0266, 0274.
- Halden last stand (d8baa74): seed 4242 `--halden_at=12` logs the stand, the flares dying, "it took one of them", the end (QA claim 10).
- 53 ElevenLabs sounds (descent, Halden, Crawler), about $0.24. Session spend about $3.01 plus 62 Meshy credits.
- Critic loops 030 and 031; ledger L201 to L219; decisions D050 to D052; VISION progression rewritten.

## Not done / known broken (be blunt)
- The critics still have not seen the Crawler properly (L213): what they call the monster is the old tape-only figure (TapeEvents, the Occupant), which the bot meets far more often than the hunt. Claude Monster stayed 4. Gemini saw the Crawler (Monster 7) and found its floor chase goofy (L217: crawl_slow sped up to 3.6 times).
- Going down a stairwell resets the hunt's timer, so the bot (and a player) can escape hunts by descending; on seed 4242 the bot is never caught in 180 s and its flash misses. Decide: keep (going down is the escape) or carry the hunt down.
- Depth 2 reads as depth 1 recoloured blue (L214). Depths need their own layouts and twists.
- Lighting (Gemini 3) and performance (Gemini 2): every perf run in both captures was flagged "GPU shared, not trusted" (74 to 80 fps average, 1 percent lows 40 to 53).
- Radio, crowbar and Halden caches: designed, not built; hidden from the locker (Progress.KIT_ORDER) until they work.
- Halden help (a technician fires a flare between you and it, standing 3 or more) is in code, never seen in a capture.
- "Parameter t is null" engine error once when flares or Halden scenes spawn (L212); about 76 "invalid UID" warnings per run from stale glb imports.
- Halden's last stand is staged in front of you without a set (no red room); the taken technician slides along the floor rather than being dragged by anything you see.
- Store above the Landing, lore tapes, chalk, the Daily Descent: not built.

## Critic: latest scores and top open LEDGER items
Columns: First, Light, Shadow, Mater., Atmos., Camera, Surreal, Monster, Sound, Pace, Perf, Keep.
| Loop | Build | Critic | F | L | Sh | M | At | Ca | Su | Mo | So | Pa | Pe | K |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 029 (S06 final) | bab4328 | Claude | 7 | 7 | 6 | 6 | 6 | 8 | 7 | 4 | NA | 6 | 8 | 6 |
| 029 (S06 final) | bab4328 | Gemini | 5 | 4 | 3 | 5 | 8 | 7 | 8 | 6 | 9 | 7 | 4 | 8 |
| 030 | e73859b | Claude | 6 | 6 | 6 | 5 | 5 | 7 | 6 | 4 | NA | 4 | 8 | 5 |
| 031 (final) | d8baa74 | Claude | 6 | 6 | 5 | 6 | 6 | 8 | 5 | 4 | NA | NA | 7 | 6 |
| 031 (final) | d8baa74 | Gemini | 6 | 3 | 4 | 4 | 7 | 8 | 8 | 7 | 8 | 7 | 2 | 7 |
030 Gemini timed out uploading (not charged). 030's pace 4 and the "half the footage is one red door" were the bot stuck at the stairwell (fixed in d8baa74).
Monster Lab panels (fear): round 1 crawler 9/8, lamp 8/8, fixture spider 7/9, old Occupant 6/2; round 3 (in engine, before the skin fix) 5/4, best shot the far silhouette in fog.
Top open: L213 the critics never see the Crawler, L217 its floor chase, L214 depths are recolours, L178/L216 lighting, L218 perf, L215 mirrored EXIT (returned twice: FIX), L196 bright or dark (Stewart).
Protected: the camcorder overlay and REC/PLAY/END OF TAPE screens, the red stairwell against the yellow, the DEPTH card with its v marks, the cold blue palette, the pillar hall's hard shadows, the chalk door and "HERE", the tripod and its shadow, fog falloff, the camcorder-only doors, the far silhouette in a lit corridor, the Crawler's calm closed-eyed face, its long reaching arms, its size against the corridor, the ceiling crawl, the paper and hum sounds, the monster's screech.

## qa-auditor result (pass/fail per claim)
Claims: docs/handoffs/s07_claims_draft.md (rewritten after the audit); scratch in review/archive/qa/s07/. 12 PASS, 2 FAIL as first written, 1 PARTIAL.
1 gdcheck PASS. 2 stairwell PASS. 3 bot finds the stairs PASS. 4 kit FAIL on seed 4242 (the bot's flash missed), PASS on seeds 11, 12, 13: claim rewritten to seed 12. 5 caught and paid FAIL on seed 4242 (never caught), PASS on seeds 21, 22: rewritten to seed 21. 6 save PASS. 7 gating PASS. 8 Crawler PASS. 9 Monster Lab PASS (round 3 had no record of how it was made: engine renders, now noted in SPEND). 10 Halden PASS. 11 Landing PASS (filename fixed). 12 critics PASS. 13 spend PASS (total line added). 14 progress copies PARTIAL (round 3's images are the look-dev 0266). 15 no em dashes, no secrets PASS.
Also found: seeded runs are deterministic (identical logs); 76 invalid-UID warnings per run.

## Next milestone and the first 3 concrete steps
M5 continues (the run loop), with the monster first. Effort high (xhigh if the ceiling hanger is built).
1. Read Stewart's play notes (docs/STEWART_FEEDBACK.md) and turn each into a LEDGER item before anything else: was the run loop clear, did buying kit feel like getting stronger, was the Crawler scary, too easy or too deadly.
2. L213 and L217: make the Crawler the thing the critics see. The tape-only figure becomes the Crawler on tape (or is cut), a lit close look by eye is guaranteed once a run (the close beat), the floor chase caps its speed scale and borrows the ceiling crawl Gemini loved (it moves along the ceiling in long halls). Then a Monster Lab round 4 on capture frames.
3. Depths that are places (L214): the Cold Rooms as low, wide, half-dark open plan with failing panels and the ceiling hanger (round 2's pick for deeper: concept pipeline/monster_lab/r2/C1.png, C2.png) as its hunter; build the radio and the crowbar or take them off the locker.

## Gotchas learned
- New StaticBody shapes do not answer raycasts until physics has stepped: wait two physics frames before raycasting at chunks built this frame (Landing._wall).
- The bot's closet logic expects "n" as a Vector3; storeroom closets' interest points give Vector3, the stairwell's gave a Vector2 (13 script errors, the bot frozen at the door).
- A storeroom's inside is not walkable: triggers for things in a storeroom must fire in the doorway.
- Posed capture shots can stand you in a trigger: the stairwell ignores the player during the capture's posed shots (Game.clock > Game.duration).
- Meshy's 678-clip library has only two true crawls (340 forward, 549 backward); hips carry root motion in library clips: pin the hips' x and z (Crawler._pin_hips).
- LookAtModifier3D was not needed: a small SkeletonModifier3D that rotates neck and head toward a point from their rest-pose facing works (Crawler.HeadLook).
- Gemini video uploads near 200 MB time out: re-encode the inbox clip to 720p (about 30 MB) first.
- The shell stalls for a minute on trivial commands in this session too; the Edit tool is faster for code changes than python patch scripts.
- tools/progress.py names come out "s07_s07-..." when the label already starts with s07: label without the prefix.

## Decisions made
D050 the Descent (progression), D051 the Monster Lab, D052 the Crawler hunts depth 1.
