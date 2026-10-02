# Critic LEDGER

Every issue from every critique (Claude critic, Gemini critic, Stewart) gets one row.
Status: FIX (then fixed in commit X), DEFER (to milestone), REJECT (real reason), DONE (fixed and not repeated by the next critique).
A REJECT that returns in 2 later critiques must become FIX or go to NEEDS_STEWART.

## Protected ("working, don't touch")
- The dark room seen from a lit hall, and the dim room with the orange-edged dead panel (005).
- Chalk circle mark and muddy footprints that sell "this place remembers you" (005).
- Lone chair for scale in the pillar hall (005).
- Red EXIT sign glow on the ceiling and walls, the best lighting beat (002).
- Water stains, tide line and drip streaks on walls, ceiling stains (002).
- Footprints on the carpet (002).
- Hard shadow wedges from doorways, the strong dark-to-lit read (002).
- Ceiling: stained speckled tiles, missing tiles showing black holes, fly-specked diffusers that glow without looking like stickers (001).
- Wallpaper stripes and dots plus baseboards, which hold up close (001).
- Camcorder HUD: REC, battery, 1996 date and timestamp (001).
- The scale and depth of the big pillar hall (001).
- Subtle wall-bounce glow near the ceiling lights (001).

## Open

| ID | First seen | Source | Severity | Issue | Status | Notes / commit |
|---|---|---|---|---|---|---|
| L001 | 001 | claude | ruins it | Nothing is happening: no creature, marks, props, traces of earlier visitors, impossible geometry | FIX (partial) + DEFER | S01: chalk marks, wet footprint trail that ends at a door that does not open, fallen ceiling tile, props, exit sign (commit after 4b4c4f2). Monster DEFER M4, run traces (your own chalk, dropped camcorder) DEFER M5 |
| L002 | 001 | claude | hurts | The space does not feel impossible; it is just a big office | FIX (small) + DEFER M2 | S01: a doorway that is slightly too small, closed doors set into solid walls. Real non-euclidean toolkit (loops, portals, rooms bigger inside) is M2 |
| L003 | 001 | claude | hurts | Everything is one yellow-brown; screenshots blur together | FIX | S01: red exit sign with a red glow, a few cold mismatched tubes, darker painted doors |
| L004 | 001 | claude | hurts | 39 fps avg, 26 fps 1% low at 1440p is unacceptable | FIX | S01: light reach 13 m to 7 m, medium soft-shadow filter: probe 66 fps avg, 50 fps 1% low (was 36/27) |
| L005 | 001 | claude | hurts | Shadow edges look stair-stepped (frame_04, _10, _19); repeated in 002 (frame_10) | FIX | 002 still saw it. Root cause: 16-bit shadow atlas plus wide spot cones at grazing angles. S01: 32-bit atlas, bias 0.06 / normal bias 2.6, shadow blur 2.5, light size 1.2 (progress/0022) |
| L006 | 001 | claude | nitpick | Glossy floor puddles read as sliding blobs, inconsistent with matte carpet | FIX | Wet-patch roughness 0.34 to 0.48, dry carpet less specular, heathered fiber variation |
| L007 | 001 | claude | nitpick | Camcorder view in the dark is unreadable mud; tracking tear looks like a glitch | FIX | Auto gain brightens the camcorder image in the dark (with more snow); tracking wobble halved |
| L008 | 002 | claude | hurts | Every space looks the same; wants landmarks every few rooms (different light color, flooded stretch, dead-light zone, furniture) | FIX | S01: one soaked, flooded stretch per seed (mirror water tried and parked: smeared light highlights into white blobs, progress/0031); a corridor of cold replacement tubes; props incl. a pink office chair; generation-loss splice errors (chair in a wall, three identical chairs, sunk chair, tracking-shear wall band) |
| L009 | 002 | claude | hurts | Ceiling lights look like stickers: flat white slabs, little bloom | FIX | S01: removed the grid bar that ran across every panel; two soft tube bands and prism sparkle in the diffuser; dimmer lens (2.4); more bloom and per-light haze |
| L010 | 002 | claude | hurts | Dark rooms are flat murky brown, a cutoff instead of a gradient | FIX | S01: flat ambient fill 0.07 to 0.015 so darkness is shaped by spill and bounce; light concentrated into pools |
| L011 | 002 | claude | nitpick | Camcorder overlay never changes; hard cut between camcorder and clean view | FIX | S01: roll-and-snow transition when the camera comes up or goes down; battery drains and the last bar blinks |
| L012 | 002 | claude | hurts | Nothing to film, nothing to find, no threat (pace 4) | FIX (small) + DEFER M4/M5 | S01: one scripted dread beat per run (lights ahead die one by one toward you, the hum dies with them, later they stutter back); the bot stops and films it. Monster M4, run loop M5 |
| L013 | 003/004 | claude (bake-off) | note | Bake-off packets (camcorder off, early build): repeated "nothing happens", "lights stuck on", "perf", "too clean a camera" | DONE (as engine evidence) | Used only to pick the engine (D011). Unique item: carpet read as glossy linoleum in the early build, already fixed by L006. Camera complaints do not apply (camcorder was switched off for a fair engine test) |
| L014 | 005 | claude | hurts | Nothing visibly impossible in a still; splice errors read as glitches, not intent | FIX | S01: deliberate, well-built copy errors: carpeted stairs climbing into the ceiling, a ceiling troffer installed sideways on a wall (lit), chair cut through mid-seat by a wall (progress/0034, 0035). Real non-euclidean spaces stay M2 |
| L015 | 005 | claude | hurts | Floating chairs, no contact shadows | FIX | Soft contact-shadow decals under every grounded prop; chair-in-wall restaged |
| L016 | 005 | claude | hurts | Milky white blobs on wet / flooded carpet | FIX | Cause: SSR of very bright lenses plus large soft light highlights on low-roughness water. SSR off (D012), flooded and wet carpet matte (progress/0031, 0035) |
| L017 | 005 | claude | hurts | Perf 57 fps / 42.5 1% low | FIX (partial) | Haze froxel grid 128x128 to 96x64, SSR off: probe 66 fps avg, 48 1% low (target 60 / 50: average met, lows 2 fps short) |
| L018 | 005 | claude | nitpick | Floor, wall and ceiling are the same tan | FIX | Carpet darker and browner, ceiling partly desaturated toward pale off-white |
| L019 | 005 | claude | nitpick | Wall light pools look like projector spots | FIX | Spot cone falloff 1.8 to 1.25 for broader, softer wall wash |
| L020 | 005 | claude | nitpick | REC dot blinks between frames; heavy tear in one frame | REJECT | A blinking REC dot and occasional tracking tears are what real 1990s camcorders do and they are part of the protected camcorder look. Revisit if it returns twice |
| L021 | 006 | opus gate + gemini | hurts | Ceiling lights throw sideways spotlight arcs and hotspots on walls instead of soft downward fluorescent light; panels still read as stickers; lighting looks flat in motion (Gemini "fullbright", 3/10) | FIX in S02 (top priority) | Likely the 80-82 degree spot cones grazing nearby walls. S02: narrower cones plus a soft unshadowed fill per panel, or retry AreaLight3D without shadows plus shadowed spot for occlusion only; bright tiles around each fixture |
| L022 | 006 | opus gate | hurts | Impossible stairs look unfinished (plain white block) | FIX in S02 | Build the stairs from the same wallpaper, carpet and baseboard as the walls so the building "grew" them |
| L023 | 006 | opus gate | hurts | Chairs read as broken assets (seat floating over legs, chair without base) | FIX in S02 | Procedural office chair model is the culprit when cut by the wall or rotated; use the Sketchfab chair for splices, make splice errors unmistakably deliberate |
| L024 | 006 | opus gate | hurts | FOV 78 plus head tilt makes walls lean and edges stretch; motion sickness risk | FIX in S02 | FOV default 70, roll removed from strafe, keep bob subtle; FOV slider in M5 |
| L025 | 006 | gemini | hurts | Camcorder snaps on like a post-process toggle; wants a raise/lower animation and a physical camera | FIX in S02/M4 | Viewmodel camcorder raised to the eye (0.35 s) before the overlay, and lowered after |
| L026 | 006 | gemini | hurts | Red EXIT glow too saturated and bleeds everywhere | FIX in S02 | Lower energy, tighter range, shadowed; protected item, so keep the beat but make it believable |
| L027 | 006 | gemini | hurts | Carpet looks dry and matte; "carpet that never dries" not sold | FIX in S02 | Bring back a controlled damp sheen without the SSR blobs (clamped reflection or roughness-limited specular) |
| L028 | 006 | gemini | ruins it | Perf 72 / 53 seen as heavy for empty rooms; QA measured 56-58 / 44-46 under GPU contention | FIX in S02 | Profile shadow updates per frame, SDFGI cascades, spot count in view; target 1% low above 50 reliably |
| L029 | 006 | opus gate | nitpick | Haze washes out bright rooms; ceiling color mismatch in one frame; floor papers glow | FIX in S02 | Lower fog density in lit rooms; check desaturated ceiling vs GI; fallen tile and footprints albedo |
| L030 | 006 | gemini | hurts | Sound 4/10 (first sound score ever) | DEFER M3 (and quick wins in S02) | Mix is quiet (about -25 LUFS); sound milestone is M3 |

## Closed

| ID | First seen | Source | Issue | Resolution |
|---|---|---|---|---|
