extends SceneTree
## Lists crawl holes and tall-room ladders near the start for one seed (S04 debug).

func _init() -> void:
	var sd := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 4242
	var g := Level0Gen.new(sd)
	var nh := 0
	var nl := 0
	for cx in range(-2, 3):
		for cz in range(-2, 3):
			var L := g.generate(cx, cz)
			for h in L.get("holes", []):
				nh += 1
				print("hole chunk %d,%d world (%.1f, %.1f)-(%.1f, %.1f)" % [cx, cz, cx * 24 + h[0], cz * 24 + h[1], cx * 24 + h[2], cz * 24 + h[3]])
			for ld in L.get("ladders", []):
				nl += 1
				print("ladder chunk %d,%d base world (%.1f, %.1f) n=%s" % [cx, cz, cx * 24 + ld["p"][0], cz * 24 + ld["p"][1], str(ld["n"])])
	print("holes %d ladders %d" % [nh, nl])
	quit()
