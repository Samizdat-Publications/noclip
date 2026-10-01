shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Wallpaper walls and pillars. UV is world-scale meters: x along the wall, y down from
// the ceiling. Macro variation (tint drift, water damage at the floor, staining from the
// ceiling) is world-space so it never repeats with the texture tile.

#include "res://shaders/common_noise.gdshaderinc"

uniform bool use_tex = false;
uniform vec3 base_color : source_color = vec3(0.79, 0.72, 0.44);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 tile = vec2(0.6, 0.6);
uniform float normal_strength = 0.8;
uniform float ceiling_h = 2.6;
uniform float damage = 1.0;
uniform vec2 seed_offset = vec2(0.0);
// Pushes the printed pattern away from the paper color so it reads at a few meters.
uniform float pattern_contrast = 2.4;
uniform vec3 tex_mean = vec3(0.584, 0.474, 0.162);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV / tile;
	vec3 alb = use_tex ? texture(albedo_tex, uv).rgb : base_color;
	alb = max(tex_mean + (alb - tex_mean) * pattern_contrast, vec3(0.0));
	float rough = use_tex ? texture(rough_tex, uv).r : 0.68;
	float ao = use_tex ? texture(ao_tex, uv).r : 1.0;
	float s = UV.x + seed_offset.x;   // continuous distance along the wall
	float y = wpos.y;

	// Slow tint drift: sun-faded and nicotine-yellowed patches.
	float drift = n_fbm(vec2(s * 0.23, y * 0.35) + seed_offset);
	alb *= mix(vec3(0.90, 0.89, 0.86), vec3(1.05, 1.04, 0.99), drift);

	// Water wicking up from the wet carpet: a darker, browner band with a tide line.
	float stretch = smoothstep(0.42, 0.72, n_fbm3(vec2(s * 0.09, 3.7) + seed_offset)) * damage;
	float band_h = 0.06 + stretch * (0.18 + 0.32 * n_fbm(vec2(s * 0.55, 11.3)));
	float below = smoothstep(band_h + 0.015, band_h - 0.025, y);
	float tide = exp(-pow((y - band_h) / 0.012, 2.0)) * stretch;
	alb = mix(alb, alb * vec3(0.74, 0.66, 0.50), below * stretch);
	alb *= 1.0 - 0.28 * tide;
	rough = mix(rough, rough * 0.82, below * stretch);

	// Staining that runs down from the ceiling in streaks.
	float leak = smoothstep(0.55, 0.78, n_fbm3(vec2(s * 0.12, 27.0) - seed_offset)) * damage;
	float streak = n_fbm(vec2(s * 7.5, y * 0.35 + 4.0));
	float from_top = smoothstep(ceiling_h - 1.6 * streak, ceiling_h, y);
	alb = mix(alb, alb * vec3(0.72, 0.62, 0.45), leak * from_top * smoothstep(0.35, 0.6, streak));

	// Contact grime: darker in the last few centimeters at the floor and the ceiling.
	alb *= mix(0.82, 1.0, smoothstep(0.0, 0.22, y));
	alb *= mix(0.9, 1.0, smoothstep(ceiling_h, ceiling_h - 0.12, y));

	ALBEDO = alb;
	ROUGHNESS = rough;
	AO = ao;
	AO_LIGHT_AFFECT = 0.15;
	SPECULAR = 0.4;
	if (use_tex) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
