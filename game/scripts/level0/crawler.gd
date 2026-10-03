class_name Crawler
extends Node3D
## The Crawler (D052, the Monster Lab's pick for depth 1): an enormous pale person-shaped thing with
## waxy mannequin skin, too big for the corridors, crawling on its hands and knees with its eyes shut.
## Meshy 7.1 model and clips (pipeline/meshes/build_crawler.py). Only one of Meshy's clips is a true
## forward crawl, so the clips are named for what the hunt asks of them (CLIP_MAP), the hips' travel
## is taken out of every clip (the hunt moves the body), and the speed of the crawl follows how fast
## the body is really moving, so its hands never slide.

const MODEL := "res://assets/crawler/crawler_rigged.glb"
const ANIM_DIR := "res://assets/crawler/anims/"
const FILES := ["crawl_slow", "crawl_fast", "crawl_idle", "grab", "look", "crouch_walk"]
## What the hunt asks for -> [clip file, play backwards]
const CLIP_MAP := {
	"walk": ["crawl_slow", false], "run": ["crawl_slow", false], "idle": ["crawl_idle", false],
	"look": ["crawl_idle", false], "scream": ["crawl_fast", true], "lunge": ["crawl_fast", true],
	"crouch": ["crawl_idle", false], "grab": ["grab", false], "rear": ["look", false],
}
const SCALE := 2.8
const STRIDE := 1.3       # meters a second the crawl covers at speed 1, at SCALE

static var _lib: AnimationLibrary
static var _model: PackedScene

var body: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var width := 1.0           # 1 = its own width; less when it squeezes through a doorway
var _clip := ""
var _clip_t := 0.0
var _layers := 1
var _eyes: Array[MeshInstance3D] = []


static func available() -> bool:
	return ResourceLoader.exists(MODEL)


static func _library() -> AnimationLibrary:
	if _lib == null:
		_lib = AnimationLibrary.new()
		for c in FILES:
			var p: String = ANIM_DIR + c + ".glb"
			if not ResourceLoader.exists(p):
				continue
			var inst := (load(p) as PackedScene).instantiate()
			var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ap and ap.get_animation_list().size() > 0:
				var a := ap.get_animation(ap.get_animation_list()[0]).duplicate(true) as Animation
				a.loop_mode = Animation.LOOP_LINEAR if c != "grab" else Animation.LOOP_NONE
				_pin_hips(a)
				_lib.add_animation(StringName(c), a)
			inst.free()
	return _lib


## The hips keep their height and lose their travel (Meshy's library clips walk off on their own).
static func _pin_hips(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not String(a.track_get_path(t)).ends_with("Hips"):
			continue
		var n := a.track_get_key_count(t)
		if n == 0:
			continue
		var p0: Vector3 = a.track_get_key_value(t, 0)
		for k in n:
			var v: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, Vector3(p0.x, v.y, p0.z))


func _init() -> void:
	name = "crawler"
	if _model == null and available():
		_model = load(MODEL)
	if _model == null:
		return
	body = _model.instantiate() as Node3D
	add_child(body)
	body.scale = Vector3.ONE * SCALE
	skel = body.find_child("Skeleton3D", true, false) as Skeleton3D
	anim = body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		anim.add_animation_library(&"crw", _library())
	if skel:
		look = HeadLook.new()
		skel.add_child(look)
	_skin(body)


var look: HeadLook


## Turns its neck and head toward a point (the lens, when it has you). w 0..1.
func look_at_point(p: Vector3, w: float) -> void:
	if look:
		look.target = p
		look.weight = w


## Its crawl keeps its face to the floor; this lifts the neck and head toward a target, on top of
## whatever clip plays (SkeletonModifier3D runs after the animation, S06 gotcha).
class HeadLook:
	extends SkeletonModifier3D
	var target := Vector3.INF
	var weight := 0.0
	var _axis := {}

	func _process_modification() -> void:
		if weight <= 0.001 or target == Vector3.INF:
			return
		var sk := get_skeleton()
		if sk == null:
			return
		var tl := sk.global_transform.affine_inverse() * target
		for spec in [["neck", 0.45], ["Head", 0.75]]:
			var b := sk.find_bone(spec[0])
			if b < 0:
				continue
			if not _axis.has(b):
				# the bone's own axis that pointed the way the face does in the rest pose (+z)
				_axis[b] = (sk.get_bone_global_rest(b).basis.inverse() * Vector3(0, 0, 1)).normalized()
			var gp := sk.get_bone_global_pose(b)
			var fwd := (gp.basis * (_axis[b] as Vector3)).normalized()
			var want := (tl - gp.origin).normalized()
			if fwd.dot(want) > 0.9999:
				continue
			var q := Quaternion(fwd, want)
			q = Quaternion.IDENTITY.slerp(q, clampf(weight * float(spec[1]), 0.0, 1.0))
			sk.set_bone_global_pose(b, Transform3D(Basis(q) * gp.basis, gp.origin))


## Waxy, dry, a little sheen where the light grazes it: an old mannequin grown huge.
func _skin(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.get_surface_override_material_count():
			var src := mi.mesh.surface_get_material(s)
			if src is StandardMaterial3D:
				var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.roughness = 0.74
				m.rim_enabled = true
				m.rim = 0.12
				m.rim_tint = 0.7
				m.subsurf_scatter_enabled = true
				m.subsurf_scatter_strength = 0.25
				mi.set_surface_override_material(s, m)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.extra_cull_margin = 2.0
		mi.layers = _layers
	for c in n.get_children():
		_skin(c)


func set_layers(bits: int) -> void:
	_layers = bits
	_set_layers(body, bits)


func _set_layers(n: Node, bits: int) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).layers = bits
	for c in n.get_children():
		_set_layers(c, bits)


func set_shadows(mode: int) -> void:
	_set_shadow(body, mode)


func _set_shadow(n: Node, mode: int) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = mode
	for c in n.get_children():
		_set_shadow(c, mode)


func _anim_name(clip: String) -> String:
	var m: Array = CLIP_MAP.get(clip, [clip, false])
	return "crw/" + String(m[0])


## Plays a clip; speed < 0 plays it backwards (the backward scramble run forward is the lunge).
func play(clip: String, speed: float = 1.0) -> void:
	var nm := _anim_name(clip)
	if anim == null or not anim.has_animation(nm):
		return
	var back: bool = CLIP_MAP.get(clip, [clip, false])[1]
	if anim.current_animation != nm:
		anim.play(nm)
	anim.speed_scale = -absf(speed) if back else speed
	_clip = clip


func set_speed(speed: float) -> void:
	if anim:
		var back: bool = CLIP_MAP.get(_clip, [_clip, false])[1]
		anim.speed_scale = -absf(speed) if back else speed


func hold(clip: String, t01: float) -> void:
	var nm := _anim_name(clip)
	if anim == null or not anim.has_animation(nm):
		return
	var a := anim.get_animation(nm)
	anim.play(nm)
	anim.seek(clampf(t01, 0.0, 1.0) * a.length, true)
	anim.speed_scale = 0.0
	_clip = clip
	_clip_t = t01


func held() -> Array:
	return [_clip, _clip_t]


## Where in its clip the body is now (0..1).
func phase() -> float:
	if anim == null or anim.current_animation == "":
		return 0.0
	var ln := anim.current_animation_length
	return anim.current_animation_position / ln if ln > 0.0 else 0.0


func clip_length(clip: String) -> float:
	var nm := _anim_name(clip)
	if anim == null or not anim.has_animation(nm):
		return 0.0
	return anim.get_animation(nm).length


## Squeezing: narrower and a little lower where the walls close in.
func set_width(w: float) -> void:
	width = w
	if body:
		body.scale = Vector3(SCALE * w, SCALE * (0.86 + 0.14 * w), SCALE)


func head_position() -> Vector3:
	if skel:
		var i := skel.find_bone("Head")
		if i >= 0:
			return skel.global_transform * skel.get_bone_global_pose(i).origin
	return global_position + Vector3(0, 1.5, 0)


## The end of a catch: its eyes open, and there is nothing behind them.
func open_eyes(on: bool) -> void:
	if _eyes.is_empty() and on and skel:
		var i := skel.find_bone("Head")
		if i < 0:
			return
		var ba := BoneAttachment3D.new()
		ba.bone_name = "Head"
		skel.add_child(ba)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0, 0, 0)
		m.roughness = 0.05
		m.metallic_specular = 1.0
		for sx in [-1.0, 1.0]:
			var e := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.016
			sm.height = 0.022
			e.mesh = sm
			e.material_override = m
			e.position = Vector3(sx * 0.032, 0.085, 0.085)
			e.layers = _layers
			ba.add_child(e)
			_eyes.append(e)
	for e in _eyes:
		e.visible = on
