# Player Review

## Gut reaction
The yellow wallpaper corridor still looks like a real place, and the tripod-camera closet is the one frame I'd screenshot. The big pillar hall is a different story: green fog, copy-pasted columns and a flat floor. It looks like a tech demo, not a place that wants to hurt me. The camcorder view is the best idea here, because it makes the ordinary look wrong. The thing I see on tape is a small blue-black cutout that jitters in a hallway, and it didn't scare me. The game looks decent and has a strong hook, but it's too clean and too empty for the dread it's selling.

## Scores (1 to 10, or N/A)
| Category | Score | Why (one line) |
|---|---|---|
| First impression / screenshot-worthiness | 6 | The yellow corridor (frame_02, frame_05) is instantly readable. Everything else is a repeat of it or a green column field. |
| Lighting | 6 | The pooled panels and red EXIT bounce (frame_03) are lovely. Most halls are evenly lit mush, and frame_13 is a black rectangle. |
| Shadows and depth | 6 | Pillar contact shadows and fog falloff give real depth (frame_16, frame_17). The pillars are untextured slabs with notched, jagged caps. |
| Materials and surfaces | 6 | The chevron wallpaper, ceiling stains and carpet grain are good up close (frame_19, frame_09). The pillars are flat mint plastic and the carpet in the pillar hall is a bland sand sheet. |
| Atmosphere and dread | 5 | Rooms and corridors have unease. The green pillar hall feels like a screensaver, and the monster being small and cartoonish takes the air out (sheet_01). |
| Camera and image feel | 7 | The VHS overlay, REC dot, timestamp, warped geometry on turns and tracking tear (frame_01, frame_04, sheet_02) all feel right. Frame_04 blows out into white scribble that hides the scene. |
| Surreal / impossible-space wow | 6 | The lit doorway into the white pillar room (frame_03) is a good beat. Frame_08 is a streaky light smear that looks like a rendering fault, not a surreal moment. |
| The monster | 4 | A flat dark-blue jittering silhouette with spindly arms, glimpsed small down a corridor (sheet_01). The idea of "only on tape" is great. The execution reads like a sticker. |
| Sound | N/A | Stills only. |
| Pace and fun | 5 | I can't judge pace from stills. The frames I have are mostly empty halls and one prop room, and nothing in them tells me what to do or why to hurry. |
| Performance | 5 | 72 fps average at 1440p on a 5070 Ti laptop is low for this little geometry. The 1% low is 32 fps and one frame took 135 ms, which is a visible stutter. |
| Would I keep playing | 6 | I'd go through a few more doors for the tape-only monster idea. I'd stop if the pillar halls keep dominating. |

## Top problems (ranked, max 7)
1. [hurts] The monster doesn't scare me. In sheet_01 it's a small flat blue silhouette with a jittery outline and arms held out like a mannequin. It looks like a sprite and has no weight in the corridor. I want something I can't quite parse and whose scale and wrongness make me lower the camera.
2. [hurts] The pillar hall (frames 14 to 18, 21, sheet_03) is the weakest-looking area. It has uniform mint-green columns with chipped tops, an even sand floor and thick green fog. It reads as a repeated primitive. I want varied wear, dirt, mold, more fixtures, one wrong thing in the grid, and lighting that carves it up instead of flat haze.
3. [hurts] The "EXIT" sign reads mirrored in frame_03 and frame_11. It's backwards, which looks like a bug. If it's deliberate it needs to read as deliberate, because right now it looks like a flipped texture.
4. [hurts] Performance is a stutter risk for a game this simple. Average 72 fps is low for 1440p on this hardware. One 135 ms frame and a 32 fps 1% low would break tension in a slow-burn horror game, exactly when I'm holding still.
5. [hurts] Some views are unreadable. Frame_13 is near-black with no cue to go anywhere. Frame_08 is a bright streak across a dark room, like a smeared light. Frame_04 blows out into white scratches. I want darkness that hides things and still lets me see shape.
6. [nitpick] The corridors repeat. Frames 02, 05 and 09 are the same hall, and the long sightlines are symmetrical and lit identically. Break the rhythm with a light that's out, a wrong door or a turn.
7. [nitpick] The ceiling tiles and wallpaper tile visibly in the hall frames (frame_02, frame_09). It's fine when you're moving but obvious when you stop.

## Working, don't touch
- The yellow chevron wallpaper with baseboards, outlets and the diagonal scrape (frame_02, frame_05).
- The tripod closet in frame_19. It has a warm single-source pool, a black cabinet shadow, a stencil, a VHS tape on the floor and water-stained tiles. It tells a story in one image.
- The doorway into the white pillar room with the red EXIT glow bouncing on the ceiling (frame_03). This is the most screenshot-worthy shot.
- Pooled light in the large dark room (frame_10, sheet_02): a bright pool, a lone crate and a red spot.
- The camcorder overlay, battery pips, timestamp and tracking glitch. The wrong-footed "look through it" graffiti in frame_01 is a smart way to teach the mechanic.
- Fog falloff that hides the far end of the pillar hall and leaves a faint red EXIT point to walk toward (frame_17, frame_18).

## Compared to last build
- **Pillar hall: worse.** Previously it was a cold gray-blue (prev_05) with a ladder and a lit EXIT. Now it's an olive green wash with chipped pillar caps. It looks sicker but also flatter and more repetitive.
- **Monster: lateral at best.** The old build had a distant humanoid in the corridor (prev_01). The new one has arms out and jitter (sheet_01), and it still isn't scary.
- **Tripod closet: same.** The fallen crate and tape are repositioned, the extra tally marks are gone, and the large shadow of a figure on the wall is gone (prev_04 vs frame_19). That shadow was the creepiest part, and I'm sorry to see it go.
- **Corridor: same.** The doorway view (prev_02) is replaced by frame_09 and others.
- **Performance:** I can't compare, because I don't have an old perf.json.

## Steam review one-liner
Great idea (a camcorder that shows what's really in the rooms), the yellow office halls are authentic, but the pillar field and the cardboard-cutout monster aren't scary yet. Wishlist for now.

## What I want next
- Make what the camcorder sees genuinely disturbing: scale, motion that's hard to follow, and a presence in the room even when the camera is down.
- Rebuild the pillar hall so it feels abandoned, with variation, mess and light that picks out wrong things in the dark.

I also couldn't play /video/clip.mp4 (review/inbox/video/clip.mp4), so everything about motion comes from the four sheets.
