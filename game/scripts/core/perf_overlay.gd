class_name PerfOverlay
extends CanvasLayer
## F3: frame rate, frame time, GPU time, draw calls, seed, preset, GPU name.

var _label: Label
var _acc := 0.0
var _frames := 0
var _rid: RID


func _ready() -> void:
	layer = 50
	visible = false
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.85))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)
	_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("toggle_perf"):
		visible = not visible


func _process(delta: float) -> void:
	if not visible:
		return
	_acc += delta
	_frames += 1
	if _acc < 0.25:
		return
	var fps := _frames / _acc
	_acc = 0.0
	_frames = 0
	var vp := get_viewport().get_visible_rect().size
	_label.text = "%.0f fps  %.2f ms  gpu %.2f ms\ndraws %d  prims %dk\n%dx%d  %s  seed %d\n%s" % [
		fps, 1000.0 / maxf(fps, 0.001), RenderingServer.viewport_get_measured_render_time_gpu(_rid),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		int(vp.x), int(vp.y), Game.preset, Game.run_seed, RenderingServer.get_video_adapter_name()]
