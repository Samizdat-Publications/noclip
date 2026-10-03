class_name Landing
extends Node3D
## Where you wake (D050). On depth 1 it is the Landing: Halden's forward post, a work light on a
## stand, their tape crates, a steel locker that holds the kit you have bought, and a freight lift
## cage standing in the middle of the office with no shaft round it (it goes down anyway). On deeper
## depths only the cage is there: the way back up, if you want to cash the tape in.

var locker_at := Vector3.INF
var cage_at := Vector3.INF
var _bulb: OmniLight3D
var _t := 0.0


func setup(space: Level0World, spawn: Transform3D, full: bool) -> void:
	name = "landing"
	var p := spawn.origin
	var fwd := -spawn.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	# The cage behind you (where you came from), the locker to one side, both on open floor.
	var cage := _spot(space, p, [-fwd * 2.4, -fwd * 2.0 + right * 1.6, -fwd * 2.0 - right * 1.6, right * 2.6, -right * 2.6,
		-fwd * 2.6 + right * 0.4, -fwd * 2.6 - right * 0.4, -fwd * 3.4], 0.55)
	if cage != Vector3.INF:
		_build_cage(cage, (p - cage).normalized())
		cage_at = cage
	if not full:
		return
	# Walls only answer rays once physics has seen them (the chunks were built this frame).
	await space.get_tree().physics_frame
	await space.get_tree().physics_frame
	if not is_inside_tree():
		return
	# The locker stands against a wall a step from you, the crates beside it.
	var lk := Vector3.INF
	var lk_face := Vector3.ZERO
	for o in [fwd * 0.9, -fwd * 0.4, fwd * 1.8]:
		for sd in [right, -right]:
			var hit := _wall(space, p + o, sd, 3.0)
			if hit != Vector3.INF and (cage == Vector3.INF or hit.distance_to(cage) > 1.4):
				lk = hit - sd * 0.27
				lk_face = -sd
				break
		if lk != Vector3.INF:
			break
	if lk != Vector3.INF:
		_build_locker(lk, lk_face)
		locker_at = lk
		var along := lk_face.cross(Vector3.UP)
		_prop("res://assets/props/level0/prop_tape_crate.glb", lk + along * 0.62 + lk_face * 0.05, 0.15)
		_prop("res://assets/props/level0/prop_tape_crate.glb", lk + along * 0.62 + lk_face * 0.05 + Vector3(0, 0.32, 0), 0.25)
	# The work light on the other wall, a little ahead, aimed back at the locker.
	var wl := Vector3.INF
	var wdir := lk_face if lk != Vector3.INF else right
	for o in [fwd * 2.4, fwd * 1.6, fwd * 3.2]:
		var hw := _wall(space, p + o, wdir, 3.0)
		if hw != Vector3.INF:
			wl = hw - wdir * 0.35
			break
	if wl != Vector3.INF:
		_prop("res://assets/props/level0/prop_worklight_sf.glb", wl, atan2((p - wl).x, (p - wl).z))
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.76, 0.5)
		sl.light_energy = 2.2
		sl.spot_range = 7.0
		sl.spot_angle = 50.0
		sl.shadow_enabled = true
		sl.light_volumetric_fog_energy = 1.2
		add_child(sl)
		sl.global_position = wl + Vector3(0, 1.6, 0)
		var aim := (p + lk) * 0.5 if lk != Vector3.INF else p
		sl.look_at(aim + Vector3(0, 0.2, 0), Vector3.UP)


## Where a wall is along dir from p (at hip height), or INF.
func _wall(space: Level0World, p: Vector3, dir: Vector3, maxd: float) -> Vector3:
	var o := p + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(o, o + dir * maxd)
	q.collision_mask = 1
	var hit := space.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	var h: Vector3 = hit["position"]
	return Vector3(h.x, p.y, h.z)


## The first offset from p whose spot (radius r) is open floor and clear of the given points.
func _spot(space: Level0World, p: Vector3, offs: Array, r: float, a := Vector3.INF, b := Vector3.INF) -> Vector3:
	for o in offs:
		var q: Vector3 = p + o
		var ok := true
		for k in 8:
			var e := q + Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * r
			if not space.is_walkable(e):
				ok = false
				break
		if ok and a != Vector3.INF and q.distance_to(a) < 1.3:
			ok = false
		if ok and b != Vector3.INF and q.distance_to(b) < 0.9:
			ok = false
		if ok:
			return Vector3(q.x, p.y, q.z)
	return Vector3.INF


func _mat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, sz: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)


func _prop(path: String, at: Vector3, yaw: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var n := (load(path) as PackedScene).instantiate() as Node3D
	add_child(n)
	n.global_position = at
	n.rotation.y = yaw


## A freight lift cage: steel bars on three sides, its gate open toward you, a diamond-plate floor,
## an amber bulb in a wire guard, and HALDEN stencilled on the header.
func _build_cage(at: Vector3, face: Vector3) -> void:
	var root := Node3D.new()
	root.name = "lift_cage"
	add_child(root)
	root.global_position = at
	root.rotation.y = atan2(face.x, face.z)
	var steel := _mat(Color(0.2, 0.21, 0.2), 0.55, 0.7)
	var plate := _mat(Color(0.32, 0.32, 0.31), 0.45, 0.8)
	var paint := _mat(Color(0.62, 0.48, 0.12), 0.7, 0.2)   # worn safety-yellow corners
	var w := 1.3
	var h := 2.3
	_box(root, Vector3(w, 0.05, w), Vector3(0, 0.025, 0), plate)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(root, Vector3(0.07, h, 0.07), Vector3(sx * w * 0.5, h * 0.5, sz * w * 0.5), paint)
	_box(root, Vector3(w, 0.08, w), Vector3(0, h, 0), steel)
	# bars: back (-z) and both sides; the front (+z, toward you) is the open gate
	var n := 9
	for k in n:
		var t := -w * 0.5 + w * (k + 0.5) / n
		_box(root, Vector3(0.022, h, 0.022), Vector3(t, h * 0.5, -w * 0.5), steel)
		_box(root, Vector3(0.022, h, 0.022), Vector3(-w * 0.5, h * 0.5, t), steel)
		_box(root, Vector3(0.022, h, 0.022), Vector3(w * 0.5, h * 0.5, t), steel)
	for y in [0.9, 1.8]:
		_box(root, Vector3(w, 0.04, 0.04), Vector3(0, y, -w * 0.5), steel)
		_box(root, Vector3(0.04, 0.04, w), Vector3(-w * 0.5, y, 0), steel)
		_box(root, Vector3(0.04, 0.04, w), Vector3(w * 0.5, y, 0), steel)
	# the folded gate on one side of the opening
	for k in 4:
		_box(root, Vector3(0.025, h - 0.1, 0.025), Vector3(w * 0.5 - 0.06 - k * 0.05, (h - 0.1) * 0.5, w * 0.5), steel)
	# the control box on the right post
	_box(root, Vector3(0.14, 0.24, 0.08), Vector3(w * 0.5 - 0.12, 1.25, w * 0.5 - 0.1), _mat(Color(0.5, 0.42, 0.12), 0.6, 0.3))
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	bulb.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(3.0, 1.6, 0.5)
	bulb.material_override = bm
	bulb.position = Vector3(0, h - 0.12, 0)
	root.add_child(bulb)
	_bulb = OmniLight3D.new()
	_bulb.light_color = Color(1.0, 0.62, 0.25)
	_bulb.light_energy = 1.1
	_bulb.omni_range = 4.0
	_bulb.shadow_enabled = true
	_bulb.position = Vector3(0, h - 0.2, 0)
	root.add_child(_bulb)
	var sign := Label3D.new()
	sign.text = "HALDEN   LIFT  2"
	sign.font_size = 40
	sign.pixel_size = 0.0035
	sign.modulate = Color(0.08, 0.07, 0.05)
	sign.position = Vector3(0, h - 0.04, w * 0.5 + 0.045)
	sign.double_sided = false
	root.add_child(sign)


## A dented steel locker, olive grey, HALDEN stencilled on the door, a padlock hasp hanging open.
func _build_locker(at: Vector3, face: Vector3) -> void:
	var root := Node3D.new()
	root.name = "halden_locker"
	add_child(root)
	root.global_position = at
	root.rotation.y = atan2(face.x, face.z)
	var body := _mat(Color(0.36, 0.38, 0.32), 0.6, 0.55)
	_box(root, Vector3(0.62, 1.86, 0.5), Vector3(0, 0.93, 0), body)
	_box(root, Vector3(0.006, 1.7, 0.01), Vector3(0, 0.93, 0.252), _mat(Color(0.05, 0.05, 0.05), 0.9))
	for k in 5:
		_box(root, Vector3(0.22, 0.012, 0.01), Vector3(-0.15, 1.62 - k * 0.035, 0.252), _mat(Color(0.08, 0.08, 0.07), 0.9))
		_box(root, Vector3(0.22, 0.012, 0.01), Vector3(0.15, 1.62 - k * 0.035, 0.252), _mat(Color(0.08, 0.08, 0.07), 0.9))
	_box(root, Vector3(0.03, 0.1, 0.03), Vector3(0.04, 1.0, 0.27), _mat(Color(0.6, 0.55, 0.4), 0.4, 0.9))
	var sign := Label3D.new()
	sign.text = "HALDEN\nFIELD KIT"
	sign.font_size = 32
	sign.pixel_size = 0.003
	sign.modulate = Color(0.85, 0.82, 0.7)
	sign.position = Vector3(0, 1.25, 0.257)
	sign.double_sided = false
	root.add_child(sign)


func _process(delta: float) -> void:
	_t += delta
	if _bulb:
		_bulb.light_energy = 1.1 * (0.92 + 0.08 * sin(_t * 9.0))
