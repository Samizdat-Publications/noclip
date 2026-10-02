class_name RouteInput
extends PlayerInput
## Debug walker for checking seams on video (`--route=east`): walks straight along a compass
## direction from the spawn, keeping to the middle of the hall, eyes level. `--route-back=SEC`
## turns around and looks back down the hall at that time (releases a loop).

var _yaw := 0.0
var _back_at := -1.0
var _started := false
var _lane_z := 0.0
var _cam: Array = []    # [[t0, t1], ...] when the camcorder is up (`--route-cam=2-6,8-12`)
var _stay := false


func _init() -> void:
	var r := String(Game.opts.get("route", "east"))
	_yaw = {"east": -PI * 0.5, "west": PI * 0.5, "north": 0.0, "south": PI}.get(r, -PI * 0.5)
	_back_at = float(Game.opts.get("route-back", "-1"))
	_stay = Game.opts.has("route-stay")
	for part in String(Game.opts.get("route-cam", "")).split(",", false):
		var ab := part.split("-")
		if ab.size() == 2:
			_cam.append([float(ab[0]), float(ab[1])])


func update_move(player: Node, _delta: float) -> void:
	var pl := player as Player
	var ns := absf(sin(_yaw)) < 0.5     # walking north or south: keep to a lane in x
	if not _started:
		_started = true
		_lane_z = pl.global_position.x if ns else pl.global_position.z
	move = Vector2(0.0, 1.0)
	sprint = Game.opts.has("route-sprint")
	# Stay in the lane we started in.
	if ns:
		var offx := pl.global_position.x - _lane_z
		move.x = clampf(offx * 0.8, -0.4, 0.4) * (1.0 if absf(_yaw) > 1.0 else -1.0)
	else:
		var off := pl.global_position.z - _lane_z
		move.x = clampf(off * 0.8, -0.4, 0.4) * (-1.0 if absf(_yaw + PI * 0.5) < 0.1 else 1.0)
	if (_back_at > 0.0 and Game.clock > _back_at) or _stay:
		move = Vector2.ZERO
	camcorder = false
	for iv in _cam:
		if Game.clock >= iv[0] and Game.clock < iv[1]:
			camcorder = true


func update_look(player: Node, delta: float) -> void:
	var pl := player as Player
	var want := _yaw
	if _back_at > 0.0 and Game.clock > _back_at:
		want = _yaw + PI
	var d := angle_difference(pl.yaw, want)
	look_delta = Vector2(-clampf(d, -2.0 * delta, 2.0 * delta), -pl.pitch * 0.1)
