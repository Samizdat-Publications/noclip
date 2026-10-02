class_name Level0Hero
extends Space
## The Level 0 look-dev hero slice (S01, kept as the reference scene): one fixed 30 x 30 m
## chunk built from data/level0_hero.json, with every fixture owning its own light and hum.
## Run it with `-- --hero`. The game itself now plays the infinite level (Level0World).

const LAYOUT := "res://data/level0_hero.json"

var chunk: Level0Chunk
var director: Level0Director
var fixtures: Array[Fixture]:
	get:
		return chunk.fixtures


func build(p_seed: int) -> void:
	super.build(p_seed)
	space_id = &"level0_hero"
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var r := Game.rng("level0:look")
	var seed_offset := Vector2(r.randf_range(0.0, 50.0), r.randf_range(0.0, 50.0))
	var mats := Level0Look.make_materials(seed_offset)
	chunk = Level0Chunk.new()
	chunk.name = "hero"
	add_child(chunk)
	chunk.build(L, "", mats, seed_offset)
	director = Level0Director.new()
	director.space = self
	director.fixtures = chunk.fixtures
	add_child(director)
	if Game.opts.has("dump-scene"):
		chunk._write_dump(String(Game.opts["dump-scene"]))


func get_spawn_transform() -> Transform3D:
	return chunk.get_spawn_transform()


func make_environment() -> Environment:
	return Level0Look.make_environment(Game.preset)


func make_camera_attributes() -> CameraAttributes:
	return Level0Look.make_camera_attributes()


func is_walkable(p: Vector3) -> bool:
	return chunk.is_walkable(p)


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return chunk.find_path(from, to)


func view_depth(p: Vector3, yaw: float, max_d: float = 20.0) -> float:
	return chunk.view_depth(p, yaw, max_d)


func get_interest_points() -> Array:
	return chunk.get_interest_points()


func floor_wetness(p: Vector3) -> float:
	return chunk.floor_wetness(p)


func set_listener(p: Vector3) -> void:
	chunk.set_listener(p)
	director.listener = p


func set_view(_p: Vector3, fwd: Vector3) -> void:
	director.view_fwd = fwd
