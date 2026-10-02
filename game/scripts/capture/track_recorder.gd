class_name TrackRecorder
extends Node
## Records the exact camera used for every rendered frame (and the brightness of every
## animated light) so another renderer can replay the same shot list. Used for the engine
## bake-off: --track=FILE.json. Runs last in the frame so it sees the final camera.

var out_path := ""
var space: Space
var player: Player
var frames: Array = []
var _done := false


func _ready() -> void:
	process_priority = 1000


func _process(_delta: float) -> void:
	if _done:
		return
	var cam := player.cam
	var q := cam.global_transform.basis.get_rotation_quaternion()
	var o := cam.global_transform.origin
	var lv := {}
	for i in space.get("fixtures").size():
		var fx: Fixture = space.get("fixtures")[i]
		if fx.is_processing():
			lv[str(i)] = snappedf(fx.level, 0.001)
	frames.append([Game.frame, snappedf(Game.clock, 0.0001), snappedf(o.x, 0.0001), snappedf(o.y, 0.0001), snappedf(o.z, 0.0001),
		snappedf(q.x, 0.00001), snappedf(q.y, 0.00001), snappedf(q.z, 0.00001), snappedf(q.w, 0.00001), snappedf(cam.fov, 0.01),
		player.camcorder.active, lv])
	if Game.clock >= Game.duration:
		_done = true
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"seed": Game.run_seed, "fps": 30, "fields": ["frame", "t", "px", "py", "pz", "qx", "qy", "qz", "qw", "fov", "camcorder", "levels"], "frames": frames}))
		f.close()
