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
var flood := Rect2(-100, -100, 1, 1)
var astar: AStarGrid2D
var _grid_n := Vector2i.ZERO
var _audio_timer := 0.0
var _thud_timer := 0.0
var _rng_amb: RandomNumberGenerator
var _thud_player: AudioStreamPlayer3D
var _listener_pos := Vector3.ZERO
var _view_fwd := Vector3.FORWARD
var _rng_evt: RandomNumberGenerator
var _event_t := 1e9
var _event_phase := 0
var _event_restore_t := 0.0
var _event_killed: Array[Fixture] = []
var _fallen_tile := Vector2i(-1, -1)
var _fixture_pairs := {}
var _dump := {"missing_tiles": [], "special_tiles": [], "decals": []}


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
	var fc: Array = L.get("flood_candidates", [])
	if fc.size() > 0:
		var f: Array = fc[r.randi() % fc.size()]
		flood = Rect2(f[0], f[1], f[2] - f[0], f[3] - f[1])
		(mats["carpet"] as ShaderMaterial).set_shader_parameter("flood_rect", Vector4(f[0], f[1], f[2], f[3]))
	_collect_solids()
	_pick_leaks()
	var kit := MeshKit.new()
	_build_shell(kit)
	_build_walls(kit)
	_build_doors(kit)
	_build_fake_doors(kit)
	_build_exit_signs(kit)
	_build_fallen_tile(kit)
	var fixture_cells := _build_fixtures(kit)
	_build_ceiling(kit, fixture_cells)
	kit.commit(self, mats, ["tbar", "housing"])
	_build_decals()
	_build_props()
	_build_collision()
	_build_nav()
	_build_traces()
	_build_ambience()
	if Game.opts.has("dump-scene"):
		_write_dump(String(Game.opts["dump-scene"]))


## Everything the seed decided, for other renderers (engine bake-off) and for tests.
func _write_dump(path: String) -> void:
	var fx := []
	for f in fixtures:
		fx.append({"x": f.position.x, "z": f.position.z, "state": f.state, "energy": f.base_energy,
			"tint": [f.tint.r, f.tint.g, f.tint.b], "cathode": f.cathode_glow})
	_dump["seed"] = space_seed
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
		kit.box("wall", Vector3(p[0] - s * 0.5, 0.0, p[1] - s * 0.5), Vector3(p[0] + s * 0.5, H, p[1] + s * 0.5), MeshKit.SIDES, H)
		var q := s * 0.5 + bb
		kit.box("baseboard", Vector3(p[0] - q, 0.0, p[1] - q), Vector3(p[0] + q, bh, p[1] + q), MeshKit.SIDES | MeshKit.PY, bh)


## Wall outlets every so often near the floor. Nothing is ever plugged into them.
func _build_outlets(kit: MeshKit) -> void:
	var r := Game.rng("level0:outlets")
	var walls: Array = L["walls"]
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
		var p := Vector3(es[0], 2.33, es[1])
		var n := Vector3(es[2], 0, es[3])
		var t := Vector3.UP.cross(n)   # the viewer's right when facing the sign
		var face := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.32, 0.16)
		face.mesh = q
		face.material_override = mats["exit"]
		face.transform = Transform3D(Basis(t, Vector3.UP, n), p + n * 0.051)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(face)
		var a := p - t * 0.17 - Vector3(0, 0.09, 0)
		var b := p + t * 0.17 + Vector3(0, 0.09, 0) + n * 0.05
		kit.box("housing", Vector3(minf(a.x, b.x), a.y, minf(a.z, b.z)), Vector3(maxf(a.x, b.x), b.y, maxf(a.z, b.z)), MeshKit.ALL, H)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.18, 0.1)
		glow.light_energy = 0.35
		glow.omni_range = 1.9
		glow.omni_attenuation = 1.6
		glow.shadow_enabled = false
		glow.position = p + n * 0.25
		add_child(glow)


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
			_fixture_pairs[Vector2i(ix, iz)] = Vector2i(ix, iz + 1)
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
			elif Game.opts.get("lights", "spot") == "omni":
				var ol := OmniLight3D.new()
				ol.omni_range = float(Game.opts.get("spot_range", "7"))
				ol.omni_attenuation = float(Game.opts.get("spot_atten", "1.4"))
				ol.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
				ol.light_size = float(Game.opts.get("light_size", "0.8"))
				light = ol
			else:
				var sl := SpotLight3D.new()
				sl.spot_range = float(Game.opts.get("spot_range", "7"))
				sl.spot_angle = float(Game.opts.get("spot_angle", "82"))
				sl.spot_angle_attenuation = float(Game.opts.get("spot_cone", "1.8"))
				sl.spot_attenuation = float(Game.opts.get("spot_atten", "1.4"))
				sl.light_size = float(Game.opts.get("light_size", "1.2"))
				light = sl
			light.position = Vector3(0, H - 0.004, 0)
			light.rotation = Vector3(-PI * 0.5, 0, 0)
			light.light_color = tint
			light.shadow_enabled = not Game.opts.has("noshadow")
			light.shadow_bias = float(Game.opts.get("sbias", "0.06"))
			light.shadow_blur = float(Game.opts.get("shadow_blur", "2.5"))
			light.shadow_normal_bias = float(Game.opts.get("nbias", "2.6"))
			light.light_specular = 0.85
			light.light_volumetric_fog_energy = float(Game.opts.get("fog_light", "1.3"))
			light.distance_fade_enabled = true
			light.distance_fade_begin = 22.0
			light.distance_fade_length = 6.0
			light.distance_fade_shadow = float(Game.opts.get("shadow_dist", "13"))
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
			var missing := (r.randf() < 0.006 and center.distance_to(spawn) > 4.0) or Vector2i(i, j) == _fallen_tile
			if missing:
				_dump["missing_tiles"].append([i, j])
				continue
			var sag := 0.0
			var drop := 0.0
			if stained > 0.0 and r.randf() < 0.25:
				sag = 0.5
				drop = r.randf_range(0.015, 0.04)
			var col := Color(rnd, stained, sag, 1.0)
			_dump["special_tiles"].append([i, j, snappedf(rnd, 0.001), stained, sag, snappedf(drop, 0.0001)])
			var y := H
			var pts := [Vector3(x0, y, z0), Vector3(x0 + TILE, y, z0), Vector3(x0 + TILE, y - drop, z0 + TILE), Vector3(x0, y - drop * 0.4, z0 + TILE)]
			kit.quad("ceiling", pts, Vector3.DOWN, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], col)
	# T-bar grid, edge by edge, so no bar runs across the middle of a 2x4 light fixture.
	var hw := 0.012
	var hd := 0.014
	for k in nz + 1:
		var z := k * TILE
		var run_start := -1
		for i in nx + 1:
			var skip := i >= nx or (fixture_cells.has(Vector2i(i, k - 1)) and fixture_cells.has(Vector2i(i, k)) and _same_fixture(Vector2i(i, k - 1), Vector2i(i, k)))
			if not skip and run_start == -1:
				run_start = i
			if skip and run_start != -1:
				kit.box("tbar", Vector3(run_start * TILE, H - hd, z - hw), Vector3(i * TILE, H, z + hw), MeshKit.NY | MeshKit.PZ | MeshKit.NZ, H)
				run_start = -1
	for k in nx + 1:
		var x := k * TILE
		kit.box("tbar", Vector3(x - hw, H - hd, 0), Vector3(x + hw, H, extent.y), MeshKit.NY | MeshKit.PX | MeshKit.NX, H)


## True if two ceiling cells belong to the same fixture (its two halves).
func _same_fixture(a: Vector2i, b: Vector2i) -> bool:
	return _fixture_pairs.has(a) and _fixture_pairs[a] == b or _fixture_pairs.has(b) and _fixture_pairs[b] == a


## One ceiling tile has come down and lies on the carpet below its hole.
func _build_fallen_tile(kit: MeshKit) -> void:
	var r := Game.rng("level0:fallen")
	var spawn := Vector2(L["spawn"][0], L["spawn"][1])
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
		kit.quad("ceiling", pts, Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Color(r.randf(), 1.0, 0.6, 1.0))
		# chipped edges
		for e in 4:
			var a: Vector3 = pts[e]
			var bb: Vector3 = pts[(e + 1) % 4]
			var sides: Array[Vector3] = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
			var nrm: Vector3 = b * sides[e]
			kit.quad("ceiling", [a, bb, bb - Vector3(0, 0.014, 0), a - Vector3(0, 0.014, 0)], nrm, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.02), Vector2(0, 0.02)], Color(0.2, 1.0, 0.8, 1.0))
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


## Traces of people who were here before: chalk on the walls and a wet footprint trail
## that walks up to the door that does not open, and stops.
func _build_traces() -> void:
	var r := Game.rng("level0:traces")
	var walls: Array = L["walls"]
	var chalk := [["decal_chalk_arrow", Vector3(0.95, 0.3, 0.48)], ["decal_chalk_tally", Vector3(0.8, 0.3, 0.4)],
		["decal_chalk_x", Vector3(0.62, 0.3, 0.62)], ["decal_chalk_arrow", Vector3(0.8, 0.3, 0.4)], ["decal_chalk_tally", Vector3(0.6, 0.3, 0.3)]]
	var placed := 0
	var tries := 0
	while placed < chalk.size() and tries < 200:
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
			Vector3(0.13, 0.25, 0.3), Color(1, 1, 1, lerpf(0.25, 0.9, age)))


## Props (procedural Blender set plus Sketchfab CC-BY models, credited in docs/CREDITS.md):
## a few abandoned office things, placed at seeded picks from hand-chosen spots.
const PROPS := {
	"prop_office_chair": {"n": 1, "half": 0.3, "spots": [[24.3, 6.6], [20.2, 3.1], [27.4, 10.6]]},
	"prop_office_chair_alt_sf": {"n": 1, "half": 0.3, "spots": [[8.0, 11.8], [16.6, 27.8], [28.2, 17.0]]},
	"prop_folding_chair_sf": {"n": 2, "half": 0.25, "spots": [[2.0, 1.2], [9.9, 1.0], [22.6, 19.6], [4.5, 27.5], [27.8, 28.6]]},
	"prop_crt_monitor_sf": {"n": 1, "half": 0.22, "spots": [[9.6, 0.45], [5.6, 12.6], [16.4, 20.6]], "tint": [0.95, 0.88, 0.72]},
	"prop_cardboard_box_sf": {"n": 2, "half": 0.3, "spots": [[0.5, 6.0], [28.6, 20.5], [12.4, 21.2], [7.0, 0.5]]},
	"prop_cardboard_box": {"n": 1, "half": 0.24, "spots": [[13.6, 29.5], [0.5, 12.5], [29.5, 14.0]]},
}


func _build_props() -> void:
	var r := Game.rng("level0:props")
	var names := PROPS.keys()
	names.sort()
	for name in names:
		var spec: Dictionary = PROPS[name]
		var path := "res://assets/props/level0/%s.glb" % name
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path)
		var cands: Array = spec["spots"].duplicate()
		for k in int(spec["n"]):
			if cands.is_empty():
				break
			var spot: Array = cands.pop_at(r.randi() % cands.size())
			var inst := scene.instantiate() as Node3D
			inst.position = Vector3(spot[0], 0.0, spot[1])
			inst.rotation.y = r.randf() * TAU
			add_child(inst)
			if spec.has("tint"):
				_tint(inst, Color(spec["tint"][0], spec["tint"][1], spec["tint"][2]))
			var half: float = spec["half"]
			solids.append(Rect2(spot[0] - half, spot[1] - half, half * 2.0, half * 2.0))


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
	if flood.grow(-0.2).has_point(v):
		w = 1.0
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
	_rng_evt = Game.rng("level0:events")
	_event_t = _rng_evt.randf_range(26.0, 46.0) if not Game.opts.has("no-events") else 1e9


func set_view(p: Vector3, fwd: Vector3) -> void:
	_view_fwd = fwd


## One dread beat per run: at a seeded moment the lights ahead die one by one, coming toward
## you, and their hum dies with them. Later they stutter back on.
func _run_events() -> void:
	if _event_phase == 0 and Game.clock >= _event_t:
		var cand := []
		for fx in fixtures:
			if fx.state != Fixture.State.ON and fx.state != Fixture.State.PULSE and fx.state != Fixture.State.DROPOUT:
				continue
			var to := Vector3(fx.global_position.x - _listener_pos.x, 0.0, fx.global_position.z - _listener_pos.z)
			var d := to.length()
			if d < 3.0 or d > 17.0:
				continue
			if to.normalized().dot(_view_fwd) < 0.82:
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
		attention_point = (cand[0][1] as Fixture).global_position
		attention_until = Game.clock + 4.0 + k * 0.4
		_event_phase = 1
		_event_restore_t = Game.clock + _rng_evt.randf_range(12.0, 18.0)
	elif _event_phase == 1 and Game.clock >= _event_restore_t:
		var k := 0
		for fx in _event_killed:
			fx.restore(k * _rng_evt.randf_range(0.2, 0.6) + _rng_evt.randf_range(0.0, 0.3))
			k += 1
		_event_phase = 2


func set_listener(p: Vector3) -> void:
	_listener_pos = p


func _process(delta: float) -> void:
	_run_events()
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
