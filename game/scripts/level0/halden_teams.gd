class_name HaldenTeams
extends Node3D
## Halden field teams in the levels (Stewart, S07; VISION "Halden Duplicating", L204). Two scenes:
## - The last stand: ahead of you, two technicians are holding the thing that hunts off with road
##   flares in a red-lit stretch of corridor; one films it, one has a hand up. Radio, muffled shouts.
##   When you come close enough to see, the flares die one after another, it takes one of them and
##   drags him away screaming, and the other backs off into the dark. A burning flare is left on the
##   carpet. Then it knows you are there too.
## - The help (once Halden knows you, standing >= 3): during a chase a technician steps out ahead,
##   fires a flare between you and it, and is gone.
## Once per run each, at most.

enum S { IDLE, STAND, FALL, GONE }

var space: Level0World
var player: Player
var state := S.IDLE
var _rng: RandomNumberGenerator
var _techs: Array[HaldenBody] = []
var _flares: Array = []
var _at := Vector3.ZERO
var _face := Vector3.ZERO
var _t := 0.0
var _next := 1e9
var _helped := false
var _radio: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _radio_t := 1.0
var log_events := false


func _ready() -> void:
	_rng = Game.rng("halden:teams:%d" % Game.depth)
	log_events = Game.opts.has("log-halden") or Game.opts.has("log-hunt")
	_radio = _p3d(2.0, 30.0)
	_voice = _p3d(3.0, 40.0)
	reset_run()


func _p3d(unit: float, maxd: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"World"
	p.unit_size = unit
	p.max_distance = maxd
	p.top_level = true
	add_child(p)
	return p


func _log(m: String) -> void:
	if log_events:
		print("[halden] t=%.1f %s" % [Game.clock, m])


## A new run or a new depth: the last stand comes a while in (sooner deeper down).
func reset_run() -> void:
	_clear()
	state = S.IDLE
	_helped = false
	if Game.opts.has("no_halden") or not HaldenBody.available():
		_next = 1e9
		return
	_next = Game.clock + float(Game.opts.get("halden_at", str(_rng.randf_range(40.0, 75.0))))


func _clear() -> void:
	for t in _techs:
		if is_instance_valid(t):
			t.queue_free()
	_techs.clear()
	_flares.clear()


func _snd(p: AudioStreamPlayer3D, name: String, db: float, at: Vector3) -> void:
	var path := "res://assets/audio/halden/%s.wav" % name
	if not ResourceLoader.exists(path):
		return
	p.stream = load(path)
	p.volume_db = db
	p.global_position = at
	p.play()


func _process(delta: float) -> void:
	if player == null or space == null or player.caught:
		return
	_t += delta
	match state:
		S.IDLE:
			if Game.clock >= _next and _can_stage():
				_stage()
		S.STAND:
			_stand(delta)
		S.FALL:
			_fall(delta)
	_help_check()


func _can_stage() -> bool:
	var h := space.hunter
	if h and h.state != OccupantHunter.S.ABSENT:
		return false
	if space.current_room or space.in_pocket(player.global_position):
		return false
	return true


## Somewhere 14 to 24 m ahead along open floor, out of sight round a turn if possible.
func _stage() -> void:
	var fwd := -player.cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var best := Vector3.INF
	for k in 16:
		var ang := deg_to_rad(_rng.randf_range(-70.0, 70.0))
		var d := _rng.randf_range(14.0, 24.0)
		var p := player.global_position + fwd.rotated(Vector3.UP, ang) * d
		if not space.is_walkable(p):
			continue
		var path := space.find_path(player.global_position, p)
		if path.is_empty():
			continue
		var side := fwd.cross(Vector3.UP)
		if not (space.is_walkable(p + side * 0.8) and space.is_walkable(p - side * 0.8)):
			continue
		best = p
		break
	if best == Vector3.INF:
		_next = Game.clock + 6.0
		return
	_at = Vector3(best.x, player.global_position.y, best.z)
	_face = (player.global_position - _at)
	_face.y = 0.0
	_face = _face.normalized()
	var side := _face.cross(Vector3.UP)
	# Two technicians back to back-ish, looking away from you, into the dark it is in.
	for k in 2:
		var t := HaldenBody.new()
		add_child(t)
		t.global_position = _at + side * (0.55 if k == 0 else -0.55) + _face * (0.2 * k)
		var look := -_face
		t.rotation.y = atan2(look.x, look.z)
		t.play("film" if k == 0 else "warn", 1.0)
		_techs.append(t)
	# Their flares, a ring in front of them (between them and it).
	for k in 3:
		var fl := Flare.new()
		space.add_child(fl)
		var fp := _at - _face * (1.6 + 0.4 * k) + side * (k - 1) * 0.9
		fl.throw_from(fp + Vector3(0, 0.05, 0), fp)
		fl.life_override = _rng.randf_range(10.0, 14.0) + k * 1.5
		space.flares.append(fl)
		_flares.append(fl)
	# It is there, at the edge of their red light.
	if space.hunter:
		space.hunter.stage_req = {"at": _at - _face * 6.4, "face_to": _at, "clip": "lunge", "t": 0.2, "eyes": false, "look": 0.6}
	state = S.STAND
	_t = 0.0
	_log("a last stand at %s (%.1f m ahead)" % [_at, player.global_position.distance_to(_at)])


func _stand(delta: float) -> void:
	_radio_t -= delta
	if _radio_t <= 0.0:
		_radio_t = _rng.randf_range(2.5, 5.0)
		_snd(_radio, "radio_0%d" % (1 + _rng.randi() % 3), -4.0, _at + Vector3(0, 1.4, 0))
		if _rng.randf() < 0.5:
			_snd(_voice, "shout_muffled_0%d" % (1 + _rng.randi() % 2), -2.0, _at + Vector3(0, 1.6, 0))
	# It falls apart once you are close enough to see it, or after a while anyway.
	var d := player.global_position.distance_to(_at)
	var sees := d < 13.0 and _sees(_at + Vector3(0, 1.2, 0))
	if sees or _t > 20.0:
		state = S.FALL
		_t = 0.0
		for i in _flares.size():
			var fl = _flares[i]
			if is_instance_valid(fl) and not (fl as Flare).out:
				(fl as Flare).life_override = minf((fl as Flare).life_override, (fl as Flare).age() + 0.8 + i * 0.9)
		_log("the flares are dying (you are %.1f m away)" % d)


func _sees(p: Vector3) -> bool:
	var to := p - player.cam.global_position
	var fwd := -player.cam.global_transform.basis.z
	if fwd.dot(to.normalized()) < cos(deg_to_rad(40.0)):
		return false
	var q := PhysicsRayQueryParameters3D.create(player.cam.global_position, p)
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _fall(delta: float) -> void:
	var h := space.hunter
	var taken: HaldenBody = _techs[0] if _techs.size() > 0 else null
	var other: HaldenBody = _techs[1] if _techs.size() > 1 else null
	if _t < 3.2:
		return
	if _t - delta < 3.2:
		# The last flare is out: it comes in and takes the one with the camera.
		if h:
			h.stage_req = {"at": _at - _face * 1.2, "face_to": _at, "clip": "grab", "t": 0.3, "look": 0.0}
		if taken:
			taken.play("death", 1.4)
		if other:
			other.play("backaway", 1.2)
		_snd(_voice, "scream_drag_01", 4.0, _at + Vector3(0, 1.0, 0))
		_log("it took one of them")
	# Dragged off, away from you, fast; the other backs into the dark.
	var k := clampf((_t - 3.6) / 2.4, 0.0, 1.0)
	if taken and _t > 3.6:
		taken.global_position = _at.lerp(_at - _face * 9.0, k * k)
		if h:
			h.stage_req["at"] = taken.global_position - _face * 1.0
	if other and _t > 3.4:
		other.global_position += _face.rotated(Vector3.UP, 1.2) * delta * 0.9
	if _t > 6.5:
		_clear()
		if h:
			h.stage_req = {}
			h.rig.visible = false
			h.soon(8.0)
		state = S.GONE
		_log("the scene is over; it knows you are here")


## Halden knows you: during a chase, once a run, someone steps out and fires a flare between you.
func _help_check() -> void:
	if _helped or Game.progress.standing < 3 or space.hunter == null:
		return
	var h := space.hunter
	if h.state != OccupantHunter.S.CHASE or h._st < 2.0:
		return
	var d := h.global_position.distance_to(player.global_position)
	if d > 9.0 or d < 2.5:
		return
	_helped = true
	var mid := (h.global_position + player.global_position) * 0.5
	var fl := Flare.new()
	space.add_child(fl)
	var side := (player.global_position - h.global_position).cross(Vector3.UP).normalized()
	var from := player.global_position + side * 2.5 + Vector3(0, 1.4, 0)
	fl.throw_from(from, Vector3(mid.x, player.global_position.y, mid.z))
	space.flares.append(fl)
	_snd(_voice, "flare_gun_pop", 2.0, from)
	_log("a technician fired a flare between you and it")
