# Player Review

## Gut reaction
I rolled my eyes when I saw the yellow wallpaper, but you actually got me. The mechanic where you use the camcorder to see impossible geometry—like the chalk door revealing a hidden room—is incredibly cool and elevates this way above the standard Backrooms asset flip. That said, the lighting is incredibly flat, the shadows are fundamentally broken, and the performance is completely unacceptable for how basic the game looks. I want to play this for the puzzles, but the technical side needs a massive overhaul.

## Scores (1 to 10, or N/A)
| Category | Score | Why (one line) |
|---|---|---|
| First impression / screenshot-worthiness | 6 | The camcorder mechanic saves it from looking like a million other identical clones. |
| Lighting | 4 | Extremely flat; ceiling panels glow but don't seem to bounce light naturally into the room. |
| Shadows and depth | 2 | Completely broken. The floating chair shadow (Frame 1) is a pitch-black, hard-edged decal. |
| Materials and surfaces | 5 | Standard issue wallpaper and carpet, missing normal maps or specular detail to make them feel real. |
| Atmosphere and dread | 7 | The tension of *having* to look through the camera to see the truth works really well. |
| Camera and image feel | 7 | The VHS overlay is nicely balanced—grungy but you can still actually see what you're doing. |
| Surreal / impossible-space wow | 8 | The chalk outline turning into a real 3D room through the lens (0:29) is fantastic. |
| The monster | 5 | A distant stick figure that rushes you with a loud static noise (1:17) is pretty cliché. |
| Sound | 6 | The constant hum is perfect, but the monster's audio cue is just generic distorted noise. |
| Pace and fun | 7 | Finding the hidden seams and navigating with the camera looks genuinely engaging. |
| Performance | 3 | 53 FPS average on an RTX 5070 Ti for PS2-era geometry is horribly unoptimized. |
| Would I keep playing | 7 | Yes, purely to see how far you push the non-Euclidean camera puzzles. |

## Top problems (ranked, max 7)
1. [ruins it] **Performance is abysmal.** You are averaging 53.9 FPS with 1% lows of 27.4 on a modern RTX 5070 Ti Laptop GPU. For a game that is mostly boxes and repeating textures, this should be running at 300+ FPS. You have a massive bottleneck somewhere (unoptimized volumetric fog, overlapping lights, or script errors).
2. [hurts] **Shadows are mathematically wrong.** Look at Frame 1 and 1:49 in the video. The floating office chair casts a single, razor-sharp, pitch-black shadow on the wall. There are multiple fluorescent lights on the ceiling right next to it. It looks like a placeholder shadow map. 
3. [hurts] **Lack of Ambient Occlusion.** Look at Frame 4. The doorframe and the corners of the walls have no contact shadows. Everything looks like it's floating because the lighting is completely uniform and flat.
4. [nitpick] **The monster scare is cheap.** At 1:17, the tall figure just slides at the player at warp speed accompanied by loud static. It feels like a standard Garry's Mod nextbot scare. Let the monster do something weirder or more unsettling with the camera mechanic instead of just rushing the player.
5. [nitpick] **Tripod shadow is weird.** At 0:35, the shadow of the tripod extends all the way up the wall and onto the ceiling in a way that doesn't match the light source in the room at all. 

## Working, don't touch
- **The Camcorder AR Mechanic:** The transition at 0:29 where the chalk drawing becomes a real room only through the lens is brilliant. This is your core hook. Lean into it heavily.
- **The UI/HUD:** The REC overlay, timestamp, and battery indicator look authentic without being overly intrusive or blinding.
- **The Audio Atmosphere:** The low, oppressive drone of the fluorescent lights is spot on.

## Compared to last build
N/A

## Steam review one-liner
A Backrooms game that actually gives you a reason to be there, though the frame rate is scarier than the monsters.

## What I want next
Fix the lighting and shadows so the environments don't look so flat and amateurish. Give me more complex, mind-bending puzzles using the camcorder to navigate impossible geometry.
