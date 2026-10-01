shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Damp commercial loop carpet. Two texture samples (one rotated and rescaled) are blended
// by low-frequency noise to kill tiling. World-space wet patches darken the fibers and
// drop roughness so the fluorescent panels glint in them.

#include "res://shaders/common_noise.gdshaderinc"

uniform bool use_tex = false;
uniform vec3 base_color : source_color = vec3(0.54, 0.45, 0.27);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 1.0;
uniform float normal_strength = 1.0;
uniform vec2 seed_offset = vec2(0.0);
uniform float wet_amount = 1.0;
// World-space wet patch field shared with gameplay (scripts/world/noise.gd floor_wetness).
uniform float wet_scale = 0.13;
uniform float wet_lo = 0.56;
uniform float wet_hi = 0.70;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 uv1 = p / tile;
	mat2 R = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	vec2 uv2 = (R * p) / (tile * 1.37) + vec2(0.31, 0.57);
	float bl = smoothstep(0.3, 0.7, n_fbm3(p * 0.45 + 5.0));

	vec3 alb;
	float rough;
	float ao;
	vec3 nrm;
	if (use_tex) {
		alb = mix(texture(albedo_tex, uv1).rgb, texture(albedo_tex, uv2).rgb, bl);
		rough = mix(texture(rough_tex, uv1).r, texture(rough_tex, uv2).r, bl);
		ao = mix(texture(ao_tex, uv1).r, texture(ao_tex, uv2).r, bl);
		nrm = mix(texture(normal_tex, uv1).rgb, texture(normal_tex, uv2).rgb, bl);
	} else {
		alb = base_color * mix(0.85, 1.1, n_value(p * 40.0));
		rough = 0.92;
		ao = 1.0;
		nrm = vec3(0.5, 0.5, 1.0);
	}

	// Large-scale color drift: traffic lanes, sun fade, old cleaning.
	alb *= mix(vec3(0.86, 0.85, 0.84), vec3(1.07, 1.05, 1.0), n_fbm(p * 0.07 + seed_offset * 0.3));

	// Wet patches with a darker tide-line rim, plus fine damp mottling everywhere.
	float field = n_fbm(p * wet_scale + seed_offset);
	float wet = smoothstep(wet_lo, wet_hi, field) * wet_amount;
	float rim = exp(-pow((field - wet_lo - 0.01) / 0.012, 2.0)) * wet_amount;
	float mottle = smoothstep(0.45, 0.8, n_fbm(p * 1.7 + 3.0)) * 0.35;
	float damp = max(wet, mottle * wet_amount);
	alb *= mix(1.0, 0.52, damp);
	alb *= 1.0 - 0.22 * rim;
	rough = mix(rough, 0.34, wet);
	rough = mix(rough, rough * 0.86, mottle);
	nrm = mix(nrm, vec3(0.5, 0.5, 1.0), wet * 0.55);

	ALBEDO = alb;
	ROUGHNESS = rough;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	SPECULAR = mix(0.3, 0.5, wet);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength;
}
