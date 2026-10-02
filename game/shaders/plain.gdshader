shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Plain surfaces (T-bar grid, baseboards, door frames, doors, outlets, plenum) with the same
// smooth horizon fade as the level shaders. The dithered fade of a standard material read as
// glitter on the distant ceiling grid (critique 012).

#include "res://shaders/horizon.gdshaderinc"
#include "res://shaders/common_noise.gdshaderinc"

uniform vec3 albedo_color : source_color = vec3(0.8);
uniform bool use_albedo_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_tex = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.0;
uniform bool use_rough_tex = false;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness = 0.6;
uniform float metallic = 0.0;
uniform vec2 uv_scale = vec2(1.0);
// 0..1: hand grime, scuffs and kick marks (door frames and doors).
uniform float grime = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 a = albedo_color;
	if (use_albedo_tex) {
		a *= texture(albedo_tex, uv).rgb;
	}
	float r = roughness;
	if (use_rough_tex) {
		r *= texture(rough_tex, uv).r;
	}
	if (grime > 0.0) {
		vec2 q = wpos.xz * 2.3 + vec2(wpos.y * 1.7, -wpos.y * 0.9);
		float g = n_fbm(q) * 0.6 + n_value(q * 6.0) * 0.4;
		a *= mix(1.0, 0.72, smoothstep(0.45, 0.85, g) * grime);
		// kick marks and mop splash at the foot, hand grime at handle height
		a *= mix(1.0, 0.62, smoothstep(0.35, 0.05, wpos.y) * grime);
		a *= mix(1.0, 0.85, smoothstep(0.25, 0.0, abs(wpos.y - 1.0)) * smoothstep(0.55, 0.8, n_value(q * 3.0)) * grime);
		r = mix(r, r * 1.2, grime * 0.5);
	}
	float hz = horizon_fade(VERTEX);
	ALBEDO = a * hz;
	ROUGHNESS = r;
	METALLIC = metallic;
	SPECULAR = 0.5 * hz;
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
