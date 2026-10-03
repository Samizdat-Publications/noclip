class_name Occupant
extends Node3D
## The Occupant (D035, M4): the building's own attempt at a person, a 2.35 m figure made of loose
## strips of Level 0's wallpaper (shaders/occupant_strips.gdshader) driven by the Meshy 7.1 rig and
## its nine animations (game/assets/entity/occupant_rigged.glb, anims/*.glb). It never moves
## smoothly where you can see it: it holds a pose, then a frame is skipped and it holds another
## (hold()), the way it exists in a recording. Used by the tape encounters, the watchers and, later,
## the hunt.

const MODEL := "res://assets/entity/occupant_rigged.glb"
const ANIM_DIR := "res://assets/entity/anims/"
const CLIPS := ["idle", "walk", "look", "twitch", "crouch", "crawl", "lunge", "run", "scream"]

static var _lib: AnimationLibrary
static var _model: PackedScene
static var _count := 0

var body: Node3D
var anim: AnimationPlayer
var mat: ShaderMaterial
var skel: Skeleton3D
var _mi: MeshInstance3D
var _layers := 1


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
				a.loop_mode = Animation.LOOP_LINEAR
				_lib.add_animation(StringName(c), a)
			inst.free()
	return _lib


func _init() -> void:
	name = "occupant"
	if _model == null and available():
		_model = load(MODEL)
	if _model == null:
		return
	body = _model.instantiate() as Node3D
	add_child(body)
	skel = body.find_child("Skeleton3D", true, false) as Skeleton3D
	anim = body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		anim.add_animation_library(&"occ", _library())
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/occupant_strips.gdshader")
	var paper := Level0Look.tex("wallpaper_v2_albedo")
	if paper:
		mat.set_shader_parameter("paper_tex", paper)
	_mi = body.find_child("*", true, false) as MeshInstance3D
	for m in body.find_children("*", "MeshInstance3D", true, false):
		_mi = m
		break
	_count += 1
	mat.set_shader_parameter("seed", float(_count) * 1.37)   # each copy its own strips (deterministic)
	_prep(body)


func _prep(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.material_override = mat
		if Game.opts.has("occ_plain"):
			var dm := StandardMaterial3D.new()
			dm.albedo_color = Color(1, 0, 0)
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			g.material_override = dm
			print("[occ] mesh %s aabb=%s skel=%s" % [g.name, g.get_aabb(), (g as MeshInstance3D).skeleton if g is MeshInstance3D else ""])
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		g.extra_cull_margin = 1.5
		g.layers = _layers
	for c in n.get_children():
		_prep(c)


## Render layers for every mesh (tape-only, eye-only, the hall's layer...).
func set_layers(bits: int) -> void:
	_layers = bits
	if body:
		_prep(body)


func set_shadows(on: bool) -> void:
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Plays a clip normally (it moves smoothly; only ever where nobody is looking).
func play(clip: String, speed: float = 1.0) -> void:
	if anim == null or not anim.has_animation("occ/" + clip):
		return
	anim.play("occ/" + clip)
	anim.speed_scale = speed


## Holds one frame of a clip: the figure frozen mid-move (a pose for a frame skip).
func hold(clip: String, t01: float) -> void:
	if anim == null or not anim.has_animation("occ/" + clip):
		return
	var a := anim.get_animation("occ/" + clip)
	anim.play("occ/" + clip)
	anim.seek(clampf(t01, 0.0, 1.0) * a.length, true)
	anim.speed_scale = 0.0


func clip_length(clip: String) -> float:
	if anim == null or not anim.has_animation("occ/" + clip):
		return 0.0
	return anim.get_animation("occ/" + clip).length


## Per-frame look values (Game.clock drives everything, so Movie Maker captures are repeatable).
func shade(tape: float, tear: float, fade: float = 1.0) -> void:
	if mat == null:
		return
	if _mi and is_inside_tree():
		var tb := global_transform.affine_inverse() * _mi.global_transform
		mat.set_shader_parameter("to_body", Projection(tb))
		mat.set_shader_parameter("from_body", Projection(tb.affine_inverse()))
	mat.set_shader_parameter("time", Game.clock)
	mat.set_shader_parameter("tape", tape)
	mat.set_shader_parameter("tear", tear)
	mat.set_shader_parameter("fade", fade)


## World position of the head (for peeking and for attention).
func head_position() -> Vector3:
	if skel:
		var i := skel.find_bone("Head")
		if i >= 0:
			return skel.global_transform * skel.get_bone_global_pose(i).origin
	return global_position + Vector3(0, 2.2, 0)
