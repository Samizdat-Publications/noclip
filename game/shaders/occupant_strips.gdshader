shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// The Occupant (D035, M4): the building's own copy of a person, made of loose strips of Level 0's
// wallpaper hanging in the air with gaps between them. Strips are vertical slats in the figure's own
// frame (model x), each a little different in width, length and sway, torn ragged at the ends; the
// hollow inside shows the pale back of the paper.
// S06 (L156): three looks. Paper (the high door's peek, close up). Silhouette: almost black, a shape
// standing where the light does not reach (the figure at the edge of sight). Tape: only a few strips
// left, floating in front of a person-shaped hole in the recording (occupant_dropout, the next pass),
// the whole body torn sideways in bands like a paused frame, the head most.

#include "res://shaders/occupant_common.gdshaderinc"
#include "res://shaders/horizon.gdshaderinc"

uniform sampler2D paper_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 paper_mean = vec3(0.584, 0.474, 0.162);
uniform float paper_sat = 1.25;
uniform vec3 paper_tint = vec3(1.03, 0.97, 0.86);
uniform float pattern_contrast = 1.8;
uniform vec2 paper_tile = vec2(0.6, 0.6);
uniform float fade = 1.0;          // 0..1, dithered (peripheral figures fade as you look at them)
uniform float silhouette = 0.0;    // 0 paper, 1 a dark shape (what is left when no light reaches it)
// Peeking out of a door (the watchers, S05): only the part in front of the wall and inside the
// door's opening is drawn. clip_xform takes world to the door frame (x across, y up from the sill,
// z out of the wall); clip_box is (x0, x1, y0, y1).
uniform bool use_clip = false;
uniform mat4 clip_xform = mat4(1.0);
uniform vec4 clip_box = vec4(-1.0, 1.0, 0.0, 2.0);

varying vec3 mpos;
varying vec3 wpos;
varying float strip_id;
varying float strip_f;

void vertex() {
	vec3 p = (to_body * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(mat3(to_body) * NORMAL);
	float id;
	float f;
	p = occ_displace(p, n, id, f);
	mpos = p;
	VERTEX = (from_body * vec4(p, 1.0)).xyz;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	strip_id = id;
	strip_f = f;
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
	if (occ_on_strip(id, strip_f, mpos.y) < 0.5) {
		discard;
	}
	// Ragged ends: some strips stop short at the top or the bottom. On tape most of them are short:
	// what is left of the paper hangs in pieces over the hole.
	float top = height * (0.86 + 0.16 * r2) + n_fbm(vec2(id, mpos.x * 20.0)) * 0.08;
	float hb = n_hash12(vec2(id, 7.7));
	float bot = (hb < 0.25 ? height * (0.05 + 0.1 * hb * 4.0) : 0.0) + n_fbm(vec2(id * 1.3, 4.0)) * 0.025;
	if (tape > 0.5) {
		float a = n_hash12(vec2(id, 11.3 + seed));
		float b = n_hash12(vec2(id, 13.9 + seed));
		top = height * mix(0.35, 1.02, a);
		bot = height * b * 0.55;
		if (top - bot < height * 0.18) {
			discard;
		}
		// Far away (small on screen) the paper is lost and only the hole is left: a solid shape.
		float tall_px = height * VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1] / (2.0 * max(length(VERTEX), 0.1));
		if (n_hash12(vec2(id, 21.7 + seed)) > smoothstep(140.0, 480.0, tall_px) * 0.9 + 0.1 || (fade < 0.99 && tall_px < 300.0)) {
			discard;
		}
	}
	if (mpos.y > top || mpos.y < bot) {
		discard;
	}
	// A screen-door fade (peripheral figures), stable per pixel.
	float dith = fract(dot(FRAGCOORD.xy, vec2(0.0671, 0.00584)) * 52.98 + time * 7.0);
	float hz = horizon_fade(VERTEX);
	if (dith > fade * (0.15 + 0.85 * hz)) {
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
	float edge = occ_edge_dist(id, strip_f, mpos.y);
	alb *= mix(0.62, 1.0, smoothstep(0.0, 0.08, edge));
	if (!FRONT_FACING) {
		// The back of the paper, seen through the gaps: pale, gray, glue-stained.
		alb = vec3(0.46, 0.43, 0.37) * (0.8 + 0.2 * n_fbm(mpos.xy * 6.0));
	}
	// On tape: the paper that is left is washed out and bleeds red to the right.
	alb = mix(alb, vec3(alb.r * 1.1, alb.g * 0.95, alb.b * 0.82) * 0.8, tape * 0.7);
	// A dark shape: the paper is there, but no light seems to reach it.
	alb = mix(alb, alb * 0.045, silhouette);
	ALBEDO = alb * hz;
	ROUGHNESS = mix(0.82, 1.0, silhouette);
	SPECULAR = 0.3 * hz * (1.0 - silhouette);
	BACKLIGHT = vec3(0.25) * alb * (1.0 - silhouette);   // thin paper lets a little light through
}
