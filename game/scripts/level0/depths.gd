class_name Depths
extends RefCounted
## The stack under the Landing (VISION "Progression: The Descent", D050). Each depth is the same kind
## of place copied again, a generation further from the original: its own paper and light, fewer
## panels left on, a haze of its own, the stairwell further from where you come in, and the thing
## that hunts there sooner and quicker. Depth 1 is the Yellow as it has always been.
##
## Palette keys are the ones PortalRoom.PALETTES uses (wall_tint, wall_sat, carpet_tint, carpet_sat,
## ceil_tint, pillar), applied to the level's shared materials; "tube" tints every panel, "gain"
## scales every panel, "fog" is the haze colour, "fidelity" the generator's dial.

const TABLE := [
	{},   # 0 unused
	{"name": "THE YELLOW", "ring": 1, "first_at": 70.0, "chase": 3.1, "gap": 1.0, "fidelity": 0.9, "salvage_m": 0.25},
	{"name": "THE COLD ROOMS", "ring": 2, "first_at": 55.0, "chase": 3.25, "gap": 0.85, "fidelity": 0.8, "salvage_m": 0.45,
		"pal": {"wall_tint": [0.84, 0.88, 0.95], "wall_sat": 0.12, "carpet_sat": 0.25, "carpet_tint": [0.8, 0.86, 0.98],
			"ceil_tint": [0.93, 0.96, 1.02], "pillar": [0.6, 0.62, 0.64]},
		"tube": [0.84, 0.9, 1.0], "gain": 0.82, "fog": [0.86, 0.9, 0.97]},
	{"name": "THE GREEN", "ring": 3, "first_at": 45.0, "chase": 3.35, "gap": 0.75, "fidelity": 0.7, "salvage_m": 0.7,
		"pal": {"wall_tint": [0.84, 1.03, 0.86], "wall_sat": 0.35, "carpet_sat": 0.6, "carpet_tint": [0.92, 1.02, 0.9],
			"pillar": [0.7, 0.78, 0.68]},
		"tube": [0.88, 1.0, 0.8], "gain": 0.66, "fog": [0.88, 0.94, 0.84]},
	{"name": "THE RED HALLS", "ring": 4, "first_at": 35.0, "chase": 3.45, "gap": 0.65, "fidelity": 0.6, "salvage_m": 1.0,
		"pal": {"wall_tint": [1.05, 0.78, 0.72], "wall_sat": 0.5, "carpet_tint": [0.95, 0.7, 0.66], "carpet_sat": 0.5,
			"ceil_tint": [1.0, 0.86, 0.84], "pillar": [0.62, 0.42, 0.4]},
		"tube": [1.0, 0.42, 0.34], "gain": 0.5, "fog": [0.95, 0.78, 0.74]},
]


## The row for a depth; below the table the last row repeats, darker each time.
static func get_row(depth: int) -> Dictionary:
	var d := clampi(depth, 1, TABLE.size() - 1)
	var row: Dictionary = (TABLE[d] as Dictionary).duplicate(true)
	var extra := depth - d
	if extra > 0:
		row["name"] = "DEPTH %d" % depth
		row["gain"] = maxf(0.25, float(row.get("gain", 1.0)) - 0.08 * extra)
		row["first_at"] = maxf(20.0, float(row["first_at"]) - 4.0 * extra)
		row["chase"] = minf(3.6, float(row["chase"]) + 0.04 * extra)
		row["fidelity"] = maxf(0.3, float(row["fidelity"]) - 0.05 * extra)
		row["salvage_m"] = float(row["salvage_m"]) + 0.2 * extra
	return row


static func label(depth: int) -> String:
	return "DEPTH %d   %s" % [depth, String(get_row(depth)["name"])] if depth <= TABLE.size() - 1 else "DEPTH %d" % depth
