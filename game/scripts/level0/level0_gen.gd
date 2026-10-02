class_name Level0Gen
extends RefCounted
## Infinite Level 0 layout generator (M2). Pure data: given the world seed and a chunk
## coordinate it returns a layout dictionary in the same schema as data/level0_hero.json, in
## chunk-local meters (0..CHUNK), which Level0Chunk builds. Deterministic, no nodes.
##
## How a chunk is made:
##   1. Boundary edges. Every chunk edge is shared by two chunks; its walls and gaps come from
##      a hash of the edge alone, so both neighbors agree. Each chunk builds its west and north
##      edges and treats the east and south ones as solid for navigation. Every edge has at
##      least one gap, so the infinite maze is always connected.
##   2. Interior. A BSP split on a 1.2 m module grid. Every split wall gets at least one door
##      or opening, so every room in the chunk is reachable. Some splits become corridors, some
##      walls are left out (open plan) or are only stubs, big leaves become pillar halls.
##   3. Ceiling grid per room: troffers centered in each room on the 0.6 m tile grid, lined up
##      along corridors, kept clear of walls (D013).
##   4. Generation loss (VISION, D009): splice errors whose odds scale with (1 - fidelity):
##      chairs pushed into walls, looped chairs, a flipped chair on the ceiling, a troffer
##      fitted to a wall or set into the floor, stairs into the ceiling, sheared wallpaper,
##      doorways copied slightly too small, doors that open onto nothing.

const CHUNK := 24.0
const MOD := 1.2              # module: walls sit on multiples of this
const NMOD := 20              # modules per chunk side
const TILE := 0.6
const T := 0.2
const H := 2.6
const DOOR_W := 1.0

var world_seed := 0
var fidelity := 0.9


func _init(p_seed: int, p_fidelity: float = 0.9) -> void:
	world_seed = p_seed
	fidelity = p_fidelity


func _rng(salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%s" % [world_seed, salt])
	return r


# ------------------------------------------------------------------ edges

## Highways (art direction, docs/reference/art_direction_s02.md): some chunk rows carry an
## east-west corridor two modules wide that runs straight through every chunk of the row, and
## some columns a north-south one. Its lights sit on one global 3 m rhythm, so a highway is the
## long vanishing-point hallway where distance cannot be judged. Returns the first module of the
## strip, or -1. Row 0 always has one: the run starts looking down a long hall.
func hwy_row(cz: int) -> int:
	if cz == 0:
		return 8
	var r := _rng("hwy:row:%d" % cz)
	return r.randi_range(5, 13) if r.randf() < 0.3 else -1


func hwy_col(cx: int) -> int:
	var r := _rng("hwy:col:%d" % cx)
	return r.randi_range(5, 13) if r.randf() < 0.22 else -1


## Loops (VISION non-euclidean toolkit: "the corridor that repeats until you turn around").
## On some highway rows a run of LOOP_LEN chunks is built from one identical template: the hall
## with no side doors, the same lights, stains and the same lone chair. Level0World quietly moves
## the player back one copy while they keep walking, until they turn around (DECISIONS D017).
const LOOP_LEN := 4


## Index of chunk (cx, cz) inside a loop run (0 .. LOOP_LEN - 1), or -1.
func loop_index(cx: int, cz: int) -> int:
	var start := loop_start(cx, cz)
	return cx - start if start != 1 << 20 else -1


## First chunk column of the loop run containing (cx, cz), or 1 << 20 if none.
func loop_start(cx: int, cz: int) -> int:
	if hwy_row(cz) < 0:
		return 1 << 20
	var block := floori(cx / 12.0)
	var r := _rng("loop:%d:%d" % [cz, block])
	var has := r.randf() < 0.55
	var lx0 := block * 12 + r.randi_range(3, 7)
	if cz == 0:
		# The spawn row always has one, starting two chunks east of the start (48 m).
		has = block == 0
		lx0 = 2
	if has and cx >= lx0 and cx < lx0 + LOOP_LEN:
		return lx0
	return 1 << 20


## Gaps (open intervals in meters along the edge, 0..CHUNK) of a shared chunk edge.
## axis "V": the vertical line x = ex * CHUNK spanning chunk row ez.
## axis "H": the horizontal line z = ez * CHUNK spanning chunk column ex.
func edge_gaps(axis: String, ex: int, ez: int) -> Array:
	var r := _rng("edge:%s:%d:%d" % [axis, ex, ez])
	# A highway crossing this edge: the boundary is walled except for the corridor (and maybe one
	# far door), so the hall reads as one continuous corridor.
	# Edges around a loop run are closed (the copies must be identical and sealed), and the
	# edges between copies only pass the hall.
	if axis == "H" and (loop_index(ex, ez) >= 0 or loop_index(ex, ez - 1) >= 0):
		return []
	if axis == "V" and (loop_index(ex, ez) >= 0 or loop_index(ex - 1, ez) >= 0):
		var hl := hwy_row(ez)
		return [[hl * MOD, (hl + 2) * MOD, "open"]]
	var hw := hwy_row(ez) if axis == "V" else hwy_col(ex)
	if hw >= 0:
		var hg := [[hw * MOD, (hw + 2) * MOD, "open"]]
		if r.randf() < 0.5:
			for attempt in 8:
				var k := r.randi_range(2, NMOD - 3)
				if k < hw - 3 or k > hw + 4:
					hg.append([(k + 0.5) * MOD - DOOR_W * 0.5, (k + 0.5) * MOD + DOOR_W * 0.5, "door"])
					break
		hg.sort_custom(func(a, b): return a[0] < b[0])
		return hg
	if r.randf() < 0.32:
		return [[0.0, CHUNK]]
	var gaps := []
	var n := r.randi_range(1, 3)
	var used := []
	for k in n:
		for attempt in 12:
			var m := r.randi_range(2, NMOD - 3)          # module index of the gap's left edge
			var kind := r.randf()
			var w_mod := 1 if kind < 0.6 else (2 if kind < 0.85 else 3)
			var ok := true
			for u in used:
				if m < u[1] + 2 and m + w_mod > u[0] - 2:
					ok = false
			if not ok or m + w_mod > NMOD - 2:
				continue
			used.append([m, m + w_mod])
			if w_mod == 1:
				var c := (m + 0.5) * MOD
				gaps.append([c - DOOR_W * 0.5, c + DOOR_W * 0.5, "door"])
			else:
				gaps.append([m * MOD, (m + w_mod) * MOD, "open"])
			break
	if gaps.is_empty():
		gaps.append([9.5 * MOD - DOOR_W * 0.5, 9.5 * MOD + DOOR_W * 0.5, "door"])
	gaps.sort_custom(func(a, b): return a[0] < b[0])
	return gaps


## Wall pieces between the gaps of an edge, as [a, b] intervals along it.
static func _solid_runs(gaps: Array, length: float) -> Array:
	var runs := []
	var t := 0.0
	for g in gaps:
		if g[0] > t + 0.01:
			runs.append([t, g[0]])
		t = maxf(t, g[1])
	if t < length - 0.01:
		runs.append([t, length])
	return runs


# ------------------------------------------------------------------ chunk

func generate(cx: int, cz: int) -> Dictionary:
	if loop_index(cx, cz) >= 0:
		return _loop_layout(cx, cz)
	var r := _rng("chunk:%d:%d" % [cx, cz])
	var L := {
		"name": "level0_chunk_%d_%d" % [cx, cz],
		"chunk": [cx, cz],
		"size": [CHUNK, CHUNK],
		"ceiling_height": H,
		"plenum_height": 3.3,
		"wall_thickness": T,
		"door_height": 2.1,
		"tile": TILE,
		"walls": [],
		"edge_walls": [],
		"doors": [],
		"pillars": [],
		"fixtures": [],
		"rooms": [],
		"dark_zones": [],
		"failing_hint": [],
		"tint_zones": [],
		"flood_candidates": [],
		"splices": [],
		"shear_bands": [],
		"wall_fixtures": [],
		"floor_fixtures": [],
		"stairs": [],
		"fake_doors": [],
		"exit_signs": [],
		"props": [],
		"interest": [],
		"gates": {},
		"fidelity": fidelity,
		"seams": [],
		"worklights": [],
		"graffiti": [],
		"pocket_zones": [],
		"tall_rooms": [],
	}
	var spawn_chunk := cx == 0 and cz == 0
	# --- boundary: build west and north, know east and south
	var gW := edge_gaps("V", cx, cz)
	var gE := edge_gaps("V", cx + 1, cz)
	var gN := edge_gaps("H", cx, cz)
	var gS := edge_gaps("H", cx, cz + 1)
	L["gates"] = {"W": gW, "E": gE, "N": gN, "S": gS}
	for run in _solid_runs(gW, CHUNK):
		L["walls"].append([0.0, run[0], 0.0, run[1]])
	for run in _solid_runs(gN, CHUNK):
		L["walls"].append([run[0], 0.0, run[1], 0.0])
	for run in _solid_runs(gE, CHUNK):
		L["edge_walls"].append([CHUNK, run[0], CHUNK, run[1]])
	for run in _solid_runs(gS, CHUNK):
		L["edge_walls"].append([run[0], CHUNK, run[1], CHUNK])
	for g in gW:
		if g.size() > 2 and g[2] == "door":
			L["doors"].append([0.0, g[0], 0.0, g[1]])
	for g in gN:
		if g.size() > 2 and g[2] == "door":
			L["doors"].append([g[0], 0.0, g[1], 0.0])
	# Gaps on each side of the root rect, in module units, so interior walls never end in a gate.
	var root_gaps := {
		"W": gW.map(func(g): return [g[0] / MOD, g[1] / MOD]),
		"E": gE.map(func(g): return [g[0] / MOD, g[1] / MOD]),
		"N": gN.map(func(g): return [g[0] / MOD, g[1] / MOD]),
		"S": gS.map(func(g): return [g[0] / MOD, g[1] / MOD]),
	}
	# --- interior BSP (module units)
	var leaves := []
	var style := r.randf()
	var max_depth := 5 if style < 0.55 else (4 if style < 0.85 else 3)   # maze, mixed, halls
	if spawn_chunk:
		max_depth = 4
	for part in _highways(r, L, cx, cz, root_gaps, leaves):
		_split(r, L, part[0], part[1], 0, max_depth, leaves)
	# --- a seam (tape-only exit) into a sealed pocket, in about a third of the chunks
	_pick_pocket_room(cx, cz, leaves, spawn_chunk)
	_pick_tall_room(cx, cz, leaves, spawn_chunk)
	# --- rooms, fixtures, pillars
	for lf in leaves:
		_furnish_room(r, L, lf, spawn_chunk)
	# --- darkness: a few whole rooms dead, a cluster or two of dead panels
	var dark_rooms := 0
	for lf in leaves:
		var rr: Rect2 = lf["rect"]
		if spawn_chunk and rr.has_point(Vector2(12, 12)):
			continue
		if r.randf() < 0.22 and dark_rooms < 3 and not lf.get("pocket", false):
			L["dark_zones"].append([rr.position.x, rr.position.y, rr.end.x, rr.end.y])
			dark_rooms += 1
	# --- landmarks and splice errors
	_landmarks(r, L, leaves, spawn_chunk)
	# Graffiti from earlier people (pipeline/manifests/graffiti_level0.json). Fair hints first:
	# "TURN AROUND" just before a loop run, "LOOK THROUGH IT" near the start of the run.
	var hr0 := hwy_row(cz)
	var fixed := []
	if hr0 >= 0 and loop_index(cx + 1, cz) == 0:
		fixed.append(["turn_around", 19.0, hr0 + 2, -1.0, 1.45, 1.1])
	if hr0 >= 0 and loop_index(cx - 1, cz) == LOOP_LEN - 1:
		fixed.append(["turn_around", 5.0, hr0, 1.0, 1.45, 1.1])
	if spawn_chunk and hr0 >= 0:
		fixed.append(["look_through", 8.5, hr0, 1.0, 1.5, 1.0])
	# The line: on some stretches of a highway someone dragged a crayon along the wall as they
	# walked, chunk after chunk (wall details, Level0Chunk._build_wall_details).
	if hr0 >= 0 and _rng("trail:%d:%d" % [cz, floori(cx / 5.0)]).randf() < 0.35:
		L["trails"] = [[hr0 * MOD, 1.0]]
	for fg in fixed:
		var x := _wall_run_x(L, fg[1], int(fg[2]) * MOD, fg[5])
		if x > -50.0:
			L["graffiti"].append([fg[0], x, int(fg[2]) * MOD + T * 0.5 * fg[3], 0.0, fg[3], fg[4]])
	if spawn_chunk:
		L["spawn"] = _spawn_point(L, leaves)
		# The opening stretch of the spawn hall is lit: the first image is the long bright hall.
		for lf in leaves:
			if lf.get("highway", false):
				var hr2: Rect2 = lf["rect"]
				L["lit_zones"] = [[0.0, hr2.position.y, 16.0, hr2.end.y]]
	return L


## One copy of a loop run: the highway hall only, sealed, identical in every copy (the template
## depends on the row, never on cx). The space beside the hall is left empty and dark.
func _loop_layout(cx: int, cz: int) -> Dictionary:
	var r := _rng("looptemplate:%d" % cz)
	var hr := hwy_row(cz)
	var lx0 := loop_start(cx, cz)
	var L := {
		"name": "level0_loop_%d_%d" % [cx, cz],
		"chunk": [cx, cz],
		"size": [CHUNK, CHUNK], "ceiling_height": H, "plenum_height": 3.3, "wall_thickness": T,
		"door_height": 2.1, "tile": TILE,
		"walls": [], "edge_walls": [], "doors": [], "pillars": [], "fixtures": [], "rooms": [],
		"dark_zones": [], "failing_hint": [], "tint_zones": [], "flood_candidates": [], "splices": [],
		"shear_bands": [], "wall_fixtures": [], "floor_fixtures": [], "stairs": [], "fake_doors": [],
		"exit_signs": [], "props": [], "interest": [], "fidelity": fidelity,
		"loop": {"index": cx - lx0, "start": lx0, "row": cz, "len": LOOP_LEN},
		"steady_lights": true,
	}
	var hg := [[hr * MOD, (hr + 2) * MOD, "open"]]
	L["gates"] = {"W": hg, "E": hg, "N": [], "S": []}
	# West edge (built here): only the hall passes. North edge: closed. East/south: neighbors.
	for run in _solid_runs(hg, CHUNK):
		L["walls"].append([0.0, run[0], 0.0, run[1]])
		L["edge_walls"].append([CHUNK, run[0], CHUNK, run[1]])
	L["walls"].append([0.0, 0.0, CHUNK, 0.0])
	L["edge_walls"].append([0.0, CHUNK, CHUNK, CHUNK])
	for line in [hr, hr + 2]:
		L["walls"].append([0.0, line * MOD, CHUNK, line * MOD])
	var strip := Rect2i(0, hr, NMOD, 2)
	var lf := {"m": strip, "rect": Rect2(Vector2(strip.position) * MOD, Vector2(strip.size) * MOD), "depth": 0, "corridor": true, "highway": true}
	_furnish_room(r, L, lf, false)
	# The lone chair that keeps coming back: the tell that you are walking the same hall again.
	var zc := (hr + 2) * MOD - T * 0.5 - 0.42
	L["props"].append(["prop_folding_chair_sf", r.randf_range(8.0, 16.0), zc, 0.0])
	# Marks left by someone who walked this hall before you, the same in every copy.
	L["graffiti"] = [["tally_copy", 5.5, hr * MOD + T * 0.5, 0.0, 1.0, 1.35], ["same", 18.5, (hr + 2) * MOD - T * 0.5, 0.0, -1.0, 1.5]]
	# A dead panel or two, the same in every copy.
	if L["fixtures"].size() > 3:
		var k := r.randi_range(1, L["fixtures"].size() - 2)
		var f: Array = L["fixtures"][k]
		L["dark_zones"].append([f[0] - 0.8, f[1] - 0.8, f[0] + 0.8, f[1] + 0.8])
	return L


## Cuts the highway strips out of the chunk (walls with a few doors into the rest) and returns
## the remaining rectangles with their side gaps, ready for the BSP. Without highways it returns
## the whole chunk.
func _highways(r: RandomNumberGenerator, L: Dictionary, cx: int, cz: int, root_gaps: Dictionary, leaves: Array) -> Array:
	var hr := hwy_row(cz)
	var hc := hwy_col(cx)
	if hr < 0 and hc < 0:
		return [[Rect2i(0, 0, NMOD, NMOD), root_gaps]]
	var row_walls := {}
	var col_walls := {}
	if hr >= 0:
		for line in [hr, hr + 2]:
			var gaps := _corridor_doors(r, hc)
			_emit_wall(r, L, false, line, 0, NMOD, gaps)
			row_walls[line] = gaps
		var strip := Rect2i(0, hr, NMOD, 2)
		leaves.append({"m": strip, "rect": Rect2(Vector2(strip.position) * MOD, Vector2(strip.size) * MOD), "depth": 0, "corridor": true, "highway": true})
	if hc >= 0:
		for line in [hc, hc + 2]:
			var gaps := _corridor_doors(r, hr)
			_emit_wall(r, L, true, line, 0, NMOD, gaps)
			col_walls[line] = gaps
		# The column strip, minus the crossing square that belongs to the row strip.
		var spans := [[0, NMOD]] if hr < 0 else [[0, hr], [hr + 2, NMOD]]
		for sp in spans:
			if sp[1] - sp[0] < 1:
				continue
			var strip := Rect2i(hc, sp[0], 2, sp[1] - sp[0])
			leaves.append({"m": strip, "rect": Rect2(Vector2(strip.position) * MOD, Vector2(strip.size) * MOD), "depth": 0, "corridor": true, "highway": true})
	# The remaining rectangles.
	var xs := [[0, NMOD]] if hc < 0 else [[0, hc], [hc + 2, NMOD]]
	var zs := [[0, NMOD]] if hr < 0 else [[0, hr], [hr + 2, NMOD]]
	var out := []
	for xr in xs:
		for zr in zs:
			if xr[1] - xr[0] < 1 or zr[1] - zr[0] < 1:
				continue
			var rect := Rect2i(xr[0], zr[0], xr[1] - xr[0], zr[1] - zr[0])
			var g := {
				"W": root_gaps["W"] if xr[0] == 0 else col_walls[hc + 2],
				"E": root_gaps["E"] if xr[1] == NMOD else col_walls[hc],
				"N": root_gaps["N"] if zr[0] == 0 else row_walls[hr + 2],
				"S": root_gaps["S"] if zr[1] == NMOD else row_walls[hr],
			}
			out.append([rect, g])
	return out


## Door gaps (modules) along a highway wall: one or two doors, plus the crossing with the other
## highway if there is one. Mostly unbroken, so the hall stays long and blank.
func _corridor_doors(r: RandomNumberGenerator, cross: int) -> Array:
	var gaps := []
	if cross >= 0:
		gaps.append([float(cross), float(cross + 2), "open"])
	var n := 1 if r.randf() < 0.7 else 2
	var tries := 0
	while gaps.size() < n + (1 if cross >= 0 else 0) and tries < 20:
		tries += 1
		var m := r.randi_range(2, NMOD - 3)
		var clash := false
		for g in gaps:
			if m < g[1] + 2 and m + 1 > g[0] - 2:
				clash = true
		if not clash:
			gaps.append([m + 0.5 - DOOR_W * 0.5 / MOD, m + 0.5 + DOOR_W * 0.5 / MOD, "door"])
	gaps.sort_custom(func(a, b): return a[0] < b[0])
	return gaps


## Emits a wall along module line `line` from a0 to a1 (modules) broken by `gaps` (modules),
## with door casings in the door-sized gaps.
func _emit_wall(r: RandomNumberGenerator, L: Dictionary, vertical: bool, line: int, a0: int, a1: int, gaps: Array) -> void:
	var lm := line * MOD
	var t := float(a0)
	var runs := []
	for g in gaps:
		if g[0] > t + 0.01:
			runs.append([t, g[0]])
		t = maxf(t, g[1])
	if t < a1 - 0.01:
		runs.append([t, float(a1)])
	for run in runs:
		if vertical:
			L["walls"].append([lm, run[0] * MOD, lm, run[1] * MOD])
		else:
			L["walls"].append([run[0] * MOD, lm, run[1] * MOD, lm])
	for g in gaps:
		if g.size() > 2 and g[2] == "door":
			var d := [lm, g[0] * MOD, lm, g[1] * MOD] if vertical else [g[0] * MOD, lm, g[1] * MOD, lm]
			if r.randf() < (1.0 - fidelity) * 0.6:
				d.append(r.randf_range(1.84, 1.92))
			L["doors"].append(d)


## Recursive split. `gaps` holds, per side of rect (W/E/N/S), the open intervals in modules
## along that side that a child wall must not end inside.
func _split(r: RandomNumberGenerator, L: Dictionary, rect: Rect2i, gaps: Dictionary, depth: int, max_depth: int, leaves: Array) -> void:
	var w := rect.size.x
	var h := rect.size.y
	var stop := depth >= max_depth or (w <= 4 and h <= 4) or w * h <= 12
	if not stop and depth >= 2 and w * h >= 36 and r.randf() < 0.16:
		stop = true   # a big hall
	if stop:
		leaves.append({"m": rect, "rect": Rect2(Vector2(rect.position) * MOD, Vector2(rect.size) * MOD), "depth": depth})
		return
	var vertical := w > h   # vertical wall (constant x) splits the width
	if w == h or (float(maxi(w, h)) / float(mini(w, h)) < 1.35):
		vertical = r.randf() < 0.5
	var span := w if vertical else h
	if span < 5:
		vertical = not vertical
		span = w if vertical else h
		if span < 5:
			leaves.append({"m": rect, "rect": Rect2(Vector2(rect.position) * MOD, Vector2(rect.size) * MOD), "depth": depth})
			return
	# Candidate split lines: not ending inside a gap on either perpendicular side.
	var side_a := "N" if vertical else "W"
	var side_b := "S" if vertical else "E"
	var cands := []
	for s in range(2, span - 1):
		var line := s + (rect.position.x if vertical else rect.position.y)
		if _in_gap(gaps[side_a], line) or _in_gap(gaps[side_b], line):
			continue
		cands.append(s)
	if cands.is_empty():
		leaves.append({"m": rect, "rect": Rect2(Vector2(rect.position) * MOD, Vector2(rect.size) * MOD), "depth": depth})
		return
	var s: int = cands[r.randi() % cands.size()]
	# A corridor: two parallel walls two modules apart.
	var corridor := span >= 9 and r.randf() < 0.3
	var s2 := s + 2
	if corridor:
		var ok := false
		for k in cands.size():
			var c: int = cands[(r.randi() + k) % cands.size()]
			if cands.has(c + 2) and c + 2 <= span - 2:
				s = c
				s2 = c + 2
				ok = true
				break
		corridor = ok
	var lines := [s, s2] if corridor else [s]
	var wall_gaps := []
	for li in lines.size():
		var line_v: int = lines[li] + (rect.position.x if vertical else rect.position.y)
		wall_gaps.append(_wall_with_gaps(r, L, rect, vertical, line_v, corridor))
	# Children with their side gaps.
	var pieces := []
	var bounds := [0] + lines + [span]
	for k in bounds.size() - 1:
		var a: int = bounds[k]
		var b: int = bounds[k + 1]
		var child: Rect2i
		if vertical:
			child = Rect2i(rect.position.x + a, rect.position.y, b - a, h)
		else:
			child = Rect2i(rect.position.x, rect.position.y + a, w, b - a)
		var cg := {}
		if vertical:
			cg["N"] = gaps["N"]
			cg["S"] = gaps["S"]
			cg["W"] = gaps["W"] if k == 0 else _offset_gaps(wall_gaps[k - 1], 0)
			cg["E"] = gaps["E"] if k == bounds.size() - 2 else _offset_gaps(wall_gaps[k], 0)
		else:
			cg["W"] = gaps["W"]
			cg["E"] = gaps["E"]
			cg["N"] = gaps["N"] if k == 0 else _offset_gaps(wall_gaps[k - 1], 0)
			cg["S"] = gaps["S"] if k == bounds.size() - 2 else _offset_gaps(wall_gaps[k], 0)
		pieces.append([child, cg, corridor and k == 1])
	for p in pieces:
		if p[2]:
			var cr: Rect2i = p[0]
			leaves.append({"m": cr, "rect": Rect2(Vector2(cr.position) * MOD, Vector2(cr.size) * MOD), "depth": depth + 1, "corridor": true})
		else:
			_split(r, L, p[0], p[1], depth + 1, max_depth, leaves)


static func _offset_gaps(g: Array, _o: int) -> Array:
	return g


static func _in_gap(gaps: Array, line: float) -> bool:
	for g in gaps:
		if line > g[0] - 0.55 and line < g[1] + 0.55:
			return true
	return false


## Builds one split wall across `rect` at module line `line` and returns its gaps (modules,
## absolute along the wall's own axis).
func _wall_with_gaps(r: RandomNumberGenerator, L: Dictionary, rect: Rect2i, vertical: bool, line: int, corridor: bool) -> Array:
	var a0 := rect.position.y if vertical else rect.position.x
	var a1 := rect.end.y if vertical else rect.end.x
	var length := a1 - a0
	var gaps := []
	var roll := r.randf()
	if not corridor and roll < 0.1 and length >= 4:
		# Open plan: no wall at all (one big gap).
		return [[float(a0), float(a1)]]
	var stub := not corridor and roll < 0.24 and length >= 6
	if stub:
		# Only a stub of wall from one or both ends, the rest open.
		var k := r.randi_range(2, length - 3)
		if r.randf() < 0.5:
			gaps.append([float(a0 + k), float(a1)])
		else:
			gaps.append([float(a0), float(a1 - k)])
	else:
		var n := 1 if length < 7 or r.randf() < 0.55 else 2
		var tries := 0
		while gaps.size() < n and tries < 20:
			tries += 1
			var m := r.randi_range(a0 + 1, a1 - 2)
			var clash := false
			for g in gaps:
				if m < g[1] + 1.5 and m + 1 > g[0] - 1.5:
					clash = true
			if clash:
				continue
			if r.randf() < 0.68:
				var c := m + 0.5
				gaps.append([c - DOOR_W * 0.5 / MOD, c + DOOR_W * 0.5 / MOD, "door"])
			else:
				var wm := 2 if m + 2 <= a1 - 1 else 1
				gaps.append([float(m), float(m + wm), "open"])
		if gaps.is_empty():
			var c2 := a0 + length * 0.5
			gaps.append([c2 - DOOR_W * 0.5 / MOD, c2 + DOOR_W * 0.5 / MOD, "door"])
	gaps.sort_custom(func(x, y): return x[0] < y[0])
	# Emit wall runs and door casings in meters.
	var t := float(a0)
	var lm := line * MOD
	var runs := []
	for g in gaps:
		if g[0] > t + 0.01:
			runs.append([t, g[0]])
		t = maxf(t, g[1])
	if t < a1 - 0.01:
		runs.append([t, float(a1)])
	for run in runs:
		if vertical:
			L["walls"].append([lm, run[0] * MOD, lm, run[1] * MOD])
		else:
			L["walls"].append([run[0] * MOD, lm, run[1] * MOD, lm])
	for g in gaps:
		if g.size() > 2 and g[2] == "door":
			var small := r.randf() < (1.0 - fidelity) * 0.6   # copied slightly too small
			var d := [lm, g[0] * MOD, lm, g[1] * MOD] if vertical else [g[0] * MOD, lm, g[1] * MOD, lm]
			if small:
				d.append(r.randf_range(1.84, 1.92))
			L["doors"].append(d)
	return gaps


# ------------------------------------------------------------------ rooms

func _furnish_room(r: RandomNumberGenerator, L: Dictionary, lf: Dictionary, spawn_chunk: bool) -> void:
	var rr: Rect2 = lf["rect"]
	var inner := rr.grow(-T * 0.5)
	var corridor := bool(lf.get("corridor", false)) or minf(rr.size.x, rr.size.y) <= 2.4 + 0.01
	var kind := "corridor" if corridor else "room"
	# Pillar hall: a big room gets a grid of square columns instead of more walls.
	if not corridor and rr.size.x >= 7.0 and rr.size.y >= 7.0 and r.randf() < 0.55:
		kind = "hall"
		var step := 3.6 if r.randf() < 0.5 else 4.8
		# Some halls have cross-shaped columns (layout language, D016).
		var shape := "plus" if r.randf() < 0.4 else "square"
		var size := 0.9 if shape == "plus" else 0.6
		var x := rr.position.x + step
		var first_pillar: int = L["pillars"].size()
		while x < rr.end.x - 1.6:
			var z := rr.position.y + step
			while z < rr.end.y - 1.6:
				L["pillars"].append([snappedf(x, MOD), snappedf(z, MOD), size, shape])
				z += step
			x += step
		var wr := _rng("wrongpillar:%d:%d:%d:%d" % [L["chunk"][0], L["chunk"][1], int(rr.position.x * 10), int(rr.position.y * 10)])
		var n_p: int = L["pillars"].size() - first_pillar
		if n_p >= 4 and wr.randf() < 0.45:
			var pk: Array = L["pillars"][first_pillar + wr.randi() % n_p]
			if pk[3] == "square":
				pk.append("hang" if wr.randf() < 0.5 else "short")
	var focus := rr.get_center()
	if lf.get("tall", false) and kind == "hall":
		kind = "room"
		while L["pillars"].size() > 0 and rr.has_point(Vector2(L["pillars"][-1][0], L["pillars"][-1][1])):
			L["pillars"].pop_back()
	if lf.get("tall", false):
		L["tall_rooms"].append([rr.position.x, rr.position.y, rr.end.x, rr.end.y, H * 3.0])
		kind = "tall"
	if lf.get("pocket", false):
		# The random draws above still happen so the rest of the chunk keeps its sequence.
		if kind == "hall":
			kind = "room"
			while L["pillars"].size() > 0 and rr.has_point(Vector2(L["pillars"][-1][0], L["pillars"][-1][1])):
				L["pillars"].pop_back()
		focus = _pocket(L, rr, spawn_chunk)
	elif kind == "room":
		_partitions(r, L, rr)
	L["rooms"].append([rr.position.x, rr.position.y, rr.end.x, rr.end.y, kind])
	L["interest"].append({"name": "%s_%d_%d" % [kind, int(rr.position.x * 10), int(rr.position.y * 10)], "p": [focus.x, focus.y]})
	if lf.get("highway", false):
		# Long halls pull people along them: points every 6 m down the hall.
		var long_x := rr.size.x > rr.size.y
		var t := 3.0
		while t < (rr.size.x if long_x else rr.size.y) - 1.0:
			var q := Vector2(rr.position.x + t, rr.get_center().y) if long_x else Vector2(rr.get_center().x, rr.position.y + t)
			L["interest"].append({"name": "hall_%d_%d" % [int(q.x * 10), int(q.y * 10)], "p": [q.x, q.y]})
			t += 6.0
	var first_fixture: int = L["fixtures"].size()
	# Ceiling grid for this room. Fixture = 1 x 2 tiles; long axis along corridors.
	var along_x := corridor and rr.size.x > rr.size.y
	var fw := 0.6
	var fl := 1.2
	var sx := 2.4
	var sz := 3.0
	if along_x:
		sx = 3.0
		sz = 2.4
	var nx := maxi(1, int(floor((inner.size.x - 0.6) / sx)) + 1)
	var nz := maxi(1, int(floor((inner.size.y - 0.6) / sz)) + 1)
	if corridor:
		if along_x:
			nz = 1
		else:
			nx = 1
	var cxm := inner.get_center().x
	var czm := inner.get_center().y
	var ex := (fl if along_x else fw) * 0.5
	var ez := (fw if along_x else fl) * 0.5
	for i in nx:
		for j in nz:
			var px := cxm + (i - (nx - 1) * 0.5) * sx
			var pz := czm + (j - (nz - 1) * 0.5) * sz
			# Snap so the lens covers whole ceiling tiles.
			px = (round(px / TILE - 0.5) + 0.5) * TILE if not along_x else round(px / TILE) * TILE
			pz = round(pz / TILE) * TILE if not along_x else (round(pz / TILE - 0.5) + 0.5) * TILE
			if px - ex < inner.position.x + 0.25 or px + ex > inner.end.x - 0.25 or pz - ez < inner.position.y + 0.25 or pz + ez > inner.end.y - 0.25:
				continue
			if px - ex < 0.31 or pz - ez < 0.31 or px + ex > CHUNK - 0.31 or pz + ez > CHUNK - 0.31:
				continue
			var blocked := false
			for p in L["pillars"]:
				if absf(px - p[0]) < ex + 0.45 and absf(pz - p[1]) < ez + 0.45:
					blocked = true
			var frect := Rect2(px - ex - 0.15, pz - ez - 0.15, 2.0 * ex + 0.3, 2.0 * ez + 0.3)
			for w in L["walls"]:
				var wr := Rect2(minf(w[0], w[2]) - 0.1, minf(w[1], w[3]) - 0.1, absf(w[2] - w[0]) + 0.2, absf(w[3] - w[1]) + 0.2)
				if wr.intersects(frect):
					blocked = true
			if blocked:
				continue
			L["fixtures"].append([px, pz, 1 if along_x else 0])
	if kind != "corridor" and not lf.get("pocket", false):
		_room_mood(L, rr, first_fixture)


## Seams (VISION "Exits", D022): about one chunk in three has a solid block standing in one of
## its rooms, like a service core. One door-sized patch of its wall exists only for the naked eye:
## through the camcorder it is not there, and you can walk through it into the sealed room inside,
## where a survey crew left a camera on a tripod filming the wall under a work light. The spawn
## chunk always has one, near the "LOOK THROUGH IT" chalk.
const POCKET := 3


func _pick_pocket_room(cx: int, cz: int, leaves: Array, spawn_chunk: bool) -> void:
	var pr := _rng("pocket:%d:%d" % [cx, cz])
	if not spawn_chunk and pr.randf() > 0.34:
		return
	var best: Dictionary = {}
	var best_score := -1e9
	for lf in leaves:
		if lf.get("corridor", false):
			continue
		var rm: Rect2i = lf["m"]
		if rm.size.x < POCKET + 2 or rm.size.y < POCKET + 2:
			continue
		var rr: Rect2 = lf["rect"]
		if rr.has_point(Vector2(3.0, rr.get_center().y)) and spawn_chunk:
			continue
		# Near the start in the spawn chunk; otherwise any, seeded.
		var score := -rr.get_center().distance_to(Vector2(10.0, 9.6)) if spawn_chunk else pr.randf()
		if score > best_score:
			best_score = score
			best = lf
	if not best.is_empty():
		best["pocket"] = true


## Scale error (art direction #3, D023): about one chunk in five has a room copied at the wrong
## scale: an ordinary office room whose walls and ceiling grid go on up to three times the
## height, over doors that are now far too small. Never the spawn chunk, never a pocket room.
func _pick_tall_room(cx: int, cz: int, leaves: Array, spawn_chunk: bool) -> void:
	var tr := _rng("tall:%d:%d" % [cx, cz])
	if spawn_chunk or tr.randf() > 0.2:
		return
	var cands := []
	for lf in leaves:
		if lf.get("corridor", false) or lf.get("pocket", false):
			continue
		var rm: Rect2i = lf["m"]
		if rm.size.x >= 4 and rm.size.y >= 4 and rm.size.x <= 11 and rm.size.y <= 11:
			cands.append(lf)
	if not cands.is_empty():
		cands[tr.randi() % cands.size()]["tall"] = true


## Builds the block, its seam and what is inside. Returns where a visitor would stand to look at
## the seam (the room's interest point).
func _pocket(L: Dictionary, rr: Rect2, spawn_chunk: bool) -> Vector2:
	var pr := _rng("pocket:in:%d:%d" % [int(rr.position.x * 10), int(rr.position.y * 10)] + "%d" % L["chunk"][0] + ":%d" % L["chunk"][1])
	var rm := Rect2i(Vector2i(roundi(rr.position.x / MOD), roundi(rr.position.y / MOD)), Vector2i(roundi(rr.size.x / MOD), roundi(rr.size.y / MOD)))
	var kx := rm.position.x + 1 + pr.randi_range(0, rm.size.x - POCKET - 2)
	var kz := rm.position.y + 1 + pr.randi_range(0, rm.size.y - POCKET - 2)
	var x0 := kx * MOD
	var z0 := kz * MOD
	var ps := POCKET * MOD
	var x1 := x0 + ps
	var z1 := z0 + ps
	# The seam faces the side with the most room in front of it.
	var sides := [["W", x0 - rr.position.x], ["E", rr.end.x - x1], ["N", z0 - rr.position.y], ["S", rr.end.y - z1]]
	var side := "W"
	var room_in_front := -1.0
	for sd in sides:
		var v: float = sd[1] + pr.randf() * 0.1
		if v > room_in_front:
			room_in_front = v
			side = sd[0]
	var n: Vector2 = {"W": Vector2(-1, 0), "E": Vector2(1, 0), "N": Vector2(0, -1), "S": Vector2(0, 1)}[side]
	# Four walls; the seam side in three pieces with the middle one left out (it is the seam).
	var faces := {"N": [x0, z0, x1, z0], "S": [x0, z1, x1, z1], "W": [x0, z0, x0, z1], "E": [x1, z0, x1, z1]}
	for f in faces:
		var w: Array = faces[f]
		if f != side:
			L["walls"].append(w)
			continue
		var horiz: bool = f == "N" or f == "S"
		var a: float = w[0] if horiz else w[1]
		var line: float = w[1] if horiz else w[0]
		for k in [0, 2]:
			var s0: float = a + k * MOD
			L["walls"].append([s0, line, s0 + MOD, line] if horiz else [line, s0, line, s0 + MOD])
		var m0 := a + MOD
		L["seams"].append({"wall": [m0, line, m0 + MOD, line] if horiz else [line, m0, line, m0 + MOD], "n": [n.x, n.y],
			"pocket": [x0, z0, x1, z1]})
	L["pocket_zones"].append([x0, z0, x1, z1])
	var c := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
	var seam_c := c + n * ps * 0.5
	# Inside: the camera on its tripod filming the wall, a crate of tapes, a work light on the floor
	# in a back corner throwing warm light up at it, and their marks on the walls.
	var t := Vector2(-n.y, n.x)
	var yaw_to_seam := rad_to_deg(atan2(n.x, n.y))
	L["props"].append(["prop_tripod_camcorder", c.x - n.x * 0.35 + t.x * 0.3, c.y - n.y * 0.35 + t.y * 0.3, yaw_to_seam + pr.randf_range(-12, 12)])
	var back := c - n * (ps * 0.5 - T * 0.5 - 0.3)
	var side_s := 1.0 if pr.randf() < 0.5 else -1.0
	var crate := back + t * side_s * (ps * 0.5 - 0.5)
	L["props"].append(["prop_tape_crate", crate.x, crate.y, pr.randf_range(0, 360)])
	L["props"].append(["prop_vhs_tape_sf", crate.x + n.x * 0.5 - t.x * side_s * 0.25, crate.y + n.y * 0.5 - t.y * side_s * 0.25, pr.randf_range(0, 360)])
	var wl := c + n * (ps * 0.5 - T * 0.5 - 0.42) - t * side_s * (ps * 0.5 - 0.5)
	var aim := (back + t * side_s * 0.3) - wl
	L["worklights"].append([wl.x, wl.y, rad_to_deg(atan2(aim.x, aim.y))])
	var back_wall := c - n * ps * 0.5 + n * T * 0.5
	L["graffiti"].append(["hd_tape_label", back_wall.x + t.x * 0.6, back_wall.y + t.y * 0.6, n.x, n.y, 1.55])
	var side_wall := c + t * side_s * (ps * 0.5 - T * 0.5)
	L["graffiti"].append(["hd_survey", side_wall.x - n.x * 0.4, side_wall.y - n.y * 0.4, -t.x * side_s, -t.y * side_s, 1.2])
	# Outside: sometimes someone traced the doorway in chalk, sometimes the crew marked it.
	var hint := pr.randf()
	var out_face := seam_c + n * T * 0.5
	if spawn_chunk or hint < 0.4:
		L["graffiti"].append(["chalk_door", out_face.x, out_face.y, n.x, n.y, 1.12, 1.7])
	elif hint < 0.65:
		L["graffiti"].append(["hd_survey", out_face.x + t.x * 1.15, out_face.y + t.y * 1.15, n.x, n.y, 1.25])
	var look := seam_c + n * minf(2.2, room_in_front * 0.6)
	L["interest"].append({"name": "seam_%d_%d" % [int(look.x * 10), int(look.y * 10)], "p": [look.x, look.y], "seam": [seam_c.x, seam_c.y], "pocket": [c.x, c.y]})
	return look


## How a room is lit (critique 008, L042: lit rooms were evenly filled; L039: one yellow
## everywhere). Most rooms are fully lit, but some keep only the panel nearest the middle (one
## pool of light and the rest falling away), some have one side dead, some have tired, warm tubes,
## and a few were refitted with tubes of the wrong color. Some rooms are papered in a color that
## bled in from somewhere else (generation loss). Draws from its own stream.
func _room_mood(L: Dictionary, rr: Rect2, first: int) -> void:
	var mr := _rng("mood:%d:%d:%d:%d" % [L["chunk"][0], L["chunk"][1], int(rr.position.x * 10), int(rr.position.y * 10)])
	var fx: Array = L["fixtures"]
	var n := fx.size() - first
	var roll := mr.randf()
	var c := rr.get_center()
	if n >= 3 and roll < 0.26:
		var best := first
		for i in range(first, fx.size()):
			if Vector2(fx[i][0], fx[i][1]).distance_to(c) < Vector2(fx[best][0], fx[best][1]).distance_to(c):
				best = i
		for i in range(first, fx.size()):
			fx[i].append("on" if i == best else "dead")
	elif n >= 4 and roll < 0.44:
		var along_x := rr.size.x >= rr.size.y
		var keep_low := mr.randf() < 0.5
		for i in range(first, fx.size()):
			var lowside: bool = (fx[i][0] < c.x) if along_x else (fx[i][1] < c.y)
			fx[i].append("dead" if lowside == keep_low else "on")
	elif roll < 0.56:
		for i in range(first, fx.size()):
			fx[i].append("dim")
	var tint_roll := mr.randf()
	if tint_roll < 0.1:
		L["tint_zones"].append([rr.position.x, rr.position.y, rr.end.x, rr.end.y, 0.64, 0.83, 1.0])    # cold blue-white
	elif tint_roll < 0.16:
		L["tint_zones"].append([rr.position.x, rr.position.y, rr.end.x, rr.end.y, 0.78, 1.0, 0.66])    # sick green
	if not L.has("recolor") and mr.randf() < 0.09:
		var cols := [[0.80, 0.98, 0.86], [1.0, 0.82, 0.78], [0.80, 0.86, 1.0]]
		var col: Array = cols[mr.randi() % cols.size()]
		L["recolor"] = [rr.position.x + 0.05, rr.position.y + 0.05, rr.end.x - 0.05, rr.end.y - 0.05, col[0], col[1], col[2]]


## The x nearest `want` where a horizontal wall on line z has a solid run wide enough for a
## piece `w` meters wide (graffiti never hangs over a doorway). -100 if none.
func _wall_run_x(L: Dictionary, want: float, z: float, w: float) -> float:
	var best := -100.0
	var bd := 1e9
	for wl in L["walls"]:
		if absf(wl[1] - z) > 0.01 or absf(wl[3] - z) > 0.01:
			continue
		var a := minf(wl[0], wl[2]) + w * 0.5 + 0.3
		var b := maxf(wl[0], wl[2]) - w * 0.5 - 0.3
		if b < a:
			continue
		var x := clampf(want, a, b)
		if absf(x - want) < bd:
			bd = absf(x - want)
			best = x
	return best


## Free-standing L and T partitions in big rooms, and short fins off long walls (layout language
## from Stewart's floor-plan reference, D016). Partitions keep 1.2 m clear of every room wall, so
## they never cut the room off; fins are short and only in deep rooms.
func _partitions(r: RandomNumberGenerator, L: Dictionary, rr: Rect2) -> void:
	if rr.size.x >= 7.2 and rr.size.y >= 7.2 and r.randf() < 0.4:
		var cx := snappedf(rr.position.x + rr.size.x * r.randf_range(0.35, 0.65), MOD)
		var cz := snappedf(rr.position.y + rr.size.y * r.randf_range(0.35, 0.65), MOD)
		var ax := MOD * r.randi_range(2, 3) * (1.0 if r.randf() < 0.5 else -1.0)
		var az := MOD * r.randi_range(2, 3) * (1.0 if r.randf() < 0.5 else -1.0)
		var inner := rr.grow(-1.2)
		if inner.has_point(Vector2(cx + ax, cz)) and inner.has_point(Vector2(cx, cz + az)) and inner.has_point(Vector2(cx, cz)):
			L["walls"].append([minf(cx, cx + ax), cz, maxf(cx, cx + ax), cz])
			L["walls"].append([cx, minf(cz, cz + az), cx, maxf(cz, cz + az)])
			if r.randf() < 0.4 and inner.has_point(Vector2(cx - ax * 0.5, cz)):
				# A T: the bar continues past the corner.
				L["walls"][-2] = [minf(cx - ax * 0.5, cx + ax), cz, maxf(cx - ax * 0.5, cx + ax), cz]
	# Fins: a short stub of wall standing out from a long wall, every few meters.
	if minf(rr.size.x, rr.size.y) >= 4.8 and r.randf() < 0.3:
		var along_x := rr.size.x >= rr.size.y
		var z0 := rr.position.y if r.randf() < 0.5 else rr.end.y
		var x0 := rr.position.x if r.randf() < 0.5 else rr.end.x
		var length := MOD * r.randi_range(1, 2)
		var t := 2.4
		while t < (rr.size.x if along_x else rr.size.y) - 2.0:
			if along_x:
				var x := snappedf(rr.position.x + t, MOD)
				var d := length if z0 == rr.position.y else -length
				if not _near_door(L, Vector2(x, z0 + d * 0.5), 1.4):
					L["walls"].append([x, minf(z0, z0 + d), x, maxf(z0, z0 + d)])
			else:
				var z := snappedf(rr.position.y + t, MOD)
				var d2 := length if x0 == rr.position.x else -length
				if not _near_door(L, Vector2(x0 + d2 * 0.5, z), 1.4):
					L["walls"].append([minf(x0, x0 + d2), z, maxf(x0, x0 + d2), z])
			t += MOD * r.randi_range(3, 5)


func _spawn_point(L: Dictionary, leaves: Array) -> Array:
	for lf in leaves:
		if lf.get("highway", false) and (lf["rect"] as Rect2).size.x > (lf["rect"] as Rect2).size.y:
			var c: Vector2 = (lf["rect"] as Rect2).get_center()
			return [3.0, c.y, 90.0]
	# The room nearest the chunk center that has a lit fixture, facing its longest view.
	var best := Vector2(12, 12)
	var bd := 1e9
	for lf in leaves:
		var c: Vector2 = (lf["rect"] as Rect2).get_center()
		var d := c.distance_to(Vector2(12, 12))
		if d < bd:
			bd = d
			best = c
	return [best.x, best.y, 90.0]


# ------------------------------------------------------------------ landmarks and splices

func _wall_spots(L: Dictionary, rr: Rect2, min_len: float) -> Array:
	## Straight wall runs bordering a room: [p0 (Vector2), p1, inward normal (Vector2)].
	var out := []
	for w in L["walls"] + L["edge_walls"]:
		var a := Vector2(w[0], w[1])
		var b := Vector2(w[2], w[3])
		if a.distance_to(b) < min_len:
			continue
		var horiz := absf(a.y - b.y) < 0.001
		if horiz:
			if absf(a.y - rr.position.y) < 0.01 and minf(a.x, b.x) < rr.end.x and maxf(a.x, b.x) > rr.position.x:
				out.append([Vector2(maxf(minf(a.x, b.x), rr.position.x), a.y), Vector2(minf(maxf(a.x, b.x), rr.end.x), a.y), Vector2(0, 1)])
			elif absf(a.y - rr.end.y) < 0.01 and minf(a.x, b.x) < rr.end.x and maxf(a.x, b.x) > rr.position.x:
				out.append([Vector2(maxf(minf(a.x, b.x), rr.position.x), a.y), Vector2(minf(maxf(a.x, b.x), rr.end.x), a.y), Vector2(0, -1)])
		else:
			if absf(a.x - rr.position.x) < 0.01 and minf(a.y, b.y) < rr.end.y and maxf(a.y, b.y) > rr.position.y:
				out.append([Vector2(a.x, maxf(minf(a.y, b.y), rr.position.y)), Vector2(a.x, minf(maxf(a.y, b.y), rr.end.y)), Vector2(1, 0)])
			elif absf(a.x - rr.end.x) < 0.01 and minf(a.y, b.y) < rr.end.y and maxf(a.y, b.y) > rr.position.y:
				out.append([Vector2(a.x, maxf(minf(a.y, b.y), rr.position.y)), Vector2(a.x, minf(maxf(a.y, b.y), rr.end.y)), Vector2(-1, 0)])
	return out.filter(func(s): return (s[0] as Vector2).distance_to(s[1]) >= min_len)


func _near_door(L: Dictionary, p: Vector2, rad: float) -> bool:
	for d in L["doors"]:
		if p.distance_to(Vector2((d[0] + d[2]) * 0.5, (d[1] + d[3]) * 0.5)) < rad:
			return true
	for side in L["gates"].keys():
		for g in L["gates"][side]:
			var m: float = (g[0] + g[1]) * 0.5
			var q := Vector2(0, m) if side == "W" else (Vector2(CHUNK, m) if side == "E" else (Vector2(m, 0) if side == "N" else Vector2(m, CHUNK)))
			if p.distance_to(q) < rad + (g[1] - g[0]) * 0.5:
				return true
	return false


func _landmarks(r: RandomNumberGenerator, L: Dictionary, leaves: Array, spawn_chunk: bool) -> void:
	var loss := clampf(1.0 - fidelity, 0.0, 1.0) * 10.0   # 1.0 at fidelity 0.9 (Level 0)
	var rooms := leaves.filter(func(lf): return not lf.get("corridor", false))
	var corridors := leaves.filter(func(lf): return lf.get("corridor", false) and not lf.get("highway", false))
	_seeded_shuffle(r, rooms)
	_seeded_shuffle(r, corridors)
	# Soaked room.
	if rooms.size() > 0 and r.randf() < 0.18:
		var rr: Rect2 = rooms[0]["rect"]
		L["flood_candidates"].append([rr.position.x + 0.2, rr.position.y + 0.2, rr.end.x - 0.2, rr.end.y - 0.2])
	# A corridor of cold replacement tubes.
	if corridors.size() > 0 and r.randf() < 0.22:
		var cr: Rect2 = corridors[0]["rect"]
		L["tint_zones"].append([cr.position.x, cr.position.y, cr.end.x, cr.end.y, 0.74, 0.92, 1.0])
	# Exit sign over a door, a door set into a solid wall.
	if L["doors"].size() > 0 and r.randf() < 0.55:
		var d: Array = L["doors"][r.randi() % L["doors"].size()]
		var horiz: bool = absf(d[1] - d[3]) < 0.001
		var c := Vector2((d[0] + d[2]) * 0.5, (d[1] + d[3]) * 0.5)
		var n := Vector2(0, 1) if horiz else Vector2(1, 0)
		if r.randf() < 0.5:
			n = -n
		if c.x > 1.0 and c.y > 1.0 and c.x < CHUNK - 1.0 and c.y < CHUNK - 1.0:
			L["exit_signs"].append([c.x + n.x * 0.1, c.y + n.y * 0.1, n.x, n.y])
	var spots_all := []
	for lf in rooms:
		for s in _wall_spots(L, lf["rect"], 2.4):
			spots_all.append([lf, s])
	_seeded_shuffle(r, spots_all)
	var used_spots := []
	var take_spot := func(min_len: float) -> Array:
		for sp in spots_all:
			if sp in used_spots:
				continue
			var s: Array = sp[1]
			if (s[0] as Vector2).distance_to(s[1]) < min_len:
				continue
			used_spots.append(sp)
			return sp
		return []
	if r.randf() < 0.3 * loss:
		var sp: Array = take_spot.call(2.4)
		if sp.size() > 0:
			var s: Array = sp[1]
			var mid: Vector2 = (s[0] + s[1]) * 0.5
			if not _near_door(L, mid, 1.4):
				L["fake_doors"].append([mid.x + s[2].x * 0.1, mid.y + s[2].y * 0.1, s[2].x, s[2].y])
	# Chair pushed into a wall (faces the wall, front buried).
	if r.randf() < 0.22 * loss:
		var sp2: Array = take_spot.call(2.0)
		if sp2.size() > 0:
			var s2: Array = sp2[1]
			var p: Vector2 = (s2[0] as Vector2).lerp(s2[1], r.randf_range(0.3, 0.7)) + s2[2] * (T * 0.5 + 0.1)
			if not _near_door(L, p, 1.2):
				var n2: Vector2 = s2[2]
				L["splices"].append({"prop": "prop_office_chair", "pos": [p.x, p.y], "yaw": rad_to_deg(atan2(-n2.x, -n2.y)), "y": 0.0, "half": 0.3, "seam": [n2.x, n2.y]})
	# The same folding chair, looped like a stuck frame.
	if r.randf() < 0.2 * loss:
		var sp3: Array = take_spot.call(4.0)
		if sp3.size() > 0:
			var s3: Array = sp3[1]
			var dir: Vector2 = ((s3[1] as Vector2) - s3[0]).normalized()
			var p3: Vector2 = (s3[0] as Vector2) + dir * 0.9 + s3[2] * (T * 0.5 + 0.35)
			if not _near_door(L, p3 + dir * 1.15, 1.8):
				var n3: Vector2 = s3[2]
				L["splices"].append({"prop": "prop_folding_chair_sf", "pos": [p3.x, p3.y], "yaw": rad_to_deg(atan2(-n3.x, -n3.y)), "y": 0.0, "half": 0.25, "repeat": 3, "step": [dir.x * 1.15, dir.y * 1.15]})
	# A chair standing upside down on the ceiling.
	if rooms.size() > 1 and r.randf() < 0.14 * loss:
		var rr2: Rect2 = rooms[1]["rect"]
		var c4 := rr2.get_center() + Vector2(r.randf_range(-0.6, 0.6), r.randf_range(-0.6, 0.6))
		L["splices"].append({"prop": "prop_office_chair_alt_sf", "pos": [c4.x, c4.y], "yaw": r.randf_range(0, 360), "flip": true, "half": 0.3})
	# A troffer installed sideways on a wall, still lit.
	if r.randf() < 0.12 * loss:
		var sp5: Array = take_spot.call(2.0)
		if sp5.size() > 0:
			var s5: Array = sp5[1]
			var p5: Vector2 = ((s5[0] as Vector2) + s5[1]) * 0.5 + s5[2] * (T * 0.5)
			if not _near_door(L, p5, 1.2):
				L["wall_fixtures"].append([p5.x, p5.y, s5[2].x, s5[2].y, 1.45])
	# A troffer set face-up into the carpet, lighting the ceiling.
	if rooms.size() > 2 and r.randf() < 0.1 * loss:
		var rr3: Rect2 = rooms[2]["rect"]
		var c6 := rr3.get_center()
		L["floor_fixtures"].append([snappedf(c6.x, TILE) + 0.3, snappedf(c6.y, TILE)])
	# Stairs that climb into the ceiling, along a long wall.
	if r.randf() < 0.1 * loss and not spawn_chunk:
		var sp7: Array = take_spot.call(6.2)
		if sp7.size() > 0:
			var s7: Array = sp7[1]
			var n7: Vector2 = s7[2]
			var dir7: Vector2 = ((s7[1] as Vector2) - s7[0]).normalized()
			var room7: Rect2 = sp7[0]["rect"]
			var depth := room7.size.x if absf(n7.x) > 0.5 else room7.size.y
			var start: Vector2 = (s7[0] as Vector2) + dir7 * 0.3 + n7 * (T * 0.5)
			var ok := depth >= 3.6
			for k in 7:
				if _near_door(L, start + dir7 * k * 0.9 + n7 * 0.5, 1.3):
					ok = false
			if ok:
				# _build_stairs puts the flight on the +side of the origin; place o accordingly.
				var side := Vector2(-dir7.y, dir7.x)
				if side.x < 0.0 or side.y < 0.0:
					side = -side
				var o := start if side.dot(n7) > 0.0 else start + n7 * 1.05
				L["stairs"].append([o.x, o.y, dir7.x, dir7.y, 1.05])
	# Wallpaper that slipped sideways, like a tracking error.
	if r.randf() < 0.18 * loss:
		var sp8: Array = take_spot.call(2.4)
		if sp8.size() > 0:
			var s8: Array = sp8[1]
			var a: Vector2 = s8[0]
			var b: Vector2 = s8[1]
			var y0 := r.randf_range(0.9, 1.5)
			L["shear_bands"].append([minf(a.x, b.x) - 0.15, minf(a.y, b.y) - 0.15, maxf(a.x, b.x) + 0.15, maxf(a.y, b.y) + 0.15, y0, y0 + r.randf_range(0.25, 0.5), 0.036])
	# Graffiti on a couple of room walls.
	var pieces := ["only_on_tape", "lights", "map_loop", "sigil", "exits", "gaps_child", "days", "we_are_copy", "handprints", "was_here", "same", "tally_copy",
		"film_walls", "missing_flyer", "calendar_oct96", "scrawl_small_1", "scrawl_small_2", "scrawl_small_3", "scrawl_small_4", "missing_flyer"]
	for k in r.randi_range(0, 2):
		var spg: Array = take_spot.call(2.4)
		if spg.size() == 0:
			break
		var sg: Array = spg[1]
		var pg: Vector2 = (sg[0] as Vector2).lerp(sg[1], r.randf_range(0.25, 0.75)) + sg[2] * (T * 0.5)
		if _near_door(L, pg, 0.9):
			continue
		var slug: String = pieces[r.randi() % pieces.size()]
		var gy := r.randf_range(1.15, 1.6) if slug != "handprints" else r.randf_range(0.9, 1.3)
		if slug in ["missing_flyer", "calendar_oct96"]:
			gy = r.randf_range(1.45, 1.6)
		L["graffiti"].append([slug, pg.x, pg.y, sg[2].x, sg[2].y, gy])
	# Ordinary abandoned things.
	var props := ["prop_office_chair_alt_sf", "prop_folding_chair_sf", "prop_crt_monitor_sf", "prop_cardboard_box_sf", "prop_cardboard_box"]
	var n_props := r.randi_range(1, 4)
	for k in n_props:
		var spp: Array = take_spot.call(1.6)
		if spp.size() == 0:
			break
		var sq: Array = spp[1]
		var pp: Vector2 = (sq[0] as Vector2).lerp(sq[1], r.randf_range(0.2, 0.8)) + sq[2] * (T * 0.5 + 0.38)
		if _near_door(L, pp, 1.1):
			continue
		L["props"].append([props[r.randi() % props.size()], pp.x, pp.y, r.randf_range(0, 360)])


static func _seeded_shuffle(r: RandomNumberGenerator, a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
