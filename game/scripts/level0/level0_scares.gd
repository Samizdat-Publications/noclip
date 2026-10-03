class_name Level0Scares
extends Node3D
## Scripted scares that are not the hunt (Stewart, S06: "seeing a hazmat suit guy dead on the floor
## and as you approach he gets dragged off screen by something").
## The dragged body: once a run, early (before the Occupant first comes, as a warning of what it
## does), a Halden technician lies on his back on the carpet ahead of you, under a light, his
## camcorder beside him. Stop and look at him, film him, or walk up to him, and he is pulled away
## feet first, fast, by nothing you can see, round a corner or through a doorway out of your sight. A
## thump somewhere behind the wall, the hum falls away, a wet streak on the carpet, his camcorder
## left blinking where he lay. Go round the corner: nothing.

const FIRST := Vector2(24.0, 44.0)     # seconds into a run it may first be set up
const DRAG_LEN := 6.5

var space: Level0World
var player: Player
var log_events := false
var drags := 0
var _rng: RandomNumberGenerator
var _next := 30.0
var _state := 0                         # 0 waiting, 1 lying there, 2 being dragged, 3 over
var _body: HaldenBody
var _s := Vector3.ZERO                  # where his feet are (the drag starts here)
var _d := Vector3.FORWARD               # the way he is dragged
var _e := Vector3.ZERO                  # out of sight
var _t := 0.0
var _seen := 0.0
var _beat := -1.0
var _snd: AudioStreamPlayer3D
var _thud: AudioStreamPlayer3D
var _left: Array = []                   # what he left: [node, blinking light or null]
var _spare: HaldenBody                  # loaded at the start


func _ready() -> void:
	_rng = Game.rng("scares")
	log_events = Game.opts.has("log-scare")
	_next = float(Game.opts.get("drag_at", str(_rng.randf_range(FIRST.x, FIRST.y))))
	if Game.opts.has("no_scares") or not HaldenBody.available():
		_next = 1e9
	_snd = _player3d(2.0, 30.0)
	_thud = _player3d(3.0, 40.0)
	# Loaded now, at the loading moment, not mid-run (critique 026: a 133 ms hitch).
	if _next < 1e8:
		_spare = HaldenBody.new()
		add_child(_spare)
		_spare.visible = false
		_spare.position = Vector3(0, -200, 0)


func _player3d(unit: float, maxd: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"World"
	p.unit_size = unit
	p.max_distance = maxd
	p.top_level = true
	add_child(p)
	return p


func _log(m: String) -> void:
	if log_events:
		print("[scare] t=%.1f %s" % [Game.clock, m])


func _process(delta: float) -> void:
	for it in _left:
		if it[1]:
			(it[1] as OmniLight3D).light_energy = 0.35 if fmod(Game.clock + 0.3, 1.0) < 0.55 else 0.0
	if player == null or player.caught:
		return
	match _state:
		0:
			if Game.clock < _next:
				return
			# Not while it is after you (following you is fine: it is the one that takes him).
			var hunting := space.hunter and space.hunter.state in [OccupantHunter.S.NOTICE, OccupantHunter.S.CHASE, OccupantHunter.S.KILL]
			if hunting or (space.tape and space.tape.state != TapeEvents.S.IDLE) or space.current_room != null:
				_next = Game.clock + 3.0
				return
			_tries += 1
			if not _try_place(_tries > 8):
				_next = Game.clock + 1.5
		1:
			_lying(delta)
		2:
			_dragging(delta)


# ------------------------------------------------------------------ placing him

func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _walk_line(a: Vector3, dir: Vector3, from: float, to: float) -> bool:
	var s := from
	while s <= to:
		if not space.is_walkable(a + dir * s):
			return false
		s += 0.25
	return true


var _tries := 0


## A lit spot ahead in view, and a way out of sight from it along the floor (through a doorway,
## round a corner) within a few meters. After a few tries with nothing found, any spot will do
## (`loose`: no light needed).
func _try_place(loose: bool = false) -> bool:
	var cam := player.cam
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var base := Vector3(eye.x, player.global_position.y, eye.z)
	var why := {}
	for dist in [8.0, 9.0, 7.0, 10.0, 11.5, 13.0]:
		for ang in [0.0, 10.0, -10.0, 20.0, -20.0, 28.0, -28.0]:
			var s: Vector3 = base + fwd.rotated(Vector3.UP, deg_to_rad(ang)) * dist
			if not space.is_walkable(s):
				why["wall"] = int(why.get("wall", 0)) + 1
				continue
			if not loose and space.fixture_near(s, 3.4) == null:
				why["dark"] = int(why.get("dark", 0)) + 1
				continue
			if not _clear(eye, s + Vector3(0, 0.3, 0)):
				why["unseen"] = int(why.get("unseen", 0)) + 1
				continue
			# Somewhere out of sight a few meters away, reached along the floor.
			var k0 := _rng.randi() % 12
			for kk in 12:
				var a := TAU * float((k0 + kk) % 12) / 12.0
				for r in [4.0, 5.5, 7.0]:
					var x: Vector3 = s + Vector3(cos(a), 0.0, sin(a)) * r
					if not space.is_walkable(x) or _clear(eye, x + Vector3(0, 0.3, 0)) or _clear(eye, x + Vector3(0, 1.0, 0)):
						continue
					var path := space.find_path(s, x)
					if path.size() < 2:
						continue
					var plen := 0.0
					for i in path.size() - 1:
						plen += path[i].distance_to(path[i + 1])
					if plen > r * 1.9 + 1.5:
						why["long_way"] = int(why.get("long_way", 0)) + 1
						continue
					var d := Vector3(path[1].x - s.x, 0.0, path[1].z - s.z)
					if d.length() < 0.3 and path.size() > 2:
						d = Vector3(path[2].x - s.x, 0.0, path[2].z - s.z)
					if d.length() < 0.3:
						continue
					d = d.normalized()
					if d.dot(fwd) < -0.3:
						continue
					# room for him (head 1.8 m back from his feet), all of him in plain view
					if not _walk_line(s, -d, 0.0, 1.9):
						why["room"] = int(why.get("room", 0)) + 1
						continue
					if not _clear(eye, s - d * 0.9 + Vector3(0, 0.25, 0)) or not _clear(eye, s - d * 1.7 + Vector3(0, 0.25, 0)):
						why["half_hidden"] = int(why.get("half_hidden", 0)) + 1
						continue
					path[0] = s
					# and on past the last point, so he is pulled well out of sight
					var tail := Vector3(path[path.size() - 1].x - path[path.size() - 2].x, 0.0, path[path.size() - 1].z - path[path.size() - 2].z)
					if tail.length() > 0.01 and space.is_walkable(path[path.size() - 1] + tail.normalized() * 2.0):
						path.append(path[path.size() - 1] + tail.normalized() * 2.0)
					_drag_path = path
					_place(s, d, x)
					return true
	_log("no spot yet %s" % why)
	return false


var _drag_path := PackedVector3Array()


## The point `dist` meters along the drag path, and the path's direction there.
func _along(dist: float) -> Array:
	var p := _drag_path
	var left := dist
	for i in p.size() - 1:
		var seg := Vector3(p[i + 1].x - p[i].x, 0.0, p[i + 1].z - p[i].z)
		var l := seg.length()
		if l > 0.001 and left <= l:
			return [Vector3(p[i].x, _s.y, p[i].z) + seg / l * left, seg / l]
		left -= l
	var last := p[p.size() - 1]
	var dir := _d
	if p.size() >= 2:
		var lseg := Vector3(last.x - p[p.size() - 2].x, 0.0, last.z - p[p.size() - 2].z)
		if lseg.length() > 0.01:
			dir = lseg.normalized()
	return [Vector3(last.x, _s.y, last.z) + dir * left, dir]


func _place(s: Vector3, d: Vector3, e: Vector3) -> void:
	_s = s
	_d = d
	_e = e
	if _spare:
		_body = _spare
		_spare = null
		_body.visible = true
	else:
		_body = HaldenBody.new()
		add_child(_body)
	_body.global_position = s
	_body.hold("death", 1.0)
	if _body.arms:
		_body.arms.mode = "side"
	_state = 1
	_seen = 0.0
	_beat = -1.0
	_t = 0.0
	# Line him up once the pose is on him: feet at s, head back along -d.
	await get_tree().process_frame
	if _body == null:
		return
	var feet := (_body.bone_world("LeftFoot") + _body.bone_world("RightFoot")) * 0.5
	var head := _body.bone_world("Head")
	var v := feet - head
	v.y = 0.0
	if v.length() > 0.2:
		var yaw := atan2(v.x, v.z)
		var want := atan2(d.x, d.z)
		_body.global_rotate(Vector3.UP, want - yaw)
	await get_tree().process_frame
	if _body == null:
		return
	feet = (_body.bone_world("LeftFoot") + _body.bone_world("RightFoot")) * 0.5
	_body.global_position += Vector3(s.x - feet.x, 0.0, s.z - feet.z)
	# A soft shadow under him, so he lies on the carpet and not over it (critique 026); it goes with him.
	var ct := "res://assets/textures/level0/decal_contact.png"
	if ResourceLoader.exists(ct) and _body.get_node_or_null("contact") == null:
		var dc := Decal.new()
		dc.name = "contact"
		dc.texture_albedo = load(ct)
		dc.size = Vector3(0.95, 0.5, 2.1)
		dc.modulate = Color(1, 1, 1, 0.95)
		_body.add_child(dc)
	var cdec := _body.get_node_or_null("contact") as Decal
	if cdec:
		var mid := s - d * 0.9
		cdec.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP), Vector3(mid.x, s.y, mid.z))
	# His camcorder, still recording, dropped by his hand.
	var side := d.cross(Vector3.UP).normalized()
	_drop("res://assets/props/player/camcorder_v3.glb", s - d * 0.5 + side * 0.7, true, Vector3(PI * 0.5, _rng.randf() * TAU, 0.0))
	_drop("res://assets/props/level0/prop_tape_crate.glb", s - d * 1.0 - side * 1.05, false, Vector3(0.0, _rng.randf() * TAU, 0.0))
	_log("a body at %s, dragged toward %s (%s)" % [s, e, d])


func _drop(path: String, p: Vector3, blink: bool, rot: Vector3) -> void:
	if not ResourceLoader.exists(path) or not space.is_walkable(p):
		return
	var root := Node3D.new()
	add_child(root)
	var m := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(m)
	root.global_position = Vector3(p.x, p.y + (0.06 if blink else 0.0), p.z)
	m.rotation = rot
	var lt: OmniLight3D = null
	if blink:
		lt = OmniLight3D.new()
		lt.light_color = Color(1.0, 0.1, 0.06)
		lt.omni_range = 0.55
		lt.position = Vector3(0, 0.1, 0)
		root.add_child(lt)
	_left.append([root, lt])


# ------------------------------------------------------------------ him

func _off_center(p: Vector3) -> float:
	var cam := player.cam
	var to := (p - cam.global_position).normalized()
	return rad_to_deg(acos(clampf((-cam.global_transform.basis.z).dot(to), -1.0, 1.0)))


func _lying(delta: float) -> void:
	_t += delta
	var mid := _s - _d * 0.9 + Vector3(0, 0.25, 0)
	var dd := Vector2(player.global_position.x - _s.x, player.global_position.z - _s.z).length()
	var vis := _clear(player.cam.global_position, mid)
	var looked := _off_center(mid) < 20.0 and vis
	if looked and dd < 14.0:
		_seen += delta
	# Anyone with a body in plain view stops and stares at it (the bot does too).
	if vis and dd < 15.0 and _off_center(mid) < 45.0:
		space.attention_point = mid
		space.attention_until = Game.clock + 0.4
		space.attention_kind = &"scare"
	if _beat < 0.0:
		var filming := player.camcorder.settled() and looked
		if dd < 4.8 or _seen > 5.0 or (filming and _seen > 2.2):
			_beat = 0.35
			_log("he is about to go (dist %.1f, seen %.1f, filming %s)" % [dd, _seen, filming])
	else:
		_beat -= delta
		if _beat <= 0.0:
			_start_drag()
	# Never seen and you are long gone: he was never there.
	if _beat < 0.0 and (dd > 34.0 or _t > 40.0) and not looked:
		_spare = _body
		_spare.visible = false
		_body = null
		for it in _left:
			(it[0] as Node3D).queue_free()
		_left.clear()
		_state = 0
		_next = Game.clock + 25.0
		_log("set aside unseen")


func _start_drag() -> void:
	_state = 2
	if _body.arms:
		_body.arms.mode = "trail"
	_t = 0.0
	drags += 1
	_play(_snd, "res://assets/audio/entity/body_drag_%02d.wav" % (1 + _rng.randi() % 2), 2.0, _s)
	var fx := space.fixture_near(_s, 3.0)
	if fx:
		fx.stutter()
	Game.fear = maxf(Game.fear, 0.8)
	_log("dragged")


func _dragging(delta: float) -> void:
	_t += delta
	# A jerk, then pulled away hard, faster and faster, feet first along the floor.
	var s := 0.0
	if _t < 0.12:
		s = 0.12 * sin(_t / 0.12 * PI * 0.5)
	else:
		var u := _t - 0.12
		s = 0.12 + 0.6 * u + 7.5 * u * u
	var at := _along(s)
	var p: Vector3 = at[0]
	var dir: Vector3 = at[1]
	# Turn him to follow the way he is pulled (about the feet).
	var feet := (_body.bone_world("LeftFoot") + _body.bone_world("RightFoot")) * 0.5
	var head := _body.bone_world("Head")
	var v := feet - head
	v.y = 0.0
	if v.length() > 0.2:
		var turn := angle_difference(atan2(v.x, v.z), atan2(dir.x, dir.z))
		var piv := Vector3(feet.x, _body.global_position.y, feet.z)
		var xf := _body.global_transform
		xf.origin -= piv
		xf = Transform3D(Basis(Vector3.UP, turn * minf(1.0, delta * 9.0)), Vector3.ZERO) * xf
		xf.origin += piv
		_body.global_transform = xf
	feet = (_body.bone_world("LeftFoot") + _body.bone_world("RightFoot")) * 0.5
	_body.global_position += Vector3(p.x - feet.x, 0.0, p.z - feet.z)
	_body.global_position.y = _s.y + absf(sin(_t * 23.0)) * 0.015
	_snd.global_position = _body.global_position + Vector3(0, 0.2, 0)
	space.attention_point = _body.global_position + Vector3(0, 0.3, 0)
	space.attention_until = Game.clock + 2.5
	space.attention_kind = &"scare"
	if _t > 0.9 and _thud.get_meta("done", false) == false:
		_thud.set_meta("done", true)
		_play(_thud, "res://assets/audio/entity/body_thud_01.wav", 0.0, _e + dir * 2.0)
		if space.director:
			space.director.hunt_shock(_e)
	if _t > 1.8:
		_body.queue_free()
		_body = null
		_wet_streak()
		_state = 3
		space.attention_point = _e + Vector3(0, 0.6, 0)
		space.attention_until = Game.clock + 3.0
		space.attention_kind = &"scare"
		# Now it knows someone else is here.
		if space.hunter:
			space.hunter.soon(30.0)
		_log("gone round the corner")


func _play(p: AudioStreamPlayer3D, path: String, db: float, at: Vector3) -> void:
	if not ResourceLoader.exists(path):
		return
	p.stream = load(path)
	p.volume_db = db
	p.global_position = at
	p.play()


## A dark wet streak on the carpet where he went, along each leg of the way he was pulled.
func _wet_streak() -> void:
	var tex := "res://assets/textures/level0/decal_floor_wetpatch.png"
	if not ResourceLoader.exists(tex):
		return
	var pts := PackedVector3Array([_s - _d * 1.0])
	for q in _drag_path:
		pts.append(q)
	for i in pts.size() - 1:
		var a := Vector3(pts[i].x, _s.y, pts[i].z)
		var b := Vector3(pts[i + 1].x, _s.y, pts[i + 1].z)
		var ln := a.distance_to(b)
		if ln < 0.2:
			continue
		var dc := Decal.new()
		dc.texture_albedo = load(tex)
		dc.size = Vector3(0.5, 0.5, ln + 0.3)
		dc.modulate = Color(0.35, 0.3, 0.22, 0.85)
		dc.albedo_mix = 0.8
		add_child(dc)
		dc.global_transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) * 0.5)
		_left.append([dc, null])
