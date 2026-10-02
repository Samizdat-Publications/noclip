# Player Review

## Gut reaction
I've played fifty variations of this exact Backrooms concept on itch.io, and this one doesn't do anything to stand out yet. The pitch promises a surreal, terrifying experience with "carpet that never dries," but what I'm looking at is a sterile, flatly lit maze made of basic primitive shapes and repeating textures. The camcorder mechanic could be cool, but right now it feels like a cheap UI overlay rather than a physical object I'm holding. If you want people to care about another liminal space game, the atmosphere and lighting need to be absolutely flawless, and right now, they look like a first-time engine tutorial.

## Scores (1 to 10, or N/A)
| Category | Score | Why (one line) |
|---|---|---|
| First impression / screenshot-worthiness | 4 | Looks like every other generic Backrooms asset flip; nothing catches the eye. |
| Lighting | 3 | Completely flat and washed out, with no real falloff or directionality. |
| Shadows and depth | 2 | Non-existent; objects and walls don't feel grounded in the space. |
| Materials and surfaces | 3 | The carpet looks like dry cardboard, completely failing the "never dries" pitch. |
| Atmosphere and dread | 4 | The innate creepiness of liminal spaces does some heavy lifting, but the cheap visuals kill the tension. |
| Camera and image feel | 5 | Headbob is okay, but the camcorder view feels like a flat 2D filter, not a lens. |
| Surreal / impossible-space wow | 4 | Walking into the dark void at 01:16 is okay, but the rest is just empty office geometry. |
| The monster | N/A | Didn't see anything chasing me. |
| Sound | 4 | The fluorescent hum is there, but it's completely monotonous and lacks spatial depth. |
| Pace and fun | 4 | Just aimless wandering so far; needs the promised "rare scares" or weirdness to kick in sooner. |
| Performance | 2 | Barely 70 FPS on a 5070 Ti for a game with zero complex geometry or dynamic shadows is completely unacceptable. |
| Would I keep playing | 3 | No, I'd refund it and play one of the free ones that look exactly like this. |

## Top problems (ranked, max 7)
1. **[ruins it] Flat, shadowless lighting.** Look at Frame 1 or 00:15 in the video. The walls are uniformly bright. There is no ambient occlusion in the corners, and the ceiling lights don't cast shadows from the pillars. It makes the entire game look like it's rendering in "fullbright" mode. 
2. **[hurts] The red EXIT sign is a disaster.** In Frame 3 (and video 00:57), the red light is absurdly saturated and bleeds everywhere. It doesn't cast a shadow from the doorframe, and it awkwardly colors the ceiling tiles. It looks like a basic point light dropped in the scene with default engine settings.
3. **[hurts] Materials don't match the pitch.** You promised "carpet that never dries," but the floor is a flat, matte texture with zero specularity or dampness. The wallpaper is also incredibly repetitive (visible tiling everywhere). Give these surfaces some roughness maps and life.
4. **[ruins it] Abysmal performance.** You are getting 71 FPS and 52 FPS 1% lows on an RTX 5070 Ti laptop. For a game that consists of empty square rooms, flat textures, and no complex lighting, this should be running at 300+ FPS. Something is deeply broken under the hood.
5. **[hurts] The camcorder transition is jarring.** At 00:06 and 00:24, the camera just instantly snaps to the VHS overlay. There's no animation of the player raising the camera to their eye, which ruins the immersion. It feels like pressing a button to toggle a post-processing volume rather than using a physical tool.
6. **[nitpick] Clashing light temperatures.** In Frame 2, the light coming down the stairs is a harsh, pure white that completely washes out the geometry, and it doesn't blend at all with the sickly yellow ambient light of the hallway. 

## Working, don't touch
- The concept of the camcorder revealing things (like the door appearing) is a strong mechanic, it just needs better visual execution.
- The sudden transition into pitch darkness around 01:16 is a good way to break up the monotony of the yellow walls.

## Steam review one-liner
Another Backrooms walking simulator with flat lighting, dry carpets, and a camcorder gimmick that doesn't save it from feeling like a developer's first test project.

## What I want next
Actual baked or ray-traced shadows to give the rooms depth, and an animation for raising/lowering the camcorder to make it feel like a physical object in the world.
