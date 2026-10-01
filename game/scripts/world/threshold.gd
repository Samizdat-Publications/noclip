class_name Threshold
extends Node3D
## A connection between two Spaces: the duct-taped noclip wall in the store, a Seam
## (exit) in a level, an elevator, a stairwell. When the player crosses it, the World
## loads or aligns the target Space and hands the player over.
##
## kind:
##   NOCLIP_WALL  looks solid, the player can walk through it (store to Level 0)
##   SEAM         a level exit; leads deeper or (rarely) back up
##   PORTAL       seamless render-to-texture doorway inside or between Spaces (M2)

enum Kind { NOCLIP_WALL, SEAM, PORTAL }

signal crossed(threshold: Threshold, body: Node3D)

@export var kind: Kind = Kind.SEAM
@export var target_space: StringName = &""
@export var target_threshold: StringName = &""
@export var size: Vector3 = Vector3(1.2, 2.2, 0.4)
var space: Space


func _ready() -> void:
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(func(b: Node3D) -> void: crossed.emit(self, b))
