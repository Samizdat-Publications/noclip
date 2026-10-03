class_name Watchers
extends Node3D
## Being watched (VISION; Stewart, S04: "always being watched but can barely make out the
## character"). A layer of almost-sightings that runs all the time, separate from any attack. Both
## use the Occupant (the building's copy of a person, made of its own wallpaper):
## - The door hung high on the wall of a tall room opens a crack while you are not looking, and
##   something papered like the walls leans out round its edge. Look at it and it keeps looking.
##   Look away, and the next time you look it is shut.
## - A figure that is only ever at the edge of your sight: it stands to one side, fades as you turn
##   toward it and is gone before it reaches the middle of the screen. Only the naked eye sees it.
## Rules (VISION): never a clear look, never twice the same way in a row, rarer early on.

const EDGE_FIRST := 22.0
const EDGE_GAP := [55.0, 30.0]        # seconds between edge figures, early and late in a run
const EDGE_FADE := [24.0, 37.0]       # degrees off center: gone at the first, whole at the second
const DOOR_UNSEEN := 2.2              # seconds out of view before the door opens
const DOOR_ANGLE := 40.0              # degrees the door stands open (a 21 degree crack is edge-on from the floor)

var space: Level0World
var player: Player
var doors: Array = []                 # {"pivot", "frame" (world), "w", "dh", "chunk", "used_at"}
var _rng: RandomNumberGenerator
var _peek: Occupant
var _edge: Occupant
var _last := ""
var _next_edge := EDGE_FIRST
var _edge_on := false
var _edge_t := 0.0
var _edge_gone_t := 0.0
var _door: Dictionary = {}
var _door_state := 0                  # 0 shut, 1 open (watching), 2 closing
var _door_ang := 0.0
var _unseen := 0.0
var _seen := 0.0
var _away := 0.0
var _shut_snd: AudioStreamPlayer3D
var log_events := false
var stage_edge_pending := false      # a focus shot wants a figure at the edge as soon as the camera is set
var _stage_wait := 0


func _ready() -> void:
	_rng = Game.rng("watchers")
	log_events = Game.opts.has("log-watch")
	if Game.opts.has("watch_now"):
		_next_edge = 4.0
	if not Occupant.available() or Game.opts.has("no_watchers"):
		set_process(false)
		return
	_peek = Occupant.new()
	_peek.set_layers(1)
	_peek.set_shadows(false)
	_peek.visible = false
	_peek.mat.set_shader_parameter("use_clip", true)
	_peek.mat.set_shader_parameter("gap", 0.22)
	add_child(_peek)
	_edge = Occupant.new()
	_edge.set_layers(TapeEvents.LAYER_EYE)   # only the naked eye sees it
	_edge.set_shadows(false)
	_edge.visible = false
	add_child(_edge)
	_shut_snd = AudioStreamPlayer3D.new()
	_shut_snd.bus = &"World"
	_shut_snd.unit_size = 2.0
	_shut_snd.max_distance = 24.0
	var p := "res://assets/audio/level0/door_distant_01.wav"
	if ResourceLoader.exists(p):
		_shut_snd.stream = load(p)
	add_child(_shut_snd)


## A chunk with watch doors was built (Level0Chunk.watch_doors).
func add_chunk(ch: Level0Chunk) -> void:
	for d in ch.watch_doors:
		var e: Dictionary = d.duplicate()
		e["chunk"] = ch
		e["frame"] = ch.global_transform * (d["frame"] as Transform3D)
		e["used_at"] = -999.0
		doors.append(e)


func remove_chunk(ch: Level0Chunk) -> void:
	if not _door.is_empty() and _door["chunk"] == ch:
		_shut(false)
	doors = doors.filter(func(e): return e["chunk"] != ch)


func _process(delta: float) -> void:
	if player == null or player.cam == null:
		return
	if Game.opts.has("occ_test"):
		# Look-dev: the Occupant standing 3.5 m in front of the camera, whole and lit.
		var cam := player.cam
		var f := -cam.global_transform.basis.z
		f.y = 0.0
		var pos := cam.global_position + f.normalized() * 3.5
		pos.y = player.global_position.y
		_edge.global_position = pos
		_edge.look_at(Vector3(cam.global_position.x, pos.y, cam.global_position.z), Vector3.UP, true)
		_edge.set_layers(1)
		if not _edge.visible:
			_edge.hold(String(Game.opts.get("occ_clip", "idle")), float(Game.opts.get("occ_t", "0.3")))
		_edge.visible = true
		_edge.shade(float(Game.opts.get("occ_tape", "0")), 0.0, 1.0)
		return
	_peek.shade(0.0, 0.0, 1.0)
	_update_door(delta)
	_update_edge(delta)


# ------------------------------------------------------------------ helpers

## Degrees between where the camera looks and the direction to p.
func _off_center(p: Vector3) -> float:
	var cam := player.cam
	var fwd := -cam.global_transform.basis.z
	var to := (p - cam.global_position).normalized()
	return rad_to_deg(acos(clampf(fwd.dot(to), -1.0, 1.0)))


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ------------------------------------------------------------------ the high door

func _update_door(delta: float) -> void:
	var eye := player.cam.global_position
	if _door_state == 0:
		if _last == "door" and Game.clock - float(_door.get("used_at", -999.0)) < 40.0:
			return
		# The nearest unused watch door you are near, below and inside its room.
		var best: Dictionary = {}
		var bd := 13.0
		for d in doors:
			if Game.clock - float(d["used_at"]) < 90.0:
				continue
			var fr: Transform3D = d["frame"]
			var flat := Vector2(eye.x - fr.origin.x, eye.z - fr.origin.z)
			if flat.length() < bd and fr.basis.z.dot(eye - fr.origin) > 0.5:
				bd = flat.length()
				best = d
		if best.is_empty():
			_unseen = 0.0
			return
		var c: Vector3 = (best["frame"] as Transform3D) * Vector3(0, float(best["dh"]) * 0.6, 0)
		if _off_center(c) > 52.0 or Game.opts.has("watch_door_now"):
			_unseen += delta
		else:
			_unseen = 0.0
		if _unseen > DOOR_UNSEEN:
			_open(best)
		return
	var fr2: Transform3D = _door["frame"]
	var c2 := fr2 * Vector3(0, float(_door["dh"]) * 0.6, 0)
	var looking := _off_center(c2) < 34.0 and _clear_line(eye, c2 + fr2.basis.z * 0.3)
	if _door_state == 1:
		if looking:
			_seen += delta
			_away = 0.0
			Game.fear = maxf(Game.fear, 0.4)
		else:
			_away += delta
		# Seen, then looked away from: it is shut by the time you look back. Never seen: it waits
		# a while, then shuts on its own (out of view).
		if (_seen > 0.4 and _away > 0.5) or (_seen == 0.0 and _away > 14.0) or Vector2(eye.x - fr2.origin.x, eye.z - fr2.origin.z).length() > 20.0:
			_shut(true)
		_door_ang = move_toward(_door_ang, DOOR_ANGLE, delta * 40.0)
		_pose_door()


func _open(d: Dictionary) -> void:
	_door = d
	_door_state = 1
	_door_ang = 0.0
	_seen = 0.0
	_away = 0.0
	d["used_at"] = Game.clock
	_last = "door"
	# Something leans out round the free edge: its head just past the wall, the rest of it clipped
	# away inside the wall (it is too tall for the door; it stoops).
	var fr: Transform3D = d["frame"]
	var w: float = d["w"]
	var head := fr * Vector3(w * 0.5 - 0.11, float(d["dh"]) * 0.74, 0.05)
	var to_room := fr.basis.z
	var face := Basis.looking_at(to_room, Vector3.UP, true)
	# leaning forward out of the doorway: the body stays back inside the wall, the head comes out
	var tilt := Basis(face.x, deg_to_rad(16.0)) * face
	_peek.global_transform = Transform3D(tilt, Vector3.ZERO)
	_peek.hold("look", _rng.randf_range(0.3, 0.6))
	_peek.visible = true
	# Shift so the head lands at the edge of the door (after the pose has been applied).
	await get_tree().process_frame
	if _door_state != 1:
		return
	_peek.global_position += head - _peek.head_position()
	_peek.mat.set_shader_parameter("clip_xform", Projection(fr.affine_inverse()))
	# only the free edge's half of the opening, upper part: a head and a shoulder, never the body
	_peek.mat.set_shader_parameter("clip_box", Vector4(0.0, w * 0.5, float(d["dh"]) * 0.5, float(d["dh"])))
	if log_events:
		print("[watch] door opened at t=%.1f pos=%s head_want=%s head_now=%s occ=%s skel=%s anim=%s" % [Game.clock, fr.origin, head, _peek.head_position(), _peek.global_position, _peek.skel != null, _peek.anim.current_animation if _peek.anim else "none"])


func _pose_door() -> void:
	if _door.is_empty():
		return
	var pv: Node3D = _door["pivot"]
	if is_instance_valid(pv):
		if not _door.has("base"):
			_door["base"] = pv.transform.basis
		pv.transform.basis = (_door["base"] as Basis) * Basis(Vector3.UP, deg_to_rad(_door_ang) * float(_door.get("swing", 1.0)))


func _shut(sound: bool) -> void:
	if log_events:
		print("[watch] door shut at t=%.1f seen=%.1f" % [Game.clock, _seen])
	_door_ang = 0.0
	_pose_door()
	_peek.visible = false
	if sound and _shut_snd.stream and not _door.is_empty():
		_shut_snd.global_position = (_door["frame"] as Transform3D).origin + Vector3(0, 1.0, 0)
		_shut_snd.volume_db = -18.0
		_shut_snd.pitch_scale = 0.8
		_shut_snd.play()
	_door_state = 0
	_unseen = 0.0


## Debug and focus shots: open the nearest watch door at once.
func stage_door(near: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1e9
	for d in doors:
		var dd := (d["frame"] as Transform3D).origin.distance_to(near)
		if dd < bd:
			bd = dd
			best = d
	if best.is_empty():
		return {}
	best["used_at"] = -999.0
	_open(best)
	_door_ang = DOOR_ANGLE
	_pose_door()
	return best


# ------------------------------------------------------------------ the edge of sight

func _update_edge(delta: float) -> void:
	if stage_edge_pending:
		_stage_wait += 1
		if _stage_wait > 6:     # let the camera arrive at the shot first
			stage_edge_pending = not _try_edge()
			if not stage_edge_pending:
				_last = "edge"
				_stage_wait = 0
	if _edge_on:
		var hp := _edge.global_position + Vector3(0, 1.9, 0)
		var off := _off_center(hp)
		var fade := smoothstep(EDGE_FADE[0], EDGE_FADE[1], off)
		_edge.shade(0.0, 0.0, fade)
		_edge_t += delta
		if off < EDGE_FADE[0] + 2.0:
			_edge_gone_t += delta
		# Turned toward it: gone. Stood there long enough: gone while you are not looking.
		if _edge_gone_t > 0.12 or (_edge_t > 7.0 and off > 60.0) or _edge_t > 14.0:
			_edge_on = false
			_edge.visible = false
			if log_events:
				print("[watch] edge figure gone at t=%.1f off=%.0f" % [Game.clock, off])
		return
	if Game.clock < _next_edge or player.camcorder.active:
		return
	if space.tape and space.tape.state != TapeEvents.S.IDLE:
		return
	if _last == "edge" and not doors.is_empty() and Game.clock - _next_edge < 20.0:
		_next_edge = Game.clock + 10.0
		return
	var late := clampf(Game.clock / 600.0, 0.0, 1.0)
	if _try_edge():
		_last = "edge"
		_next_edge = Game.clock + lerpf(EDGE_GAP[0], EDGE_GAP[1], late) * _rng.randf_range(0.8, 1.3)
	else:
		_next_edge = Game.clock + 2.0


## Places the figure off to one side, at the edge of the frame, where a long clear line runs.
func _try_edge(force_yaw: float = INF) -> bool:
	var cam := player.cam
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var first := 1.0 if _rng.randf() < 0.5 else -1.0
	for side in [first, -first]:
		for ang in [44.0, 40.0, 47.0, 38.0]:
			var dir: Vector3 = fwd.rotated(Vector3.UP, deg_to_rad(ang) * side)
			for dist in [9.0, 12.0, 7.5, 15.0, 6.0, 18.0]:
				var p: Vector3 = Vector3(eye.x, 0.0, eye.z) + dir * dist
				if not space.is_walkable(p):
					continue
				if not _clear_line(eye, p + Vector3(0, 1.6, 0)):
					continue
				_show_edge(p, eye)
				return true
	return false


func _show_edge(p: Vector3, eye: Vector3) -> void:
	_edge.global_position = p
	var t := Vector3(eye.x, p.y, eye.z)
	_edge.look_at(t, Vector3.UP, true)
	var clips := ["idle", "look", "twitch"]
	_edge.hold(clips[_rng.randi() % clips.size()], _rng.randf_range(0.2, 0.8))
	_edge.visible = true
	_edge.shade(0.0, 0.0, 1.0)
	_edge_on = true
	_edge_t = 0.0
	_edge_gone_t = 0.0
	if log_events:
		print("[watch] edge figure at t=%.1f pos=%s" % [Game.clock, p])


## Focus shots: put the figure at the edge of the frame right now.
func stage_edge() -> bool:
	return _try_edge()
