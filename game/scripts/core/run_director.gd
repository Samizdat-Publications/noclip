class_name RunDirector
extends CanvasLayer
## The run loop (VISION "Progression: The Descent", D050). A run starts at the Landing, Halden's post
## at the start of depth 1. You go down by the stairwell in each depth. It ends when you are caught
## (Halden drags you back up and pays for the damaged tape) or when you ride a lift cage back up
## (paid in full). Salvage buys kit at the Landing's locker; the Landing's lift takes you straight down
## to any depth you have reached. This node owns the screens for all of it: the long walk down, the
## appraisal, the locker and the lift.

const STAIR_TIME := 5.5

var world: Level0World
var player: Player
var kit: Kit
var start_depth := 1
var max_depth := 1
var meters := 0.0            # salvage-weighted meters walked this run
var _last_pos := Vector3.INF
var _busy := false           # a transition is playing
var _black: ColorRect
var _card: Label
var _prompt: Label
var _menu: Label
var _menu_kind := ""         # "", "kit", "lift"
var _menu_i := 0
var _menu_items: Array = []
var _saved_input: PlayerInput
var _snd: AudioStreamPlayer
var _loop: AudioStreamPlayer
var landing: Landing


func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	var font := Kit.vhs_font()
	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_card = _label(font, 34, Color(0.92, 0.9, 0.84))
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_card)
	_prompt = _label(font, 24, Color(0.95, 0.93, 0.86, 0.9))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-300, -170)
	_prompt.size = Vector2(600, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt)
	_menu = _label(font, 26, Color(0.93, 0.91, 0.85))
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_menu)
	for c in [_card, _prompt, _menu]:
		(c as Label).visible = false
	_snd = AudioStreamPlayer.new()
	_snd.bus = &"Master"
	add_child(_snd)
	_loop = AudioStreamPlayer.new()
	_loop.bus = &"Master"
	add_child(_loop)


func _label(font: Font, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func attach(w: Level0World, p: Player) -> void:
	world = w
	player = p
	kit = Kit.new()
	kit.name = "kit"
	add_child(kit)
	kit.attach(p, w)
	w.run = self
	landing = w.landing
	new_run(Game.depth)


## A new run starts where you woke.
func new_run(depth: int) -> void:
	start_depth = depth
	max_depth = depth
	meters = 0.0
	_last_pos = Vector3.INF
	Game.appraisal = ""
	if kit:
		kit.refill()
	_log("new run at depth %d (salvage %d, deepest %d, kit %s)" % [depth, Game.progress.salvage, Game.progress.deepest, Game.progress.kit])


func _log(msg: String) -> void:
	if Game.opts.has("log-run") or Game.opts.has("log-hunt"):
		print("[run] t=%.1f %s" % [Game.clock, msg])


func _sfx(nm: String, db: float, folder := "descent") -> void:
	var p := "res://assets/audio/%s/%s.wav" % [folder, nm]
	if ResourceLoader.exists(p):
		_snd.stream = load(p)
		_snd.volume_db = db
		_snd.play()


func _loop_play(nm: String, db: float) -> void:
	var p := "res://assets/audio/descent/%s.wav" % nm
	if not ResourceLoader.exists(p):
		return
	var s := (load(p) as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(s.get_length() * s.mix_rate)
	_loop.stream = s
	_loop.volume_db = db
	_loop.play()


func _process(delta: float) -> void:
	if world == null or player == null:
		return
	# Meters walked, worth more the deeper you are.
	if not _busy and not player.caught:
		var p := player.global_position
		if _last_pos != Vector3.INF:
			var step := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
			if step < 2.0:
				meters += step * float(Depths.get_row(Game.depth).get("salvage_m", 0.25))
		_last_pos = p
	if _busy:
		return
	# Builder checks: --descend_at=S goes down the stairs at S seconds (and every S seconds after).
	if Game.opts.has("descend_at") and Game.clock > float(Game.opts["descend_at"]) * (Game.depth - start_depth + 1):
		descend()
		return
	if _menu_kind != "":
		_menu_input()
		return
	var what := _near_interactable()
	_prompt.visible = what != ""
	match what:
		"locker":
			_prompt.text = "E   HALDEN LOCKER   (SALVAGE %d)" % Game.progress.salvage
		"lift_down":
			_prompt.text = "E   RIDE THE LIFT DOWN"
		"lift_up":
			_prompt.text = "E   RIDE THE LIFT UP   (KEEP ALL %d SALVAGE)" % appraise(false)[0]
	if what != "" and Input.is_action_just_pressed("interact") and not Game.autoplay:
		match what:
			"locker":
				_open_menu("kit")
			"lift_down":
				_open_menu("lift")
			"lift_up":
				bank()
	var posed := Game.is_capture() and Game.clock > Game.duration   # the capture's posed shots after the run
	if world.stairwell and not posed and world.stairwell.contains(player.global_position) and not player.caught:
		descend()


func _near_interactable() -> String:
	if landing == null or not is_instance_valid(landing) or player.caught:
		return ""
	var p := player.global_position
	if landing.locker_at != Vector3.INF and Vector2(p.x - landing.locker_at.x, p.z - landing.locker_at.z).length() < 1.5:
		return "locker"
	if landing.cage_at != Vector3.INF and Vector2(p.x - landing.cage_at.x, p.z - landing.cage_at.z).length() < 1.6:
		if Game.depth == 1:
			return "lift_down" if Game.progress.deepest > 1 else ""
		return "lift_up"
	return ""


## What this run's tape is worth now: [salvage, the lines that explain it].
func appraise(caught: bool) -> Array:
	var lines := []
	var total := 0.0
	var m := roundi(meters)
	lines.append("DISTANCE                %4d" % m)
	total += m
	var new_depths := 0
	for d in range(start_depth + 1, max_depth + 1):
		total += 60.0 * d
		if d > Game.progress.deepest:
			new_depths += 1
	if max_depth > start_depth:
		lines.append("DEPTHS REACHED %d        %4d" % [max_depth, roundi(60.0 * (max_depth * (max_depth + 1) / 2.0 - start_depth * (start_depth + 1) / 2.0))])
	if new_depths > 0:
		lines.append("NEVER FILMED BEFORE     %4d" % (100 * new_depths))
		total += 100 * new_depths
	var cat := world.catalogue
	if cat:
		var firsts := cat.new_ids.size()
		if firsts > 0:
			lines.append("FIRSTS ON THE SHELF x%d  %4d" % [firsts, 25 * firsts])
			total += 25 * firsts
		if cat.tape.has("crawler") or cat.tape.has("occupant"):
			lines.append("IT, ON TAPE             %4d" % 30)
			total += 30
	if world.hunter and world.hunter.pins > 0:
		lines.append("HELD IN THE FLASH x%d    %4d" % [world.hunter.pins, 15 * world.hunter.pins])
		total += 15 * world.hunter.pins
	var share := Game.progress.caught_share() if caught else 1.0
	var paid := roundi(total * share)
	if caught:
		lines.append("TAPE DAMAGED            x%.2f" % share)
	lines.append("HALDEN PAYS             %4d" % paid)
	return [paid, lines]


## Caught: the tape is recovered damaged. Called before the END OF TAPE card goes up.
func on_caught() -> void:
	var a := appraise(true)
	_settle(a, "RECOVERED BY HALDEN")


func _settle(a: Array, head: String) -> void:
	var pr := Game.progress
	pr.salvage += int(a[0])
	pr.lifetime += int(a[0])
	pr.deepest = maxi(pr.deepest, max_depth)
	pr.standing += 1
	pr.runs += 1
	pr.save()
	Game.appraisal = "%s\n%s\nSALVAGE ON HAND  %d" % [head, "\n".join(a[1]), pr.salvage]
	_log("run over: +%d salvage (on hand %d), deepest %d" % [a[0], pr.salvage, pr.deepest])


## The stairwell: the long walk down, and the next depth built in the dark.
func descend() -> void:
	if _busy:
		return
	_busy = true
	_prompt.visible = false
	_saved_input = player.input
	player.input = PlayerInput.new()
	_sfx("stair_door_open", -2.0)
	_loop_play("stair_descend_loop", -6.0)
	var next := Game.depth + 1
	_log("down the stairs to depth %d" % next)
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 1.0, 1.1)
	tw.tween_callback(func(): _card_show("%s\n\n%s" % [_flights(next), Depths.label(next)]))
	tw.tween_interval(0.2)
	tw.tween_callback(_build_depth.bind(next))
	tw.tween_interval(STAIR_TIME)
	tw.tween_callback(func():
		_loop.stop()
		_sfx("stair_arrive", -3.0)
		_card.visible = false)
	tw.tween_property(_black, "color:a", 0.0, 1.4)
	tw.tween_callback(_done_transition)


func _flights(d: int) -> String:
	var s := ""
	for k in d * 2 + 3:
		s += "v  "
	return s


func _card_show(t: String) -> void:
	_card.text = t
	_card.visible = true


func _build_depth(d: int) -> void:
	world.goto_depth(d)
	max_depth = maxi(max_depth, d)
	if d > Game.progress.deepest:
		Game.progress.deepest = d
		Game.progress.save()
	player.spawn(world.get_spawn_transform())
	_last_pos = Vector3.INF


func _done_transition() -> void:
	player.input = _saved_input
	if player.input is AutoplayBot:
		(player.input as AutoplayBot).reset(player)
	_busy = false


## Back up in the lift cage you came down to: the tape is paid in full and a new run starts.
func bank() -> void:
	if _busy:
		return
	var a := appraise(false)
	_settle(a, "BROUGHT BACK UP")
	_busy = true
	_prompt.visible = false
	_saved_input = player.input
	player.input = PlayerInput.new()
	_sfx("lift_start", -2.0)
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 1.0, 1.2)
	tw.tween_callback(func(): _card_show(Game.appraisal))
	tw.tween_callback(func():
		world.goto_depth(1)
		player.spawn(world.get_spawn_transform())
		world.catalogue.new_tape()
		new_run(1))
	tw.tween_interval(5.0)
	tw.tween_callback(func():
		_card.visible = false
		_sfx("lift_arrive", -3.0))
	tw.tween_property(_black, "color:a", 0.0, 1.2)
	tw.tween_callback(_done_transition)


## The Landing's lift: straight down to a depth you have reached.
func ride_down(d: int) -> void:
	_busy = true
	_saved_input = player.input
	player.input = PlayerInput.new()
	_sfx("lift_start", -2.0)
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 1.0, 1.2)
	tw.tween_callback(func(): _card_show("%s\n\n%s" % ["|  ".repeat(d * 3), Depths.label(d)]))
	tw.tween_callback(func():
		world.goto_depth(d)
		player.spawn(world.get_spawn_transform())
		new_run(d))
	tw.tween_interval(3.5)
	tw.tween_callback(func():
		_card.visible = false
		_sfx("lift_arrive", -3.0))
	tw.tween_property(_black, "color:a", 0.0, 1.2)
	tw.tween_callback(_done_transition)


# ------------------------------------------------------------------ the locker and the lift

func _open_menu(kind: String) -> void:
	_menu_kind = kind
	_menu_i = 0
	_saved_input = player.input
	player.input = PlayerInput.new()
	_prompt.visible = false
	_black.color.a = 0.82
	_sfx("locker_open" if kind == "kit" else "appraise_tick", -6.0)
	_refresh_menu()
	_menu.visible = true


func _close_menu() -> void:
	_menu_kind = ""
	_menu.visible = false
	_black.color.a = 0.0
	player.input = _saved_input
	kit.refill()


func _refresh_menu() -> void:
	var pr := Game.progress
	var lines := []
	_menu_items.clear()
	if _menu_kind == "kit":
		lines.append("HALDEN DUPLICATING   FIELD LOCKER")
		lines.append("SALVAGE ON HAND  %d        DEEPEST  %d" % [pr.salvage, pr.deepest])
		lines.append("")
		for id in Progress.KIT_ORDER:
			_menu_items.append(id)
			var row: Array = Progress.KIT[id]
			var lv := pr.level(id)
			var maxlv: int = (row[1] as Array).size()
			var nc := pr.next_cost(id)
			var state := ""
			if nc.is_empty():
				state = "FULL"
			elif pr.deepest < int(nc[1]):
				state = "NEEDS DEPTH %d" % int(nc[1])
			else:
				state = "%d" % int(nc[0])
			var cur := ">" if _menu_items.size() - 1 == _menu_i else " "
			lines.append("%s %-18s %s%s   %s" % [cur, String(row[0]), "o".repeat(lv), ".".repeat(maxlv - lv), state])
		lines.append("")
		lines.append(String(Progress.KIT[_menu_items[_menu_i]][3]))
		lines.append("")
		lines.append("W S  CHOOSE     E  BUY     ESC  CLOSE")
	else:
		lines.append("HALDEN LIFT")
		lines.append("")
		for d in range(2, pr.deepest + 1):
			_menu_items.append(d)
			var cur := ">" if _menu_items.size() - 1 == _menu_i else " "
			lines.append("%s %s" % [cur, Depths.label(d)])
		lines.append("")
		lines.append("W S  CHOOSE     E  GO DOWN     ESC  STAY")
	_menu.text = "\n".join(lines)


func _menu_input() -> void:
	if Input.is_action_just_pressed("ui_up_kit"):
		_menu_i = posmod(_menu_i - 1, maxi(1, _menu_items.size()))
		_refresh_menu()
	elif Input.is_action_just_pressed("ui_down_kit"):
		_menu_i = posmod(_menu_i + 1, maxi(1, _menu_items.size()))
		_refresh_menu()
	elif Input.is_action_just_pressed("pause"):
		_close_menu()
	elif Input.is_action_just_pressed("interact"):
		if _menu_items.is_empty():
			_close_menu()
			return
		if _menu_kind == "kit":
			if Game.progress.buy(String(_menu_items[_menu_i])):
				_sfx("kit_buy", -4.0)
			else:
				_sfx("appraise_tick", -14.0)
			_refresh_menu()
		else:
			var d := int(_menu_items[_menu_i])
			_menu_kind = ""
			_menu.visible = false
			_black.color.a = 0.0
			player.input = _saved_input
			ride_down(d)


## Esc closes a menu before the pause screen sees it.
func _input(e: InputEvent) -> void:
	if _menu_kind != "" and e.is_action_pressed("pause"):
		_close_menu()
		get_viewport().set_input_as_handled()
