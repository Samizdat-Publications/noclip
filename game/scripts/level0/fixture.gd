class_name Fixture
extends Node3D
## One 2x4 ft fluorescent troffer: diffuser mesh, a real area light, hum and buzz.
##
## Failing tubes follow real failure patterns instead of random strobing:
##   STARTER  the starter keeps trying: dim cathode glow, a burst of strike flashes, sometimes
##            it catches and holds for a few seconds, then drops out again
##   PULSE    worn cathode / weak ballast: slow uneven breathing in brightness
##   DROPOUT  mostly fine, with rare short dropouts and a double flash on recovery
##   DEAD     off; some still show a faint orange glow at the tube ends
## Everything is driven by the game clock and a per-fixture random stream, so a seed
## reproduces every flicker frame-exactly under Movie Maker.

enum State { ON, DEAD, STARTER, PULSE, DROPOUT, EVENT }

var state: int = State.ON
var base_energy: float = 1.0
var tint: Color = Color(1.0, 0.98, 0.9)
var level: float = 1.0
var cathode_glow: float = 0.0
var rng: RandomNumberGenerator

var light: Light3D
var lens: MeshInstance3D
var hum: AudioStreamPlayer3D
var buzz: AudioStreamPlayer3D
var tick_player: AudioStreamPlayer3D

var _queue: Array = []        # pending [duration, level, kind] segments
var _seg_left: float = 0.0
var _seg_level: float = 1.0
var _seg_kind: int = 0        # 0 hold, 1 pulse
var _pulse_phase: float = 0.0
var _pulse_freq: float = 0.7
var _shown: float = 1.0
var _was_bright: bool = true
var _orig_state: int = -1

const LIGHT_ENERGY := 2.2


func setup(p_state: int, p_rng: RandomNumberGenerator, p_energy: float, p_tint: Color) -> void:
	state = p_state
	rng = p_rng
	base_energy = p_energy
	tint = p_tint
	_pulse_phase = rng.randf() * TAU
	_pulse_freq = rng.randf_range(0.45, 1.1)
	if state == State.DEAD:
		level = 0.0
		cathode_glow = 0.35 if rng.randf() < 0.3 else 0.0
	elif state == State.ON:
		level = 1.0
	set_process(state != State.ON and state != State.DEAD)


func apply() -> void:
	if light:
		light.light_energy = LIGHT_ENERGY * base_energy * level
		light.visible = level > 0.002
	if lens:
		lens.set_instance_shader_parameter("light_level", level * base_energy)
		lens.set_instance_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		lens.set_instance_shader_parameter("cathode", cathode_glow)
	if hum:
		hum.volume_db = -80.0 if level < 0.08 else lerpf(-14.0, -6.0, clampf(level, 0.0, 1.0))
	if buzz:
		var failing := state == State.STARTER or state == State.PULSE or state == State.DROPOUT
		buzz.volume_db = lerpf(-30.0, -8.0, clampf(level, 0.0, 1.0)) if failing and level > 0.05 else -80.0


func _process(delta: float) -> void:
	_seg_left -= delta
	while _seg_left <= 0.0:
		if _queue.is_empty():
			_plan()
		var seg: Array = _queue.pop_front()
		_seg_left += seg[0]
		_seg_level = seg[1]
		_seg_kind = seg[2]
	var target := _seg_level
	if _seg_kind == 1:
		_pulse_phase += delta * TAU * _pulse_freq
		var w := 0.5 + 0.5 * sin(_pulse_phase) + 0.18 * sin(_pulse_phase * 2.71 + 1.3)
		target = clampf(0.5 + 0.5 * pow(clampf(w, 0.0, 1.0), 0.7), 0.0, 1.0) * _seg_level
	if Game.reduced_flicker:
		# Photosensitivity: no flashes; ease slowly toward a calm value.
		target = clampf(target, 0.35, 1.0) if state != State.STARTER else 0.25
		_shown = lerpf(_shown, target, 1.0 - exp(-delta / 0.6))
	else:
		# Tubes switch almost instantly; a few ms of phosphor persistence.
		_shown = lerpf(_shown, target, 1.0 - exp(-delta / 0.012))
	level = _shown
	cathode_glow = 0.6 if (state == State.STARTER and level < 0.2) else 0.0
	var bright := level > 0.5
	if bright and not _was_bright and tick_player and tick_player.stream:
		tick_player.pitch_scale = rng.randf_range(0.92, 1.08)
		tick_player.play()
	_was_bright = bright
	apply()


## Scripted event: the tube gives a last stutter and goes out (after `delay` seconds).
func kill(delay: float) -> void:
	if _orig_state == -1:
		_orig_state = state
	state = State.EVENT
	_queue = [[delay, level, 0], [0.05, 0.12, 0], [0.04, 0.95, 0], [0.09, 0.0, 0], [0.03, 0.55, 0], [0.05, 0.0, 0], [100000.0, 0.0, 0]]
	_seg_left = 0.0
	set_process(true)


## Scripted event: the tube struggles back on, then returns to its normal behavior.
func restore(delay: float) -> void:
	if _orig_state == -1:
		return
	state = State.EVENT
	_queue = [[delay, 0.0, 0], [rng.randf_range(0.3, 0.9), 0.03, 0], [0.05, 0.9, 0], [0.1, 0.05, 0], [0.06, 1.0, 0], [0.14, 0.06, 0], [0.4, 1.0, 0]]
	_seg_left = 0.0
	set_process(true)


func _plan() -> void:
	if state == State.EVENT:
		if _queue.is_empty() and _orig_state != -1 and level > 0.5:
			state = _orig_state
			_orig_state = -1
			if state == State.ON or state == State.DEAD:
				_queue.append([0.1, 1.0 if state == State.ON else 0.0, 0])
				set_process(false)
				return
		else:
			_queue.append([1.0, level, 0])
			return
	match state:
		State.STARTER:
			_queue.append([rng.randf_range(0.5, 2.2), 0.03, 0])
			var flashes := rng.randi_range(1, 4)
			for i in flashes:
				_queue.append([rng.randf_range(0.03, 0.11), rng.randf_range(0.7, 1.0), 0])
				_queue.append([rng.randf_range(0.04, 0.16), 0.04, 0])
			if rng.randf() < 0.45:
				_queue.append([rng.randf_range(0.04, 0.09), 1.0, 0])
				_queue.append([rng.randf_range(0.03, 0.06), 0.1, 0])
				_queue.append([rng.randf_range(1.0, 6.0), rng.randf_range(0.85, 1.0), 0])
		State.PULSE:
			_queue.append([rng.randf_range(2.0, 6.0), 1.0, 1])
			if rng.randf() < 0.35:
				_queue.append([rng.randf_range(0.05, 0.14), 0.15, 0])
				_queue.append([rng.randf_range(0.2, 0.6), 0.9, 1])
		State.DROPOUT:
			_queue.append([rng.randf_range(2.5, 10.0), 1.0, 0])
			_queue.append([rng.randf_range(0.06, 0.22), 0.03, 0])
			_queue.append([0.05, 1.0, 0])
			_queue.append([rng.randf_range(0.04, 0.09), 0.08, 0])
		_:
			_queue.append([5.0, level, 0])
