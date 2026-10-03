class_name Kit
extends Node
## The kit you bought at the Landing (D050), carried every run: the flashbulb on the camcorder (F
## with the camcorder up: the thing that hunts you is pinned where the flash catches it), road flares
## (G: thrown ahead, burn red, it will not cross red light) and overshoes (quieter, longer sprint).
## Charges refill at the start of every run. The bot uses them on its own when it is chased.

var player: Player
var space: Level0World
var flashes := 0
var flares := 0
var flashes_max := 0
var flares_max := 0
var _cool := 0.0
var _hud: Label
var _white: ColorRect
var _burst: OmniLight3D
var _snd: AudioStreamPlayer
var _hud_t := 0.0


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_white = ColorRect.new()
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.color = Color(1, 1, 1, 0)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_white)
	_hud = Label.new()
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hud.position = Vector2(48, -96)
	_hud.add_theme_font_size_override("font_size", 22)
	_hud.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82, 0.85))
	_hud.add_theme_font_override("font", Kit.vhs_font())
	_hud.visible = false
	layer.add_child(_hud)
	_snd = AudioStreamPlayer.new()
	_snd.bus = &"Master"
	add_child(_snd)


## The camcorder's monospace OSD face, for every VHS screen (kit, lift, appraisal).
static func vhs_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	font.font_weight = 700
	return font


func attach(p: Player, s: Level0World) -> void:
	player = p
	space = s
	_burst = OmniLight3D.new()
	_burst.light_color = Color(0.92, 0.95, 1.0)
	_burst.light_energy = 0.0
	_burst.omni_range = 16.0
	_burst.omni_attenuation = 0.9
	_burst.shadow_enabled = true
	_burst.position = Vector3(0, 0, -0.3)
	player.cam.add_child(_burst)
	refill()


## A new run: charges from what you own, the overshoes on your feet.
func refill() -> void:
	var pr := Game.progress
	flashes_max = pr.level("flash")
	flares_max = pr.level("flares")
	flashes = flashes_max
	flares = flares_max
	var b := pr.level("boots")
	player.quiet = [1.0, 0.72, 0.55][clampi(b, 0, 2)]
	player.stamina_drain = [0.11, 0.08, 0.06][clampi(b, 0, 2)]
	_show_hud(4.0)


func _show_hud(t: float) -> void:
	_hud_t = t


func _sfx(nm: String, db: float) -> void:
	var p := "res://assets/audio/descent/%s.wav" % nm
	if ResourceLoader.exists(p):
		_snd.stream = load(p)
		_snd.volume_db = db
		_snd.play()


func _process(delta: float) -> void:
	if player == null:
		return
	_cool -= delta
	_hud_t -= delta
	var show := (player.camcorder.active or _hud_t > 0.0) and (flashes_max + flares_max) > 0 and not player.caught
	_hud.visible = show
	if show:
		var parts := []
		if flashes_max > 0:
			parts.append("FLASH " + "o".repeat(flashes) + ".".repeat(flashes_max - flashes))
		if flares_max > 0:
			parts.append("FLARE " + "o".repeat(flares) + ".".repeat(flares_max - flares))
		_hud.text = "   ".join(parts)
	_white.color.a = move_toward(_white.color.a, 0.0, delta * 2.2)
	if _burst:
		_burst.light_energy = move_toward(_burst.light_energy, 0.0, delta * 60.0)
	if player.caught or _cool > 0.0:
		return
	if Game.autoplay:
		_bot(delta)
		return
	if Input.is_action_just_pressed("flash") and player.camcorder.settled():
		use_flash()
	elif Input.is_action_just_pressed("flare"):
		use_flare()


func use_flash(dir_override := Vector3.ZERO) -> bool:
	if flashes <= 0:
		_sfx("appraise_tick", -16.0)
		return false
	flashes -= 1
	_cool = 1.2
	_white.color.a = 0.85
	_burst.light_energy = 14.0
	_sfx("flash_pop_0%d" % (1 + Game.frame % 2), 0.0)
	get_tree().create_timer(0.9).timeout.connect(_sfx.bind("flash_charge", -14.0))
	_show_hud(3.0)
	var hit := false
	if space and space.hunter:
		var dir := dir_override if dir_override != Vector3.ZERO else -player.cam.global_transform.basis.z
		hit = space.hunter.flashed(player.cam.global_position, dir)
	if Game.opts.has("log-hunt") or Game.opts.has("log-kit"):
		print("[kit] t=%.1f flash (%d left) %s" % [Game.clock, flashes, "PINNED it" if hit else "missed"])
	return hit


func use_flare() -> bool:
	if flares <= 0 or space == null:
		return false
	flares -= 1
	_cool = 0.8
	var fwd := -player.cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var from := player.cam.global_position + fwd * 0.3 - Vector3(0, 0.3, 0)
	# As far as 4.5 m ahead, short of any wall.
	var dist := 4.5
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * dist)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		dist = maxf(0.6, from.distance_to(hit["position"]) - 0.4)
	var to := Vector3(from.x, player.global_position.y, from.z) + fwd * dist
	var fl := Flare.new()
	space.add_child(fl)
	fl.throw_from(from, to)
	space.flares.append(fl)
	_show_hud(3.0)
	if Game.opts.has("log-hunt") or Game.opts.has("log-kit"):
		print("[kit] t=%.1f flare thrown (%d left) to %s" % [Game.clock, flares, to])
	return true


## The bot: a flare when a chase starts, the flash when it is close behind and in view.
func _bot(_delta: float) -> void:
	if space == null or space.hunter == null:
		return
	var h := space.hunter
	if h._pinned > 0.0 or space.in_flare(player.global_position):
		return
	if h.state == OccupantHunter.S.CHASE:
		var d := h.global_position.distance_to(player.global_position)
		if flashes > 0 and d < 8.0:
			use_flash((h.global_position + Vector3(0, 1.0, 0) - player.cam.global_position).normalized())
		elif flares > 0 and d < 12.0 and h._st > 1.5:
			use_flare()
