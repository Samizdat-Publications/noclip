class_name Flare
extends Node3D
## A Halden road flare (D050): thrown a few meters ahead, it lands and burns red for LIFE seconds.
## The thing that hunts you will not come into red light (OccupantHunter checks Level0World.in_flare),
## so a flare is a safe pool for as long as it burns, and the only real light in the dark depths.

const LIFE := 40.0
const RADIUS := 4.2

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _light: OmniLight3D
var _stick: MeshInstance3D
var _burn: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var landed := false
var out := false
var _out_t := 0.0
var life_override := 0.0     # > 0: burns this long instead of LIFE (Halden's last stand)


func throw_from(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	global_position = from
	_rng.seed = hash("flare:%d" % Game.frame)


func _ready() -> void:
	_stick = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = 0.24
	_stick.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.08, 0.05)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.2, 0.1)
	m.emission_energy_multiplier = 2.0
	_stick.material_override = m
	_stick.rotation = Vector3(PI * 0.5, 0, 0.3)
	add_child(_stick)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	tip.mesh = sm
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(4.0, 1.4, 0.9)
	tip.material_override = tm
	tip.position = Vector3(0, 0, -0.12)
	_stick.add_child(tip)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.16, 0.08)
	_light.light_energy = 3.2
	_light.omni_range = 7.5
	_light.omni_attenuation = 1.1
	_light.shadow_enabled = true
	_light.light_volumetric_fog_energy = 3.0
	_light.position = Vector3(0, 0.25, 0)
	add_child(_light)
	_burn = AudioStreamPlayer3D.new()
	_burn.bus = &"World"
	_burn.unit_size = 2.0
	_burn.max_distance = 22.0
	add_child(_burn)
	_play("flare_ignite_01", -2.0, false)


func _play(nm: String, db: float, loop: bool) -> void:
	var p := "res://assets/audio/descent/%s.wav" % nm
	if not ResourceLoader.exists(p):
		return
	var s := load(p) as AudioStreamWAV
	if loop:
		s = s.duplicate() as AudioStreamWAV
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	_burn.stream = s
	_burn.volume_db = db
	_burn.play()


func _process(delta: float) -> void:
	_t += delta
	if not landed:
		var k := clampf(_t / 0.55, 0.0, 1.0)
		var p := _from.lerp(_to, k)
		p.y += sin(k * PI) * 0.9
		global_position = p
		_stick.rotation.x += delta * 14.0
		if k >= 1.0:
			landed = true
			_stick.rotation = Vector3(PI * 0.5, _rng.randf() * TAU, 0.0)
			_stick.position.y = 0.02
			_play("flare_land_01", -4.0, false)
			get_tree().create_timer(0.8).timeout.connect(_start_burn)
	# It sputters: a fast random flicker over a slow breathing swell.
	var life_s := life_override if life_override > 0.0 else LIFE
	var life := clampf(1.0 - (_t - 0.55) / life_s, 0.0, 1.0)
	var flick := 0.82 + 0.18 * _rng.randf() + 0.08 * sin(_t * 3.1)
	if life < 0.08:
		flick *= 0.4 + 0.6 * float(_rng.randf() > 0.4)
	if out:
		_out_t += delta
		_light.light_energy = maxf(0.0, 3.2 * flick * (1.0 - _out_t / 1.5) * 0.3)
		if _out_t > 2.5:
			queue_free()
		return
	_light.light_energy = 3.2 * flick * (1.0 if life > 0.0 else 0.0)
	if _t > life_s + 0.55:
		out = true
		_out_t = 0.0
		_play("flare_die_01", -6.0, false)


func age() -> float:
	return maxf(_t - 0.55, 0.0)


func _start_burn() -> void:
	if not out:
		_play("flare_burn_loop", -8.0, true)


## Burning, and close enough to p to keep it off.
func guards(p: Vector3) -> bool:
	return landed and not out and Vector2(p.x - global_position.x, p.z - global_position.z).length() < RADIUS and absf(p.y - global_position.y) < 2.0
