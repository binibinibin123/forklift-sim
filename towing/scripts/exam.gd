class_name Exam
extends RefCounted
## Runs one licence's exam (or a single practice course) over a Rig and scores
## it: 100 points, pass at 90. Rules per licence are in Courses' header.

signal message(text: String, kind: String)   # kind: info / good / bad
signal step_started(index: int)
signal checklist_ready(options: Array)
signal finished(passed: bool)
## Every deduction or disqualification with what was measured at that moment:
## {code, dq, points, text, measured, limit, unit, cmp, detail, t, step, a, b, kind}
## a/b are ground points for the measurement line (equal when there is none).
signal violation(v: Dictionary)

const PASS := 90
const START_GRACE := 20.0

var kind := "small"
var steps: Array = []
var practice := false
var rig: Rig

var index := 0
var step: Dictionary
var score := 100
var deductions: Array = []      # violations (see `violation`): text, points, code, measured, limit...
var disqualified := ""          # reason, empty when not
var dq_info := {}               # the disqualifying violation (see `violation`)
var seatbelt := false           # 좌석안전띠; the demo driver buckles up
var confirm_min := {}           # confirm id -> {d, a, b}: closest approach so far
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
	confirm_min = {}
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
		if not seatbelt and not step.get("free_run", false):
			_disqualify(Lang.t("tow.ex.belt"), {"code": "seatbelt", "detail": Lang.t("tow.m.belt", [rig.speed_kmh()]), "a": rig.pos, "b": rig.pos})
			return
	if not moved and index == 0 and not practice:
		t_wait += dt
		if t_wait > START_GRACE:
			_disqualify(Lang.t("tow.ex.start_late"), {"code": "start_late", "measured": t_wait, "limit": START_GRACE, "unit": "s", "cmp": ">", "a": rig.pos, "b": rig.pos})
			return
	if rig.jackknifed:
		var deg := absf(rad_to_deg(rig.beta()))
		_disqualify(Lang.t("tow.ex.jack_large") if is_large() else Lang.t("tow.ex.jack"), {"code": "jackknife", "measured": deg, "limit": rad_to_deg(Rig.JACKKNIFE), "unit": "deg", "cmp": ">", "a": rig.hitch(), "b": rig.trailer_axle()})
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
	var info := {"code": "time", "measured": t_step, "limit": limit, "unit": "s", "cmp": ">", "a": rig.pos, "b": rig.pos}
	if is_large():
		_deduct(20, Lang.t("tow.ex.time", [step.title]), info)
		limit += 1e9
	else:
		_deduct(10, Lang.t("tow.ex.time", [step.title]), info)
		limit += 180.0
		message.emit(Lang.t("tow.ex.more_time"), "info")


## info: code, measured, limit, unit, cmp, detail, a, b (see `violation`)
func _deduct(points: int, text: String, info := {}) -> void:
	score -= points
	var v := _violation(false, points, text, info)
	deductions.append(v)
	message.emit("%s  -%d" % [text, points], "bad")
	violation.emit(v)
	if is_large() and points >= 20:
		_end(false, "")


func _disqualify(reason: String, info := {}) -> void:
	disqualified = reason
	dq_info = _violation(true, 0, reason, info)
	message.emit(Lang.t("tow.ex.dq_prefix") + reason, "bad")
	violation.emit(dq_info)
	_end(false, reason)


func _violation(dq: bool, points: int, text: String, info: Dictionary) -> Dictionary:
	var v := {"code": "", "dq": dq, "points": points, "text": text, "measured": -1.0, "limit": -1.0, "unit": "", "cmp": "",
		"detail": "", "t": t_total, "step": index, "a": rig.pos, "b": rig.pos, "kind": kind}
	v.merge(info, true)
	return v


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
	message.emit(Lang.t("tow.ex.step_pass", [step.title]), "good")
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
		var near := nearest_line(last_hit.p, step.lines)
		var info := {"code": "line", "measured": float(near.d) * 100.0, "limit": Courses.LINE_HIT * 100.0, "unit": "cm", "cmp": "<", "a": last_hit.p, "b": near.q}
		if is_large():
			_deduct(20, Lang.t("tow.ex.line"), info)
			return
		_deduct(10, Lang.t("tow.ex.line_small"), info)
	elif not hit:
		touching = false
	# off course: the rig strays far outside the lines
	var off := _off_wheel(wheels)
	if not off.is_empty():
		_disqualify(Lang.t("tow.ex.off"), {"code": "off_course", "measured": float(off.d) * 100.0, "limit": 0.0, "unit": "cm", "cmp": ">", "a": off.p, "b": off.q})
		return
	# confirm lines
	for c in step.confirms:
		if touched.has(c.id):
			continue
		if c.id == "B" and step.confirms.size() > 1 and not touched.has("A"):
			continue
		for w in _wheels_for(wheels, c.who):
			var dd := _seg_dist(w.p, c.a, c.b)
			if not confirm_min.has(c.id) or dd < float(confirm_min[c.id].d):
				confirm_min[c.id] = {"d": dd, "a": w.p, "b": _seg_closest(w.p, c.a, c.b)}
			if dd < Courses.LINE_HIT + 0.1:
				touched[c.id] = true
				message.emit(Lang.t("tow.ex.confirm_ok", [c.label]), "good")
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
				var m: Dictionary = confirm_min.get(c.id, {"d": -1.0, "a": c.a, "b": c.b})
				var info := {"code": "confirm", "measured": float(m.d) * 100.0, "limit": (Courses.LINE_HIT + 0.1) * 100.0, "unit": "cm", "cmp": ">", "a": m.a, "b": m.b}
				if is_large():
					_deduct(20, Lang.t("tow.ex.confirm_miss", [c.label]), info)
				else:
					_disqualify(Lang.t("tow.ex.confirm_dq", [c.label]), info)
				return
		_next_step()


func _near_lines(p: Vector2, lines: Array) -> bool:
	for l in lines:
		for i in l.size() - 1:
			if _seg_dist(p, l[i], l[i + 1]) < Courses.LINE_HIT:
				return true
	return false


## The closest point of any line to p: {d, q}.
static func nearest_line(p: Vector2, lines: Array) -> Dictionary:
	var best := {"d": INF, "q": p}
	for l in lines:
		for i in l.size() - 1:
			var q := _seg_closest(p, l[i], l[i + 1])
			var d := p.distance_to(q)
			if d < float(best.d):
				best = {"d": d, "q": q}
	return best


## The tyre closest to any line of the current course step (examiner panel): {d, p, q} or {}.
func closest_wheel_to_line() -> Dictionary:
	if step.get("type", "") != "course" or step.lines.is_empty():
		return {}
	var best := {}
	for w in rig.wheels():
		var n := nearest_line(w.p, step.lines)
		if best.is_empty() or float(n.d) < float(best.d):
			best = {"d": n.d, "p": w.p, "q": n.q}
	return best


func _far_off(wheels: Array) -> bool:
	return not _off_wheel(wheels).is_empty()


## A tyre outside the paved area: {p, q, d} (q = nearest paved point), or {}.
func _off_wheel(wheels: Array) -> Dictionary:
	for w in wheels:
		var inside := false
		var best_q: Vector2 = w.p
		var best_d := INF
		for r in step.asphalt:
			if r.has_point(w.p):
				inside = true
				break
			var q := Vector2(clampf(w.p.x, r.position.x, r.end.x), clampf(w.p.y, r.position.y, r.end.y))
			if w.p.distance_to(q) < best_d:
				best_d = w.p.distance_to(q)
				best_q = q
		if not inside:
			return {"p": w.p, "q": best_q, "d": best_d}
	return {}


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
	return p.distance_to(_seg_closest(p, a, b))


static func _seg_closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return a + ab * t


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
		_disqualify(Lang.t("tow.ex.collide"), {"code": "collide", "measured": -float(e.along) * 100.0, "limit": 50.0, "unit": "cm", "cmp": ">", "a": rig.hitch(), "b": trailer_pos})
		return
	# far past the sides counts as leaving the yard
	if absf(e.side) > 4.0 and e.along < 6.0:
		_disqualify(Lang.t("tow.ex.yard_out"), {"code": "yard_out", "measured": absf(e.side) * 100.0, "limit": 400.0, "unit": "cm", "cmp": ">", "a": rig.hitch(), "b": trailer_pos})
		return
	if absf(e.along) < 0.3 and absf(e.side) < 0.35 and absf(e.angle) < 8.0 and absf(rig.v) < 0.25:
		aligned = true
		rig.v = 0.0
		rig.throttle = 0.0
		message.emit(Lang.t("tow.ex.aligned"), "good")
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
		_deduct(10, Lang.t("tow.ex.order", [step.title]), {"code": "order", "detail": Lang.t("tow.m.order", [item, checklist[check_next]])})
	message.emit(Lang.t("tow.ex.next_item") + checklist[check_next], "info")
	return false


func _checklist_done() -> void:
	if step.type == "couple":
		trailer_parked = false
		rig.couple(trailer_th)
		aligned = false
		message.emit(Lang.t("tow.ex.coupled"), "good")
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
		message.emit(Lang.t("tow.ex.uncoupled"), "good")


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
		message.emit(Lang.t("tow.ex.in_zone"), "good")

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
