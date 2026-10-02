shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The edge of a seam as the camcorder sees it (D022): where the wall is missing on tape, its
// outline tears like a bad tracking line, bright and wavering, with snow along the cut and a
// few faint lines drifting across the gap. Render layer 11 only (tape).

uniform float time = 0.0;
uniform vec2 size_m = vec2(1.2, 2.15);

float h2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	float frame = floor(time * 30.0);
	vec2 m = UV * size_m;                       // meters from the top-left of the opening
	float row = floor(UV.y * 150.0);
	float wob = (h2(vec2(row, frame)) - 0.5) * 0.035 + (h2(vec2(floor(row / 9.0), floor(frame / 3.0))) - 0.5) * 0.05;
	float ex = min(m.x, size_m.x - m.x) + wob;
	float et = m.y + wob * 0.5;
	float e = min(ex, et);
	float flick = 0.55 + 0.45 * h2(vec2(frame, 3.0));
	float edge = exp(-pow(max(e, 0.0) / 0.009, 2.0)) * flick * (0.35 + 0.65 * step(0.45, h2(vec2(row, floor(frame / 2.0)))));
	float halo = exp(-max(e, 0.0) / 0.05) * 0.05;
	float snow = step(0.9, h2(floor(FRAGCOORD.xy / 2.0) + frame * 1.7)) * smoothstep(0.18, 0.0, e) * 0.35;
	float lines = step(0.988, h2(vec2(row, floor(frame * 0.5) + 1.0))) * 0.07;
	vec3 col = vec3(0.82, 0.9, 1.0) * (edge * 0.5 + halo) + vec3(0.75, 0.8, 0.9) * snow + vec3(0.9, 0.86, 0.72) * lines;
	// chroma slip on the cut, red one side, blue the other
	col.r += 0.35 * exp(-pow((e - 0.012) / 0.008, 2.0)) * flick;
	col.b += 0.25 * exp(-pow((e + 0.006) / 0.008, 2.0)) * flick;
	ALBEDO = col;
}
