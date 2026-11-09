extends SceneTree
## Translation table completeness: KO and EN carry the same keys with the same
## format placeholders, and every key the code asks for exists.
## godot --headless --path . --script res://tests/test_lang.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	var ko := Lang.table("ko")
	var en := Lang.table("en")
	var missing_en := ko.keys().filter(func(k): return not en.has(k))
	var missing_ko := en.keys().filter(func(k): return not ko.has(k))
	check(missing_en.is_empty(), "every Korean key has English %s" % str(missing_en.slice(0, 8)))
	check(missing_ko.is_empty(), "every English key has Korean %s" % str(missing_ko.slice(0, 8)))
	var re := RegEx.create_from_string("%[-+0-9.]*[dsf]")
	var bad := []
	for k in ko:
		if en.has(k) and re.search_all(ko[k]).size() != re.search_all(en[k]).size():
			bad.append(k)
	check(bad.is_empty(), "same placeholders in both languages %s" % str(bad))
	var empty := ko.keys().filter(func(k): return str(ko[k]) == "" or str(en.get(k, "")) == "")
	check(empty.is_empty(), "no empty text %s" % str(empty))

	# literal keys in code
	var used := {}
	var lit := RegEx.create_from_string("Lang\\.t\\(\"([a-z0-9_.°]+)\"")
	for dir in ["res://scripts", "res://towing/scripts", "res://towing/scripts/ui"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd") or f == "lang.gd":
				continue
			var src := FileAccess.get_file_as_string(dir + "/" + f)
			for m in lit.search_all(src):
				var key := m.get_string(1)
				if not key.ends_with("."):
					used[key] = f
	var absent := used.keys().filter(func(k): return not ko.has(k))
	check(absent.is_empty(), "%d literal keys in code all exist %s" % [used.size(), str(absent)])

	# keys built at run time
	var dyn := []
	for i in 9:
		dyn.append("step.%d" % i)
	for i in 4:
		dyn.append("cam.%d" % i)
	for i in range(1, 9):
		dyn.append("order.%d" % i)
	for r in ExamRules.ROWS:
		dyn.append("rule." + r.id)
		if r.checked:
			dyn.append("rdrill." + r.id)
	for code in ExamRules.all_codes():
		dyn.append("f." + code)
	for code in ExamRules.DEDUCTIONS:
		dyn.append("d." + code)
		dyn.append("part." + ExamRules.DEDUCTION_PART[code])
	for d in Drills.list(Course.load_default()):
		for s in ["", ".d", ".tip"]:
			dyn.append("drill." + d.id + s)
	for k in ["work1", "work2", "park", "travel"]:
		dyn.append("zone." + k)
	for k in ["f", "n", "r"]:
		dyn.append("gear." + k)
	for k in ["cm", "s", "m", "°"]:
		dyn.append("unit." + k)
	for k in ["dq", "ded", "plan"]:
		dyn.append("rules.tab." + k)
	for k in ["drills", "rules", "records", "settings"]:
		dyn.append("screen." + k)
	for k in ["exam", "practice", "drill"]:
		dyn.append("mode." + k)
	for k in ["load", "unload"]:
		dyn.append("sheet.part." + k)
	for k in ["date", "mode", "result", "score", "load", "unload", "time", "note"]:
		dyn.append("rec." + k)
	var absent2 := dyn.filter(func(k): return not ko.has(k))
	check(absent2.is_empty(), "%d run-time keys all exist %s" % [dyn.size(), str(absent2)])
	print("  %d keys per language" % ko.size())
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
