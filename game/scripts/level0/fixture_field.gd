class_name FixtureField
extends RefCounted
## A tiny texture with one texel per ceiling tile that holds the live light level (and tube
## tint) of the fixture occupying that tile. The ceiling shader blurs it into the soft glow a
## lit panel throws on the tiles around it, and the troffer housing uses it to light its own
## reveal, so the panels stop reading as flat stickers (critique 006, LEDGER L021).
## Updated every frame from the fixtures' flicker levels; only changed texels are written.

var origin := Vector2.ZERO
var cell := 0.6
var size := Vector2i.ONE
var img: Image
var tex: ImageTexture
var _fixtures: Array[Fixture] = []
var _cells: Array = []     # per fixture: Array of Vector2i texels
var _last: Array[Color] = []
var _dirty := true
var _pending := {}         # fixture indices whose level changed since the last update


func _init(p_origin: Vector2, p_size_m: Vector2, p_cell: float) -> void:
	origin = p_origin
	cell = p_cell
	size = Vector2i(ceili(p_size_m.x / cell - 0.001), ceili(p_size_m.y / cell - 0.001))
	img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	tex = ImageTexture.create_from_image(img)


func texel(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / cell), floori((p.y - origin.y) / cell))


func add(fx: Fixture, cells: Array) -> void:
	fx.field = self
	fx.field_index = _fixtures.size()
	_fixtures.append(fx)
	_cells.append(cells)
	_last.append(Color(-1, -1, -1, 1))
	_pending[fx.field_index] = true


func mark(i: int) -> void:
	_pending[i] = true


func has_pending() -> bool:
	return not _pending.is_empty()


## Pushes the field to a material (ceiling, housing) that declares the field uniforms.
func bind(m: ShaderMaterial) -> void:
	m.set_shader_parameter("field_tex", tex)
	m.set_shader_parameter("field_origin", origin)
	m.set_shader_parameter("field_cell", cell)
	m.set_shader_parameter("field_size", Vector2(size))


func update() -> void:
	if _pending.is_empty():
		return
	var todo := _pending.keys()
	_pending.clear()
	for i in todo:
		var fx := _fixtures[i]
		var v := clampf(fx.level * fx.base_energy, 0.0, 1.0)
		var c := Color(fx.tint.r * v, fx.tint.g * v, fx.tint.b * v, 1.0)
		var o := _last[i]
		if absf(c.r - o.r) + absf(c.g - o.g) + absf(c.b - o.b) < 0.004:
			continue
		_last[i] = c
		for t in _cells[i]:
			var q: Vector2i = t
			if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y:
				img.set_pixelv(q, c)
		_dirty = true
	if _dirty:
		tex.update(img)
		_dirty = false
