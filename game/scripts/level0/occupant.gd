class_name Occupant
extends Node3D
## The Occupant (D035, M4): the building's own attempt at a person, a 2.35 m figure made of loose
## strips of Level 0's wallpaper (shaders/occupant_strips.gdshader) driven by the Meshy 7.1 rig and
## its nine animations (game/assets/entity/occupant_rigged.glb, anims/*.glb). It never moves
## smoothly where you can see it: it holds a pose, then a frame is skipped and it holds another
## (hold()), the way it exists in a recording.
## S06 (L156: "a tan mannequin" by eye, "a masking-tape stick figure" on tape) gives it looks per use
## (set_look): "paper" (the high door's peek), "silhouette" (a dark shape at the edge of sight),
## "tape" (a hole in the recording with a few strips of paper left on it), "shimmer" (all the naked
## eye gets of it when it hunts: the room bent where it stands) and "shadow" (an invisible body that
## only throws a shadow). Its forearms and neck are a little too long (a SkeletonModifier3D).

const MODEL := "res://assets/entity/occupant_rigged.glb"
const ANIM_DIR := "res://assets/entity/anims/"
const CLIPS := ["idle", "walk", "look", "twitch", "crouch", "crawl", "lunge", "run", "scream"]

static var _lib: AnimationLibrary
static var _model: PackedScene
static var _count := 0

var body: Node3D
var anim: AnimationPlayer
var mat: ShaderMaterial              # the paper strips (every look but shimmer)
var drop_mat: ShaderMaterial         # the hole in the recording (tape look, the paper's next pass)
var shim_mat: ShaderMaterial         # the bent picture (shimmer look)
var skel: Skeleton3D
var look := "paper"
var smear := 0.0
var _mi: MeshInstance3D
var _layers := 1
var _shadows := true
var _clip := ""
var _clip_t := 0.0


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
	if skel:
		skel.add_child(Proportions.new())
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/occupant_strips.gdshader")
	var paper := Level0Look.tex("wallpaper_v2_albedo")
	if paper:
		mat.set_shader_parameter("paper_tex", paper)
	drop_mat = ShaderMaterial.new()
	drop_mat.shader = load("res://shaders/occupant_dropout.gdshader")
	shim_mat = ShaderMaterial.new()
	shim_mat.shader = load("res://shaders/occupant_shimmer.gdshader")
	for m in body.find_children("*", "MeshInstance3D", true, false):
		_mi = m
		break
	_count += 1
	for m2 in [mat, drop_mat, shim_mat]:
		(m2 as ShaderMaterial).set_shader_parameter("seed", float(_count) * 1.37)   # each copy its own strips (deterministic)
	_prep(body)


func _prep(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.material_override = shim_mat if look == "shimmer" else mat
		if Game.opts.has("occ_plain"):
			var dm := StandardMaterial3D.new()
			dm.albedo_color = Color(1, 0, 0)
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			g.material_override = dm
		if look == "shadow":
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif look == "shimmer" or look == "tape" or not _shadows:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
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
	_shadows = on
	if body:
		_prep(body)


## One of "paper", "silhouette", "tape", "shimmer", "shadow" (see the class notes).
func set_look(kind: String) -> void:
	look = kind
	if mat == null:
		return
	mat.next_pass = null
	match kind:
		"paper":
			mat.set_shader_parameter("silhouette", 0.0)
			mat.set_shader_parameter("inflate", 0.0)
			smear = 0.0
		"silhouette":
			mat.set_shader_parameter("silhouette", 1.0)
			mat.set_shader_parameter("gap", 0.1)
			mat.set_shader_parameter("inflate", 0.0)
			smear = 0.0
		"tape":
			mat.set_shader_parameter("silhouette", 0.0)
			mat.set_shader_parameter("gap", 0.66)
			mat.set_shader_parameter("inflate", 0.028)
			drop_mat.set_shader_parameter("inflate", 0.008)
			mat.next_pass = drop_mat
			smear = 1.0
		"shimmer":
			smear = 0.35
			shim_mat.set_shader_parameter("inflate", 0.01)
		"shadow":
			mat.set_shader_parameter("silhouette", 0.0)
			mat.set_shader_parameter("gap", 0.32)
			mat.set_shader_parameter("inflate", 0.0)
			smear = 0.0
	if body:
		_prep(body)


## Plays a clip normally (it moves smoothly; only ever where nobody is looking).
func play(clip: String, speed: float = 1.0) -> void:
	if anim == null or not anim.has_animation("occ/" + clip):
		return
	anim.play("occ/" + clip)
	anim.speed_scale = speed
	_clip = clip


## Holds one frame of a clip: the figure frozen mid-move (a pose for a frame skip).
func hold(clip: String, t01: float) -> void:
	if anim == null or not anim.has_animation("occ/" + clip):
		return
	var a := anim.get_animation("occ/" + clip)
	anim.play("occ/" + clip)
	anim.seek(clampf(t01, 0.0, 1.0) * a.length, true)
	anim.speed_scale = 0.0
	_clip = clip
	_clip_t = t01


## The clip and moment last held (after-images copy it).
func held() -> Array:
	return [_clip, _clip_t]


func clip_length(clip: String) -> float:
	if anim == null or not anim.has_animation("occ/" + clip):
		return 0.0
	return anim.get_animation("occ/" + clip).length


## Per-frame look values (Game.clock drives everything, so Movie Maker captures are repeatable).
func shade(tape: float, tear: float, fade: float = 1.0, presence: float = 1.0) -> void:
	if mat == null:
		return
	var tb := Transform3D.IDENTITY
	if _mi and is_inside_tree():
		tb = global_transform.affine_inverse() * _mi.global_transform
	for m in [mat, drop_mat, shim_mat]:
		var sm := m as ShaderMaterial
		sm.set_shader_parameter("to_body", Projection(tb))
		sm.set_shader_parameter("from_body", Projection(tb.affine_inverse()))
		sm.set_shader_parameter("time", Game.clock)
		sm.set_shader_parameter("tape", tape)
		sm.set_shader_parameter("tear", tear)
		sm.set_shader_parameter("fade", fade)
		sm.set_shader_parameter("smear", smear)
	shim_mat.set_shader_parameter("presence", presence)


## Papered in the paper of the space it stands in (a hall behind a storeroom door has its own).
func set_paper(tint: Vector3, sat: float) -> void:
	if mat:
		mat.set_shader_parameter("paper_tint", tint)
		mat.set_shader_parameter("paper_sat", sat)


## World position of the head (for peeking and for attention).
func head_position() -> Vector3:
	if skel:
		var i := skel.find_bone("Head")
		if i >= 0:
			return skel.global_transform * skel.get_bone_global_pose(i).origin
	return global_position + Vector3(0, 2.2, 0)


## How much the arms are pulled down to hang at its sides (the standing clips' arms stood out
## like a mannequin's, L156), and how far the head is tipped over.
const HANG := {"idle": 0.85, "look": 0.75, "walk": 0.55, "scream": 0.0}


## A person copied slightly wrong (the S03 tape figure's proportions, on the Meshy rig): forearms
## too long with the hands their own size, a neck too long under a head a touch small, arms that
## hang straight down when it stands, the head tipped to one side. Runs after the animation every
## frame, so every clip and held pose has it.
class Proportions:
	extends SkeletonModifier3D
	const ARM := 1.22
	const NECK := 1.3
	var _ids := {}

	func _bone(sk: Skeleton3D, nm: String) -> int:
		if not _ids.has(nm):
			_ids[nm] = sk.find_bone(nm)
		return _ids[nm]

	## Turns bone b (skeleton space) so the direction to its child c moves toward `want` by w.
	func _aim(sk: Skeleton3D, b: int, c: int, want: Vector3, w: float) -> void:
		if b < 0 or c < 0 or w <= 0.0:
			return
		var gb := sk.get_bone_global_pose(b)
		var gc := sk.get_bone_global_pose(c)
		var now := gc.origin - gb.origin
		if now.length() < 0.001:
			return
		var q := Quaternion(now.normalized(), want.normalized())
		q = Quaternion.IDENTITY.slerp(q, w)
		sk.set_bone_global_pose(b, Transform3D(Basis(q) * gb.basis, gb.origin))

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		var occ := sk.get_parent()
		while occ and not (occ is Occupant):
			occ = occ.get_parent()
		var hang := 0.0
		if occ:
			hang = float(Occupant.HANG.get((occ as Occupant)._clip, 0.0))
		for side in ["Left", "Right"]:
			var fa := _bone(sk, side + "ForeArm")
			var hd := _bone(sk, side + "Hand")
			if fa >= 0:
				sk.set_bone_pose_scale(fa, Vector3(1.0, ARM, 1.0))
			if hd >= 0:
				sk.set_bone_pose_scale(hd, Vector3(1.0, 1.0 / ARM, 1.0))
			# Character's left is +x, it faces +z (the Meshy rig).
			var sx := 1.0 if side == "Left" else -1.0
			_aim(sk, _bone(sk, side + "Arm"), fa, Vector3(0.1 * sx, -1.0, 0.06), hang)
			_aim(sk, fa, hd, Vector3(0.03 * sx, -1.0, 0.12), hang)
		var nk := _bone(sk, "neck")
		var head := _bone(sk, "Head")
		if nk >= 0:
			sk.set_bone_pose_scale(nk, Vector3(1.0, NECK, 1.0))
		if head >= 0:
			sk.set_bone_pose_scale(head, Vector3(0.92, 0.92 / NECK, 0.92))
			if hang > 0.0:
				sk.set_bone_pose_rotation(head, sk.get_bone_pose_rotation(head) * Quaternion(Vector3(0, 0, 1), 0.32 * hang))
