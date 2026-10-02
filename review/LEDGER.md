# Critic LEDGER

Every issue from every critique (Claude critic, Gemini critic, Stewart) gets one row.
Status: FIX (then fixed in commit X), DEFER (to milestone), REJECT (real reason), DONE (fixed and not repeated by the next critique).
A REJECT that returns in 2 later critiques must become FIX or go to NEEDS_STEWART.

## Protected ("working, don't touch")
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

## Closed

| ID | First seen | Source | Issue | Resolution |
|---|---|---|---|---|
