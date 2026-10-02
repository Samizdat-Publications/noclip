class_name Player
extends CharacterBody3D
## First-person body. Grounded and slightly heavy: inertia on movement, a step-driven head
## bob, a small camera kick on each footstep, breath sway when standing still.
## Movement runs on physics ticks; the camera is placed every render frame from the
## interpolated body so it stays smooth at any frame rate.

const WALK := 1.45
const SPRINT := 3.8
const CROUCH := 0.75
const EYE := 1.62
const EYE_CROUCH := 1.06
const STRIDE_WALK := 0.66
const STRIDE_SPRINT := 0.98
const STRIDE_CROUCH := 0.5

var input: PlayerInput
var space: Space
var cam: Camera3D
var camcorder: Camcorder
var yaw := 0.0
var pitch := 0.0
var base_fov := 78.0

var _eye := EYE
var _phase := 0.0
var _step_acc := 0.0
var _stride := STRIDE_WALK
var _stamina := 1.0
var _kick := 0.0
var _speed := 0.0
var _roll := 0.0
var _sprinting := false
var _crouching := false
var _cap: CollisionShape3D
var _steps_damp: AudioStreamRandomizer
var _steps_wet: AudioStreamRandomizer
var _step_player: AudioStreamPlayer


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
	_setup_steps()


func spawn(t: Transform3D) -> void:
	global_position = t.origin
	yaw = t.basis.get_euler().y
	pitch = 0.0
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func _setup_steps() -> void:
	_steps_damp = _randomizer("step_carpet_damp_%02d", 8)
	_steps_wet = _randomizer("step_carpet_wet_%02d", 6)
	_step_player = AudioStreamPlayer.new()
	_step_player.bus = &"World"
	_step_player.max_polyphony = 2
	add_child(_step_player)


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
	_crouching = input.crouch
	var want := WALK
	if _crouching:
		want = CROUCH
	elif input.sprint and _stamina > 0.1 and input.move.y > 0.3:
		want = SPRINT
	_sprinting = want == SPRINT
	_stamina = clampf(_stamina + (-0.11 if _sprinting else 0.07) * delta, 0.0, 1.0)
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
	_stride = STRIDE_SPRINT if _sprinting else (STRIDE_CROUCH if _crouching else STRIDE_WALK)
	_step_acc += _speed * delta
	if _step_acc >= _stride:
		_step_acc -= _stride
		_footstep()
	_eye = lerpf(_eye, EYE_CROUCH if _crouching else EYE, 1.0 - exp(-7.0 * delta))
	var cap_shape := _cap.shape as CapsuleShape3D
	cap_shape.height = lerpf(cap_shape.height, 1.2 if _crouching else 1.75, 1.0 - exp(-10.0 * delta))
	_cap.position.y = cap_shape.height * 0.5
	camcorder.set_active(input.camcorder)
	if space and space.has_method("set_listener"):
		space.set_listener(global_position)
	if space and space.has_method("set_view"):
		space.set_view(global_position, Basis(Vector3.UP, yaw) * Vector3.FORWARD)


func _footstep() -> void:
	_kick = 0.008 if _sprinting else 0.004
	if _step_player == null:
		return
	var wet := space.floor_wetness(global_position) if space else 0.0
	var bank := _steps_wet if wet > 0.45 and _steps_wet.streams_count > 0 else _steps_damp
	if bank.streams_count == 0:
		return
	_step_player.stream = bank
	_step_player.volume_db = -3.0 if _sprinting else (-15.0 if _crouching else -9.0)
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
	var strafe := input.move.x
	_roll = lerpf(_roll, -strafe * 0.008, 1.0 - exp(-4.0 * delta))
	var b := Basis.from_euler(Vector3(pitch + sway_p - _kick, yaw + sway_y, _roll + bob_h * 0.15))
	var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	cam.global_transform = Transform3D(b, t.origin + Vector3(0.0, _eye + bob_v, 0.0) + right * bob_h)
	var target_fov := camcorder.fov if camcorder.active else base_fov
	cam.fov = lerpf(cam.fov, target_fov, 1.0 - exp(-9.0 * delta))
