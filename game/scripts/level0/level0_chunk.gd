class_name Level0Chunk
extends Node3D
## Builds one piece of Level 0 from a layout dictionary (schema: data/level0_hero.json, in
## local meters): walls, doors, ceiling grid and troffers, decals, props, splice errors,
## collision and a navigation grid, with seeded decay on top (which tubes are dead or
## failing, ceiling leaks, stains, wet carpet, missing tiles).
## The hero slice is one 30 x 30 m chunk (Level0Hero); the infinite level streams 24 x 24 m
## chunks from Level0Gen (Level0World). Everything is local to this node, so the chunk is
## simply positioned at its world origin; world-space shader noise keeps neighbors seamless.

const SND := "res://assets/audio/level0/"
const TEXD := "res://assets/textures/level0/"
const CELL := 0.2
const AGENT_R := 0.34
const TILE := 0.6
const WET_SCALE := 0.13
const WET_LO := 0.56
const WET_HI := 0.70

var L: Dictionary
var salt := ""                 # prefixes every random stream, so chunks differ
var own_far_edges := true      # build the T-bar lines on the far (east/south) edges too
var pooled := false            # lights and hum come from a FixturePool instead of each fixture
var H: float = 2.6
var T: float = 0.2
var DH: float = 2.1
var extent := Vector2(30, 30)
var mats: Dictionary
var fixtures: Array[Fixture] = []
var field: FixtureField
var seed_offset := Vector2.ZERO
var solids: Array[Rect2] = []
var _edge_solids: Array[Rect2] = []   # built by a neighbor chunk: no collision here
var leaks: Array[Vector2] = []
var flood := Rect2(-100, -100, 1, 1)
var astar: AStarGrid2D
var _grid_n := Vector2i.ZERO
var _audio_timer := 0.0
var _listener_pos := Vector3.ZERO
var _fallen_tile := Vector2i(-1, -1)
var _ceiling_holes := {}   # tiles left open on purpose (the stairs climb up through them)
var _fixture_pairs := {}
var _dump := {"missing_tiles": [], "special_tiles": [], "decals": []}


func _rng(name: String) -> RandomNumberGenerator:
	return Game.rng(salt + name)


## The chunk's world origin on the floor plane (it is positioned before build()).
func _spawn2() -> Vector2:
	return Vector2(L["spawn"][0], L["spawn"][1]) if L.has("spawn") else Vector2(-100, -100)


func origin2() -> Vector2:
	return Vector2(position.x, position.z)


## shared_mats: the level's materials (Level0Look.make_materials); this chunk duplicates the
## few that need per-chunk values (the fixture glow field, a shear band, a flooded room).
func build(layout: Dictionary, p_salt: String, shared_mats: Dictionary, p_seed_offset: Vector2) -> void:
	for st in begin_build(layout, p_salt, shared_mats, p_seed_offset):
		(st as Callable).call()


## Same as build(), as a list of steps the streamer runs one per frame (each a few ms).
func begin_build(layout: Dictionary, p_salt: String, shared_mats: Dictionary, p_seed_offset: Vector2) -> Array:
	L = layout
	salt = p_salt
	H = float(L["ceiling_height"])
	T = float(L["wall_thickness"])
	DH = float(L["door_height"])
	extent = Vector2(float(L["size"][0]), float(L["size"][1]))
	seed_offset = p_seed_offset
	var r := _rng("level0:look")
	if salt == "":
		r.randf()
		r.randf()   # the hero drew its seed offset from this stream first; keep its sequence
	mats = shared_mats.duplicate()
	var o := origin2()
	mats["ceiling"] = (shared_mats["ceiling"] as ShaderMaterial).duplicate()
	mats["housing"] = (shared_mats["housing"] as ShaderMaterial).duplicate()
	field = FixtureField.new(o, extent, TILE)
	field.bind(mats["ceiling"])
	field.bind(mats["housing"])
	var sb: Array = L.get("shear_bands", [])
	if sb.size() > 0 or L.has("recolor"):
		mats["wall"] = (shared_mats["wall"] as ShaderMaterial).duplicate()
	if sb.size() > 0:
		var b: Array = sb[0]
		(mats["wall"] as ShaderMaterial).set_shader_parameter("shear_rect", Vector4(b[0] + o.x, b[1] + o.y, b[2] + o.x, b[3] + o.y))
		(mats["wall"] as ShaderMaterial).set_shader_parameter("shear_band", Vector3(b[4], b[5], b[6]))
	if L.has("recolor"):
		var rc: Array = L["recolor"]
		(mats["wall"] as ShaderMaterial).set_shader_parameter("recolor_rect", Vector4(rc[0] + o.x, rc[1] + o.y, rc[2] + o.x, rc[3] + o.y))
		(mats["wall"] as ShaderMaterial).set_shader_parameter("recolor", Vector3(rc[4], rc[5], rc[6]))
	var fc: Array = L.get("flood_candidates", [])
	if fc.size() > 0:
		var f: Array = fc[r.randi() % fc.size()]
		flood = Rect2(f[0], f[1], f[2] - f[0], f[3] - f[1])
		mats["carpet"] = (shared_mats["carpet"] as ShaderMaterial).duplicate()
		(mats["carpet"] as ShaderMaterial).set_shader_parameter("flood_rect", Vector4(f[0] + o.x, f[1] + o.y, f[2] + o.x, f[3] + o.y))
	# The carpet reflects this chunk's panels in its wet patches, so it needs the field too.
	if mats["carpet"] == shared_mats["carpet"]:
		mats["carpet"] = (shared_mats["carpet"] as ShaderMaterial).duplicate()
	field.bind(mats["carpet"])
	# Seams: the patch of wall that only the eye sees uses the wallpaper slipped a few centimeters,
	# a splice you can spot if you look for it (D022).
	if L.get("seams", []).size() > 0:
		mats["seam_wall"] = (mats["wall"] as ShaderMaterial).duplicate()
		(mats["seam_wall"] as ShaderMaterial).set_shader_parameter("uv_slip", Vector2(0.0, 0.034))
		mats["seam_base"] = mats["baseboard"]
	_collect_solids()
	_pick_leaks()
	var kit := MeshKit.new()
	# World-continuous wallpaper; a loop copy uses its template's origin so every copy matches.
	kit.uv_origin = Vector3(position.x, 0.0, position.z)
	if L.has("loop"):
		var lp: Dictionary = L["loop"]
		kit.uv_origin = Vector3(float(lp["start"]) * extent.x, 0.0, float(lp["row"]) * extent.y)
		var shift := Vector3(position.x, 0.0, position.z) - kit.uv_origin
		for key in ["carpet", "ceiling"]:
			if mats[key] == shared_mats[key]:
				mats[key] = (shared_mats[key] as ShaderMaterial).duplicate()
			(mats[key] as ShaderMaterial).set_shader_parameter("world_shift", shift)
	var cells := {}
	return [
		func() -> void:
			_build_shell(kit)
			_build_walls(kit)
			_build_doors(kit)
			_build_fake_doors(kit)
			_build_exit_signs(kit)
			_build_fallen_tile(kit)
			_build_wrong_architecture(kit)
			_build_seams(kit),
		func() -> void:
			cells.merge(_build_fixtures(kit)),
		func() -> void:
			_build_ceiling(kit, cells),
		func() -> void:
			var parts := kit.commit(self, mats, ["tbar", "housing"])
			for key in ["seam_wall", "seam_base"]:
				if parts.has(key):
					(parts[key] as GeometryInstance3D).layers = TapeEvents.LAYER_EYE,
		func() -> void:
			_build_decals(),
		func() -> void:
			_build_props(),
		func() -> void:
			_build_splices(),
		func() -> void:
			_build_collision()
			_build_nav(),
		func() -> void:
			_build_traces(),
		func() -> void:
			_build_wall_details()
			_build_seam_fx(),
	]


## Everything the seed decided, for other renderers (engine bake-off) and for tests.
func _write_dump(path: String) -> void:
	var fx := []
	for f in fixtures:
		fx.append({"x": f.position.x, "z": f.position.z, "state": f.state, "energy": f.base_energy,
			"tint": [f.tint.r, f.tint.g, f.tint.b], "cathode": f.cathode_glow})
	_dump["seed"] = Game.run_seed
	_dump["seed_offset"] = [seed_offset.x, seed_offset.y]
	_dump["leaks"] = leaks.map(func(v): return [v.x, v.y])
	_dump["fixtures"] = fx
	_dump["fixture_light_energy"] = Fixture.LIGHT_ENERGY
	_dump["note"] = "Ceiling tiles not listed in missing_tiles and not covered by a fixture are clean tiles (rnd from special_tiles only when stained). special_tiles lists every placed tile: [i, j, rnd, stained, sag, drop]."
	var fh := FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(_dump))
	fh.close()


# ---------------------------------------------------------------- layout helpers

func _wall_rect(w: Array, ext_a: float, ext_b: float, grow: float = 0.0) -> Rect2:
	var x0: float = minf(w[0], w[2])
	var x1: float = maxf(w[0], w[2])
	var z0: float = minf(w[1], w[3])
	var z1: float = maxf(w[1], w[3])
	var h := T * 0.5 + grow
	if absf(w[1] - w[3]) < 0.001:
		return Rect2(x0 - ext_a - grow, z0 - h, (x1 - x0) + ext_a + ext_b + 2.0 * grow, 2.0 * h)
	return Rect2(x0 - h, z0 - ext_a - grow, 2.0 * h, (z1 - z0) + ext_a + ext_b + 2.0 * grow)


func _is_horizontal(w: Array) -> bool:
	return absf(w[1] - w[3]) < 0.001


## True if point p lies on a wall perpendicular to wall index `self_i`.
func _joined(p: Vector2, self_i: int) -> bool:
	var me: Array = L["walls"][self_i]
	var me_h := _is_horizontal(me)
	for j in L["walls"].size():
		if j == self_i:
			continue
		var w: Array = L["walls"][j]
		if _is_horizontal(w) == me_h:
			continue
		if _is_horizontal(w):
			if absf(p.y - w[1]) < 0.001 and p.x >= minf(w[0], w[2]) - 0.001 and p.x <= maxf(w[0], w[2]) + 0.001:
				return true
		else:
			if absf(p.x - w[0]) < 0.001 and p.y >= minf(w[1], w[3]) - 0.001 and p.y <= maxf(w[1], w[3]) + 0.001:
				return true
	return false


func _wall_ends(i: int) -> Array:
	var w: Array = L["walls"][i]
	var a := Vector2(minf(w[0], w[2]), minf(w[1], w[3]))
	var b := Vector2(maxf(w[0], w[2]), maxf(w[1], w[3]))
	return [_joined(a, i), _joined(b, i)]


func _collect_solids() -> void:
	solids.clear()
	for i in L["walls"].size():
		var ends := _wall_ends(i)
		solids.append(_wall_rect(L["walls"][i], T * 0.5 if ends[0] else 0.0, T * 0.5 if ends[1] else 0.0))
	# Walls on the east and south chunk edges belong to the neighbors, but block us too.
	for w in L.get("edge_walls", []):
		_edge_solids.append(_wall_rect(w, 0.0, 0.0))
		solids.append(_edge_solids[-1])
	for p in L["pillars"]:
		var s: float = p[2]
		solids.append(Rect2(p[0] - s * 0.5, p[1] - s * 0.5, s, s))


func _hits_solid(r: Rect2) -> bool:
	for s in solids:
		if s.intersects(r):
			return true
	return false


func _pick_leaks() -> void:
	var r := _rng("level0:leaks")
	var n := r.randi_range(3, 6)
	var tries := 0
	while leaks.size() < n and tries < 200:
		tries += 1
		var p := Vector2(r.randf_range(1.0, extent.x - 1.0), r.randf_range(1.0, extent.y - 1.0))
		if _hits_solid(Rect2(p - Vector2(0.4, 0.4), Vector2(0.8, 0.8))):
			continue
		var spawn := _spawn2()
		if p.distance_to(spawn) < 3.0:
			continue
		leaks.append(p)


# ---------------------------------------------------------------- geometry

func _build_shell(kit: MeshKit) -> void:
	kit.face("carpet", [Vector3(0, 0, 0), Vector3(extent.x, 0, 0), Vector3(extent.x, 0, extent.y), Vector3(0, 0, extent.y)], Vector3.UP, 0.0)
	var ph := float(L["plenum_height"])
	kit.face("plenum", [Vector3(0, ph, 0), Vector3(extent.x, ph, 0), Vector3(extent.x, ph, extent.y), Vector3(0, ph, extent.y)], Vector3.DOWN, 0.0)


func _build_walls(kit: MeshKit) -> void:
	var bb := 0.012
	var bh := 0.1
	for i in L["walls"].size():
		var w: Array = L["walls"][i]
		var ends := _wall_ends(i)
		var r := _wall_rect(w, T * 0.5 if ends[0] else 0.0, T * 0.5 if ends[1] else 0.0)
		var faces := MeshKit.SIDES
		var horiz := _is_horizontal(w)
		if horiz:
			if ends[0]:
				faces &= ~MeshKit.NX
			if ends[1]:
				faces &= ~MeshKit.PX
		else:
			if ends[0]:
				faces &= ~MeshKit.NZ
			if ends[1]:
				faces &= ~MeshKit.PZ
		kit.box("wall", Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, H, r.end.y), faces, H)
		# Vinyl cove base, proud of the wall on the long faces and around free ends.
		var g := r
		if horiz:
			g = Rect2(r.position.x - (0.0 if ends[0] else bb), r.position.y - bb, r.size.x + (0.0 if ends[0] else bb) + (0.0 if ends[1] else bb), r.size.y + 2.0 * bb)
		else:
			g = Rect2(r.position.x - bb, r.position.y - (0.0 if ends[0] else bb), r.size.x + 2.0 * bb, r.size.y + (0.0 if ends[0] else bb) + (0.0 if ends[1] else bb))
		kit.box("baseboard", Vector3(g.position.x, 0.0, g.position.y), Vector3(g.end.x, bh, g.end.y), faces | MeshKit.PY, bh)
		# Wall angle: the L-shaped ceiling trim where the drop ceiling meets the wall.
		var wa := 0.022
		var ga := r
		if horiz:
			ga = Rect2(r.position.x - (0.0 if ends[0] else wa), r.position.y - wa, r.size.x + (0.0 if ends[0] else wa) + (0.0 if ends[1] else wa), r.size.y + 2.0 * wa)
		else:
			ga = Rect2(r.position.x - wa, r.position.y - (0.0 if ends[0] else wa), r.size.x + 2.0 * wa, r.size.y + (0.0 if ends[0] else wa) + (0.0 if ends[1] else wa))
		kit.box("tbar", Vector3(ga.position.x, H - wa, ga.position.y), Vector3(ga.end.x, H, ga.end.y), faces | MeshKit.NY, H)
	_build_outlets(kit)
	for p in L["pillars"]:
		var s: float = p[2]
		if p.size() > 3 and p[3] == "plus":
			# A cross-shaped column: two slabs crossing, each a third as thick as it is wide.
			var th := s / 3.0
			for slab in [Vector2(s, th), Vector2(th, s)]:
				kit.box("wall", Vector3(p[0] - slab.x * 0.5, 0.0, p[1] - slab.y * 0.5), Vector3(p[0] + slab.x * 0.5, H, p[1] + slab.y * 0.5), MeshKit.SIDES, H)
				var qb := Vector2(slab.x * 0.5 + 0.012, slab.y * 0.5 + 0.012)
				kit.box("baseboard", Vector3(p[0] - qb.x, 0.0, p[1] - qb.y), Vector3(p[0] + qb.x, 0.1, p[1] + qb.y), MeshKit.SIDES | MeshKit.PY, 0.1)
			_pending_contacts.append([Vector3(p[0], 0.0, p[1]), s * 0.6])
			continue
		kit.box("wall", Vector3(p[0] - s * 0.5, 0.0, p[1] - s * 0.5), Vector3(p[0] + s * 0.5, H, p[1] + s * 0.5), MeshKit.SIDES, H)
		# Soft occlusion on the carpet around each column, so it stands on the floor (L032).
		_pending_contacts.append([Vector3(p[0], 0.0, p[1]), s * 0.62])
		var q := s * 0.5 + bb
		kit.box("baseboard", Vector3(p[0] - q, 0.0, p[1] - q), Vector3(p[0] + q, bh, p[1] + q), MeshKit.SIDES | MeshKit.PY, bh)


var _outlet_spots: Array = []


## Wall outlets every so often near the floor. Nothing is ever plugged into them.
func _build_outlets(kit: MeshKit) -> void:
	var r := _rng("level0:outlets")
	var walls: Array = L["walls"]
	if walls.is_empty():
		return
	for k in 26:
		var w: Array = walls[r.randi() % walls.size()]
		var length: float = absf(w[2] - w[0]) + absf(w[3] - w[1])
		if length < 1.5:
			continue
		var horiz := _is_horizontal(w)
		var t := r.randf_range(0.15, 0.85)
		var c := Vector2(lerpf(w[0], w[2], t), lerpf(w[1], w[3], t))
		var side := 1.0 if r.randf() < 0.5 else -1.0
		var n := Vector2(0, side) if horiz else Vector2(side, 0)
		var tan := Vector2(-n.y, n.x)
		var face := c + n * (T * 0.5)
		var y := 0.3 if r.randf() < 0.8 else 1.1
		_outlet_spots.append([face, n, y])
		var plate := [[-0.035, 0.035, y - 0.058, y + 0.058, 0.0, 0.006, "plate"]]
		for dy in [-0.02, 0.02]:
			plate.append([-0.012, -0.008, y + dy - 0.007, y + dy + 0.007, 0.006, 0.0065, "slot"])
			plate.append([0.008, 0.012, y + dy - 0.008, y + dy + 0.008, 0.006, 0.0065, "slot"])
		for b in plate:
			var c0: Vector2 = face + tan * float(b[0]) + n * float(b[4])
			var c1: Vector2 = face + tan * float(b[1]) + n * float(b[5])
			kit.box(b[6], Vector3(minf(c0.x, c1.x), b[2], minf(c0.y, c1.y)), Vector3(maxf(c0.x, c1.x), b[3], maxf(c0.y, c1.y)), MeshKit.ALL, H)


func _build_doors(kit: MeshKit) -> void:
	var cw := 0.07    # casing width
	var cp := 0.018   # casing projection from the wall face
	var li := 0.02    # jamb lining thickness
	for d in L["doors"]:
		var horiz: bool = absf(d[1] - d[3]) < 0.001
		var a: float = minf(d[0], d[2]) if horiz else minf(d[1], d[3])
		var b: float = maxf(d[0], d[2]) if horiz else maxf(d[1], d[3])
		var c: float = d[1] if horiz else d[0]
		var dh: float = float(d[4]) if d.size() > 4 else DH   # some doorways are slightly too small
		var boxes := []  # [key, min(along, y, across), max(along, y, across)]
		boxes.append(["wall", Vector3(a, dh, c - T * 0.5), Vector3(b, H, c + T * 0.5)])
		boxes.append(["trim", Vector3(a, 0.0, c - T * 0.5), Vector3(a + li, dh, c + T * 0.5)])
		boxes.append(["trim", Vector3(b - li, 0.0, c - T * 0.5), Vector3(b, dh, c + T * 0.5)])
		boxes.append(["trim", Vector3(a, dh - li, c - T * 0.5), Vector3(b, dh, c + T * 0.5)])
		for s in [-1.0, 1.0]:
			var f: float = c + s * T * 0.5
			var f2: float = f + s * cp
			var lo := minf(f, f2)
			var hi := maxf(f, f2)
			boxes.append(["trim", Vector3(a - cw, 0.0, lo), Vector3(a, dh + cw, hi)])
			boxes.append(["trim", Vector3(b, 0.0, lo), Vector3(b + cw, dh + cw, hi)])
			boxes.append(["trim", Vector3(a - cw, dh, lo), Vector3(b + cw, dh + cw, hi)])
		for bx in boxes:
			var mn: Vector3 = bx[1]
			var mx: Vector3 = bx[2]
			if horiz:
				kit.box(bx[0], mn, mx, MeshKit.ALL, H)
			else:
				kit.box(bx[0], Vector3(mn.z, mn.y, mn.x), Vector3(mx.z, mx.y, mx.x), MeshKit.ALL, H)


## A finished door frame and a closed door set into a solid wall. It does not open.
func _build_fake_doors(kit: MeshKit) -> void:
	for fd in L.get("fake_doors", []):
		var p := Vector2(fd[0], fd[1])
		var n := Vector2(fd[2], fd[3])
		var t := Vector2(-n.y, n.x)
		var w := 0.92
		var cw := 0.07
		var bx := []
		# casing: two jambs and a head, then the slab slightly proud of the wall, then a knob
		bx.append(["trim", -w * 0.5 - cw, -w * 0.5, 0.0, DH + cw, 0.0, 0.018])
		bx.append(["trim", w * 0.5, w * 0.5 + cw, 0.0, DH + cw, 0.0, 0.018])
		bx.append(["trim", -w * 0.5 - cw, w * 0.5 + cw, DH, DH + cw, 0.0, 0.018])
		bx.append(["door", -w * 0.5 + 0.004, w * 0.5 - 0.004, 0.006, DH - 0.004, 0.0, 0.012])
		bx.append(["knob", w * 0.5 - 0.11, w * 0.5 - 0.06, 0.96, 1.01, 0.012, 0.07])
		for b in bx:
			var a0: float = b[1]
			var a1: float = b[2]
			var y0: float = b[3]
			var y1: float = b[4]
			var o0: float = b[5]
			var o1: float = b[6]
			var c0 := p + t * a0 + n * o0
			var c1 := p + t * a1 + n * o1
			kit.box(b[0], Vector3(minf(c0.x, c1.x), y0, minf(c0.y, c1.y)), Vector3(maxf(c0.x, c1.x), y1, maxf(c0.y, c1.y)), MeshKit.ALL, H)


## Exit signs: a lit box above a doorway with a faint red glow on the wall around it.
func _build_exit_signs(kit: MeshKit) -> void:
	for es in L.get("exit_signs", []):
		var p := Vector3(es[0], 2.36, es[1])
		var n := Vector3(es[2], 0, es[3])
		var t := Vector3.UP.cross(n)   # the viewer's right when facing the sign
		var face := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.4, 0.2)
		face.mesh = q
		face.material_override = mats["exit"]
		face.transform = Transform3D(Basis(t, Vector3.UP, n), p + n * 0.051)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(face)
		var a := p - t * 0.22 - Vector3(0, 0.115, 0)
		var b := p + t * 0.22 + Vector3(0, 0.115, 0) + n * 0.05
		kit.box("housing", Vector3(minf(a.x, b.x), a.y, minf(a.z, b.z)), Vector3(maxf(a.x, b.x), b.y, maxf(a.z, b.z)), MeshKit.ALL, H)
		var glow := OmniLight3D.new()
		# Believable rather than neon (critique 006, L026): less saturated and weaker, shadowed so
		# the door frame and the sign box block it.
		glow.light_color = Color(1.0, 0.3, 0.2)
		glow.light_energy = 0.15
		glow.omni_range = 1.9
		glow.omni_attenuation = 1.8
		glow.shadow_enabled = true
		glow.shadow_bias = 0.05
		glow.light_size = 0.15
		glow.position = p + n * 0.14 - Vector3(0, 0.12, 0)
		add_child(glow)


func _build_fixtures(kit: MeshKit) -> Dictionary:
	var cells := {}
	var r := _rng("level0:fixtures")
	var ctx := {}
	ctx["lens_z"] = _make_lens_mesh(0.58, 1.18)
	ctx["lens_x"] = _make_lens_mesh(1.18, 0.58)
	var dark_zones := []
	for z in L["dark_zones"]:
		dark_zones.append(Rect2(z[0], z[1], z[2] - z[0], z[3] - z[1]))
	ctx["dark_zones"] = dark_zones
	var pockets := []
	for z in L.get("pocket_zones", []):
		pockets.append(Rect2(z[0], z[1], z[2] - z[0], z[3] - z[1]))
	ctx["pockets"] = pockets
	# Clusters of dead panels give the level its pools of darkness (four per 30 x 30 m).
	ctx["spawn"] = Vector2(L["spawn"][0], L["spawn"][1]) if L.has("spawn") else Vector2(-100, -100)
	var clusters := []
	var n_cl := int(Game.opts.get("clusters", "4"))
	if not L.has("fixture_grid"):
		n_cl = int(n_cl * extent.x * extent.y / 900.0 + r.randf())
	for k in n_cl:
		clusters.append(Vector2(r.randf_range(3.0, extent.x - 3.0), r.randf_range(3.0, extent.y - 3.0)))
	ctx["clusters"] = clusters
	ctx["dead_rate"] = float(Game.opts.get("dead_rate", "0.18"))
	var hints := []
	for h in L["failing_hint"]:
		hints.append(Vector2(h[0], h[1]))
	ctx["hints"] = hints
	ctx["hum_a"] = _snd("hum_fixture_a")
	ctx["hum_b"] = _snd("hum_fixture_b")
	ctx["buzz"] = _snd("buzz_failing")
	var ticks := []
	for t in 4:
		var s := _snd("tube_tick_%02d" % (t + 1))
		if s:
			ticks.append(s)
	ctx["ticks"] = ticks
	if L.has("fixtures"):
		# Generated chunks: the ceiling grid was laid out per room by Level0Gen.
		for k in L["fixtures"].size():
			var f: Array = L["fixtures"][k]
			ctx["hint"] = String(f[3]) if f.size() > 3 else ""
			_make_fixture(kit, r, cells, Vector2(f[0], f[1]), int(f[2]) == 1, "%d" % k, ctx)
	else:
		var fg: Dictionary = L["fixture_grid"]
		for i in int(fg["nx"]):
			for j in int(fg["nz"]):
				var c := _place_fixture(Vector2(float(fg["x0"]) + i * float(fg["dx"]), float(fg["z0"]) + j * float(fg["dz"])), Vector2(fg["w"], fg["l"]), cells)
				if c.x < -50.0:
					continue
				_make_fixture(kit, r, cells, c, false, "%d:%d" % [i, j], ctx)
	for ff in L.get("floor_fixtures", []):
		_make_floor_fixture(kit, Vector2(ff[0], ff[1]))
	return cells


## One 2 x 4 troffer: recessed housing, lens, its condition (dead, failing, tint) and, unless
## a FixturePool lends it a light and hum later, its own light and sounds.
func _make_fixture(kit: MeshKit, r: RandomNumberGenerator, cells: Dictionary, c: Vector2, along_x: bool, id: String, ctx: Dictionary) -> void:
	var fw := 1.2 if along_x else 0.6
	var fl := 0.6 if along_x else 1.2
	var rect := Rect2(c - Vector2(fw, fl) * 0.5, Vector2(fw, fl))
	var ix := int(floor(rect.position.x / TILE + 0.01))
	var iz := int(floor(rect.position.y / TILE + 0.01))
	var c2 := Vector2i(ix + 1, iz) if along_x else Vector2i(ix, iz + 1)
	cells[Vector2i(ix, iz)] = true
	cells[c2] = true
	_fixture_pairs[Vector2i(ix, iz)] = c2
	# Recessed housing reveal around the lens.
	var y0 := H
	var y1 := H + 0.03
	var a := Vector3(rect.position.x, y0, rect.position.y)
	var b := Vector3(rect.end.x, y1, rect.end.y)
	kit.face("housing", [Vector3(a.x, y0, a.z), Vector3(b.x, y0, a.z), Vector3(b.x, y1, a.z), Vector3(a.x, y1, a.z)], Vector3.BACK, 0.0)
	kit.face("housing", [Vector3(a.x, y0, b.z), Vector3(b.x, y0, b.z), Vector3(b.x, y1, b.z), Vector3(a.x, y1, b.z)], Vector3.FORWARD, 0.0)
	kit.face("housing", [Vector3(a.x, y0, a.z), Vector3(a.x, y0, b.z), Vector3(a.x, y1, b.z), Vector3(a.x, y1, a.z)], Vector3.RIGHT, 0.0)
	kit.face("housing", [Vector3(b.x, y0, a.z), Vector3(b.x, y0, b.z), Vector3(b.x, y1, b.z), Vector3(b.x, y1, a.z)], Vector3.LEFT, 0.0)

	# Decide this fixture's condition.
	var st := Fixture.State.ON
	var roll := r.randf()
	var in_dark := false
	for dz in ctx["dark_zones"]:
		if (dz as Rect2).has_point(c):
			in_dark = true
	var near_cluster := false
	for cl in ctx["clusters"]:
		if c.distance_to(cl) < 3.6:
			near_cluster = true
	var dead_rate: float = ctx["dead_rate"]
	var dim := false
	if in_dark:
		# A dead room keeps one weak, breathing tube so you can still read its shape (VISION:
		# blacks deep, silhouettes readable).
		st = Fixture.State.STARTER if roll < 0.14 else Fixture.State.DEAD
		if roll >= 0.14 and roll < 0.62:
			st = Fixture.State.PULSE
			dim = true
	elif near_cluster and roll < 0.6:
		st = Fixture.State.DEAD
	elif roll < dead_rate:
		st = Fixture.State.DEAD
	elif roll < dead_rate + 0.025:
		st = Fixture.State.STARTER
	elif roll < dead_rate + 0.05:
		st = Fixture.State.PULSE
	elif roll < dead_rate + 0.085:
		st = Fixture.State.DROPOUT
	for h in ctx["hints"]:
		if c.distance_to(h) < 1.3:
			st = Fixture.State.PULSE
	# The room's mood (Level0Gen._room_mood).
	var hint: String = ctx.get("hint", "")
	if hint == "dead" and not in_dark:
		st = Fixture.State.DEAD
	elif hint == "on" and not in_dark:
		st = Fixture.State.ON
	if L.get("steady_lights", false):
		# Loop copies must look identical at every moment: no flicker, only on or dead.
		st = Fixture.State.DEAD if in_dark else Fixture.State.ON
		dim = false
	if c.distance_to(ctx["spawn"]) < 3.2 and st != Fixture.State.PULSE:
		st = Fixture.State.ON
	for pz in ctx["pockets"]:
		if (pz as Rect2).has_point(c):
			st = Fixture.State.DEAD   # the survey pocket is lit by its work light alone
	for lz in L.get("lit_zones", []):
		if Rect2(lz[0], lz[1], lz[2] - lz[0], lz[3] - lz[1]).has_point(c):
			st = Fixture.State.ON
	var tint_roll := r.randf()
	var tint := Color(1.0, 0.975, 0.9)
	if tint_roll < 0.035:
		tint = Color(0.74, 0.9, 1.0)     # a cold replacement tube that does not match
	elif tint_roll < 0.18:
		tint = Color(0.93, 1.0, 0.86)    # greenish cool-white tube
	elif tint_roll < 0.3:
		tint = Color(1.0, 0.93, 0.84)    # warmer, slightly pink aged tube
	for tz in L.get("tint_zones", []):
		if Rect2(tz[0], tz[1], tz[2] - tz[0], tz[3] - tz[1]).has_point(c):
			tint = Color(tz[4], tz[5], tz[6])   # a stretch where every tube is a cold replacement
	var energy := r.randf_range(0.82, 1.04)
	if dim:
		energy *= 0.32
	if hint == "dim":
		energy *= 0.55
		tint = tint * Color(1.0, 0.88, 0.74)   # tired, warm, nearly spent tubes
	var variant := r.randi()
	var offset := r.randf_range(0.0, 7.9)

	var fx := Fixture.new()
	fx.name = "fixture_" + id.replace(":", "_")
	fx.position = Vector3(c.x, 0.0, c.y)
	fx.ceiling_h = H
	fx.variant = variant
	fx.audio_offset = offset
	add_child(fx)
	var lens := MeshInstance3D.new()
	lens.mesh = ctx["lens_x"] if along_x else ctx["lens_z"]
	lens.material_override = mats["lens"]
	lens.position = Vector3(0, H + 0.03, 0)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lens.visibility_range_end = 48.0
	fx.add_child(lens)
	fx.lens = lens
	if not pooled:
		var light := Fixture.make_ceiling_light()
		light.position = Vector3(0, H - 0.004, 0)
		light.light_color = tint
		fx.add_child(light)
		fx.light = light
		if ctx["hum_a"]:
			var hum := _audio(H, 1.1, 9.0)
			hum.stream = ctx["hum_a"] if variant % 5 < 3 else ctx["hum_b"]
			hum.pitch_scale = 1.0 + (variant % 11 - 5) * 0.001
			fx.add_child(hum)
			fx.hum = hum
		if fx_failing(st) and ctx["buzz"]:
			var bz := _audio(H, 1.4, 14.0)
			bz.stream = ctx["buzz"]
			fx.add_child(bz)
			fx.buzz = bz
			if ctx["ticks"].size() > 0:
				var tk := _audio(H, 1.6, 16.0)
				tk.stream = ctx["ticks"][variant % ctx["ticks"].size()]
				tk.volume_db = -6.0
				fx.add_child(tk)
				fx.tick_player = tk
	fx.setup(st, _rng("fixture:" + id), energy, tint)
	fx.apply()
	fixtures.append(fx)
	field.add(fx, [Vector2i(ix, iz), c2])


static func fx_failing(st: int) -> bool:
	return st == Fixture.State.STARTER or st == Fixture.State.PULSE or st == Fixture.State.DROPOUT


func _audio(h: float, unit: float, maxd: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"World"
	p.position = Vector3(0, h - 0.05, 0)
	p.unit_size = unit
	p.max_distance = maxd
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	return p


## A troffer set face-up into the carpet like a floor tile, still lit, throwing its light up at
## the ceiling: a copy that came out upside down (generation loss).
func _make_floor_fixture(kit: MeshKit, c: Vector2) -> void:
	var fx := Fixture.new()
	fx.name = "floor_fixture"
	fx.mount = Fixture.Mount.FLOOR
	fx.position = Vector3(c.x, 0.0, c.y)
	add_child(fx)
	var lens := MeshInstance3D.new()
	lens.mesh = _make_lens_mesh(0.58, 1.18)
	lens.material_override = mats["lens"]
	lens.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0.006, 0))
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(lens)
	fx.lens = lens
	kit.box("housing", Vector3(c.x - 0.31, 0.0, c.y - 0.61), Vector3(c.x + 0.31, 0.012, c.y + 0.61), MeshKit.SIDES, H)
	var sl := Fixture.make_ceiling_light()
	sl.rotation = Vector3(PI * 0.5, 0, 0)
	sl.position = Vector3(0, 0.02, 0)
	sl.light_color = Color(0.95, 1.0, 0.9)
	fx.add_child(sl)
	fx.light = sl
	fx.setup(Fixture.State.PULSE, _rng("level0:floorfixture"), 0.75, Color(0.95, 1.0, 0.9))
	fx.apply()
	fixtures.append(fx)
	solids.append(Rect2(c.x - 0.35, c.y - 0.65, 0.7, 1.3))


## Real ceiling grids are laid out per room, so a panel never sits hard against a wall. A point
## light that close paints a bright arc on the wall (critique 006, L021). Slide the grid
## position by whole tiles to the spot with the most clearance; returns x < -50 to skip it.
func _place_fixture(c0: Vector2, size: Vector2, taken: Dictionary) -> Vector2:
	var best := Vector2(-100, -100)
	var best_score := -1e9
	for dx in [0.0, -TILE, TILE, -2.0 * TILE, 2.0 * TILE]:
		for dz in [0.0, -TILE, TILE, -2.0 * TILE, 2.0 * TILE]:
			var c := c0 + Vector2(dx, dz)
			var rect := Rect2(c - size * 0.5, size)
			if rect.position.x < 0.3 or rect.position.y < 0.3 or rect.end.x > extent.x - 0.3 or rect.end.y > extent.y - 0.3:
				continue
			if _hits_solid(rect.grow(0.04)):
				continue
			var ix := int(floor((c.x - size.x * 0.5) / TILE + 0.01))
			var iz := int(floor((c.y - size.y * 0.5) / TILE + 0.01))
			if taken.has(Vector2i(ix, iz)) or taken.has(Vector2i(ix, iz + 1)) or taken.has(Vector2i(ix, iz - 1)) or taken.has(Vector2i(ix, iz + 2)):
				continue
			var score := minf(_clearance(c), 1.25) - 0.18 * (absf(dx) + absf(dz))
			if score > best_score:
				best_score = score
				best = c
	return best


## Distance from p to the nearest wall or pillar.
func _clearance(p: Vector2) -> float:
	var d := 1e9
	for s in solids:
		var q := Vector2(clampf(p.x, s.position.x, s.end.x), clampf(p.y, s.position.y, s.end.y))
		d = minf(d, p.distance_to(q))
	return d


func _make_lens_mesh(w: float, l: float) -> ArrayMesh:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := [Vector3(-w * 0.5, 0, -l * 0.5), Vector3(w * 0.5, 0, -l * 0.5), Vector3(w * 0.5, 0, l * 0.5), Vector3(-w * 0.5, 0, l * 0.5)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var c: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	var order := [0, 1, 2, 0, 2, 3]
	if c.dot(Vector3.DOWN) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		s.set_normal(Vector3.DOWN)
		s.set_uv(uv[i])
		s.add_vertex(p[i])
	s.generate_tangents()
	return s.commit()


func _build_ceiling(kit: MeshKit, fixture_cells: Dictionary) -> void:
	var r := _rng("level0:ceiling")
	var nx := int(round(extent.x / TILE))
	var nz := int(round(extent.y / TILE))
	var plain := {}
	var spawn := _spawn2()
	for i in nx:
		for j in nz:
			if fixture_cells.has(Vector2i(i, j)):
				continue
			var x0 := i * TILE
			var z0 := j * TILE
			var center := Vector2(x0 + TILE * 0.5, z0 + TILE * 0.5)
			var rnd := r.randf()
			var stained := 0.0
			for lk in leaks:
				var dd := center.distance_to(lk)
				if dd < 0.45 or (dd < 1.4 and r.randf() < 0.35):
					stained = 1.0
			if stained == 0.0 and r.randf() < 0.02:
				stained = 1.0
			var missing := (r.randf() < 0.006 and center.distance_to(spawn) > 4.0) or Vector2i(i, j) == _fallen_tile or _ceiling_holes.has(Vector2i(i, j))
			if missing:
				_dump["missing_tiles"].append([i, j])
				continue
			var sag := 0.0
			var drop := 0.0
			if stained > 0.0 and r.randf() < 0.25:
				sag = 0.5
				drop = r.randf_range(0.015, 0.04)
			if stained == 0.0:
				plain[Vector2i(i, j)] = true
				continue
			# Stained or sagging tiles are their own quads; COLOR.a = 0 tells the shader to use
			# COLOR (random, stained, sag) instead of deriving it from the world tile index.
			var col := Color(rnd, stained, sag, 0.0)
			_dump["special_tiles"].append([i, j, snappedf(rnd, 0.001), stained, sag, snappedf(drop, 0.0001)])
			var y := H
			var pts := [Vector3(x0, y, z0), Vector3(x0 + TILE, y, z0), Vector3(x0 + TILE, y - drop, z0 + TILE), Vector3(x0, y - drop * 0.4, z0 + TILE)]
			kit.quad("ceiling", pts, Vector3.DOWN, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], col)
	# Plain tiles merged into rectangles (a chunk has ~1,600 tiles; this keeps it to a few hundred
	# quads so chunks stream quickly). The shader picks each tile's look from its world index.
	var open_runs := {}   # Vector2i(i0, i1) -> first row
	for j in nz + 1:
		var runs := {}
		if j < nz:
			var i := 0
			while i < nx:
				if not plain.has(Vector2i(i, j)):
					i += 1
					continue
				var i0 := i
				while i < nx and plain.has(Vector2i(i, j)):
					i += 1
				runs[Vector2i(i0, i)] = true
		for key in open_runs.keys():
			if not runs.has(key):
				var j0: int = open_runs[key]
				var k: Vector2i = key
				kit.quad("ceiling", [Vector3(k.x * TILE, H, j0 * TILE), Vector3(k.y * TILE, H, j0 * TILE), Vector3(k.y * TILE, H, j * TILE), Vector3(k.x * TILE, H, j * TILE)],
					Vector3.DOWN, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Color(1, 1, 1, 1))
				open_runs.erase(key)
		for key in runs.keys():
			if not open_runs.has(key):
				open_runs[key] = j
	# T-bar grid, edge by edge, so no bar runs across the middle of a 2x4 light fixture.
	var hw := 0.012
	var hd := 0.014
	for k in (nz + 1 if own_far_edges else nz):
		var z := k * TILE
		var run_start := -1
		for i in nx + 1:
			var skip := i >= nx or (fixture_cells.has(Vector2i(i, k - 1)) and fixture_cells.has(Vector2i(i, k)) and _same_fixture(Vector2i(i, k - 1), Vector2i(i, k))) 					or (_ceiling_holes.has(Vector2i(i, k - 1)) and _ceiling_holes.has(Vector2i(i, k)))
			if not skip and run_start == -1:
				run_start = i
			if skip and run_start != -1:
				kit.box("tbar", Vector3(run_start * TILE, H - hd, z - hw), Vector3(i * TILE, H, z + hw), MeshKit.NY | MeshKit.PZ | MeshKit.NZ, H)
				run_start = -1
	for k in (nx + 1 if own_far_edges else nx):
		var x := k * TILE
		var run_start := -1
		for j in nz + 1:
			var skip := j >= nz or (_ceiling_holes.has(Vector2i(k - 1, j)) and _ceiling_holes.has(Vector2i(k, j))) \
					or (fixture_cells.has(Vector2i(k - 1, j)) and fixture_cells.has(Vector2i(k, j)) and _same_fixture(Vector2i(k - 1, j), Vector2i(k, j)))
			if not skip and run_start == -1:
				run_start = j
			if skip and run_start != -1:
				kit.box("tbar", Vector3(x - hw, H - hd, run_start * TILE), Vector3(x + hw, H, j * TILE), MeshKit.NY | MeshKit.PX | MeshKit.NX, H)
				run_start = -1


## True if two ceiling cells belong to the same fixture (its two halves).
func _same_fixture(a: Vector2i, b: Vector2i) -> bool:
	return _fixture_pairs.has(a) and _fixture_pairs[a] == b or _fixture_pairs.has(b) and _fixture_pairs[b] == a


## One ceiling tile has come down and lies on the carpet below its hole.
func _build_fallen_tile(kit: MeshKit) -> void:
	var r := _rng("level0:fallen")
	var spawn := _spawn2()
	for k in 40:
		var i := r.randi_range(2, int(extent.x / TILE) - 3)
		var j := r.randi_range(2, int(extent.y / TILE) - 3)
		var c := Vector2((i + 0.5) * TILE, (j + 0.5) * TILE)
		if c.distance_to(spawn) < 5.0 or _hits_solid(Rect2(c - Vector2(0.7, 0.7), Vector2(1.4, 1.4))):
			continue
		_fallen_tile = Vector2i(i, j)
		var ang := r.randf_range(-0.6, 0.6)
		var off := Vector2(r.randf_range(-0.25, 0.25), r.randf_range(-0.25, 0.25))
		var b := Basis(Vector3.UP, ang)
		var center := Vector3(c.x + off.x, 0.012, c.y + off.y)
		var hs := TILE * 0.5 - 0.01
		var tilt := r.randf_range(0.0, 0.035)
		var pts := []
		for q in [Vector3(-hs, 0, -hs), Vector3(hs, 0, -hs), Vector3(hs, tilt, hs), Vector3(-hs, tilt, hs)]:
			pts.append(center + b * q)
		kit.quad("ceiling", pts, Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Color(r.randf(), 1.0, 0.6, 0.0))
		# chipped edges
		for e in 4:
			var a: Vector3 = pts[e]
			var bb: Vector3 = pts[(e + 1) % 4]
			var sides: Array[Vector3] = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
			var nrm: Vector3 = b * sides[e]
			kit.quad("ceiling", [a, bb, bb - Vector3(0, 0.014, 0), a - Vector3(0, 0.014, 0)], nrm, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.02), Vector2(0, 0.02)], Color(0.2, 1.0, 0.8, 0.0))
		return


# ---------------------------------------------------------------- decals

func _decal(tex_name: String, pos: Vector3, basis: Basis, size: Vector3, modulate: Color = Color(1, 1, 1, 1)) -> Decal:
	var p := TEXD + tex_name + ".png"
	if not ResourceLoader.exists(p):
		return null
	var d := Decal.new()
	d.texture_albedo = load(p)
	var np := TEXD + tex_name + "_normal.png"
	if ResourceLoader.exists(np):
		d.texture_normal = load(np)
	d.size = size
	d.modulate = modulate
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.normal_fade = 0.4
	d.distance_fade_enabled = true
	d.distance_fade_begin = 30.0
	d.distance_fade_length = 6.0
	d.transform = Transform3D(basis, pos)
	add_child(d)
	_dump["decals"].append({"tex": tex_name, "origin": [pos.x, pos.y, pos.z],
		"basis": [basis.x.x, basis.x.y, basis.x.z, basis.y.x, basis.y.y, basis.y.z, basis.z.x, basis.z.y, basis.z.z],
		"size": [size.x, size.y, size.z], "modulate": [modulate.r, modulate.g, modulate.b, modulate.a]})
	return d


static func _basis_facing(n: Vector3, spin: float = 0.0) -> Basis:
	# Decals project along local -Y: aim local +Y along the surface normal n.
	var y := n.normalized()
	var x := Vector3.UP.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT.rotated(Vector3.UP, spin)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _nearest_wall_face(p: Vector2, max_d: float) -> Array:
	# Returns [point on face (Vector2), outward normal (Vector2), wall rect] or [].
	var best := []
	var best_d := max_d
	for s in solids:
		if s.size.x * s.size.y <= 0.0:
			continue
		var cands := [
			[Vector2(s.position.x, clampf(p.y, s.position.y, s.end.y)), Vector2(-1, 0)],
			[Vector2(s.end.x, clampf(p.y, s.position.y, s.end.y)), Vector2(1, 0)],
			[Vector2(clampf(p.x, s.position.x, s.end.x), s.position.y), Vector2(0, -1)],
			[Vector2(clampf(p.x, s.position.x, s.end.x), s.end.y), Vector2(0, 1)],
		]
		for cd in cands:
			var q: Vector2 = cd[0]
			var n: Vector2 = cd[1]
			if (p - q).dot(n) <= 0.0:
				continue
			var d := p.distance_to(q)
			if d < best_d:
				best_d = d
				best = [q, n, s]
	return best


static var _graffiti_table := {}


## Marks left by earlier people (data/graffiti.json, made by pipeline/textures/build_graffiti.py).
func _build_graffiti() -> void:
	if _graffiti_table.is_empty():
		_graffiti_table = JSON.parse_string(FileAccess.get_file_as_string("res://data/graffiti.json"))
	var r := _rng("level0:graffiti")
	for g in L.get("graffiti", []):
		var info: Dictionary = _graffiti_table.get(g[0], {})
		if info.is_empty():
			continue
		var w: float = (float(g[6]) if g.size() > 6 else float(info["width"])) * r.randf_range(0.9, 1.1)
		var h: float = w * float(info["aspect"])
		var n := Vector3(g[3], 0.0, g[4])
		var b := _basis_facing(n).rotated(n, r.randf_range(-0.05, 0.05))
		_decal(String(info["tex"]), Vector3(g[1], g[5], g[2]), b, Vector3(w, 0.3, h), Color(1, 1, 1, r.randf_range(0.82, 0.96)))


func _build_decals() -> void:
	var r := _rng("level0:decals")
	_build_graffiti()
	for pc in _pending_contacts:
		_contact_shadow(pc[0], pc[1])
	for lk in leaks:
		var spin := r.randf() * TAU
		var fs := r.randf_range(1.8, 3.2)
		_decal("decal_floor_wetpatch", Vector3(lk.x, 0.0, lk.y), _basis_facing(Vector3.UP).rotated(Vector3.UP, spin), Vector3(fs, 0.6, fs * r.randf_range(0.7, 1.1)))
		var cs := r.randf_range(0.9, 1.6)
		_decal("decal_ceiling_stain", Vector3(lk.x, H, lk.y), _basis_facing(Vector3.DOWN).rotated(Vector3.UP, spin), Vector3(cs, 0.3, cs))
		var wf := _nearest_wall_face(lk, 1.8)
		if wf.size() > 0:
			var q: Vector2 = wf[0]
			var n: Vector2 = wf[1]
			var ww := r.randf_range(0.8, 1.5)
			_decal("decal_wall_waterdamage", Vector3(q.x, H - ww, q.y), _basis_facing(Vector3(n.x, 0, n.y)), Vector3(ww, 0.3, ww * 2.0))
			_decal("decal_mold", Vector3(q.x + n.y * 0.4, H - 0.25, q.y - n.x * 0.4), _basis_facing(Vector3(n.x, 0, n.y)), Vector3(0.6, 0.3, 0.6), Color(1, 1, 1, 0.85))
	# Grime above the baseboards along random stretches of wall.
	var walls: Array = L["walls"]
	for k in (26 if not walls.is_empty() else 0):
		var w: Array = walls[r.randi() % walls.size()]
		var horiz := _is_horizontal(w)
		var t := r.randf()
		var px := lerpf(w[0], w[2], t)
		var pz := lerpf(w[1], w[3], t)
		var side := 1.0 if r.randf() < 0.5 else -1.0
		var n := Vector3(0, 0, side) if horiz else Vector3(side, 0, 0)
		var pos := Vector3(px, 0.28, pz) + n * T * 0.5
		var gw := r.randf_range(1.2, 2.8)
		_decal("decal_wall_grime_low", pos, _basis_facing(n), Vector3(gw, 0.3, 0.6), Color(1, 1, 1, r.randf_range(0.5, 0.9)))


## Traces of people who were here before: chalk on the walls and a wet footprint trail
## that walks up to the door that does not open, and stops.
func _build_traces() -> void:
	var r := _rng("level0:traces")
	var walls: Array = L["walls"]
	var chalk := [["decal_chalk_arrow", Vector3(0.95, 0.3, 0.48)], ["decal_chalk_tally", Vector3(0.8, 0.3, 0.4)],
		["decal_chalk_x", Vector3(0.62, 0.3, 0.62)], ["decal_chalk_arrow", Vector3(0.8, 0.3, 0.4)], ["decal_chalk_tally", Vector3(0.6, 0.3, 0.3)]]
	var placed := 0
	var tries := 0
	while placed < chalk.size() and tries < 200 and not walls.is_empty():
		tries += 1
		var w: Array = walls[r.randi() % walls.size()]
		var length: float = absf(w[2] - w[0]) + absf(w[3] - w[1])
		if length < 2.5:
			continue
		var horiz := _is_horizontal(w)
		var t := r.randf_range(0.2, 0.8)
		var px: float = lerpf(w[0], w[2], t)
		var pz: float = lerpf(w[1], w[3], t)
		var side := 1.0 if r.randf() < 0.5 else -1.0
		var n := Vector3(0, 0, side) if horiz else Vector3(side, 0, 0)
		var probe := Vector3(px, 0, pz) + n * 0.6
		if probe.x < 0.3 or probe.z < 0.3 or probe.x > extent.x - 0.3 or probe.z > extent.y - 0.3 or not is_walkable(probe):
			continue
		var c: Array = chalk[placed]
		var spin := r.randf_range(-0.08, 0.08)
		var pos := Vector3(px, r.randf_range(1.05, 1.5), pz) + n * T * 0.5
		var b := _basis_facing(n).rotated(n, spin)
		if c[0] == "decal_chalk_arrow" and r.randf() < 0.5:
			b = b.rotated(n, PI)
		_decal(c[0], pos, b, c[1], Color(1, 1, 1, r.randf_range(0.65, 0.95)))
		placed += 1
	# Footprints to the first fake door.
	var fds: Array = L.get("fake_doors", [])
	if fds.is_empty():
		return
	var fd: Array = fds[0]
	var door := Vector3(fd[0] + fd[2] * 0.35, 0.0, fd[1] + fd[3] * 0.35)
	var starts := []
	for it in get_interest_points():
		var d: float = it["pos"].distance_to(door)
		if d > 9.0 and d < 18.0:
			starts.append(it["pos"])
	if starts.is_empty():
		return
	var from: Vector3 = starts[r.randi() % starts.size()]
	var path := find_path(from, door)
	if path.size() < 2:
		return
	var pts: Array[Vector3] = []
	var step := 0.36
	var acc := 0.0
	for k in range(path.size() - 1):
		var a: Vector3 = path[k]
		var bb: Vector3 = path[k + 1]
		var seg := bb.distance_to(a)
		while acc <= seg:
			pts.append(a.lerp(bb, acc / maxf(seg, 0.001)))
			acc += step
		acc -= seg
	var total := pts.size()
	for k in total:
		var here: Vector3 = pts[k]
		var nxt: Vector3 = pts[mini(k + 1, total - 1)] if k < total - 1 else Vector3(fd[0], 0, fd[1])
		var dir := Vector3(nxt.x - here.x, 0, nxt.z - here.z)
		if dir.length() < 0.01:
			dir = Vector3(-fd[2], 0, -fd[3])
		dir = dir.normalized()
		var left := k % 2 == 0
		var side_v := Vector3.UP.cross(dir) * (0.1 if left else -0.1)
		var x := Vector3.UP.cross(-dir)
		var b := Basis(x, Vector3.UP, -dir).rotated(Vector3.UP, r.randf_range(-0.12, 0.12))
		var age := float(k) / maxf(total - 1, 1)
		_decal("decal_footprint_l" if left else "decal_footprint_r", here + side_v + Vector3(0, 0.01, 0), b,
			Vector3(0.13, 0.25, 0.3), Color(1, 1, 1, lerpf(0.5, 1.0, age)))


static var _detail_table := {}


## Wear on the walls where the eye lands (critique 008, L041): the pale ghosts of posters and
## desks that stood there for years, tape scraps, chair scuffs, a hole or two, grime around the
## outlets, an old flood line, and on some long halls a crayon line that someone dragged along
## the wall as they walked (data/wall_details.json, pipeline/textures/build_wall_details.py).
func _build_wall_details() -> void:
	if _detail_table.is_empty():
		_detail_table = JSON.parse_string(FileAccess.get_file_as_string("res://data/wall_details.json"))
	var r := _rng("level0:walldetail")
	var walls: Array = L["walls"]
	if walls.is_empty():
		return
	var used := {}
	var place := func(slug: String, alpha: float, wall_i: int = -1, at: float = -1.0, side_in: float = 0.0) -> bool:
		var info: Dictionary = _detail_table.get(slug, {})
		if info.is_empty():
			return false
		var tiled: bool = info.get("tile", false)
		var w: float = float(info["w"]) * (1.0 if tiled else r.randf_range(0.9, 1.1))
		var h: float = float(info["h"]) * w / float(info["w"])
		for attempt in (1 if wall_i >= 0 else 14):
			var i := wall_i if wall_i >= 0 else r.randi() % walls.size()
			var wl: Array = walls[i]
			var horiz := _is_horizontal(wl)
			var a: float = minf(wl[0], wl[2]) if horiz else minf(wl[1], wl[3])
			var b: float = maxf(wl[0], wl[2]) if horiz else maxf(wl[1], wl[3])
			var margin := 0.0 if tiled else 0.16
			if b - a < w + 2.0 * margin:
				continue
			var side := side_in if side_in != 0.0 else (1.0 if r.randf() < 0.5 else -1.0)
			var t := at if at >= 0.0 else r.randf_range(a + w * 0.5 + margin, b - w * 0.5 - margin)
			var key := i * 2 + (0 if side > 0.0 else 1)
			var clash := false
			for iv in used.get(key, []):
				if t - w * 0.5 < iv[1] and t + w * 0.5 > iv[0]:
					clash = true
			if clash:
				continue
			var c := Vector2(t, wl[1]) if horiz else Vector2(wl[0], t)
			var n := Vector2(0, side) if horiz else Vector2(side, 0)
			var probe := Vector3(c.x + n.x * 0.6, 0.0, c.y + n.y * 0.6)
			if probe.x < 0.3 or probe.z < 0.3 or probe.x > extent.x - 0.3 or probe.z > extent.y - 0.3 or not is_walkable(probe):
				continue
			var y := r.randf_range(float(info["y"][0]), float(info["y"][1]))
			var n3 := Vector3(n.x, 0.0, n.y)
			var spin := 0.0 if tiled else r.randf_range(-0.03, 0.03)
			_decal(String(info["tex"]), Vector3(c.x, y, c.y) + n3 * T * 0.5, _basis_facing(n3).rotated(n3, spin), Vector3(w, 0.3, h), Color(1, 1, 1, alpha))
			if not used.has(key):
				used[key] = []
			used[key].append([t - w * 0.5, t + w * 0.5])
			return true
		return false
	for k in r.randi_range(6, 10):
		place.call("scuffs_%d" % r.randi_range(1, 4), r.randf_range(0.55, 0.9))
	for k in r.randi_range(1, 3):
		place.call(["poster_ghost_a", "poster_ghost_b", "poster_ghost_c"][r.randi() % 3], r.randf_range(0.3, 0.5))
	for k in r.randi_range(0, 2):
		place.call("desk_ghost", r.randf_range(0.35, 0.55))
	for k in r.randi_range(2, 4):
		place.call("tape_scraps_%d" % r.randi_range(1, 3), r.randf_range(0.8, 1.0))
	if r.randf() < 0.3:
		place.call("hole_punch" if r.randf() < 0.6 else "hole_knob", 1.0)
	if r.randf() < 0.35:
		place.call("damp_bloom", r.randf_range(0.45, 0.7))
	for o in _outlet_spots:
		if r.randf() < 0.45:
			var on: Vector2 = o[1]
			var op: Vector2 = o[0]
			var n4 := Vector3(on.x, 0.0, on.y)
			_decal("walldetail/outlet_grime", Vector3(op.x, float(o[2]) + 0.03, op.y), _basis_facing(n4), Vector3(0.22, 0.3, 0.22), Color(1, 1, 1, r.randf_range(0.5, 0.8)))
	# An old flood line along one long wall.
	if r.randf() < 0.16:
		var best := -1
		var best_len := 4.0
		for i in walls.size():
			var wl2: Array = walls[i]
			var ln: float = absf(wl2[2] - wl2[0]) + absf(wl2[3] - wl2[1])
			if ln > best_len:
				best_len = ln
				best = i
		if best >= 0:
			_tile_along(place, best, "water_line", r.randf_range(0.65, 0.9), 1.0 if r.randf() < 0.5 else -1.0)
	# The line: someone walked this hall dragging a crayon along the wall (Level0Gen "trails").
	for tr in L.get("trails", []):
		for i in walls.size():
			var wl3: Array = walls[i]
			if _is_horizontal(wl3) and absf(wl3[1] - float(tr[0])) < 0.01:
				_tile_along(place, i, "crayon_trail", 0.9, float(tr[1]))


## Lays a horizontally tileable wall detail end to end along wall i, on one side.
func _tile_along(place: Callable, i: int, slug: String, alpha: float, side: float) -> void:
	var wl: Array = L["walls"][i]
	var horiz := _is_horizontal(wl)
	var a: float = minf(wl[0], wl[2]) if horiz else minf(wl[1], wl[3])
	var b: float = maxf(wl[0], wl[2]) if horiz else maxf(wl[1], wl[3])
	var w: float = float(_detail_table[slug]["w"])
	# Start on the world 2.4 m grid so a line carries on seamlessly into the next chunk.
	var o := origin2().x if horiz else origin2().y
	var t := (ceilf((a + o) / w) * w - o) + w * 0.5
	while t + w * 0.5 <= b + 0.001:
		place.call(slug, alpha, i, t, side)
		t += w


## Props (procedural Blender set plus Sketchfab CC-BY models, credited in docs/CREDITS.md):
## a few abandoned office things, placed at seeded picks from hand-chosen spots.
const PROPS := {
	"prop_office_chair": {"n": 1, "half": 0.3, "spots": [[24.3, 6.6], [20.2, 3.1], [27.4, 10.6]]},
	"prop_office_chair_alt_sf": {"n": 1, "half": 0.3, "spots": [[8.0, 11.8], [16.6, 27.8], [28.2, 17.0]]},
	"prop_folding_chair_sf": {"n": 2, "half": 0.25, "spots": [[2.0, 1.2], [11.6, 3.4], [22.6, 19.6], [4.5, 27.5], [27.8, 28.6]]},
	"prop_crt_monitor_sf": {"n": 1, "half": 0.22, "spots": [[12.5, 0.5], [5.6, 12.6], [16.4, 20.6]], "tint": [0.95, 0.88, 0.72]},
	"prop_cardboard_box_sf": {"n": 2, "half": 0.3, "spots": [[0.5, 6.0], [28.6, 20.5], [12.4, 21.2], [2.0, 3.4]]},
	"prop_cardboard_box": {"n": 1, "half": 0.24, "spots": [[13.6, 29.5], [0.5, 12.5], [29.5, 14.0]]},
}


func _build_props() -> void:
	var r := _rng("level0:props")
	if L.has("props"):
		for pr in L["props"]:
			var path0 := "res://assets/props/level0/%s.glb" % pr[0]
			if not ResourceLoader.exists(path0):
				continue
			var inst0 := PropCache.make(path0)
			inst0.position = Vector3(pr[1], 0.0, pr[2])
			inst0.rotation.y = deg_to_rad(float(pr[3]))
			add_child(inst0)
			var half0: float = PROPS.get(pr[0], {}).get("half", 0.3)
			if PROPS.get(pr[0], {}).has("tint"):
				var tt: Array = PROPS[pr[0]]["tint"]
				_tint(inst0, Color(tt[0], tt[1], tt[2]))
			_contact_shadow(Vector3(pr[1], 0.0, pr[2]), half0)
			solids.append(Rect2(pr[1] - half0, pr[2] - half0, half0 * 2.0, half0 * 2.0))
		return
	var names := PROPS.keys()
	names.sort()
	for name in names:
		var spec: Dictionary = PROPS[name]
		var path := "res://assets/props/level0/%s.glb" % name
		if not ResourceLoader.exists(path):
			continue
		var cands: Array = spec["spots"].duplicate()
		for k in int(spec["n"]):
			if cands.is_empty():
				break
			var spot: Array = cands.pop_at(r.randi() % cands.size())
			var inst := PropCache.make(path)
			inst.position = Vector3(spot[0], 0.0, spot[1])
			inst.rotation.y = r.randf() * TAU
			add_child(inst)
			if spec.has("tint"):
				_tint(inst, Color(spec["tint"][0], spec["tint"][1], spec["tint"][2]))
			var half: float = spec["half"]
			_contact_shadow(Vector3(spot[0], 0.0, spot[1]), half)
			solids.append(Rect2(spot[0] - half, spot[1] - half, half * 2.0, half * 2.0))


## Generation-loss splice errors (VISION "Generation loss", DECISIONS D009): things copied
## slightly wrong. A chair halfway into a wall, a box sunk into the carpet, the same chair
## repeated like a looped frame.
func _build_splices() -> void:
	for sp in L.get("splices", []):
		var path := "res://assets/props/level0/%s.glb" % sp["prop"]
		if not ResourceLoader.exists(path):
			continue
		var n := int(sp.get("repeat", 1))
		var step: Array = sp.get("step", [0.0, 0.0])
		for k in n:
			var inst := PropCache.make(path)
			var x: float = float(sp["pos"][0]) + float(step[0]) * k
			var z: float = float(sp["pos"][1]) + float(step[1]) * k
			var flip := bool(sp.get("flip", false))
			# A flipped copy stands on the ceiling, upside down, as if the frame was inverted.
			inst.position = Vector3(x, H if flip else float(sp.get("y", 0.0)), z)
			inst.rotation = Vector3(PI if flip else 0.0, deg_to_rad(float(sp["yaw"])), 0.0)
			add_child(inst)
			var half: float = sp.get("half", 0.25)
			if flip:
				_decal("decal_contact", Vector3(x, H, z), _basis_facing(Vector3.DOWN), Vector3(half * 2.6, 0.4, half * 2.6), Color(1, 1, 1, 0.6))
			elif float(sp.get("y", 0.0)) >= 0.0:
				_contact_shadow(Vector3(x, 0.0, z), half)
			if sp.has("seam"):
				# Where the copy and the wall overlap, the wallpaper darkens like a bad splice.
				var sn: Array = sp["seam"]
				var nrm := Vector3(sn[0], 0, sn[1])
				_decal("decal_contact", Vector3(x, 0.55, z) - nrm * 0.12, _basis_facing(nrm), Vector3(1.0, 0.4, 1.3), Color(1, 1, 1, 0.8))
			solids.append(Rect2(x - half, z - half, half * 2.0, half * 2.0))


## A soft dark footprint under a prop so it sits on the carpet (critique 005: props looked
## like they floated).
var _pending_contacts: Array = []


func _contact_shadow(p: Vector3, half: float) -> void:
	var sz := half * 2.6
	_decal("decal_contact", p, _basis_facing(Vector3.UP), Vector3(sz, 0.4, sz), Color(1, 1, 1, 0.75))


## Copy errors that read as deliberate: a ceiling troffer installed sideways on a wall, still
## lit, and a flight of carpeted stairs that climbs straight into the ceiling tiles.
func _build_wrong_architecture(kit: MeshKit) -> void:
	for wf in L.get("wall_fixtures", []):
		var n := Vector3(wf[2], 0.0, wf[3])
		var t := Vector3.UP.cross(n)
		var pos := Vector3(wf[0], wf[4], wf[1])
		var fx := Fixture.new()
		fx.name = "wall_fixture"
		fx.position = Vector3(pos.x, 0.0, pos.z)
		add_child(fx)
		var lens := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.58, 1.18)
		lens.mesh = q
		lens.material_override = mats["lens"]
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lens.transform = Transform3D(Basis(t, Vector3.UP, n), pos + n * 0.012)
		add_child(lens)
		fx.lens = lens
		var a := pos - t * 0.32 - Vector3(0, 0.62, 0)
		var b := pos + t * 0.32 + Vector3(0, 0.62, 0) + n * 0.008
		kit.box("housing", Vector3(minf(a.x, b.x), a.y, minf(a.z, b.z)), Vector3(maxf(a.x, b.x), b.y, maxf(a.z, b.z)), MeshKit.ALL, H)
		fx.mount = Fixture.Mount.WALL
		var sl := Fixture.make_ceiling_light()
		sl.spot_angle = 80.0
		sl.light_color = Color(0.96, 1.0, 0.9)
		sl.transform = Transform3D(Basis.looking_at(n, Vector3.UP), pos + n * 0.05)
		add_child(sl)
		fx.light = sl
		fx.setup(Fixture.State.ON, _rng("level0:wallfixture"), 0.9, Color(0.96, 1.0, 0.9))
		fx.apply()
		fixtures.append(fx)
	for st in L.get("stairs", []):
		_build_stairs(kit, st)


## Seams (D022): a door-sized patch of a pocket's wall that exists only for the naked eye. It is
## drawn on render layer 12, which the camera stops drawing when the camcorder is up, and it has
## no collision. Above it a normal lintel; its baseboard is eye-only too.
const SEAM_H := 2.15


func _build_seams(kit: MeshKit) -> void:
	for sm in L.get("seams", []):
		var w: Array = sm["wall"]
		var horiz := _is_horizontal(w)
		var r := _wall_rect(w, 0.0, 0.0)
		var long_faces := (MeshKit.PZ | MeshKit.NZ) if horiz else (MeshKit.PX | MeshKit.NX)
		kit.box("seam_wall", Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, SEAM_H, r.end.y), long_faces, H)
		kit.box("wall", Vector3(r.position.x, SEAM_H, r.position.y), Vector3(r.end.x, H, r.end.y), long_faces | MeshKit.NY, H)
		var bb := 0.012
		var g := r.grow_individual(0.0, bb, 0.0, bb) if horiz else r.grow_individual(bb, 0.0, bb, 0.0)
		kit.box("seam_base", Vector3(g.position.x, 0.0, g.position.y), Vector3(g.end.x, 0.1, g.end.y), long_faces | MeshKit.PY, 0.1)
		var wa := 0.022
		var ga := r.grow_individual(0.0, wa, 0.0, wa) if horiz else r.grow_individual(wa, 0.0, wa, 0.0)
		kit.box("tbar", Vector3(ga.position.x, H - wa, ga.position.y), Vector3(ga.end.x, H, ga.end.y), long_faces | MeshKit.NY, H)


var seam_fx: Array[MeshInstance3D] = []
static var _tear_mat: ShaderMaterial


## What only the tape shows at a seam (a torn outline where the wall is missing), and the survey
## crew's work light inside the pocket.
func _build_seam_fx() -> void:
	if _tear_mat == null:
		_tear_mat = ShaderMaterial.new()
		_tear_mat.shader = load("res://shaders/seam_tear.gdshader")
		_tear_mat.set_shader_parameter("size_m", Vector2(1.2, SEAM_H))
	for sm in L.get("seams", []):
		var w: Array = sm["wall"]
		var n := Vector3(sm["n"][0], 0.0, sm["n"][1])
		var t := Vector3.UP.cross(n)
		var c := Vector3((w[0] + w[2]) * 0.5, SEAM_H * 0.5, (w[1] + w[3]) * 0.5)
		for k in 2:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(Vector2(w[0], w[1]).distance_to(Vector2(w[2], w[3])), SEAM_H)
			q.mesh = qm
			q.material_override = _tear_mat
			q.layers = TapeEvents.LAYER_TAPE
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			q.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			var nn := n if k == 0 else -n
			q.transform = Transform3D(Basis(Vector3.UP.cross(nn), Vector3.UP, nn), c + nn * (T * 0.5 + 0.004))
			add_child(q)
			seam_fx.append(q)
	for wl in L.get("worklights", []):
		var pos := Vector3(wl[0], 0.0, wl[1])
		var yaw := deg_to_rad(float(wl[2]))
		var path := "res://assets/props/level0/prop_worklight_box_sf.glb"
		if ResourceLoader.exists(path):
			var inst := PropCache.make(path)
			inst.position = pos
			inst.rotation.y = yaw
			add_child(inst)
			_contact_shadow(pos, 0.22)
		var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.71, 0.42)   # a halogen lamp: the one warm, hard light in the Yellow
		sl.light_energy = 1.05
		sl.spot_range = 6.5
		sl.spot_angle = 52.0
		sl.spot_attenuation = 1.1
		sl.spot_angle_attenuation = 1.6
		sl.shadow_enabled = true
		sl.shadow_bias = 0.04
		sl.light_size = 0.08
		sl.distance_fade_enabled = true
		sl.distance_fade_begin = 22.0
		sl.distance_fade_length = 6.0
		var lp := pos + Vector3(0, 0.22, 0) + fwd * 0.2
		var target := pos + fwd * 2.4 + Vector3(0, 1.45, 0)
		sl.transform = Transform3D(Basis.looking_at(target - lp, Vector3.UP), lp)
		add_child(sl)
		# A little of it bounces off the floor and walls of the pocket.
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.76, 0.5)
		fill.light_energy = 0.14
		fill.omni_range = 2.6
		fill.position = pos + fwd * 1.2 + Vector3(0, 0.9, 0)
		add_child(fill)


## A flight of carpeted stairs that the building grew by mistake (critique 006, L022): the same
## wallpaper, carpet, vinyl nosing and baseboard as everything else, a handrail on the wall,
## and it climbs straight up through a gap in the ceiling tiles into the dark above.
func _build_stairs(kit: MeshKit, st: Array) -> void:
	var o := Vector2(st[0], st[1])
	var d := Vector2(st[2], st[3])
	var side := Vector2(-d.y, d.x)
	if side.x < 0.0 or side.y < 0.0:
		side = -side
	var w: float = st[4]
	var rise := 0.18
	var run := 0.28
	var top := float(L["plenum_height"])
	var steps := int(ceil(top / rise))
	var dir3 := Vector3(d.x, 0, d.y)
	var side3 := Vector3(side.x, 0, side.y)
	var o3 := Vector3(o.x, 0, o.y)
	var open_face := MeshKit.PZ if side.y > 0.5 else MeshKit.PX
	var riser_face := MeshKit.NX if d.x > 0.5 else (MeshKit.PX if d.x < -0.5 else (MeshKit.NZ if d.y > 0.5 else MeshKit.PZ))
	var aabb := func(p: Vector3, q: Vector3) -> Array:
		return [Vector3(minf(p.x, q.x), minf(p.y, q.y), minf(p.z, q.z)), Vector3(maxf(p.x, q.x), maxf(p.y, q.y), maxf(p.z, q.z))]
	for i in steps:
		var y1 := minf((i + 1) * rise, top)
		var b: Array = aabb.call(o3 + dir3 * (i * run), o3 + dir3 * ((i + 1) * run) + side3 * w + Vector3(0, y1, 0))
		kit.box("carpet", b[0], b[1], MeshKit.PY | riser_face, H)
		kit.box("wall", b[0], b[1], open_face, H)
		# vinyl nosing on the front edge of each tread
		var n: Array = aabb.call(o3 + dir3 * (i * run - 0.018) + Vector3(0, y1 - 0.03, 0), o3 + dir3 * (i * run + 0.035) + side3 * (w + 0.006) + Vector3(0, y1 + 0.006, 0))
		kit.box("baseboard", n[0], n[1], MeshKit.ALL, H)
		# stepped skirt board along the open side
		var k: Array = aabb.call(o3 + dir3 * (i * run) + side3 * w + Vector3(0, y1 - 0.11, 0), o3 + dir3 * ((i + 1) * run) + side3 * (w + 0.014) + Vector3(0, y1 - 0.01, 0))
		kit.box("baseboard", k[0], k[1], MeshKit.ALL, H)
		# open the ceiling where the flight passes through it
		if y1 > H - 0.45:
			for t in [0.15, 0.5, 0.85]:
				for u in [0.1, 0.5, 0.9]:
					var q: Vector2 = o + d * ((i + t) * run) + side * (w * u)
					_ceiling_holes[Vector2i(floori(q.x / TILE), floori(q.y / TILE))] = true
	var length := steps * run
	var bb: Array = aabb.call(o3 + side3 * w, o3 + dir3 * length + side3 * (w + 0.014) + Vector3(0, 0.1, 0))
	kit.box("baseboard", bb[0], bb[1], MeshKit.ALL, H)
	# handrail on the wall side, following the pitch of the flight
	var rail_in := 0.07
	var a := o3 + side3 * rail_in + Vector3(0, 0.88, 0) - dir3 * 0.15
	var e := o3 + dir3 * length + side3 * rail_in + Vector3(0, 0.88 + length * rise / run, 0)
	_sloped_bar(kit, "trim", a, e, side3, 0.028, 0.03)
	var e2 := o + d * length + side * w
	solids.append(Rect2(minf(o.x, e2.x), minf(o.y, e2.y), absf(e2.x - o.x), absf(e2.y - o.y)))


## A bar between a and b with a rectangular cross-section (half sizes hw across `side`, hh up).
func _sloped_bar(kit: MeshKit, key: String, a: Vector3, b: Vector3, side: Vector3, hw: float, hh: float) -> void:
	var along := (b - a).normalized()
	var up := side.cross(along).normalized()
	if up.y < 0.0:
		up = -up
	var corners := [side * hw + up * hh, -side * hw + up * hh, -side * hw - up * hh, side * hw - up * hh]
	var l := a.distance_to(b)
	for f in 4:
		var c0: Vector3 = corners[f]
		var c1: Vector3 = corners[(f + 1) % 4]
		var nn: Vector3 = (c0 + c1).normalized()
		kit.quad(key, [a + c0, b + c0, b + c1, a + c1], nn, [Vector2(0, 0), Vector2(l, 0), Vector2(l, 0.05), Vector2(0, 0.05)])


## Ages a model's color (for example, white plastic yellowed by years of fluorescent light).
func _tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.mesh.surface_get_material(i)
			if m is BaseMaterial3D:
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.albedo_color = d.albedo_color * c
				mi.set_surface_override_material(i, d)
	for ch in n.get_children():
		_tint(ch, c)


# ---------------------------------------------------------------- collision and navigation

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "collision"
	add_child(body)
	var add_box := func(center: Vector3, size: Vector3) -> void:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = center
		body.add_child(cs)
	add_box.call(Vector3(extent.x * 0.5, -0.25, extent.y * 0.5), Vector3(extent.x + 2, 0.5, extent.y + 2))
	add_box.call(Vector3(extent.x * 0.5, H + 0.25, extent.y * 0.5), Vector3(extent.x + 2, 0.5, extent.y + 2))
	for s in solids:
		if s.size.x * s.size.y <= 0.0 or s in _edge_solids:
			continue
		add_box.call(Vector3(s.get_center().x, H * 0.5, s.get_center().y), Vector3(s.size.x, H, s.size.y))


func _build_nav() -> void:
	_grid_n = Vector2i(int(ceil(extent.x / CELL)), int(ceil(extent.y / CELL)))
	astar = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, _grid_n)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	var whole := Rect2i(Vector2i.ZERO, _grid_n)
	# People walk down the middle of corridors, not along the wall (filled region by region in
	# C++: a per-cell GDScript loop cost ~20 ms per streamed chunk).
	for s in solids:
		if s.size.x * s.size.y <= 0.0:
			continue
		var g2 := s.grow(AGENT_R + 0.45)
		var a0 := Vector2i(floori(g2.position.x / CELL), floori(g2.position.y / CELL))
		var a1 := Vector2i(ceili(g2.end.x / CELL), ceili(g2.end.y / CELL))
		var rw := Rect2i(a0, a1 - a0 + Vector2i.ONE).intersection(whole)
		if rw.has_area():
			astar.fill_weight_scale_region(rw, 4.0)
	# Solid: every cell whose center lies inside the wall grown by the agent radius.
	for s in solids:
		if s.size.x * s.size.y <= 0.0:
			continue
		var g := s.grow(AGENT_R)
		var c0 := Vector2i(ceili(g.position.x / CELL - 0.5), ceili(g.position.y / CELL - 0.5))
		var c1 := Vector2i(floori(g.end.x / CELL - 0.5), floori(g.end.y / CELL - 0.5))
		var rs := Rect2i(c0, c1 - c0 + Vector2i.ONE).intersection(whole)
		if rs.has_area():
			astar.fill_solid_region(rs, true)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, _grid_n.x - 1), clampi(int(p.z / CELL), 0, _grid_n.y - 1))


func _free_cell(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for rad in range(1, 12):
		for dx in range(-rad, rad + 1):
			for dy in range(-rad, rad + 1):
				var q := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(q) and not astar.is_point_solid(q):
					return q
	return c


func is_walkable(p: Vector3) -> bool:
	var c := _cell(p)
	return not astar.is_point_solid(c)


func _los(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / (CELL * 0.5)) + 1
	for k in steps + 1:
		var q := a.lerp(b, float(k) / steps)
		var c := Vector2i(int(q.x / CELL), int(q.y / CELL))
		if not astar.is_in_boundsv(c) or astar.is_point_solid(c):
			return false
	return true


## Distance of clear floor from p along a horizontal direction (used to look somewhere open).
func view_depth(p: Vector3, yaw: float, max_d: float = 20.0) -> float:
	var dir := Vector2(-sin(yaw), -cos(yaw))
	var a := Vector2(p.x, p.z)
	var d := 0.0
	while d < max_d:
		d += CELL
		var q := a + dir * d
		var c := Vector2i(int(q.x / CELL), int(q.y / CELL))
		if not astar.is_in_boundsv(c) or astar.is_point_solid(c):
			return d
	return max_d


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := _free_cell(_cell(from))
	var b := _free_cell(_cell(to))
	var ids := astar.get_id_path(a, b)
	var pts: Array[Vector2] = []
	for id in ids:
		pts.append(Vector2((id.x + 0.5) * CELL, (id.y + 0.5) * CELL))
	if pts.is_empty():
		return PackedVector3Array()
	# String-pull: keep only the corners we actually need.
	var out := PackedVector3Array()
	var anchor := pts[0]
	out.append(Vector3(anchor.x, 0, anchor.y))
	var k := 1
	while k < pts.size():
		var j := k
		while j + 1 < pts.size() and _los(anchor, pts[j + 1]):
			j += 1
		anchor = pts[j]
		out.append(Vector3(anchor.x, 0, anchor.y))
		k = j + 1
	return out


func get_interest_points() -> Array:
	var out := []
	for it in L["interest"]:
		var e := {"name": it["name"], "pos": Vector3(it["p"][0], 0.0, it["p"][1])}
		if it.has("seam"):
			e["seam"] = Vector3(it["seam"][0], 0.0, it["seam"][1])
			e["pocket"] = Vector3(it["pocket"][0], 0.0, it["pocket"][1])
		out.append(e)
	return out


func get_spawn_transform() -> Transform3D:
	var s: Array = L["spawn"]
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(float(s[2]))), Vector3(s[0], 0.0, s[1]))


func floor_wetness(p: Vector3) -> float:
	var v := Vector2(p.x, p.z)
	var f := NoiseUtil.fbm((v + origin2()) * WET_SCALE + seed_offset)   # same field the carpet shader draws (world space)
	var w := smoothstep(WET_LO, WET_HI, f)
	for lk in leaks:
		w = maxf(w, 1.0 - smoothstep(0.6, 1.3, v.distance_to(lk)))
	if flood.grow(-0.2).has_point(v):
		w = 1.0
	return w


# ---------------------------------------------------------------- sound level of detail

func _snd(name: String) -> AudioStream:
	var p := SND + name + ".wav"
	if ResourceLoader.exists(p):
		return load(p)
	return null


func set_listener(p: Vector3) -> void:
	_listener_pos = p


func _process(delta: float) -> void:
	if field == null:
		return
	field.update()
	if pooled:
		return
	# Own hum and buzz players only run near the listener.
	_audio_timer -= delta
	if _audio_timer <= 0.0:
		_audio_timer = 0.25
		for fx in fixtures:
			var near := fx.global_position.distance_to(_listener_pos) < 11.0
			for pl in [fx.hum, fx.buzz]:
				if pl == null:
					continue
				if near and not pl.playing:
					pl.play(fx.audio_offset)
				elif not near and pl.playing:
					pl.stop()
