class_name Camcorder
extends CanvasLayer
## The camcorder in your hands (hold right mouse). Its overlay IS the HUD: REC, the tape
## timestamp, battery. M1: the VHS image and sounds. Later: infrared, battery drain, and
## showing things the naked eye cannot see.

var active := false
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
	if on == active:
		return
	active = on
	visible = on
	if on:
		if _beep.stream:
			_beep.play()
		if _motor.stream:
			_motor.play()
	else:
		_motor.stop()


func _process(delta: float) -> void:
	if not active:
		return
	_rec_time += delta
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
	m.set_shader_parameter("degrade", clampf(degrade + Game.drift, 0.0, 1.0))
