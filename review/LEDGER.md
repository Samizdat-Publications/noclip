# Critic LEDGER

Every issue from every critique (Claude critic, Gemini critic, Stewart) gets one row.
Status: FIX (then fixed in commit X), DEFER (to milestone), REJECT (real reason), DONE (fixed and not repeated by the next critique).
A REJECT that returns in 2 later critiques must become FIX or go to NEEDS_STEWART.

## Protected ("working, don't touch")
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
| L005 | 001 | claude | hurts | Shadow edges look stair-stepped (frame_04, _10, _19) | FIX (verify) | Fewer overlapping shadowed lights per pixel, soft PCSS kept. Re-check in loop 2 |
| L006 | 001 | claude | nitpick | Glossy floor puddles read as sliding blobs, inconsistent with matte carpet | FIX | Wet-patch roughness 0.34 to 0.48, dry carpet less specular, heathered fiber variation |
| L007 | 001 | claude | nitpick | Camcorder view in the dark is unreadable mud; tracking tear looks like a glitch | FIX | Auto gain brightens the camcorder image in the dark (with more snow); tracking wobble halved |

## Closed

| ID | First seen | Source | Issue | Resolution |
|---|---|---|---|---|
