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

## Gaps (open intervals in meters along the edge, 0..CHUNK) of a shared chunk edge.
## axis "V": the vertical line x = ex * CHUNK spanning chunk row ez.
## axis "H": the horizontal line z = ez * CHUNK spanning chunk column ex.
func edge_gaps(axis: String, ex: int, ez: int) -> Array:
	var r := _rng("edge:%s:%d:%d" % [axis, ex, ez])
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
	_split(r, L, Rect2i(0, 0, NMOD, NMOD), root_gaps, 0, max_depth, leaves)
	# --- rooms, fixtures, pillars
	for lf in leaves:
		_furnish_room(r, L, lf, spawn_chunk)
	# --- darkness: a few whole rooms dead, a cluster or two of dead panels
	var dark_rooms := 0
	for lf in leaves:
		var rr: Rect2 = lf["rect"]
		if spawn_chunk and rr.has_point(Vector2(12, 12)):
			continue
		if r.randf() < 0.22 and dark_rooms < 3:
			L["dark_zones"].append([rr.position.x, rr.position.y, rr.end.x, rr.end.y])
			dark_rooms += 1
	# --- landmarks and splice errors
	_landmarks(r, L, leaves, spawn_chunk)
	if spawn_chunk:
		L["spawn"] = _spawn_point(L, leaves)
	return L


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
		var x := rr.position.x + step
		while x < rr.end.x - 1.6:
			var z := rr.position.y + step
			while z < rr.end.y - 1.6:
				L["pillars"].append([snappedf(x, MOD), snappedf(z, MOD), 0.6])
				z += step
			x += step
	L["rooms"].append([rr.position.x, rr.position.y, rr.end.x, rr.end.y, kind])
	L["interest"].append({"name": "%s_%d_%d" % [kind, int(rr.position.x * 10), int(rr.position.y * 10)], "p": [rr.get_center().x, rr.get_center().y]})
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
			if blocked:
				continue
			L["fixtures"].append([px, pz, 1 if along_x else 0])


func _spawn_point(L: Dictionary, leaves: Array) -> Array:
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
	var corridors := leaves.filter(func(lf): return lf.get("corridor", false))
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
	if L["doors"].size() > 0 and r.randf() < 0.3:
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
