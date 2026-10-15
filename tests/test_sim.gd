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
	test_line_touch()
	test_fork_too_high()
	test_missed_pallet()
	test_seatbelt()
	test_timeout()
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)


func test_course() -> void:
	print("course")
	var c := Course.load_default()
	check(c.inside(c.start_pos), "출발 위치가 코스 안")
	check(c.zone_at(c.drum_pos) == "load", "드럼은 상차 구역")
	check(c.zone_at(c.unload_target) == "unload", "하역 표시는 하역 구역")
	check(c.boundary_segments().size() > 6, "경계선 생성")


static func full_run(sim: Sim, ap: Autopilot) -> void:
	run_until(sim, ap, 99)


## 코스 전체를 자동 운전으로 돈다. stop 단계에서 멈춤(스크린샷용)
static func run_until(sim: Sim, ap: Autopilot, stop: int) -> void:
	var c := sim.course
	sim.seatbelt = true
	sim.give_signal()
	sim.park_brake = false
	ap.set_fork(0.25, 0.0)
	var lane_y := 6.4
	var col_x := -6.6
	var top_y := 13.6
	var reach := Sim.CARRIAGE + Sim.FORK_LEN - Sim.PALLET * 0.5   # 앞축 → 팔레트 중심(완전 삽입)
	if stop <= 1:
		return
	# 1) 드럼까지 전진, 작업 높이로
	ap.drive(Autopilot.rounded([c.start_pos, Vector2(0, 6.8)], 0.5), false, func(s): return s.pos.y >= 6.8, 1.0)
	ap.set_fork(c.drum_height + 0.04, 0.0)
	ap.drive(Autopilot.rounded([Vector2(0, 6.0), Vector2(0, c.drum_pos.y - reach)], 0.5), false,
		func(s): return s.pos.y >= c.drum_pos.y - reach, 0.4)
	ap.set_fork(c.drum_height + 0.13, 4.0)
	if stop <= 2:
		return
	# 2) 조금 후진 후 주행 높이로
	ap.drive(Autopilot.rounded([Vector2(0, 9), Vector2(0, 5.6)], 0.5), true, func(s): return s.pos.y <= 5.6, 0.6)
	ap.set_fork(0.25, 4.0)
	if stop <= 3:
		return
	# 3) 전진 코스
	var fwd := Autopilot.rounded([Vector2(0, 5.6), Vector2(0, lane_y), Vector2(col_x, lane_y), Vector2(col_x, top_y), Vector2(c.unload_target.x - reach, top_y)], 1.0)
	ap.drive(fwd, false, func(s): return s.pos.x >= c.unload_target.x - reach - 0.05 and s.pos.y > 12, 1.2)
	if stop <= 4:
		return
	# 4) 하역
	ap.set_fork(0.04, 0.0)
	if stop <= 5:
		return
	# 5) 후진선까지 후진
	var bx := c.back_line_x - (Sim.CARRIAGE + Sim.FORK_LEN * 0.5)
	ap.drive(Autopilot.rounded([Vector2(c.unload_target.x, top_y), Vector2(bx - 1, top_y)], 0.5), true, func(s): return s.pos.x <= bx, 0.8)
	sim.gear = 0
	ap.set_fork(0.0, 0.0)
	if OS.has_environment("SIM_DEBUG"): print("after touch lift=", sim.lift, " step=", sim.step, " gt=", sim._ground_touching, " mid=", sim.fork_mid(), " v=", sim.speed)
	if stop <= 6:
		return
	# 6) 다시 상차
	ap.set_fork(0.045, 0.0)
	ap.drive(Autopilot.rounded([Vector2(bx, top_y), Vector2(c.unload_target.x - reach, top_y)], 0.5), false,
		func(s): return s.pos.x >= c.unload_target.x - reach - 0.02, 0.4)
	ap.set_fork(0.16, 4.0)
	ap.set_fork(0.25, 4.0)
	if stop <= 7:
		return
	# 7) 후진 코스
	var rev := Autopilot.rounded([Vector2(c.unload_target.x - reach, top_y), Vector2(col_x, top_y), Vector2(col_x, lane_y), Vector2(0.0, lane_y), Vector2(0.0, 4.6)], 1.0)
	ap.drive(rev, true, func(s): return s.pos.y <= 4.6 and s.pos.x > -1.0, 1.0)
	if stop <= 8:
		return
	# 8) 드럼에 내려놓기
	ap.set_fork(c.drum_height + 0.15, 4.0)
	ap.drive(Autopilot.rounded([Vector2(0, 4.6), Vector2(0, c.drum_pos.y - reach)], 0.5), false,
		func(s): return s.pos.y >= c.drum_pos.y - reach - 0.03, 0.4)
	ap.set_fork(c.drum_height + 0.03, 0.0)
	if stop <= 9:
		return
	# 9) 출발선 뒤로 후진, 주차
	ap.drive(Autopilot.rounded([Vector2(0, 8), Vector2(0, 7.0)], 0.5), true, func(s): return s.pos.y <= 7.0, 0.5)
	ap.set_fork(0.25, 0.0)
	ap.drive(Autopilot.rounded([Vector2(0, 7), Vector2(0, 1.9)], 0.5), true, func(s): return s.pos.y <= 2.2, 1.0)
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
	check(sim.faults.is_empty(), "실격 없음")
	check(sim.step == Sim.Step.PARKED, "주차까지 완료")
	check(sim.passed(), "합격")
	check(sim.t_exam < sim.course.time_limit, "제한 시간 안")
	var f := FileAccess.open("user://autopilot_path.txt", FileAccess.WRITE)
	for p in ap.log_points:
		f.store_line("%f %f" % [p.x, p.y])


func test_line_touch() -> void:
	print("line touch")
	var sim := Sim.new(null, true)
	sim.seatbelt = true
	sim.give_signal()
	sim.park_brake = false
	sim.lift = 0.25
	sim.gear = 1
	for i in 600:
		sim.update(1.0 / 60, {throttle = 1.0, steer = -1.0})
	check(sim.faults.size() > 0 and sim.faults[0].code == "line", "핸들을 꺾고 계속 가면 선 접촉 실격")


func test_fork_too_high() -> void:
	print("fork high")
	var sim := Sim.new(null, true)
	sim.step = Sim.Step.LOADED
	sim.pos = Vector2(-4, 6.4)
	sim.heading = PI
	sim.lift = 0.8
	sim.speed = 1.0
	sim.gear = 1
	sim.park_brake = false
	sim.update(1.0 / 60, {throttle = 0.5})
	check(sim.faults.size() > 0 and sim.faults[0].code == "fork_high", "주행 구간 포크 50cm 초과 실격")


func test_missed_pallet() -> void:
	print("pallet push")
	var sim := Sim.new(null, true)
	sim.seatbelt = true
	sim.give_signal()
	sim.park_brake = false
	sim.lift = 0.6     # 드럼 높이보다 낮게 들이받음
	sim.gear = 1
	for i in 900:
		sim.update(1.0 / 60, {throttle = 0.5})
		if sim.done:
			break
	check(sim.faults.size() > 0 and sim.faults[0].code in ["drum_touch", "pallet_push"], "낮은 포크로 드럼·팔레트 접촉 실격")


func test_seatbelt() -> void:
	print("seatbelt")
	var sim := Sim.new(null, true)
	sim.give_signal()
	sim.park_brake = false
	sim.gear = 1
	for i in 60:
		sim.update(1.0 / 60, {throttle = 1.0})
	check(sim.faults.size() > 0 and sim.faults[0].code == "seatbelt", "안전벨트 없이 출발 실격")


func test_timeout() -> void:
	print("timeout")
	var sim := Sim.new(null, false)
	sim.give_signal()
	for i in 61 * 10:
		sim.update(0.1, {})
	check(sim.faults.size() > 0 and sim.faults[0].code == "start_late", "1분 안에 출발 못하면 실격")
	check(not sim.done, "연습 모드는 실격이어도 계속")
