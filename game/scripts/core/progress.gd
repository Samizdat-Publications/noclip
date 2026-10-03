class_name Progress
extends RefCounted
## What carries between runs (VISION "Progression: The Descent", D050): salvage, the kit you have
## bought, the deepest depth you have reached (it opens kit levels and lift stops), Halden's standing,
## the layout seed each depth keeps, and where you died on each depth. Saved in user://progress.json
## (the autoplay bot keeps its own file, wiped at the start of every bot run unless --keep_progress,
## so a capture never depends on an old save).

## Kit: id -> [label, [cost per level], [depth needed per level], what it does]
const KIT := {
	"flash": ["FLASHBULB", [80, 260, 520], [1, 2, 3], "F with the camcorder up. Pins it where it stands. Charges per run."],
	"flares": ["ROAD FLARES", [70, 200, 420], [1, 2, 3], "G throws one. Burns red. It will not cross red light."],
	"boots": ["OVERSHOES", [110, 300], [1, 2], "Quieter steps. Sprint for longer."],
	"stock": ["BETTER TAPE STOCK", [150, 380], [1, 3], "A caught tape keeps more of its salvage."],
	"radio": ["FIELD RADIO", [300], [2], "The hiss clears when you face the way down."],
	"crowbar": ["CROWBAR", [340], [2], "Opens the doors with no handles."],
}
## What the locker offers. The radio and the crowbar join when they do something (S08).
const KIT_ORDER := ["flash", "flares", "boots", "stock"]

var salvage := 0
var lifetime := 0
var deepest := 1
var standing := 0
var runs := 0
var world_seed := 0
var kit := {}                  # id -> level bought
var deaths := {}               # "depth" -> [x, y, z] where you were caught last on that depth
var _path := ""


func _init() -> void:
	_path = "user://progress_bot.json" if Game.autoplay else "user://progress.json"
	if Game.autoplay and not Game.opts.has("keep_progress"):
		_reset()
		save()
	else:
		load_file()
	if Game.opts.has("fresh_progress"):
		_reset()
		save()
	# Builder overrides: --kit=flash:2,flares:1  --deepest=3  --salvage=500
	if Game.opts.has("kit"):
		for kv in String(Game.opts["kit"]).split(","):
			var p := kv.split(":")
			if p.size() == 2:
				kit[p[0]] = int(p[1])
	if Game.opts.has("deepest"):
		deepest = int(Game.opts["deepest"])
	if Game.opts.has("salvage"):
		salvage = int(Game.opts["salvage"])


func _reset() -> void:
	salvage = 0
	lifetime = 0
	deepest = 1
	standing = 0
	runs = 0
	kit = {}
	deaths = {}
	# The bot's (and a fresh save's) layout follows the run seed, so a capture seed reproduces its level.
	world_seed = Game.run_seed if Game.autoplay else Game.rng("progress:world").randi() % 1000000


func load_file() -> void:
	if not FileAccess.file_exists(_path):
		_reset()
		save()
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if not (d is Dictionary):
		_reset()
		return
	salvage = int(d.get("salvage", 0))
	lifetime = int(d.get("lifetime", 0))
	deepest = maxi(1, int(d.get("deepest", 1)))
	standing = int(d.get("standing", 0))
	runs = int(d.get("runs", 0))
	world_seed = int(d.get("world_seed", Game.run_seed))
	kit = d.get("kit", {})
	deaths = d.get("deaths", {})


func save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"salvage": salvage, "lifetime": lifetime, "deepest": deepest,
			"standing": standing, "runs": runs, "world_seed": world_seed, "kit": kit, "deaths": deaths}, "  "))
		f.close()


func level(id: String) -> int:
	return int(kit.get(id, 0))


## The next level of an item: [cost, depth needed] or [] when it is maxed out.
func next_cost(id: String) -> Array:
	var lv := level(id)
	var costs: Array = KIT[id][1]
	if lv >= costs.size():
		return []
	return [int(costs[lv]), int(KIT[id][2][lv])]


func can_buy(id: String) -> bool:
	var nc := next_cost(id)
	return not nc.is_empty() and salvage >= int(nc[0]) and deepest >= int(nc[1])


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	salvage -= int(next_cost(id)[0])
	kit[id] = level(id) + 1
	save()
	return true


## The share of salvage a tape keeps when you are caught.
func caught_share() -> float:
	return [0.6, 0.75, 0.9][clampi(level("stock"), 0, 2)]


## The layout a depth keeps from run to run.
func depth_seed(depth: int) -> int:
	return absi(hash("%d:depth:%d" % [world_seed, depth])) % 1000000 if depth > 1 else world_seed
