class_name HaldenBody
extends Node3D
## A Halden Duplicating field technician (VISION "Halden Duplicating"; Meshy 7.1 model, S06): white
## disposable coverall, hood, respirator with pink filters. Used dead for now: lying on its back at
## the end of its "death" clip. Living field teams (M4.5) will use the same model and clips.

const MODEL := "res://assets/halden/tech_rigged.glb"
const ANIM_DIR := "res://assets/halden/anims/"
const CLIPS := ["idle", "walk", "look", "kneel", "backaway", "warn", "film", "death", "crawl"]

static var _lib: AnimationLibrary
static var _model: PackedScene

var body: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D


static func available() -> bool:
	return ResourceLoader.exists(MODEL)


static func _library() -> AnimationLibrary:
	if _lib == null:
		_lib = AnimationLibrary.new()
		for c in CLIPS:
			var p: String = ANIM_DIR + c + ".glb"
			if not ResourceLoader.exists(p):
				continue
			var inst := (load(p) as PackedScene).instantiate()
			var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ap and ap.get_animation_list().size() > 0:
				var a := ap.get_animation(ap.get_animation_list()[0]).duplicate() as Animation
				a.loop_mode = Animation.LOOP_NONE if c == "death" else Animation.LOOP_LINEAR
				_lib.add_animation(StringName(c), a)
			inst.free()
	return _lib


func _init() -> void:
	name = "halden_tech"
	if _model == null and available():
		_model = load(MODEL)
	if _model == null:
		return
	body = _model.instantiate() as Node3D
	add_child(body)
	skel = body.find_child("Skeleton3D", true, false) as Skeleton3D
	anim = body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		anim.add_animation_library(&"tech", _library())
	for g in body.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		(g as GeometryInstance3D).extra_cull_margin = 2.0
	if skel:
		arms = Arms.new()
		skel.add_child(arms)


var arms: Arms


## Where a body lying on its back keeps its arms (the death clip ends with them spread straight out,
## which reads as a mannequin): "side" along the body, "trail" stretched past the head as it is
## pulled by the feet, "" as the clip has them.
class Arms:
	extends SkeletonModifier3D
	var mode := ""
	var _ids := {}

	func _bone(sk: Skeleton3D, nm: String) -> int:
		if not _ids.has(nm):
			_ids[nm] = sk.find_bone(nm)
		return _ids[nm]

	func _aim(sk: Skeleton3D, b: int, c: int, want: Vector3) -> void:
		if b < 0 or c < 0:
			return
		var gb := sk.get_bone_global_pose(b)
		var gc := sk.get_bone_global_pose(c)
		var now := gc.origin - gb.origin
		if now.length() < 0.001:
			return
		sk.set_bone_global_pose(b, Transform3D(Basis(Quaternion(now.normalized(), want.normalized())) * gb.basis, gb.origin))

	func _process_modification() -> void:
		if mode == "":
			return
		var sk := get_skeleton()
		var hips := sk.get_bone_global_pose(_bone(sk, "Hips")).origin
		var head := sk.get_bone_global_pose(_bone(sk, "Head")).origin
		var axis := (head - hips).normalized()
		var ls := sk.get_bone_global_pose(_bone(sk, "LeftShoulder")).origin
		var rs := sk.get_bone_global_pose(_bone(sk, "RightShoulder")).origin
		var lat := (ls - rs).normalized()
		for side in ["Left", "Right"]:
			var out := lat if side == "Left" else -lat
			var want := (-axis * 0.92 + out * 0.3) if mode == "side" else (axis * 0.95 + out * 0.22)
			var want2 := (-axis * 0.8 + out * 0.15) if mode == "side" else (axis + out * 0.1)
			_aim(sk, _bone(sk, side + "Arm"), _bone(sk, side + "ForeArm"), want)
			_aim(sk, _bone(sk, side + "ForeArm"), _bone(sk, side + "Hand"), want2)


func hold(clip: String, t01: float) -> void:
	if anim == null or not anim.has_animation("tech/" + clip):
		return
	var a := anim.get_animation("tech/" + clip)
	anim.play("tech/" + clip)
	anim.seek(clampf(t01, 0.0, 1.0) * a.length, true)
	anim.speed_scale = 0.0


func play(clip: String, speed: float = 1.0) -> void:
	if anim == null or not anim.has_animation("tech/" + clip):
		return
	anim.play("tech/" + clip)
	anim.speed_scale = speed


## World position of a bone (by name), or the node's own position.
func bone_world(bone: String) -> Vector3:
	if skel:
		var i := skel.find_bone(bone)
		if i >= 0:
			return skel.global_transform * skel.get_bone_global_pose(i).origin
	return global_position
