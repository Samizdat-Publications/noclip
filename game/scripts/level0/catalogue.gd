class_name Catalogue
extends Node
## The Catalogue (VISION "Progression", D049, S06): the first piece of what carries between runs.
## Everything distinct you film long enough (camcorder up and steady, the thing in the middle of the
## picture, close enough to make out, for a second) goes on this run's tape; the first time ever, it
## also goes on the shelf for good (saved in user://). The end-of-tape card lists what is on the tape
## and marks the new ones, with how much of the shelf is filled. Most of the shelf starts as blank
## labels, so you know there is more to find.

## Every Level 0 entry: id -> label. Order is the shelf's order.
const ENTRIES := {
	"crawler": "THE ONE TOO BIG FOR THE HALLS",
	"occupant": "THE ONE MADE OF WALLPAPER",
	"high_door": "THE DOOR HIGH ON THE WALL",
	"halden_body": "HALDEN TECHNICIAN, TAKEN",
	"seam": "A DOOR ONLY THE TAPE SEES",
	"storeroom_hall": "THE HALL UNDER THE STOREROOM",
	"hall_far_door": "THE WAY OUT IS THE WAY IN",
	"loop": "THE HALL THAT REPEATS",
	"tall_room": "A ROOM COPIED TOO TALL",
	"free_frame": "A DOOR WITH NO WALL",
	"floor_hole": "THE FLOOR BELOW, FROM ABOVE",
	"category": "THE IDEA OF A FILING CABINET",
	"tripod": "A CAMERA LEFT RECORDING",
	"crawl_hole": "A DOORWAY FOR SOMETHING SMALLER",
	"dropped_camera": "YOUR OWN CAMERA",
}
const MIN_FILM := 1.0
const PERIOD := 0.2

var space: Level0World
var player: Player
var tape: Array = []                 # ids filmed this run, in order
var new_ids := {}                    # ids that went on the shelf for the first time this run
var shelf := {}                      # id -> {"first": run number, "times": n}
var runs := 1
var _acc := {}                       # id -> seconds filmed (this run)
var _t := 0.0
var _path := ""


func _ready() -> void:
	_path = "user://catalogue_bot.json" if Game.autoplay else "user://catalogue.json"
	if Game.opts.has("fresh_catalogue"):
		_save()
	_load()


func _load() -> void:
	if not FileAccess.file_exists(_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if d is Dictionary:
		shelf = d.get("shelf", {})
		runs = int(d.get("runs", 0)) + 1


func _save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"shelf": shelf, "runs": runs}, "  "))
		f.close()


## A new tape (you woke at the start after dying): the shelf keeps everything.
func new_tape() -> void:
	tape.clear()
	new_ids.clear()
	_acc.clear()
	runs += 1
	_save()


func _process(delta: float) -> void:
	if player == null or space == null or player.caught:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = PERIOD
	if not player.camcorder.settled():
		return
	for tg in _targets():
		var id: String = tg[0]
		if tape.has(id):
			continue
		if _framed(tg[1], float(tg[2])):
			_acc[id] = float(_acc.get(id, 0.0)) + PERIOD
			if _acc[id] >= MIN_FILM:
				_add(id)


func _add(id: String) -> void:
	tape.append(id)
	if not shelf.has(id):
		shelf[id] = {"first": runs, "times": 0}
		new_ids[id] = true
	shelf[id]["times"] = int(shelf[id]["times"]) + 1
	_save()
	if Game.opts.has("log-catalogue") or Game.opts.has("log-hunt"):
		print("[catalogue] t=%.1f filmed %s%s" % [Game.clock, id, " (new)" if new_ids.has(id) else ""])


## In the middle of the picture, close enough, nothing in the way. Places you are standing in
## (dist < 0) count while you film inside them.
func _framed(p: Vector3, max_d: float) -> bool:
	if max_d < 0.0:
		return true
	var cam := player.cam
	var to := p - cam.global_position
	if to.length() > max_d:
		return false
	var off := rad_to_deg(acos(clampf((-cam.global_transform.basis.z).dot(to.normalized()), -1.0, 1.0)))
	if off > 24.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, p)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < 0.6


## What could be filmed right now: [id, world point, max distance (or -1: you are in it)].
func _targets() -> Array:
	var out := []
	if space.tape and space.tape.figure and space.tape.figure.visible:
		out.append(["occupant", space.tape.figure.global_position + Vector3(0, 1.5, 0), 30.0])
	if space.hunter and space.hunter.active():
		out.append(["crawler" if space.hunter.crawler else "occupant", space.hunter.global_position + Vector3(0, 1.2, 0), 25.0])
	if space.watchers and space.watchers._door_state == 1 and not space.watchers._door.is_empty():
		var fr: Transform3D = space.watchers._door["frame"]
		out.append(["high_door", fr * Vector3(0, float(space.watchers._door["dh"]) * 0.6, 0.2), 25.0])
	if space.scares and space.scares._body:
		out.append(["halden_body", space.scares._body.global_position + Vector3(0, 0.3, 0), 18.0])
	if space.current_room:
		out.append(["storeroom_hall", Vector3.ZERO, -1.0])
		var far: Portal = space.current_room.portal_far
		if far:
			out.append(["hall_far_door", far.global_position + Vector3(0, 1.1, 0), 14.0])
	if space.loop_dir() != 0 and space.loops_done_here > 0:
		out.append(["loop", Vector3.ZERO, -1.0])
	for d in space._dropped:
		out.append(["dropped_camera", (d[0] as Node3D).global_position, 8.0])
	var pc := Level0World.chunk_of(player.global_position)
	var here := player.global_position
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var ch: Level0Chunk = space.chunks.get(pc + Vector2i(dx, dz))
			if ch == null:
				continue
			var L := ch.L
			var o := ch.position
			for sm in L.get("seams", []):
				var w: Array = sm["wall"]
				out.append(["seam", o + Vector3((w[0] + w[2]) * 0.5, 1.1, (w[1] + w[3]) * 0.5), 12.0])
			for tr in L.get("tall_rooms", []):
				var r := Rect2(tr[0], tr[1], tr[2] - tr[0], tr[3] - tr[1])
				if r.has_point(Vector2(here.x - o.x, here.z - o.z)):
					out.append(["tall_room", Vector3.ZERO, -1.0])
			for ff in L.get("free_frames", []):
				out.append(["free_frame", o + Vector3(ff[0], 1.0, ff[1]), 14.0])
			for fh in L.get("floor_holes", []):
				out.append(["floor_hole", o + Vector3((fh[0] + fh[2]) * 0.5, 0.0, (fh[1] + fh[3]) * 0.5), 9.0])
			for pr in L.get("props", []):
				var nm := String(pr[0])
				if nm.begins_with("cat:"):
					out.append(["category", o + Vector3(pr[1], 0.6, pr[2]), 10.0])
				elif nm == "prop_tripod_camcorder":
					out.append(["tripod", o + Vector3(pr[1], 1.2, pr[2]), 14.0])
			for hl in L.get("holes", []):
				if hl.size() >= 4:
					out.append(["crawl_hole", o + Vector3((hl[0] + hl[2]) * 0.5, 0.35, (hl[1] + hl[3]) * 0.5), 10.0])
	return out


## The tape label at the end of a tape: what is on it, the new ones marked, the shelf count.
func tape_label() -> String:
	var lines := []
	if tape.is_empty():
		lines.append("NOTHING WORTH KEEPING")
	for id in tape:
		lines.append("%s%s" % [ENTRIES.get(id, id), "   NEW" if new_ids.has(id) else ""])
	var known := 0
	for id in ENTRIES:
		if shelf.has(id):
			known += 1
	lines.append("")
	lines.append("ON THE SHELF  %d / %d" % [known, ENTRIES.size()])
	return "\n".join(lines)
