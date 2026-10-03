extends Node3D
## The World: holds the active Space, the Player, the global look (environment, lens), and
## the review tools. M2 boots into the infinite Level 0 (Level0World); `--hero` loads the S01
## look-dev hero slice instead. M5 adds the furniture
## store hub: the store is another Space, and its duct-taped wall is a Threshold whose
## target is a Level 0 Space built behind it, so the crossing is one continuous walk.

var space: Space
var player: Player
var world_env: WorldEnvironment
var human: HumanInput
var _post: ColorRect
var _pause: Label


func _ready() -> void:
	if Game.is_capture() or Game.is_perf():
		# Exact output size for review frames: borderless, at the top-left, set explicitly
		# (switching to borderless otherwise keeps the old outer size).
		var res := String(Game.opts.get("res", "2560x1440")).split("x")
		get_window().borderless = true
		get_window().position = Vector2i.ZERO
		get_window().size = Vector2i(int(res[0]), int(res[1]))
	_apply_render_settings()
	# M2: the game is the infinite Level 0; the S01 hero slice stays as a reference (--hero).
	space = Level0Hero.new() if Game.opts.has("hero") else Level0World.new()
	add_child(space)
	space.build(Game.run_seed)

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = space.make_environment()
	world_env.camera_attributes = space.make_camera_attributes()
	add_child(world_env)

	player = Player.new()
	player.space = space
	add_child(player)
	player.spawn(space.get_spawn_transform())
	if Game.opts.has("start"):
		# Debug: --start=x,z,yaw_degrees (filmed checks of one spot).
		var st := String(Game.opts["start"]).split(",")
		if space.has_method("prepare_view"):
			space.prepare_view(Vector3(float(st[0]), 0.0, float(st[1])))
		player.spawn(Transform3D(Basis(Vector3.UP, deg_to_rad(float(st[2]))), Vector3(float(st[0]), 0.0, float(st[1]))))
	if Game.opts.has("start-room") and space.has_method("room_spawn"):
		# Debug: --start-room=cx:cz,hall_x,hall_z,face_x,face_z (inside a storeroom's hall, D036).
		var sr := String(Game.opts["start-room"]).split(",")
		var xf: Transform3D = space.room_spawn(sr[0], float(sr[1]), float(sr[2]), Vector2(float(sr[3]), float(sr[4])))
		player.spawn(xf)
	if space.has_method("attach_player"):
		space.attach_player(player)
	if Game.opts.has("route"):
		player.input = RouteInput.new()
	elif Game.autoplay:
		var bot := AutoplayBot.new()
		bot.space = space
		player.input = bot
	else:
		human = HumanInput.new()
		player.input = human
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_make_post()
	add_child(PerfOverlay.new())
	if space is Level0World:
		# Records your last seconds all the time; plays them back when the Occupant gets you (S06).
		var rp := DeathReplay.new()
		rp.name = "death_replay"
		add_child(rp)
		(space as Level0World).replay = rp
		rp.catalogue = (space as Level0World).catalogue
		if not Game.opts.has("no_descent"):
			# The run loop: the Landing, the stairwells, salvage, the kit (D050).
			var rd := RunDirector.new()
			rd.name = "run_director"
			add_child(rd)
			rd.attach(space as Level0World, player)
	if Game.is_capture():
		var cd := CaptureDirector.new()
		cd.process_mode = Node.PROCESS_MODE_ALWAYS   # keeps shooting while the death replay plays
		add_child(cd)
		cd.setup(Game.capture_dir, Game.duration, player)
	if Game.is_perf():
		add_child(PerfRecorder.new())
	if Game.opts.has("track"):
		var tr := TrackRecorder.new()
		tr.out_path = String(Game.opts["track"])
		tr.space = space
		tr.player = player
		add_child(tr)
	print("[NOCLIP] gpu=%s api=%s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])


## Quality knobs that live on the viewport / rendering server (also profiling switches).
func _apply_render_settings() -> void:
	var vp := get_viewport()
	vp.positional_shadow_atlas_size = int(Game.opts.get("atlas", "8192"))
	vp.positional_shadow_atlas_16_bits = Game.opts.has("atlas16")   # 16-bit depth bands on grazing walls
	RenderingServer.positional_soft_shadow_filter_set_quality(int(Game.opts.get("shadowq", "2")))
	# Haze froxel grid: 96 x 64 keeps the look and saves ~4 fps over 128 x 128.
	RenderingServer.environment_set_volumetric_fog_volume_size(int(Game.opts.get("fog_size", "96")), int(Game.opts.get("fog_depth", "64")))
	# SDFGI: how many frames light updates and convergence are spread over (profiling switches).
	if Game.opts.has("sdfgi_light"):
		RenderingServer.environment_set_sdfgi_frames_to_update_light(int(Game.opts["sdfgi_light"]))
	if Game.opts.has("sdfgi_conv"):
		RenderingServer.environment_set_sdfgi_frames_to_converge(int(Game.opts["sdfgi_conv"]))
	if Game.opts.has("sdfgi_rays"):
		RenderingServer.environment_set_sdfgi_ray_count(int(Game.opts["sdfgi_rays"]))


func _make_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_post = ColorRect.new()
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/lens_post.gdshader")
	_post.material = m
	layer.add_child(_post)
	_pause = Label.new()
	_pause.text = "Paused.  Click to keep going.  Press Q to quit."
	_pause.set_anchors_preset(Control.PRESET_CENTER)
	_pause.add_theme_font_size_override("font_size", 28)
	_pause.visible = false
	layer.add_child(_pause)


func _process(_delta: float) -> void:
	var m := _post.material as ShaderMaterial
	m.set_shader_parameter("frame_seed", float(Game.frame % 1009))
	m.set_shader_parameter("drift", Game.drift)


func _unhandled_input(e: InputEvent) -> void:
	if human == null:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		human.push_mouse(e.relative)
	elif e.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pause.visible = true
		var cat = space.get("catalogue")
		_pause.text = "Paused.  Click to keep going.  Press Q to quit." + (("\n\nON THIS TAPE\n" + (cat as Catalogue).tape_label()) if cat else "")
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_pause.visible = false
	elif e is InputEventKey and e.pressed and e.physical_keycode == KEY_Q and _pause.visible:
		get_tree().quit()
