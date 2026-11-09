extends SceneTree
## Headless: each graded limit fires at its boundary with the measured value
## and the limit recorded, every violation maps to a rulebook row, and the
## Korean and English tables carry the same keys.
## godot --headless --path . --audio-driver Dummy --script res://towing/tests/test_rules.gd

const DT := 1.0 / 60.0
var fails := 0


func _init() -> void:
	_start_window()
	_seatbelt()
	_time_limits()
	_line_touch()
	_jackknife()
	_coupling()
	_confirm_line()
	_off_course()
	_rows_and_text()
	_lang_parity()
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1


func _run(e: Exam, seconds: float) -> void:
	var t := 0.0
	while t < seconds and not e.done:
		e.update(DT)
		t += DT


func _last(e: Exam) -> Dictionary:
	if not e.dq_info.is_empty():
		return e.dq_info
	return e.deductions.back() if not e.deductions.is_empty() else {}


func _start_window() -> void:
	var e := Exam.new("small")
	e.start()
	_run(e, 19.9)
	_check(not e.done, "start: still waiting at 19.9 s")
	_run(e, 0.3)
	var v := e.dq_info
	_check(e.done and v.get("code", "") == "start_late", "start: disqualified just after 20 s")
	_check(float(v.get("measured", 0)) > 20.0 and float(v.get("limit", 0)) == 20.0 and v.get("unit", "") == "s", "start: measured %.2f s > limit 20 s" % float(v.get("measured", 0)))
	for k in ["wrecker", "large"]:
		var e2 := Exam.new(k)
		e2.start()
		_run(e2, 21.0)
		_check(e2.dq_info.get("code", "") == "start_late", "%s: same 20 s start rule" % k)


func _seatbelt() -> void:
	var e := Exam.new("small", "crank")
	e.start()
	e.rig.throttle = 0.6
	_run(e, 3.0)
	_check(e.dq_info.get("code", "") == "seatbelt", "seatbelt: moving off unbelted disqualifies")
	var e2 := Exam.new("small", "crank")
	e2.start()
	e2.seatbelt = true
	e2.rig.throttle = 0.6
	_run(e2, 1.0)
	_check(e2.dq_info.get("code", "") != "seatbelt", "seatbelt: belted start is fine")
	var e3 := Exam.new("small", "free")
	e3.start()
	e3.rig.throttle = 0.6
	_run(e3, 1.0)
	_check(e3.dq_info.is_empty(), "seatbelt: not graded in free practice")


func _time_limits() -> void:
	var want := {"small": 180.0, "wrecker": 180.0, "large": 300.0}
	for k in want:
		var e := Exam.new(k, "garage")
		e.start()
		e.seatbelt = true
		_check(is_equal_approx(e.limit, want[k]), "%s: turnaround limit %d s" % [k, int(want[k])])
		e.t_step = e.limit - 0.05
		e.update(DT)
		_check(e.deductions.is_empty(), "%s: no deduction right at the limit" % k)
		e.update(DT * 6.0)
		var v := _last(e)
		var pts := 20 if k == "large" else 10
		_check(v.get("code", "") == "time" and int(v.get("points", 0)) == pts, "%s: over time -%d" % [k, pts])
		_check(float(v.get("measured", 0)) > float(v.get("limit", 1e9)) and is_equal_approx(float(v.get("limit", 0)), want[k]), "%s: measured %.1f s > %.0f s" % [k, float(v.get("measured", 0)), float(v.get("limit", 0))])
		if k == "large":
			_check(e.done and not e.passed, "large: over time is an instant fail")
		else:
			e.t_step = e.limit + 0.01
			e.update(DT)
			_check(e.deductions.size() == 2, "%s: over time again 3 min later costs again" % k)


func _line_touch() -> void:
	for k in ["small", "large"]:
		var e := Exam.new(k, "crank" if k == "small" else "garage")
		e.start()
		e.seatbelt = true
		e.rig.throttle = 0.7
		e.rig.steer = 0.0 if k == "small" else 1.0
		var t := 0.0
		while t < 60.0 and e.deductions.is_empty() and e.dq_info.is_empty():
			e.update(DT)
			t += DT
		var v := _last(e)
		var pts := 20 if k == "large" else 10
		_check(v.get("code", "") == "line" and int(v.get("points", 0)) == pts, "%s: line touch -%d" % [k, pts])
		var gap: float = (v.get("a", Vector2.ZERO) as Vector2).distance_to(v.get("b", Vector2.ZERO))
		_check(float(v.get("measured", 99)) < float(v.get("limit", 0)) and absf(gap * 100.0 - float(v.measured)) < 0.5, "%s: tyre %.1f cm from the line < %.0f cm, measurement line matches" % [k, float(v.get("measured", 0)), float(v.get("limit", 0))])
		if k == "large":
			_check(e.done and not e.passed, "large: a line touch ends the exam")


func _jackknife() -> void:
	var e := Exam.new("large", "garage")
	e.start()
	e.seatbelt = true
	e.rig.reverse = true
	e.rig.phi = e.rig.th - deg_to_rad(80.0)
	e.rig.throttle = 0.6
	e.rig.steer = 0.0
	_run(e, 20.0)
	var v := e.dq_info
	_check(v.get("code", "") == "jackknife", "jackknife: folding past the limit disqualifies (got '%s')" % v.get("code", ""))
	_check(float(v.get("measured", 0)) >= 88.0 and is_equal_approx(float(v.get("limit", 0)), 88.0), "jackknife: measured %.0f° vs 88°" % float(v.get("measured", 0)))


func _coupling() -> void:
	var e := Exam.new("large", "couple")
	e.start()
	e.seatbelt = true
	e.aligned = true
	e.choose(e.checklist[1])
	var v := _last(e)
	_check(v.get("code", "") == "order" and int(v.points) == 10 and str(v.detail) != "", "order: -10 with picked vs correct step")
	var c := Exam.new("wrecker", "couple")
	c.start()
	c.seatbelt = true
	c.rig.reverse = true
	c.rig.throttle = 0.5
	c.rig.steer = 0.0
	_run(c, 40.0)
	var cv := c.dq_info
	_check(cv.get("code", "") == "collide" or cv.get("code", "") == "", "collide: reversing straight in either couples or collides")
	var d := Exam.new("wrecker", "couple")
	d.start()
	d.seatbelt = true
	# put the hitch 60 cm past the coupler
	var f := Vector2(cos(d.trailer_th), sin(d.trailer_th))
	d.rig.set_pose(d.rig.pos - f * (d.couple_error().along + 0.6), d.rig.th)
	d.update(DT)
	var dv := d.dq_info
	_check(dv.get("code", "") == "collide" and float(dv.get("measured", 0)) > 50.0, "collide: %.0f cm past contact > 50 cm" % float(dv.get("measured", 0)))


func _confirm_line() -> void:
	var e := Exam.new("large", "garage")
	e.start()
	e.seatbelt = true
	e.touched["B"] = true
	var f: Dictionary = e.step.finish
	var mid: Vector2 = (f.a + f.b) * 0.5
	e.rig.uncouple()
	e.rig.set_pose(mid + Vector2(0, e.rig.spec.L + 0.4), -PI / 2)
	e.rig.throttle = 0.5
	var t := 0.0
	while t < 5.0 and e.deductions.is_empty() and not e.done:
		e.update(DT)
		t += DT
	var v := _last(e)
	_check(v.get("code", "") == "confirm" and int(v.get("points", 0)) == 20, "large: check line A missed -20 (got '%s')" % v.get("code", ""))


func _off_course() -> void:
	var e := Exam.new("small", "crank")
	e.start()
	e.seatbelt = true
	var r: Rect2 = e.step.asphalt[0]
	e.rig.set_pose(r.end + Vector2(5, 5), 0.0)
	e.update(DT)
	var v := e.dq_info
	_check(v.get("code", "") == "off_course" and float(v.get("measured", 0)) > 0.0, "off course: tyre %.0f cm outside the paved area" % float(v.get("measured", 0)))


func _rows_and_text() -> void:
	for code in ["start_late", "seatbelt", "line", "time", "confirm", "jackknife", "order", "collide", "off_course", "yard_out"]:
		_check(not TowRules.row_for_code(code).is_empty(), "rulebook row for '%s'" % code)
	for k in ["small", "wrecker", "large"]:
		_check(TowRules.rows_for(k).size() >= 6, "%s: rulebook has its rows" % k)
	var v := {"code": "start_late", "dq": true, "text": "x", "measured": 23.0, "limit": 20.0, "unit": "s", "cmp": ">"}
	Lang.code = "ko"
	_check(TowRules.measure_text(v) == "23.0초 > 20초", "ko measure text: %s" % TowRules.measure_text(v))
	Lang.code = "en"
	_check(TowRules.measure_text(v) == "23.0 s > 20 s", "en measure text: %s" % TowRules.measure_text(v))
	_check("Annex 24" in TowRules.headline(v), "en headline cites Annex 24")
	Lang.code = "ko"


func _lang_parity() -> void:
	var ko: Array = TowLang.KO.keys()
	var en: Array = TowLang.EN.keys()
	ko.sort()
	en.sort()
	_check(ko == en, "TowLang: KO and EN have the same %d keys" % ko.size())
	var empty := 0
	for k in en:
		if str(TowLang.EN[k]).strip_edges() == "" or str(TowLang.KO[k]).strip_edges() == "":
			empty += 1
	_check(empty == 0, "TowLang: no empty text")
	# every literal key used in the towing scripts exists
	var missing := []
	var re := RegEx.create_from_string("\"(tow\\.[A-Za-z0-9_.]+[A-Za-z0-9_])\"")
	for path in _scripts("res://towing/scripts"):
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			var key := m.get_string(1)
			if not TowLang.KO.has(key):
				missing.append("%s in %s" % [key, path.get_file()])
	_check(missing.is_empty(), "every tow.* key used in scripts exists %s" % str(missing))
	# keys built at run time
	var dyn := []
	for k in ["small", "wrecker", "large"]:
		dyn.append_array(["tow.kind." + k, "tow.kind_desc." + k])
	for c in ["chase", "top", "driver"]:
		dyn.append("tow.cam." + c)
	for r in TowRules.ROWS:
		dyn.append_array(["tow.rd." + r.id, r.title, r.crit])
	var miss2 := dyn.filter(func(k): return not TowLang.KO.has(k))
	_check(miss2.is_empty(), "run-time keys exist %s" % str(miss2))
	# placeholders line up between languages
	var bad := []
	for k in ko:
		if str(TowLang.KO[k]).count("%") != str(TowLang.EN[k]).count("%"):
			bad.append(k)
	_check(bad.is_empty(), "same number of %% placeholders %s" % str(bad))


func _scripts(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd") and f != "tow_lang.gd":
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_scripts(dir + "/" + sub))
	return out
