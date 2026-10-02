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
// Standing water: one flooded stretch per level (x0, z0, x1, z1), ragged edges.
uniform vec4 flood_rect = vec4(-100.0, -100.0, -99.0, -99.0);
// Live panel levels of this chunk (scripts/level0/fixture_field.gd): wet carpet shows a soft,
// blurred reflection of the panels overhead, found by bouncing the view ray off the floor up to
// the ceiling plane. Never a hot spot (critique 007, L034).
uniform sampler2D field_tex : filter_linear, repeat_disable;
uniform vec2 field_origin = vec2(0.0);
uniform float field_cell = 0.6;
uniform vec2 field_size = vec2(1.0);
uniform float ceiling_h = 2.6;
uniform float reflect_strength = 0.9;

uniform vec3 world_shift = vec3(0.0);   // a loop copy samples its template's patterns

varying vec3 wpos;
varying vec3 wraw;

void vertex() {
	wraw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wpos = wraw - world_shift;
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

	// Heathered fibers: color varies at the centimeter scale, so far carpet still reads as fabric.
	float heather = n_value(p * 31.0 + 7.0) * 0.6 + n_value(p * 83.0) * 0.4;
	alb *= mix(0.84, 1.12, heather);
	// Berber yarn: dark brown and pale flecks a centimeter or two across, so the carpet still
	// reads as woven fabric at walking distance (critique 006: "flat ochre with no texture").
	float fk = n_value(p * 70.0);
	float fk2 = n_value(p * 52.0 + 9.7);
	alb *= mix(1.0, 0.74, smoothstep(0.22, 0.12, fk));
	alb *= mix(1.0, 1.14, smoothstep(0.8, 0.9, fk));
	alb *= mix(vec3(1.0), vec3(0.8, 0.74, 0.68), smoothstep(0.16, 0.08, fk2));
	// Rows of tufts: faint lines of light and shade across the pile.
	float rows = 0.5 + 0.5 * sin((p.x * 0.8 + p.y * 0.6) * 230.0);
	alb *= mix(0.95, 1.04, rows * smoothstep(0.2, 0.8, n_value(p * 2.0 + 4.0)));
	// Pile direction: brushed patches look lighter or darker depending on how the fibers lie.
	alb *= mix(0.9, 1.08, n_fbm3(vec2(p.x * 1.4 + p.y * 0.3, p.y * 0.55) + 21.0));
	alb *= vec3(0.8, 0.74, 0.62);   // darker, browner than the walls: value separation (critique 005)

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
	// Damp sheen (critique 006, L027): wet fibers lie flat and catch the panels as a soft smear.
	// SSR stays off (D012), so this is only the lights' own highlight, never a mirror blob.
	rough = mix(rough, 0.62, wet);
	rough = mix(rough, rough * 0.86, mottle);
	nrm = mix(nrm, vec3(0.5, 0.5, 1.0), wet * 0.55);

	// Flood: drowned, soaked carpet with a soft sheen. (Mirror-still water smeared the big soft
	// light highlights into white blobs, progress/0031; revisit with SSR-only reflections.)
	vec2 fc = (flood_rect.xy + flood_rect.zw) * 0.5;
	vec2 fh = (flood_rect.zw - flood_rect.xy) * 0.5;
	vec2 fd = abs(p - fc) - fh;
	float box = length(max(fd, 0.0)) + min(max(fd.x, fd.y), 0.0);
	float edge = box + (n_fbm(p * 0.9 + 11.0) - 0.5) * 1.6;
	float flood = smoothstep(0.25, -0.35, edge);
	alb = mix(alb, alb * vec3(0.32, 0.3, 0.26), smoothstep(0.6, -0.6, edge));
	rough = mix(rough, 0.6 + 0.08 * n_value(p * 3.0), flood);
	nrm = mix(nrm, vec3(0.5 + 0.015 * sin(p.x * 9.0 + p.y * 4.0), 0.5, 1.0), flood);

	ALBEDO = alb;
	ROUGHNESS = rough;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	SPECULAR = mix(mix(0.2, 0.22, wet), 0.2, flood);
	// Soft reflection of the lit panels above, in wet patches and the flooded room.
	float sheen = max(wet * 0.75, flood) + mottle * 0.15;
	if (sheen > 0.01) {
		vec3 V = normalize(CAMERA_POSITION_WORLD - wraw);
		vec3 R = reflect(-V, vec3(0.0, 1.0, 0.0));
		if (R.y > 0.02) {
			vec2 pc = wraw.xz + R.xz * ((ceiling_h - wraw.y) / R.y);
			vec2 t = (pc - field_origin) / field_cell;
			// Wider blur farther away along the ray (rough, wet fibers smear the image).
			float spread = 0.6 + 0.25 * length(R.xz) / max(R.y, 0.05);
			vec3 refl = vec3(0.0);
			for (int i = -1; i <= 1; i++) {
				for (int j = -1; j <= 1; j++) {
					refl += texture(field_tex, (t + vec2(float(i), float(j)) * spread) / field_size).rgb;
				}
			}
			refl /= 9.0;
			float fres = 0.03 + 0.5 * pow(1.0 - clamp(V.y, 0.0, 1.0), 4.0);
			EMISSION = refl * vec3(1.0, 0.96, 0.86) * fres * sheen * reflect_strength;
		}
	}
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength;
}
