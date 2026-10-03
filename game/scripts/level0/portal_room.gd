class_name PortalRoom
extends Node3D
## The hall inside a storeroom (M2b, D036). A 3.6 m storeroom stands free in a room of Level 0;
## its door opens onto a pillar hall 72 x 72 m with a high ceiling, built out of sight under the
## level (one of three depths, so neighbors never overlap). Three portals tie it together:
##   door   the storeroom door, seen from the room: shows the hall, walking in takes you there;
##   back   the hall's entrance, seen from inside: shows the room, walking out takes you back;
##   far    the door at the hall's far end, under an exit sign: it lets you out of the same
##          storeroom door you went in by, facing out into the room.
## The hall has its own render layer (POCKET), its own small light pool and is built a chunk step
## at a time by Level0World, like the level itself. This node's frame is hall-local: x from the
## entrance wall (0) to the far wall (72), z across (0..72), the doors at z = 36.

const POCKET := 1 << 12          # render layer 13
const LEVEL := 1                 # render layer 1 (everything in the level)
const N := 3                     # chunks per side
const SIDE := 24.0 * N
const MID := SIDE * 0.5
const HALL_H := 4.4
const DEPTHS := [-14.0, -26.0, -38.0, -50.0, -62.0]
const OPENING := Vector2(1.16, 2.08)

var world: Level0World
var key := ""                    # "cx:cz"
var door_world := Vector3.ZERO   # middle of the storeroom doorway, at the floor
var n := Vector2.ZERO            # the storeroom door's outward normal
var chunks: Array[Level0Chunk] = []
var pool: FixturePool
var portal_in: Portal            # storeroom door -> hall
var portal_back: Portal          # hall entrance -> room
var portal_far: Portal           # hall far door -> out of the storeroom door
var steps: Array = []            # pending build steps (Callables), run by Level0World
var built := false


## The hall's footprint on the ground plan (world x/z) for a storeroom door, before it is built.
static func footprint(door_w: Vector3, nn: Vector2) -> Rect2:
	var bx := Vector3(-nn.x, 0.0, -nn.y)
	var bz := bx.cross(Vector3.UP)
	var o := door_w - bz * MID
	var r := Rect2(Vector2(o.x, o.z), Vector2.ZERO)
	for c in [o + bx * SIDE, o + bz * SIDE, o + bx * SIDE + bz * SIDE]:
		r = r.expand(Vector2(c.x, c.z))
	return r.grow(2.0)


var depth_index := 0
var plan_rect := Rect2()
# Each hall has its own palette (S05, L118: "the same mustard everywhere"; L124: papered columns).
# Colors are sRGB-ish multipliers on the level's own materials; "tube" tints every panel.
const PALETTES := {
	"yellow": {"pillar": [0.8, 0.68, 0.34]},
	"cold": {"wall_tint": [0.84, 0.88, 0.95], "wall_sat": 0.12, "carpet_sat": 0.25, "carpet_tint": [0.8, 0.86, 0.98],
		"ceil_tint": [0.93, 0.96, 1.02], "pillar": [0.6, 0.62, 0.64], "tube": [0.84, 0.9, 1.0], "fog": [0.88, 0.91, 0.97]},
	"green": {"wall_tint": [0.84, 1.03, 0.86], "wall_sat": 0.35, "carpet_sat": 0.6, "carpet_tint": [0.92, 1.02, 0.9],
		"pillar": [0.7, 0.78, 0.68], "tube": [0.92, 1.0, 0.86], "fog": [0.9, 0.94, 0.88]},
}
var palette := "yellow"
var floor_y := 0.0               # world height of the hall's floor (its shaders shade by height)
var field: FixtureField


func setup(p_world: Level0World, c: Vector2i, closet: Dictionary, salt: String, p_depth: int = 0) -> void:
	world = p_world
	key = "%d:%d" % [c.x, c.y]
	var d: Vector2 = closet["door"]
	n = closet["n"]
	door_world = Vector3(c.x * Level0World.CHUNK + d.x, 0.0, c.y * Level0World.CHUNK + d.y)
	depth_index = p_depth
	plan_rect = footprint(door_world, n)
	var dy: float = DEPTHS[p_depth % DEPTHS.size()]
	floor_y = door_world.y + dy
	var bx := Vector3(-n.x, 0.0, -n.y)
	var bz := bx.cross(Vector3.UP)
	var b := Basis(bx, Vector3.UP, bz)
	global_transform = Transform3D(b, door_world + Vector3(0, dy, 0) - b * Vector3(0, 0, MID))
	name = "portal_room_%d_%d" % [c.x, c.y]
	var pr := Game.rng("hallpalette:%d:%d" % [c.x, c.y]).randf()
	# Weighted away from yellow (critique 022: "everything is the same mustard"; L118): the hall is
	# somewhere else.
	palette = "cold" if pr < 0.45 else ("green" if pr < 0.7 else "yellow")
	if Game.opts.has("hall_palette"):
		palette = String(Game.opts["hall_palette"])
	# The hall's own glow field, in its own (rotated) frame, shared by its nine chunks (S05).
	field = FixtureField.new(Vector2.ZERO, Vector2(76.8, 76.8), 0.6)
	field.wrap = true
	field.to_local = global_transform.affine_inverse()
	pool = FixturePool.new()
	pool.name = "pool"
	pool.light_cap = int(Game.opts.get("hall_lights", "32"))
	pool.hum_cap = 8
	pool.layer_bits = POCKET
	pool.enabled = false
	add_child(pool)
	# The hall's own air: thicker haze than the level's, so its far end is lost and its light hangs
	# in shafts (critique 021: the hall had turned clean and flat, L128, L134). Only cameras that
	# show the hall draw it.
	var fogd := float(Game.opts.get("hall_fog", "0.008"))
	if fogd > 0.0:
		var fv := FogVolume.new()
		fv.name = "hall_air"
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		fv.size = Vector3(SIDE, HALL_H, SIDE)
		fv.position = Vector3(MID, HALL_H * 0.5, MID)
		fv.layers = POCKET
		var fm := FogMaterial.new()
		fm.density = fogd
		# its own air colour: cold tubes through the level's warm haze read green (critique 023)
		var fc: Array = PALETTES.get(palette, {}).get("fog", [0.95, 0.92, 0.84])
		fm.albedo = Color(fc[0], fc[1], fc[2])
		fm.edge_fade = 0.05
		fv.material = fm
		add_child(fv)
	for j in N:
		for i in N:
			var ch := Level0Chunk.new()
			ch.name = "hall_%d_%d" % [i, j]
			ch.pooled = true
			ch.shared_field = field
			ch.own_far_edges = i == N - 1 or j == N - 1
			ch.position = Vector3(i * 24.0, 0.0, j * 24.0)
			add_child(ch)
			chunks.append(ch)
			steps.append(_begin_chunk.bind(ch, i, j, c, salt))
	steps.append(_make_portals)


## Sets one chunk up and puts its build steps at the front of the queue (the set-up itself is a
## few ms, so it gets a frame of its own).
func _begin_chunk(ch: Level0Chunk, i: int, j: int, c: Vector2i, salt: String) -> void:
	var st: Array = ch.begin_build(_layout(i, j, c), "%s%d:%d:" % [salt, i, j], world.mats, world.seed_offset)
	st.append(_finish_chunk.bind(ch))
	steps = st + steps


## One step of the build (Level0World calls this when it has a frame to spare). True when done.
func step() -> bool:
	if steps.is_empty():
		return true
	(steps.pop_front() as Callable).call()
	if steps.is_empty():
		built = true
	return steps.is_empty()


func _finish_chunk(ch: Level0Chunk) -> void:
	for vi in ch.find_children("*", "VisualInstance3D", true, false):
		(vi as VisualInstance3D).layers = POCKET
	for fx in ch.fixtures:
		if fx.mount == Fixture.Mount.CEILING:
			pool.fixtures.append(fx)


func _make_portals() -> void:
	var env: Environment = null
	var we := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we:
		env = we.environment
	var main_cam: Camera3D = world.player_ref.cam if world.player_ref else get_viewport().get_camera_3d()
	var b_in := global_transform.basis               # x: into the hall
	var b_out := Basis(-b_in.x, Vector3.UP, -b_in.z)  # x: out of the storeroom
	var hall_door := global_transform * Vector3(0, 0, MID)
	var far_door := global_transform * Vector3(SIDE, 0, MID)
	var out_frame := Transform3D(b_out, door_world)
	portal_in = _portal("door", Transform3D(b_in, door_world), Transform3D(b_in, hall_door), POCKET, LEVEL, main_cam, env)
	portal_back = _portal("back", Transform3D(b_out, hall_door), out_frame, LEVEL, POCKET, main_cam, env)
	portal_far = _portal("far", Transform3D(b_in, far_door), out_frame, LEVEL, POCKET, main_cam, env)
	# The far door from across the hall (L120: "a flat black rectangle"): beyond 12 m it shows a still
	# of the lit room behind it (taken when you first come in, Level0World._update_rooms), and a lamp
	# in that room throws its light into the dark end of the hall.
	# The still is taken from the hand-over distance and both it and the live view sit under the
	# hall's haze, so the switch between them is invisible.
	portal_far.range_m = float(Game.opts.get("far_range", "7"))
	portal_far.live_fog_from = 2.5
	var spill := SpotLight3D.new()
	spill.name = "far_spill"
	spill.layers = POCKET
	spill.light_color = Color(1.0, 0.86, 0.6)
	spill.light_energy = float(Game.opts.get("spill", "2.4"))
	spill.spot_range = 16.0
	spill.spot_angle = 38.0
	spill.spot_attenuation = 1.2
	spill.spot_angle_attenuation = 1.6
	spill.shadow_enabled = true
	spill.light_volumetric_fog_energy = 1.6
	add_child(spill)
	# just outside the doorway, aiming back into the hall and a little down
	spill.position = Vector3(SIDE + 0.9, 1.9, MID)
	spill.rotation = Vector3(-0.12, PI * 0.5, 0.0)


func _portal(nm: String, frame: Transform3D, target: Transform3D, show: int, hide: int, main_cam: Camera3D, env: Environment) -> Portal:
	var p := Portal.new()
	p.name = nm
	p.top_level = true
	p.opening = OPENING
	p.target = target
	p.show_layers = show
	p.hide_layers = hide
	add_child(p)
	p.global_transform = frame
	p.setup(main_cam, env)
	return p


func portals() -> Array[Portal]:
	var out: Array[Portal] = []
	for p in [portal_in, portal_back, portal_far]:
		if p:
			out.append(p)
	return out


## True if p (world) is inside the hall.
func contains(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	return l.x > -0.5 and l.x < SIDE + 0.5 and l.z > -0.5 and l.z < SIDE + 0.5 and l.y > -2.0 and l.y < HALL_H + 2.0


func hall_local(p: Vector3) -> Vector3:
	return global_transform.affine_inverse() * p


## A walkable point in the hall (pillars and walls kept clear by a margin).
func is_walkable(p: Vector3) -> bool:
	var l := hall_local(p)
	if l.x < 0.5 or l.x > SIDE - 0.5 or l.z < 0.5 or l.z > SIDE - 0.5:
		return false
	for k in range(1, 15):
		var px := 4.8 * k
		if absf(l.x - px) < 0.75:
			var dz := fposmod(l.z - MID + 2.4, 4.8)
			if dz < 0.75 or dz > 4.05:
				return false
	return true


# ------------------------------------------------------------------ layout

func _layout(i: int, j: int, c: Vector2i) -> Dictionary:
	var L := {
		"name": "portal_hall_%d_%d_%d_%d" % [c.x, c.y, i, j],
		"chunk": [10000 + c.x * 7 + i, 10000 + c.y * 7 + j],
		"size": [24.0, 24.0], "ceiling_height": HALL_H, "base_y": floor_y, "space_xform": global_transform, "plenum_height": HALL_H + 0.7, "wall_thickness": 0.2,
		"door_height": 2.1, "tile": 0.6,
		"walls": [], "edge_walls": [], "doors": [], "pillars": [], "fixtures": [], "rooms": [],
		"dark_zones": [], "failing_hint": [], "tint_zones": [], "flood_candidates": [], "splices": [],
		"shear_bands": [], "wall_fixtures": [], "floor_fixtures": [], "stairs": [], "fake_doors": [],
		"exit_signs": [], "props": [], "interest": [], "fidelity": 0.9, "seams": [], "worklights": [],
		"graffiti": [], "pocket_zones": [], "tall_rooms": [], "closets": [],
		"gates": {"W": [], "E": [], "N": [], "S": []},
	}
	var ox := i * 24.0
	var oz := j * 24.0
	var mid_row := j == 1
	# The outer walls; the entrance and the far door in the middle of the west and east walls.
	if i == 0:
		if mid_row:
			L["walls"].append([0.0, 0.0, 0.0, 11.4])
			L["walls"].append([0.0, 12.6, 0.0, 24.0])
			L["doors"].append([0.0, 11.4, 0.0, 12.6])
		else:
			L["walls"].append([0.0, 0.0, 0.0, 24.0])
	if i == N - 1:
		if mid_row:
			L["walls"].append([24.0, 0.0, 24.0, 11.4])
			L["walls"].append([24.0, 12.6, 24.0, 24.0])
			L["doors"].append([24.0, 11.4, 24.0, 12.6])
			L["exit_signs"].append([24.0 - 0.1, 12.0, -1.0, 0.0])
		else:
			L["walls"].append([24.0, 0.0, 24.0, 24.0])
	if j == 0:
		L["walls"].append([0.0, 0.0, 24.0, 0.0])
	if j == N - 1:
		L["walls"].append([0.0, 24.0, 24.0, 24.0])
	# Columns on a 4.8 m grid, leaving a 4.8 m aisle from door to door down the middle.
	for kx in range(1, 15):
		var x := 4.8 * kx
		for side in [-1.0, 1.0]:
			for kz in 7:
				var z: float = MID + side * (2.4 + 4.8 * kz)
				if z < 1.5 or z > SIDE - 1.5:
					continue
				var lx := x - ox
				var lz := z - oz
				if lx >= 0.0 and lx < 24.0 and lz >= 0.0 and lz < 24.0:
					L["pillars"].append([lx, lz, 0.6, "square"])
	# Panels between the columns (lens along z), on whole ceiling tiles.
	for kx in 15:
		var px := 2.7 + 4.8 * kx
		for kz in range(-7, 8):
			var pz := MID + 4.8 * kz
			var lx2 := px - ox
			var lz2 := pz - oz
			if lx2 > 0.7 and lx2 < 23.3 and lz2 > 0.9 and lz2 < 23.1:
				L["fixtures"].append([lx2, lz2, 0])
	L["rooms"].append([0.0, 0.0, 24.0, 24.0, "hall"])
	var pal: Dictionary = PALETTES.get(palette, {})
	L["palette"] = pal
	if pal.has("tube"):
		var tb: Array = pal["tube"]
		L["tint_zones"].append([0.0, 0.0, 24.0, 24.0, tb[0], tb[1], tb[2]])
	# The long side walls are not blank (L120): doors set into them at a steady rhythm, every one
	# without a handle (remembered wrong: the word "door" without the part you open it with).
	for side_j in [0, N - 1]:
		if j != side_j:
			continue
		var wz := 0.1 if j == 0 else 24.0 - 0.1
		var nz := 1.0 if j == 0 else -1.0
		for k in 3:
			var fx := 4.8 + 7.2 * k + (2.4 if (i + j) % 2 == 1 else 0.0)
			if fx > 1.5 and fx < 22.5:
				L["fake_doors"].append([fx, wz, 0.0, nz, 0.0, "nohandle"])
	# The far third is dark; the exit sign is the only light at the end of the hall.
	# Fewer, stronger panels on a sparse grid (every other one each way), so each column has one
	# light that dominates it and throws a shadow you can read, with pools of dark between them
	# (critiques 020 to 022: "the pillars cast zero shadows", L134; with every panel lit, four
	# overlapping lights filled each other's shadows). The lights thin out toward the far end
	# instead of stopping at a line (L127).
	var lr := Game.rng("halllights:%s:%d:%d" % [key, i, j])
	L["light_gain"] = float(Game.opts.get("hall_gain", "1.8"))
	L["quiet_dead"] = true
	for f in L["fixtures"]:
		var gx: float = f[0] + ox
		var kx := int(round((gx - 2.7) / 4.8))
		var kz := int(round((f[1] + oz - MID) / 4.8))
		var lit := (kx % 2 == 0 and kz % 2 == 0) or lr.randf() < 0.06
		# (the far end keeps a few panels: QA S05 found it nearly black past the lamp's reach)
		if gx > 44.0 and lr.randf() < (0.35 if gx < 60.0 else 0.62):
			lit = false
		f.append("on" if lit else "dead")
	if i == N - 1:
		L["dark_zones"].append([18.0, 0.0, 24.0, 24.0])
	if i == 0 and mid_row:
		L["lit_zones"] = [[0.0, 5.0, 8.0, 19.0]]
		# The survey crew got in before you: their camera on its tripod, filming the way back out.
		L["props"].append(["prop_tripod_camcorder", 6.6, 15.0, -114.0])
		L.get_or_add("rec_lights", []).append([6.6, 15.0, -90.0])
		L["props"].append(["prop_tape_crate", 7.6, 16.4, 30.0])
		L["graffiti"].append(["hd_survey", 0.1, 8.2, 1.0, 0.0, 1.25])
	if i == 1 and mid_row:
		L["props"].append(["prop_folding_chair_sf", 7.0, 13.0, 180.0])
	_variety(L, i, j, ox, oz)
	L["interest"].append({"name": "hall_%d_%d" % [i, j], "p": [12.0, 12.0]})
	return L


## Each hall its own (critique 025: "the pillar hall repeats itself, the same fog, pillars and glow
## frame after frame"; L168). Off the central aisle, seeded per storeroom: a stretch where columns are
## missing and one hangs short of the floor; a free-standing wall with a doorway in it; a patch of
## tubes of another colour; and one thing to walk toward: an office chair facing an old monitor left
## on the carpet, its screen still glowing.
func _variety(L: Dictionary, i: int, j: int, _ox: float, _oz: float) -> void:
	var vr := Game.rng("hallvariety:%s" % key)
	var pick_i := vr.randi_range(0, N - 1)
	var pick_j := 0 if vr.randf() < 0.5 else N - 1
	var wall_i := (pick_i + 1 + vr.randi() % (N - 1)) % N
	var wall_j := N - 1 - pick_j
	var tint_i := vr.randi_range(0, N - 1)
	var beacon_i := (pick_i + 1) % N
	var beacon_j := pick_j
	var kinds := ["warm", "cold", "green"]
	var tint_kind: String = kinds[vr.randi() % kinds.size()]
	if Game.opts.has("log-hall") and i == 0 and j == 0:
		print("[hall] %s collapse chunk %d,%d  wall chunk %d,%d  tint chunk %d (%s)  monitor chunk %d,%d" % [key, pick_i, pick_j, wall_i, wall_j, tint_i, tint_kind, beacon_i, beacon_j])
	# 1. The collapse: a 2 x 2 patch of columns gone, one beside it hanging short of the floor.
	if i == pick_i and j == pick_j:
		var cx := 12.0 + vr.randf_range(-4.8, 4.8)
		var cz := 12.0 + vr.randf_range(-3.0, 3.0)
		var kept := []
		var hung := false
		for pl in L["pillars"]:
			var d := Vector2(pl[0] - cx, pl[1] - cz)
			if absf(d.x) < 4.9 and absf(d.y) < 4.9:
				continue
			if not hung and d.length() < 8.0:
				pl.append("hang")
				hung = true
			kept.append(pl)
		L["pillars"] = kept
		L["dark_zones"].append([cx - 3.0, cz - 3.0, cx + 3.0, cz + 3.0])
	# 2. A free-standing wall across the side aisle, a doorway in it.
	if i == wall_i and j == wall_j:
		var wx := 9.6 + 2.4 * float(vr.randi() % 3)
		var za := 0.0 if j == 0 else 15.0
		var zb := 9.0 if j == 0 else 24.0
		var dz := (za + zb) * 0.5
		L["walls"].append([wx, za, wx, dz - 0.55])
		L["walls"].append([wx, dz + 0.55, wx, zb])
		L["doors"].append([wx, dz - 0.55, wx, dz + 0.55])
		L["pillars"] = L["pillars"].filter(func(pl): return absf(pl[0] - wx) > 0.8 or pl[1] < minf(za, zb) - 0.5 or pl[1] > maxf(za, zb) + 0.5)
	# 3. A patch of tubes that are not the hall's.
	if i == tint_i and j != 1:
		var tcs := {"warm": [1.0, 0.82, 0.62], "cold": [0.7, 0.86, 1.0], "green": [0.82, 1.0, 0.78]}
		var tc: Array = tcs[tint_kind]
		L["tint_zones"].append([4.0, 2.0, 20.0, 22.0, tc[0], tc[1], tc[2]])
	# 4. Something to walk toward.
	if i == beacon_i and j == beacon_j:
		var bx := 12.0 + vr.randf_range(-3.0, 3.0)
		var bz := 9.0 if j == 0 else 15.0
		L["props"].append(["prop_crt_monitor", bx, bz, 90.0 if j == 0 else -90.0])
		L["props"].append(["prop_office_chair", bx, bz + (1.3 if j == 0 else -1.3), 0.0 if j == 0 else 180.0])
		L.get_or_add("screen_glows", []).append([bx, 0.35, bz])
