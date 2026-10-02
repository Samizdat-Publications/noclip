class_name CaptureDirector
extends Node
## Review capture (only with --capture=DIR). While the bot plays, saves stills at seeded,
## spread-out moments and short bursts of 9 frames 0.4 s apart for motion sheets. After
## the bot run it can take a few hand-posed "focus" shots (--focus=FILE.json), then quits.
## Timing uses the game clock, so under Movie Maker every shot lands on an exact frame.

var dir := ""
var duration := 90.0
var player: Player
var shots: Array = []
var focus: Array = []
var _focus_i := -1
var _focus_wait := 0.0
var _log: Array = []
var _event_sheet := -1


func setup(p_dir: String, p_duration: float, p_player: Player) -> void:
	dir = p_dir
	duration = p_duration
	player = p_player
	DirAccess.make_dir_recursive_absolute(dir + "/stills")
	DirAccess.make_dir_recursive_absolute(dir + "/sheets")
	DirAccess.make_dir_recursive_absolute(dir + "/focus")
	var r := Game.rng("capture")
	var n_st := int(Game.opts.get("stills", "18"))
	var n_sh := int(Game.opts.get("sheets", "4"))
	# One motion sheet is held back and taken when something actually happens in the run
	# (like a player grabbing footage of the moment). Falls back to the end if nothing does.
	if n_sh > 1:
		n_sh -= 1
		_event_sheet = n_sh
	var t0 := 4.5
	var t1 := duration - 1.0
	for i in n_st:
		var seg := (t1 - t0) / n_st
		shots.append({"t": t0 + seg * (i + r.randf_range(0.15, 0.85)), "path": "%s/stills/s_%03d.png" % [dir, i]})
	for k in n_sh:
		var seg := (t1 - t0 - 4.0) / n_sh
		var ts := t0 + seg * (k + r.randf_range(0.1, 0.7))
		for f in 9:
			shots.append({"t": ts + f * 0.4, "path": "%s/sheets/k%02d_f%d.png" % [dir, k, f]})
	shots.sort_custom(func(a, b): return a["t"] < b["t"])
	if Game.focus_file == "auto" and player.space.has_method("get_focus_shots"):
		focus = player.space.get_focus_shots(int(Game.opts.get("focus_n", "8")))
	elif Game.focus_file != "" and FileAccess.file_exists(Game.focus_file):
		var data = JSON.parse_string(FileAccess.get_file_as_string(Game.focus_file))
		if data is Array:
			focus = data


func _process(_delta: float) -> void:
	if _event_sheet >= 0 and Game.clock > 3.0:
		var sp: Space = player.space
		# Prefer the moment something shows on tape; any other event will do later in the run.
		var on_tape := sp != null and sp.attention_until > Game.clock and sp.attention_kind == &"tape"
		var any_ev := sp != null and sp.attention_until > Game.clock and Game.clock > duration * 0.6
		var fire := on_tape or any_ev or Game.clock >= duration - 5.0
		if fire:
			for f in 9:
				shots.append({"t": Game.clock + 0.3 + f * 0.4, "path": "%s/sheets/k%02d_f%d.png" % [dir, _event_sheet, f]})
			shots.sort_custom(func(a, b): return a["t"] < b["t"])
			_event_sheet = -1
	while not shots.is_empty() and Game.clock >= float(shots[0]["t"]):
		var s: Dictionary = shots.pop_front()
		_save(s["path"])
	if _focus_i == -1 and Game.clock >= duration:
		_focus_i = 0
		_focus_wait = -1.0
	if _focus_i >= 0:
		_run_focus(_delta)


func _run_focus(delta: float) -> void:
	if _focus_i >= focus.size():
		_finish()
		return
	var f: Dictionary = focus[_focus_i]
	if _focus_wait < 0.0:
		var hold := FocusHold.new()
		hold.camcorder = bool(f.get("camcorder", false))
		player.input = hold
		var p: Array = f["pos"]
		if player.space.has_method("prepare_view"):
			player.space.prepare_view(Vector3(p[0], 0.0, p[1]))
		player.spawn(Transform3D(Basis(Vector3.UP, -deg_to_rad(float(f.get("yaw", 0.0)))), Vector3(p[0], 0.0, p[1])))
		player.pitch = deg_to_rad(float(f.get("pitch", 0.0)))
		_focus_wait = float(f.get("settle", 2.0))
		return
	_focus_wait -= delta
	if _focus_wait <= 0.0:
		_save("%s/focus/f_%02d.png" % [dir, _focus_i])
		_focus_i += 1
		_focus_wait = -1.0


func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	_log.append({"t": snappedf(Game.clock, 0.001), "frame": Game.frame, "render_frame": Game.frame - 1, "file": path.get_file(),
		"pos": [snappedf(player.global_position.x, 0.01), snappedf(player.global_position.z, 0.01)],
		"camcorder": player.camcorder.active})


func _finish() -> void:
	var f := FileAccess.open(dir + "/capture_log.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"seed": Game.run_seed, "duration": duration, "shots": _log}, "  "))
	f.close()
	set_process(false)
	get_tree().quit()


class FocusHold:
	extends PlayerInput
	func update_move(_p: Node, _d: float) -> void:
		move = Vector2.ZERO
	func update_look(_p: Node, _d: float) -> void:
		look_delta = Vector2.ZERO
