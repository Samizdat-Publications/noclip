// The Occupant's shared body math (S06): the strip pattern, the sway, and on tape the horizontal
// tearing that smears it like a paused VHS frame. Used by occupant_strips (the paper), occupant_dropout
// (the hole in the recording, its next pass) and occupant_shimmer (what the naked eye gets).
// Skinning runs before vertex(), so VERTEX is the animated body. The rig works in centimeters under a
// 0.01-scaled parent, so everything here runs in a body frame in meters passed from the script.

#include "res://shaders/common_noise.gdshaderinc"

uniform float time = 0.0;
uniform float strip_w = 0.105;     // meters
uniform float gap = 0.3;           // share of each strip's slot that is empty
uniform float sway = 1.0;
uniform float tape = 0.0;          // 0 eye, 1 seen through the camcorder
uniform float tear = 0.0;          // a frame-skip burst (strips and bands jump sideways)
uniform float smear = 0.0;         // 0..1 horizontal tearing of the whole body (tape), head most
uniform float inflate = 0.0;       // meters the body is pushed out along its normals (the hole is bigger than the paper)
uniform float height = 2.35;
uniform float seed = 0.0;
uniform mat4 to_body = mat4(1.0);
uniform mat4 from_body = mat4(1.0);

// x offset (meters, body frame) of the horizontal band at height y: bands about 5 cm tall, most
// barely moved, some thrown well to one side, the head's bands smeared most. Changes in steps (the
// tape's frame rate), never smoothly.
float occ_band_shift(float y) {
	float bh = 0.045;
	float band = floor(y / bh);
	float step_t = floor(time * 15.0);
	float r = n_hash12(vec2(band + seed * 7.0, step_t * 0.37));
	float r2 = n_hash12(vec2(band * 1.7, floor(time * 3.0) + seed));
	float head = smoothstep(height * 0.8, height * 0.88, y);
	// Smears trail to the right like chroma on a worn tape: mostly positive. Most bands stay put so
	// the outline still reads as a person; one in ten is thrown aside.
	float s = (r2 - 0.3) * 0.02 + step(0.93, r) * (r - 0.8) * 0.5;
	s *= (1.0 + head * 3.0);
	s += head * (n_hash12(vec2(band, step_t)) - 0.3) * 0.14;
	return s * smear * (1.0 + tear * 2.5);
}

// Moves a body-frame point: the paper's sway (lower ends move most) and the tape's tearing.
vec3 occ_displace(vec3 p, vec3 n, out float id, out float f) {
	float sx = (p.x + 4.0) / strip_w + seed * 13.0;
	id = floor(sx);
	f = fract(sx);
	float h01 = clamp(p.y / height, 0.0, 1.0);
	float ph = n_hash12(vec2(id, 3.1 + seed)) * 6.283;
	float loose = pow(1.0 - h01, 1.4);
	float s = sin(time * (0.9 + 0.6 * n_hash12(vec2(id, 9.0))) + ph) * 0.028 + sin(time * 5.3 + ph * 2.0) * 0.006;
	p.z += s * loose * sway;
	p.x += sin(time * 1.7 + ph) * 0.008 * loose * sway;
	float jump = step(0.72, n_hash12(vec2(id, floor(time * 12.0)))) * tear;
	p.x += (n_hash12(vec2(id, floor(time * 12.0) + 0.5)) - 0.5) * 0.12 * jump;
	p += n * inflate * (0.6 + 0.8 * n_hash12(vec2(floor(p.y / 0.04), seed)));
	p.x += occ_band_shift(p.y);
	return p;
}

// The strip cover at this point: 1 on paper, 0 in a gap. Edges torn along y.
float occ_on_strip(float id, float f, float y) {
	float r1 = n_hash12(vec2(id, 1.7 + seed));
	float edge_n = n_fbm(vec2(id * 3.1, y * 9.0)) * 0.22;
	float c0 = 0.5 * gap + (r1 - 0.5) * 0.18 + edge_n * 0.4;
	float c1 = 1.0 - 0.5 * gap + (r1 - 0.5) * 0.18 - edge_n * 0.4;
	return (f < c0 || f > c1) ? 0.0 : 1.0;
}

// Distance into the paper from the nearest torn edge (0 at the edge), in slot units.
float occ_edge_dist(float id, float f, float y) {
	float r1 = n_hash12(vec2(id, 1.7 + seed));
	float edge_n = n_fbm(vec2(id * 3.1, y * 9.0)) * 0.22;
	float c0 = 0.5 * gap + (r1 - 0.5) * 0.18 + edge_n * 0.4;
	float c1 = 1.0 - 0.5 * gap + (r1 - 0.5) * 0.18 - edge_n * 0.4;
	return min(f - c0, c1 - f);
}
