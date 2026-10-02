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

## M3.5: Look pass (effort: xhigh) (added S03)
The critics' weakest categories after S03 are Lighting (Gemini 4 to 6, Claude 6), Shadows and depth (Gemini 4 to 5) and Materials (4 to 7); the ship gate needs 8. One focused session before the Entity:
- Corner occlusion strips along every wall base, ceiling line and vertical corner (deterministic, visible on video), contact shading under all props.
- GI: more warm bounce color while darkness comes from fewer lit panels, check auto-exposure compression, lit surfaces near panels.
- The held camcorder out of frame until late in the lift (L092), door slabs with hinges and kick plates, better partitions, tall-room upper walls (L094).
- Exit: Gemini and Claude Lighting and Shadows 7+ on two consecutive loops.

## M4: The Entity (effort: xhigh)
- Design per VISION, Meshy to Blender pipeline, animation set, shader distortion, VHS face smear.
- AI: senses, stalking, investigation, chase, using portals and loops, readable tells.
- Death and the VHS death replay.
- Exit: critic Monster and Atmosphere at 7 or higher on both critics.

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
