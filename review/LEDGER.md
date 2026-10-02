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
| L021 | 006 | opus gate + gemini | hurts | Ceiling lights throw sideways spotlight arcs and hotspots on walls instead of soft downward fluorescent light; panels still read as stickers; lighting looks flat in motion (Gemini "fullbright", 3/10) | DONE (arcs) + FIX (flat fill, see L032) | S02 84cf7cc: panels slid clear of walls, pooled cones, ceiling glow field, lit reveal (D013). 007: arcs no longer mentioned; Opus "panels read as light sources"; Lighting Opus 6, Gemini 4 (was 3) |
| L022 | 006 | opus gate | hurts | Impossible stairs look unfinished (plain white block) | DONE | S02 84cf7cc: wallpaper sides, carpet treads, vinyl nosing, skirt, handrail, climbs through a ceiling gap (D014). 007 Opus lists it under "working, don't touch" |
| L023 | 006 | opus gate | hurts | Chairs read as broken assets (seat floating over legs, chair without base) | DONE | S02: chair faces into the wall with its front buried plus a seam; sunk chair became an upside-down chair on the ceiling (D014). 007 Opus: ceiling chair is "the surreal tone the store page promises" |
| L024 | 006 | opus gate | hurts | Wide FOV plus head tilt makes walls lean and edges stretch; motion sickness risk | DONE | S02: FOV 70, no roll. 007: not repeated |
| L025 | 006 | gemini | hurts | Camcorder snaps on like a post-process toggle; wants a raise/lower animation and a physical camera | DONE | S02: camcorder model (pipeline/blender/build_camcorder.py) lifted to the eye before the viewfinder cuts in. 007 Gemini lists the transitions under "working" |
| L026 | 006 | gemini | hurts | Red EXIT glow too saturated and bleeds everywhere | DONE + new L037 | S02: weaker, less saturated, shadowed. 007 Gemini silent; Opus: the lamp washes the tiles nicely, but the sign does not read as EXIT (L037) |
| L027 | 006 | gemini | hurts | Carpet looks dry and matte; "carpet that never dries" not sold | FIX (again, see L034) | S02: berber flecks and a damp sheen. 007: Opus Materials 7 and likes the damp patches, but the sheen reads as white smears (Opus) and still dry (Gemini) |
| L028 | 006 | gemini | ruins it | Perf 72 / 53 seen as heavy for empty rooms; QA measured 56-58 / 44-46 under GPU contention | FIX (re-measure) | S02 found the cause of the S01 QA numbers and part of 007: a stuck S01 perf run had been rendering in the background since 8:17 PM (killed), plus an unrelated Blender render on the GPU since 11:00 PM. Clean probe on an idle GPU: 72.5 avg / 54.3 1% low. The 007 packet (56.8 / 33.3) was measured under that contention |
| L029 | 006 | opus gate | nitpick | Haze washes out bright rooms; ceiling color mismatch in one frame; floor papers glow | DONE | S02: haze 0.022 to 0.016, fallen tile darkened, footprints stronger. 007: haze not mentioned |
| L030 | 006 | gemini | hurts | Sound 4/10 (first sound score ever) | DEFER M3 (and quick wins in S02) | Mix is quiet (about -25 LUFS); sound milestone is M3 |
| L031 | 007 | opus gate + gemini | ruins it | Nothing happens on screen; the camcorder never shows anything the eye cannot (both critics, both ask for something only the viewfinder reveals) | FIX in S02 (M2) | M2: tape-only Seams (doors in walls visible only through the camcorder), the looping corridor; staged moment early in the run |
| L032 | 007 | opus gate + gemini | hurts | Flat fill: corners, side rooms and pillars all mid-yellow; pillars cast no shadow; "about two values of darkness"; Opus says the darkness got worse than the S01 gate build | FIX in S02 | Less GI fill, auto exposure no longer lifts dark rooms as much, sharper panel shadows, SSAO allowed to darken direct light, contact shading at pillar bases, more dead side rooms |
| L033 | 007 | opus gate | hurts | Layout repeats (the same corridor, footprints and box in four frames) and reads as a reused tile | FIX in S02 (M2) | The infinite generated level replaces the 30 m hero slice; footprints become rarer |
| L034 | 007 | opus gate + gemini | nitpick | Wet carpet sheen reads as bright white smears (Opus); carpet still looks dry (Gemini) | FIX in S02 | Replace the light highlight with a soft, blurred reflection of the panels above in wet patches (fixture field), warm, never a hot spot |
| L035 | 007 | opus gate | nitpick | Ceiling tint jumps between neighboring tiles with a hard edge (stained tiles are whole tan squares) | FIX in S02 | Stains as soft blotches within a tile instead of a whole-tile swap |
| L036 | 007 | gemini | hurts | Generic asset feel: wallpaper, tiles and doors look stock | DEFER M2/M3 | Needs more unique set dressing per area; the generator adds landmarks; revisit after the generated-level critique |
| L037 | 007 | opus gate | nitpick | Exit lamp reads as a "sunset nightlight", not EXIT; the door under it opens onto a flat wall | FIX in S02 | Bigger, readable sign; in the generated level exit signs hang over real passages |
| L038 | 007 | gemini | note | Sound N/A: Gemini said no audio track, but clip.mp4 has AAC audio (checked with ffprobe) | WATCH | Mix now -19.9 LUFS (was -26.5). If Gemini misses the audio again, send the audio as a separate file too |
| L039 | 008 | claude | hurts | Everything is one yellow; no sense of place after five minutes; the red exit sign accent was missing from this set | FIX in S03 | Rooms with a different color temperature (cold replacement tubes, a sodium-orange room, a wrong-colored wall), exit signs more frequent near halls |
| L040 | 008 | claude | hurts | The tape-only figure reads as a stiff, aliased mannequin, centered, barely moving | FIX in S03 | Off-center placement, a little closer each time, subtle sway and frame-skip motion, softer silhouette edge (keep it an absence, not a monster; M4 owns the Entity) |
| L041 | 008 | claude | hurts | Big blank walls are dead space; wallpaper repeat too clean | FIX in S03 | More wall detail where the eye lands: tape marks, scuffs, posters removed (pale rectangles), water damage, more graffiti; macro variation of the pattern |
| L042 | 008 | claude | hurts | Lit rooms evenly filled; want one pool of light and falloff | FIX in S03 | Fewer lit panels per room, more single-panel rooms, partial dead rows |
| L043 | 008 | claude | hurts | The loop and the surreal hook are not legible in stills; wants one unmistakable "that is wrong" frame | FIX in S03 | Make the bot traverse the loop in captures (it turned back this run), a focus shot of the repeated chair/tally, scale-error rooms, more splices in view |
| L044 | 008 | claude | nitpick | Orange cathode rims on dead tubes and the floor troffer look pasted on (no spill) | FIX in S03 | Small orange glow on adjacent tiles via the fixture field; floor troffer needs spill on carpet and a frame |
| L045 | 008 | claude | nitpick | Crushed blacks in dark frames; a dead room can go fully black | FIX in S03 | Raise the floor of auto exposure / a little ambient in dead zones; every dead room keeps a weak source |
| L046 | 008 | gemini | ruins it | The tape figure looks like a low-poly default mannequin painted black (Monster 3); "kills the tension the moment you see it" | FIX in S03 | Same as L040, now top priority: break the silhouette (static, smear, partial dropout, wrong proportions in motion), never show it clean or centered; M4 designs the real Entity |
| L047 | 008 | gemini | hurts | Footsteps sound like hard shoes on dry concrete; carpet looks bone dry (corkboard) | FIX in S03 (quick) / M3 | Swap in squelchier wet-carpet steps on wet patches, louder; stronger damp darkening and the panel reflections in wet patches; repeat of L027/L034 |
| L048 | 008 | gemini | hurts | Camcorder still feels like an instant toggle in the video | FIX in S03 | The 0.3 s lift is too short to read at 30 fps; lengthen to about 0.5 s, show more of the body and hands-free sway, delay the overlay until the eyecup |
| L049 | 008 | gemini | hurts | No corner occlusion where walls meet floor and ceiling in lit rooms; 75 fps judged heavy for bare corridors | FIX in S03 / M7 | Baked corner darkening in the wall shader (distance to the wall's ends), check light culling through walls; perf pass is M7 |

## Closed

| ID | First seen | Source | Issue | Resolution |
|---|---|---|---|---|
