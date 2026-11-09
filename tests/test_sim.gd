extends SceneTree
## 헤드리스 테스트: godot --headless --path . --script res://tests/test_sim.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	test_course()
	test_full_run()
	test_scoring_parts()
	test_drills()
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)


func test_course() -> void:
	print("course")
	var c := Course.load_default()
	check(c.inside(c.start_pos), "start position inside the course")
	check(c.zone_at(c.start_pos) == "park", "start in the parking area")
	check(c.zone_at(Vector2(0, c.drum_pos.y - 1.0)) == "work1", "drum side is work zone 1")
	check(c.zone_at(Vector2(c.unload_line_x + 0.5, c.center.y)) == "work2", "stub is work zone 2")
	check(c.zone_at(c.center) == "travel", "ring centre is the travel section")
	check(absf(c.r_out - 9.4 * c.D) < 0.001 and absf(c.r_in - 7.2 * c.D) < 0.001, "ring radii from the drawing")
	check(absf(c.box.size.y - 12.0 * c.D) < 0.001, "box 4.0+2.0+3.0+3.0 D")
	check(absf((c.box.end.y - c.start_line_y) - 6.0 * c.D) < 0.001, "start line 6.0 D below the loading line")
	check(absf((c.center.x - c.r_out - c.unload_line_x) - 2.2 * c.D) < 0.001, "stub 2.2 D")
	var total := (c.box.end.x - c.unload_line_x)
	check(absf(total - 23.4 * c.D) < 0.01, "overall 23.4 D (%.2f m)" % total)
	check(c.boundary_polylines().size() > 6, "edges built")
	check(not c.inside(c.center + Vector2(4, 4)), "islands are not drivable")


static func full_run(sim: Sim, ap: Autopilot) -> void:
	run_until(sim, ap, 99)


## Drives the whole course with the test driver; stops after stage `stop` (screenshots).
static func run_until(sim: Sim, ap: Autopilot, stop: int) -> void:
	var c := sim.course
	var reach := Sim.CARRIAGE + Sim.FORK_LEN - Sim.PALLET * 0.5
	sim.seatbelt = true
	sim.give_signal()
	sim.park_brake = false
	ap.set_fork(0.25, 0.0)
	if stop <= 1:
		return
	# 1) up to the drum, forks to the pallet openings, pick up
	ap.drive(Route.line_path(c.start_pos, Vector2(0, 10.6)), false, func(s): return s.pos.y >= 10.6, 1.0)
	ap.set_fork(c.drum_height + 0.04, 0.0)
	ap.drive(Route.line_path(Vector2(0, 10.6), Vector2(0, c.drum_pos.y - reach)), false,
		func(s): return s.pos.y >= c.drum_pos.y - reach, 0.4)
	ap.set_fork(c.drum_height + 0.13, 4.0)
	if stop <= 2:
		return
	# 2) back off and lower to 20~30 cm
	ap.drive(Route.line_path(Vector2(0, 13.6), Vector2(0, 9.5)), true, func(s): return s.pos.y <= 9.5, 0.6)
	ap.set_fork(0.25, 4.0)
	if stop <= 3:
		return
	# 3) forward course to the 표준 파렛트
	var ux := Route.unload_x(c)
	ap.drive(Route.forward(c, sim.pos.y), false, func(s): return s.pos.x <= ux + 0.02 and absf(s.pos.y - c.center.y) < 1.0 and s.pos.x < c.back_line_x, 1.2)
	if stop <= 4:
		return
	# 4) lower the moving pallet onto the 표준 파렛트
	ap.set_fork(Sim.PALLET_H + 0.04, 0.0)
	if stop <= 5:
		return
	# 5) back to the 후진선, neutral, forks down
	var tx := Route.touch_x(c)
	ap.drive(Route.line_path(Vector2(ux, c.center.y), Vector2(tx + 1.0, c.center.y)), true, func(s): return s.pos.x >= tx, 0.8)
	sim.gear = 0
	ap.set_fork(0.0, 0.0)
	if stop <= 6:
		return
	# 6) pick it up again
	ap.set_fork(Sim.PALLET_H + 0.045, 0.0)
	ap.drive(Route.line_path(Vector2(tx, c.center.y), Vector2(ux - 1.0, c.center.y)), false,
		func(s): return s.pos.x <= ux + 0.02, 0.4)
	ap.set_fork(0.30, 4.0)
	ap.drive(Route.line_path(Vector2(ux, c.center.y), Vector2(ux + 2.0, c.center.y)), true, func(s): return s.pos.x >= ux + 1.5, 0.5)
	ap.set_fork(0.25, 4.0)
	if stop <= 7:
		return
	# 7) reverse course back into the box
	ap.drive(Route.reverse(c, sim.pos.x), true, func(s): return s.pos.x >= -0.05 and s.pos.y <= 9.7 and s.heading > 0.0, 1.0)
	if stop <= 8:
		return
	# 8) onto the drum
	ap.set_fork(c.drum_height + 0.15, 4.0)
	ap.drive(Route.line_path(Vector2(0, sim.pos.y), Vector2(0, c.drum_pos.y)), false,
		func(s): return s.pallet_pos.y >= c.drum_pos.y - 0.02, 0.4)
	ap.set_fork(c.drum_height + 0.03, 0.0)
	if stop <= 9:
		return
	# 9) back over the finish line, forks onto the 주차보조선, park
	ap.drive(Route.line_path(Vector2(0, sim.pos.y), Vector2(0, 11.0)), true, func(s): return s.pos.y <= 11.0, 0.5)
	ap.set_fork(0.25, 0.0)
	ap.drive(Route.line_path(Vector2(0, 11.0), Vector2(0, c.start_pos.y - 1.0)), true, func(s): return s.pos.y <= c.start_pos.y, 1.0)
	sim.gear = 0
	ap.set_fork(0.0, -2.0)
	sim.park_brake = true
	ap._tick({})


func test_full_run() -> void:
	print("full run")
	var sim := Sim.new(null, true)
	var ap := Autopilot.new(sim)
	full_run(sim, ap)
	for f in sim.faults:
		print("    실격: ", f.msg, " @", f.pos)
	for d in sim.deductions:
		print("    감점: ", d.msg, " (", d.code, ")")
	print("    단계=%d 점수=%d 시간=%.1f초" % [sim.step, sim.score(), sim.t_exam])
	check(sim.faults.is_empty(), "no disqualification")
	check(sim.step == Sim.Step.PARKED, "parked at the end")
	check(sim.passed(), "passed")
	check(sim.t_exam < sim.course.time_limit, "inside 4:00")
	var f := FileAccess.open("user://autopilot_path.txt", FileAccess.WRITE)
	for p in ap.log_points:
		f.store_line("%f %f" % [p.x, p.y])


func test_scoring_parts() -> void:
	print("scoring parts")
	var sim := Sim.new(null, false)
	check(sim.score() == 100 and sim.part_score("load") == 45 and sim.part_score("unload") == 55, "starts at 45/55")
	sim.step = Sim.Step.LOADED
	sim._deduct("a", 5)
	sim.step = Sim.Step.UNLOADED
	sim._deduct("b", 5)
	check(sim.part_score("load") == 40 and sim.part_score("unload") == 50 and sim.score() == 90, "deductions go to the part of their step")


func test_drills() -> void:
	print("drills")
	var c := Course.load_default()
	for d in Drills.list(c):
		var sim := Sim.new(c, false)
		sim.start_drill(d)
		check(sim.step == d.step and sim.faults.is_empty(), "%s: start state" % d.id)
		for i in 60:
			sim.update(1.0 / 60.0, {})
		check(sim.faults.is_empty() and not sim.done, "%s: no fault when standing still" % d.id)
		check(c.inside(sim.pos), "%s: starts inside the course" % d.id)
	# touch drill: back to the 후진선, neutral, forks down
	var sim := Sim.new(c, false)
	sim.start_drill(Drills.by_id(c, "touch"))
	var ap := Autopilot.new(sim)
	var tx := Route.touch_x(c)
	ap.drive(Route.line_path(sim.pos, Vector2(tx + 1.0, c.center.y)), true, func(s): return s.pos.x >= tx, 0.8)
	sim.gear = 0
	ap.set_fork(0.0, 0.0)
	check(sim.step == Sim.Step.TOUCHED and sim.done and sim.faults.is_empty(), "touch drill completes")
	# park drill
	sim = Sim.new(c, false)
	sim.start_drill(Drills.by_id(c, "park"))
	ap = Autopilot.new(sim)
	ap.drive(Route.line_path(sim.pos, Vector2(0, c.start_pos.y - 1.0)), true, func(s): return s.pos.y <= c.start_pos.y, 1.0)
	sim.gear = 0
	ap.set_fork(0.0, -2.0)
	sim.park_brake = true
	ap._tick({})
	check(sim.step == Sim.Step.PARKED and sim.done and sim.faults.is_empty(), "park drill completes")
