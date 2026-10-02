class_name AutoplayBot
extends PlayerInput
## Plays like a curious, nervous person: walks to places that look interesting, glances
## around and up at the lights, stops to check behind, sprints down long corridors, sneaks
## into dark rooms, hides crouched in corners, and films with the camcorder.
## Driven by the run seed, so a seed reproduces the same playthrough.

enum Mode { WALK, PAUSE, HIDE }

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
		# somewhere instead of circling the start.
		if space.has_method("get_focus_shots"):
			var to: Vector3 = (p["pos"] - player.global_position).normalized()
			score *= 1.0 + 0.9 * maxf(0.0, to.dot(_heading))
			# A long hall running the way you are going is hard to resist.
			if String(p["name"]).contains("hall_") and to.dot(_heading) > 0.8:
				score *= 2.2
		if score > best_score:
			best_score = score
			best = p
	if best.is_empty():
		recent.clear()
		return
	target_name = best["name"]
	recent.append(target_name)
	if recent.size() > 5:
		recent.pop_front()
	var goal: Vector3 = best["pos"] + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
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

	_cam_cool -= delta
	if _cam_left > 0.0:
		_cam_left -= delta
		if _cam_left <= 0.0:
			_cam_cool = rng.randf_range(6.0, 16.0)
	elif _cam_cool <= 0.0 and rng.randf() < delta * 0.4:
		_cam_left = rng.randf_range(4.0, 9.0)
	camcorder = _cam_left > 0.0 and not Game.opts.has("nocam")

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
		var r := rng.randf()
		if r < 0.28:
			_start_pause(pl)
			return
		elif r < 0.38:
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
