class_name Level0Look
extends RefCounted
## The look of Level 0 ("The Yellow"): materials, environment, exposure. One place to tune.

const TEX := "res://assets/textures/level0/"


static func tex(name: String) -> Texture2D:
	var p := TEX + name + ".png"
	if ResourceLoader.exists(p):
		return load(p)
	return null


static func _shader(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


static func _bind(m: ShaderMaterial, prefix: String, maps: Dictionary) -> void:
	var albedo := tex(prefix + "_albedo")
	m.set_shader_parameter("use_tex", albedo != null)
	if albedo == null:
		return
	for param in maps.keys():
		var t := tex(prefix + "_" + String(maps[param]))
		if t:
			m.set_shader_parameter(param, t)


static func make_materials(seed_offset: Vector2) -> Dictionary:
	var m := {}

	var wall := _shader("res://shaders/wall.gdshader")
	_bind(wall, "wallpaper", {"albedo_tex": "albedo", "normal_tex": "normal", "rough_tex": "roughness", "ao_tex": "ao"})
	wall.set_shader_parameter("seed_offset", seed_offset)
	m["wall"] = wall

	var carpet := _shader("res://shaders/carpet.gdshader")
	_bind(carpet, "carpet", {"albedo_tex": "albedo", "normal_tex": "normal", "rough_tex": "roughness", "ao_tex": "ao"})
	carpet.set_shader_parameter("seed_offset", seed_offset)
	m["carpet"] = carpet

	var ceil := _shader("res://shaders/ceiling.gdshader")
	_bind(ceil, "ceiling_tile", {"albedo_tex": "albedo", "normal_tex": "normal", "rough_tex": "roughness", "ao_tex": "ao"})
	var stain := tex("ceiling_tile_stained_albedo")
	if stain:
		ceil.set_shader_parameter("stain_tex", stain)
	elif tex("ceiling_tile_albedo"):
		ceil.set_shader_parameter("stain_tex", tex("ceiling_tile_albedo"))
	ceil.set_shader_parameter("halo_strength", float(Game.opts.get("halo", "0.8")))
	m["ceiling"] = ceil

	var lens := _shader("res://shaders/troffer_lens.gdshader")
	var lens_e := tex("troffer_lens_emission")
	lens.set_shader_parameter("use_tex", lens_e != null)
	if lens_e:
		lens.set_shader_parameter("emission_tex", lens_e)
		var ln := tex("troffer_lens_normal")
		if ln:
			lens.set_shader_parameter("normal_tex", ln)
	lens.set_shader_parameter("emission_energy", float(Game.opts.get("lens_e", "2.4")))
	m["lens"] = lens

	var base := StandardMaterial3D.new()
	var bb := tex("baseboard_albedo")
	if bb:
		base.albedo_texture = bb
		base.normal_enabled = tex("baseboard_normal") != null
		base.normal_texture = tex("baseboard_normal")
		base.roughness_texture = tex("baseboard_roughness")
		base.roughness = 1.0
		base.uv1_scale = Vector3(1.0, 10.0, 1.0)
	else:
		base.albedo_color = Color(0.36, 0.29, 0.19)
		base.roughness = 0.6
	m["baseboard"] = base

	var tbar := StandardMaterial3D.new()
	tbar.albedo_color = Color(0.86, 0.84, 0.78)
	tbar.roughness = 0.5
	tbar.metallic = 0.0
	m["tbar"] = tbar

	m["housing"] = _shader("res://shaders/housing.gdshader")
	m["housing"].set_shader_parameter("reveal_glow", float(Game.opts.get("reveal", "0.9")))

	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.6, 0.55, 0.43)
	trim.roughness = 0.42
	m["trim"] = trim

	var door := StandardMaterial3D.new()
	door.albedo_color = Color(0.5, 0.45, 0.35)
	door.roughness = 0.55
	door.albedo_texture = tex("baseboard_albedo")
	door.uv1_scale = Vector3(0.2, 0.2, 0.2)
	m["door"] = door

	var knob := StandardMaterial3D.new()
	knob.albedo_color = Color(0.55, 0.47, 0.32)
	knob.metallic = 0.85
	knob.roughness = 0.38
	m["knob"] = knob

	var exit := StandardMaterial3D.new()
	var ex := tex("exit_sign_emission")
	exit.albedo_color = Color(0.1, 0.02, 0.02)
	exit.emission_enabled = true
	exit.emission_texture = ex
	exit.emission = Color(1, 1, 1)
	exit.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	exit.emission_energy_multiplier = 0.85   # letters stay legible under the bloom (L037)
	exit.roughness = 0.25
	m["exit"] = exit

	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.8, 0.76, 0.66)
	plate.roughness = 0.42
	m["plate"] = plate

	var slot := StandardMaterial3D.new()
	slot.albedo_color = Color(0.04, 0.035, 0.03)
	slot.roughness = 0.8
	m["slot"] = slot

	var plenum := StandardMaterial3D.new()
	plenum.albedo_color = Color(0.08, 0.075, 0.07)
	plenum.roughness = 0.95
	m["plenum"] = plenum
	return m


static func make_environment(preset: String) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.38, 0.24)
	e.ambient_light_energy = float(Game.opts.get("ambient", "0.015"))
	e.reflected_light_source = Environment.REFLECTION_SOURCE_BG

	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.tonemap_agx_white = 10.0
	e.tonemap_agx_contrast = float(Game.opts.get("agx_c", "1.3"))

	e.sdfgi_enabled = preset != "low"
	e.sdfgi_use_occlusion = true
	e.sdfgi_cascades = 3
	e.sdfgi_min_cell_size = 0.1
	e.sdfgi_bounce_feedback = float(Game.opts.get("gi_fb", "0.6"))
	e.sdfgi_energy = float(Game.opts.get("gi", "0.7"))
	e.sdfgi_read_sky_light = false
	e.sdfgi_normal_bias = 1.1
	e.sdfgi_probe_bias = 1.1

	e.ssao_enabled = true
	e.ssao_radius = 1.0
	e.ssao_intensity = float(Game.opts.get("ssao", "3.0"))
	e.ssao_power = 1.6
	e.ssao_detail = 0.6
	e.ssao_light_affect = float(Game.opts.get("ssao_la", "0.45"))   # corners darken under direct light too (L032)

	e.ssil_enabled = preset == "high"
	e.ssil_radius = 4.0
	e.ssil_intensity = 0.9
	e.ssil_sharpness = 0.98

	# SSR off: it smeared the bright lenses into milky blobs on wet carpet (critique 005) and costs ~2 fps.
	e.ssr_enabled = preset == "high" and Game.opts.has("ssr")
	e.ssr_max_steps = 56
	e.ssr_fade_in = 0.1
	e.ssr_fade_out = 1.6
	e.ssr_depth_tolerance = 0.25

	e.glow_enabled = true
	e.glow_normalized = true
	e.glow_intensity = 0.85
	e.glow_strength = 1.0
	e.glow_bloom = float(Game.opts.get("bloom", "0.1"))
	e.glow_hdr_threshold = 0.95
	e.glow_hdr_scale = 2.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 0.6)
	e.set_glow_level(2, 1.0)
	e.set_glow_level(3, 0.8)
	e.set_glow_level(4, 0.4)
	e.set_glow_level(5, 0.0)

	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = float(Game.opts.get("fog", "0.016"))
	e.volumetric_fog_albedo = Color(0.95, 0.92, 0.82)
	e.volumetric_fog_emission = Color(0, 0, 0)
	e.volumetric_fog_anisotropy = 0.45
	e.volumetric_fog_length = 36.0
	e.volumetric_fog_detail_spread = 2.0
	e.volumetric_fog_gi_inject = 0.6
	e.volumetric_fog_ambient_inject = 0.0
	e.volumetric_fog_temporal_reprojection_enabled = true
	e.volumetric_fog_temporal_reprojection_amount = 0.9

	# Profiling switches: --env-off=fog,sdfgi,ssil,ssr,ssao,glow
	var off := String(Game.opts.get("env-off", "")).split(",")
	if "fog" in off:
		e.volumetric_fog_enabled = false
	if "sdfgi" in off:
		e.sdfgi_enabled = false
	if "ssil" in off:
		e.ssil_enabled = false
	if "ssr" in off:
		e.ssr_enabled = false
	if "ssao" in off:
		e.ssao_enabled = false
	if "glow" in off:
		e.glow_enabled = false

	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.04
	e.adjustment_saturation = 1.1
	return e


static func make_camera_attributes() -> CameraAttributesPractical:
	var c := CameraAttributesPractical.new()
	c.auto_exposure_enabled = true
	c.auto_exposure_scale = float(Game.opts.get("ae", "0.36"))
	c.auto_exposure_speed = 0.55
	c.auto_exposure_min_sensitivity = 60.0
	c.auto_exposure_max_sensitivity = float(Game.opts.get("ae_max", "650"))   # dark rooms stay dark (L032)
	c.exposure_multiplier = 1.0
	return c
