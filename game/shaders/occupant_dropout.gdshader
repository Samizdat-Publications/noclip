shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, shadows_disabled, depth_draw_opaque;
// The Occupant on tape (S06, L156): a person-shaped hole in the recording. Black where the tape lost
// its signal, with white dropout streaks running across it in rows, its outline torn sideways in
// bands like a paused frame (occupant_common's band shift), the head smeared most. Not lit and not in
// the haze: it is not in the room, it is missing from the picture. Drawn as the next pass of the paper
// strips, a little smaller than them, so the last strips of paper hang in front of it.

#include "res://shaders/occupant_common.gdshaderinc"
#include "res://shaders/horizon.gdshaderinc"

uniform float fade = 1.0;
uniform float streaks = 1.0;

varying vec3 mpos;

void vertex() {
	vec3 p = (to_body * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(mat3(to_body) * NORMAL);
	float id;
	float f;
	p = occ_displace(p, n, id, f);
	mpos = p;
	VERTEX = (from_body * vec4(p, 1.0)).xyz;
}

void fragment() {
	float hz = horizon_fade(VERTEX);
	float dith = fract(dot(FRAGCOORD.xy, vec2(0.0671, 0.00584)) * 52.98 + time * 7.0);
	if (dith > fade * hz) {
		discard;
	}
	// Rows sized to the picture (about 3 px at 1440p), so the hole reads the same at any resolution.
	float px = VIEWPORT_SIZE.y / 480.0;
	float row = floor(FRAGCOORD.y / px);
	float fr = floor(time * 30.0);
	// The hole's edge frays: rows near the outline drop in and out from frame to frame.
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	if (edge > 0.9 && n_hash12(vec2(row, fr)) < 0.35) {
		discard;
	}
	// Mostly black: a few short white dropout streaks, and now and then one long line.
	float streak = step(0.955, n_hash12(vec2(row, fr))) * step(0.45, n_hash12(vec2(floor(FRAGCOORD.x / (px * 14.0)), row + fr)));
	float head = smoothstep(height * 0.8, height * 0.9, mpos.y);
	float line = step(0.99 - head * 0.02, n_hash12(vec2(floor(row / 1.5), fr * 1.7)));
	vec3 c = vec3(0.008, 0.007, 0.01) + vec3(0.88, 0.88, 0.84) * max(streak * 0.8, line) * streaks;
	ALBEDO = c;
}
