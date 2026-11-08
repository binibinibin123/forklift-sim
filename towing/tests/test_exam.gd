extends SceneTree
## Headless: the demo driver must pass every licence's full exam, and the
## scoring rules must catch the basic faults.
## godot --headless --path . --script res://towing/tests/test_exam.gd [-- trace]

var fails := 0


func _init() -> void:
	var trace := "trace" in OS.get_cmdline_user_args()
	for k in ["small", "wrecker", "large"]:
		_run_demo(k, trace)
	_rules()
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _run_demo(k: String, trace: bool) -> void:
	var e := Exam.new(k)
	var log := []
	e.message.connect(func(t, _k): log.append("%6.1fs %s %s" % [e.t_total, t, str(e.last_hit) if "검지선" in t else ""]))
	var ap := TowAutopilot.new(e)
	e.start()
	var dt := 1.0 / 60.0
	var f: FileAccess
	if trace:
		f = FileAccess.open("user://trace_%s.csv" % k, FileAccess.WRITE)
		var geo := []
		for st in e.steps:
			var g := {"lines": [], "paint": [], "confirms": [], "asphalt": [], "demo": []}
			for l in st.lines:
				g.lines.append(Array(l).map(func(p): return [p.x, p.y]))
			for l in st.get("paint", []):
				g.paint.append(Array(l).map(func(p): return [p.x, p.y]))
			for c in st.get("confirms", []):
				g.confirms.append([[c.a.x, c.a.y], [c.b.x, c.b.y]])
			for r in st.get("asphalt", []):
				g.asphalt.append([r.position.x, r.position.y, r.size.x, r.size.y])
			for d in st.get("demo", []):
				g.demo.append(Array(d.path).map(func(p): return [p.x, p.y]))
			geo.append(g)
		var gf := FileAccess.open("user://geo_%s.json" % k, FileAccess.WRITE)
		gf.store_string(JSON.stringify(geo))
		gf.close()
	var n := 0
	while not e.done and e.t_total < 1500.0:
		ap.update(dt)
		e.update(dt)
		n += 1
		if f and n % 6 == 0:
			var ws := e.rig.wheels()
			var row := [e.index, e.rig.pos.x, e.rig.pos.y, e.rig.th, e.rig.phi, int(e.rig.coupled), e.rig.steer, e.rig.v]
			for w in ws:
				row.append_array([w.p.x, w.p.y])
			f.store_line(",".join(row.map(func(x): return str(x))))
	print("[%s] score %d passed %s time %.0fs dq='%s' step %d/%d" % [k, e.score, e.passed, e.t_total, e.disqualified, e.index + 1, e.steps.size()])
	for l in log:
		print("    ", l)
	_check(e.passed and e.score == 100, "%s demo passes with 100" % k)


func _rules() -> void:
	# standing still for 20 s at the start disqualifies
	var e := Exam.new("small")
	e.start()
	for i in 60 * 21:
		e.update(1.0 / 60.0)
	_check(e.done and e.disqualified != "", "no start in 20 s = 실격")
	# driving straight into the crank's first bend touches a line
	var e2 := Exam.new("small", "crank")
	e2.start()
	e2.rig.throttle = 0.6
	for i in 60 * 30:
		e2.update(1.0 / 60.0)
		if e2.done:
			break
	_check(e2.score < 100 or e2.disqualified != "", "driving straight through the crank is penalised")
	# large: any line touch is an immediate fail
	var e3 := Exam.new("large", "garage")
	e3.start()
	e3.rig.throttle = 0.8
	e3.rig.steer = 1.0
	for i in 60 * 40:
		e3.update(1.0 / 60.0)
		if e3.done:
			break
	_check(e3.done and not e3.passed, "large: line touch ends the exam")
	# wrong coupling order costs 10 points once
	var e4 := Exam.new("large", "couple")
	e4.start()
	e4.aligned = true
	e4.choose(e4.checklist[1])
	e4.choose(e4.checklist[2])
	_check(e4.score == 90, "wrong coupling order -10 once")
