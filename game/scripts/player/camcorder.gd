class_name Camcorder
extends CanvasLayer
## The camcorder in your hands (hold right mouse). Its overlay IS the HUD: REC, the tape
## timestamp, battery. Holding the button lifts the physical camera to your eye (a viewmodel
## on the player camera); the viewfinder image cuts in only once the eyecup is at your eye,
## and lowering reverses it (critique 006, L025). Later: infrared and showing things the
## naked eye cannot see.

## The record beep (something listening hears it, S06).
signal beeped

const RAISE_T := 0.52   # 0.3 s read as an instant toggle on video (critique 008, L048)
const LOWER_T := 0.42

var active := false
var want := false
## 0 = held low out of view, 1 = eyecup at the eye.
var raise := 0.0
var viewmodel: Node3D
var lcd_mat: ShaderMaterial          # the flip-out screen's picture (Player._add_flip_screen)
var fov := 60.0
var degrade := 0.0
var _rect: ColorRect
var _osd: Control
var _rec: Label
var _dot: Label
var _stamp: Label
var _batt: Label
var _beep: AudioStreamPlayer
var _motor: AudioStreamPlayer
var _rec_time := 0.0
var _burst := 0.0
var _hide_in := -1.0
var _start_minutes := 0


func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/camcorder.gdshader")
	_rect.material = m
	add_child(_rect)
	_osd = Control.new()
	_osd.set_anchors_preset(Control.PRESET_FULL_RECT)
	_osd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_osd)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	font.font_weight = 700
	_dot = _label(font, Color(1.0, 0.16, 0.12))
	_rec = _label(font, Color(0.95, 0.95, 0.92))
	_stamp = _label(font, Color(0.95, 0.95, 0.92))
	_batt = _label(font, Color(0.95, 0.95, 0.92))
	_dot.text = "●"
	_rec.text = "REC"
	_batt.text = "▮▮▮▯"
	_beep = _player("cam_rec_beep", -10.0)
	_motor = _player("cam_motor_loop", -24.0)
	var r := Game.rng("camcorder")
	_start_minutes = 23 * 60 + r.randi_range(2, 50)
	visible = false


func _label(font: Font, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_osd.add_child(l)
	return l


func _player(name: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var path := "res://assets/audio/level0/" + name + ".wav"
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = db
	p.bus = &"UI"
	add_child(p)
	return p


func set_active(on: bool) -> void:
	want = on


var _active_since := 0.0


## Up, recording, and past the power-on snow.
func settled() -> bool:
	return active and Game.clock - _active_since > 0.6


## A short burst of roll and snow (something just left the frame).
func glitch() -> void:
	_burst = 0.15


## A one-frame hiccup (a frame skip on the tape).
func glitch_small() -> void:
	_burst = maxf(_burst, 0.07)


func _switch(on: bool) -> void:
	if on == active:
		return
	active = on
	if on:
		_active_since = Game.clock
	if Game.opts.has("log-cam"):
		print("[cam] %s frame=%d" % ["on" if on else "off", Game.frame])
	_burst = 0.2   # the picture rolls and snows for a moment when the camera comes up or goes down
	if on:
		visible = true
		_hide_in = -1.0
		if _beep.stream:
			_beep.play()
		beeped.emit()
		if _motor.stream:
			_motor.play()
	else:
		_hide_in = 0.14
		_motor.stop()


## Where the physical camcorder sits for the current raise amount (local to the player camera).
func _update_viewmodel() -> void:
	if viewmodel == null:
		return
	var r := raise
	if Game.opts.has("vm_hold"):
		r = float(Game.opts["vm_hold"])   # look-dev: photograph the camera mid-lift
	if lcd_mat:
		lcd_mat.set_shader_parameter("time", Game.clock)
	# Out of sight for the first part of the lift (L092: seen low and pointing forward, the body
	# read as a pistol); it comes up from below the frame with its side screen turned to you.
	viewmodel.visible = r > 0.22 and not active
	if not viewmodel.visible:
		return
	var e := 1.0 - pow(1.0 - r, 1.6)   # quick to come into view, settles onto the eye
	var low := Vector3(0.17, -0.42, -0.3)
	var eye := Vector3(0.0, 0.0, 0.004)
	var p := low.lerp(eye, e) + Vector3(0.0, sin(e * PI) * 0.04, sin(e * PI) * -0.04)
	# Held level and turned a little to the left, the way you hold a camcorder at the chest before
	# you lift it, not tipped down like a held tool.
	var low_rot := Quaternion.from_euler(Vector3(-0.12, -0.3, 0.08))
	var q := low_rot.slerp(Quaternion.IDENTITY, pow(e, 0.8))
	viewmodel.transform = Transform3D(Basis(q).scaled(Vector3.ONE * 0.82), p)


func _process(delta: float) -> void:
	if want:
		raise = minf(raise + delta / RAISE_T, 1.0)
		if raise >= 1.0:
			_switch(true)
	else:
		_switch(false)
		raise = maxf(raise - delta / LOWER_T, 0.0)
	_update_viewmodel()
	_burst = maxf(_burst - delta, 0.0)
	if _hide_in >= 0.0:
		_hide_in -= delta
		if _hide_in < 0.0:
			visible = false
	if not visible:
		return
	_rec_time += delta
	# Battery drains over the run; the last bar blinks.
	var bars := clampi(4 - int(Game.clock / 80.0), 1, 4)
	var shown := "▮".repeat(bars) + "▯".repeat(4 - bars)
	if bars == 1 and fmod(Game.clock, 1.0) < 0.5:
		shown = "▯▯▯▯"
	_batt.text = shown
	var vp := get_viewport().get_visible_rect().size
	var w := vp.y * 4.0 / 3.0
	var x0 := (vp.x - w) * 0.5
	var fs := int(vp.y * 0.034)
	for l in [_dot, _rec, _stamp, _batt]:
		l.add_theme_font_size_override("font_size", fs)
	_dot.position = Vector2(x0 + w * 0.06, vp.y * 0.06)
	_rec.position = _dot.position + Vector2(fs * 1.2, 0)
	_dot.visible = fmod(Game.clock, 1.0) < 0.6
	_batt.position = Vector2(x0 + w * 0.94 - fs * 3.0, vp.y * 0.06)
	var mins := _start_minutes + int((Game.clock) / 60.0)
	var secs := int(Game.clock) % 60
	var hh := (mins / 60) % 12
	if hh == 0:
		hh = 12
	_stamp.text = "PM %2d:%02d:%02d\nOCT. 14 1996" % [hh, mins % 60, secs]
	_stamp.position = Vector2(x0 + w * 0.94 - fs * 7.5, vp.y * 0.84)
	var m := _rect.material as ShaderMaterial
	m.set_shader_parameter("time", Game.clock)
	m.set_shader_parameter("frame_seed", float(Game.frame % 977))
	m.set_shader_parameter("degrade", clampf(degrade + Game.drift + _burst * 3.0, 0.0, 1.0))
	m.set_shader_parameter("burst", _burst / 0.28)
