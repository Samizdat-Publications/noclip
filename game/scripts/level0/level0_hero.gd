class_name Level0Hero
extends Space
## Level 0 look-dev hero slice: a fixed 30 x 30 m layout (data/level0_hero.json) with seeded
## decay on top: which tubes are dead or failing, ceiling leaks, stains, wet carpet, missing
## tiles. The layout is shared with the three.js spike so both engines build the same place.

const LAYOUT := "res://data/level0_hero.json"
const SND := "res://assets/audio/level0/"
const TEXD := "res://assets/textures/level0/"
const CELL := 0.2
const AGENT_R := 0.34
const TILE := 0.6
const WET_SCALE := 0.13
const WET_LO := 0.56
const WET_HI := 0.70

var L: Dictionary
var H: float = 2.6
var T: float = 0.2
var DH: float = 2.1
var extent := Vector2(30, 30)
var mats: Dictionary
var fixtures: Array[Fixture] = []
var seed_offset := Vector2.ZERO
var solids: Array[Rect2] = []
var leaks: Array[Vector2] = []
var astar: AStarGrid2D
var _grid_n := Vector2i.ZERO
var _audio_timer := 0.0
var _thud_timer := 0.0
var _rng_amb: RandomNumberGenerator
var _thud_player: AudioStreamPlayer3D
var _listener_pos := Vector3.ZERO


func build(p_seed: int) -> void:
	super.build(p_seed)
	space_id = &"level0_hero"
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	H = float(L["ceiling_height"])
	T = float(L["wall_thickness"])
	DH = float(L["door_height"])
	extent = Vector2(float(L["size"][0]), float(L["size"][1]))
	var r := Game.rng("level0:look")
	seed_offset = Vector2(r.randf_range(0.0, 50.0), r.randf_range(0.0, 50.0))
	mats = Level0Look.make_materials(seed_offset)
	_collect_solids()
	_pick_leaks()
	var kit := MeshKit.new()
	_build_shell(kit)
	_build_walls(kit)
	_build_doors(kit)
	var fixture_cells := _build_fixtures(kit)
	_build_ceiling(kit, fixture_cells)
	kit.commit(self, mats, ["tbar", "housing"])
	_build_decals()
	_build_collision()
	_build_nav()
	_build_ambience()


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
	for p in L["pillars"]:
		var s: float = p[2]
		solids.append(Rect2(p[0] - s * 0.5, p[1] - s * 0.5, s, s))


func _hits_solid(r: Rect2) -> bool:
	for s in solids:
		if s.intersects(r):
			return true
	return false


func _pick_leaks() -> void:
	var r := Game.rng("level0:leaks")
	var n := r.randi_range(3, 6)
	var tries := 0
	while leaks.size() < n and tries < 200:
		tries += 1
		var p := Vector2(r.randf_range(1.0, extent.x - 1.0), r.randf_range(1.0, extent.y - 1.0))
		if _hits_solid(Rect2(p - Vector2(0.4, 0.4), Vector2(0.8, 0.8))):
			continue
		var spawn := Vector2(L["spawn"][0], L["spawn"][1])
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
	for p in L["pillars"]:
		var s: float = p[2]
		kit.box("wall", Vector3(p[0] - s * 0.5, 0.0, p[1] - s * 0.5), Vector3(p[0] + s * 0.5, H, p[1] + s * 0.5), MeshKit.SIDES, H)
		var q := s * 0.5 + bb
		kit.box("baseboard", Vector3(p[0] - q, 0.0, p[1] - q), Vector3(p[0] + q, bh, p[1] + q), MeshKit.SIDES | MeshKit.PY, bh)


func _build_doors(kit: MeshKit) -> void:
	var cw := 0.07    # casing width
	var cp := 0.018   # casing projection from the wall face
	var li := 0.02    # jamb lining thickness
	for d in L["doors"]:
		var horiz: bool = absf(d[1] - d[3]) < 0.001
		var a: float = minf(d[0], d[2]) if horiz else minf(d[1], d[3])
		var b: float = maxf(d[0], d[2]) if horiz else maxf(d[1], d[3])
		var c: float = d[1] if horiz else d[0]
		var boxes := []  # [key, min(along, y, across), max(along, y, across)]
		boxes.append(["wall", Vector3(a, DH, c - T * 0.5), Vector3(b, H, c + T * 0.5)])
		boxes.append(["trim", Vector3(a, 0.0, c - T * 0.5), Vector3(a + li, DH, c + T * 0.5)])
		boxes.append(["trim", Vector3(b - li, 0.0, c - T * 0.5), Vector3(b, DH, c + T * 0.5)])
		boxes.append(["trim", Vector3(a, DH - li, c - T * 0.5), Vector3(b, DH, c + T * 0.5)])
		for s in [-1.0, 1.0]:
			var f: float = c + s * T * 0.5
			var f2: float = f + s * cp
			var lo := minf(f, f2)
			var hi := maxf(f, f2)
			boxes.append(["trim", Vector3(a - cw, 0.0, lo), Vector3(a, DH + cw, hi)])
			boxes.append(["trim", Vector3(b, 0.0, lo), Vector3(b + cw, DH + cw, hi)])
			boxes.append(["trim", Vector3(a - cw, DH, lo), Vector3(b + cw, DH + cw, hi)])
		for bx in boxes:
			var mn: Vector3 = bx[1]
			var mx: Vector3 = bx[2]
			if horiz:
				kit.box(bx[0], mn, mx, MeshKit.ALL, H)
			else:
				kit.box(bx[0], Vector3(mn.z, mn.y, mn.x), Vector3(mx.z, mx.y, mx.x), MeshKit.ALL, H)
		solids.append(Rect2())  # doors add no floor obstacles


func _build_fixtures(kit: MeshKit) -> Dictionary:
	var cells := {}
	var fg: Dictionary = L["fixture_grid"]
	var fw: float = fg["w"]
	var fl: float = fg["l"]
	var r := Game.rng("level0:fixtures")
	var lens_mesh := _make_lens_mesh(fw - 0.02, fl - 0.02)
	var dark_zones := []
	for z in L["dark_zones"]:
		dark_zones.append(Rect2(z[0], z[1], z[2] - z[0], z[3] - z[1]))
	# Clusters of dead panels give the level its pools of darkness.
	var spawn := Vector2(L["spawn"][0], L["spawn"][1])
	var clusters := []
	for k in 2:
		clusters.append(Vector2(r.randf_range(3.0, extent.x - 3.0), r.randf_range(3.0, extent.y - 3.0)))
	var hints := []
	for h in L["failing_hint"]:
		hints.append(Vector2(h[0], h[1]))
	# AreaLight3D shadows in 4.7.2 draw curved projection artifacts (DECISIONS D006); spot
	# lights with soft PCSS shadows are clean, and SSR reflects the real rectangular lens.
	var area_ok := ClassDB.class_exists("AreaLight3D") and Game.opts.has("arealights")
	var hum_a: AudioStream = _snd("hum_fixture_a")
	var hum_b: AudioStream = _snd("hum_fixture_b")
	var buzz_s: AudioStream = _snd("buzz_failing")
	var ticks := []
	for t in 4:
		var s := _snd("tube_tick_%02d" % (t + 1))
		if s:
			ticks.append(s)
	for i in int(fg["nx"]):
		for j in int(fg["nz"]):
			var c := Vector2(float(fg["x0"]) + i * float(fg["dx"]), float(fg["z0"]) + j * float(fg["dz"]))
			var rect := Rect2(c - Vector2(fw, fl) * 0.5, Vector2(fw, fl))
			if _hits_solid(rect.grow(0.04)):
				continue
			var ix := int(floor((c.x - fw * 0.5) / TILE + 0.01))
			var iz := int(floor((c.y - fl * 0.5) / TILE + 0.01))
			cells[Vector2i(ix, iz)] = true
			cells[Vector2i(ix, iz + 1)] = true
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
			for dz in dark_zones:
				if dz.has_point(c):
					in_dark = true
			var near_cluster := false
			for cl in clusters:
				if c.distance_to(cl) < 3.6:
					near_cluster = true
			if in_dark:
				st = Fixture.State.STARTER if roll < 0.12 else Fixture.State.DEAD
			elif near_cluster and roll < 0.6:
				st = Fixture.State.DEAD
			elif roll < 0.06:
				st = Fixture.State.DEAD
			elif roll < 0.085:
				st = Fixture.State.STARTER
			elif roll < 0.11:
				st = Fixture.State.PULSE
			elif roll < 0.145:
				st = Fixture.State.DROPOUT
			for h in hints:
				if c.distance_to(h) < 1.3:
					st = Fixture.State.PULSE
			if c.distance_to(spawn) < 3.2 and st != Fixture.State.PULSE:
				st = Fixture.State.ON
			var tint_roll := r.randf()
			var tint := Color(1.0, 0.975, 0.9)
			if tint_roll < 0.18:
				tint = Color(0.93, 1.0, 0.86)    # greenish cool-white tube
			elif tint_roll < 0.3:
				tint = Color(1.0, 0.93, 0.84)    # warmer, slightly pink aged tube
			var energy := r.randf_range(0.82, 1.04)

			var fx := Fixture.new()
			fx.name = "fixture_%d_%d" % [i, j]
			fx.position = Vector3(c.x, 0.0, c.y)
			add_child(fx)
			var lens := MeshInstance3D.new()
			lens.mesh = lens_mesh
			lens.material_override = mats["lens"]
			lens.position = Vector3(0, H + 0.03, 0)
			lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fx.add_child(lens)
			fx.lens = lens
			var light: Light3D
			if area_ok:
				light = ClassDB.instantiate("AreaLight3D")
				light.set("area_size", Vector2(fw - 0.06, fl - 0.06))
				light.set("area_range", 14.0)
				light.set("area_attenuation", 1.6)
				light.set("area_normalize_energy", true)
			else:
				var sl := SpotLight3D.new()
				sl.spot_range = 13.0
				sl.spot_angle = float(Game.opts.get("spot_angle", "82"))
				sl.spot_angle_attenuation = float(Game.opts.get("spot_cone", "0.7"))
				sl.spot_attenuation = float(Game.opts.get("spot_atten", "1.4"))
				sl.light_size = float(Game.opts.get("light_size", "0.8"))
				light = sl
			light.position = Vector3(0, H - 0.004, 0)
			light.rotation = Vector3(-PI * 0.5, 0, 0)
			light.light_color = tint
			light.shadow_enabled = not Game.opts.has("noshadow")
			light.shadow_bias = 0.04
			light.shadow_normal_bias = 1.2
			light.light_specular = 0.85
			light.light_volumetric_fog_energy = 0.7
			light.distance_fade_enabled = true
			light.distance_fade_begin = 22.0
			light.distance_fade_length = 6.0
			light.distance_fade_shadow = 13.0
			fx.add_child(light)
			fx.light = light
			if hum_a:
				var hum := AudioStreamPlayer3D.new()
				hum.stream = hum_a if r.randf() < 0.6 else hum_b
				hum.bus = &"World"
				hum.position = Vector3(0, H - 0.05, 0)
				hum.unit_size = 1.1
				hum.max_distance = 9.0
				hum.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
				hum.pitch_scale = r.randf_range(0.995, 1.005)
				hum.set_meta("offset", r.randf_range(0.0, 7.9))
				fx.add_child(hum)
				fx.hum = hum
			if st != Fixture.State.ON and st != Fixture.State.DEAD and buzz_s:
				var bz := AudioStreamPlayer3D.new()
				bz.stream = buzz_s
				bz.bus = &"World"
				bz.position = Vector3(0, H - 0.05, 0)
				bz.unit_size = 1.4
				bz.max_distance = 14.0
				bz.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
				bz.set_meta("offset", r.randf_range(0.0, 5.9))
				fx.add_child(bz)
				fx.buzz = bz
				if ticks.size() > 0:
					var tk := AudioStreamPlayer3D.new()
					tk.stream = ticks[r.randi() % ticks.size()]
					tk.bus = &"World"
					tk.position = Vector3(0, H - 0.05, 0)
					tk.unit_size = 1.6
					tk.max_distance = 16.0
					tk.volume_db = -6.0
					fx.add_child(tk)
					fx.tick_player = tk
			fx.setup(st, Game.rng("fixture:%d:%d" % [i, j]), energy, tint)
			fx.apply()
			fixtures.append(fx)
	return cells


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
	var r := Game.rng("level0:ceiling")
	var nx := int(round(extent.x / TILE))
	var nz := int(round(extent.y / TILE))
	var spawn := Vector2(L["spawn"][0], L["spawn"][1])
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
			var missing := r.randf() < 0.006 and center.distance_to(spawn) > 4.0
			if missing:
				continue
			var sag := 0.0
			var drop := 0.0
			if stained > 0.0 and r.randf() < 0.25:
				sag = 0.5
				drop = r.randf_range(0.015, 0.04)
			var col := Color(rnd, stained, sag, 1.0)
			var y := H
			var pts := [Vector3(x0, y, z0), Vector3(x0 + TILE, y, z0), Vector3(x0 + TILE, y - drop, z0 + TILE), Vector3(x0, y - drop * 0.4, z0 + TILE)]
			kit.quad("ceiling", pts, Vector3.DOWN, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], col)
	# T-bar grid.
	var hw := 0.012
	var hd := 0.014
	for k in nz + 1:
		var z := k * TILE
		kit.box("tbar", Vector3(0, H - hd, z - hw), Vector3(extent.x, H, z + hw), MeshKit.NY | MeshKit.PZ | MeshKit.NZ, H)
	for k in nx + 1:
		var x := k * TILE
		kit.box("tbar", Vector3(x - hw, H - hd, 0), Vector3(x + hw, H, extent.y), MeshKit.NY | MeshKit.PX | MeshKit.NX, H)


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


func _build_decals() -> void:
	var r := Game.rng("level0:decals")
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
	for k in 26:
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
		if s.size.x * s.size.y <= 0.0:
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
	for s in solids:
		if s.size.x * s.size.y <= 0.0:
			continue
		var g := s.grow(AGENT_R)
		var i0 := clampi(int(floor(g.position.x / CELL)), 0, _grid_n.x - 1)
		var i1 := clampi(int(ceil(g.end.x / CELL)), 0, _grid_n.x - 1)
		var j0 := clampi(int(floor(g.position.y / CELL)), 0, _grid_n.y - 1)
		var j1 := clampi(int(ceil(g.end.y / CELL)), 0, _grid_n.y - 1)
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var c := Vector2((i + 0.5) * CELL, (j + 0.5) * CELL)
				if g.has_point(c):
					astar.set_point_solid(Vector2i(i, j), true)
	# People walk down the middle of corridors, not along the wall.
	for s in solids:
		if s.size.x * s.size.y <= 0.0:
			continue
		var g2 := s.grow(AGENT_R + 0.45)
		var a0 := clampi(int(floor(g2.position.x / CELL)), 0, _grid_n.x - 1)
		var a1 := clampi(int(ceil(g2.end.x / CELL)), 0, _grid_n.x - 1)
		var b0 := clampi(int(floor(g2.position.y / CELL)), 0, _grid_n.y - 1)
		var b1 := clampi(int(ceil(g2.end.y / CELL)), 0, _grid_n.y - 1)
		for i in range(a0, a1 + 1):
			for j in range(b0, b1 + 1):
				var id := Vector2i(i, j)
				if not astar.is_point_solid(id):
					astar.set_point_weight_scale(id, 4.0)


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
		out.append({"name": it["name"], "pos": Vector3(it["p"][0], 0.0, it["p"][1])})
	return out


func get_spawn_transform() -> Transform3D:
	var s: Array = L["spawn"]
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(float(s[2]))), Vector3(s[0], 0.0, s[1]))


func floor_wetness(p: Vector3) -> float:
	var v := Vector2(p.x, p.z)
	var f := NoiseUtil.fbm(v * WET_SCALE + seed_offset)
	var w := smoothstep(WET_LO, WET_HI, f)
	for lk in leaks:
		w = maxf(w, 1.0 - smoothstep(0.6, 1.3, v.distance_to(lk)))
	return w


# ---------------------------------------------------------------- environment and sound

func make_environment() -> Environment:
	return Level0Look.make_environment(Game.preset)


func make_camera_attributes() -> CameraAttributes:
	return Level0Look.make_camera_attributes()


func _snd(name: String) -> AudioStream:
	var p := SND + name + ".wav"
	if ResourceLoader.exists(p):
		return load(p)
	return null


func _build_ambience() -> void:
	_rng_amb = Game.rng("level0:ambience")
	var tone := _snd("room_tone")
	if tone:
		var p := AudioStreamPlayer.new()
		p.stream = tone
		p.volume_db = -15.0
		p.bus = &"Master"
		p.autoplay = true
		add_child(p)
	_thud_player = AudioStreamPlayer3D.new()
	_thud_player.bus = &"World"
	_thud_player.unit_size = 6.0
	_thud_player.max_distance = 60.0
	_thud_player.volume_db = -4.0
	add_child(_thud_player)
	_thud_timer = _rng_amb.randf_range(18.0, 40.0)


func set_listener(p: Vector3) -> void:
	_listener_pos = p


func _process(delta: float) -> void:
	_audio_timer -= delta
	if _audio_timer <= 0.0:
		_audio_timer = 0.25
		for fx in fixtures:
			var near := fx.global_position.distance_to(_listener_pos) < 11.0
			for pl in [fx.hum, fx.buzz]:
				if pl == null:
					continue
				if near and not pl.playing:
					pl.play(float(pl.get_meta("offset", 0.0)))
				elif not near and pl.playing:
					pl.stop()
	_thud_timer -= delta
	if _thud_timer <= 0.0:
		_thud_timer = _rng_amb.randf_range(25.0, 60.0)
		var thuds := []
		for k in 3:
			var s := _snd("distant_thud_%02d" % (k + 1))
			if s:
				thuds.append(s)
		if thuds.size() > 0:
			var ang := _rng_amb.randf() * TAU
			_thud_player.global_position = _listener_pos + Vector3(cos(ang), 0.0, sin(ang)) * _rng_amb.randf_range(16.0, 26.0) + Vector3(0, 1.0, 0)
			_thud_player.stream = thuds[_rng_amb.randi() % thuds.size()]
			_thud_player.pitch_scale = _rng_amb.randf_range(0.85, 1.05)
			_thud_player.play()
