# Handoff: session 04 to 05 (10/02/2026)

## State in one paragraph
Session 04 ran in the daytime with Stewart checking in, and his direction outranked the plan: rooms that are small outside and giant inside, crawling and climbing, an abstract monster, live crew members, and the "remembered wrong" feel of the reference stills. Built: storerooms (3.6 m blocks standing free in big rooms) whose doorway is a portal into a 72 x 72 m pillar hall built under the level; you walk in with no visible jump, and the hall's far door, under an exit sign at the dark end, lets you out of the same storeroom door you went in by (D036). A crawl stance that comes on by itself at low openings (or Z), crawl holes (fully cased doorways 72 cm tall), and ladders in tall rooms up to a nook 3.9 m up (D037). The monster has a design and a rigged model: the Occupant, the building's own copy of a person papered in our wallpaper (Meshy 7.1, 9 animations), to be shown abstractly as loose wallpaper strips (D035, VISION). VISION gained "Remembered wrong", "Being watched", live Halden field teams and plural abstract monsters; the roadmap now runs M3.6 (remembered wrong, look toward the stills), M4 (Entity and watchers), M4.5 (Halden teams). Stewart fixed the critic hand-back guard (D033).

## Playable now (exact run command)
- Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip`. Controls: WASD, mouse, Shift sprint, Ctrl crouch, Z crawl (it also happens on its own at low holes), walk into a ladder to climb it, hold right mouse for the camcorder, F3 performance overlay, Esc pause (Q quits).
- The storeroom: from the start, go east down the long hall; it stands in a big room on the left or right within about 30 m (chunk 1,0 in 198 of 200 seeds).
- Debug: `-- --start=x,z,yaw_deg` starts at a spot; `-- --start-room=1:0,63,36,1,0` starts inside a storeroom's hall (hall-local x, z, facing); `--route=north|south|east|west` walks straight; `--log-portal`, `--portal_never`, `--portal_always`, `--portal_scale=0.6`, `--hall_lights=32`.
- Review capture: `python tools/capture/capture.py`. Tests: `godot_console --headless --path game --script res://scripts/tests_closet.gd` (storeroom placement), `tests_holes.gd -- SEED` (lists holes and ladders), `tests_spawn_seam.gd`, `tests_gen_determinism.gd`.

## Done this session (commit, evidence)
- Rooms bigger inside than outside (D036, a191471): storeroom placement (tests_closet.gd: chunk 1,0 in 198/200 seeds, about 9 percent of other chunks), PortalRoom hall under the level at the first free depth, Portal node (SubViewport camera, seamless crossing on the physics tick, near plane at the doorway, dark fogged stand-in when out of range), far door back out of the storeroom, bot visit routine, focus shots, debug starts. Evidence: progress/0129 (first look), 0134 and 0135 (crossing frames matched in brightness within about 3 percent), 0136 (far door out), 0137 (doorway still). Cost while a doorway is on screen: about 3.5 ms at 1440p (L114).
- Crawl and climb (D037, c4fbd94): crawl stance (auto at low openings, Z), ladders, crawl holes (about a third of chunks), tall-room ladders to a lit nook 3.9 m up; collision over low doorways, on tall walls above 2.6 m, and no ceiling slab over tall rooms. Evidence: progress crawl-hole and ladder-climb sheets.
- The Occupant (D035, 3030083, c4fbd94): concepts (progress/0123, 0124), Meshy 7.1 models C_2 and C_4 (progress/0125, 0126), C_4 rigged with 9 animations (progress/0138; game/assets/entity/occupant_rigged.glb and anims/). Not in the game yet.
- Exit signs lit from behind the plate with a soft spill (L119, 173a660; progress/0145).
- Design: VISION "Remembered wrong", "Being watched", live Halden field teams, abstract plural monsters; ROADMAP M2b crawl and climb, M3.6, M4 with watchers, M4.5 Halden teams (7646414). Stewart's notes copied to STEWART_FEEDBACK.md.
- Critic guard: Stewart's edit tested (D033); the critic now hands back directly. CLAUDE.md updated.
- Critic loops: 019, 020 (final).

## Not done / known broken (be blunt)
- The Occupant is not in the game: no strip shader, no AI, no watchers layer yet (M4). The tape figure is still the only presence and critics still call it a placeholder (Monster 4 to 5).
- Halden field teams are design only (M4.5).
- The crawl into the plenum over the rooms (in VISION) is not built: ceiling tiles have no top faces and the ceiling collision is a slab.
- The bot does not use ladders or crawl holes on purpose (it may stumble through a hole); nothing shows them in captures unless a focus shot does.
- Portals cost about 3.5 ms while on screen (portal view at 60 percent resolution, a second full render with SDFGI and haze); the far side's own glow cannot be undone exactly (gain 1.22 and 8 percent desaturation measured on video).
- Perf in the 019 capture was contaminated by another program on the GPU (53.9 / 27.4); clean re-run 75.7 / 51.4 (84.1 without portals). The 1% low target (50) is only just met.
- Still open: the held camcorder reads as a pistol (L092), same mustard everywhere (L118), wall-foot gradient artifact (L117), carpet tiling and wallpaper banding (L104), a floating chair Gemini reported (L116, unverified).

## Critic: latest scores and top open LEDGER items
Columns: First, Light, Shadow, Mater., Atmos., Camera, Surreal, Monster, Sound, Pace, Perf, Keep.
| Loop | Build | Critic | F | L | Sh | M | At | Ca | Su | Mo | So | Pa | Pe | K |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 018 (S03 final) | 00d5ddb | Claude | 7 | 7 | 6 | 6 | 6 | 8 | 6 | 4 | NA | 6 | 9 | 6 |
| 018 (S03 final) | 00d5ddb | Gemini | 7 | 8 | 7 | 7 | 8 | 8 | 6 | 3 | 8 | 7 | 9 | 7 |
| 019 | c4fbd94 | Claude | 7 | 7 | 6 | 6 | 6 | 8 | 7 | 4 | NA | 5 | 6 | 6 |
| 019 | c4fbd94 | Gemini | 6 | 4 | 2 | 5 | 7 | 7 | 8 | 5 | 6 | 7 | 3 | 7 |
| 020 (S04 final) | 173a660 | Claude | 7 | 7 | 6 | 6 | 6 | 7 | 8 | 6 | NA | NA | 7 | 6 |
| 020 (S04 final) | 173a660 | Gemini | 4 | 3 | 3 | 4 | 6 | 6 | 8 | 4 | 5 | 6 | 5 | 6 |
Surreal is now 7 to 8 on both critics (the storeroom hall: "the signature moment", "fantastic and seamless"). The 019 performance scores came from perf runs that shared the GPU with another program (L115; clean re-run 75.7 / 51.4). Gemini's Lighting and Shadows swing from 8/7 (018) to 3/3 (020) on similar lighting; read its trend over several runs. Both critics agree the next gains are the look (lighting depth, materials, color variety) and a monster that does something.
Top open LEDGER items: L118 one mustard everywhere, L120 the hall's far door and walls, L092/L125 the held camcorder (reads as a pistol), L104 wallpaper and carpet repeat, L117 wall-foot gradient, L121/L122/L116 three props to verify (glowing bucket, something in a doorway top, a floating chair), L114 portal cost, L108 the figure (M4).
Protected: the camcorder overlay, the chalk-door seam, the long fogged halls, the tripod room, the small door onto the giant hall and the hall's fog shafts, the figure with its floor reflection, the hum mix.

## qa-auditor result (pass/fail per claim)
(fill)

## Next milestone and the first 3 concrete steps
M3.6 Remembered wrong batch 1 plus the look toward Stewart's reference stills (effort xhigh), then M4 (the Occupant, the Dropout, the watchers).
1. Look: cleaner, more saturated mono-yellow with brighter panel rows and plain walls (grime concentrated), and at least one hall with a different palette behind a portal or seam (L118); fix the wall-foot gradient (L117). A/B lookdev against the reference feel, then a critic loop.
2. Remembered-wrong rules, batch 1: handle-less doors, freestanding door frames, almost-right signs, category objects, chairs facing walls, a floor opening onto the lit ceiling of the level below.
3. The watchers, cheap first: the tall room's high door opening a crack with something looking out; a figure drawn only at the screen edge. Then the Occupant strip shader on occupant_rigged.glb.

## Gotchas learned
- A Camera3D environment override drops the volumetric haze when the camera renders in a SubViewport (Godot 4.7.2). Portal cameras use the world environment and the portal shader undoes AgX (copied from 4.7 tonemap.glsl and environment_storage.cpp).
- Halls built during the loading moment exist before the player's camera; anything that grabs the camera at build time must pick it up again later.
- Resetting volumetric fog temporal reprojection on a teleport darkens the haze for a few frames; across a portal (same picture both sides) keep it.
- The chunk ceiling collision was a single slab at 2.6 m over the whole chunk, tall rooms included; walls had collision only up to 2.6 m.
- The Meshy account is shared with Stewart's other projects; its balance drops between calls for reasons that are not ours.
- A heredoc containing many nested quotes broke bash once; patch scripts are now written with the Write tool.

## Decisions made
D033 critic hand-back (Stewart's edit), D034 Stewart's priorities, D035 the Occupant, D036 storeroom portals, D037 crawl and climb.
