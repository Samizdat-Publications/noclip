shader_type canvas_item;
// Lifting the camcorder to your eye (S06): the viewfinder's rubber eyecup closes in from the edges
// of your view to the 4:3 picture the camcorder shows, soft and dark at its rim, the picture a little
// darker as it comes up. It replaces the held camera model, which critics read as a pistol five times
// (L092, L125, critique 025).

uniform float amount = 0.0;       // 0 nothing, 1 the eyecup on your eye
uniform float aspect = 1.7778;    // viewport width / height

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	// The opening shrinks from well past the screen edge to the 4:3 frame.
	float e = smoothstep(0.0, 1.0, amount);
	vec2 half_open = mix(vec2(aspect * 0.5 + 0.35, 0.85), vec2(4.0 / 3.0 * 0.5, 0.5), e);
	float r = mix(0.35, 0.06, e);    // corner rounding
	vec2 q = abs(p) - (half_open - vec2(r));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	float soft = mix(0.12, 0.02, e);
	float mask = smoothstep(-soft, soft * 0.4, d);
	float dim = 0.28 * e;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(max(mask, dim), 0.0, 1.0) * step(0.001, amount));
}
