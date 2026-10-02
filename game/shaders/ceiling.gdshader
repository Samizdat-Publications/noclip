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
// Live fixture levels, one texel per tile (scripts/level0/fixture_field.gd). Blurred here into
// the glow a lit panel throws on the tiles around it: lens glare plus the bounce from the
// bright pool on the floor below, which real drop ceilings show strongly.
uniform sampler2D field_tex : filter_linear, repeat_disable;
uniform vec2 field_origin = vec2(0.0);
uniform float field_cell = 0.6;
uniform vec2 field_size = vec2(1.0);
uniform float halo_strength = 0.55;

uniform float ceiling_h = 2.6;

varying vec3 wpos;
varying float wup;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wup = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
}

vec3 halo_at(vec2 p) {
	vec2 t = (p - field_origin) / field_cell;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			vec2 o = vec2(float(i), float(j)) * 0.7;
			float w = exp(-dot(o, o) * 0.55);
			acc += texture(field_tex, (t + o) / field_size).rgb * w;
			wsum += w;
		}
	}
	return acc / wsum;
}

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
	// A tile that fell onto the wet carpet is dirty and damp, not bright white (critique 006).
	if (wup > 0.5) { alb *= vec3(0.36, 0.33, 0.28); }
	ALBEDO = alb;
	if (wpos.y > ceiling_h - 0.15) {
		EMISSION = alb * halo_at(wpos.xz) * halo_strength;
	}
	ROUGHNESS = use_tex ? texture(rough_tex, uv).r : 0.93;
	AO = use_tex ? texture(ao_tex, uv).r : 1.0;
	SPECULAR = 0.3;
	if (use_tex) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
