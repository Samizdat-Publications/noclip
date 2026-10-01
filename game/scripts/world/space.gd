class_name Space
extends Node3D
## A self-contained place: the furniture store (hub), a Backrooms level, or a set piece.
##
## Every Space builds itself from a seed, owns its look (Environment and camera
## attributes) and its ambience, and connects to other Spaces through Thresholds.
## The World (scripts/core/main.gd) holds the active Space(s) and the Player and
## moves the player between Spaces when a Threshold is crossed. Two Spaces can be
## live at once so a crossing can be seamless (the duct-taped wall in the store
## opens onto a Level 0 chunk that is already built behind it).

@export var space_id: StringName = &""
var space_seed: int = 0
var thresholds: Array[Threshold] = []


## Build all geometry, lights and audio for this seed. Must be deterministic.
func build(p_seed: int) -> void:
	space_seed = p_seed


## Where the player appears when entering this space without a threshold.
func get_spawn_transform() -> Transform3D:
	return Transform3D.IDENTITY


## The Environment (tonemap, GI, fog, grade) that defines this space's look.
func make_environment() -> Environment:
	return Environment.new()


func make_camera_attributes() -> CameraAttributes:
	return CameraAttributesPractical.new()


## Walkable-space query for bots and AI: returns true if a point is free floor.
func is_walkable(_p: Vector3) -> bool:
	return true


## Path between two points (world space) for bots. Spaces override this.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return PackedVector3Array([from, to])


## Clear distance from p looking along yaw (bots use it to look somewhere open).
func view_depth(_p: Vector3, _yaw: float, max_d: float = 20.0) -> float:
	return max_d


## Points a curious player would walk to (rooms, doorways, dark corners).
func get_interest_points() -> Array:
	return []


## How wet the floor is at a point (0..1), used by footsteps.
func floor_wetness(_p: Vector3) -> float:
	return 0.0


func register_threshold(t: Threshold) -> void:
	thresholds.append(t)
	t.space = self
