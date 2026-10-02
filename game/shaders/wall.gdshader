shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/horizon.gdshaderinc"
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
// A seam's eye-only patch has its paper slipped a few centimeters (a splice, D022).
uniform vec2 uv_slip = vec2(0.0);
// Generation loss: a room papered in a color that bled in from somewhere else.
uniform vec4 recolor_rect = vec4(-100.0, -100.0, -99.0, -99.0);
uniform vec3 recolor = vec3(1.0);
// Pushes the printed pattern away from the paper color so it reads at a few meters.
uniform float pattern_contrast = 2.4;
uniform vec3 tex_mean = vec3(0.584, 0.474, 0.162);

// Generation loss: a band of wall where the copy slipped sideways like a tracking error.
uniform vec4 shear_rect = vec4(-100.0, -100.0, -99.0, -99.0);   // x0, z0, x1, z1 (world)
uniform vec3 shear_band = vec3(1.1, 1.4, 0.07);                 // y0, y1, horizontal slip (m)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (UV + uv_slip) / tile;
	// Wallpaper hangs in sheets 0.53 m wide; each sheet's pattern sits a few millimeters off its
	// neighbor and the seams show as a hairline with a lifted edge (critique 006: walls looked flat).
	float sheet_w = 0.53;
	float sx = (UV.x + seed_offset.x * 3.0) / sheet_w;
	float sheet = floor(sx);
	float sf = fract(sx) * sheet_w;   // meters from this sheet's left edge
	float sh = n_hash12(vec2(sheet, 7.0));
	uv.y += (sh - 0.5) * 0.012 / tile.y;
	float seam_dark = exp(-pow(sf / 0.0012, 2.0)) + exp(-pow((sheet_w - sf) / 0.0012, 2.0));
	float lift = step(0.82, sh) * smoothstep(0.004, 0.0, sf) * smoothstep(1.4, 2.4, wpos.y);
	bool in_rect = wpos.x > shear_rect.x && wpos.x < shear_rect.z && wpos.z > shear_rect.y && wpos.z < shear_rect.w;
	float in_band = in_rect ? step(shear_band.x, wpos.y) * step(wpos.y, shear_band.y) : 0.0;
	float band_edge = in_rect ? max(exp(-pow((wpos.y - shear_band.x) / 0.004, 2.0)), exp(-pow((wpos.y - shear_band.y) / 0.004, 2.0))) : 0.0;
	uv.x += in_band * shear_band.z / tile.x;
	vec3 alb = use_tex ? texture(albedo_tex, uv).rgb : base_color;
	if (in_band > 0.5 && use_tex) {
		// a little chroma slip inside the band, as on a bad dub
		alb.r = texture(albedo_tex, uv + vec2(0.03, 0.0)).r;
		alb *= vec3(1.03, 0.98, 0.94);
	}
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
	// (critique 008/009, L049: corners where walls meet floor and ceiling looked like paper)
	alb *= mix(0.68, 1.0, smoothstep(0.0, 0.34, y));
	alb *= mix(0.78, 1.0, smoothstep(ceiling_h, ceiling_h - 0.32, y));

	alb = mix(alb, alb * 1.12 + vec3(0.015), band_edge * 0.35);
	alb *= 1.0 - 0.35 * seam_dark;
	alb = mix(alb, alb * 1.15 + vec3(0.02), lift * 0.6);
	// Grime where hands and shoulders brush the wall, and scuffs low down from chairs and feet.
	float hands = smoothstep(0.62, 0.8, n_fbm3(vec2(s * 1.7, y * 2.2) + 41.0)) * smoothstep(0.7, 1.0, y) * smoothstep(1.6, 1.3, y);
	alb *= 1.0 - 0.12 * hands * damage;
	float scuff = smoothstep(0.7, 0.86, n_value(vec2(s * 9.0, y * 3.0) + 13.0)) * smoothstep(0.55, 0.18, y);
	alb *= 1.0 - 0.18 * scuff * damage;
	if (wpos.x > recolor_rect.x && wpos.x < recolor_rect.z && wpos.z > recolor_rect.y && wpos.z < recolor_rect.w) {
		alb *= recolor;
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	AO = ao;
	AO_LIGHT_AFFECT = 0.15;
	SPECULAR = 0.4;
	if (use_tex) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	float hz = horizon_fade(VERTEX);
	ALBEDO *= hz;
	SPECULAR *= hz;
}
