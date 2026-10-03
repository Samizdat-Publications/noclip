shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// The Occupant (D035, M4): the building's own copy of a person, made of loose strips of Level 0's
// wallpaper hanging in the air with gaps between them. You see the wall through it; against a wall
// it nearly vanishes. Strips are vertical slats in the figure's own frame (model x), each a little
// different in width, length and sway, torn ragged at the ends; the hollow inside shows the pale
// back of the paper. On tape (the camcorder) it is more there: fewer gaps, strips tearing sideways.
// Skinning runs before vertex(), so VERTEX is the animated body.

#include "res://shaders/common_noise.gdshaderinc"
#include "res://shaders/horizon.gdshaderinc"

uniform sampler2D paper_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 paper_mean = vec3(0.584, 0.474, 0.162);
uniform float paper_sat = 1.25;
uniform vec3 paper_tint = vec3(1.03, 0.97, 0.86);
uniform float pattern_contrast = 1.8;
uniform vec2 paper_tile = vec2(0.6, 0.6);
uniform float time = 0.0;
uniform float strip_w = 0.105;     // meters
uniform float gap = 0.3;           // share of each strip's slot that is empty
uniform float sway = 1.0;
uniform float tape = 0.0;          // 0 eye, 1 seen through the camcorder
uniform float tear = 0.0;          // a frame-skip burst (strips jump sideways)
uniform float fade = 1.0;          // 0..1, dithered (peripheral figures fade as you look at them)
uniform float height = 2.35;
uniform float seed = 0.0;
// Peeking out of a door (the watchers, S05): only the part in front of the wall and inside the
// door's opening is drawn. clip_xform takes world to the door frame (x across, y up from the sill,
// z out of the wall); clip_box is (x0, x1, y0, y1).
uniform bool use_clip = false;
uniform mat4 clip_xform = mat4(1.0);
uniform vec4 clip_box = vec4(-1.0, 1.0, 0.0, 2.0);

// The figure's own frame in meters (feet at the origin, facing +z). The rig's skeleton works in
// centimeters under a 0.01-scaled parent, so model space is not meters (S05).
uniform mat4 to_body = mat4(1.0);
uniform mat4 from_body = mat4(1.0);

varying vec3 mpos;
varying vec3 wpos;
varying float strip_id;
varying float strip_f;

void vertex() {
	vec3 p = (to_body * vec4(VERTEX, 1.0)).xyz;
	float sx = (p.x + 4.0) / strip_w + seed * 13.0;
	float id = floor(sx);
	float h01 = clamp(p.y / height, 0.0, 1.0);
	// Strips hang from somewhere above; the lower ends move most. Each its own slow sway, and a
	// quicker flutter as if a draft ran through the room.
	float ph = n_hash12(vec2(id, 3.1 + seed)) * 6.283;
	float loose = pow(1.0 - h01, 1.4);
	float s = sin(time * (0.9 + 0.6 * n_hash12(vec2(id, 9.0))) + ph) * 0.028 + sin(time * 5.3 + ph * 2.0) * 0.006;
	p.z += s * loose * sway;
	p.x += sin(time * 1.7 + ph) * 0.008 * loose * sway;
	// On tape a skipped frame throws whole strips sideways.
	float jump = step(0.72, n_hash12(vec2(id, floor(time * 12.0)))) * tear;
	p.x += (n_hash12(vec2(id, floor(time * 12.0) + 0.5)) - 0.5) * 0.12 * jump;
	mpos = p;
	VERTEX = (from_body * vec4(p, 1.0)).xyz;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	strip_id = id;
	strip_f = fract(sx);
}

void fragment() {
	if (use_clip) {
		vec3 d = (clip_xform * vec4(wpos, 1.0)).xyz;
		if (d.z < 0.0 || d.z > 0.6 || d.x < clip_box.x || d.x > clip_box.y || d.y < clip_box.z || d.y > clip_box.w) {
			discard;
		}
	}
	float id = strip_id;
	float r1 = n_hash12(vec2(id, 1.7 + seed));
	float r2 = n_hash12(vec2(id, 5.3 + seed));
	float g = gap;
	// Each strip covers part of its slot, offset a little; edges torn (noise along y).
	float edge_n = n_fbm(vec2(id * 3.1, mpos.y * 9.0)) * 0.22;
	float c0 = 0.5 * g + (r1 - 0.5) * 0.18 + edge_n * 0.4;
	float c1 = 1.0 - 0.5 * g + (r1 - 0.5) * 0.18 - edge_n * 0.4;
	bool in_gap = strip_f < c0 || strip_f > c1;
	// By eye the gaps are empty (you see the wall through it). On tape they are dropout: the
	// recording has a hole there, black with white streaks, so on tape it is a person-shaped hole
	// held together by strips of paper (S05, critique 023: "a gold glitch").
	if (in_gap && tape < 0.5) {
		discard;
	}
	// Ragged ends: some strips stop short at the top or the bottom.
	float top = height * (0.86 + 0.16 * r2) + n_fbm(vec2(id, mpos.x * 20.0)) * 0.08;
	// Most strips reach the carpet (it stands); one in four was torn off short.
	float hb = n_hash12(vec2(id, 7.7));
	float bot = (hb < 0.25 ? height * (0.05 + 0.1 * hb * 4.0) : 0.0) + n_fbm(vec2(id * 1.3, 4.0)) * 0.025;
	if (mpos.y > top || mpos.y < bot * (1.0 - tape)) {
		discard;
	}
	// A screen-door fade (peripheral figures), stable per pixel.
	float dith = fract(dot(FRAGCOORD.xy, vec2(0.0671, 0.00584)) * 52.98 + time * 7.0);
	if (dith > fade) {
		discard;
	}
	// The pattern: each strip is a sheet of the level's wallpaper, its pattern slipped up or down a
	// little against its neighbors (a bad seam), the head's strips slipped more.
	float slip = (r2 - 0.5) * 0.09 + step(height * 0.84, mpos.y) * (r1 - 0.5) * 0.18;
	vec2 uv = vec2(mpos.x, height - mpos.y + slip) / paper_tile;
	vec3 alb = texture(paper_tex, uv).rgb;
	alb = max(paper_mean + (alb - paper_mean) * pattern_contrast, vec3(0.0));
	float pl = dot(alb, vec3(0.2126, 0.7152, 0.0722));
	alb = max(mix(vec3(pl), alb, paper_sat), vec3(0.0)) * paper_tint;
	// Water damage wicking up from the bottom, stains, a darker torn edge.
	float wet = smoothstep(height * 0.32, 0.0, mpos.y) * (0.5 + 0.5 * n_fbm(vec2(id, mpos.y * 3.0)));
	alb = mix(alb, alb * vec3(0.62, 0.53, 0.38), wet);
	float stain = smoothstep(0.58, 0.8, n_fbm3(mpos.xy * vec2(2.2, 1.4) + seed));
	alb *= 1.0 - 0.3 * stain;
	float edge = min(strip_f - c0, c1 - strip_f);
	alb *= mix(0.62, 1.0, smoothstep(0.0, 0.08, edge));
	if (!FRONT_FACING) {
		// The back of the paper, seen through the gaps: pale, gray, glue-stained.
		alb = vec3(0.46, 0.43, 0.37) * (0.8 + 0.2 * n_fbm(mpos.xy * 6.0));
	}
	// On tape: a little chroma slip and lift.
	alb = mix(alb, vec3(alb.r * 1.08, alb.g, alb.b * 0.9), tape * 0.6);
	float hz = horizon_fade(VERTEX);
	if (in_gap) {
		float row = floor(FRAGCOORD.y / 2.0);
		float streak = step(0.9, n_hash12(vec2(row, floor(time * 30.0)))) * step(0.3, n_hash12(vec2(floor(FRAGCOORD.x / 24.0), row + floor(time * 30.0))));
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = vec3(0.85, 0.85, 0.8) * streak * 0.9 * hz;
	} else {
		ALBEDO = alb * hz;
		ROUGHNESS = 0.82;
		SPECULAR = 0.3 * hz;
		BACKLIGHT = vec3(0.25) * alb;   // thin paper lets a little light through
	}
}
