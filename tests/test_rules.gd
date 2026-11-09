extends SceneTree
## Forklift disqualification rules, one by one, at their limits; exam timer; drill for every rule row.
## godot --headless --path . --script res://tests/test_rules.gd

var fails := 0
var c: Course


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	c = Course.load_default()
	test_limits()
	test_timer()
	test_rule_drills()
	test_rows()
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)


func _drill(id: String) -> Sim:
	var sim := Sim.new(c, true)
	sim.start_drill(Drills.rule_drill(c, id))
	return sim


func _run(sim: Sim, inp: Dictionary, secs: float, gear := 0) -> void:
	sim.gear = gear
	for i in int(secs * 60):
		sim.update(1.0 / 60.0, inp)
		if sim.done:
			return


func _code(sim: Sim) -> String:
	return sim.faults[0].code if not sim.faults.is_empty() else ""


func test_limits() -> void:
	print("limits")
	# (14) fork height in the travel section: 50 cm
	var d := Drills.rule_drill(c, "r14")
	for h in [0.49, 0.51]:
		var sim := Sim.new(c, true)
		sim.start_drill(d)
		sim.lift = h
		sim.update(1.0 / 60.0, {})
		check((_code(sim) == "fork_high") == (h > 0.5), "fork %d cm in the travel section -> %s" % [roundi(h * 100), _code(sim)])
	# same height inside work zone 1 is allowed
	var sim2 := Sim.new(c, true)
	sim2.start_drill(Drills.by_id(c, "load"))
	sim2.lift = 0.9
	sim2.update(1.0 / 60.0, {})
	check(sim2.faults.is_empty(), "fork 90 cm inside work zone 1 is allowed")
	# (15) offset on the 표준 파렛트: 20 cm in either direction
	var g := c.guide_pos
	check(Sim.axis_offset(g + Vector2(0.19, 0), 0.0, g, 0.0) <= Sim.OFFSET_LIMIT, "19 cm along is inside the limit")
	check(Sim.axis_offset(g + Vector2(0, 0.21), 0.0, g, 0.0) > Sim.OFFSET_LIMIT, "21 cm across is over the limit")
	check(Sim.axis_offset(g, PI / 2, g, 0.0) < 0.001, "a quarter-turned square pallet sits in place")
	# (4) start window 60 s after the whistle
	for t in [59.9, 60.1]:
		var s := Sim.new(c, true)
		s.give_signal()
		s.t_signal = t - 0.05
		s.update(0.05, {})
		check((_code(s) == "start_late") == (t > 60.0), "%.1f s without crossing the start line -> %s" % [t, _code(s)])
	# (2) 4:00 from the front wheels over the start line
	for t in [239.9, 240.1]:
		var s := Sim.new(c, true)
		s.start_drill(Drills.by_id(c, "forward"))
		s.exam = true
		s.t_exam = t - 0.05
		s.update(0.05, {})
		check((_code(s) == "timeout") == (t > 240.0), "%.1f s on the clock -> %s" % [t, _code(s)])
	# measured values are recorded
	var s3 := _drill("r14")
	_run(s3, {lift = 1.0}, 2.0)
	check(_code(s3) == "fork_high" and s3.faults[0].val > 50.0 and s3.faults[0].lim == 50.0, "fork_high records %.1f cm vs 50" % (s3.faults[0].val if not s3.faults.is_empty() else -1.0))
	check(ExamRules.measured(s3.faults[0]) != "", "measured line: " + ExamRules.measured(s3.faults[0]))


func test_timer() -> void:
	print("timer")
	var sim := Sim.new(c, true)
	sim.seatbelt = true
	sim.park_brake = false
	sim.lift = 0.25
	sim.give_signal()
	check(not sim.running, "clock waits for the front wheels")
	for i in 600:
		_run(sim, {throttle = 0.6}, 0.1, 1)
		if sim.running:
			break
	var crossed := sim.pos.y >= c.start_line_y
	check(crossed == sim.running, "clock runs once the front axle is over the start line (y %.2f)" % sim.pos.y)
	var before := sim.t_exam
	_run(sim, {brake = 1.0}, 1.0, 0)
	check(absf(sim.t_exam - before - 1.0) < 0.05, "clock counts while standing")
	check(sim.t_signal < 60.0, "start window stops counting after the start")


const DRIVE := {
	"r2": [{}, 20.0, 0],
	"r3": [{throttle = 0.7}, 25.0, 1],
	"r4": [{}, 15.0, 0],
	"r6": [{throttle = 0.6}, 8.0, 1],
	"r7": [{throttle = 0.6}, 10.0, 1],
	"r8": [{throttle = 0.25}, 10.0, 1],
	"r9": [{throttle = 0.4}, 8.0, 1],
	"r10": [{throttle = 0.4}, 8.0, 1],
	"r11": [{throttle = 0.5}, 8.0, 1],
	"r12": [{lift = -1.0}, 4.0, 0],
	"r13": [{lift = -1.0}, 4.0, 0],
	"r14": [{lift = 1.0}, 4.0, 0],
	"r15": [{lift = -1.0}, 4.0, 0],
	"r16": [{throttle = 0.3, steer = 1.0}, 8.0, -1],
	"r17": [{throttle = 0.3}, 8.0, 1],
	"r18": [{lift = 1.0}, 3.0, 0],
}


func test_rule_drills() -> void:
	print("rule drills")
	for r in ExamRules.ROWS:
		if not r.checked:
			continue
		var d := Drills.rule_drill(c, r.id)
		check(not d.is_empty(), "%s has a drill" % r.id)
		if d.is_empty():
			continue
		var sim := Sim.new(c, true)
		sim.start_drill(d)
		check(sim.faults.is_empty(), "%s: clean start" % r.id)
		var how: Array = DRIVE.get(r.id, [{}, 5.0, 0])
		_run(sim, how[0], how[1], how[2])
		var code := _code(sim)
		check(code in r.codes, "%s: the violation happens -> %s" % [r.id, code])
		if code != "":
			var m := ExamRules.measured(sim.faults[0])
			print("      ", Lang.t("f." + code), "  ", m, "  ", ExamRules.cite(code))


func test_rows() -> void:
	print("rows")
	var seen := {}
	for r in ExamRules.ROWS:
		check(Lang.has("rule." + r.id), "%s has text" % r.id)
		for code in r.codes:
			seen[code] = true
			check(Lang.has("f." + code), "fault %s has text" % code)
	for code in ExamRules.DEDUCTIONS:
		check(Lang.has("d." + code), "deduction %s has text" % code)
	check(ExamRules.row_of("fork_high").n == 14, "fork_high is item (14)")
