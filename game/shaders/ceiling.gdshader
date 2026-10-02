shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Drop-ceiling tiles. UV is 0..1 per tile. COLOR.r = per-tile random, COLOR.g = stained,
// COLOR.b = sag darkening.

uniform bool use_tex = false;
uniform vec3 base_color : source_color = vec3(0.86, 0.84, 0.76);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stain_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength = 0.8;

void fragment() {
	vec2 uv = UV;
	float rnd = COLOR.r;
	// Tiles are not always laid the same way round.
	if (rnd > 0.5) { uv = vec2(1.0) - uv; }
	vec3 alb = use_tex ? mix(texture(albedo_tex, uv).rgb, texture(stain_tex, uv).rgb, COLOR.g) : base_color;
	alb *= mix(0.9, 1.03, fract(rnd * 7.31));
	alb *= mix(vec3(1.0), vec3(0.95, 0.92, 0.84), fract(rnd * 3.17) * 0.7);
	alb *= 1.0 - 0.35 * COLOR.b;
	// Keep the ceiling a pale, slightly gray off-white so it separates from the yellow walls.
	float l = dot(alb, vec3(0.2126, 0.7152, 0.0722));
	alb = mix(vec3(l), alb, 0.7) * 1.06;
	ALBEDO = alb;
	ROUGHNESS = use_tex ? texture(rough_tex, uv).r : 0.93;
	AO = use_tex ? texture(ao_tex, uv).r : 1.0;
	SPECULAR = 0.3;
	if (use_tex) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
