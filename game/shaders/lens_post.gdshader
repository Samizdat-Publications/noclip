shader_type canvas_item;
// Main-view lens character (VISION: mild chromatic aberration at the edges only, soft
// vignette, fine film grain). Runs on the final image.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.03;
uniform float vignette = 0.32;
uniform float aberration = 0.0025;
uniform float frame_seed = 0.0;
uniform float drift = 0.0;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r2 = dot(d, d);
	vec2 off = (uv - 0.5) * aberration * (1.0 + drift * 3.0) * smoothstep(0.05, 0.5, r2);
	vec3 c;
	c.r = texture(screen_tex, uv - off).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv + off).b;
	float v = 1.0 - vignette * smoothstep(0.08, 0.62, r2);
	c *= v;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec2 px = floor(FRAGCOORD.xy);
	float n = h12(px + vec2(frame_seed * 37.0, frame_seed * 91.0)) + h12(px * 1.37 + frame_seed * 13.0) - 1.0;
	c += n * grain * mix(1.0, 0.35, l);
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
