extends Node
## Global state (autoload "Game"): command-line options, the run seed, deterministic
## random streams, the game clock, quality preset, and the input map.
##
## User args come after `--` on the Godot command line:
##   --seed=N            reproduce a run exactly (default: random, always logged)
##   --autoplay          the bot plays instead of the mouse and keyboard
##   --capture=DIR       save review stills and motion-sheet frames into DIR (implies autoplay)
##   --perf=FILE.json    realtime performance run, writes the stats to FILE (implies autoplay)
##   --duration=SEC      length of an autoplay/capture/perf run (default 90)
##   --focus=FILE.json   extra hand-posed "focus" shots taken after the bot run (capture only)
##   --preset=high|medium
##   --reduced-flicker   photosensitivity mode: no fast light flicker

var opts: Dictionary = {}
var run_seed: int = 0
var preset: String = "high"
var autoplay: bool = false
var capture_dir: String = ""
var perf_out: String = ""
var focus_file: String = ""
var duration: float = 90.0
var reduced_flicker: bool = false

## Game clock in seconds. Advances by the frame delta, so under Movie Maker
## (--fixed-fps) it is exactly reproducible.
var clock: float = 0.0
var frame: int = 0

## Hidden disorientation value (VISION "Drift"), 0..1. Systems read it; M2+ drives it.
var drift: float = 0.0
## How afraid the player is (0..1): something on tape, a light dying near you. Drives breathing
## and the mix (M3, D026). Raised by events, falls back slowly on its own.
var fear: float = 0.0
## 0..1: how far the world sound is pulled down (the hum dies when something is near, D026).
var duck: float = 0.0
var duck_target: float = 0.0


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if opts.has("seed"):
		run_seed = int(opts["seed"])
	else:
		var r := RandomNumberGenerator.new()
		r.randomize()
		run_seed = r.randi() % 1000000
	preset = String(opts.get("preset", "high"))
	capture_dir = String(opts.get("capture", ""))
	perf_out = String(opts.get("perf", ""))
	focus_file = String(opts.get("focus", ""))
	autoplay = opts.has("autoplay") or capture_dir != "" or perf_out != ""
	duration = float(opts.get("duration", "90"))
	reduced_flicker = opts.has("reduced-flicker")
	_setup_input()
	_setup_audio_buses()
	print("[NOCLIP] seed=%d preset=%s autoplay=%s capture=%s perf=%s" % [run_seed, preset, autoplay, capture_dir, perf_out])


func _process(delta: float) -> void:
	clock += delta
	frame += 1
	fear = move_toward(fear, 0.0, delta * 0.06)
	drift = move_toward(drift, 0.0, delta * 1.4)
	duck = move_toward(duck, duck_target, delta * (0.9 if duck_target > duck else 0.35))
	var w := AudioServer.get_bus_index("World")
	if w >= 0:
		AudioServer.set_bus_volume_db(w, -10.0 * duck)


## A random stream that depends only on the run seed and a salt string, so every
## system draws its own numbers and adding a system never changes another one.
func rng(salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%s" % [run_seed, salt])
	return r


func is_capture() -> bool:
	return capture_dir != ""


func is_perf() -> bool:
	return perf_out != ""


func _setup_input() -> void:
	_keys("move_forward", [KEY_W, KEY_UP])
	_keys("move_back", [KEY_S, KEY_DOWN])
	_keys("move_left", [KEY_A, KEY_LEFT])
	_keys("move_right", [KEY_D, KEY_RIGHT])
	_keys("sprint", [KEY_SHIFT])
	_keys("crouch", [KEY_CTRL, KEY_C])
	_keys("interact", [KEY_E])
	_keys("toggle_perf", [KEY_F3])
	_keys("pause", [KEY_ESCAPE])
	if not InputMap.has_action("camcorder"):
		InputMap.add_action("camcorder")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("camcorder", mb)


func _keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


## Buses: Master <- World (positional world sound, short damped reverb) and UI.
func _setup_audio_buses() -> void:
	if AudioServer.get_bus_index("World") != -1:
		return
	# Loudness: the S01 mix measured about -26.5 LUFS (critique 006, L030). Make up gain on the
	# master with a limiter on top lands near -18 LUFS without clipping the camcorder beeps.
	var amp := AudioEffectAmplify.new()
	amp.volume_db = float(opts.get("master_gain", "7.5"))
	AudioServer.add_bus_effect(0, amp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, lim)
	AudioServer.add_bus()
	var w := AudioServer.bus_count - 1
	AudioServer.set_bus_name(w, "World")
	AudioServer.set_bus_send(w, "Master")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.55
	rev.damping = 0.75
	rev.spread = 0.6
	rev.hipass = 0.15
	rev.dry = 1.0
	rev.wet = 0.11
	rev.predelay_msec = 18.0
	AudioServer.add_bus_effect(w, rev)
	AudioServer.add_bus()
	var u := AudioServer.bus_count - 1
	AudioServer.set_bus_name(u, "UI")
	AudioServer.set_bus_send(u, "Master")
	# Room reverbs (M3, D026): sounds made inside a room's Area3D are sent to the reverb that
	# fits its size. Small offices, corridors, and big halls or rooms copied too tall.
	for spec in [["RevSmall", 0.32, 0.55, 0.18, 12.0], ["RevCorridor", 0.55, 0.62, 0.2, 26.0], ["RevLarge", 0.86, 0.5, 0.28, 48.0]]:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, spec[0])
		AudioServer.set_bus_send(b, "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = spec[1]
		rv.damping = spec[2]
		rv.wet = spec[3]
		rv.dry = 0.0
		rv.predelay_msec = spec[4]
		rv.spread = 0.8
		rv.hipass = 0.2
		AudioServer.add_bus_effect(b, rv)
