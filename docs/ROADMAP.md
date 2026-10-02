# ROADMAP

One milestone per session is the norm; big milestones may take two. Reorder or split freely, and log why in DECISIONS.md. Effort is the recommended Opus 5.5 effort for the session.

## M1: Foundation and look-dev (effort: xhigh)
Status after S01: everything is built (engine chosen by blind bake-off, harness, both critics, hero slice). The exit criterion "Lighting and Atmosphere 7+" is not met yet: best was Lighting 7 / Atmosphere 6 in loop 3, and the gate gave 6/6 (Opus) and 3/4 (Gemini). S02 starts with the gate fixes listed in HANDOFF.
- Environment check and installs (git, git LFS, Node, Python, ffmpeg, Blender, Godot 4.7.x, gh). Confirm GPU rendering works for captures.
- Repo, LFS, .gitignore, layout from CLAUDE.md, private GitHub repo via gh.
- Look-dev spike: the same hero slice of Level 0 (about 30 m x 30 m: corridors, one large open room, a doorway, fluorescent grid with dead and failing tubes, damp carpet, stained walls) in Godot Forward+ at final quality, and a time-boxed three.js WebGPU version (no more than a quarter of the session). Blind A/B by player-critic. Pick the engine; Godot wins ties.
- Review machinery: autoplay bot (simple version is fine), one-command capture harness, review packet, Gemini critic script, scores.csv, LEDGER.md, perf overlay and perf.json.
- Prove the critic guard: ask player-critic to read CLAUDE.md; it must be blocked.
- Exit: harness runs end to end with one command; at least three critic loops on the hero slice; critic Lighting and Atmosphere at 7 or higher.

## M2: Infinite Level 0 and the non-euclidean toolkit (effort: xhigh)
- Seeded, chunk-streamed generator (room grammar, WFC, or graph-based; your call). S01 built Level 0 from code (MeshKit + shaders) rather than a Blender kit; keep that unless a kit clearly looks better.
- Generation loss as a system (VISION, D009): a per-level `fidelity` dial driving splice errors (props clipped into walls and floors, looped-frame repeats, tracking-shear bands), detail loss and color bleed. Level 0 is generation 1.
- Lighting that stays great when procedural: fixture grid grammar, dead-panel clusters, GI that keeps up with streaming, no light leaks.
- Toolkit from VISION: portals, overlapping spaces, loops, unobserved rearrangement, impossible stairs. Navigation that understands portals.
- Exit: a 10 minute bot walk with no seams, hitches, or pops; critic "Surreal / non-euclidean wow" at 7 or higher; perf targets held.

## M3: Sound (effort: high)
- Audio architecture: spatial HRTF, reverb zones from room size, occlusion, per-fixture hum and buzz, footsteps by surface and wetness, breathing, ambience director with silence.
- ElevenLabs asset pass with loudness normalization.
- Exit: Gemini critic Sound at 7 or higher.

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
