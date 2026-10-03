# ROADMAP

One milestone per session is the norm; big milestones may take two. Reorder or split freely, and log why in DECISIONS.md. Effort is the recommended Opus 5.5 effort for the session.

## M1: Foundation and look-dev (effort: xhigh)
Status after S02: CLOSED WITHOUT PASSING THE GATE (two honest attempts, D019). Everything is built (engine chosen by blind bake-off, harness, both critics, hero slice). Gate attempt 1 (S01): Opus 6/6, Gemini 3/4. Gate attempt 2 (S02, after the L021 to L029 fixes): Opus Lighting 6 / Atmosphere 5, Gemini 4/6. The named causes (nothing happens, the camcorder shows nothing, the 30 m slice repeats, flat fill) are M2 work and are re-judged in the M2 loops.
- Environment check and installs (git, git LFS, Node, Python, ffmpeg, Blender, Godot 4.7.x, gh). Confirm GPU rendering works for captures.
- Repo, LFS, .gitignore, layout from CLAUDE.md, private GitHub repo via gh.
- Look-dev spike: the same hero slice of Level 0 (about 30 m x 30 m: corridors, one large open room, a doorway, fluorescent grid with dead and failing tubes, damp carpet, stained walls) in Godot Forward+ at final quality, and a time-boxed three.js WebGPU version (no more than a quarter of the session). Blind A/B by player-critic. Pick the engine; Godot wins ties.
- Review machinery: autoplay bot (simple version is fine), one-command capture harness, review packet, Gemini critic script, scores.csv, LEDGER.md, perf overlay and perf.json.
- Prove the critic guard: ask player-critic to read CLAUDE.md; it must be blocked.
- Exit: harness runs end to end with one command; at least three critic loops on the hero slice; critic Lighting and Atmosphere at 7 or higher.

## M2: Infinite Level 0 and the non-euclidean toolkit (effort: xhigh)
Status after S03: CLOSED WITHOUT PASSING THE GATE (two attempts, D028). Built in S03: loop jump verified invisible (horizon fade D020), tape-only seams into survey pockets (D022), scale-error tall rooms (D023), unobserved rearrangement (D025), tape figure v4 (D021), streaming steps under 7 ms, perf 87 to 102 fps at 1440p (D024), 10-minute walk clean. Gate: Opus Surreal 6 both times (Gemini 8, then 6). Open: portal doorways, overlapping spaces, impossible stairs, four-turn loop; halls too evenly lit; corridor sameness.
Status after S02 (started): infinite chunk-streamed Level 0 (Level0Gen BSP rooms, shared-edge connectivity, highways = long vanishing-point halls, pillar halls, dark rooms, splice errors incl. a troffer set into the floor), stepped deterministic streaming with a light pool, the loop corridor (identical sealed copies, silent repeat until you turn around), the tape-only figure (render layer 11), graffiti from earlier lost people (Gemini decals) with fair hints. Still to do: portal doorways / tape-only Seams (exits), overlapping spaces, unobserved rearrangement, impossible stairs, the four-right-turns loop, scale-error rooms, Stewart's layout language (plus-shaped columns, T/L partitions, wall fins, stepped walls), verify the loop jump on video, perf pass with streaming.
- Seeded, chunk-streamed generator (room grammar, WFC, or graph-based; your call). S01 built Level 0 from code (MeshKit + shaders) rather than a Blender kit; keep that unless a kit clearly looks better.
- Generation loss as a system (VISION, D009): a per-level `fidelity` dial driving splice errors (props clipped into walls and floors, looped-frame repeats, tracking-shear bands), detail loss and color bleed. Level 0 is generation 1.
- Lighting that stays great when procedural: fixture grid grammar, dead-panel clusters, GI that keeps up with streaming, no light leaks.
- Toolkit from VISION: portals, overlapping spaces, loops, unobserved rearrangement, impossible stairs. Navigation that understands portals.
- Exit: a 10 minute bot walk with no seams, hitches, or pops; critic "Surreal / non-euclidean wow" at 7 or higher; perf targets held.

## M3: Sound (effort: high)
Status after S03: EXIT CRITERION MET (Gemini Sound 8, 8, 8 in critiques 013, 014, 015; 7 and 8 at the M2 gates), gate with Stewart's listening notes pending. Built (D026): room reverb zones by size, positional squelch footsteps, wall occlusion for hum and buzz, breathing driven by stamina and fear, world duck and a drone while the tape figure is out, distant one-shots, work-light hum, seam draft, tape dropouts, reversed breath, dying tubes; the PCM decode bug fixed (every generated sound had been an octave low). Still to do: HRTF (Steam Audio GDExtension, deferred), music layers, an ambience director that stages silence before events, a mixer with settings sliders.
- Audio architecture: spatial HRTF, reverb zones from room size, occlusion, per-fixture hum and buzz, footsteps by surface and wetness, breathing, ambience director with silence.
- ElevenLabs asset pass with loudness normalization.
- Exit: Gemini critic Sound at 7 or higher.

## M2b: Impossible rooms (effort: xhigh) (added S04, Stewart's priority, D034)
Stewart asked for rooms that are small outside, giant inside, and loop back paradoxically. The M2 toolkit pieces never built in S03 come first:
- Portal doorways: render the destination through the doorway, cross seamlessly (no visible jump, no GI or fog pop), audio and the bot pass through.
- A room bigger inside than outside: a small office you can walk all the way around whose door opens onto a giant hall; the hall's far exit leads back somewhere impossible (into the hall you came from, facing the small room's door from behind, or into a copy of the start).
- Then: overlapping rooms (two rooms in one space, which one you are in depends on the door), impossible stairs, the corridor that grows each time you run it.
- Crawl and climb (Stewart, S04): crawl automatically into openings too low to crouch through (or hold Ctrl), climb ladders by walking into them; low crawl holes between rooms, square openings high on walls with ladders, ladders up through a missing ceiling tile into the plenum (crawl over the rooms, drop out elsewhere).
- Exit: both critics Surreal 7 or higher on two loops, no visible seam at a portal on video, perf targets held, Stewart's notes.
- Status S04: storeroom portals into a hall under the level, far door back out of the storeroom (D036), crossing filmed seamless (progress/0134 to 0137); crawl stance, crawl holes and tall-room ladders (D037). Critics: Surreal 7 and 8 (019), 8 and 8 (020): the Surreal part of the exit is met on two loops. Not built yet: overlapping rooms, impossible stairs, the growing corridor, the plenum crawl.

## M3.5: Look pass (effort: xhigh) (added S03)
The critics' weakest categories after S03 are Lighting (Gemini 4 to 6, Claude 6), Shadows and depth (Gemini 4 to 5) and Materials (4 to 7); the ship gate needs 8. One focused session before the Entity:
- Done in S03: corner occlusion strips (D031); hum drift and power sags, carpet rolls and anti-tiling, rectangular light pools (D032).
- Corner occlusion strips along every wall base, ceiling line and vertical corner (deterministic, visible on video), contact shading under all props.
- GI: more warm bounce color while darkness comes from fewer lit panels, check auto-exposure compression, lit surfaces near panels.
- The held camcorder out of frame until late in the lift (L092), door slabs with hinges and kick plates, better partitions, tall-room upper walls (L094).
- Exit: Gemini and Claude Lighting and Shadows 7+ on two consecutive loops.

## M3.6: Remembered wrong, batch 1 (Stewart, S04; see VISION "Remembered wrong")
- Look toward the reference stills: cleaner, more saturated mono-yellow, brighter panel rows, plain walls with grime concentrated, huge plain blocks and columns.
- Generator rules for the first tricks: handle-less doors, freestanding door frames, mirrored or almost-right signs, category objects (solid filing cabinet, bottle-less water cooler), chairs facing walls, the floor opening that looks down onto the level below's lit ceiling.
- Status S05: built. Look moved toward the stills (D038: saturated mustard paper, grime in patches, cream ceiling with a bounce glow, light grid, brighter panels); storeroom halls with their own palettes, painted columns, handle-less doors, a lit far door (D039); the hall lit by a sparse grid of stronger panels so columns throw shadows (D043); remembered-wrong batch 1 as learned misunderstandings per 3 x 3 block of chunks (D040: all seven tricks above plus blind panels). The held camcorder turned the right way round with a flip-out screen (D041). Next batch: windows into the wall cavity, switches at ankle height, clocks with no hands, carpet running up a wall, the corridor that narrows, the plenum crawl.

## M4: The Entity and the watchers (effort: xhigh)
- Abstract and plural (Stewart, S04): the Occupant as a strip-cut outline of wallpaper driven by the Meshy C_4 rig; the Dropout, a hole in the recording that slides along walls; the watchers layer (the high door that opens a crack, peripheral figures, things drawing back from wall openings).
- Status S05 (started, D042): the Occupant is in (strip shader on the rig, nine clips, held frame-skip poses) as the tape encounter's body; the watchers: the high door that opens with a papered head looking out, the figure at the edge of sight. Final critics: Monster 5 (Claude) and 3 (Gemini): it fails when seen plainly (L156). Not yet: its presentation fixed, the Occupant hunting (senses, stalking, chase through portals and loops), the Dropout, things drawing back from wall openings, the VHS death replay. Session 06 continues M4 (effort xhigh), after Stewart's play notes, with the level's lighting balance (L155) alongside.
- Status S06: the Occupant works when seen (D044: by eye a bend in the picture and a shadow, at the edge of sight a dark silhouette, on tape a hole in the recording that is a solid black shape far away and a torn one close up; long forearms, hanging arms) and it hunts (D045: comes from behind, follows at a shrinking distance, footsteps a beat late, hiccupping panels, the hum sinking; hears running and the record beep, sees you lit, knows when it is filmed; once a hunt it stands two meters behind you when you stop; notice, the lights going out toward you, a chase that can be escaped, through storeroom doors, never into a seam). Death: the VHS replay (D046), waking at the start, your camcorder left where you died with its tape (press E). Stewart's scares (D048): the dragged Halden technician, the head round a doorway. The Catalogue (D049) as the first piece of progression. Critics: Gemini Monster 3 to 8 then 7, Sound 9, Atmosphere 8; Claude Monster 4 (wants it close and big: answered by the close beat after 026). Not yet: the Dropout, things drawing back from wall openings, losing the thread to Drift.
- Design per VISION, Meshy to Blender pipeline, animation set, shader distortion, VHS face smear.
- AI: senses, stalking, investigation, chase, using portals and loops, readable tells.
- Death and the VHS death replay.
- Exit: critic Monster and Atmosphere at 7 or higher on both critics.

## M4.5: Halden field teams (Stewart, S04)
- Teams of two to four in white clean-room suits documenting rooms (filming, measuring, chalking codes), who stop and turn to you when you come in, then ignore you, back away, warn you off, leave a crate, or kill the lights and lock the door. Meshy characters with the same rig and animation pipeline as the Entity.

## M5: The run loop and progression (effort: high)
- The Store hub (VISION "The Store"): the taped-wall Threshold into a Level 0 Space built behind it, one continuous step.
- Halden Duplicating's buyer in the hub: trade recovered tapes for gear (VISION, D010).
- Full loop: start, descend, Seams, Tape, death or escape, recovered tape.
- Meta progression: gear, Known Seams shortcuts, lore tapes, past-run echoes (chalk, footprints, dropped camcorder with replay), depth record, Daily Descent.
- Menus, notebook, settings (including reduced flicker mode), save system.
- Exit: critic "Would I keep playing" at 7 or higher; Stewart plays one full run.

## M6: Deeper levels (effort: xhigh; likely two sessions)
- Underlot, Pipeworks, The Pools, After Hours, and The Run set piece, each with its own lighting, sound, twist, and entity modifier. A second entity type.
- Each level is a later generation (lower fidelity). Halden field teams appear: tripod cameras, tape crates, degaussed sectors, a team crossing a far corridor.
- Exit: each level scores 7 or higher on Lighting and Atmosphere in its own capture.

## M7: Ship (effort: high)
- Quality presets, laptop performance pass with upscaling, 30 minute crash-free soak run, error logging.
- itch.io page (butler), trailer captured from the game, store_page.md finalized.
- Exit: qa-auditor full pass, URL live (login steps in NEEDS_STEWART if needed).

## M8+: Polish loops (effort: high)
- Pure critic-driven iteration until the ship gate in CLAUDE.md is met twice in a row.
