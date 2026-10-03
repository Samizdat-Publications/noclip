class_name Player
extends CharacterBody3D
## First-person body. Grounded and slightly heavy: inertia on movement, a step-driven head
## bob, a small camera kick on each footstep, breath sway when standing still.
## Movement runs on physics ticks; the camera is placed every render frame from the
## interpolated body so it stays smooth at any frame rate.

const WALK := 1.45
const SPRINT := 3.8
const CROUCH := 0.75
const CRAWL := 0.55
const CLIMB := 1.35
const EYE := 1.62
const EYE_CROUCH := 1.06
const EYE_CRAWL := 0.36
const STRIDE_CRAWL := 0.4
const STRIDE_WALK := 0.76   # about 1.9 steps a second at a walk (0.66 read as hurried, Gemini 023)
const STRIDE_SPRINT := 0.98
const STRIDE_CROUCH := 0.5

## Every footstep, with how far it carries in meters (the Occupant listens, S06).
signal stepped(loud_m: float)

var input: PlayerInput
var space: Space
var caught := false          # the Occupant has you: no control, the death replay follows (S06)
var cam: Camera3D
var camcorder: Camcorder
var yaw := 0.0
var pitch := 0.0
## Render layers of the space you are not in (the hall under a storeroom, or the level above it,
## PortalRoom / D036). The held camcorder lives on its own layer so it shows in both.
var hide_layers := 1 << 12
const VIEW_LAYER := 1 << 14
var base_fov := 70.0   # 78 stretched the walls at the screen edges (critique 006, L024)

var _eye := EYE
var _phase := 0.0
var _step_acc := 0.0
var _stride := STRIDE_WALK
var _stride_jitter := 1.0
var _step_rng := Game.rng("player:steps")
var _stamina := 1.0
var _kick := 0.0
var _speed := 0.0
var _sprinting := false
var _crouching := false
var _crawling := false
var _climbing := false
var _climb_acc := 0.0
var _cap: CollisionShape3D
var _steps_damp: AudioStreamRandomizer
var _steps_wet: AudioStreamRandomizer
var _steps_soggy: AudioStreamRandomizer
var _steps_run: AudioStreamRandomizer
var _step_player: AudioStreamPlayer3D
var _steps_squish: AudioStreamRandomizer
var _breath: Array[AudioStreamPlayer] = []
var _vm_baked := false   # camcorder_v3 carries its own worn, baked materials (L087)   # calm, heavy, fear loops (M3, D026)


func _ready() -> void:
	_cap = CollisionShape3D.new()
	var c := CapsuleShape3D.new()
	c.radius = 0.3
	c.height = 1.75
	_cap.shape = c
	_cap.position.y = 0.875
	add_child(_cap)
	floor_snap_length = 0.3
	cam = Camera3D.new()
	cam.fov = base_fov
	cam.near = 0.04
	cam.far = 90.0
	cam.top_level = true
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	cam.current = true
	camcorder = Camcorder.new()
	add_child(camcorder)
	var vm_path := "res://assets/props/player/camcorder.glb"
	for cand in ["camcorder_v3", "camcorder_v2"]:
		if ResourceLoader.exists("res://assets/props/player/%s.glb" % cand):
			vm_path = "res://assets/props/player/%s.glb" % cand
			break
	_vm_baked = vm_path.contains("_v3")
	if ResourceLoader.exists(vm_path):
		var body := (load(vm_path) as PackedScene).instantiate() as Node3D
		# The model was built with its lens toward you (S05: that is why it read as a pistol aimed
		# back at the player, L092/L125). Turned round inside a pivot whose origin is the eyecup and
		# whose -z is the way the lens looks.
		var vm := Node3D.new()
		vm.name = "camcorder_view"
		vm.add_child(body)
		body.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, -0.215))
		cam.add_child(vm)
		_add_flip_screen(vm)
		_prep_viewmodel(vm)
		vm.visible = false
		camcorder.viewmodel = vm
	_setup_steps()


## The open flip-out screen on the camera's left side, facing you (S05, L092/L125: critics read the
## held camera as a pistol four times; the lit side screen is the one shape that says camcorder).
## Pivot frame: eyecup at the origin, lens toward -z, the body's left side at x = -0.06.
func _add_flip_screen(vm: Node3D) -> void:
	var lcd := Node3D.new()
	lcd.name = "flip_screen"
	vm.add_child(lcd)
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.078, 0.054, 0.007)
	frame.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.07, 0.07, 0.075)
	fm.roughness = 0.55
	frame.material_override = fm
	frame.position = Vector3(-0.06 - 0.039, -0.022, -0.118)
	lcd.add_child(frame)
	var hinge := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.008, 0.05, 0.012)
	hinge.mesh = hb
	hinge.material_override = fm
	hinge.position = Vector3(-0.062, -0.022, -0.122)
	lcd.add_child(hinge)
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.064, 0.044)
	screen.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/cam_lcd.gdshader")
	screen.material_override = sm
	screen.position = Vector3(-0.06 - 0.039, -0.022, -0.118 + 0.0036)
	lcd.add_child(screen)
	camcorder.lcd_mat = sm


## The held camcorder is part of the view, not the world: no shadows, no GI.
func _prep_viewmodel(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.layers = VIEW_LAYER
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		g.extra_cull_margin = 1.0
	if n is MeshInstance3D:
		# Worn charcoal plastic (critiques 009/012: the held camera looked like a shiny toy).
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is BaseMaterial3D and not _vm_baked:
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				if m.resource_name == "camcorder_body":
					d.albedo_color = d.albedo_color * Color(0.32, 0.32, 0.33)
				elif m.resource_name.to_lower().contains("glass"):
					d.metallic = 0.0
					d.roughness = 0.08
				else:
					d.metallic = minf(d.metallic, 0.15)
					d.roughness = maxf(d.roughness, 0.62)
					d.albedo_color = d.albedo_color * Color(1.25, 1.25, 1.25)
				mi.set_surface_override_material(i, d)
	for c in n.get_children():
		_prep_viewmodel(c)


func spawn(t: Transform3D) -> void:
	global_position = t.origin
	yaw = t.basis.get_euler().y
	pitch = 0.0
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func _setup_steps() -> void:
	_steps_damp = _randomizer("step_carpet_damp_%02d", 8)
	_steps_wet = _randomizer("step_carpet_wet_%02d", 6)
	_steps_soggy = _randomizer("step_carpet_soggy_%02d", 8)
	_steps_run = _randomizer("step_carpet_soggy_run_%02d", 4)
	_steps_squish = _randomizer("step_carpet_squish_%02d", 8)
	# Positional at the feet, so the room's reverb (its Area3D) colors them (M3, D026).
	_step_player = AudioStreamPlayer3D.new()
	_step_player.bus = &"World"
	_step_player.max_polyphony = 2
	_step_player.unit_size = 3.0
	_step_player.position = Vector3(0, 0.1, 0)
	_step_player.attenuation_filter_cutoff_hz = 20000.0
	add_child(_step_player)
	for nm in ["breath_calm_loop", "breath_heavy_loop", "breath_fear_loop"]:
		var bp := AudioStreamPlayer.new()
		var path: String = "res://assets/audio/level0/" + nm + ".wav"
		if ResourceLoader.exists(path):
			var st := load(path) as AudioStreamWAV
			if st:
				st.loop_mode = AudioStreamWAV.LOOP_FORWARD
				st.loop_end = int(st.get_length() * st.mix_rate)
			bp.stream = st
			bp.autoplay = true
		bp.bus = &"Master"
		bp.volume_db = -80.0
		add_child(bp)
		_breath.append(bp)


func _randomizer(pattern: String, n: int) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = 1.05
	r.random_volume_offset_db = 1.5
	for i in n:
		var p := "res://assets/audio/level0/" + (pattern % (i + 1)) + ".wav"
		if ResourceLoader.exists(p):
			r.add_stream(-1, load(p))
	return r


func _physics_process(delta: float) -> void:
	if input == null:
		return
	input.update_move(self, delta)
	# Stance (S04): crawl when asked, when walking into an opening too low to crouch through,
	# and for as long as there is no room above to get up; crouch likewise under ~1.8 m.
	var room := _head_room()
	var low_ahead := input.move.y > 0.2 and _low_opening_ahead()
	_crawling = input.crawl or low_ahead or (_crawling and room < 1.3)
	_crouching = not _crawling and (input.crouch or room < 1.85)
	var want := WALK
	if _crawling:
		want = CRAWL
	elif _crouching:
		want = CROUCH
	elif input.sprint and _stamina > 0.1 and input.move.y > 0.3:
		want = SPRINT
	_sprinting = want == SPRINT
	_stamina = clampf(_stamina + (-0.11 if _sprinting else 0.07) * delta, 0.0, 1.0)
	# Ladders (S04): walk into one facing it and you climb; forward goes up (down if you look
	# down), back goes down; at the top, keep pushing to step off onto the ledge.
	var lad: Dictionary = space.ladder_at(global_position) if space and space.has_method("ladder_at") else {}
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	if lad.is_empty():
		_climbing = false
	elif not _climbing and fwd.dot(-(lad["n"] as Vector3)) > 0.35 and input.move.y > 0.15 and not _crawling:
		_climbing = true
	if _climbing and global_position.y > float(lad["top"]) - 0.75:
		_crawling = true     # pull yourself in through a hole too low to stand in
		_crouching = false
	if _climbing:
		var nn: Vector3 = lad["n"]
		var up := input.move.y * (-1.0 if pitch < -0.75 else 1.0)
		velocity = Vector3(0.0, up * CLIMB, 0.0) - nn * 0.35 * clampf(input.move.y, 0.0, 1.0)
		if global_position.y > float(lad["top"]) - 0.35 and input.move.y > 0.1:
			velocity = -nn * 1.3 + Vector3(0.0, 1.2, 0.0)   # over the sill
		if is_on_floor() and input.move.y < -0.1:
			_climbing = false
		_climb_acc += absf(velocity.y) * delta
		if _climb_acc > 0.32:
			_climb_acc = 0.0
			_footstep()
	else:
		var wish := Basis(Vector3.UP, yaw) * Vector3(input.move.x, 0.0, -input.move.y)
		if wish.length() > 1.0:
			wish = wish.normalized()
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		var accel := 6.0 if wish.length() > 0.01 else 8.5
		hv = hv.lerp(wish * want, 1.0 - exp(-accel * delta))
		velocity.x = hv.x
		velocity.z = hv.z
		velocity.y = -0.5 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()
	_speed = Vector3(velocity.x, 0.0, velocity.z).length()
	_stride = STRIDE_SPRINT if _sprinting else (STRIDE_CRAWL if _crawling else (STRIDE_CROUCH if _crouching else STRIDE_WALK))
	if not _climbing:
		_step_acc += _speed * delta
		if _step_acc >= _stride * _stride_jitter:
			_step_acc -= _stride * _stride_jitter
			# no two steps quite the same length, so the rhythm is a person's, not a metronome's
			_stride_jitter = _step_rng.randf_range(0.93, 1.07)
			_footstep()
	var eye_want := EYE_CRAWL if _crawling else (EYE_CROUCH if _crouching else EYE)
	_eye = lerpf(_eye, eye_want, 1.0 - exp(-7.0 * delta))
	var cap_shape := _cap.shape as CapsuleShape3D
	var h_want := 0.62 if _crawling else (1.2 if _crouching else 1.75)
	cap_shape.height = lerpf(cap_shape.height, h_want, 1.0 - exp(-10.0 * delta))
	_cap.position.y = cap_shape.height * 0.5
	camcorder.set_active(input.camcorder)
	_update_breath(delta)
	if space and space.has_method("set_listener"):
		space.set_listener(global_position)
	if space and space.has_method("set_view"):
		space.set_view(global_position, Basis(Vector3.UP, yaw) * Vector3.FORWARD)


## Free height above the feet (up to 2.4 m).
func _head_room() -> float:
	var ss := get_world_3d().direct_space_state
	var a := global_position + Vector3(0, 0.25, 0)
	var q := PhysicsRayQueryParameters3D.create(a, a + Vector3(0, 2.15, 0))
	q.exclude = [get_rid()]
	var hit := ss.intersect_ray(q)
	return 2.4 if hit.is_empty() else (hit["position"] as Vector3).y - global_position.y


## A wall at chest height just ahead with a gap under it: an opening too low to walk into.
func _low_opening_ahead() -> bool:
	var ss := get_world_3d().direct_space_state
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var hi := global_position + Vector3(0, 1.0, 0)
	var lo := global_position + Vector3(0, 0.32, 0)
	var q1 := PhysicsRayQueryParameters3D.create(hi, hi + fwd * 0.75)
	q1.exclude = [get_rid()]
	if ss.intersect_ray(q1).is_empty():
		return false
	var q2 := PhysicsRayQueryParameters3D.create(lo, lo + fwd * 1.1)
	q2.exclude = [get_rid()]
	return ss.intersect_ray(q2).is_empty()


## Breathing you hear in your own head: calm, winded after a sprint, held and shaky when afraid.
func _update_breath(delta: float) -> void:
	if _breath.size() < 3:
		return
	var winded := clampf((0.75 - _stamina) / 0.6, 0.0, 1.0)
	var afraid := clampf(Game.fear, 0.0, 1.0)
	var calm := clampf(1.0 - winded - afraid, 0.0, 1.0)
	var lv := [calm, winded, afraid]
	for i in 3:
		var target: float = -80.0 if float(lv[i]) < 0.02 else linear_to_db(float(lv[i])) + [-6.0, -3.0, -4.0][i]
		_breath[i].volume_db = lerpf(_breath[i].volume_db, target, 1.0 - exp(-3.0 * delta))


## How far your steps carry right now (meters): running on wet carpet is loud, crouching is not.
func noise_radius() -> float:
	if _speed < 0.2:
		return 0.0
	if _sprinting:
		return 21.0
	if _crawling:
		return 1.5
	if _crouching:
		return 2.5
	if _climbing:
		return 5.0
	return 6.5


func stamina() -> float:
	return _stamina


func is_sprinting() -> bool:
	return _sprinting


func is_low() -> bool:
	return _crouching or _crawling


func _footstep() -> void:
	_kick = 0.008 if _sprinting else 0.004
	var wet := space.floor_wetness(global_position) if space else 0.0
	stepped.emit(noise_radius() + (2.5 if wet > 0.3 else 0.0))
	if _step_player == null:
		return
	# The carpet never dries (critiques 006 to 008: steps sounded like shoes on dry concrete).
	var bank := _steps_soggy if _steps_soggy.streams_count > 0 else _steps_damp
	if _steps_squish.streams_count > 0 and Game.frame % 2 == 0:
		bank = _steps_squish
	if wet > 0.3 and _steps_wet.streams_count > 0 and Game.frame % 3 != 0:
		bank = _steps_wet
	if _sprinting and _steps_run.streams_count > 0:
		bank = _steps_run
	if bank.streams_count == 0:
		return
	_step_player.stream = bank
	_step_player.volume_db = (-3.0 if _sprinting else (-15.0 if _crouching else (-17.0 if _crawling else (-11.0 if _climbing else -9.0)))) + (2.5 if bank == _steps_wet else (1.5 if bank == _steps_soggy else 0.0))
	_step_player.play()


func _process(delta: float) -> void:
	if input == null:
		return
	input.update_look(self, delta)
	yaw -= input.look_delta.x
	pitch = clampf(pitch + input.look_delta.y, -1.35, 1.35)

	var t := get_global_transform_interpolated()
	var moving := clampf(_speed / WALK, 0.0, 2.2)
	_phase += delta * _speed / maxf(_stride, 0.01) * PI
	var amp := 0.022 * moving
	var bob_v := (cos(_phase * 2.0) - 1.0) * 0.5 * amp
	var bob_h := sin(_phase) * amp * 0.6
	# Breath sway, stronger when winded.
	var clk := Game.clock
	var breath := (1.0 - clampf(moving, 0.0, 1.0)) * (1.0 + (1.0 - _stamina) * 2.0)
	var sway_p := (sin(clk * 0.93) * 0.0035 + sin(clk * 2.1 + 1.0) * 0.0012) * breath
	var sway_y := (sin(clk * 0.61 + 2.0) * 0.003) * breath
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-10.0 * delta))
	# No camera roll: strafe lean and bob roll made the walls look like they were toppling (L024).
	var b := Basis.from_euler(Vector3(pitch + sway_p - _kick, yaw + sway_y, 0.0))
	var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	cam.global_transform = Transform3D(b, t.origin + Vector3(0.0, _eye + bob_v, 0.0) + right * bob_h)
	# Render layer 11 holds what exists only on tape (TapeEvents); the eye never draws it.
	# Layer 12 holds what only the eye sees (the wall over a seam, D022); the tape never draws it.
	cam.cull_mask = ((0xFFFFF & ~TapeEvents.LAYER_EYE) if camcorder.active else (0xFFFFF & ~TapeEvents.LAYER_TAPE)) & ~hide_layers
	var target_fov := camcorder.fov if camcorder.active else base_fov
	cam.fov = lerpf(cam.fov, target_fov, 1.0 - exp(-9.0 * delta))
