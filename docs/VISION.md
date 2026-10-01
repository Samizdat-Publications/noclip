# VISION: the creative bible

Everything here is a strong starting point, not a cage. You have authority to change it. When you change something, log it in DECISIONS.md and update this file so it stays the truth.

## Pillars
1. **Real enough to be wrong.** Photoreal-leaning light and materials. The uncanny comes from realistic surfaces arranged in impossible ways, not from stylization.
2. **Dread over jump scares.** Silence, anticipation, wrongness. Scares are rare and earned. The film's tone is dreamlike psychological dread, not a haunted house.
3. **Space is the enemy.** Non-euclidean geometry disorients, traps, and lies to you. It is never a puzzle gimmick, and it is always fair (no softlocks, no unreadable cheap deaths).
4. **Every run leaves a mark.** You always come back knowing or owning something new, and the Backrooms remember you.
5. **Sound is half the game.** Players should be able to play with their eyes closed for ten seconds and still feel exactly where they are.

## Tone reference
The 2026 film plays the Backrooms as endless liminal spaces that feel like warped memories of real places: mostly clean cinematic images, with VHS camcorder footage used sparingly. We do the same. The normal view is cinematic and grounded. The camcorder is a device in your hands, and what it shows is where the horror lives. Do not copy the film's creatures, story, or shots. Capture the feeling only.

## Game concept (working title: NOCLIP)
You slipped out of reality and you are holding a camcorder. Go deeper, film what you find, and try to get back out with the tape.

### Moment to moment
- **Movement:** walk, sprint (stamina, loud on wet carpet), crouch (quiet), peek around corners, interact. Grounded, slightly heavy camera with natural inertia.
- **The camcorder (hold right mouse):** the view snaps to a 4:3 VHS image with REC, timestamp, and battery. Infrared mode sees in darkness but drains the battery fast. The camera shows things the naked eye does not: the shimmer of a portal edge, the seam that is an exit, and sometimes the Entity standing where your eyes see an empty hallway. Filming anomalies earns Tape. "The camera sees what you can't" is the core hook.
- **Drift:** a hidden disorientation value. It rises with time in impossible spaces, darkness, and when the Entity is near. It falls under steady light, near stable landmarks, and with grounding items. High Drift means stronger distortions, warped audio, lights failing, and a more attentive Entity. No meter on screen; the player reads it through the image and the sound.
- **Exits (Seams):** each level hides one to three exits: a patch of wall you can noclip through, an elevator that should not exist, a stairwell going down. Finding them is the goal. Each level type has a learnable tell.

### The run
Start at Level 0, descend through procedurally generated levels, and the run ends when you die or when you take a Seam marked as a way back up. Either way your tape is "recovered". On death, play the last 20 seconds back as a VHS tape with tracking errors (a ring buffer of the player's view). It should feel like found footage of your own death.

### Progression that carries between runs
- **Tape** buys gear: bigger batteries, an IR lamp, an audio recorder that shows the direction of sounds, chalk, flares, a sturdier camcorder.
- **The Backrooms remember you.** Traces of past runs appear in new runs: your chalk marks, wet footprints, and your dropped camcorder where you died. Pick it up and its footage plays, showing how you died, which is also a hint. This is the signature surreal hook. Protect it.
- **Known Seams:** each exit type you discover goes into your notebook. Enough discoveries unlock starting deeper (shortcuts).
- **Lore tapes:** short recorded logs (ElevenLabs voices) that slowly reveal that the place is assembled from misremembered real places. The final level is a warped version of somewhere personal. Keep the story light, environmental, and original.
- Depth record plus a seeded "Daily Descent" so friends can compare runs.

## Levels (original names; reorder, cut, or add freely)
Each level needs its own lighting signature, material set, sound signature, a non-euclidean twist, and an Entity behavior modifier.
| Level | Look and light | Sound | Twist |
|---|---|---|---|
| The Yellow (Level 0) | Mono-yellow office maze, damp carpet, stained wallpaper (original pattern), drop ceiling, fluorescent panels with dead and failing tubes | Mains hum and tube buzz per fixture, squelching carpet, distant thuds | Corridors that loop, rooms bigger inside than outside |
| Underlot | Endless concrete parking structure and warehouse, sodium-vapor orange, wet floors reflecting lights | Long echoes, dripping, a car alarm far away that never moves | Ramps always go down, even when you walk up |
| Pipeworks | Maintenance tunnels, steam, red emergency lights, grates, tight spaces | Hissing, metal groans, heat, pipes knocking back at you | Pipes that run in a loop through themselves |
| The Pools | Endless white tile and still water, soft sourceless daylight, caustics, perfect reflections | Near silence, water lapping, your own footsteps too loud | Beauty as dread. Water that is deeper than the room is tall |
| After Hours | Dark offices and hotel corridors, only your IR and failing exit signs | Air handlers, a TV somewhere, doors | Doors that open onto the room you just left, slightly changed |
| The Run (set piece) | Red-lit corridor, lights dying behind you | Rising roar, your breathing | A chase. Pure adrenaline, used sparingly |

## The Entity (original design; refine freely)
Seed concept: **the Occupant.** A tall humanoid that is a misremembered person. The proportions are slightly wrong (forearms too long, neck a little too long), the face is smeared like a paused VHS frame, and it wears the clothes of nobody in particular.
- **On camera** it moves in stutters, frame-skipping like bad tape. **Off camera** it moves smoothly and quietly.
- **Senses:** hearing first (sprinting, dropped items, the camcorder's beep), then sight. The camcorder's IR light attracts it.
- **Uses the space:** it travels through portals and loops, and it can be in the corridor behind you that you just walked through.
- **Tells, for fairness:** the hum near it dies, lights flicker in its direction, and you hear footsteps in a rhythm that is not yours.
- **Escalation per depth:** more aggressive, new behaviors. Deeper levels add a second entity type of your own design (for example, something that only moves in total darkness). Never use named fan-wiki entities.
- **Pipeline:** Meshy (image or text to 3D, auto-rig, animation and text-to-motion) for the base, Blender headless to distort proportions, add damage and wetness, and retarget. Mixamo is a fallback only (no API, unreliable): put it in NEEDS_STEWART if needed. Vertex-shader distortion and the VHS smear on its face sell the uncanny.

## Non-euclidean toolkit
Build these as reusable systems. They must be seamless (no visible pops in the capture; the critic will catch them), performant, and understood by physics, audio, and AI.
- **Portal doorways:** render-to-texture viewport with synced camera transform, oblique near-plane clipping, recursion depth 1 to 2, seamless teleport on crossing, and audio plus AI pathing through portals.
- **Overlapping spaces:** two rooms occupying the same space. Which one is visible and collidable depends on which door you used (visibility and collision layer swaps).
- **Loops:** the corridor that repeats until you turn around, and the corridor that gets a little longer every time you run it.
- **Unobserved rearrangement:** rooms change only when outside the frustum and occluded (double-check with raycasts). The player sees the result, never the change.
- **Impossible stairs:** going down five flights puts you back on the floor you started from, but the lights are now off.
- **Scale shifts:** a room where the doors are slightly too small, or the ceiling slowly lowers.
- **Rule:** disorientation is the goal, frustration is not. Every space has a way forward.

## Look bible
### Lighting
- Fluorescent panels as real area lights (AreaLight3D or equivalent) with realistic 4000K greenish-yellow light, realistic falloff, and GI bounce off yellow walls tinting everything. This bounce IS the Backrooms look.
- Failing tubes follow real ballast failure patterns (stutter at startup, slow pulse, buzz changes with flicker), not random strobing. Dead panels create pools of darkness that the level design uses.
- Contact shadows and ambient occlusion so nothing floats. Subtle volumetric haze and dust motes in light shafts.
- Slow auto-exposure that adapts like an eye: stepping from a dead zone into light should briefly overexpose.
- AgX or filmic tonemapping. A color grade per level, sickly but not monochrome. Blacks can be deep but silhouettes must stay readable.

### Materials
- 2K to 4K PBR: damp carpet with wet stains and matted fibers (real roughness variation), wallpaper with water damage, peeling seams, and an original repeating pattern, drop-ceiling tiles with stains and the occasional sagging or missing tile, scuffed baseboards, outlets with no purpose.
- Decals break repetition: grime, mold, water lines, scuffs, chalk. Detail normals for close-up quality. Fight visible tiling with macro variation.

### Camera and image
- FOV 75 to 85 (adjustable), subtle head bob (toggle), small camera kick on footsteps, breath sway when still.
- Main view: cinematic and clean. Slight lens character (mild chromatic aberration at edges only, soft vignette), fine film grain, per-object motion blur (toggle). Depth of field only for interaction focus.
- Camcorder view: its own post stack. 4:3, chroma bleed and subsampling, luma noise, tracking wobble, head-switching noise at the bottom, interlacing, auto-gain noise in the dark, autofocus hunting, timestamp and REC overlay. It degrades with Drift and with the Entity nearby.

### Anti-goals (the critic will punish these)
Flat unlit yellow boxes. Neon cyberpunk palettes. Asset-store look. Grain or VHS so heavy it hides bad rendering. Bloom soup. Too dark to read. Obvious texture tiling. Lights that look like stickers. Pop-in and streaming hitches.

## Sound bible
- Fluorescent hum (mains harmonics) plus tube buzz positioned per fixture and changing with flicker state. The overall hum is the bed of Level 0, and its absence is a warning.
- Footsteps per surface and wetness (carpet squelch varies by stain map), clothing rustle, breathing that responds to stamina and fear.
- Spatial audio with HRTF, reverb zones derived from actual room dimensions, occlusion and obstruction (raycast low-pass), and sound traveling through portals.
- An ambience director that controls intensity, including deliberate silence before danger. Rare stingers.
- The Entity sounds wrong: human sounds pitch-shifted, reversed breaths, the rhythm of steps that are not yours.
- Music: minimal synth drones and swells (the film used a synth score), adaptive layers, never wall to wall.
- Consistent loudness normalization for all assets. A full mixer with settings sliders.
- Tools: ElevenLabs sound effects (v2 supports seamless loops) for SFX and ambience beds, ElevenLabs Music for drones and stingers, ElevenLabs TTS and voice design for lore tapes. Procedural synthesis (hum harmonics) where it beats samples.

## UX
- Diegetic HUD: nothing on screen in the normal view except an optional small interaction prompt. The camcorder overlay is the HUD.
- Notebook menu: map sketches, known Seams, gear, tapes.
- Settings: quality presets plus individual toggles, FOV, motion blur, grain, head bob, audio sliders, subtitles for tapes, mouse sensitivity, key rebinding, and a **reduced flicker mode** (photosensitivity: flicker is core to the look, so this option is required).
- Onboarding through level design, not text walls.

## Tool map (all keys are in .env)
| Need | Tool |
|---|---|
| Modular architecture kit, UVs, LODs, lightmap UV2, baking, glTF export | Blender headless Python |
| Props (chairs, desks, vending machine, pool ladder) and monster base mesh | Meshy API (text/image to 3D, retexture, remesh, rigging, animation) |
| Tileable textures and concept art | OpenAI gpt-image or Gemini image models, then a script that makes them seamless and derives normal/roughness/AO; or procedural Blender materials baked to textures (often better for tiling) |
| SFX, ambience, music, voices | ElevenLabs |
| Video plus audio critique | Gemini (strongest current model that takes video) |
| Pixel art (optional) | PixelLab: notebook icons or tape label art only, or skip |
| Animation fallback | Mixamo via NEEDS_STEWART (manual download into `pipeline/incoming/`) |
