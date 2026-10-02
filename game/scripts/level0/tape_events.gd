class_name TapeEvents
extends Node3D
## Things that exist only on tape (VISION: "the camera sees what you can't"; critiques 006 and
## 007, LEDGER L031). Everything here lives on render layer 11, which the player camera only
## draws while the camcorder is up (Player).
##
## The figure at the end of the hall (D018, reworked in S03 as D021 after critique 008 called it
## a stiff mannequin): lift the camcorder while looking down a long, open view and sometimes the
## viewfinder shows a person standing far away under a light, off to one side, facing you. To
## the naked eye there is nothing there, except the panel above it stutters. It does not walk.
## It stutters from one pose to the next like a frame skip. Lower the camera and look again,
## and it is standing a little closer. Walk toward it, or look too many times, and it is gone,
## and the light it stood under goes out.

const LAYER_TAPE := 1 << 10
## Render layer 12: things only the naked eye sees (the wall over a seam, D022).
const LAYER_EYE := 1 << 11
const MIN_DEPTH := 17.0
const FIRST_AFTER := 8.0
const COOLDOWN := 40.0
const MAX_ENCOUNTERS := 3
const RELOOK_WINDOW := 9.0      # seconds you have to raise the camera again for it to come closer
const STEP_CLOSER := 3.6
const MESH := "res://assets/props/tape/figure_tape.glb"

enum S { IDLE, SHOWN, HIDDEN }

var space: Space
var player: Player
var figure: Node3D
var state := S.IDLE
var _mat: ShaderMaterial
var _rng: RandomNumberGenerator
var _encounters := 0
var _approaches := 0
var _next_ok := FIRST_AFTER
var _hidden_at := -1.0
var _hide_t := -1.0
var _pose_t := 0.0
var _pose := 0
var _tear := 0.0
var _skel: Skeleton3D
var _bones := {}          # stem -> bone index
var _base := {}           # bone index -> base local rotation (Quaternion)
var _point := {}          # bone index -> local rotation with one long arm raised, pointing
var _side := 1.0
var _light_fx: Fixture
var _final := false
var _final_t := 0.0
var _drop: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _drone: AudioStreamPlayer


func _ready() -> void:
	_rng = Game.rng("tape:figure")
	if Game.opts.has("tape-always"):
		_next_ok = 0.0
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/tape_figure.gdshader")
	figure = _make_figure()
	figure.visible = false
	add_child(figure)
	# Heard through the camcorder's own speaker (only while it records).
	_drop = _ui_player("tape_dropout_%02d", 3, -14.0)
	_breath = _ui_player("figure_breath_rev_%02d", 2, -16.0)
	_drone = AudioStreamPlayer.new()
	var dp := "res://assets/audio/level0/drone_dread_loop.wav"
	if ResourceLoader.exists(dp):
		var ds := load(dp) as AudioStreamWAV
		if ds:
			ds.loop_mode = AudioStreamWAV.LOOP_FORWARD
			ds.loop_end = int(ds.get_length() * ds.mix_rate)
		_drone.stream = ds
	_drone.bus = &"Master"
	_drone.volume_db = -80.0
	add_child(_drone)


## The player just walked through a seam.
func seam_cross() -> void:
	if (_drop.stream as AudioStreamRandomizer).streams_count > 0:
		_drop.volume_db = -8.0
		_drop.play()
		get_tree().create_timer(0.3).timeout.connect(func() -> void: _drop.volume_db = -14.0)
	Game.fear = maxf(Game.fear, 0.3)


func _ui_player(pattern: String, n: int, db: float) -> AudioStreamPlayer:
	var rz := AudioStreamRandomizer.new()
	rz.random_pitch = 1.04
	for i in n:
		var p := "res://assets/audio/level0/" + (pattern % (i + 1)) + ".wav"
		if ResourceLoader.exists(p):
			rz.add_stream(-1, load(p))
	var pl := AudioStreamPlayer.new()
	pl.stream = rz
	pl.bus = &"UI"
	pl.volume_db = db
	add_child(pl)
	return pl


# ------------------------------------------------------------------ the body

func _make_figure() -> Node3D:
	var root := Node3D.new()
	root.name = "tape_figure"
	if not ResourceLoader.exists(MESH):
		return root
	var inst := (load(MESH) as PackedScene).instantiate() as Node3D
	root.add_child(inst)
	_prep(inst)
	if _skel:
		_pose_body()
	return root


func _prep(n: Node) -> void:
	if n is Skeleton3D and _skel == null:
		_skel = n
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.material_override = _mat
		g.layers = LAYER_TAPE
		if Game.opts.has("tape-debug"):
			var dm := StandardMaterial3D.new()
			dm.albedo_color = Color(1, 0, 0)
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			g.material_override = dm
			g.layers = 1
			print("[tape] mesh %s aabb=%s skin=%s" % [g.name, g.get_aabb(), (g as MeshInstance3D).skin if g is MeshInstance3D else null])
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		g.extra_cull_margin = 1.0
	for c in n.get_children():
		_prep(c)


## Bone index by name stem ("upperarm_l" finds "upperarm_l_024").
func _bone(stem: String) -> int:
	if _bones.has(stem):
		return _bones[stem]
	var found := -1
	for i in _skel.get_bone_count():
		var nm := _skel.get_bone_name(i).to_lower()
		if nm == stem or (nm.begins_with(stem + "_") and nm.substr(stem.length() + 1).is_valid_int()):
			found = i
			break
	_bones[stem] = found
	return found


## Turn a bone (in skeleton space) so the direction to its child points along `want`.
func _aim(stem: String, child_stem: String, want: Vector3) -> void:
	var b := _bone(stem)
	var c := _bone(child_stem)
	if b < 0 or c < 0:
		return
	var gb := _skel.get_bone_global_pose(b)
	var gc := _skel.get_bone_global_pose(c)
	var now := (gc.origin - gb.origin).normalized()
	if now.length() < 0.5:
		return
	var q := Quaternion(now, want.normalized())
	_skel.set_bone_global_pose(b, Transform3D(Basis(q) * gb.basis, gb.origin))


## A person copied slightly wrong: arms hanging too long, neck a touch long, head a touch small,
## shoulders slightly uneven.
func _pose_body() -> void:
	_skel.reset_bone_poses()
	var left_x := signf(_skel.get_bone_global_pose(_bone("upperarm_l")).origin.x) if _bone("upperarm_l") >= 0 else 1.0
	for s in [["l", left_x], ["r", -left_x]]:
		var side: String = s[0]
		var sx: float = s[1]
		_aim("upperarm_" + side, "lowerarm_" + side, Vector3(0.1 * sx, -1.0, 0.02))
		_aim("lowerarm_" + side, "hand_" + side, Vector3(0.05 * sx, -1.0, 0.06))
		_aim("hand_" + side, "middle_01_" + side, Vector3(0.0, -1.0, 0.02))
		# Forearms too long: stretch along the bone, keep the hand its own size.
		var la := _bone("lowerarm_" + side)
		if la >= 0:
			_skel.set_bone_pose_scale(la, Vector3(1.0, 1.24, 1.0))
		var hd := _bone("hand_" + side)
		if hd >= 0:
			_skel.set_bone_pose_scale(hd, Vector3(1.0, 1.0 / 1.24, 1.0))
	var nk := _bone("neck")
	if nk >= 0:
		_skel.set_bone_pose_scale(nk, Vector3(1.0, 1.28, 1.0))
	var head := _bone("head")
	if head >= 0:
		_skel.set_bone_pose_scale(head, Vector3(0.93, 0.93 / 1.28, 0.93))
	var sh := _bone("shoulder_r" if left_x > 0.0 else "shoulder_l")
	if sh >= 0:
		_skel.set_bone_pose_rotation(sh, _skel.get_bone_pose_rotation(sh) * Quaternion(Vector3(0, 0, 1), 0.07))
	for stem in ["head", "neck", "spine_03", "spine_02", "upperarm_l", "upperarm_r", "lowerarm_r", "lowerarm_l"]:
		var i := _bone(stem)
		if i >= 0:
			_base[i] = _skel.get_bone_pose_rotation(i)
	# One arm raised straight at you, too long, the hand hanging (a pose for the stutter).
	var arm := "r" if left_x > 0.0 else "l"
	_aim("upperarm_" + arm, "lowerarm_" + arm, Vector3(-0.12 * left_x, 0.12, 1.0))
	_aim("lowerarm_" + arm, "hand_" + arm, Vector3(-0.05 * left_x, 0.02, 1.0))
	for stem in ["upperarm_" + arm, "lowerarm_" + arm]:
		var i := _bone(stem)
		if i >= 0:
			_point[i] = _skel.get_bone_pose_rotation(i)
			_skel.set_bone_pose_rotation(i, _base[i])


## Four held poses; the figure jumps between them with no motion in between (a frame skip).
const POSES := [
	{"head": Vector3(0.10, 0.0, 0.16), "neck": Vector3(0.05, 0.0, 0.05), "spine_03": Vector3(0.0, 0.0, 0.0)},
	{"head": Vector3(0.0, 0.28, -0.12), "neck": Vector3(0.0, 0.1, -0.04), "spine_03": Vector3(0.03, 0.04, 0.03)},
	{"head": Vector3(0.32, 0.0, 0.05), "neck": Vector3(0.12, 0.0, 0.0), "spine_03": Vector3(0.08, 0.0, 0.0)},
	{"head": Vector3(-0.05, -0.1, 0.42), "neck": Vector3(0.0, 0.0, 0.14), "spine_03": Vector3(0.0, -0.05, -0.04)},
	# Turned away, the head twisted all the way round to keep facing you.
	{"turn": PI, "head": Vector3(0.0, PI * 0.92, 0.1), "neck": Vector3(0.0, 0.25, 0.0)},
	# One arm raised, pointing at you.
	{"point": true, "head": Vector3(0.18, 0.0, -0.1), "spine_03": Vector3(-0.04, 0.0, 0.0)},
]


func _apply_pose(k: int, breath: float) -> void:
	if _skel == null:
		return
	var p: Dictionary = POSES[k]
	for i in _base:
		_skel.set_bone_pose_rotation(i, _base[i])
	if p.get("point", false):
		for i in _point:
			_skel.set_bone_pose_rotation(i, _point[i])
	var body: Node3D = figure.get_child(0) as Node3D if figure and figure.get_child_count() > 0 else null
	if body:
		body.rotation.y = float(p.get("turn", 0.0))
	for stem in p:
		if stem == "point" or stem == "turn":
			continue
		var i := _bone(stem)
		if i < 0 or not _base.has(i):
			continue
		var e: Vector3 = p[stem]
		if stem == "spine_03":
			e.x += breath
		_skel.set_bone_pose_rotation(i, (_base[i] as Quaternion) * Quaternion.from_euler(e))


# ------------------------------------------------------------------ behavior

func _process(delta: float) -> void:
	_mat.set_shader_parameter("time", Game.clock)
	# While it is out there, the hum around you fades and a low drone comes up (M3, D026).
	var present := state != S.IDLE
	Game.duck_target = 0.85 if state == S.SHOWN else (0.5 if state == S.HIDDEN else 0.0)
	if _drone.stream:
		if present and not _drone.playing:
			_drone.play()
		var dt := -10.0 if state == S.SHOWN else (-16.0 if present else -80.0)
		_drone.volume_db = lerpf(_drone.volume_db, dt, 1.0 - exp(-(0.8 if present else 0.4) * delta))
		if not present and _drone.volume_db < -60.0 and _drone.playing:
			_drone.stop()
	if state == S.SHOWN:
		Game.fear = maxf(Game.fear, 0.55 + 0.15 * _approaches)
	_tear = maxf(_tear - delta * 6.0, 0.0)
	_mat.set_shader_parameter("tear", _tear)
	if player == null or space == null:
		return
	var cam_on := player.camcorder.active
	match state:
		S.SHOWN:
			_update_shown(delta, cam_on)
		S.HIDDEN:
			_update_hidden(cam_on)
		S.IDLE:
			_try_start(cam_on)


func _update_shown(delta: float, cam_on: bool) -> void:
	var d := _flat_dist(figure.global_position, player.global_position)
	if _final:
		_final_t -= delta
		if _final_t <= 0.0 or d < 3.5:
			_final = false
			_vanish(true)
			if _light_fx and is_instance_valid(_light_fx):
				_light_fx.kill(0.0)
			return
	elif d < 8.0:
		_vanish(true)
		return
	if not cam_on:
		if _hide_t < 0.0:
			_hide_t = 0.25
		_hide_t -= delta
		if _hide_t <= 0.0:
			_hide_t = -1.0
			figure.visible = false
			player.camcorder.degrade = 0.0
			state = S.HIDDEN
			_hidden_at = Game.clock
			if Game.opts.has("log-tape"):
				print("[tape] hidden at t=%.1f" % Game.clock)
		return
	_hide_t = -1.0
	player.camcorder.degrade = 0.3 + 0.12 * _approaches
	# Stutter: hold a pose, then jump to another in one frame.
	_pose_t -= delta
	if _pose_t <= 0.0:
		_pose = (_pose + 1 + _rng.randi() % (POSES.size() - 1)) % POSES.size()
		_pose_t = _rng.randf_range(0.5, 1.8)
		_tear = 1.0
		player.camcorder.glitch_small()
		if (_drop.stream as AudioStreamRandomizer).streams_count > 0:
			_drop.play()
		# Sometimes the skipped frames carried it closer.
		var to_pl := player.global_position - figure.global_position
		to_pl.y = 0.0
		if _rng.randf() < 0.4 and to_pl.length() > 10.0:
			var step := figure.global_position + to_pl.normalized() * _rng.randf_range(0.5, 0.9)
			if space.is_walkable(step):
				figure.global_position = step
		# Sometimes the jump also turns it to face you squarely again.
		_face_player()
	_apply_pose(_pose, sin(Game.clock * 1.3) * 0.015)
	space.attention_point = figure.global_position + Vector3(0, 1.7, 0)
	space.attention_until = Game.clock + 0.5
	space.attention_kind = &"tape"


func _update_hidden(cam_on: bool) -> void:
	# Still worth staring at the spot (bots look again; a person would too).
	space.attention_point = figure.global_position + Vector3(0, 1.7, 0)
	space.attention_until = Game.clock + 0.5
	space.attention_kind = &"tape"
	if Game.clock - _hidden_at > RELOOK_WINDOW:
		_end_encounter(false)
		return
	if not cam_on or not player.camcorder.settled():
		return
	# Looked again. If you are still facing that way, it has come closer.
	var to := figure.global_position - player.global_position
	to.y = 0.0
	var fwd := Basis(Vector3.UP, player.yaw) * Vector3.FORWARD
	if to.normalized().dot(fwd) < 0.75:
		return
	_approaches += 1
	var d := to.length() - STEP_CLOSER
	if _final:
		_end_encounter(true)
		return
	if Game.opts.has("log-tape"):
		print("[tape] looked again at t=%.1f approach=%d new dist=%.1f" % [Game.clock, _approaches, d])
	if _approaches >= 3 or d < 9.0:
		# The last look: it is close, under the light, twisted wrong; a moment later it is gone
		# and the light it stood under dies (critique 012: "one shot where it's close, lit, wrong").
		d = 5.8
		_final = true
		_final_t = 1.6
	var p := _stand_point(player.global_position + to.normalized() * d, -to.normalized(), true)
	if p.x > 1e8:
		p = _stand_point(player.global_position + to.normalized() * d, -to.normalized(), true, false)
	if p.x > 1e8:
		_end_encounter(false)
		return
	_show_at(p)
	if (_breath.stream as AudioStreamRandomizer).streams_count > 0:
		_breath.play()


func _try_start(cam_on: bool) -> void:
	if not cam_on or Game.clock < _next_ok or _encounters >= MAX_ENCOUNTERS or not player.camcorder.settled():
		return
	var yaw := player.yaw
	var depth := space.view_depth(player.global_position, yaw, 34.0)
	if depth < (15.0 if _encounters == 0 else MIN_DEPTH):
		return
	if _encounters > 0 and _rng.randf() > 0.5 and not Game.opts.has("tape-always"):
		_next_ok = Game.clock + 6.0   # not every time
		return
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	# Farther the first time, nearer on later encounters.
	var dists: Array = [[19.0, 21.0, 17.0, 23.0], [16.0, 18.0, 14.0], [14.0, 12.5, 16.0]][mini(_encounters, 2)]
	for dd in dists:
		if dd > depth - 2.0:
			continue
		var p := _stand_point(player.global_position + dir * dd, -dir, false)
		if p.x > 1e8:
			continue
		_encounters += 1
		_approaches = 0
		_side = 1.0 if _rng.randf() < 0.5 else -1.0
		_show_at(p)
		# The only thing the naked eye gets: the nearest panel stutters.
		_light_fx = space.fixture_near(p, 4.0) if space.has_method("fixture_near") else null
		if _light_fx:
			_light_fx.stutter()
		if Game.opts.has("log-tape"):
			print("[tape] figure shown at t=%.1f dist=%.1f pos=%s player=%s skel=%s meshes=%d" % [Game.clock, dd, p, player.global_position, _skel != null, figure.find_children("*", "MeshInstance3D", true, false).size()])
		return
	_next_ok = Game.clock + 2.0


## A spot near `q` off to one side of the view line, close to a wall (never dead center), under
## a lit panel if there is one. `back` points from q toward the player.
func _stand_point(q: Vector3, back: Vector3, keep_side: bool, need_light: bool = true) -> Vector3:
	var right := Vector3(-back.z, 0.0, back.x)
	var sides := [_side, -_side] if not keep_side else [_side]
	for s in sides:
		for along in [0.0, 1.2, -1.2, 2.4]:
			var base: Vector3 = q + back * along
			if not space.is_walkable(base):
				continue
			# Walk sideways until the wall, then stand just off it.
			var off := 0.0
			while off < 2.2 and space.is_walkable(base + right * s * (off + 0.3)):
				off += 0.15
			var p: Vector3 = base + right * s * maxf(off - 0.2, 0.0)
			if need_light and space.has_method("fixture_near") and space.fixture_near(p, 2.2) == null:
				continue
			_side = s
			return Vector3(p.x, 0.0, p.z)
	return Vector3(1e9, 0, 0)


func _show_at(p: Vector3) -> void:
	figure.global_position = p
	_face_player()
	_pose = _rng.randi() % POSES.size() if not _final else 4
	_pose_t = _rng.randf_range(0.6, 1.4) if not _final else 99.0
	_apply_pose(_pose, 0.0)
	_tear = 1.0
	figure.visible = true
	state = S.SHOWN
	space.attention_point = p + Vector3(0, 1.7, 0)
	space.attention_until = Game.clock + 4.0
	space.attention_kind = &"tape"


func _face_player() -> void:
	var t := Vector3(player.global_position.x, 0.0, player.global_position.z)
	if _flat_dist(t, figure.global_position) > 0.1:
		figure.look_at(t, Vector3.UP, true)


func _vanish(glitch: bool) -> void:
	figure.visible = false
	player.camcorder.degrade = 0.0
	if glitch:
		player.camcorder.glitch()
	_end_encounter(false)


func _end_encounter(kill_light: bool) -> void:
	_final = false
	if Game.opts.has("log-tape"):
		print("[tape] encounter over at t=%.1f kill_light=%s" % [Game.clock, kill_light])
	figure.visible = false
	state = S.IDLE
	_hide_t = -1.0
	_next_ok = Game.clock + COOLDOWN
	if kill_light and _light_fx and is_instance_valid(_light_fx):
		_light_fx.kill(0.0)
		space.attention_point = _light_fx.global_position + Vector3(0, 2.4, 0)
		space.attention_until = Game.clock + 2.5
		space.attention_kind = &"light"
	_light_fx = null


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
