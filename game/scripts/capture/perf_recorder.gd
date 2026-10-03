class_name PerfRecorder
extends Node
## Realtime performance run (--perf=FILE.json). Vsync off, the bot plays, frame times are
## recorded after a warm-up and summarised: average fps, 1% low, p99 frame time.

var out_path := ""
var warmup := 6.0
var _ms := PackedFloat64Array()
var _gpu := PackedFloat64Array()
var _rid: RID


func _ready() -> void:
	out_path = Game.perf_out
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)


func _process(delta: float) -> void:
	if Game.clock < warmup:
		return
	_ms.append(delta * 1000.0)
	_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_rid))
	if delta > 0.035 and Game.opts.has("log-spikes"):
		print("[spike] t=%.2f frame=%.1f ms gpu=%.1f ms" % [Game.clock, delta * 1000.0, _gpu[-1]])
	if Game.clock >= Game.duration:
		_write()
		set_process(false)
		get_tree().quit()


func _write() -> void:
	var ms := Array(_ms)
	ms.sort()
	var n := ms.size()
	var total := 0.0
	for v in ms:
		total += v
	var avg_ms := total / maxf(n, 1)
	var worst := ms.slice(int(n * 0.99), n)
	var wsum := 0.0
	for v in worst:
		wsum += v
	var low_ms := wsum / maxf(worst.size(), 1)
	var gpu := Array(_gpu)
	gpu.sort()
	var gsum := 0.0
	for v in gpu:
		gsum += v
	var vp := get_viewport().get_visible_rect().size
	var data := {
		"avg_fps": snappedf(1000.0 / avg_ms, 0.1),
		"low_1pct_fps": snappedf(1000.0 / low_ms, 0.1),
		"p99_frame_ms": snappedf(ms[int(n * 0.99)], 0.01),
		"avg_frame_ms": snappedf(avg_ms, 0.01),
		"max_frame_ms": snappedf(ms[n - 1], 0.01),
		"frames_over_25ms": ms.filter(func(v): return v > 25.0).size(),
		"frames_over_33ms": ms.filter(func(v): return v > 33.4).size(),
		"avg_gpu_ms": snappedf(gsum / maxf(gpu.size(), 1), 0.01),
		"frames": n,
		"seconds_measured": snappedf(total / 1000.0, 0.1),
		"resolution": "%dx%d" % [int(vp.x), int(vp.y)],
		"preset": Game.preset,
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"cpu": OS.get_processor_name(),
		"engine": Engine.get_version_info()["string"],
		"seed": Game.run_seed,
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("[PERF] ", JSON.stringify(data))
