class_name FixturePool
extends Node3D
## Lights and sound for the infinite level. A streamed level holds well over a thousand
## troffers; only the ones near the player get a real shadowed SpotLight3D, a hum and (if the
## tube is failing) a buzz and starter ticks. Panels farther out keep their glowing lens and
## the ceiling glow, and their light fades out with distance before it is taken away, so the
## hand-over is invisible. Re-assignment runs on the game clock, so captures stay deterministic.

const LIGHTS := 112
const LIGHT_R := 23.0
const FADE_BEGIN := 16.0
const FADE_LEN := 6.0
const HUMS := 14
const HUM_R := 9.0
const BUZZES := 6
const BUZZ_R := 14.0
const PERIOD := 0.2

var fixtures: Array = []      # every ceiling fixture of the loaded chunks
var listener := Vector3.ZERO
# A second, smaller pool lights the hall inside a storeroom (PortalRoom, D036).
var light_cap := LIGHTS
var hum_cap := HUMS
var layer_bits := 1           # render layers of its lights (camera cull masks hide another space's)
var enabled := true           # false: everything handed back, nothing lent
var _was_enabled := true

var _lights: Array[SpotLight3D] = []
var _hums: Array[AudioStreamPlayer3D] = []
var _buzzes: Array[AudioStreamPlayer3D] = []
var _ticks: Array[AudioStreamPlayer3D] = []
var _hum_streams: Array = []
var _buzz_stream: AudioStream
var _tick_streams: Array = []
var _t := 0.0
var _base_range := float(Game.opts.get("spot_range", "7"))


func _ready() -> void:
	top_level = true
	for k in light_cap:
		var l := Fixture.make_ceiling_light()
		l.distance_fade_begin = FADE_BEGIN
		l.distance_fade_length = FADE_LEN
		l.layers = layer_bits
		l.visible = false
		add_child(l)
		_lights.append(l)
	_hum_streams = [_snd("hum_fixture_a"), _snd("hum_fixture_b")].filter(func(s): return s != null)
	_buzz_stream = _snd("buzz_failing")
	for t in 4:
		var s := _snd("tube_tick_%02d" % (t + 1))
		if s:
			_tick_streams.append(s)
	for k in hum_cap:
		var hp := _player(1.1, 9.0)
		hp.bus = &"Hum"
		_hums.append(hp)
	for k in BUZZES:
		_buzzes.append(_player(1.4, 14.0))
		var tk := _player(1.6, 16.0)
		tk.volume_db = -6.0
		_ticks.append(tk)


func _snd(name: String) -> AudioStream:
	var p := "res://assets/audio/level0/" + name + ".wav"
	return load(p) if ResourceLoader.exists(p) else null


func _player(unit: float, maxd: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"World"
	p.unit_size = unit
	p.max_distance = maxd
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	add_child(p)
	return p


## The player was moved by `offset` between identical places: shift every lent light and sound
## by the same offset and hand it to the matching panel (twin_of), so the lighting and the hum
## carry on unbroken. Anything without a twin is taken back and re-lent on the next update.
func carry_over(offset: Vector3, twin_of: Callable) -> void:
	listener += offset
	var moves := []
	for fx in fixtures:
		if not is_instance_valid(fx):
			continue
		if fx.light == null and fx.hum == null and fx.buzz == null:
			continue
		var tw: Fixture = twin_of.call(fx)
		moves.append([fx, tw, {"light": fx.light, "hum": fx.hum, "buzz": fx.buzz, "tick": fx.tick_player}])
	# Take everything back first, then hand it out, so nothing is moved twice.
	for m in moves:
		var f0: Fixture = m[0]
		f0.light = null
		f0.hum = null
		f0.buzz = null
		f0.tick_player = null
	for m in moves:
		var tw: Fixture = m[1]
		var held: Dictionary = m[2]
		if tw == null:
			for key in held:
				var obj = held[key]
				if obj == null:
					continue
				if obj is Light3D:
					(obj as Light3D).visible = false
				elif obj is AudioStreamPlayer3D:
					(obj as AudioStreamPlayer3D).stop()
			continue
		for key in held:
			var obj = held[key]
			if obj is Node3D:
				(obj as Node3D).global_position += offset
		tw.light = held["light"]
		tw.hum = held["hum"]
		tw.buzz = held["buzz"]
		tw.tick_player = held["tick"]
		tw.apply()
	_t = 0.0


## A fixture is leaving (its chunk unloads): give back anything it holds.
func release(fx: Fixture) -> void:
	if fx.light and fx.light in _lights:
		fx.light.visible = false
		fx.light = null
	if fx.hum and fx.hum in _hums:
		fx.hum.stop()
		fx.hum = null
	if fx.buzz and fx.buzz in _buzzes:
		fx.buzz.stop()
		fx.buzz = null
	if fx.tick_player and fx.tick_player in _ticks:
		fx.tick_player = null


func _process(delta: float) -> void:
	if not enabled:
		if _was_enabled:
			for fx in fixtures:
				if is_instance_valid(fx):
					release(fx)
					fx.apply()
		_was_enabled = false
		return
	_was_enabled = true
	_t -= delta
	if _t > 0.0:
		return
	_t = PERIOD
	var lit := []
	var hum := []
	var buzz := []
	for fx in fixtures:
		if not is_instance_valid(fx):
			continue
		var p: Vector3 = fx.global_position
		var d := Vector2(p.x - listener.x, p.z - listener.z).length()
		var dark: bool = fx.state == Fixture.State.DEAD and fx.level < 0.002
		if d < LIGHT_R and not dark:
			lit.append([d, fx])
		if d < HUM_R and not dark:
			hum.append([d, fx])
		if d < BUZZ_R and fx.is_failing():
			buzz.append([d, fx])
	_assign(lit, light_cap, "light", _lights)
	_assign(hum, hum_cap, "hum", _hums)
	_assign(buzz, BUZZES, "buzz", _buzzes)
	_occlude()


## A hum or buzz behind a wall sounds muffled and quieter (M3, D026): one ray per sound from
## the listener's head, every PERIOD.
func _occlude() -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var head := listener + Vector3(0, 1.6, 0)
	for pl in _hums + _buzzes:
		if not pl.playing:
			continue
		var q := PhysicsRayQueryParameters3D.create(head, pl.global_position - Vector3(0, 0.15, 0))
		var hit := space.intersect_ray(q)
		var occ := not hit.is_empty()
		pl.attenuation_filter_cutoff_hz = 900.0 if occ else 5000.0
		pl.set_meta("occ_db", -7.0 if occ else 0.0)
	for fx in fixtures:
		if is_instance_valid(fx) and (fx.hum != null or fx.buzz != null):
			fx.apply()


func _assign(cands: Array, cap: int, slot: String, pool: Array) -> void:
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var want := {}
	for k in mini(cap, cands.size()):
		want[cands[k][1]] = true
	# Free what is no longer wanted.
	var owner_of := {}
	for fx in fixtures:
		if not is_instance_valid(fx):
			continue
		var held = fx.get(slot)
		if held != null and held in pool:
			if want.has(fx):
				owner_of[held] = fx
			else:
				_drop(fx, slot)
	var free := pool.filter(func(x): return not owner_of.has(x))
	for fx in want.keys():
		if fx.get(slot) != null:
			continue
		if free.is_empty():
			break
		var obj = free.pop_back()
		_give(fx, slot, obj)


func _drop(fx: Fixture, slot: String) -> void:
	match slot:
		"light":
			fx.light.visible = false
			fx.light = null
		"hum":
			fx.hum.stop()
			fx.hum = null
		"buzz":
			fx.buzz.stop()
			fx.buzz = null
			if fx.tick_player:
				fx.tick_player = null


func _give(fx: Fixture, slot: String, obj) -> void:
	var top := fx.global_position + Vector3(0, fx.ceiling_h, 0)
	match slot:
		"light":
			var l: SpotLight3D = obj
			l.global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0 if fx.along_x else PI * 0.5, 0)), top - Vector3(0, 0.004, 0))
			l.spot_range = _base_range * fx.ceiling_h / 2.6
			l.light_color = fx.tint
			fx.light = l
		"hum":
			var h: AudioStreamPlayer3D = obj
			h.global_position = top - Vector3(0, 0.05, 0)
			if not _hum_streams.is_empty():
				h.stream = _hum_streams[fx.variant % _hum_streams.size()]
			# Neighbors a few percent apart beat against each other, so the hum wavers as you
			# walk instead of one steady tone (L099).
			h.pitch_scale = 1.0 + (fx.variant % 11 - 5) * 0.006
			fx.hum = h
			h.play(fx.audio_offset)
		"buzz":
			var b: AudioStreamPlayer3D = obj
			b.global_position = top - Vector3(0, 0.05, 0)
			b.stream = _buzz_stream
			fx.buzz = b
			if _buzz_stream:
				b.play(fx.audio_offset * 0.75)
			var i := _buzzes.find(b)
			if i >= 0 and not _tick_streams.is_empty():
				var tk := _ticks[i]
				tk.global_position = b.global_position
				tk.stream = _tick_streams[fx.variant % _tick_streams.size()]
				fx.tick_player = tk
	fx.apply()
