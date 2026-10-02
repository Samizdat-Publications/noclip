shader_type spatial;
render_mode cull_back, shadows_disabled, fog_disabled, diffuse_lambert, specular_schlick_ggx;
// The figure that exists only on tape (TapeEvents, D018/D021). Through the camcorder it is fully
// there: a dark, real-shaped person under the light. But it is made of bad tape: its outline
// fizzes away into noise, its head smears sideways like a paused frame, thin bands of it slip
// out of line, and white drop-out streaks cross it the way they cross a worn recording.

uniform float time = 0.0;
uniform float jitter = 0.012;     // band slip in meters
uniform float tear = 0.0;         // 0..1, a burst of slip on the frame it changes pose
uniform float smear = 0.05;       // how far the head drags sideways (m)
uniform float head_y = 1.52;      // above this the head and neck smear

float h(float x) { return fract(sin(x * 91.17) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void vertex() {
	float t = floor(time * 15.0);
	float band = floor(VERTEX.y * 26.0);
	float slip = (h(band + t * 3.1) - 0.5) * jitter;
	slip *= h(t + band * 0.37) > 0.82 ? 4.0 : 1.0;
	slip += (h(band * 1.7 + t) - 0.5) * tear * 0.09;
	VERTEX.x += slip;
	// The face drags sideways in a few thick bands, as on a paused, worn tape.
	float above = smoothstep(head_y, head_y + 0.1, VERTEX.y);
	float hb = floor(VERTEX.y * 18.0);
	VERTEX.x += above * (h(hb + t * 0.5) - 0.3) * smear;
	VERTEX.z += above * (h(hb * 2.3 + t) - 0.5) * smear * 0.4;
}

void fragment() {
	float frame = floor(time * 30.0);
	vec2 px = floor(FRAGCOORD.xy / 2.0);
	float n = h2(px + frame * 1.37);
	// The outline fizzes away into noise.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	if (n < rim * 0.85 - 0.08) {
		discard;
	}
	// Scattered drop-out pixels inside too.
	if (n > 0.985) {
		discard;
	}
	vec3 col = vec3(0.026, 0.024, 0.022) * (0.55 + 0.9 * n);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	// Drop-out streaks: short white horizontal lines, a few per frame, as on old tape.
	float row = floor(FRAGCOORD.y / 2.0);
	float seg = floor(FRAGCOORD.x / 90.0);
	float d = h2(vec2(row, seg) + frame * 7.31);
	if (d > 0.9965) {
		EMISSION = vec3(0.55, 0.56, 0.6) * (0.6 + 0.4 * h(row + frame));
	}
}
