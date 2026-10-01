class_name MeshKit
extends RefCounted
## Builds static level geometry: accumulates quads per material key, with world-scale
## UVs in meters (walls: x along the face, y down from a reference height; floors and
## ceilings: world x/z). commit() turns everything into MeshInstance3D nodes.

var _tools: Dictionary = {}


func st(key: String) -> SurfaceTool:
	if not _tools.has(key):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = s
	return _tools[key]


## Quad from four corners going around the face, its outward normal, and four UVs.
## Winding is fixed up automatically so the face points along n.
func quad(key: String, p: Array, n: Vector3, uv: Array, col: Color = Color(1, 1, 1, 1)) -> void:
	var s := st(key)
	var c: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	var order := [0, 1, 2, 0, 2, 3]
	if c.dot(n) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		s.set_color(col)
		s.set_normal(n)
		s.set_uv(uv[i])
		s.add_vertex(p[i])


static func world_uv(p: Vector3, n: Vector3, v_ref: float) -> Vector2:
	if absf(n.y) > 0.5:
		return Vector2(p.x, p.z)
	var t := Vector3.UP.cross(n)
	return Vector2(p.dot(t), v_ref - p.y)


func face(key: String, pts: Array, n: Vector3, v_ref: float, col: Color = Color(1, 1, 1, 1)) -> void:
	var uvs := []
	for q in pts:
		uvs.append(world_uv(q, n, v_ref))
	quad(key, pts, n, uvs, col)


const PX := 1
const NX := 2
const PY := 4
const NY := 8
const PZ := 16
const NZ := 32
const SIDES := PX | NX | PZ | NZ
const ALL := 63


## Axis-aligned box between corners a (min) and b (max).
func box(key: String, a: Vector3, b: Vector3, faces: int = ALL, v_ref: float = 0.0, col: Color = Color(1, 1, 1, 1)) -> void:
	if faces & PX:
		face(key, [Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z)], Vector3.RIGHT, v_ref, col)
	if faces & NX:
		face(key, [Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z)], Vector3.LEFT, v_ref, col)
	if faces & PY:
		face(key, [Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)], Vector3.UP, v_ref, col)
	if faces & NY:
		face(key, [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)], Vector3.DOWN, v_ref, col)
	if faces & PZ:
		face(key, [Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)], Vector3.BACK, v_ref, col)
	if faces & NZ:
		face(key, [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z)], Vector3.FORWARD, v_ref, col)


## Creates one MeshInstance3D per material key under parent. materials maps key -> Material.
## shadow_off lists keys that should not cast shadows.
func commit(parent: Node3D, materials: Dictionary, shadow_off: Array = []) -> Dictionary:
	var out := {}
	for key in _tools.keys():
		var s: SurfaceTool = _tools[key]
		s.generate_tangents()
		var mesh := s.commit()
		var mi := MeshInstance3D.new()
		mi.name = "geo_" + key
		mi.mesh = mesh
		if materials.has(key):
			mi.material_override = materials[key]
		if key in shadow_off:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		parent.add_child(mi)
		out[key] = mi
	_tools.clear()
	return out
