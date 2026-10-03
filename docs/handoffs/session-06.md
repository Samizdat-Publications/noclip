# Handoff: session 06 to 07 (10/03/2026)

## State in one paragraph
Session 06 was M4, worked overnight in Stewart's order. The Occupant works when seen and it hunts (D044, D045): by eye it is only the room bent where it stands and a shadow with nothing to throw it; at the edge of sight a dark silhouette; on tape a hole in the recording, a solid black shape far away and a torn one held together by a few strips of wallpaper up close, forearms and neck too long, arms hanging. It comes from behind about a minute into a run (sooner if you film it at the end of a hall, or after the body scene), follows at a shrinking distance with footsteps that answer yours a beat late, hears running and the record beep, knows when it is filmed, stands two meters behind you once a hunt when you stop, screams and puts the lights out toward you, and chases you (escapably) through storeroom doors but never into a seam; on tape the chase is held frames of a run, a lunge, a scream and a crouch, never a plain sprint. If it gets you, the VHS death replay plays your last 16 seconds and you wake at the start with your camcorder blinking where you died; stand by it and press E to watch its tape (D046). Stewart's scares: a dead Halden technician (new Meshy model) dragged feet first out of sight, a dark head leaning round a doorway (D048). The level is lit in pools while its opening stays bright (D047); each storeroom hall has a collapse, a free-standing wall, a patch of other tubes and a chair lit by a monitor left on. Progression starts with the Catalogue (D049): what you film goes on the tape and onto a shelf kept between runs. The worst stutter (stepping into a hall) is fixed. Gemini's last loop (029) was its best: Atmosphere 8, Surreal 8 ("the shadow on the wall with no monster casting it is brilliant"), Sound 9, Keep playing 8. Gemini Lighting 4 and Shadows 3 never moved, and Claude's Monster stayed 4 to 5 (it wants it close, big and believable in stills).

## Playable now (exact run command)
- Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip`. WASD, mouse, Shift sprint, Ctrl crouch, Z crawl, hold right mouse for the camcorder, E by your dropped camcorder to play its tape, Esc pause (shows what is on your tape; Q quits), F3 performance overlay.
- Clean checkout (ced59ca): a fresh clone with `git lfs pull` imports with 0 errors and runs 900 frames of autoplay on seed 4242 with 0 script errors.
- Review capture: `python tools/capture/capture.py`. Never edit game/ or tools/ while it runs.
- Builder options: `--hunt_at=S`, `--no_hunt`, `--drag_at=S`, `--no_scares`, `--no_replay`, `--found_test`, `--show_vm` (the old held camera), `--log-hunt`, `--log-scare`, `--log-watch`, `--log-catalogue`, `--log-hall`, `--log-spikes` (perf runs), `--shots_at=t1,t2,...` (capture stills at those game times), `--fresh_catalogue`, `--strong_gain`, `--glow_blend=screen|softlight|add`, `--glow_th`, `--glow_i`, `--still_readback`.

## Done this session (each with commit hash and evidence)
- The Occupant's looks and proportions (D044; e701698, 79a13f4, bab4328): look-dev progress 0222, 0223, 0227, 0228; first filmed hunts 0229, 0230; chase poses 0250.
- The hunt (D045; e701698, 86a3b49): headless runs on seeds 4242, 777, 2024, 90210, 5150 log stalk, the close beat ("right behind you"; "filmed up close: it screams" on 90210 and 5150), notice, chase, catch (QA claims 3 and 4 PASS). Escape rules in 86a3b49.
- The VHS death replay and the dropped camcorder's tape (D046; e701698, 79a13f4): "[replay] start: 240 frames (16.0 s), 16.0 s of sound"; progress 0230, 0240 (QA 5 and 6 PASS).
- Pooled lighting (D047; 8f71c66, 86a3b49): progress 0231, 0244.
- The dragged Halden technician (D048; acce623, 86a3b49): model 0221, 0225, 0226; the drag 0232 (QA 7 PASS). The head round a doorway: 0233; after ced59ca it shows on 4 of 6 seeds in headless runs (777, 2024, 90210, 5150), not on 4242 or 31337 (QA 8 FAIL as first written).
- The Catalogue (D049; acce623): end card "ON THE SHELF n / 14" (0240, 0250; QA 9 PASS).
- Paper sounds, eyecup lift, column occlusion, glow (79a13f4): Gemini Sound 6 to 9 in 026; eyecup 0241.
- Storeroom hall variety (86a3b49): 0245 (QA 12 PASS). The hall-entry stutter (f0ffd8b): worst frame 133 to 72 ms on seed 865723.
- 29 ElevenLabs sounds (pipeline/audio/build_s06.py, about $0.31), the Halden technician (pipeline/meshes/build_halden_tech.py, 62 Meshy credits).
- Critic loops 025 to 029, Claude and Gemini each; ledger L161 to L200; decisions D044 to D049; VISION fail states and progression.

## Not done / known broken (be blunt)
- Gemini scores Lighting 4 and Shadows 3 every loop ("flat, no AO, stickers", "the tripod casts no shadow"); Claude splits 6 to 7. The bright clean rooms are Stewart's reference stills; Stewart has not yet said whether the yellow level should stay bright or go darker (Claude 029 asks for the darker red-lit mood as the default).
- Claude's Monster stays 4: up close on tape it is "a flat black cutout with speckle, no weight". Gemini wants it to look like torn moving wallpaper, as the store page says. The paper look is only on the high-door peek.
- Two "Texture is not a valid texture" errors appear at the respawn after a death; not the portal stills (tested); no visible effect seen. Source unknown.
- Performance on hall seeds: 72 to 79 fps average at 1440p, 1% lows 30 to 44 (every capture's perf runs this session shared the GPU with another program, flagged "not trusted"); stutters of 35 to 70 ms remain (hall building, the first tape sighting).
- The autoplay bot is caught in nearly every run (it glances back while fleeing); a sprinting human with a head start should escape, untested by a human.
- Not built: losing the thread to Drift (designed in VISION), the Dropout, things drawing back from wall openings, the store hub and gear (M5).
- The mirrored exit signs read as a bug to one critic; the doorway into a lit hall can blow out to white; the carpet reads as sand (L179); corridors need one wrong thing each (L184).

## Critic: latest scores and top open LEDGER items
Columns: First, Light, Shadow, Mater., Atmos., Camera, Surreal, Monster, Sound, Pace, Perf, Keep.
| Loop | Build | Critic | F | L | Sh | M | At | Ca | Su | Mo | So | Pa | Pe | K |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 024 (S05 final) | c557d3d | Claude | 6 | 6 | 5 | 6 | 5 | 7 | 6 | 5 | NA | 5 | 9 | 5 |
| 024 (S05 final) | c557d3d | Gemini | 6 | 4 | 4 | 5 | 8 | 8 | 8 | 3 | 9 | 7 | 9 | 7 |
| 025 | acce623 | Claude | 6 | 6 | 6 | 5 | 6 | 7 | 6 | 4 | NA | 5 | 8 | 6 |
| 025 | acce623 | Gemini | 5 | 4 | 4 | 5 | 6 | 8 | 6 | 8 | 6 | 6 | 8 | 6 |
| 026 | 79a13f4 | Claude | 6 | 6 | 5 | 6 | 5 | 7 | 5 | 4 | NA | 5 | 8 | 6 |
| 026 | 79a13f4 | Gemini | 5 | 4 | 4 | 5 | 8 | 8 | 5 | 7 | 9 | 7 | 6 | 7 |
| 027 | 86a3b49 | Claude | 7 | 7 | 6 | 6 | 7 | 7 | 6 | 5 | NA | NA | 6 | 7 |
| 027 | 86a3b49 | Gemini | 5 | 4 | 3 | 5 | 7 | 8 | 5 | 7 | 8 | 6 | 4 | 6 |
| 028 | f0ffd8b | Claude | 6 | 6 | 6 | 6 | 5 | 7 | 6 | 4 | NA | 5 | 5 | 6 |
| 028 | f0ffd8b | Gemini | 5 | 4 | 3 | 4 | 7 | 7 | 6 | 5 | 8 | 6 | 4 | 6 |
| 029 (final) | bab4328 | Claude | 7 | 7 | 6 | 6 | 6 | 8 | 7 | 4 | NA | 6 | 8 | 6 |
| 029 (final) | bab4328 | Gemini | 5 | 4 | 3 | 5 | 8 | 7 | 8 | 6 | 9 | 7 | 4 | 8 |
Seeds differ per loop (the cold storeroom hall scores best; a yellow or green one worse). 029 is the build Stewart plays except the QA fixes in ced59ca.
Top open LEDGER items: L193 the monster up close, L178 lighting flat for Gemini, L196 bright or dark default (Stewart), L179 carpet, L184 one wrong thing per corridor, L188/L195 the doorway blowing out, L168/L187 hall detail, L165/L158 props, L191 perf on hall seeds, L200 respawn texture errors.
Protected (025 to 029): the VHS look and the REW/PLAY/END OF TAPE screens with the shelf count, the tripod room and its figure shadow, the warm exit at the end of the cold hall, fog depth in the halls, pooled light in long halls, the paper sounds, the wet steps and the hum, the camcorder-only monster and seams, the shadow with nothing to throw it, the distant silhouette in a long corridor.

## qa-auditor result (pass/fail per claim)
Claims: docs/handoffs/s06_claims_draft.md; scratch in review/archive/qa/s06/. 12 PASS, 2 PARTIAL-level notes, 1 FAIL.
1 gdcheck PASS. 2 tests PASS (determinism, spawn seam 0 of 200, closet, wrong 4242). 3 hunt sequence PASS (4242, 90210, 5150). 4 close beat filmed PASS (90210, 5150). 5 replay PASS with errors (two to three "not a valid texture" pairs after the death and 240 leaked textures at exit; the leak fixed in ced59ca, two error lines remain: L200). 6 found tape PASS. 7 dragged body PASS. 8 head round a doorway FAIL on 4242 (the hunt began before its first chance at 48 s; moved to 30 s in ced59ca, then 4 of 6 seeds). 9 Catalogue PASS (7 entries on the bot's shelf). 10 pooled lighting PASS. 11 eyecup PASS. 12 hall variety PASS. 13 critic loops PASS (the final loop was 028 at audit time; 029 ran after). 14 spend PASS. 15 progress copies PASS (0221 onward). 16 no em dashes or secrets PASS (only the verbatim critiques carry em dashes).
Also found: the bot is caught about 4.6 s into every chase; "resources still in use at exit" on movie runs; a headless-only portal still error.

## Next milestone and the first 3 concrete steps
M4 close-out, then M5 (the store hub and gear). Effort xhigh.
1. Read Stewart's first play notes (docs/STEWART_FEEDBACK.md): too deadly or too easy, bright or dark, scary or not. Tune the hunt (CHASE_SPEED, the close beat, FIRST_AT) and the light from them before anything else (L196).
2. The monster up close (L193): the hole lit at its rim by the room, more torn paper on it near the camera, motion that is hard to follow; then losing the thread (Drift) as a second way to fail.
3. M5 start: the store hub with the shelf of tapes (the Catalogue made physical), Halden's buyer, the first gear that opens places (a crowbar for the handle-less doors).

## Gotchas learned
- Never edit game/ or tools/ while capture.py runs: its perf runs start minutes later and load the working tree; a half-edited script made one hang for 10 minutes.
- progress.py and the Gemini critic read the session number from docs/HANDOFF.md: move it only after the last capture and critique.
- A TextureRect with no texture draws nothing, even with a shader material: use a ColorRect for full-screen shader screens.
- RenderingDevice.texture_copy needs TEXTURE_USAGE_CAN_COPY_FROM_BIT on the source; viewport textures have it; textures you create need it if you copy out of them later. Free RD textures a beat after the last material that samples them lets go.
- Each SubViewport builds its own render buffers (GI cascades, haze) on its first frame and again on every resize: warm portal views once when their hall is built and never resize them (Portal.prewarm, stills at the live size). get_image on a viewport texture stalls the frame.
- SkeletonModifier3D._process_modification still runs in 4.7; set_bone_global_pose works inside it.
- Halden and Occupant rigs: bones Hips, Spine02, Spine01, Spine, neck, Head, Left/RightShoulder, Arm, ForeArm, Hand, UpLeg, Leg, Foot, ToeBase; the character faces +z, its left is +x.
- Godot's --script mode does not load autoloads (Game): test tools touching game classes must run inside the game.
- tools/critic_gemini/critic.py writes its own SPEND.md row; do not add one by hand.
- The shell can stall a minute on trivial commands while a capture or another project's Blender is busy; prefer the Read tool for files.

## Decisions made
D044 the Occupant seen four ways, D045 the hunt, D046 the VHS death replay, D047 the level lit in pools, D048 Stewart's scares (the dragged body, the head round a doorway), D049 fails, progression (the Catalogue) and the shape of the world.
