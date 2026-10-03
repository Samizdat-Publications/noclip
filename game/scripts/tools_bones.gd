extends SceneTree
## Prints the bone names of a rigged glb (builder tool): godot --headless --path game --script res://scripts/tools_bones.gd -- res://assets/entity/occupant_rigged.glb


func _init() -> void:
	var path := "res://assets/entity/occupant_rigged.glb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("res://"):
			path = a
	var inst := (load(path) as PackedScene).instantiate()
	var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk:
		for i in sk.get_bone_count():
			print("%d %s parent=%d rest=%s" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), sk.get_bone_rest(i).origin])
	for n in inst.find_children("*", "Node3D", true, false):
		print("node ", n.get_path(), " ", n.get_class(), " scale=", (n as Node3D).scale)
	inst.free()
	quit()
