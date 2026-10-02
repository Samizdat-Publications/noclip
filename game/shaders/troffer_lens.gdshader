shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, shadows_disabled;
// Prismatic diffuser of a fluorescent troffer. Brightness and tint are per instance so one
// material serves every fixture; the fixture script drives light_level for flicker.
// cathode = faint orange glow at the tube ends of a dead or struggling tube.

instance uniform float light_level = 1.0;
instance uniform vec3 tint = vec3(1.0, 0.98, 0.9);
instance uniform float cathode = 0.0;
uniform float emission_energy = 5.0;
uniform bool use_tex = false;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;

void fragment() {
	vec3 e = use_tex ? texture(emission_tex, UV).rgb : vec3(1.0);
	// Two tubes behind the diffuser: soft brighter bands along the length, darker between and
	// at the edges, fading near the tube ends.
	float across = UV.x;
	float tubes = 0.42 + 0.78 * (exp(-pow((across - 0.3) / 0.1, 2.0)) + exp(-pow((across - 0.7) / 0.1, 2.0)));
	float along = UV.y;
	tubes *= mix(0.78, 1.0, smoothstep(0.0, 0.12, along) * smoothstep(1.0, 0.88, along));
	// The prism grid catches the light: a fine sparkle that keeps it from looking like a sticker.
	float prism = use_tex ? texture(normal_tex, UV).r : 0.5;
	tubes *= mix(0.86, 1.14, prism);
	float ends = smoothstep(0.1, 0.0, along) + smoothstep(0.9, 1.0, along);
	vec3 col = e * tint * tubes * light_level * emission_energy;
	col += vec3(1.0, 0.35, 0.08) * cathode * ends * 0.6;
	ALBEDO = vec3(0.82, 0.82, 0.8);
	ROUGHNESS = 0.3;
	SPECULAR = 0.5;
	EMISSION = col;
	if (use_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.5;
	}
}
