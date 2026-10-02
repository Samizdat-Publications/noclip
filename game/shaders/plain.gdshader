shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Plain surfaces (T-bar grid, baseboards, door frames, doors, outlets, plenum) with the same
// smooth horizon fade as the level shaders. The dithered fade of a standard material read as
// glitter on the distant ceiling grid (critique 012).

#include "res://shaders/horizon.gdshaderinc"

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
