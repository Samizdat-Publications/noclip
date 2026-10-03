class_name OccupantRig
extends Node3D
## The Occupant as the hunt shows it (S06, L156). One body seen four ways at once:
## - by eye: nothing but the room bent where it stands (shimmer) and the shadow it throws (an
##   invisible copy that only casts shadows), both moving smoothly, the way it moves when you are
##   not filming it;
## - on tape: a hole in the recording with a few strips of paper on it, that never moves smoothly:
##   it holds where it was and jumps to where it is now every few frames (a frame skip), leaving an
##   after-image of the pose it skipped from.
## The rig's own position is the true one (the hunt moves it); the tape body lags it in jumps.

var tape: Occupant
var ghost: Occupant
var eye: Occupant
var shade_body: Occupant
var presence := 1.0          # how strongly the eye's bend shows (0 gone)
var tear := 0.0
var skip_gap := Vector2(0.18, 0.42)   # seconds between tape frame skips
var show_eye := true
var show_tape := true
var alt_clips: Array = []    # other clips a held frame may come from (the chase: never just a sprint)
var _skip_t := 0.0
var _ghost_t := 0.0
var _clip := ""
var _speed := 1.0
var _rng: RandomNumberGenerator
var _tape_xf := Transform3D.IDENTITY
var _held_clip := "idle"
var _held_t := 0.0


func _ready() -> void:
	_rng = Game.rng("occupant:rig")
	tape = _make("tape", TapeEvents.LAYER_TAPE)
	tape.top_level = true
	ghost = _make("tape", TapeEvents.LAYER_TAPE)
	ghost.top_level = true
	ghost.visible = false
	eye = _make("shimmer", TapeEvents.LAYER_EYE)
	shade_body = _make("shadow", 1)
	_tape_xf = global_transform


func _make(look: String, layers: int) -> Occupant:
	var o := Occupant.new()
	add_child(o)
	o.set_look(look)
	o.set_layers(layers)
	return o


## The clip it is doing; by eye it plays smoothly, on tape it is held a frame at a time.
func set_clip(clip: String, speed: float = 1.0) -> void:
	if clip == _clip and is_equal_approx(speed, _speed):
		return
	_clip = clip
	_speed = speed
	eye.play(clip, speed)
	shade_body.play(clip, speed)


## Jumps the tape body to where the rig is now (a frame skip), with an after-image of the old pose.
func skip_now() -> void:
	var prev := tape.held()
	ghost.global_transform = _tape_xf
	if String(prev[0]) != "":
		ghost.hold(String(prev[0]), float(prev[1]))
	_ghost_t = 0.32
	_tape_xf = global_transform
	tape.global_transform = _tape_xf
	_held_clip = _clip
	if not alt_clips.is_empty() and _rng.randf() < 0.45:
		_held_clip = alt_clips[_rng.randi() % alt_clips.size()]
	var ln := tape.clip_length(_held_clip)
	_held_t = fmod(Game.clock * _speed / maxf(ln, 0.01), 1.0) if ln > 0.0 else 0.0
	if _held_clip != _clip:
		_held_t = _rng.randf_range(0.2, 0.7)
	tape.hold(_held_clip, _held_t)
	tear = 1.0


## Puts everything exactly at the rig (no lag), e.g. when it first appears.
func snap() -> void:
	_tape_xf = global_transform
	tape.global_transform = _tape_xf
	var ln := tape.clip_length(_clip)
	tape.hold(_clip, fmod(Game.clock * _speed / maxf(ln, 0.01), 1.0) if ln > 0.0 else 0.3)
	_ghost_t = 0.0


func hold_all(clip: String, t01: float) -> void:
	_clip = clip
	for o in [tape, eye, shade_body]:
		(o as Occupant).hold(clip, t01)


func _process(delta: float) -> void:
	if not visible:
		return
	_skip_t -= delta
	if _skip_t <= 0.0:
		_skip_t = _rng.randf_range(skip_gap.x, skip_gap.y)
		skip_now()
	tear = maxf(tear - delta * 5.0, 0.0)
	_ghost_t = maxf(_ghost_t - delta, 0.0)
	ghost.visible = show_tape and _ghost_t > 0.0
	tape.visible = show_tape
	eye.visible = show_eye
	tape.shade(1.0, tear, 1.0)
	ghost.shade(1.0, 0.6, clampf(_ghost_t / 0.32, 0.0, 1.0) * 0.7)
	eye.shade(0.0, 0.0, 1.0, presence)
	shade_body.shade(0.0, 0.0, 1.0)


## Papered in the space's paper (matters for the strips left on the hole).
func set_paper(tint: Vector3, sat: float) -> void:
	for o in [tape, ghost, shade_body]:
		(o as Occupant).set_paper(tint, sat)
