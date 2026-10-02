class_name PlayerInput
extends RefCounted
## What the player wants this frame. The human (mouse and keyboard) and the autoplay bot
## both fill this in, so the bot drives the exact same controller a person does.

var move := Vector2.ZERO          # x = strafe right, y = forward, length <= 1
var look_delta := Vector2.ZERO    # radians this render frame: x = yaw right, y = pitch up
var sprint := false
var crouch := false
var crawl := false                # lie down and crawl (toggle); low openings also force it
var camcorder := false


## Called once per physics tick (movement intent).
func update_move(_player: Node, _delta: float) -> void:
	pass


## Called once per render frame (look).
func update_look(_player: Node, _delta: float) -> void:
	pass
