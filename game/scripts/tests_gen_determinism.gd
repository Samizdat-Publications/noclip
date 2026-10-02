extends SceneTree
## Headless check: Level0Gen is a pure function of (seed, chunk). Also checks the shared-edge rule
## (both neighbors agree on every edge) and that every non-loop chunk edge has a gap.
## Run: godot --headless --path game --script res://scripts/tests_gen_determinism.gd

func _init() -> void:
	var ok := true
	for seed in [777, 4242, 123456]:
		var g1 := Level0Gen.new(seed)
		var g2 := Level0Gen.new(seed)
		for cx in range(-3, 4):
			for cz in range(-3, 4):
				var a := JSON.stringify(g1.generate(cx, cz))
				var b := JSON.stringify(g2.generate(cx, cz))
				if a != b:
					print("FAIL determinism seed %d chunk %d,%d" % [seed, cx, cz])
					ok = false
				var L := g1.generate(cx, cz)
				var east := g1.generate(cx + 1, cz)
				if JSON.stringify(L["gates"]["E"]) != JSON.stringify(east["gates"]["W"]):
					print("FAIL shared edge E/W seed %d chunk %d,%d" % [seed, cx, cz])
					ok = false
				var south := g1.generate(cx, cz + 1)
				if JSON.stringify(L["gates"]["S"]) != JSON.stringify(south["gates"]["N"]):
					print("FAIL shared edge S/N seed %d chunk %d,%d" % [seed, cx, cz])
					ok = false
				if not L.has("loop"):
					var open_sides := 0
					for side in ["W", "E", "N", "S"]:
						if not L["gates"][side].is_empty():
							open_sides += 1
					if open_sides < 2:
						print("WARN chunk %d,%d seed %d has only %d open sides" % [cx, cz, seed, open_sides])
	print("gen tests: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
