extends Node3D
## The World: holds the active Space, the Player, the global look (environment, lens), and
## the review tools. M1 boots straight into the Level 0 hero slice. M5 adds the furniture
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
	space = Level0Hero.new()
	add_child(space)
	space.build(Game.run_seed)

	world_env = WorldEnvironment.new()
	world_env.environment = space.make_environment()
	world_env.camera_attributes = space.make_camera_attributes()
	add_child(world_env)

	player = Player.new()
	player.space = space
	add_child(player)
	player.spawn(space.get_spawn_transform())
	if Game.autoplay:
		var bot := AutoplayBot.new()
		bot.space = space
		player.input = bot
	else:
		human = HumanInput.new()
		player.input = human
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_make_post()
	add_child(PerfOverlay.new())
	if Game.is_capture():
		var cd := CaptureDirector.new()
		add_child(cd)
		cd.setup(Game.capture_dir, Game.duration, player)
	if Game.is_perf():
		add_child(PerfRecorder.new())
	print("[NOCLIP] gpu=%s api=%s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])


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
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_pause.visible = false
	elif e is InputEventKey and e.pressed and e.physical_keycode == KEY_Q and _pause.visible:
		get_tree().quit()
