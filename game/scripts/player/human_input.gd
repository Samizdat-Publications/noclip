class_name HumanInput
extends PlayerInput
## Mouse and keyboard.

var sensitivity := 0.0022
var _mouse := Vector2.ZERO


func push_mouse(rel: Vector2) -> void:
	_mouse += rel


func update_move(_player: Node, _delta: float) -> void:
	move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	sprint = Input.is_action_pressed("sprint")
	crouch = Input.is_action_pressed("crouch")
	camcorder = Input.is_action_pressed("camcorder")


func update_look(_player: Node, _delta: float) -> void:
	look_delta = Vector2(_mouse.x, -_mouse.y) * sensitivity
	_mouse = Vector2.ZERO
