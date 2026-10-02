class_name AutoplayBot
extends PlayerInput
## Plays like a curious, nervous person: walks to places that look interesting, glances
## around and up at the lights, stops to check behind, sprints down long corridors, sneaks
## into dark rooms, hides crouched in corners, and films with the camcorder.
## Driven by the run seed, so a seed reproduces the same playthrough.

enum Mode { WALK, PAUSE, HIDE, SEAM }

var space: Space
var rng: RandomNumberGenerator
var mode: int = Mode.WALK
var path := PackedVector3Array()
var path_i := 0
var recent: Array = []
var target_name := ""

var _mode_left := 0.0
var _sneak := false
var _sprint_left := 0.0
var _sprint_cool := 6.0
var _cam_left := 0.0
var _cam_cool := 5.0
var _glance_left := 0.0
var _glance_cool := 2.0
var _glance_yaw := 0.0
var _glance_pitch := 0.0
var _plan: Array = []   # PAUSE/HIDE look plan: [yaw_offset, pitch, hold]
var _plan_left := 0.0
var _plan_base_yaw := 0.0
var _want_yaw := 0.0
var _want_pitch := -0.04
var _yaw_v := 0.0
var _pitch_v := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _started := false
var _heading := Vector3.FORWARD
var _visited := {}         # chunk (Vector2i) -> seconds spent there
var _seams_done := {}      # seam interest names already gone through
var _seam: Dictionary = {}  # the seam being visited: look, seam, pocket (world)
var _seam_step := 0
var _seam_t := 0.0
var _heading_t := 0.0
var _relook_t := 0.0
var _seam_looked_up := {}
var _long_t := 0.0


func _init() -> void:
	rng = Game.rng("bot")
	var h := rng.randf() * TAU
	_heading = Vector3(sin(h), 0.0, cos(h))


static func yaw_of(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _pick_target(player: Player) -> void:
	var pts := space.get_interest_points()
	var best := {}
	var best_score := -1.0
	for p in pts:
		if p["name"] in recent:
			continue
		var d: float = player.global_position.distance_to(p["pos"])
		if d < 3.0:
			continue
		var score := rng.randf() * (0.5 + minf(d, 18.0) / 18.0)
		# In an endless level, keep a loose direction of travel so the walk actually goes
		# somewhere instead of circling the start, and prefer places not seen yet.
		if space.has_method("get_focus_shots"):
			var to: Vector3 = (p["pos"] - player.global_position).normalized()
			score *= 1.0 + 1.2 * maxf(0.0, to.dot(_heading))
			if to.dot(_heading) < -0.3:
				score *= 0.35
			var pc := Vector2i(floori(p["pos"].x / 24.0), floori(p["pos"].z / 24.0))
			if not _visited.has(pc):
				score *= 2.4
			# A long hall running the way you are going is hard to resist.
			if String(p["name"]).contains("hall_") and to.dot(_heading) > 0.8:
				score *= 1.4
			if String(p["name"]).contains("_room_"):
				score *= 1.4
			# Something that only shows on tape: a person who has learned that would go and look.
			if p.has("seam") and not _seams_done.has(p["name"]) and d < 22.0:
				score *= 25.0
			if String(p["name"]).contains("_tall_") and not _seam_looked_up.has(p["name"]) and d < 24.0:
				score *= 8.0
			# Inside a corridor that keeps repeating, a person keeps walking on for a while.
			if space.has_method("loop_dir") and space.loop_dir() != 0:
				if absf(p["pos"].z - player.global_position.z) > 3.0:
					score *= 0.05
				elif to.x * space.loop_dir() > 0.7:
					score *= 4.0
		if score > best_score:
			best_score = score
			best = p
	if best.is_empty():
		recent.clear()
		return
	target_name = best["name"]
	if Game.opts.has("log-bot"):
		print("[bot] t=%.1f target %s d=%.1f" % [Game.clock, target_name, player.global_position.distance_to(best["pos"])])
	recent.append(target_name)
	if recent.size() > 12:
		recent.pop_front()
	_seam = {}
	if best.has("seam") and not _seams_done.has(target_name):
		_seam = {"name": target_name, "look": best["pos"], "seam": best["seam"], "pocket": best["pocket"]}
	var goal: Vector3 = best["pos"] + (Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)) if _seam.is_empty() else Vector3.ZERO)
	path = space.find_path(player.global_position, goal)
	path_i = 1 if path.size() > 1 else 0
	_sneak = rng.randf() < 0.12 or target_name.contains("dark")


## The world moved us (a loop repeat): carry the plan along.
func shift(offset: Vector3) -> void:
	for i in path.size():
		path[i] += offset
	_last_pos += offset


## A yaw near `base + offset` that looks down open space instead of into a wall.
func _open_yaw(player: Player, base: float, spread: float, min_depth: float) -> float:
	var best := base
	var best_score := -1.0
	for k in 10:
		var y := base + rng.randf_range(-spread, spread)
		var d := space.view_depth(player.global_position, y)
		var score := minf(d, 14.0) + rng.randf() * 3.0
		if d >= min_depth and score > best_score:
			best_score = score
			best = y
	if best_score < 0.0:
		var d_best := -1.0
		for k in 12:
			var y2 := base + TAU * k / 12.0
			var d2 := space.view_depth(player.global_position, y2)
			if d2 > d_best:
				d_best = d2
				best = y2
	return best


func _start_pause(player: Player, hide := false) -> void:
	mode = Mode.HIDE if hide else Mode.PAUSE
	_plan.clear()
	_plan_base_yaw = 0.0
	if hide:
		var out := _open_yaw(player, player.yaw + PI, PI, 6.0)
		_plan.append([out, -0.06, rng.randf_range(2.5, 4.0)])
		_plan.append([out + rng.randf_range(-0.5, 0.5), -0.04, rng.randf_range(2.0, 3.5)])
		_cam_left = maxf(_cam_left, rng.randf_range(3.0, 6.0))
	else:
		var n := rng.randi_range(2, 4)
		var y := player.yaw
		for k in n:
			y = _open_yaw(player, y, 2.4, 4.0)
			var p := rng.randf_range(-0.1, 0.04)
			if rng.randf() < 0.15:
				p = rng.randf_range(0.12, 0.28)   # look up at the lights
			_plan.append([y, p, rng.randf_range(1.0, 2.4)])
		if rng.randf() < 0.45:
			_plan.append([_open_yaw(player, player.yaw + PI, 0.8, 3.0), -0.02, rng.randf_range(1.2, 2.0)])   # check behind
	_plan_left = 0.0


func update_move(player: Node, delta: float) -> void:
	var pl := player as Player
	if not _started:
		_started = true
		_last_pos = pl.global_position
		if space.has_method("get_focus_shots"):
			# In the endless level, set off the way we are facing.
			_heading = Basis(Vector3.UP, pl.yaw) * Vector3.FORWARD
		_want_yaw = pl.yaw
		_mode_left = rng.randf_range(1.5, 3.0)
		mode = Mode.PAUSE
		_plan = [[pl.yaw, 0.0, 1.0], [pl.yaw + rng.randf_range(-0.6, 0.6), 0.1, 1.2], [pl.yaw, -0.03, 0.8]]
		_plan_base_yaw = 0.0
	move = Vector2.ZERO
	sprint = false
	crouch = false
	var here := Vector2i(floori(pl.global_position.x / 24.0), floori(pl.global_position.z / 24.0))
	_visited[here] = float(_visited.get(here, 0.0)) + delta
	# Every so often, or after lingering in one chunk, set off in a new direction (never straight back).
	_heading_t += delta
	if _heading_t > 45.0 or float(_visited[here]) > 40.0 and _heading_t > 15.0:
		_heading_t = 0.0
		var best_h := _heading
		var best_s := -1.0
		for k in 8:
			var a := TAU * k / 8.0
			var hd := Vector3(sin(a), 0.0, cos(a))
			if hd.dot(_heading) < -0.5:
				continue
			var dep := space.view_depth(pl.global_position, yaw_of(hd), 30.0)
			var ahead := Vector2i(floori((pl.global_position.x + hd.x * 30.0) / 24.0), floori((pl.global_position.z + hd.z * 30.0) / 24.0))
			var sc := dep * rng.randf_range(0.6, 1.0) * (1.8 if not _visited.has(ahead) else 1.0)
			if sc > best_s:
				best_s = sc
				best_h = hd
		_heading = best_h

	if mode == Mode.SEAM:
		_update_seam(pl, delta)
		return

	_cam_cool -= delta
	if _cam_left > 0.0:
		_cam_left -= delta
		if _cam_left <= 0.0:
			_cam_cool = rng.randf_range(6.0, 16.0)
	elif _cam_cool <= 0.0 and rng.randf() < delta * 0.4:
		_cam_left = rng.randf_range(4.0, 9.0)
	camcorder = _cam_left > 0.0 and not Game.opts.has("nocam")

	# Something only the tape shows: keep looking, lower the camera, raise it again (does it move?).
	if space.attention_until > Game.clock and space.attention_kind == &"tape" and mode != Mode.HIDE:
		var tt := space.attention_point - pl.global_position
		_want_yaw = yaw_of(Vector3(tt.x, 0.0, tt.z))
		_want_pitch = clampf(atan2(tt.y - 1.6, Vector2(tt.x, tt.z).length()) * 0.5, -0.1, 0.2)
		_relook_t += delta
		var cyc := fmod(_relook_t, 4.6)
		camcorder = cyc < 3.2 and not Game.opts.has("nocam")
		_sprint_left = 0.0
		mode = Mode.WALK
		path = PackedVector3Array()
		return
	_relook_t = 0.0
	# Something happened (lights dying): stop and stare at it, like anyone would.
	if space.attention_until > Game.clock and mode != Mode.HIDE:
		var to := space.attention_point - pl.global_position
		_want_yaw = yaw_of(Vector3(to.x, 0.0, to.z))
		_want_pitch = clampf(atan2(to.y - 1.6, Vector2(to.x, to.z).length()) * 0.5, -0.1, 0.2)
		_sprint_left = 0.0
		if _cam_cool <= 0.0 and _cam_left <= 0.0:
			_cam_left = rng.randf_range(3.0, 5.0)
		camcorder = _cam_left > 0.0 and not Game.opts.has("nocam")
		mode = Mode.WALK
		path = PackedVector3Array()
		return

	if mode == Mode.PAUSE or mode == Mode.HIDE:
		crouch = mode == Mode.HIDE
		_plan_left -= delta
		if _plan_left <= 0.0:
			if _plan.is_empty():
				mode = Mode.WALK
				path = PackedVector3Array()
			else:
				var step: Array = _plan.pop_front()
				_want_yaw = _plan_base_yaw + float(step[0])
				_want_pitch = float(step[1])
				_plan_left = float(step[2])
		return

	# WALK
	if path.is_empty() or path_i >= path.size():
		if not _seam.is_empty() and pl.global_position.distance_to(_seam["look"]) < 1.2:
			mode = Mode.SEAM
			_seam_step = 0
			_seam_t = 0.0
			return
		var r := rng.randf()
		if target_name.contains("_tall_") and not _seam_looked_up.has(target_name):
			# A room far too tall: stop and look up at it, and film it.
			_seam_looked_up[target_name] = true
			_start_pause(pl)
			_plan = [[pl.yaw, 0.5, 2.6], [pl.yaw + 1.1, 0.42, 2.0], [pl.yaw - 0.9, 0.55, 2.2], [pl.yaw, 0.0, 1.0]]
			_cam_left = maxf(_cam_left, 4.0)
			return
		if r < 0.16:
			_start_pause(pl)
			return
		elif r < 0.21:
			_start_pause(pl, true)
			return
		_pick_target(pl)
		if path.is_empty():
			return
	var pos := pl.global_position
	var wp := path[path_i]
	var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	if to.length() < 0.45:
		path_i += 1
		if path_i >= path.size():
			return
		wp = path[path_i]
		to = Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	var dir := to.normalized()
	var local := Basis(Vector3.UP, -pl.yaw) * dir
	move = Vector2(local.x, -local.z)
	# Ease off when the target direction is far from where we look (people turn, then walk).
	var off := absf(angle_difference(pl.yaw, yaw_of(dir)))
	move *= clampf(1.25 - off, 0.25, 1.0)

	# A long view ahead: someone who knows what shows on tape lifts the camera to look.
	_long_t -= delta
	if _long_t <= 0.0:
		_long_t = 1.0
		if _cam_left <= 0.0 and _cam_cool <= 0.0 and space.view_depth(pos, pl.yaw, 30.0) >= 22.0 and rng.randf() < 0.6:
			_cam_left = rng.randf_range(4.5, 7.0)

	_sprint_cool -= delta
	if _sprint_left > 0.0:
		_sprint_left -= delta
		sprint = true
	elif _sprint_cool <= 0.0 and to.length() > 5.0 and not _sneak and rng.randf() < delta * 0.5:
		_sprint_left = rng.randf_range(1.5, 3.5)
		_sprint_cool = rng.randf_range(8.0, 18.0)
	crouch = _sneak

	# Look ahead along the path, with occasional glances.
	var ahead := _point_ahead(pos, 2.8)
	var look_dir := Vector3(ahead.x - pos.x, 0.0, ahead.z - pos.z)
	if look_dir.length() > 0.05:
		_want_yaw = yaw_of(look_dir)
	_want_pitch = -0.03
	_glance_cool -= delta
	if _glance_left > 0.0:
		_glance_left -= delta
		_want_yaw += _glance_yaw
		_want_pitch = _glance_pitch
	elif _glance_cool <= 0.0 and rng.randf() < delta * 0.6:
		_glance_left = rng.randf_range(0.6, 1.6)
		_glance_cool = rng.randf_range(2.0, 5.0)
		_glance_yaw = angle_difference(_want_yaw, _open_yaw(pl, _want_yaw, 1.2, 3.5))
		_glance_pitch = rng.randf_range(0.12, 0.26) if rng.randf() < 0.15 else rng.randf_range(-0.1, 0.03)

	# Unstick.
	_stuck_t += delta
	if _stuck_t > 1.5:
		if pos.distance_to(_last_pos) < 0.15 and move.length() > 0.2:
			path = PackedVector3Array()
		_stuck_t = 0.0
		_last_pos = pos


## Going through a seam the way a player who knows the trick would: look at the wall, raise the
## camcorder, see the opening, walk through it filming, look around inside, walk back out.
func _update_seam(pl: Player, delta: float) -> void:
	_seam_t += delta
	var seam: Vector3 = _seam["seam"]
	var pocket: Vector3 = _seam["pocket"]
	match _seam_step:
		0:   # look at the wall, then raise the camera
			var to := seam - pl.global_position
			_want_yaw = yaw_of(Vector3(to.x, 0.0, to.z))
			_want_pitch = 0.02
			camcorder = _seam_t > 0.9 and not Game.opts.has("nocam")
			if _seam_t > 3.0:
				path = space.find_path(pl.global_position, pocket)
				path_i = 1 if path.size() > 1 else 0
				_seam_step = 1
				_seam_t = 0.0
		1, 3:   # walk through, filming
			camcorder = not Game.opts.has("nocam")
			if path.is_empty() or path_i >= path.size() or _seam_t > 12.0:
				_seam_step += 1
				_seam_t = 0.0
				if _seam_step == 4:
					_seams_done[_seam["name"]] = true
					_seam = {}
					mode = Mode.WALK
					path = PackedVector3Array()
				return
			_follow(pl)
		2:   # inside: look around, lower the camera (the eye sees a sealed room), raise it again
			var k := int(_seam_t / 1.6)
			_want_yaw = pl.yaw + (0.9 if k % 2 == 0 else -0.9) * delta
			_want_pitch = -0.05
			camcorder = (_seam_t < 2.5 or _seam_t > 4.5) and not Game.opts.has("nocam")
			if _seam_t > 6.5:
				path = space.find_path(pl.global_position, _seam["look"])
				path_i = 1 if path.size() > 1 else 0
				_seam_step = 3
				_seam_t = 0.0


## Steps along the current path (shared by the walk and the seam visit).
func _follow(pl: Player) -> void:
	var pos := pl.global_position
	if path_i >= path.size():
		return
	var wp := path[path_i]
	var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	if to.length() < 0.35:
		path_i += 1
		if path_i >= path.size():
			return
		wp = path[path_i]
		to = Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	var dir := to.normalized()
	var local := Basis(Vector3.UP, -pl.yaw) * dir
	move = Vector2(local.x, -local.z) * clampf(1.25 - absf(angle_difference(pl.yaw, yaw_of(dir))), 0.25, 1.0) * 0.8
	var ahead := _point_ahead(pos, 1.6)
	var ld := Vector3(ahead.x - pos.x, 0.0, ahead.z - pos.z)
	if ld.length() > 0.05:
		_want_yaw = yaw_of(ld)
	_want_pitch = -0.02


## A point about `dist` meters further along the current path.
func _point_ahead(pos: Vector3, dist: float) -> Vector3:
	var prev := pos
	var left := dist
	var k := path_i
	while k < path.size():
		var seg := Vector3(path[k].x - prev.x, 0.0, path[k].z - prev.z)
		var l := seg.length()
		if l >= left:
			return prev + seg.normalized() * left
		left -= l
		prev = Vector3(path[k].x, 0.0, path[k].z)
		k += 1
	return prev


func update_look(player: Node, delta: float) -> void:
	var pl := player as Player
	if not _started:
		look_delta = Vector2.ZERO
		return
	# Critically damped spring toward the wanted view, like a head that settles.
	var w := 3.2 if mode == Mode.WALK else 2.4
	var dy := angle_difference(pl.yaw, _want_yaw)
	var acc_y := w * w * dy - 2.0 * w * _yaw_v
	_yaw_v += acc_y * delta
	_yaw_v = clampf(_yaw_v, -2.6, 2.6)
	var dp := _want_pitch - pl.pitch
	var acc_p := w * w * dp - 2.0 * w * _pitch_v
	_pitch_v += acc_p * delta
	var t := Game.clock
	var jitter := Vector2(sin(t * 1.7) * 0.0006 + sin(t * 4.3) * 0.0003, sin(t * 1.3 + 2.0) * 0.0005)
	look_delta = Vector2(-_yaw_v * delta, _pitch_v * delta) + jitter
