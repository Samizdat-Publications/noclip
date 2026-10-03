class_name DeathReplay
extends CanvasLayer
## The VHS death replay (VISION "The run": "it should feel like found footage of your own death").
## Always recording: the last SECONDS of the picture you saw (camcorder up or not) at 15 frames a
## second, shrunk to 480 x 270 and kept on the GPU (a ring of textures, copied with the
## RenderingDevice, so nothing is read back and nothing stalls), and the last SECONDS of the sound
## (an AudioEffectCapture on the master bus). When the Occupant gets you the world pauses and the
## tape plays: a crunch, a fast rewind, PLAY, your last seconds again through a worn VCR (tracking,
## chroma, head-switch noise, wow in the sound), a shaking freeze on the last frame, snow, then
## END OF TAPE, and you are back at the start (Level0World.after_death).

signal finished
## The end card is up (black): the world can rebuild round the start now, out of sight.
signal card_up

var catalogue: Catalogue            # what is on this tape (the end card's label)

const W := 480
const H := 270
const FPS := 15.0
const SECONDS := 16.0
const N := int(FPS * SECONDS)

var playing := false
var _src: SubViewport
var _rd: RenderingDevice
var _ring: Array[RID] = []
var _tex: Array[Texture2DRD] = []
var _head := 0                    # next slot to write
var _count := 0
var _rec_t := 0.0
var _ok := false
var _cap: AudioEffectCapture
var _cap_idx := -1
var _audio: Array = []            # PackedVector2Array chunks, oldest first
var _audio_frames := 0
var _mix_rate := 48000.0
# playback
var _screen: ColorRect
var _mat: ShaderMaterial
var _osd: Label
var _counter: Label
var _end: Label
var _t := 0.0
var _phase := 0                  # 0 crunch, 1 rewind, 2 play, 3 freeze, 4 snow, 5 end card
var _frames: Array = []          # ring order oldest -> newest, frozen at the moment of death
var _gen: AudioStreamPlayer
var _gen_pb: AudioStreamGeneratorPlayback
var _clip: PackedVector2Array
var _clip_pos := 0.0
var _sfx: AudioStreamPlayer
var _hiss: AudioStreamPlayer


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mix_rate = AudioServer.get_mix_rate()
	_setup_video()
	_setup_audio()
	_setup_screen()


func _setup_video() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null or Game.opts.has("no_replay"):
		return
	_src = SubViewport.new()
	_src.size = Vector2i(W, H)
	_src.disable_3d = true
	_src.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_src.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_src)
	var tr := TextureRect.new()
	tr.texture = get_viewport().get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = Vector2(W, H)
	_src.add_child(tr)


## The ring is made on the first frame the source has rendered (its format is known then).
func _make_ring() -> bool:
	var src := RenderingServer.texture_get_rd_texture(_src.get_texture().get_rid())
	if not src.is_valid():
		return false
	var f := _rd.texture_get_format(src)
	for i in N:
		var tf := RDTextureFormat.new()
		tf.width = W
		tf.height = H
		tf.format = f.format
		tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		var rid := _rd.texture_create(tf, RDTextureView.new())
		_ring.append(rid)
		var t := Texture2DRD.new()
		t.texture_rd_rid = rid
		_tex.append(t)
	return true


func _setup_audio() -> void:
	if Game.opts.has("no_replay"):
		return
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 0.5
	AudioServer.add_bus_effect(0, _cap, 0)
	_cap_idx = 0
	AudioServer.add_bus()
	var b := AudioServer.bus_count - 1
	AudioServer.set_bus_name(b, "Replay")
	AudioServer.set_bus_send(b, "Master")


func _setup_screen() -> void:
	# A ColorRect, not a TextureRect: a TextureRect with no texture draws nothing at all.
	_screen = ColorRect.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/vhs_replay.gdshader")
	_screen.material = _mat
	_screen.visible = false
	add_child(_screen)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	font.font_weight = 700
	_osd = _label(font)
	_counter = _label(font)
	_end = _label(font)
	_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for nm in ["_sfx", "_hiss"]:
		var p := AudioStreamPlayer.new()
		p.bus = &"Replay"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		set(nm, p)
	_gen = AudioStreamPlayer.new()
	_gen.bus = &"Replay"
	_gen.process_mode = Node.PROCESS_MODE_ALWAYS
	var g := AudioStreamGenerator.new()
	g.mix_rate = _mix_rate
	g.buffer_length = 0.4
	_gen.stream = g
	add_child(_gen)


func _label(font: Font) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", Color(0.93, 0.93, 0.9))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	add_child(l)
	return l


func _process(delta: float) -> void:
	if playing:
		_play(delta)
		return
	_record(delta)


func _record(delta: float) -> void:
	# sound: keep the last SECONDS
	if _cap and AudioServer.is_bus_effect_enabled(0, _cap_idx):
		var n := _cap.get_frames_available()
		if n > 0:
			var buf := _cap.get_buffer(n)
			_audio.append(buf)
			_audio_frames += buf.size()
			while _audio.size() > 1 and _audio_frames - (_audio[0] as PackedVector2Array).size() > int(_mix_rate * SECONDS):
				_audio_frames -= (_audio[0] as PackedVector2Array).size()
				_audio.pop_front()
	# picture
	if _src == null:
		return
	_rec_t -= delta
	if _rec_t > 0.0:
		return
	_rec_t += 1.0 / FPS
	if _rec_t < 0.0:
		_rec_t = 0.0
	if not _ok:
		_ok = _make_ring()
		if not _ok:
			return
	var src := RenderingServer.texture_get_rd_texture(_src.get_texture().get_rid())
	if not src.is_valid():
		return
	var dst: RID = _ring[_head]
	RenderingServer.call_on_render_thread(func() -> void:
		_rd.texture_copy(src, dst, Vector3.ZERO, Vector3.ZERO, Vector3(W, H, 1), 0, 0, 0, 0))
	_head = (_head + 1) % N
	_count = mini(_count + 1, N)


var _end_clock := 0.0
var _card_text := ""
var _found := false                 # playing the tape of the camcorder you dropped (not a death)
var _saved: Array[RID] = []
var _saved_tex: Array[Texture2DRD] = []
var _saved_count := 0
var _saved_clip := PackedVector2Array()
var _saved_end := 0.0
var _prompt: Label


## Keeps a copy of this death's tape in the camcorder left where you died (VISION: "pick it up and
## its footage plays, showing how you died").
func _keep() -> void:
	if not _ok or _rd == null:
		return
	if _saved.is_empty():
		var f := _rd.texture_get_format(_ring[0])
		for i in N:
			var tf := RDTextureFormat.new()
			tf.width = W
			tf.height = H
			tf.format = f.format
			tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
			var rid := _rd.texture_create(tf, RDTextureView.new())
			_saved.append(rid)
			var t := Texture2DRD.new()
			t.texture_rd_rid = rid
			_saved_tex.append(t)
	var srcs: Array[RID] = []
	for i in _count:
		srcs.append(_ring[(_head - _count + i + N) % N])
	var dsts := _saved.slice(0, _count)
	RenderingServer.call_on_render_thread(func() -> void:
		for i in srcs.size():
			_rd.texture_copy(srcs[i], dsts[i], Vector3.ZERO, Vector3.ZERO, Vector3(W, H, 1), 0, 0, 0, 0))
	_saved_count = _count
	_saved_clip = _clip.duplicate()
	_saved_end = _end_clock


func has_found_tape() -> bool:
	return _saved_count > 0


## "E  PLAY TAPE" by the camcorder you dropped.
func show_prompt(on: bool) -> void:
	if _prompt == null:
		_prompt = _label((_osd.get_theme_font("font") as Font))
	_prompt.visible = on and not playing
	if on:
		var vp := get_viewport().get_visible_rect().size
		_prompt.add_theme_font_size_override("font_size", int(vp.y * 0.03))
		_prompt.text = "E   PLAY TAPE"
		_prompt.position = Vector2(vp.x * 0.5 - vp.y * 0.12, vp.y * 0.62)


## Plays the tape of the camcorder you dropped: straight to PLAY, no crunch, no end card.
func play_found() -> void:
	if playing or _saved_count == 0:
		return
	playing = true
	_found = true
	_frames.clear()
	for i in _saved_count:
		_frames.append(_saved_tex[i])
	_clip = _saved_clip
	_end_clock = _saved_end
	if _cap:
		AudioServer.set_bus_effect_enabled(0, _cap_idx, false)
	_screen.visible = true
	get_tree().paused = true
	for nm in ["World", "UI"]:
		var b := AudioServer.get_bus_index(nm)
		if b >= 0:
			AudioServer.set_bus_mute(b, true)
	if _prompt:
		_prompt.visible = false
	_next_phase(2)
	_sfx_play("vcr_play_01", -4.0, false)
	_hiss_play()
	_clip_pos = 0.0
	_gen.play()
	_gen_pb = _gen.get_stream_playback() as AudioStreamGeneratorPlayback
	_osd.visible = true
	_counter.visible = true
	print("[replay] the dropped camcorder's tape: %d frames" % _frames.size())


## The tape ends here: play it back.
func start() -> void:
	if playing:
		return
	playing = true
	_frames.clear()
	for i in _count:
		_frames.append(_tex[(_head - _count + i + N) % N])
	_clip = PackedVector2Array()
	for c in _audio:
		_clip.append_array(c)
	_end_clock = Game.clock
	_found = false
	_keep()
	if _cap:
		AudioServer.set_bus_effect_enabled(0, _cap_idx, false)
	_t = 0.0
	_phase = 0
	_screen.visible = true
	_mat.set_shader_parameter("mode", 3)
	get_tree().paused = true
	for nm in ["World", "UI"]:
		var b := AudioServer.get_bus_index(nm)
		if b >= 0:
			AudioServer.set_bus_mute(b, true)
	print("[replay] start: %d frames (%.1f s), %.1f s of sound" % [_frames.size(), _frames.size() / FPS, _clip.size() / _mix_rate])


func _play(delta: float) -> void:
	_t += delta
	var vp := get_viewport().get_visible_rect().size
	var fs := int(vp.y * 0.045)
	for l in [_osd, _counter, _end]:
		(l as Label).add_theme_font_size_override("font_size", fs)
	_osd.position = Vector2(vp.x * 0.07, vp.y * 0.07)
	_counter.position = Vector2(vp.x * 0.66, vp.y * 0.86)
	_end.size = vp
	_end.position = Vector2.ZERO
	_mat.set_shader_parameter("time", Game.clock)
	var nf := _frames.size()
	match _phase:
		0:   # the crunch: snow
			_mat.set_shader_parameter("mode", 3)
			if _t > 0.9:
				_next_phase(1)
				_sfx_play("vcr_rewind_loop", -6.0, true)
		1:   # rewind, fast, newest to oldest
			var dur := 2.2
			var k := clampi(int((1.0 - _t / dur) * (nf - 1)), 0, maxi(nf - 1, 0))
			_show(k, 1)
			_osd.visible = true
			_osd.text = "<< REW"
			_counter.visible = true
			_counter.text = _stamp(k)
			if _t > dur or nf == 0:
				_next_phase(2)
				_sfx.stop()
				_sfx_play("vcr_play_01", -4.0, false)
				_hiss_play()
				_clip_pos = 0.0
				_gen.play()
				_gen_pb = _gen.get_stream_playback() as AudioStreamGeneratorPlayback
		2:   # play, real time, with the sound
			var k2 := clampi(int(_t * FPS), 0, maxi(nf - 1, 0))
			_show(k2, 0)
			_osd.text = "PLAY >"
			_osd.visible = fmod(_t, 2.0) < 1.6
			_counter.text = _stamp(k2)
			_feed_audio()
			if _t * FPS >= nf - 1:
				_next_phase(3)
				_gen.stop()
		3:   # the last frame, shaking
			_show(nf - 1, 2)
			_osd.text = "PAUSE"
			if _found and _t > 1.4:
				_finish()
				return
			if _t > 1.6:
				_next_phase(4)
				_osd.visible = false
				_counter.visible = false
				_hiss.stop()
				_sfx_play("tape_static_loop", -8.0, true)
		4:   # snow
			_mat.set_shader_parameter("mode", 3)
			if _t > 1.1:
				_next_phase(5)
				_sfx.stop()
				_sfx_play("vcr_eject_01", -6.0, false)
		5:   # end card on black
			_mat.set_shader_parameter("mode", 4)
			if not _end.visible:
				_card_text = "END OF TAPE   %s\n\n%s" % [_stamp(nf - 1), catalogue.tape_label() if catalogue else ""]
				_end.visible = true
				card_up.emit()
			_end.text = _card_text
			if _t > 5.0:
				_finish()


func _next_phase(p: int) -> void:
	_phase = p
	_t = 0.0


func _show(k: int, mode: int) -> void:
	if _frames.is_empty():
		_mat.set_shader_parameter("mode", 3)
		return
	_mat.set_shader_parameter("frame_tex", _frames[k])
	_mat.set_shader_parameter("mode", mode)


## The tape counter: minutes and seconds into the run at that frame.
func _stamp(k: int) -> String:
	var secs := _end_clock - (_frames.size() - 1 - k) / FPS
	secs = maxf(secs, 0.0)
	return "%d:%02d:%02d" % [int(secs / 3600.0), int(secs / 60.0) % 60, int(secs) % 60]


func _feed_audio() -> void:
	if _gen_pb == null or _clip.is_empty():
		return
	var n := _gen_pb.get_frames_available()
	if n <= 0:
		return
	var out := PackedVector2Array()
	out.resize(n)
	# Wow and flutter: the read speed wanders a little; now and then a dropout.
	for i in n:
		var rate := 1.0 + 0.012 * sin(Game.clock * 3.1 + i * 0.00007) + 0.004 * sin(Game.clock * 17.0)
		_clip_pos += rate
		var j := int(_clip_pos)
		if j >= _clip.size() - 1:
			out[i] = Vector2.ZERO
			continue
		var f := _clip_pos - j
		out[i] = _clip[j].lerp(_clip[j + 1], f) * 0.85
	_gen_pb.push_buffer(out)


func _sfx_play(nm: String, db: float, loop: bool) -> void:
	var p := "res://assets/audio/entity/%s.wav" % nm
	if not ResourceLoader.exists(p):
		return
	var s := load(p) as AudioStreamWAV
	if loop and s:
		s = s.duplicate() as AudioStreamWAV
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	_sfx.stream = s
	_sfx.volume_db = db
	_sfx.play()


func _hiss_play() -> void:
	var p := "res://assets/audio/entity/tape_static_loop.wav"
	if not ResourceLoader.exists(p):
		return
	var s := (load(p) as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(s.get_length() * s.mix_rate)
	_hiss.stream = s
	_hiss.volume_db = -26.0
	_hiss.play()


func _finish() -> void:
	playing = false
	_screen.visible = false
	_end.visible = false
	_osd.visible = false
	_counter.visible = false
	_sfx.stop()
	_hiss.stop()
	_gen.stop()
	for nm in ["World", "UI"]:
		var b := AudioServer.get_bus_index(nm)
		if b >= 0:
			AudioServer.set_bus_mute(b, false)
	if _cap:
		_cap.clear_buffer()
		AudioServer.set_bus_effect_enabled(0, _cap_idx, true)
	_audio.clear()
	_audio_frames = 0
	_count = 0
	get_tree().paused = false
	print("[replay] over")
	finished.emit()


func _exit_tree() -> void:
	if _rd:
		for rid in _ring + _saved:
			if rid.is_valid():
				_rd.free_rid(rid)
	_ring.clear()
	_saved.clear()
