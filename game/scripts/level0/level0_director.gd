class_name Level0Director
extends Node
## The run-level life of Level 0, shared by the hero slice and the infinite level: the room
## tone, distant thuds, and the one scripted dread beat per run (the lights ahead die one by
## one toward you, their hum dying with them, and later stutter back on).
## The owning Space keeps `fixtures` current (all fixtures near the player).

var space: Space
var fixtures: Array = []
var listener := Vector3.ZERO
var view_fwd := Vector3.FORWARD

var _rng_amb: RandomNumberGenerator
var _rng_evt: RandomNumberGenerator
var _thud_player: AudioStreamPlayer3D
var _thud_timer := 0.0
var _event_t := 1e9
var _event_phase := 0
var _event_restore_t := 0.0
var _event_killed: Array = []
var _sag_start := -100.0
var _sag_len := 0.0
var _sag_next := 0.0

const SND := "res://assets/audio/level0/"


func _ready() -> void:
	_rng_amb = Game.rng("level0:ambience")
	var tone := _snd("room_tone")
	if tone:
		var p := AudioStreamPlayer.new()
		p.stream = tone
		p.volume_db = -14.0
		p.bus = &"Hum"
		p.autoplay = true
		add_child(p)
	_thud_player = AudioStreamPlayer3D.new()
	_thud_player.bus = &"World"
	_thud_player.unit_size = 6.0
	_thud_player.max_distance = 60.0
	_thud_player.volume_db = -4.0
	add_child(_thud_player)
	_thud_timer = _rng_amb.randf_range(18.0, 40.0)
	_sag_next = _rng_amb.randf_range(35.0, 60.0)
	_rng_evt = Game.rng("level0:events")
	_event_t = _rng_evt.randf_range(26.0, 46.0) if not Game.opts.has("no-events") else 1e9


func _snd(name: String) -> AudioStream:
	var p := SND + name + ".wav"
	if ResourceLoader.exists(p):
		return load(p)
	return null


func _process(delta: float) -> void:
	_run_events()
	_update_hum()
	_thud_timer -= delta
	if _thud_timer <= 0.0:
		_thud_timer = _rng_amb.randf_range(25.0, 60.0)
		var thuds := []
		for k in 3:
			var s := _snd("distant_thud_%02d" % (k + 1))
			if s:
				thuds.append(s)
		# M3: a door far away, a chair rolling, a ballast, steps that are not yours, knocks in a wall.
		for nm in ["distant_door_01", "distant_chair_01", "distant_ballast_01", "distant_steps_01", "distant_knock_01", "distant_hum_drop_01"]:
			var s2 := _snd(nm)
			if s2:
				thuds.append(s2)
		if thuds.size() > 0:
			var ang := _rng_amb.randf() * TAU
			_thud_player.global_position = listener + Vector3(cos(ang), 0.0, sin(ang)) * _rng_amb.randf_range(16.0, 26.0) + Vector3(0, 1.0, 0)
			_thud_player.stream = thuds[_rng_amb.randi() % thuds.size()]
			_thud_player.pitch_scale = _rng_amb.randf_range(0.85, 1.05)
			_thud_player.play()


## The building's hum is never steady (L099): it drifts a few dB over tens of seconds, and every
## minute or two the power sags and the hum falls away for a few seconds of near silence, with a
## ballast clunk somewhere, then comes back.
func _update_hum() -> void:
	var b := AudioServer.get_bus_index("Hum")
	if b < 0:
		return
	var t := Game.clock
	var wob := sin(t * 0.19 + 1.3) * 1.3 + sin(t * 0.061 + 0.4) * 1.7
	if t >= _sag_next:
		_sag_start = t
		_sag_len = _rng_amb.randf_range(3.5, 8.0)
		_sag_next = t + _sag_len + _rng_amb.randf_range(50.0, 110.0)
		var s := _snd("distant_hum_drop_01")
		if s:
			var ang := _rng_amb.randf() * TAU
			_thud_player.global_position = listener + Vector3(cos(ang), 0.0, sin(ang)) * 12.0 + Vector3(0, 2.0, 0)
			_thud_player.stream = s
			_thud_player.pitch_scale = _rng_amb.randf_range(0.9, 1.0)
			_thud_player.play()
	var u := t - _sag_start
	var sag := smoothstep(0.0, 1.4, u) * (1.0 - smoothstep(_sag_len, _sag_len + 2.8, u))
	AudioServer.set_bus_volume_db(b, -3.0 + wob - 13.0 * sag)


func _run_events() -> void:
	if _event_phase == 0 and Game.clock >= _event_t:
		var cand := []
		for fx in fixtures:
			if not is_instance_valid(fx):
				continue
			if fx.state != Fixture.State.ON and fx.state != Fixture.State.PULSE and fx.state != Fixture.State.DROPOUT:
				continue
			if fx.mount != Fixture.Mount.CEILING:
				continue
			var to := Vector3(fx.global_position.x - listener.x, 0.0, fx.global_position.z - listener.z)
			var d := to.length()
			if d < 3.0 or d > 17.0:
				continue
			if to.normalized().dot(view_fwd) < 0.82:
				continue
			cand.append([d, fx])
		if cand.size() < 3:
			_event_t += 3.0   # nothing good in view yet; try again shortly
			return
		cand.sort_custom(func(a, b): return a[0] > b[0])
		var k := 0
		for c in cand:
			(c[1] as Fixture).kill(0.15 + k * _rng_evt.randf_range(0.32, 0.5))
			_event_killed.append(c[1])
			k += 1
		space.attention_point = (cand[0][1] as Fixture).global_position
		space.attention_until = Game.clock + 4.0 + k * 0.4
		_event_phase = 1
		_event_restore_t = Game.clock + _rng_evt.randf_range(12.0, 18.0)
	elif _event_phase == 1 and Game.clock >= _event_restore_t:
		var k := 0
		for fx in _event_killed:
			if is_instance_valid(fx):
				fx.restore(k * _rng_evt.randf_range(0.2, 0.6) + _rng_evt.randf_range(0.0, 0.3))
			k += 1
		_event_phase = 2
