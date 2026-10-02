shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
// The figure that exists only on tape: a hole in the picture more than a body. Near black, its
// outline slipping sideways in thin bands like a bad tracking line, with drop-out specks.

uniform float time = 0.0;
uniform float jitter = 0.022;

float h(float x) { return fract(sin(x * 91.17) * 43758.5453); }

void vertex() {
	float band = floor(VERTEX.y * 34.0);
	float t = floor(time * 18.0);
	VERTEX.x += (h(band + t * 3.1) - 0.5) * jitter * (h(t + band * 0.37) > 0.7 ? 3.0 : 1.0);
}

void fragment() {
	vec2 px = floor(FRAGCOORD.xy / 3.0);
	float n = fract(sin(dot(px + floor(time * 24.0), vec2(12.9898, 78.233))) * 43758.5453);
	if (n > 0.965) {
		discard;
	}
	ALBEDO = vec3(0.012, 0.011, 0.01) * (0.6 + 0.8 * n);
}
