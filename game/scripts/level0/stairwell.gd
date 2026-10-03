class_name Stairwell
extends Node3D
## The way down (D050): one storeroom in each depth is a stairwell. Its door carries a lit sign that
## says EXIT with an arrow pointing at the floor; inside, the floor is gone and concrete stairs go
## down into the dark to a landing lit by one red emergency lamp, and on through a black doorway. Cold
## air moans up out of it, so you can hear it a few rooms away. Step in and you go down (the
## RunDirector plays the long stairs and builds the next depth).

var door_world := Vector3.ZERO      # the middle of the storeroom's doorway, on the floor
var n := Vector2.ZERO               # out of the doorway, into the room in front of it
var block := Rect2()                # the storeroom, world plan
var hole := Rect2()                 # the stairs, world plan
var _lamp: OmniLight3D
var _lamp_mesh: MeshInstance3D
var _t := 0.0


func setup(origin: Vector3, cl: Dictionary) -> void:
	name = "stairwell"
	var d: Vector2 = cl["door"]
	n = cl["n"]
	door_world = origin + Vector3(d.x, 0.0, d.y)
	var b: Array = cl["block"]
	block = Rect2(origin.x + b[0], origin.z + b[1], b[2] - b[0], b[3] - b[1])
	var h: Array = cl["hole"]
	hole = Rect2(origin.x + h[0], origin.z + h[1], h[2] - h[0], h[3] - h[1])
	_build()


## In the doorway or past it: you are on your way down.
func contains(p: Vector3) -> bool:
	if absf(p.y) > 1.5:
		return false
	# In the doorway (a step from its middle, on the threshold) or anywhere past it.
	var at := Vector2(p.x - door_world.x, p.z - door_world.z)
	var into := -at.dot(n)
	return block.grow(-0.05).has_point(Vector2(p.x, p.z)) or (at.length() < 0.7 and into > -0.15)


func _mat(c: Color, rough: float = 0.92) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(sz: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	add_child(mi)
	return mi


func _build() -> void:
	var concrete := _mat(Color(0.36, 0.35, 0.33))
	var wall := _mat(Color(0.3, 0.3, 0.29))
	var nose := _mat(Color(0.55, 0.5, 0.3), 0.6)      # worn yellow safety paint on each step's edge
	var black := _mat(Color(0.0, 0.0, 0.0), 1.0)
	var rail := _mat(Color(0.42, 0.42, 0.43), 0.45)
	rail.metallic = 0.8
	var c := Vector3(hole.get_center().x, 0.0, hole.get_center().y)
	# Down is away from the door: -n. Across is perpendicular.
	var down := Vector3(-n.x, 0.0, -n.y)
	var across := Vector3(down.z, 0.0, -down.x)
	var along: float = hole.size.x if absf(n.x) > 0.5 else hole.size.y
	var wide: float = hole.size.y if absf(n.x) > 0.5 else hole.size.x
	var depth := 3.2
	# The shaft: four walls from the floor down past the landing.
	var yaw := atan2(down.x, down.z)
	var basis := Basis(Vector3.UP, yaw)
	var shaft := Node3D.new()
	shaft.position = Vector3(c.x, 0.0, c.z)
	shaft.basis = basis
	add_child(shaft)
	var put := func(sz: Vector3, local: Vector3, m: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz
		mi.mesh = bm
		mi.material_override = m
		mi.position = local
		shaft.add_child(mi)
		return mi
	# local frame: +z is down the stairs, +x across
	put.call(Vector3(0.08, depth, along + 0.16), Vector3(-wide * 0.5 - 0.04, -depth * 0.5, 0), wall)
	put.call(Vector3(0.08, depth, along + 0.16), Vector3(wide * 0.5 + 0.04, -depth * 0.5, 0), wall)
	put.call(Vector3(wide, depth, 0.08), Vector3(0, -depth * 0.5, -along * 0.5 - 0.04), wall)
	# the far wall has the black doorway the stairs carry on through
	var dw := minf(1.0, wide - 0.3)
	var side := (wide - dw) * 0.5
	put.call(Vector3(side, depth, 0.08), Vector3(-wide * 0.5 + side * 0.5, -depth * 0.5, along * 0.5 + 0.04), wall)
	put.call(Vector3(side, depth, 0.08), Vector3(wide * 0.5 - side * 0.5, -depth * 0.5, along * 0.5 + 0.04), wall)
	put.call(Vector3(dw, depth - 2.95, 0.08), Vector3(0, -(depth - 2.95) * 0.5, along * 0.5 + 0.04), wall)
	put.call(Vector3(dw, 2.1, 0.02), Vector3(0, -depth + 1.05, along * 0.5 + 0.12), black)
	# Steps: 0.18 rise, run to fill the opening, then the landing.
	var steps := 7
	var run := (along - 0.9) / steps
	for k in steps:
		var y := -0.18 * (k + 1)
		var z := -along * 0.5 + run * (k + 0.5)
		put.call(Vector3(wide, 0.3, run), Vector3(0, y - 0.15, z), concrete)
		put.call(Vector3(wide, 0.012, 0.05), Vector3(0, y + 0.006, z - run * 0.5 + 0.025), nose)
	var land_y := -0.18 * steps
	put.call(Vector3(wide, 0.3, 0.9), Vector3(0, land_y - 0.15, along * 0.5 - 0.45), concrete)
	# and on below the landing, out of sight through the black doorway
	put.call(Vector3(wide, 0.3, 0.9), Vector3(0, -depth - 0.15, along * 0.5 - 0.45), black)
	# a handrail down the left side
	var rl: MeshInstance3D = put.call(Vector3(0.04, 0.04, along * 1.08), Vector3(-wide * 0.5 + 0.08, -0.18 * steps * 0.5 + 0.9, 0), rail)
	rl.rotation.x = atan2(0.18 * steps, along - 0.9)
	# The red emergency lamp over the black doorway, flickering a little.
	_lamp_mesh = put.call(Vector3(0.22, 0.1, 0.08), Vector3(0, land_y + 2.3, along * 0.5 - 0.02), _mat(Color(0.2, 0.02, 0.02)))
	var em := _mat(Color(0.3, 0.02, 0.02))
	em.emission_enabled = true
	em.emission = Color(1.0, 0.12, 0.08)
	em.emission_energy_multiplier = 4.0
	_lamp_mesh.material_override = em
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.18, 0.12)
	_lamp.light_energy = 1.6
	_lamp.omni_range = 4.6
	_lamp.omni_attenuation = 1.3
	_lamp.light_volumetric_fog_energy = 2.0
	_lamp.shadow_enabled = true
	_lamp.position = Vector3(0, land_y + 2.1, along * 0.5 - 0.25)
	shaft.add_child(_lamp)
	# Outside: the sign over the door. EXIT, and under it an arrow pointing at the floor.
	var out := Vector3(n.x, 0.0, n.y)
	var sign_pos := door_world + out * 0.13 + Vector3(0, 2.32, 0)
	var sign_yaw := atan2(out.x, out.z)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.62, 0.3, 0.06)
	plate.mesh = pm
	plate.material_override = _mat(Color(0.08, 0.02, 0.02), 0.5)
	plate.position = sign_pos - out * 0.03
	plate.rotation.y = sign_yaw
	add_child(plate)
	var txt := Label3D.new()
	txt.text = "EXIT\nv"
	txt.font_size = 56
	txt.pixel_size = 0.0028
	txt.line_spacing = -18.0
	txt.modulate = Color(2.4, 0.35, 0.25)
	txt.shaded = false
	txt.double_sided = false
	txt.outline_size = 0
	txt.position = sign_pos + out * 0.002
	txt.rotation.y = sign_yaw
	add_child(txt)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.25, 0.18)
	glow.light_energy = 0.5
	glow.omni_range = 1.8
	glow.shadow_enabled = false
	glow.position = sign_pos + out * 0.3 - Vector3(0, 0.15, 0)
	add_child(glow)
	# The draft: cold air moaning up the stairs, heard a few rooms away.
	var path := "res://assets/audio/descent/stair_draft_loop.wav"
	if ResourceLoader.exists(path):
		var st := load(path) as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = int(st.get_length() * st.mix_rate)
		var ap := AudioStreamPlayer3D.new()
		ap.stream = st
		ap.bus = &"World"
		ap.unit_size = 4.0
		ap.max_distance = 34.0
		ap.volume_db = 2.0
		ap.autoplay = true
		ap.position = Vector3(c.x, -0.5, c.z)
		add_child(ap)


func _process(delta: float) -> void:
	_t += delta
	if _lamp:
		var f := 1.0 if fmod(_t * 1.7, 5.3) > 0.18 else 0.35
		_lamp.light_energy = 1.6 * f
