class_name PropCache
extends RefCounted
## Fast prop placement for streamed chunks. Instancing a whole imported .glb scene costs several
## milliseconds; the first time a prop is needed its meshes are recorded, and every later copy is
## a light Node3D with MeshInstance3D children sharing those meshes and materials.

static var _parts := {}   # path -> Array of [Mesh, Transform3D, Array[Material] overrides]


static func make(path: String) -> Node3D:
	if not _parts.has(path):
		var parts := []
		if ResourceLoader.exists(path):
			var inst := (load(path) as PackedScene).instantiate() as Node3D
			_collect(inst, Transform3D.IDENTITY, parts, true)
			inst.free()
		_parts[path] = parts
	var root := Node3D.new()
	for p in _parts[path]:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.transform = p[1]
		# Fade into the haze with the rest of the level (D020).
		mi.visibility_range_end = 38.0
		mi.visibility_range_end_margin = 8.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		for i in (p[2] as Array).size():
			if p[2][i] != null:
				mi.set_surface_override_material(i, p[2][i])
		root.add_child(mi)
	return root


static func _collect(n: Node, xf: Transform3D, parts: Array, is_root: bool) -> void:
	var here := xf if is_root else xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var ov := []
		for i in mi.get_surface_override_material_count():
			ov.append(mi.get_surface_override_material(i))
		parts.append([mi.mesh, here, ov])
	for c in n.get_children():
		_collect(c, here, parts, false)
