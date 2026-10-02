class_name TapeEvents
extends Node3D
## Things that exist only on tape (VISION: "the camera sees what you can't"; critiques 006 and
## 007, LEDGER L031). Everything here lives on render layer 11, which the player camera only
## draws while the camcorder is up (Player).
##
## The figure at the end of the hall: lift the camcorder while looking down a long, open view
## and sometimes the viewfinder shows a tall figure standing far away, facing you. To the naked
## eye there is nothing there, except the panel above that spot stutters. Lower the camera and
## it is gone; walk toward it and it is gone. Never more than a few times per run.

const LAYER_TAPE := 1 << 10
const MIN_DEPTH := 17.0
const FIRST_AFTER := 8.0
const COOLDOWN := 35.0
const MAX_SHOWS := 3

var space: Space
var player: Player
var figure: Node3D
var _mat: ShaderMaterial
var _rng: RandomNumberGenerator
var _shows := 0
var _next_ok := FIRST_AFTER
var _visible_until := -1.0
var _hide_t := -1.0


func _ready() -> void:
	_rng = Game.rng("tape:figure")
	if Game.opts.has("tape-always"):
		_next_ok = 0.0
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/tape_figure.gdshader")
	figure = _make_figure()
	figure.visible = false
	add_child(figure)


func _part(mesh: Mesh, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.layers = LAYER_TAPE
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.transform = Transform3D(Basis.from_euler(rot).scaled(scl), pos)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 4
	return c


## A person copied slightly wrong: a little too tall, forearms too long, neck a touch long,
## head a touch small. Facing +Z.
func _make_figure() -> Node3D:
	var root := Node3D.new()
	root.name = "tape_figure"
	for sx in [-1.0, 1.0]:
		root.add_child(_part(_capsule(0.075, 1.0), Vector3(0.1 * sx, 0.5, 0.0)))                       # legs
		root.add_child(_part(_capsule(0.05, 1.12), Vector3(0.27 * sx, 1.12, 0.02), Vector3(0, 0, 0.06 * sx)))   # arms, hands past the knees
	root.add_child(_part(_capsule(0.17, 0.78), Vector3(0, 1.33, 0), Vector3.ZERO, Vector3(1.08, 1.0, 0.62)))  # torso
	root.add_child(_part(_capsule(0.045, 0.26), Vector3(0, 1.79, 0.01)))                               # neck
	var head := SphereMesh.new()
	head.radius = 0.095
	head.height = 0.235
	root.add_child(_part(head, Vector3(0, 1.98, 0.015)))
	return root


func _process(delta: float) -> void:
	_mat.set_shader_parameter("time", Game.clock)
	if player == null or space == null:
		return
	var cam_on := player.camcorder.active
	if figure.visible and Game.opts.has("log-tape") and Game.frame % 30 == 0:
		print("[tape] visible at %s player %s cam_on=%s mask=%x vis_in_tree=%s" % [figure.global_position, player.global_position, cam_on, player.cam.cull_mask, figure.is_visible_in_tree()])
	if figure.visible:
		var d := Vector2(figure.global_position.x - player.global_position.x, figure.global_position.z - player.global_position.z).length()
		if d < 9.0:
			_hide(true)
		elif not cam_on:
			if _hide_t < 0.0:
				_hide_t = 0.25
			_hide_t -= delta
			if _hide_t <= 0.0:
				_hide(false)
		else:
			_hide_t = -1.0
			player.camcorder.degrade = 0.3
		return
	if not cam_on or Game.clock < _next_ok or _shows >= MAX_SHOWS or not player.camcorder.settled():
		return
	# Looking down a long open view?
	var yaw := player.yaw
	var depth := space.view_depth(player.global_position, yaw, 34.0)
	if depth < MIN_DEPTH:
		return
	if _rng.randf() > 0.5 and not Game.opts.has("tape-always"):
		_next_ok = Game.clock + 6.0   # not every time
		return
	# Stand under a lit panel, so it reads as a silhouette against the light.
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var p := Vector3.ZERO
	var dist := -1.0
	for d in [16.0, 18.0, 14.0, 20.0, 22.0, 12.5]:
		if d > depth - 2.0:
			continue
		var q: Vector3 = player.global_position + dir * d
		if not space.is_walkable(q):
			continue
		if space.has_method("fixture_near") and space.fixture_near(q, 1.6) == null:
			continue
		p = q
		dist = d
		break
	if dist < 0.0:
		_next_ok = Game.clock + 2.0
		return
	figure.global_position = Vector3(p.x, 0.0, p.z)
	figure.look_at(Vector3(player.global_position.x, 0.0, player.global_position.z), Vector3.UP, true)
	figure.visible = true
	_shows += 1
	space.attention_point = p + Vector3(0, 1.7, 0)
	space.attention_until = Game.clock + 4.0
	# The only thing the naked eye gets: the nearest panel stutters.
	if space.has_method("fixture_near"):
		var fx: Fixture = space.fixture_near(p, 4.0)
		if fx:
			fx.stutter()
	if Game.opts.has("log-tape"):
		print("[tape] figure shown at t=%.1f dist=%.1f" % [Game.clock, dist])


func _hide(glitch: bool) -> void:
	figure.visible = false
	_hide_t = -1.0
	_next_ok = Game.clock + COOLDOWN
	player.camcorder.degrade = 0.0
	if glitch:
		player.camcorder.glitch()
