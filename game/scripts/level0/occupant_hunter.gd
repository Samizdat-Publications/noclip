class_name OccupantHunter
extends Node3D
## The Occupant hunts (S06, M4; VISION "The Entity"). It comes for you a while into a run, from
## behind, out of sight, and follows you at a distance. You can learn it is there:
## - footsteps that answer yours a beat late, and keep going a step after you stop;
## - the panel it passes under hiccups; the building's hum sinks the nearer it is;
## - by eye there is almost nothing: the room bends a little where it stands, and in the light it
##   throws a shadow with nothing to throw it; on tape it is a hole in the recording.
## It listens (running on wet carpet carries far, the camcorder's record beep, crouching is quiet),
## it sees (lit and standing up you are seen from far, crouched in the dark only up close), and it
## knows when it is being filmed. Once it has you it screams, the lights between you go out toward
## you, and it runs: a little slower than you sprint, faster than you walk, the panels dying over it
## as it comes. Break its line of sight and get away and it searches where it lost you, then leaves.
## It follows you through a storeroom door into the hall behind it; it cannot follow you through a
## seam (the sealed rooms behind the tape-only doors are safe). If it reaches you the recording ends:
## the death replay (DeathReplay) plays the last seconds of your tape, and you wake at the start.

enum S { ABSENT, STALK, NOTICE, CHASE, SEARCH, LEAVE, KILL }
const NAMES := ["absent", "stalk", "notice", "chase", "search", "leave", "kill"]

const FIRST_AT := 70.0               # seconds into a run before it first comes
const GAP := [75.0, 130.0]           # seconds between hunts
const STALK_SPEED := 1.25
const CATCHUP_SPEED := 2.4
const CHASE_SPEED := 3.1              # you sprint at 3.8 and walk at 1.45
const STALK_BACK := 14.0              # path meters it keeps behind you while stalking
const CATCH_R := 1.05
const SEE_LIT := 14.0
const SEE_DARK := 6.0
const ARRIVE_BACK := 26.0

var space: Level0World
var player: Player
var rig: OccupantRig
var state := S.ABSENT
var suspicion := 0.0
var last_known := Vector3.ZERO
var hunts := 0
var room: PortalRoom = null          # the storeroom hall it is in, or null (the level)
var log_events := false
var on_caught: Callable              # called once when it reaches you (the world plays the replay)
var saved_input: PlayerInput         # your controls, given back after the replay

var _rng: RandomNumberGenerator
var _next := FIRST_AT
var _trail: Array[Vector3] = []      # where you walked (every meter), for coming from behind
var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _st := 0.0                       # seconds in this state
var _lost := 0.0
var _speed := 0.0
var _moving := false
var _echo: Array = []                # [time, loud] steps answering yours
var _step_t := 0.0
var _killed: Array = []              # panels it put out
var _stuttered := {}
var _steps: AudioStreamPlayer3D
var _rustle: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _drone: AudioStreamPlayer
var _step_bank: AudioStreamRandomizer
var _kill_t := 0.0
var _paper_snd: AudioStreamPlayer3D   # paper tearing: it is made of the walls' paper (Gemini 025)
var _tear_bank: AudioStreamRandomizer
var _tear_t := 6.0
var _breath_t := 3.0
var _caught_called := false
# The Descent (D050): each depth tunes it (Depths), the flashbulb pins it, flares keep it off.
var first_at := FIRST_AT
var chase_speed := CHASE_SPEED
var gap_mult := 1.0
var _pinned := 0.0
var pins := 0


func _ready() -> void:
	_rng = Game.rng("occupant:hunt")
	log_events = Game.opts.has("log-hunt")
	configure(Game.depth)
	if Game.opts.has("no_hunt") or not _body_ok():
		_next = 1e9
	crawler = Crawler.available() and not Game.opts.has("occupant_hunts")
	rig = CrawlerRig.new() if crawler else OccupantRig.new()
	rig.name = "occupant_rig"
	rig.top_level = true
	add_child(rig)
	rig.visible = false
	_step_bank = AudioStreamRandomizer.new()
	_step_bank.random_pitch = 1.06
	_step_bank.random_volume_offset_db = 2.0
	for i in 6:
		var p := _snd("step") % (i + 1)
		if ResourceLoader.exists(p):
			_step_bank.add_stream(-1, load(p))
	_steps = _player3d(1.6, 34.0)
	_steps.stream = _step_bank
	_steps.max_polyphony = 2
	_rustle = _player3d(1.0, 12.0)
	var rl := _loop(_snd("rustle"))
	if rl:
		_rustle.stream = rl
	_voice = _player3d(3.0, 50.0)
	_paper_snd = _player3d(2.2, 30.0)
	_paper_snd.max_polyphony = 2
	_tear_bank = AudioStreamRandomizer.new()
	_tear_bank.random_pitch = 1.12
	_tear_bank.random_volume_offset_db = 2.5
	for i in 4:
		var tp := _snd("tear") % (i + 1)
		if ResourceLoader.exists(tp):
			_tear_bank.add_stream(-1, load(tp))
	_drone = AudioStreamPlayer.new()
	_drone.bus = &"Master"
	var dl := _loop("res://assets/audio/entity/chase_drone_loop.wav")
	if dl:
		_drone.stream = dl
	_drone.volume_db = -80.0
	add_child(_drone)


## Look-dev (builder only, focus shots with "stage"): the body posed in front of the camera,
## {"dist": m, "side": m, "clip": name, "t": 0..1, "eyes": bool}.
var stage_req := {}


func _do_stage() -> void:
	var fwd := -player.cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var p := player.global_position + fwd * float(stage_req.get("dist", 5.0)) + side * float(stage_req.get("side", 0.0))
	if stage_req.has("at"):
		p = stage_req["at"]
	global_position = Vector3(p.x, player.global_position.y, p.z)
	_face(stage_req["face_to"] if stage_req.has("face_to") else player.global_position)
	if rig is CrawlerRig and stage_req.get("by_face", false):
		var ho := (rig as CrawlerRig).head_position() - rig.global_position
		ho.y = 0.0
		global_position -= ho
	rig.visible = true
	rig.global_transform = global_transform
	rig.hold_all(String(stage_req.get("clip", "walk")), float(stage_req.get("t", 0.3)))
	rig.snap()
	rig.presence = 1.0
	if rig is CrawlerRig:
		(rig as CrawlerRig).open_eyes(bool(stage_req.get("eyes", false)))
		(rig as CrawlerRig).look_at_point(player.cam.global_position, float(stage_req.get("look", 0.0)))


## Which body hunts (D052): the Crawler, the Monster Lab's pick, unless --occupant_hunts.
var crawler := false
const SND_OCC := {"step": "res://assets/audio/entity/occ_step_%02d.wav", "rustle": "res://assets/audio/entity/occ_rustle_loop.wav",
	"tear": "res://assets/audio/entity/occ_tear_%02d.wav", "breath": "res://assets/audio/entity/occ_breath_%02d.wav",
	"shriek": "res://assets/audio/entity/occ_shriek_%02d.wav", "kill": "res://assets/audio/entity/kill_tape_01.wav",
	"flashed": "res://assets/audio/descent/occ_flashed_%02d.wav"}
const SND_CRW := {"step": "res://assets/audio/crawler/crw_step_%02d.wav", "rustle": "res://assets/audio/crawler/crw_drag_loop.wav",
	"tear": "res://assets/audio/crawler/crw_tear_%02d.wav", "breath": "res://assets/audio/crawler/crw_breath_%02d.wav",
	"shriek": "res://assets/audio/crawler/crw_notice_%02d.wav", "kill": "res://assets/audio/crawler/crw_grab_01.wav",
	"flashed": "res://assets/audio/crawler/crw_flashed_%02d.wav"}


func _body_ok() -> bool:
	return Crawler.available() or Occupant.available()


## Its sounds: the Crawler's own where they exist, the Occupant's otherwise.
func _snd(kind: String) -> String:
	if crawler:
		var c: String = SND_CRW[kind]
		var probe := c % 1 if c.contains("%") else c
		if ResourceLoader.exists(probe):
			return c
	return SND_OCC[kind]


## A new depth (or a new run): its timing and speed from the depth table.
func configure(depth: int) -> void:
	var row := Depths.get_row(depth)
	first_at = float(row.get("first_at", FIRST_AT))
	chase_speed = float(row.get("chase", CHASE_SPEED))
	gap_mult = float(row.get("gap", 1.0))
	_next = Game.clock + float(Game.opts.get("hunt_at", str(first_at)))
	if Game.opts.has("no_hunt") or not _body_ok():
		_next = 1e9


## The flashbulb went off at `from`, looking along `dir`. If it is caught in the flash (in front, near
## enough, nothing between) it is pinned where it stands for a few seconds, then it has lost you.
func flashed(from: Vector3, dir: Vector3) -> bool:
	if state == S.ABSENT or state == S.KILL or state == S.LEAVE:
		return false
	var to := _head() - Vector3(0, 0.6, 0) - from
	if to.length() > 16.0:
		return false
	if rad_to_deg(acos(clampf(dir.normalized().dot(to.normalized()), -1.0, 1.0))) > 32.0:
		return false
	if not _clear(from, from + to * 0.97):
		return false
	_pinned = 3.6
	pins += 1
	_close = false
	_close_done = true
	_speed = 0.0
	suspicion = 0.0
	rig.presence = 1.0
	rig.tear = 1.0
	rig.hold_all("scream", 0.3)
	_voice_play(_snd("flashed") % (1 + _rng.randi() % 2), 2.0)
	_log("pinned by the flash (%.1f m)" % to.length())
	return true


func _player3d(unit: float, maxd: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"World"
	p.unit_size = unit
	p.max_distance = maxd
	p.top_level = true
	add_child(p)
	return p


func _loop(path: String) -> AudioStreamWAV:
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStreamWAV
	if s:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func attach(p: Player) -> void:
	player = p
	player.stepped.connect(_on_step)
	player.camcorder.beeped.connect(_on_beep)


func active() -> bool:
	return state != S.ABSENT


## Gone for good (the capture's posed shots, after the run).
func stand_down() -> void:
	if state != S.ABSENT and state != S.KILL:
		_gone()
	_next = 1e9


## Come sooner (something drew its attention: you filmed it on tape).
func soon(seconds: float) -> void:
	if state == S.ABSENT and _next < 1e8:
		_next = minf(_next, Game.clock + seconds)
		_log("coming in %.0f s" % (_next - Game.clock))


func _log(msg: String) -> void:
	if log_events:
		print("[hunt] t=%.1f %s" % [Game.clock, msg])


func _set_state(s: int) -> void:
	if s == state:
		return
	_log("%s -> %s pos=%s dist=%.1f" % [NAMES[state], NAMES[s], global_position, _dist()])
	state = s
	_st = 0.0
	_path = PackedVector3Array()
	_repath = 0.0


# ------------------------------------------------------------------ geometry helpers

func _dist() -> float:
	if player == null:
		return 1e9
	if _space_of(player.global_position) != room:
		return 1e9
	var d := player.global_position - global_position
	return Vector2(d.x, d.z).length()


## The hall that holds p, or null for the level.
func _space_of(p: Vector3) -> PortalRoom:
	for r in space.rooms.values():
		var rm := r as PortalRoom
		if rm.built and rm.contains(p):
			return rm
	return null


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	if player:
		q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Can the player's eye see a point (in view and nothing in between)?
func _player_sees(p: Vector3, max_off_deg: float = 40.0) -> bool:
	var cam := player.cam
	var to := p - cam.global_position
	if to.length() > 40.0:
		return false
	var fwd := -cam.global_transform.basis.z
	if rad_to_deg(acos(clampf(fwd.dot(to.normalized()), -1.0, 1.0))) > max_off_deg:
		return false
	return _clear(cam.global_position, p)


func _head() -> Vector3:
	return global_position + Vector3(0, 2.05, 0)


# ------------------------------------------------------------------ senses

func _on_step(loud: float) -> void:
	if state == S.ABSENT or state == S.KILL:
		return
	var d := _dist()
	if state == S.STALK and d < 26.0 and _moving:
		# Your steps answered a beat late, from behind you.
		_echo.append([Game.clock + _rng.randf_range(0.36, 0.5), 1.0])
	if d < loud:
		var through_wall := not _clear(_head(), player.global_position + Vector3(0, 1.2, 0))
		if not through_wall or d < loud * 0.55:
			suspicion += 0.34 if loud > 15.0 else 0.12
			last_known = player.global_position


func _on_beep() -> void:
	if state == S.ABSENT or state == S.KILL:
		return
	if _dist() < 16.0:
		suspicion += 0.55
		last_known = player.global_position
		_log("heard the record beep, suspicion %.2f" % suspicion)


func _sees_player(scale: float = 1.0) -> bool:
	var d := _dist()
	if d > SEE_LIT:
		return false
	var lit := space.fixture_near(player.global_position, 2.6) != null
	var r := (SEE_LIT if lit else SEE_DARK) * scale
	if player.is_low():
		r *= 0.6
	if d > r:
		return false
	return _clear(_head(), player.global_position + Vector3(0, 1.3 if not player.is_low() else 0.5, 0))


## Filming it: the camcorder up and pointed at it, close enough to make it out.
func _being_filmed() -> bool:
	if not player.camcorder.settled() or _dist() > 15.0:
		return false
	return _player_sees(global_position + Vector3(0, 1.3, 0), 22.0)


# ------------------------------------------------------------------ the hunt

func _process(delta: float) -> void:
	if player == null or space == null:
		return
	_st += delta
	if not stage_req.is_empty():
		_do_stage()
		return
	_trail_update()
	_echo_steps()
	if _pinned > 0.0:
		_pinned -= delta
		_speed = 0.0
		_drone_to(-30.0, delta, 1.0)
		Game.duck_extra = move_toward(Game.duck_extra, 0.2, delta)
		rig.global_position = global_position
		rig.global_basis = global_basis
		if _pinned <= 0.0:
			_log("the flash let go: it has lost you")
			_set_state(S.LEAVE)
		return
	match state:
		S.ABSENT:
			Game.duck_extra = move_toward(Game.duck_extra, 0.0, delta * 0.3)
			_drone_to(-80.0, delta, 0.5)
			if Game.clock >= _next and not player.caught and _can_start():
				_arrive()
			return
		S.STALK:
			_stalk(delta)
		S.NOTICE:
			_notice(delta)
		S.CHASE:
			_chase(delta)
		S.SEARCH:
			_search(delta)
		S.LEAVE:
			_leave(delta)
		S.KILL:
			_kill(delta)
	_tells(delta)
	rig.global_position = global_position
	rig.global_basis = global_basis
	if log_events and Game.frame % 150 == 0:
		_log("%s dist=%.1f path_left=%.1f speed=%.1f susp=%.2f room=%s player_room=%s via=%s" % [NAMES[state], _dist(), _path_left(), _speed, suspicion, room.key if room else "-", _space_of(player.global_position).key if _space_of(player.global_position) else "-", _via != null])


func _can_start() -> bool:
	if space.tape and space.tape.state != TapeEvents.S.IDLE:
		return false
	if space.in_pocket(player.global_position):
		return false
	if space.scares and space.scares._state in [1, 2]:
		return false     # a body lies ahead of you: that scene plays out first
	return _trail.size() > 12


func _trail_update() -> void:
	if player.caught:
		return
	var p := player.global_position
	if _trail.is_empty() or Vector2(p.x - _trail[-1].x, p.z - _trail[-1].z).length() > 1.0:
		if not _trail.is_empty() and p.distance_to(_trail[-1]) > 4.0:
			_trail.clear()     # a portal or a loop moved you: the old trail is somewhere else
		_trail.append(p)
		if _trail.size() > 80:
			_trail.pop_front()


## It comes from behind: a point on your own trail, out of your sight.
func _arrive() -> void:
	var here := player.global_position
	room = _space_of(here)
	var spot := Vector3.INF
	var walked := 0.0
	for i in range(_trail.size() - 1, 0, -1):
		walked += _trail[i].distance_to(_trail[i - 1])
		if walked < ARRIVE_BACK * 0.6:
			continue
		var c := _trail[i - 1]
		if not _player_sees(c + Vector3(0, 1.2, 0), 70.0):
			spot = c
			if walked >= ARRIVE_BACK:
				break
	if spot == Vector3.INF:
		_next = Game.clock + 4.0
		return
	hunts += 1
	_close_done = false
	_close = false
	global_position = spot
	suspicion = 0.0
	rig.visible = true
	rig.presence = 0.55
	rig.set_clip("walk", 0.9)
	rig.snap()
	_paper()
	_set_state(S.STALK)
	if _rustle.stream:
		_rustle.global_position = global_position + Vector3(0, 1.4, 0)
		_rustle.volume_db = -12.0
		_rustle.play()


func _paper() -> void:
	var tint := Vector3(1.03, 0.97, 0.86)
	var sat := 1.25
	if room:
		var pal: Dictionary = PortalRoom.PALETTES.get(room.palette, {})
		if pal.has("wall_tint"):
			var wt: Array = pal["wall_tint"]
			tint = Vector3(wt[0], wt[1], wt[2])
		sat = float(pal.get("wall_sat", sat))
	rig.set_paper(tint, sat)


var _door_hold := 0.0                # seconds it stands in a doorway it has just come through
var _close := false                  # standing right behind you, still (the close beat)
var _close_t := 0.0
var _close_done := false
var _close_seen := 0.0
var _close_filmed := 0.0
var _still_t := 0.0


## Too close and too still (critique 026: "something that sits too close and too still"): once a hunt,
## when you stand still a while, it is suddenly right behind you, two meters away, not moving. The
## panel over it dies, the hum sinks away, you hear it breathe. Turn round and film it and it screams
## in your face and comes for you. Look at it by eye and it is gone. Do nothing and it leaves.
func _start_close() -> bool:
	var cam := player.cam
	var back := cam.global_transform.basis.z
	back.y = 0.0
	if back.length() < 0.1:
		return false
	back = back.normalized()
	var pp := player.global_position
	for ang in [0.0, 22.0, -22.0, 40.0, -40.0]:
		for dist in [2.2, 2.6, 1.9]:
			var p: Vector3 = pp + back.rotated(Vector3.UP, deg_to_rad(ang)) * dist
			if not space.is_walkable(p):
				continue
			if _player_sees(p + Vector3(0, 1.2, 0), 75.0):
				continue
			var hq := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.9, 0), player.cam.global_position)
			hq.exclude = [player.get_rid()]
			if not get_world_3d().direct_space_state.intersect_ray(hq).is_empty():
				continue
			global_position = Vector3(p.x, pp.y, p.z)
			_face(pp)
			rig.global_transform = global_transform
			rig.set_clip("idle", 0.5)
			rig.snap()
			rig.presence = 0.9
			_close = true
			_close_t = 0.0
			_close_seen = 0.0
			_close_filmed = 0.0
			_speed = 0.0
			var fx := space.fixture_near(global_position, 2.2)
			if fx and not _killed.has(fx):
				fx.kill(0.2)
				_killed.append(fx)
			_voice_play(_snd("breath") % (1 + _rng.randi() % 2), -3.0)
			_log("right behind you (%.1f m)" % _dist())
			return true
	return false


func _close_beat(delta: float) -> void:
	_close_t += delta
	_face(player.global_position)
	if rig is CrawlerRig:
		(rig as CrawlerRig).look_at_point(player.cam.global_position, 0.9)
	Game.duck_extra = move_toward(Game.duck_extra, 0.85, delta * 1.5)
	Game.fear = maxf(Game.fear, 0.7)
	if _being_filmed():
		_close_filmed += delta
	elif _player_sees(_head(), 32.0):
		_close_seen += delta
	if _close_filmed > 0.45:
		_close = false
		_close_done = true
		_log("filmed up close: it screams")
		_set_state(S.NOTICE)
		return
	if _close_seen > 0.9 or _close_t > 7.0 or _dist() > 6.0:
		_close = false
		_close_done = true
		rig.tear = 1.0
		_log("gone from behind you (seen %.1f, %.1f s)" % [_close_seen, _close_t])
		# back down your trail, out of sight, still following
		var here := _space_of(player.global_position)
		for k in range(_trail.size() - 1, 0, -1):
			var q := _trail[k]
			var flat := Vector2(q.x - player.global_position.x, q.z - player.global_position.z).length()
			if flat > 12.0 and absf(q.y - player.global_position.y) < 2.0 and _space_of(q) == here and not _player_sees(q + Vector3(0, 1.2, 0), 80.0):
				global_position = q
				room = here
				break
		rig.global_transform = global_transform
		rig.snap()
		_st = 8.0


func _stalk(delta: float) -> void:
	if _close:
		_close_beat(delta)
		return
	if Vector2(player.velocity.x, player.velocity.z).length() < 0.3:
		_still_t += delta
	else:
		_still_t = 0.0
	if not _close_done and _st > 16.0 and _still_t > 1.4 and not player.camcorder.active and _space_of(player.global_position) == room and not space.in_pocket(player.global_position):
		if _start_close():
			return
	var d := _dist()
	# Senses: seen, heard (steps, the beep), filmed. While it only follows, it looks less hard.
	if _sees_player(0.7):
		suspicion += delta * (2.2 if d < 8.0 else 1.2)
		last_known = player.global_position
	if _being_filmed():
		suspicion += delta * 0.9
	suspicion = maxf(suspicion - delta * 0.08, 0.0)
	# Just come through a storeroom door after you: it stands in the doorway a moment first.
	if _door_hold > 0.0:
		_door_hold -= delta
		_speed = 0.0
		rig.set_clip("look", 0.6)
		return
	if (suspicion >= 1.0 and d < 40.0) or (d < 3.5 and _st > 2.0):
		_set_state(S.NOTICE)
		return
	if _st > 90.0:
		_set_state(S.LEAVE)
		return
	# It keeps a distance behind you that shrinks the longer it follows: each time you look back it
	# is a little nearer (14 m of path at first, 4 m after about 50 s).
	var back := lerpf(STALK_BACK, 4.0, clampf((_st - 6.0) / 45.0, 0.0, 1.0))
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.6
		_path = _route_to(player.global_position)
		_path_i = 1 if _path.size() > 1 else 0
	var left := _path_left()
	var want := 0.0
	if left > back + 8.0 or _via != null:
		want = CATCHUP_SPEED
	elif left > back:
		want = STALK_SPEED
	var seen_now := _player_sees(_head(), 38.0) and d < 22.0
	if seen_now:
		want = 0.0         # it stops when you turn round (by eye it is hardly there)
	if rig is CrawlerRig:
		# caught looking: it stops, and its face comes up to you
		(rig as CrawlerRig).look_at_point(player.cam.global_position, 0.7 if seen_now else 0.0)
	_speed = move_toward(_speed, want, delta * 2.0)
	_advance(delta)
	rig.set_clip("walk" if _speed > 0.2 else "look", 0.85)
	rig.presence = 0.5
	Game.duck_extra = clampf(1.0 - (d - 5.0) / 20.0, 0.0, 0.55)
	_drone_to(-80.0, delta, 0.5)


func _notice(delta: float) -> void:
	_speed = 0.0
	_face(player.global_position)
	if _st < delta * 1.5:
		_log("noticed you (suspicion %.2f)" % suspicion)
		Game.fear = 1.0
		if space.director:
			space.director.hunt_shock(global_position)
		_voice_play(_snd("shriek") % (1 + _rng.randi() % 2), -2.0)
		if _tear_bank.streams_count > 0:
			_paper_snd.stream = _tear_bank
			_paper_snd.global_position = _head()
			_paper_snd.volume_db = 3.0
			_paper_snd.play()
		_tear_t = 0.5
		rig.tear = 1.0
		rig.hold_all("scream", 0.45)
		# The lights between you go out, toward you.
		_light_wave()
		space.attention_point = _head()
		space.attention_until = Game.clock + 1.2
		space.attention_kind = &"hunt"
	rig.presence = 1.0
	_drone_to(-6.0, delta, 2.0)
	if _st > 1.0:
		last_known = player.global_position
		_set_state(S.CHASE)


func _chase(delta: float) -> void:
	var d := _dist()
	var seen := _sees_player() or d < 4.0
	if seen:
		last_known = player.global_position
		_lost = 0.0
	else:
		_lost += delta
	if space.in_pocket(player.global_position) or space.in_flare(player.global_position):
		_lost += delta * 2.0
	# Lost you, or you kept ahead of it long enough: it stops and searches.
	if (_lost > 4.0 and d > 8.0) or (_st > 15.0 and d > 3.5):
		_set_state(S.SEARCH)
		return
	if d < CATCH_R and not player.caught and _st > 1.0 and not space.in_flare(player.global_position):
		_caught()
		return
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.3
		_path = _route_to(player.global_position if seen or _lost < 1.5 else last_known)
		_path_i = 1 if _path.size() > 1 else 0
	_speed = move_toward(_speed, chase_speed * (1.0 if _st > 1.2 else 0.6), delta * 3.0)
	_advance(delta)
	rig.set_clip("run", 1.0)
	rig.presence = 1.0
	rig.skip_gap = Vector2(0.24, 0.5)
	rig.alt_clips = ["lunge", "scream", "crouch"]
	# The panels it runs under die.
	var fx := space.fixture_near(global_position, 1.9)
	if fx and not _killed.has(fx):
		fx.kill(0.0)
		_killed.append(fx)
	Game.duck_extra = 0.7
	Game.fear = maxf(Game.fear, 0.85)
	_drone_to(-4.0, delta, 2.0)
	space.attention_point = _head()
	space.attention_until = Game.clock + 0.3
	space.attention_kind = &"hunt"


func _search(delta: float) -> void:
	rig.alt_clips = []
	if _sees_player():
		suspicion += delta * 2.0
		last_known = player.global_position
	if suspicion >= 1.0:
		_set_state(S.NOTICE)
		return
	suspicion = maxf(suspicion - delta * 0.1, 0.0)
	if _path.is_empty():
		_path = _route_to(last_known)
		_path_i = 1 if _path.size() > 1 else 0
	if _path_left() > 0.6:
		_speed = move_toward(_speed, 1.6, delta * 2.0)
		_advance(delta)
		rig.set_clip("walk", 1.1)
	else:
		_speed = 0.0
		rig.set_clip("look", 0.7)
	rig.presence = 0.7
	rig.skip_gap = Vector2(0.18, 0.42)
	suspicion = minf(suspicion, 0.6)
	Game.duck_extra = 0.45
	_drone_to(-16.0, delta, 0.4)
	if _st > 11.0:
		_set_state(S.LEAVE)


func _leave(delta: float) -> void:
	if _st < delta * 1.5:
		# Away from you, somewhere you are not looking.
		var away := global_position - player.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		_path = _route_to(global_position + away * 18.0)
		_path_i = 1 if _path.size() > 1 else 0
	_speed = move_toward(_speed, 1.5, delta)
	_advance(delta)
	rig.set_clip("walk", 0.9)
	rig.presence = 0.4
	Game.duck_extra = move_toward(Game.duck_extra, 0.0, delta * 0.2)
	_drone_to(-80.0, delta, 0.3)
	if _st > 6.0 and not _player_sees(_head(), 60.0) or _st > 20.0:
		_gone()


## Off the board until next time; the lights it put out come back on one by one.
func _gone() -> void:
	_log("gone (hunt %d over)" % hunts)
	rig.visible = false
	_rustle.stop()
	var k := 0
	for fx in _killed:
		if is_instance_valid(fx):
			fx.restore(1.0 + k * _rng.randf_range(0.3, 0.8))
		k += 1
	_killed.clear()
	_next = Game.clock + _rng.randf_range(GAP[0], GAP[1]) * (0.8 if hunts > 1 else 1.0) * gap_mult
	suspicion = 0.0
	_set_state(S.ABSENT)


# ------------------------------------------------------------------ moving

## A path to `to`, through the storeroom doors when it and you are on different sides of one.
func _route_to(to: Vector3) -> PackedVector3Array:
	var target_room := _space_of(to)
	_via = null
	if target_room != room:
		var door := _door_toward(target_room)
		if door.is_empty():
			return PackedVector3Array()
		var p := _straight_or_path(global_position, door["pos"])
		p.append(door["through"])
		_via = door["portal"]
		return p
	return _straight_or_path(global_position, to)


var _via: Portal = null              # the storeroom door the current path goes through


func _straight_or_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	if room:
		return PackedVector3Array([a, b])
	var p := space.find_path(a, b)
	if p.is_empty() and a.distance_to(b) < 3.0:
		p = PackedVector3Array([a, b])
	return p


## The portal on its side that leads toward `target_room` (null: the level): where to stand, and a
## point just through it. {} if there is none.
func _door_toward(target_room: PortalRoom) -> Dictionary:
	var rm: PortalRoom = room if room else target_room
	if rm == null or not rm.built:
		return {}
	var best := {}
	var bd := 1e9
	for po in rm.portals():
		var on_my_side := rm.contains(po.global_position) == (room != null)
		if not on_my_side:
			continue
		var d := po.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			# A portal's x axis is the way you walk through it (Portal.crossed).
			var nx := po.global_basis.x
			nx.y = 0.0
			nx = nx.normalized()
			var front := po.global_position - nx * 0.8
			var through := po.global_position + nx * 0.3
			best = {"pos": Vector3(front.x, global_position.y, front.z), "through": Vector3(through.x, global_position.y, through.z), "portal": po}
	return best


func _path_left() -> float:
	if _path.is_empty() or _path_i >= _path.size():
		return 0.0
	var l := Vector2(global_position.x - _path[_path_i].x, global_position.z - _path[_path_i].z).length()
	for i in range(_path_i, _path.size() - 1):
		l += Vector2(_path[i].x - _path[i + 1].x, _path[i].z - _path[i + 1].z).length()
	return l


func _advance(delta: float) -> void:
	_moving = false
	if _path.is_empty() or _path_i >= _path.size() or _speed <= 0.01:
		return
	var left := _speed * delta
	while left > 0.0 and _path_i < _path.size():
		var wp := _path[_path_i]
		var to := Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
		var l := to.length()
		# Red light: it will not step into a burning flare's pool.
		if l > 0.01 and space.in_flare(global_position + to / l * minf(left + 0.6, l)) and not space.in_flare(global_position):
			_speed = 0.0
			break
		if l <= left:
			global_position = Vector3(wp.x, global_position.y, wp.z)
			left -= l
			_path_i += 1
			_check_portal()
		else:
			global_position += to / l * left
			left = 0.0
		if l > 0.05:
			_face(global_position + to)
	_moving = true
	_step_sounds(delta)


## Walking through a storeroom door: carried across like you are (Portal.mapping).
func _check_portal() -> void:
	if _via == null or not is_instance_valid(_via):
		return
	var l := _via.local_of(global_position + Vector3(0, 1.0, 0))
	if l.x < 0.0 or l.x > 1.5 or absf(l.z) > 1.0:
		return
	var m := _via.mapping()
	global_position = m * global_position
	global_basis = m.basis * global_basis
	_via = null
	room = _space_of(global_position)
	_path = PackedVector3Array()
	_repath = 0.0
	rig.global_transform = global_transform
	rig.snap()
	_paper()
	_log("went through a storeroom door, now in %s" % (room.key if room else "the level"))
	if state == S.STALK:
		_door_hold = 2.5
		_st = minf(_st, 20.0)


func _face(p: Vector3) -> void:
	var t := Vector3(p.x, global_position.y, p.z)
	if t.distance_to(global_position) > 0.05:
		look_at(t, Vector3.UP, true)


## A loop repeat carried you back a copy: it is carried with you (it stays in the hall behind you).
func shift(offset: Vector3) -> void:
	if state == S.ABSENT:
		return
	global_position += offset
	for i in _path.size():
		_path[i] += offset
	for i in _trail.size():
		_trail[i] += offset
	last_known += offset
	rig.global_position = global_position
	rig.snap()


# ------------------------------------------------------------------ tells

func _step_sounds(delta: float) -> void:
	if state != S.CHASE and state != S.SEARCH and state != S.LEAVE:
		return
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = 0.36 if state == S.CHASE else 0.72
		_play_step(0.0 if state == S.CHASE else -5.0)


func _echo_steps() -> void:
	while not _echo.is_empty() and Game.clock >= float(_echo[0][0]):
		_echo.pop_front()
		if state == S.STALK:
			_play_step(-7.0)


func _play_step(db: float) -> void:
	if _step_bank.streams_count == 0:
		return
	_steps.global_position = global_position + Vector3(0, 0.1, 0)
	_steps.volume_db = db
	_steps.play()


func _voice_play(path: String, db: float) -> void:
	if not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.global_position = _head()
	_voice.volume_db = db
	_voice.play()


func _drone_to(db: float, delta: float, rate: float) -> void:
	if _drone.stream == null:
		return
	if db > -60.0 and not _drone.playing:
		_drone.play()
	_drone.volume_db = lerpf(_drone.volume_db, db, 1.0 - exp(-rate * delta))
	if db <= -79.0 and _drone.volume_db < -60.0 and _drone.playing:
		_drone.stop()


func _tells(delta: float) -> void:
	_rustle.global_position = global_position + Vector3(0, 1.4, 0)
	var rv := -15.0
	match state:
		S.SEARCH:
			rv = -8.0
		S.NOTICE, S.CHASE, S.KILL:
			rv = -3.0
	_rustle.volume_db = lerpf(_rustle.volume_db, rv, 1.0 - exp(-2.0 * delta))
	# Paper tearing: soft and rare while it follows, harsh while it runs.
	_tear_t -= delta
	if _tear_t <= 0.0 and _tear_bank.streams_count > 0:
		var chase := state == S.CHASE or state == S.KILL
		_tear_t = _rng.randf_range(0.7, 1.4) if chase else _rng.randf_range(7.0, 13.0)
		if state != S.LEAVE:
			_paper_snd.stream = _tear_bank
			_paper_snd.global_position = _head() - Vector3(0, 0.5, 0)
			_paper_snd.volume_db = 0.0 if chase else -9.0
			_paper_snd.play()
	if state == S.SEARCH:
		_breath_t -= delta
		if _breath_t <= 0.0:
			_breath_t = _rng.randf_range(4.0, 6.5)
			_voice_play(_snd("breath") % (1 + _rng.randi() % 2), -4.0)
	# The panel over it hiccups as it passes (not every time).
	if state == S.STALK or state == S.SEARCH:
		var fx := space.fixture_near(global_position, 1.5)
		if fx and Game.clock - float(_stuttered.get(fx, -99.0)) > 8.0:
			_stuttered[fx] = Game.clock
			if _rng.randf() < 0.7:
				fx.stutter()


## The lights between it and you go out, the farthest from you first.
func _light_wave() -> void:
	var pp := player.global_position
	var me := global_position
	var line := pp - me
	line.y = 0.0
	var ln := line.length()
	var cand := []
	for fx in space.pool.fixtures:
		if not is_instance_valid(fx) or fx.level < 0.5:
			continue
		var p: Vector3 = fx.global_position
		var rel := Vector3(p.x - me.x, 0.0, p.z - me.z)
		var along := rel.dot(line / maxf(ln, 0.01))
		var side := (rel - line / maxf(ln, 0.01) * along).length()
		if along > -3.0 and along < ln - 2.5 and side < 3.5:
			cand.append([along, fx])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var k := 0
	for c in cand:
		(c[1] as Fixture).kill(0.12 + k * 0.11)
		_killed.append(c[1])
		k += 1
	_log("light wave: %d panels" % k)


# ------------------------------------------------------------------ the end of the tape

func _caught() -> void:
	_log("caught you")
	_set_state(S.KILL)
	player.caught = true
	saved_input = player.input
	player.input = DeathInput.new()
	(player.input as DeathInput).target = self
	(player.input as DeathInput).look_h = 1.2 if crawler else 1.9
	_speed = 0.0
	Game.fear = 1.0
	_voice_play(_snd("shriek") % (1 + _rng.randi() % 2), 2.0)


func _kill(delta: float) -> void:
	# It is right in front of the lens, the camera up whether you raised it or not.
	var cam := player.cam
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if crawler:
		# The Crawler leans its face in, slowly, eyes shut, until it fills the lens; then they open.
		var lean := clampf(_st / 1.05, 0.0, 1.0)
		# placed by its face, not its hips: the face comes to rest just in front of the lens
		var head_off := (rig as CrawlerRig).head_position() - global_position
		head_off.y = 0.0
		var want_c := Vector3(cam.global_position.x, player.global_position.y, cam.global_position.z) + fwd * lerpf(1.8, 1.05, lean) - head_off
		global_position = global_position.lerp(want_c, 1.0 - exp(-8.0 * delta))
		_face(player.global_position)
		rig.global_position = global_position
		rig.global_basis = global_basis
		rig.hold_all("idle", 0.5 + 0.04 * sin(Game.clock * 2.0))
		(rig as CrawlerRig).open_eyes(_st > 0.8)
		(rig as CrawlerRig).look_at_point(cam.global_position, clampf(_st * 1.2, 0.0, 0.85))
	else:
		var want := Vector3(cam.global_position.x, player.global_position.y, cam.global_position.z) + fwd * 0.95
		global_position = global_position.lerp(want, 1.0 - exp(-14.0 * delta))
		_face(player.global_position)
		rig.global_position = global_position
		rig.hold_all("scream", 0.4 + 0.1 * sin(Game.clock * 9.0))
	rig.skip_gap = Vector2(0.04, 0.09)
	rig.tear = 1.0
	player.camcorder.degrade = 0.6
	_drone_to(0.0, delta, 4.0)
	if _st > 1.05 and not _caught_called:
		_caught_called = true
		_voice_play(_snd("kill"), 4.0)
		player.camcorder.glitch()
		if on_caught.is_valid():
			on_caught.call()


## After the replay: you are back at the start, it is gone for now.
func reset_after_death() -> void:
	_caught_called = false
	player.caught = false
	player.camcorder.degrade = 0.0
	_drone.stop()
	_drone.volume_db = -80.0
	_trail.clear()
	_echo.clear()
	Game.duck_extra = 0.0
	rig.skip_gap = Vector2(0.18, 0.42)
	if rig is CrawlerRig:
		(rig as CrawlerRig).open_eyes(false)
		(rig as CrawlerRig).look_at_point(Vector3.INF, 0.0)
	_gone()
	_next = Game.clock + _rng.randf_range(GAP[0], GAP[1])


## Your view while it has you: turned to face it.
class DeathInput:
	extends PlayerInput
	var target: Node3D
	var look_h := 1.9

	func update_move(_p: Node, _d: float) -> void:
		move = Vector2.ZERO
		sprint = false
		crouch = false
		camcorder = true

	func update_look(p: Node, delta: float) -> void:
		var pl := p as Player
		look_delta = Vector2.ZERO
		if target == null:
			return
		var to := (target.global_position + Vector3(0, look_h, 0)) - pl.cam.global_position
		var want_yaw := atan2(-to.x, -to.z)
		var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
		var dy := angle_difference(pl.yaw, want_yaw)
		look_delta = Vector2(-dy * (1.0 - exp(-10.0 * delta)), (want_pitch - pl.pitch) * (1.0 - exp(-8.0 * delta)))
