class_name Exam
extends RefCounted
## Runs one licence's exam (or a single practice course) over a Rig and scores
## it: 100 points, pass at 90. Rules per licence are in Courses' header.

signal message(text: String, kind: String)   # kind: info / good / bad
signal step_started(index: int)
signal checklist_ready(options: Array)
signal finished(passed: bool)

const PASS := 90
const START_GRACE := 20.0

var kind := "small"
var steps: Array = []
var practice := false
var rig: Rig

var index := 0
var step: Dictionary
var score := 100
var deductions: Array = []      # [{text, points}]
var disqualified := ""          # reason, empty when not
var done := false
var passed := false

var t_step := 0.0               # time spent in this step
var t_total := 0.0
var limit := 180.0
var overtime_count := 0
var moved := false
var t_wait := 0.0               # seconds since the exam began without moving
var touched := {}               # confirm id -> true
var touching := false
var last_hit := {}              # the tyre that touched a line last (debug, replays)
var finished_step := false

# coupling state
var trailer_parked := false     # trailer/towed car sits on the ground, unhitched
var trailer_pos := Vector2.ZERO # its hitch point
var trailer_th := 0.0
var aligned := false            # coupling: in position, waiting for the checklist
var checklist: Array = []
var check_next := 0
var check_mistake := false
var pulled_away := false
var pull_from := Vector2.ZERO


func _init(k: String, only_step: String = "") -> void:
	kind = k
	steps = Courses.exam_steps(k)
	if only_step != "":
		practice = true
		steps = [Courses.step_by_id(k, only_step)]
	rig = Rig.new(k)


func start() -> void:
	index = 0
	_begin_step()


func is_large() -> bool:
	return kind == "large"


func _begin_step() -> void:
	step = steps[index]
	t_step = 0.0
	limit = step.time_limit
	overtime_count = 0
	touched = {}
	touching = false
	finished_step = false
	aligned = false
	check_next = 0
	check_mistake = false
	pulled_away = false
	checklist = step.get("checklist", [])
	var st: Dictionary = step.start
	match step.type:
		"couple":
			trailer_parked = true
			trailer_pos = step.trailer_pose.pos
			trailer_th = step.trailer_pose.th
			rig.uncouple()
			rig.set_pose(st.pos, st.th)
		"uncouple":
			trailer_parked = false
			rig.couple(st.th)
			rig.set_pose(st.pos, st.th)
		_:
			if step.get("solo", false):
				trailer_parked = false
				rig.uncouple()
			else:
				trailer_parked = false
				rig.couple(st.th)
			rig.set_pose(st.pos, st.th)
	rig.steer = 0.0
	rig.throttle = 0.0
	rig.brake = 0.0
	rig.reverse = step.type == "couple"
	step_started.emit(index)


func remaining() -> float:
	return limit - t_step


func update(dt: float) -> void:
	if done:
		return
	var before := rig.pos
	var before_wheels := rig.wheels()
	rig.step(dt)
	t_step += dt
	t_total += dt
	if absf(rig.v) > 0.05:
		moved = true
	if not moved and index == 0 and not practice:
		t_wait += dt
		if t_wait > START_GRACE:
			_disqualify("20초 안에 출발하지 않았어요")
			return
	if rig.jackknifed:
		_disqualify("트랙터와 트레일러가 예각으로 꺾였어요" if is_large() else "차와 트레일러가 너무 꺾였어요 (잭나이프)")
		return
	_check_time()
	if done:
		return
	match step.type:
		"course":
			_update_course(before, before_wheels)
		"couple":
			_update_couple()
		"uncouple":
			_update_uncouple()


func _check_time() -> void:
	if t_step <= limit:
		return
	overtime_count += 1
	if is_large():
		_deduct(20, "%s 시간 초과" % step.title)
		limit += 1e9
	else:
		_deduct(10, "%s 시간 초과" % step.title)
		limit += 180.0
		message.emit("3분이 더 주어져요", "info")


func _deduct(points: int, text: String) -> void:
	score -= points
	deductions.append({"text": text, "points": points})
	message.emit("%s  -%d" % [text, points], "bad")
	if is_large() and points >= 20:
		_end(false, "")


func _disqualify(reason: String) -> void:
	disqualified = reason
	message.emit("실격: " + reason, "bad")
	_end(false, reason)


func _end(ok: bool, _reason: String) -> void:
	if done:
		return
	done = true
	rig.throttle = 0.0
	rig.brake = 1.0
	passed = ok and score >= PASS and disqualified == ""
	finished.emit(passed)


func _next_step() -> void:
	if index + 1 >= steps.size():
		_end(true, "")
		return
	message.emit("%s 통과" % step.title, "good")
	index += 1
	_begin_step()


# ---------------------------------------------------------------- course

func _update_course(before: Vector2, before_wheels: Array) -> void:
	var wheels := rig.wheels()
	# detection lines: one deduction per contact
	var hit := false
	for w in wheels:
		if _near_lines(w.p, step.lines):
			hit = true
			last_hit = w
			break
	if hit and not touching:
		touching = true
		if is_large():
			_deduct(20, "검지선 접촉")
			return
		_deduct(10, "검지선 접촉 (탈선)")
	elif not hit:
		touching = false
	# off course: the rig strays far outside the lines
	if _far_off(wheels):
		_disqualify("코스를 벗어났어요")
		return
	# confirm lines
	for c in step.confirms:
		if touched.has(c.id):
			continue
		if c.id == "B" and step.confirms.size() > 1 and not touched.has("A"):
			continue
		for w in _wheels_for(wheels, c.who):
			if _seg_dist(w.p, c.a, c.b) < Courses.LINE_HIT + 0.1:
				touched[c.id] = true
				message.emit("%s 접촉" % c.label, "good")
				break
	# finish
	var f: Dictionary = step.finish
	if f.has("after") and not touched.has(f.after):
		return
	var p_now := _finish_point(f.who)
	var p_before := _finish_point_from(f.who, before, before_wheels)
	if _crossed(p_before, p_now, f.a, f.b, f.dir):
		for c in step.confirms:
			if not touched.has(c.id):
				if is_large():
					_deduct(20, "%s 미접촉" % c.label)
				else:
					_disqualify("%s을 밟지 않았어요 (과제 미이행)" % c.label)
				return
		_next_step()


func _near_lines(p: Vector2, lines: Array) -> bool:
	for l in lines:
		for i in l.size() - 1:
			if _seg_dist(p, l[i], l[i + 1]) < Courses.LINE_HIT:
				return true
	return false


func _far_off(wheels: Array) -> bool:
	# a tyre more than 2.5 m past the nearest line, outside the paved area
	for w in wheels:
		var inside := false
		for r in step.asphalt:
			if r.has_point(w.p):
				inside = true
		if not inside:
			return true
	return false


func _wheels_for(wheels: Array, who: String) -> Array:
	var out := []
	for w in wheels:
		match who:
			"tractor_front":
				if w.unit == "tractor" and w.axle == "front":
					out.append(w)
			"tractor_rear":
				if w.unit == "tractor" and w.axle == "rear":
					out.append(w)
			"trailer_rear":
				if w.unit == "trailer":
					out.append(w)
	return out


func _finish_point(who: String) -> Vector2:
	return _finish_point_from(who, rig.pos, rig.wheels())


func _finish_point_from(who: String, axle: Vector2, wheels: Array) -> Vector2:
	match who:
		"last":   # the rearmost axle of the whole rig
			var ws := _wheels_for(wheels, "trailer_rear")
			if ws.is_empty():
				ws = _wheels_for(wheels, "tractor_rear")
			var s := Vector2.ZERO
			for w in ws:
				s += w.p
			return s / ws.size()
		"tractor_front_axle":
			var ws2 := _wheels_for(wheels, "tractor_front")
			return (ws2[0].p + ws2[1].p) * 0.5
	return axle


static func _crossed(p0: Vector2, p1: Vector2, a: Vector2, b: Vector2, dir: Vector2) -> bool:
	if (p1 - p0).dot(dir) <= 0.0:
		return false
	var s0 := (b - a).cross(p0 - a)
	var s1 := (b - a).cross(p1 - a)
	if signf(s0) == signf(s1):
		return false
	# within the segment span
	var t := (p1 - a).dot(b - a) / (b - a).length_squared()
	return t >= -0.1 and t <= 1.1


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---------------------------------------------------------------- coupling

## Where the tractor's hitch must meet the parked unit.
func coupler_point() -> Vector2:
	return trailer_pos


func couple_error() -> Dictionary:
	var h := rig.hitch()
	var f := Vector2(cos(trailer_th), sin(trailer_th))
	var d := h - trailer_pos
	return {"along": d.dot(f), "side": d.dot(Vector2(-f.y, f.x)), "angle": rad_to_deg(wrapf(rig.th - trailer_th, -PI, PI))}


func _update_couple() -> void:
	var e := couple_error()
	if aligned:
		rig.v = 0.0
		return
	if e.along < -0.5:
		_disqualify("피견인차와 충돌했어요")
		return
	# far past the sides counts as leaving the yard
	if absf(e.side) > 4.0 and e.along < 6.0:
		_disqualify("연결 구역을 벗어났어요")
		return
	if absf(e.along) < 0.3 and absf(e.side) < 0.35 and absf(e.angle) < 8.0 and absf(rig.v) < 0.25:
		aligned = true
		rig.v = 0.0
		rig.throttle = 0.0
		message.emit("위치가 맞았어요. 연결 순서를 고르세요", "good")
		checklist_ready.emit(checklist)


## The user (or demo) picks the next coupling action.
func choose(item: String) -> bool:
	if check_next >= checklist.size():
		return false
	if item == checklist[check_next]:
		check_next += 1
		if check_next >= checklist.size():
			_checklist_done()
		return true
	if not check_mistake:
		check_mistake = true
		_deduct(10, "%s 순서 미숙" % step.title)
	message.emit("다음 순서: " + checklist[check_next], "info")
	return false


func _checklist_done() -> void:
	if step.type == "couple":
		trailer_parked = false
		rig.couple(trailer_th)
		aligned = false
		message.emit("연결 완료", "good")
		_next_step()
	else:
		trailer_parked = true
		trailer_pos = rig.hitch()
		trailer_th = rig.phi
		rig.uncouple()
		pull_from = rig.pos
		aligned = false
		pulled_away = true
		rig.reverse = false
		message.emit("분리 완료. 앞으로 빠져나오세요", "good")


func _update_uncouple() -> void:
	if pulled_away:
		if rig.pos.distance_to(pull_from) > 4.0:
			_next_step()
		return
	if aligned:
		rig.v = 0.0
		return
	if absf(rig.v) < 0.05 and rig.throttle < 0.01 and _rig_in_zone():
		aligned = true
		message.emit("주차 구역에 섰어요. 분리 순서를 고르세요", "good")
		checklist_ready.emit(checklist)


func _rig_in_zone() -> bool:
	var z: PackedVector2Array = step.zone
	for p in rig.tractor_corners():
		if not Geometry2D.is_point_in_polygon(p, z):
			return false
	if rig.coupled:
		for p in rig.trailer_corners():
			if not Geometry2D.is_point_in_polygon(p, z):
				return false
	return true


func progress_text() -> String:
	if practice:
		return step.title
	return "%d/%d  %s" % [index + 1, steps.size(), step.title]
