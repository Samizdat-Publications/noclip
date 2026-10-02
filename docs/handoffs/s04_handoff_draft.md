# Handoff: session 04 to 05 (10/02/2026)

## State in one paragraph
Session 04 ran in the daytime with Stewart checking in, and his direction outranked the plan: rooms that are small outside and giant inside, crawling and climbing, an abstract monster, live crew members, and the "remembered wrong" feel of the reference stills. Built: storerooms (3.6 m blocks standing free in big rooms) whose doorway is a portal into a 72 x 72 m pillar hall built under the level; you walk in with no visible jump, and the hall's far door, under an exit sign at the dark end, lets you out of the same storeroom door you went in by (D036). A crawl stance that comes on by itself at low openings (or Z), crawl holes (fully cased doorways 72 cm tall), and ladders in tall rooms up to a nook 3.9 m up (D037). The monster has a design and a rigged model: the Occupant, the building's own copy of a person papered in our wallpaper (Meshy 7.1, 9 animations), to be shown abstractly as loose wallpaper strips (D035, VISION). VISION gained "Remembered wrong", "Being watched", live Halden field teams and plural abstract monsters; the roadmap now runs M3.6 (remembered wrong, look toward the stills), M4 (Entity and watchers), M4.5 (Halden teams). Stewart fixed the critic hand-back guard (D033).

## Playable now (exact run command)
- Double-click `Play NOCLIP.bat` in `C:\\Users\\stewa\\ClaudeProjects\\Noclip`. Controls: WASD, mouse, Shift sprint, Ctrl crouch, Z crawl (it also happens on its own at low holes), walk into a ladder to climb it, hold right mouse for the camcorder, F3 performance overlay, Esc pause (Q quits).
- The storeroom: from the start, go east down the long hall; it stands in a big room on the left or right within about 30 m (chunk 1,0 in 198 of 200 seeds).
- Debug: `-- --start=x,z,yaw_deg` starts at a spot; `-- --start-room=1:0,63,36,1,0` starts inside a storeroom's hall (hall-local x, z, facing); `--route=north|south|east|west` walks straight; `--log-portal`, `--portal_never`, `--portal_always`, `--portal_scale=0.6`, `--hall_lights=32`.
- Review capture: `python tools/capture/capture.py`. Tests: `godot_console --headless --path game --script res://scripts/tests_closet.gd` (storeroom placement), `tests_holes.gd -- SEED` (lists holes and ladders), `tests_spawn_seam.gd`, `tests_gen_determinism.gd`.

## Done this session (commit, evidence)
(fill)

## Not done / known broken (be blunt)
(fill)

## Critic: latest scores and top open LEDGER items
(fill)

## qa-auditor result (pass/fail per claim)
(fill)

## Next milestone and the first 3 concrete steps
(fill)

## Gotchas learned
- A Camera3D environment override drops the volumetric haze when the camera renders in a SubViewport (Godot 4.7.2). Portal cameras use the world environment and the portal shader undoes AgX (copied from 4.7 tonemap.glsl and environment_storage.cpp).
- Halls built during the loading moment exist before the player's camera; anything that grabs the camera at build time must pick it up again later.
- Camera3D.get_frustum() planes: is_point_over() is outside (that was not the portal bug).
- Resetting volumetric fog temporal reprojection on a teleport darkens the haze for a few frames; across a portal (same picture both sides) keep it.
- The chunk ceiling collision was a single slab at 2.6 m over the whole chunk, tall rooms included; walls had collision only up to 2.6 m.
- The Meshy account is shared with Stewart's other projects; its balance drops between calls for reasons that are not ours.
- A heredoc containing many nested quotes broke bash once; patch scripts are now written with the Write tool.

## Decisions made
D033 critic hand-back (Stewart's edit), D034 Stewart's priorities, D035 the Occupant, D036 storeroom portals, D037 crawl and climb.
