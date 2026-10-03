extends SceneTree
## Remembered-wrong rules (S05): how often each thing lands in a layout, over many chunks.
##   godot_console --headless --path game --script res://scripts/tests_wrong.gd -- [SEED] [rules]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 4242
	var gen := Level0Gen.new(seed)
	if args.size() > 1:
		gen.forced_wrong = Array(String(args[1]).split(","))
	var counts := {"chunks": 0, "free_frames": 0, "floor_holes": 0, "cat": 0, "nobottle": 0, "nohandle": 0, "signs": 0, "blind": 0}
	var rules_seen := {}
	for cx in range(-6, 7):
		for cz in range(-6, 7):
			if OS.get_cmdline_user_args().size() > 2:
				print("chunk ", cx, ",", cz)
			var L := gen.generate(cx, cz)
			counts["chunks"] += 1
			for r in L.get("wrong", []):
				rules_seen[r] = rules_seen.get(r, 0) + 1
			counts["free_frames"] += L.get("free_frames", []).size()
			counts["floor_holes"] += L.get("floor_holes", []).size()
			if L.has("sign_variant") and L["exit_signs"].size() > 0:
				counts["signs"] += 1
			for pr in L["props"]:
				if String(pr[0]).begins_with("cat:"):
					counts["cat"] += 1
				if String(pr[0]).contains("nobottle"):
					counts["nobottle"] += 1
			for fd in L["fake_doors"]:
				if fd.size() > 5 and String(fd[5]).contains("nohandle"):
					counts["nohandle"] += 1
			for f in L["fixtures"]:
				if f.size() > 3 and String(f[3]) == "blind":
					counts["blind"] += 1
	print("rules per chunk: ", rules_seen)
	print("counts: ", counts)
	quit()
