extends SceneTree
## QA check (S04, D036): chunk (1, 0), just east of the start, has a storeroom in at least 98 of 100
## seeds (its rooms are built big for it), and storerooms elsewhere are about one chunk in eight. Run headless with --script.

func _init() -> void:
	var missing := []
	var total := 0
	var count := 0
	for s in range(1, 201):
		var g := Level0Gen.new(s)
		var L := g.generate(1, 0)
		if L.get("closets", []).is_empty():
			missing.append(s)
		if s <= 20:
			for cx in range(-4, 5):
				for cz in range(-4, 5):
					total += 1
					if not g.generate(cx, cz).get("closets", []).is_empty():
						count += 1
	print("closet test: %s (%d of 200 seeds without one in chunk 1,0: %s); elsewhere %d of %d chunks" % ["PASS" if missing.size() <= 4 else "FAIL", missing.size(), str(missing.slice(0, 12)), count, total])
	quit()
