shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
// The camcorder's flip-out screen (S05, L092: the held camera read as a pistol until it had the one
// shape that says camcorder). A dim blue-gray standby picture with scanlines, a little snow, the
// REC dot in the corner. Unshaded: it glows on its own.

uniform float time = 0.0;
uniform float level = 1.0;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float scan = 0.82 + 0.18 * sin(uv.y * 220.0);
	float snow = h(floor(uv * vec2(90.0, 70.0)) + floor(time * 24.0)) * 0.18;
	vec3 col = vec3(0.1, 0.16, 0.28) + vec3(0.04, 0.06, 0.1) * (1.0 - length(uv - 0.5) * 1.3);
	col = col * scan + snow * vec3(0.7, 0.8, 0.9);
	// REC dot, blinking
	float dot_ = smoothstep(0.035, 0.02, length((uv - vec2(0.12, 0.14)) * vec2(1.4, 1.0)));
	col = mix(col, vec3(1.0, 0.12, 0.08) * 1.6, dot_ * step(0.5, fract(time * 0.9)));
	// a bright frame line at the panel edge, as an LCD's backlight bleeds
	float edge = max(smoothstep(0.06, 0.0, uv.x) + smoothstep(0.94, 1.0, uv.x), smoothstep(0.06, 0.0, uv.y) + smoothstep(0.94, 1.0, uv.y));
	col += vec3(0.08, 0.1, 0.12) * edge;
	ALBEDO = col * level * 0.75;
}
