class_name CrawlerRig
extends OccupantRig
## The hunt's body when the Crawler hunts (D052). Two copies of one body: by eye a solid, lit, heavy
## thing that crawls smoothly and throws a real shadow; on tape the same body that never moves
## smoothly, held a frame at a time and jumping on (the frame skips the critics liked), with a
## fading after-image of the pose it jumped from. It squeezes narrower through doorways. The hunt
## drives it through OccupantRig's interface (set_clip, hold_all, presence, tear, skip_gap...).

var c_eye: Crawler
var c_tape: Crawler
var c_ghost: Crawler
var _last := Vector3.INF
var _v := 0.0
var _probe_t := 0.0
var _want_w := 1.0
var _cl := ""


func _ready() -> void:
	_rng = Game.rng("crawler:rig")
	c_eye = _mk(TapeEvents.LAYER_EYE, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	c_tape = _mk(TapeEvents.LAYER_TAPE, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	c_tape.top_level = true
	c_ghost = _mk(TapeEvents.LAYER_TAPE, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	c_ghost.top_level = true
	c_ghost.visible = false
	_tape_xf = global_transform


func _mk(layers: int, shadow: int) -> Crawler:
	var c := Crawler.new()
	add_child(c)
	c.set_layers(layers)
	c.set_shadows(shadow)
	return c


func set_clip(clip: String, speed: float = 1.0) -> void:
	if clip == _cl:
		return
	_cl = clip
	_clip = clip
	_speed = speed
	c_eye.play(clip, speed)


func skip_now() -> void:
	var prev := c_tape.held()
	c_ghost.global_transform = _tape_xf
	c_ghost.set_width(c_tape.width)
	if String(prev[0]) != "":
		c_ghost.hold(String(prev[0]), float(prev[1]))
	_ghost_t = 0.3
	_tape_xf = global_transform
	c_tape.global_transform = _tape_xf
	c_tape.set_width(c_eye.width)
	var held_clip := _cl
	var t := c_eye.phase()
	if not alt_clips.is_empty() and _rng.randf() < 0.35:
		held_clip = alt_clips[_rng.randi() % alt_clips.size()]
		t = _rng.randf_range(0.2, 0.7)
	c_tape.hold(held_clip, t)
	tear = 1.0


func snap() -> void:
	_tape_xf = global_transform
	c_tape.global_transform = _tape_xf
	c_tape.hold(_cl if _cl != "" else "walk", c_eye.phase())
	_ghost_t = 0.0
	_last = global_position


func hold_all(clip: String, t01: float) -> void:
	_cl = clip
	_clip = clip
	for c in [c_eye, c_tape]:
		(c as Crawler).hold(clip, t01)


func set_paper(_tint: Vector3, _sat: float) -> void:
	pass


## Its eyes open (the last moment of a catch).
func open_eyes(on: bool) -> void:
	c_eye.open_eyes(on)
	c_tape.open_eyes(on)


## Lifts its face toward a point (the lens), w 0..1; w 0 lets the clip have the head back.
func look_at_point(p: Vector3, w: float) -> void:
	for c in [c_eye, c_tape, c_ghost]:
		(c as Crawler).look_at_point(p, w)


func head_position() -> Vector3:
	return c_eye.head_position()


func _process(delta: float) -> void:
	if not visible:
		_last = Vector3.INF
		return
	# The crawl keeps pace with the body: no sliding hands.
	if _last != Vector3.INF and delta > 0.0:
		var step := Vector2(global_position.x - _last.x, global_position.z - _last.z).length()
		_v = lerpf(_v, step / delta, 1.0 - exp(-6.0 * delta))
	_last = global_position
	if c_eye.anim and c_eye.anim.speed_scale != 0.0 and _cl in ["walk", "run"]:
		c_eye.set_speed(clampf(_v / Crawler.STRIDE, 0.25, 3.6) if _v > 0.05 else 0.25)
	# Too big for the corridor: it squeezes, narrower and lower, where the walls close in.
	_probe_t -= delta
	if _probe_t <= 0.0 and is_inside_tree():
		_probe_t = 0.15
		_want_w = _clearance()
	c_eye.set_width(move_toward(c_eye.width, _want_w, delta * 1.6))
	_skip_t -= delta
	if _skip_t <= 0.0:
		_skip_t = _rng.randf_range(skip_gap.x, skip_gap.y)
		skip_now()
	tear = maxf(tear - delta * 5.0, 0.0)
	_ghost_t = maxf(_ghost_t - delta, 0.0)
	c_ghost.visible = show_tape and _ghost_t > 0.0
	c_tape.visible = show_tape
	c_eye.visible = show_eye


func _clearance() -> float:
	var space := get_world_3d().direct_space_state
	var o := global_position + Vector3(0, 1.0, 0)
	var side := global_basis.x.normalized()
	var tot := 0.0
	for s in [-1.0, 1.0]:
		var q := PhysicsRayQueryParameters3D.create(o, o + side * s * 1.4)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		tot += o.distance_to(hit["position"]) if not hit.is_empty() else 1.4
	return clampf(tot / 2.4, 0.45, 1.0)
