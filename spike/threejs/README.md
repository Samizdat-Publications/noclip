# Level 0 look-dev spike: three.js WebGPU (bake-off packet B)

Time-boxed (about 90 minutes) three.js r186 WebGPU renderer for the seed 4242 hero slice, built from the same
inputs as the Godot reference: `game/data/level0_hero.json`, `data/scene_4242.json`, `data/track_4242.json`,
`data/shots_4242.json` and the shared PBR textures in `game/assets/textures/level0/`.

## Run it

```
cd spike/threejs
npm install
node capture.mjs          # full packet -> review/archive/bakeoff/B/ (about 5 minutes)
node capture.mjs test     # 4 quick stills -> spike/threejs/out/test/
node capture.mjs stills|sheets|video|perf   # one stage only
```

Needs Chrome at `C:\Program Files\Google\Chrome\Application\chrome.exe` (override with `CHROME`), ffmpeg
(`FFMPEG`, defaults to the WinGet link) and Python with Pillow (contact sheets). The script starts a small local
web server, opens headed Chrome with WebGPU through Playwright, checks the adapter is the NVIDIA GPU (logged),
renders on a fixed 30 fps timestep (no animation loop), and reads pixels back from the canvas. Stills render the
30 preceding track frames first (60 settle frames for static poses) so the temporal passes have history. The
video renders every track frame in order at 1920x1080 and pipes JPEG frames (q 0.95) into ffmpeg (H.264 crf 19,
yuv420p, audio copied from `data/audio_4242.m4a`). Perf plays the track in real time with requestAnimationFrame
at 2560x1440 for 4 s warm-up plus 40 s measured.

Files: `index.html`, `src/main.js` (everything visual), `capture.mjs` (harness), `make_sheets.py` (3x3 sheets).

## What is implemented

- Geometry from the layout: walls up to the plenum with corner extension, door headers and soffits, painted door
  casings and jamb liners, pillars, 10 cm vinyl baseboards on every wall face, pillar and free wall end, a 0.6 m
  drop ceiling built tile by tile from `special_tiles` (stained albedo, 180 degree rotation, per-tile brightness,
  sagging far edge), missing tiles open to a dark plenum, a T-bar grid that stops at troffers, troffers with the
  lens recessed 3 cm and a white housing reveal and flange.
- Lighting: every working fixture is a real `RectAreaLight` (LTC, 0.58 x 1.18 m) with the dump's tint and energy;
  animated fixtures follow the per-frame levels from the track; dead fixtures are off, some with an orange
  cathode glow at the tube ends. Rect lights have no shadows, so each fixture gets a baked 2D visibility mask
  (512x512 per light in a texture array, 8 area samples, soft edges, range window) rasterized from the wall
  layout at startup; the mask is folded into the light's `colorNode`, so light does not leak through walls into
  dark rooms. A pool of 28 lights is re-assigned to the most relevant fixtures every frame.
- Bounce: a baked 2D irradiance map from the same masks (tight blur plus a wide spill through doorways, animated
  fixtures in their own layers weighted per frame) adds yellow-tinted indirect light to every material. This is
  what lights the ceiling, which the down-facing troffers never hit directly.
- Materials (TSL): world-scaled wallpaper with slow tint drift, a water-wicking band with a darker tide edge in
  some stretches and drip staining from the ceiling in others; carpet blending a second rotated sample by
  low-frequency noise, with damp patches (darker, flatter normals, roughness down to 0.42) that also
  gather around the three leak points; decals from the dump projected with `DecalGeometry`.
- Post (RenderPipeline): MRT scene pass, SSGI used for ambient occlusion and contact darkening only (masked off
  emitters), TRAA, bloom, exponential haze whose colour follows the local bounce light (so dark rooms stay dark),
  slow auto-exposure (metered from the bounce map along the view direction, about 1.6 s time constant), mild
  edge-only chromatic aberration, soft vignette, per-frame film grain, a gentle contrast curve, AgX tone mapping.

## What is missing compared to the target

- No true realtime GI. The bounce is a baked 2D approximation; screen-space GI from SSGI was tried but at an
  affordable sample count it sparkled on dim surfaces, so it is used for AO only.
- No real volumetric light shafts; the haze is a surface fog tinted by local bounce.
- Shadows only from walls and pillars (2D). Door headers, the T-bar and small details cast no light shadows.
- Auto-exposure is a CPU meter on the bounce map, not a luminance histogram of the rendered frame.
- Failing tubes reuse the reference levels; there is no flicker-specific lens behaviour beyond brightness.
- No camcorder mode, monster, or gameplay. This is a look-dev renderer only.

## Measured performance

Perf stage re-run alone on an idle GPU (`review/archive/bakeoff/B/perf.json`): RTX 5070 Ti Laptop GPU, Chrome
WebGPU, 2560x1440, 40 s of the real-time track after 4 s warm-up: 38.1 fps average (26.2 ms), 1% low 27.0 fps,
p99 frame 33.7 ms. Earlier runs this session ranged from about 30 to 44 fps average, so treat single runs as
+/- 15%. Pool size is the main cost knob (`index.html?pool=20`).

## Gotcha (fixed)

The renderer's node frame counter only advances on its own requestAnimationFrame tick. The capture renders many
frames inside one JS task, so per-frame passes (scene pass, TRAA, SSGI) ran only once per task, and every still
showed the first warm-up frame (30 frames, about 1 s, earlier on the track) instead of the requested one.
`render()` now calls `renderer._nodes.nodeFrame.update()` before each frame. Debug URL flags kept in `main.js`:
`direct` (no post chain), `passonly`, `notaa`, `nograin`.
