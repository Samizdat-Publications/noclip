class_name Rearranger
extends Node
## Unobserved rearrangement (VISION non-euclidean toolkit; critique 009, L052, D025): things you
## have already looked at change while you are not looking. A chair you passed turns to face
## where you are now; a camcorder the survey crew left recording has turned to point at you.
## Never while it could be seen: it must be outside the camera's view, or hidden behind a wall
## (checked with a ray), for several seconds, and it is checked again at the moment it changes. Rare: at most one change every 25 s and six a run.

const CHECK := 0.25
const UNSEEN_FOR := 6.0
const COOLDOWN := 25.0
const MAX_CHANGES := 6

var space: Level0World
var player: Player
var _t := 0.0
var _next_ok := 20.0
var _changes := 0
var _state := {}   # instance id -> {"seen": bool, "unseen_t": float, "moved": int}


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or player == null or space == null:
		return
	_t = CHECK
	var cam := player.cam
	var pp := player.global_position
	var candidate: Node3D = null
	for c in space.chunks.values():
		var ch := c as Level0Chunk
		if ch == null or ch.position.distance_to(Vector3(pp.x, 0, pp.z)) > 40.0:
			continue
		for m in ch.movables:
			if not is_instance_valid(m):
				continue
			var d := Vector2(m.global_position.x - pp.x, m.global_position.z - pp.z).length()
			if d > 16.0:
				continue
			var id := m.get_instance_id()
			var st: Dictionary = _state.get(id, {"seen": false, "unseen_t": 0.0, "moved": 0})
			if _visible(cam, m):
				if Game.opts.has("log-rearrange") and not st["seen"]:
					print("[rearrange] t=%.1f first saw chair at %s d=%.1f" % [Game.clock, m.global_position, d])
				st["seen"] = true
				st["unseen_t"] = 0.0
			else:
				st["unseen_t"] = float(st["unseen_t"]) + CHECK
			_state[id] = st
			if candidate == null and st["seen"] and float(st["unseen_t"]) >= UNSEEN_FOR and int(st["moved"]) == 0 and d > 3.5 and d < 14.0:
				candidate = m
	if candidate == null or Game.clock < _next_ok or _changes >= MAX_CHANGES:
		return
	if _visible(cam, candidate):
		return
	# Turn to face the player (model front is +Z).
	var to := Vector3(pp.x - candidate.global_position.x, 0.0, pp.z - candidate.global_position.z)
	candidate.rotation.y = atan2(to.x, to.z)
	_state[candidate.get_instance_id()]["moved"] = 1
	_changes += 1
	_next_ok = Game.clock + COOLDOWN
	if Game.opts.has("log-stream"):
		print("[rearrange] t=%.1f a chair at (%.1f, %.1f) turned to face the player" % [Game.clock, candidate.global_position.x, candidate.global_position.z])


func _visible(cam: Camera3D, m: Node3D) -> bool:
	var p := m.global_position + Vector3(0, 0.55, 0)
	if not cam.is_position_in_frustum(p):
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, p)
	q.exclude = [player.get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()
