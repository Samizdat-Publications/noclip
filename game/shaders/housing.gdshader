shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// White-painted sheet metal of a recessed troffer and the exit-sign box. The reveal around
// a lit lens catches its light (live level from scripts/level0/fixture_field.gd), so the
// panel has a lit frame instead of a hard edge against the dark ceiling.

uniform vec3 base_color : source_color = vec3(0.9, 0.89, 0.85);
uniform sampler2D field_tex : filter_nearest, repeat_disable;
uniform vec2 field_origin = vec2(0.0);
uniform float field_cell = 0.6;
uniform vec2 field_size = vec2(1.0);
uniform float ceiling_h = 2.6;
uniform float reveal_glow = 0.9;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 lit = vec3(0.0);
	if (wpos.y > ceiling_h - 0.005) {
		// Step a few centimeters toward the lens (the reveal faces point inward) and read its level.
		vec2 p = wpos.xz + wnrm.xz * 0.05;
		ivec2 t = ivec2(floor((p - field_origin) / field_cell));
		t = clamp(t, ivec2(0), ivec2(field_size) - 1);
		lit = texelFetch(field_tex, t, 0).rgb;
		// Brightest at the lens edge, fading up into the recess.
		lit *= mix(1.0, 0.45, clamp((wpos.y - ceiling_h) / 0.03, 0.0, 1.0));
	}
	ALBEDO = base_color;
	ROUGHNESS = 0.35;
	METALLIC = 0.2;
	EMISSION = base_color * lit * reveal_glow;
}
