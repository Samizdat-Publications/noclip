class_name Portal
extends Node3D
## A doorway that shows another place and takes you there (VISION non-euclidean toolkit, M2b,
## D036). This node sits at the middle of the opening at floor level; its +X axis points the way
## you walk through, +Y up. `target` is the frame you arrive in (same convention). A second
## camera, placed where your eye would be on the far side (target * this^-1 * eye), renders that
## place into a texture; a thin box filling the opening shows it at screen position, so the
## doorway looks straight into the other place. Crossing is handled by the Space (it moves the
## player by mapping()).
##
## The portal render is scene-linear HDR (no exposure, no tonemap, no glow): the main view then
## exposes, tonemaps and grades it together with everything else, so the two match.

const SURFACE_LAYER := 1 << 13    # render layer 14: portal surfaces; portal cameras never draw them
const SHADER := preload("res://shaders/portal_view.gdshader")

var target := Transform3D.IDENTITY
var opening := Vector2(1.16, 2.08)   # width, height of the clear opening
var depth := 0.5                     # how far the surface box reaches past the plane
var show_layers := 1                 # the far side's space (render layers its camera may draw)
var hide_layers := 0                 # layers the far side never shows (the near space)
var main_cam: Camera3D               # the player's camera
var range_m := 32.0                  # beyond this the far side is not rendered

var vp: SubViewport
var cam: Camera3D
var surface: MeshInstance3D
var active := false
var _env: Environment
var _attr: CameraAttributesPractical
var _src_env: Environment


func setup(p_main_cam: Camera3D, src_env: Environment) -> void:
	main_cam = p_main_cam
	_src_env = src_env
	vp = SubViewport.new()
	vp.name = "view"
	vp.world_3d = get_viewport().world_3d
	vp.use_hdr_2d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.positional_shadow_atlas_size = get_viewport().positional_shadow_atlas_size
	vp.positional_shadow_atlas_16_bits = get_viewport().positional_shadow_atlas_16_bits
	vp.use_taa = get_viewport().use_taa
	vp.screen_space_aa = get_viewport().screen_space_aa
	vp.msaa_3d = get_viewport().msaa_3d
	vp.audio_listener_enable_3d = false
	add_child(vp)
	cam = Camera3D.new()
	cam.name = "far_eye"
	_env = src_env.duplicate() if src_env else Environment.new()
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 1.0
	_env.glow_enabled = false
	_env.adjustment_enabled = false
	cam.environment = _env
	_attr = CameraAttributesPractical.new()
	_attr.auto_exposure_enabled = false
	_attr.exposure_multiplier = 1.0
	cam.attributes = _attr
	vp.add_child(cam)
	cam.current = true
	surface = MeshInstance3D.new()
	surface.name = "surface"
	var bm := BoxMesh.new()
	bm.size = Vector3(depth + 0.04, opening.y, opening.x)
	surface.mesh = bm
	surface.position = Vector3(depth * 0.5 - 0.02, opening.y * 0.5, 0.0)
	surface.layers = SURFACE_LAYER
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("view", vp.get_texture())
	surface.material_override = m
	add_child(surface)


## Where a point or frame on this side lands on the far side.
func mapping() -> Transform3D:
	return target * global_transform.affine_inverse()


## Position in this portal's frame (x: distance past the plane, z: across, y: up).
func local_of(p: Vector3) -> Vector3:
	return global_transform.affine_inverse() * p


## True if the segment a -> b (an eye point between two physics ticks) passes through the opening
## in the walking direction.
func crossed(a: Vector3, b: Vector3) -> bool:
	var la := local_of(a)
	var lb := local_of(b)
	if not (la.x < 0.0 and lb.x >= 0.0):
		return false
	var t := -la.x / maxf(lb.x - la.x, 1e-6)
	var q := la.lerp(lb, t)
	return absf(q.z) <= opening.x * 0.5 + 0.05 and q.y > -0.5 and q.y < opening.y + 0.6


func _ready() -> void:
	process_priority = 50     # after the player has placed its camera this frame


func _process(_delta: float) -> void:
	if cam == null or main_cam == null or not is_instance_valid(main_cam):
		return
	var want := _wanted()
	if want != active:
		active = want
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		return
	var sz := Vector2i(get_viewport().get_visible_rect().size)
	var sc := float(Game.opts.get("portal_scale", "1.0"))
	var want_sz := Vector2i(maxi(int(sz.x * sc), 64), maxi(int(sz.y * sc), 64))
	if vp.size != want_sz:
		vp.size = want_sz
	cam.global_transform = mapping() * main_cam.global_transform
	cam.fov = main_cam.fov
	cam.near = main_cam.near
	cam.far = main_cam.far
	# The far side shows its own space, never another portal's surface, and keeps the
	# camcorder's tape/eye rule.
	cam.cull_mask = (main_cam.cull_mask & ~(SURFACE_LAYER | hide_layers)) | show_layers
	if _src_env:
		_env.volumetric_fog_temporal_reprojection_enabled = _src_env.volumetric_fog_temporal_reprojection_enabled


## Rendered only while the opening could be on screen, from the near side, within range.
func _wanted() -> bool:
	var e := main_cam.global_position
	var l := local_of(e)
	if l.x > 0.6 or l.length() > range_m:
		return false
	if l.x > -0.8:
		return true     # standing in the doorway: always
	var corners: Array[Vector3] = []
	for sx in [-0.1, depth]:
		for sz in [-1.0, 1.0]:
			for sy in [0.0, 1.0]:
				corners.append(global_transform * Vector3(sx, opening.y * sy, sz * opening.x * 0.5))
	for pl in main_cam.get_frustum():
		var outside := true
		for c in corners:
			if not pl.is_point_over(c):
				outside = false
				break
		if outside:
			return false
	return true
