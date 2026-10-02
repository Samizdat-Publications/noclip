extends SceneTree
## QA check (S03): the spawn chunk always has a seam. Run headless with --script.

func _init() -> void:
	var missing := []
	for s in range(1, 201):
		var g := Level0Gen.new(s)
		var L := g.generate(0, 0)
		if L.get("seams", []).is_empty():
			missing.append(s)
	print("spawn seam test: %s (%d of 200 seeds without a seam: %s)" % ["PASS" if missing.is_empty() else "FAIL", missing.size(), str(missing.slice(0, 10))])
	quit()
