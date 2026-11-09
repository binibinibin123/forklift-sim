class_name Sim
extends RefCounted
## Forklift driving, load handling and grading. Pure logic (headless tests).
## Plane coordinates (x, y), y = towards the drum. In 3D: (x, height, -y).
##
## Disqualifications follow the Q-Net public exam "코스운전 및 작업" (2025-12-22),
## 수험자 유의사항 10) 나) 실격 (1)~(18); each fault records the measured value and
## the limit. The exam publishes only the part totals (상차 45 / 하차 55), not the
## deduction items, so the deductions here are this app's estimate.

# ---- vehicle (3 t counterbalance class, estimated) ----
const WHEELBASE := 1.7
const TRACK_F := 0.98
const TRACK_R := 0.92
const TIRE_HALF_W := 0.11
const TIRE_HALF_L := 0.3
const CONTACT_HALF_L := 0.1      # tyre contact patch half length (what touches a painted line)
const MAX_STEER := deg_to_rad(65.0)
const STEER_RATE := 1.6
const CARRIAGE := 0.55           # front axle -> fork heel (drawing's "a")
const FORK_LEN := 1.07
const FORK_SIDE := 0.35
const FORK_T := 0.045
const MAX_LIFT := 3.0
const LIFT_SPEED := 0.3
const TILT_MIN := -6.0
const TILT_MAX := 10.0
const TILT_SPEED := 4.0
const MAX_FWD := 2.2
const MAX_REV := 1.8
const ACCEL := 1.1
const BRAKE_DECEL := 4.0
const DRAG := 0.5

# ---- pallet ----
const PALLET := 1.1
const PALLET_H := 0.144
const OPEN_LO := 0.02
const OPEN_HI := 0.077
const CARRY_AT := 0.077

# ---- official limits ----
const FORK_HIGH_LIMIT := 0.5     # 주행구간 포크 높이 (m)
const SHALLOW_LIMIT := 0.2       # 덜 삽입 (m)
const OFFSET_LIMIT := 0.2        # 표준 파렛트 위 가로·세로 (m)
const COURSE_SLACK := 2.0        # m of wrong-direction driving tolerated before (3)

enum Step { READY, TO_LOAD, LOADED, UNLOADED, TOUCHED, RELOADED, RETURNED, FINISHED, PARKED }

var course: Course
var exam := true                 # false = practice: keep going after a fault

var pos := Vector2.ZERO          # front axle centre
var heading := PI / 2
var speed := 0.0
var steer := 0.0
var lift := 0.0                  # fork bottom height (m)
var tilt := 0.0                  # degrees, + = back
var gear := 0
var park_brake := true
var seatbelt := false

var pallet_pos := Vector2.ZERO
var pallet_heading := 0.0
var pallet_base := 0.9
var engaged := false
var carried := false
var carry_local := Vector2.ZERO
var carry_dang := 0.0
var pallet_fallen := false
var drum_fallen := false
var on_guide := false            # moving pallet rests on the 표준 파렛트

var step := Step.READY
var signal_given := false
var t_signal := 0.0
var t_exam := 0.0                # from front wheels over the start line
var running := false
var done := false
var deductions: Array = []       # {t, code, msg, pts, part, val, lim, unit}
var faults: Array = []           # {t, code, msg, pos, val, lim, unit, ma, mb}
var _once := {}
var _last_fault := {}
var t_total := 0.0
var _line_touching := false
var _ground_touching := false
var drill_goal := -1
var horn_count := 0
var center_seen := false
var north_seen := false
var south_seen := false
var wrong_dist := 0.0
const PART_LOAD := "load"
const PART_UNLOAD := "unload"
const PART_MAX := {"load": 45, "unload": 55}
const PASS_MARK := 60


func _init(c: Course = null, exam_mode := true) -> void:
	course = c if c else Course.load_default()
	exam = exam_mode
	reset()


func reset() -> void:
	pos = course.start_pos
	heading = course.start_heading
	speed = 0.0
	steer = 0.0
	lift = 0.0
	tilt = 0.0
	gear = 0
	park_brake = true
	seatbelt = false
	pallet_pos = course.pallet_start
	pallet_heading = course.pallet_start_heading
	pallet_base = course.drum_height
	engaged = false
	carried = false
	pallet_fallen = false
	drum_fallen = false
	on_guide = false
	step = Step.READY
	signal_given = false
	t_signal = 0.0
	t_exam = 0.0
	running = false
	done = false
	deductions.clear()
	faults.clear()
	_once.clear()
	_last_fault.clear()
	t_total = 0.0
	_line_touching = false
	_ground_touching = false
	drill_goal = -1
	horn_count = 0
	center_seen = false
	north_seen = false
	south_seen = false
	wrong_dist = 0.0


## Drill: start mid-course. d = {pos, heading, step, goal, lift?, tilt?, carried?, pallet?,
## pallet_heading?, pallet_base?, engaged?, seatbelt?, park_brake?, signal?, t_signal?, t_exam?,
## route? ("north" / "south" / "center" already seen), exam? (stop at the first fault)}
func start_drill(d: Dictionary) -> void:
	reset()
	exam = d.get("exam", exam)
	seatbelt = d.get("seatbelt", true)
	park_brake = d.get("park_brake", false)
	signal_given = d.get("signal", true)
	t_signal = d.get("t_signal", 0.0)
	pos = d.pos
	heading = d.heading
	lift = d.get("lift", 0.25)
	tilt = d.get("tilt", 0.0)
	step = d.step
	running = step > Step.READY and step < Step.FINISHED
	t_exam = d.get("t_exam", 0.0)
	for r in d.get("route", []):
		match r:
			"center": center_seen = true
			"north": north_seen = true
			"south": south_seen = true
	if d.get("carried", false):
		engaged = true
		carried = true
		carry_local = Vector2(CARRIAGE + FORK_LEN - PALLET * 0.5, 0.0)
		carry_dang = 0.0
		_update_pallet_follow()
	elif d.has("pallet"):
		pallet_pos = d.pallet
		pallet_heading = d.get("pallet_heading", 0.0)
		pallet_base = d.get("pallet_base", 0.0)
		engaged = d.get("engaged", false)
		on_guide = absf(pallet_base - PALLET_H) < 0.01
	_ground_touching = lift <= 0.001
	drill_goal = d.goal


func part_of_step(st: int) -> String:
	return PART_LOAD if st <= Step.LOADED else PART_UNLOAD


func part_score(part: String) -> int:
	var s: int = PART_MAX[part]
	for d in deductions:
		if d.part == part:
			s -= d.pts
	return maxi(s, 0)


func give_signal() -> void:
	signal_given = true


# ---------- geometry ----------
func dir() -> Vector2:
	return Vector2(cos(heading), sin(heading))


func right() -> Vector2:
	return Vector2(sin(heading), -cos(heading))


func rear_axle() -> Vector2:
	return pos - dir() * WHEELBASE


func fork_heel() -> Vector2:
	return pos + dir() * CARRIAGE


func fork_tip() -> Vector2:
	return pos + dir() * (CARRIAGE + FORK_LEN)


func fork_mid() -> Vector2:
	return pos + dir() * (CARRIAGE + FORK_LEN * 0.5)


## Four wheels: [centre, direction angle]. 0,1 = front.
func wheels() -> Array:
	var r := right()
	var ra := rear_axle()
	var rear_ang := heading - steer * MAX_STEER
	return [
		[pos + r * TRACK_F * 0.5, heading],
		[pos - r * TRACK_F * 0.5, heading],
		[ra + r * TRACK_R * 0.5, rear_ang],
		[ra - r * TRACK_R * 0.5, rear_ang],
	]


## Contact patch corners of one wheel.
static func contact_corners(w: Array) -> Array:
	var c: Vector2 = w[0]
	var a: float = w[1]
	var f := Vector2(cos(a), sin(a)) * CONTACT_HALF_L
	var s := Vector2(sin(a), -cos(a)) * TIRE_HALF_W
	return [c + f + s, c + f - s, c - f + s, c - f - s]


func _to_pallet(p: Vector2, c: Vector2, ang: float) -> Vector2:
	return (p - c).rotated(-ang)


func _in_pallet(p: Vector2, c: Vector2, ang: float, margin := 0.0) -> bool:
	var l := _to_pallet(p, c, ang)
	var h := PALLET * 0.5 + margin
	return abs(l.x) <= h and abs(l.y) <= h


static func _wrap_quarter(a: float) -> float:
	return fposmod(a + PI / 4, PI / 2) - PI / 4


## Zone of the fork heel (작업 판정용)
func zone() -> String:
	return course.zone_at(fork_heel())


## True once a front wheel has fully left the work zones into 주행구간 (the exam's entry rule).
func front_in_travel() -> bool:
	var ws := wheels()
	for i in 2:
		var all := true
		for p in contact_corners(ws[i]):
			if course.zone_at(p) != "travel":
				all = false
				break
		if all:
			return true
	return false


func front_zone() -> String:
	return course.zone_at(pos)


# ---------- live examiner values ----------
## Closest tyre contact to a course edge, cm (negative = over the line).
func wheel_line_cm() -> float:
	var best := INF
	for w in wheels():
		for p in contact_corners(w):
			best = minf(best, course.edge_dist(p))
	return best * 100.0


## Moving pallet vs 표준 파렛트, the larger of the two axis offsets in cm; -1 when far away.
func pallet_offset_cm() -> float:
	if pallet_fallen or pallet_pos.distance_to(course.guide_pos) > 2.0:
		return -1.0
	return axis_offset(pallet_pos, pallet_heading, course.guide_pos, course.guide_heading) * 100.0


## Larger of the 가로/세로 offsets (m) of a placed pallet against a target pallet.
static func axis_offset(c: Vector2, ang: float, tc: Vector2, tang: float) -> float:
	var h := PALLET * 0.5
	var targets := [Vector2(h, h), Vector2(-h, h), Vector2(h, -h), Vector2(-h, -h)]
	var worst := 0.0
	for s: Vector2 in targets:
		var p := (c + s.rotated(ang) - tc).rotated(-tang)
		var best := INF
		for t: Vector2 in targets:   # square pallet: match each corner to the nearest target corner
			var d := p - t
			best = minf(best, maxf(absf(d.x), absf(d.y)))
		worst = maxf(worst, best)
	return worst


# ---------- records ----------
static func h3(p: Vector2, h := 0.0) -> Vector3:
	return Vector3(p.x, p.y, h)


func _deduct(code: String, pts: int, val := NAN, lim := NAN, unit := "") -> void:
	if _once.has(code):
		return
	_once[code] = true
	var key := code.get_slice("_", 0) if code.begins_with("height_") or code.begins_with("tilt_") else code
	deductions.append({t = t_exam, code = key, msg = Lang.t("d." + key), pts = pts, part = part_of_step(step),
		val = val, lim = lim, unit = unit, pos = pos})


func _fault(code: String, val := NAN, lim := NAN, unit := "", ma := Vector3.INF, mb := Vector3.INF) -> void:
	if OS.has_environment("SIM_DEBUG"):
		print("FAULT ", code, " val=", val, " pos=", pos, " hd=", rad_to_deg(heading), " zone=", zone(), " lift=", lift, " step=", step)
		print_stack()
	if _last_fault.has(code) and t_total - _last_fault[code] < 2.0:
		return
	_last_fault[code] = t_total
	if ma == Vector3.INF:
		ma = h3(pos)
	faults.append({t = t_exam, code = code, msg = Lang.t("f." + code), pos = pos,
		val = val, lim = lim, unit = unit, ma = ma, mb = mb})
	if exam:
		done = true
		running = false


func score() -> int:
	return part_score(PART_LOAD) + part_score(PART_UNLOAD)


func passed() -> bool:
	return step == Step.PARKED and faults.is_empty() and score() >= PASS_MARK


func instruction() -> String:
	return Lang.t("step.%d" % step)


# ---------- one frame ----------
## inp: steer(-1..1, +left), throttle(0..1), brake(0..1), lift(-1..1), tilt(-1..1, +back)
func update(dt: float, inp: Dictionary) -> void:
	if done:
		return
	t_total += dt
	if signal_given and step == Step.READY:
		t_signal += dt
		if t_signal > course.start_limit:
			_fault("start_late", t_signal, course.start_limit, "s")
	if running:
		t_exam += dt
		if t_exam > course.time_limit:
			_fault("timeout", t_exam, course.time_limit, "s")

	var lift_in: float = inp.get("lift", 0.0)
	var new_lift := clampf(lift + lift_in * LIFT_SPEED * dt, 0.0, MAX_LIFT)
	if engaged and not carried:
		new_lift = maxf(new_lift, pallet_base + OPEN_LO)
	tilt = clampf(tilt + float(inp.get("tilt", 0.0)) * TILT_SPEED * dt, TILT_MIN, TILT_MAX)

	var target_steer := clampf(inp.get("steer", 0.0), -1.0, 1.0)
	steer = move_toward(steer, target_steer, STEER_RATE * dt)

	var throttle: float = inp.get("throttle", 0.0)
	var brake: float = inp.get("brake", 0.0)
	if park_brake:
		brake = 1.0
	var acc := 0.0
	if gear != 0:
		acc = throttle * ACCEL * gear
	acc -= DRAG * speed
	speed += acc * dt
	speed = move_toward(speed, 0.0, brake * BRAKE_DECEL * dt)
	speed = clampf(speed, -MAX_REV, MAX_FWD)
	if gear == 1 and speed < 0 or gear == -1 and speed > 0:
		speed = move_toward(speed, 0.0, BRAKE_DECEL * dt)

	var prev_pos := pos
	var prev_heading := heading
	var prev_lift := lift
	var prev_tip := fork_tip()
	var ds := speed * dt
	pos += dir() * ds
	heading += ds * tan(steer * MAX_STEER) / WHEELBASE
	lift = new_lift

	if absf(speed) > 0.05 and not seatbelt and step <= Step.TO_LOAD:
		_deduct("seatbelt", 5)

	if not _update_pallet():
		pos = prev_pos
		heading = prev_heading
		lift = prev_lift
		speed = 0.0
		_update_pallet_follow()

	_check_lines()
	_check_ground(prev_tip)
	_check_travel_rules(ds)
	_check_progress(prev_pos)
	if drill_goal >= 0 and step >= drill_goal and not done:
		done = true
		running = false


## false = blocked by a collision
func _update_pallet() -> bool:
	if pallet_fallen:
		return true
	var d := dir()
	var tips := [fork_tip() + right() * FORK_SIDE, fork_tip() - right() * FORK_SIDE]
	var heels := [fork_heel() + right() * FORK_SIDE, fork_heel() - right() * FORK_SIDE]

	# forks against the drum ((10), loaded or not)
	for i in 2:
		if lift < course.drum_height:
			for k in 6:
				var p: Vector2 = heels[i].lerp(tips[i], k / 5.0)
				if p.distance_to(course.drum_pos) < course.drum_radius + 0.03:
					_fault("drum_touch", NAN, NAN, "", h3(p, lift), h3(course.drum_pos, lift))
					return false
	for k in 5:
		var p: Vector2 = heels[0].lerp(heels[1], k / 4.0)
		if p.distance_to(course.drum_pos) < course.drum_radius + 0.02:
			_fault("drum_touch", NAN, NAN, "", h3(p, 0.5), h3(course.drum_pos, 0.5))
			return false
		if not engaged and not carried and lift < pallet_base + PALLET_H and lift + 1.2 > pallet_base \
				and _in_pallet(p, pallet_pos, pallet_heading):
			_fault("pallet_push", NAN, NAN, "", h3(p, pallet_base), h3(pallet_pos, pallet_base))
			return false
		# carriage into the 표준 파렛트 ((17))
		if lift < PALLET_H and _in_pallet(p, course.guide_pos, course.guide_heading):
			_fault("std_push", NAN, NAN, "", h3(p, 0.07), h3(course.guide_pos, 0.07))
			return false

	# fork tips into the 표준 파렛트 ((17))
	if lift < PALLET_H:
		for i in 2:
			if _in_pallet(tips[i], course.guide_pos, course.guide_heading):
				_fault("std_push", NAN, NAN, "", h3(tips[i], lift), h3(course.guide_pos, 0.07))
				return false

	if carried:
		_update_pallet_follow()
		pallet_base = lift - CARRY_AT
		var surf := _surface_under(pallet_pos)
		if surf.h < 0.0:
			if pallet_base < surf.top:
				if surf.what == "drum":
					_fault("drum_touch", NAN, NAN, "", h3(pallet_pos, pallet_base), h3(course.drum_pos, course.drum_height))
				else:
					_fault("std_push", NAN, NAN, "", h3(pallet_pos, pallet_base), h3(course.guide_pos, PALLET_H))
				return false
		elif pallet_base <= surf.h:
			pallet_base = surf.h
			carried = false
			_on_placed(surf.what)
		return true

	# pallet resting somewhere, forks not in it yet
	var dang := _wrap_quarter(heading - pallet_heading)
	var tip_in := _in_pallet(tips[0], pallet_pos, pallet_heading) or _in_pallet(tips[1], pallet_pos, pallet_heading)
	var vert_overlap := lift < pallet_base + PALLET_H and lift + FORK_T > pallet_base
	if not engaged:
		if tip_in and vert_overlap:
			var lateral := absf((pallet_pos - fork_heel()).dot(right()))
			var rel := lift - pallet_base
			if absf(dang) < deg_to_rad(12.0) and lateral < 0.15 and rel >= OPEN_LO - 0.005 and rel <= OPEN_HI:
				engaged = true
			else:
				_fault("pallet_push", NAN, NAN, "", h3(fork_tip(), lift), h3(pallet_pos, pallet_base))
				return false
		return true

	# forks in the pallet
	var depth := (fork_tip() - pallet_pos).dot(d) + PALLET * 0.5
	if depth <= 0.0:
		engaged = false
		return true
	var lat := (pallet_pos - fork_heel()).dot(right())
	if on_guide:
		# forks in the openings drag a pallet resting on the 표준 파렛트 sideways ((16))
		var play := 0.08
		if absf(lat) > play:
			pallet_pos -= right() * (lat - signf(lat) * play)
		if absf(dang) > deg_to_rad(6.0):
			pallet_heading += dang - signf(dang) * deg_to_rad(6.0)
		var off2 := axis_offset(pallet_pos, pallet_heading, course.guide_pos, course.guide_heading)
		if off2 > OFFSET_LIMIT:
			_fault("pushed_off", off2 * 100.0, OFFSET_LIMIT * 100.0, "cm", h3(pallet_pos, PALLET_H * 2), h3(course.guide_pos, PALLET_H * 2))
		lat = (pallet_pos - fork_heel()).dot(right())
		dang = _wrap_quarter(heading - pallet_heading)
	var lateral2 := absf(lat)
	if absf(dang) > deg_to_rad(15.0) or lateral2 > 0.22:
		_fault("pallet_push", NAN, NAN, "", h3(fork_tip(), lift), h3(pallet_pos, pallet_base))
		return false
	if depth > FORK_LEN + 0.02:
		# the carriage pushes the pallet along
		var push := depth - FORK_LEN
		pallet_pos += d * push
		if pallet_base > 0.5 and pallet_pos.distance_to(course.drum_pos) > 0.2:
			_drop()
		elif on_guide:
			var off := axis_offset(pallet_pos, pallet_heading, course.guide_pos, course.guide_heading)
			if off > OFFSET_LIMIT:
				_fault("pushed_off", off * 100.0, OFFSET_LIMIT * 100.0, "cm", h3(pallet_pos, PALLET_H * 2), h3(course.guide_pos, PALLET_H * 2))
	if lift - pallet_base > CARRY_AT:
		var short := FORK_LEN - depth
		if short > SHALLOW_LIMIT:
			_fault("shallow", short * 100.0, SHALLOW_LIMIT * 100.0, "cm", h3(fork_tip(), lift), h3(pallet_pos + d * PALLET * 0.5, lift))
		carried = true
		on_guide = false
		carry_local = (pallet_pos - pos).rotated(-heading)
		carry_dang = pallet_heading - heading
		if step == Step.TO_LOAD:
			step = Step.LOADED
		elif step == Step.TOUCHED:
			step = Step.RELOADED
		elif step == Step.UNLOADED:
			_fault("skip_touch")
	return true


func _update_pallet_follow() -> void:
	if carried:
		pallet_pos = pos + carry_local.rotated(heading)
		pallet_heading = heading + carry_dang
		pallet_base = lift - CARRY_AT


## Where a carried pallet would land: {h: rest height or -1 if it catches an edge, top, what}
func _surface_under(c: Vector2) -> Dictionary:
	var dd := c.distance_to(course.drum_pos)
	if dd < 0.32:
		return {h = course.drum_height, top = course.drum_height, what = "drum"}
	if dd < PALLET * 0.5 + course.drum_radius:
		return {h = -1.0, top = course.drum_height, what = "drum"}
	var l := _to_pallet(c, course.guide_pos, course.guide_heading)
	var m := maxf(absf(l.x), absf(l.y))
	if m < 0.35:
		return {h = PALLET_H, top = PALLET_H, what = "guide"}
	if m < PALLET:
		return {h = -1.0, top = PALLET_H, what = "guide"}
	return {h = 0.0, top = 0.0, what = "ground"}


func _drop() -> void:
	pallet_fallen = true
	carried = false
	engaged = false
	pallet_base = 0.0
	_fault("drop", NAN, NAN, "", h3(pallet_pos, 0.0))


func _on_placed(what: String) -> void:
	if what == "ground":
		_fault("pallet_ground", NAN, NAN, "", h3(pallet_pos, 0.0))
		return
	if step == Step.LOADED:
		if what != "guide":
			_fault("wrong_place", NAN, NAN, "", h3(pallet_pos, pallet_base))
			return
		on_guide = true
		var off := axis_offset(pallet_pos, pallet_heading, course.guide_pos, course.guide_heading)
		if off > OFFSET_LIMIT:
			_fault("offset", off * 100.0, OFFSET_LIMIT * 100.0, "cm", h3(pallet_pos, PALLET_H * 2), h3(course.guide_pos, PALLET_H * 2))
		step = Step.UNLOADED
	elif step == Step.RELOADED:
		if what != "drum":
			_fault("wrong_place", NAN, NAN, "", h3(pallet_pos, pallet_base))
			return
		step = Step.RETURNED
	else:
		on_guide = what == "guide"


func _check_lines() -> void:
	var worst := 0.0
	var wp := Vector2.ZERO
	var start_hit := false
	for w in wheels():
		for p: Vector2 in contact_corners(w):
			if not course.inside(p):
				var e := course.nearest_edge_point(p)
				var over := p.distance_to(e)
				if over >= worst:
					worst = over
					wp = p
		if carried:
			var ys := []
			for p: Vector2 in contact_corners(w):
				ys.append(p.y)
			var c: Vector2 = w[0]
			if ys.min() <= course.start_line_y and ys.max() >= course.start_line_y and absf(c.x - course.box.get_center().x) < course.box.size.x * 0.5:
				start_hit = true
				wp = c
	var touching := worst > 0.0 or start_hit
	if touching and not _line_touching:
		if start_hit and worst <= 0.0:
			_fault("line_start", 0.0, 0.0, "cm", h3(wp), h3(Vector2(wp.x, course.start_line_y)))
		else:
			_fault("line", worst * 100.0, 0.0, "cm", h3(wp), h3(course.nearest_edge_point(wp)))
	_line_touching = touching


func _back_line_under_fork() -> bool:
	var a := fork_heel().x
	var b := fork_tip().x
	return course.back_line_x >= minf(a, b) - 0.02 and course.back_line_x <= maxf(a, b) + 0.02 \
		and absf(fork_mid().y - course.center.y) <= course.hw


func _park_line_under_fork() -> bool:
	var a := fork_heel().y
	var b := fork_tip().y
	return course.park_line_y >= minf(a, b) and course.park_line_y <= maxf(a, b)


func _check_ground(prev_tip: Vector2) -> void:
	var touching := lift <= 0.001 and not engaged
	# (6) forks on the ground until the fork ends reach the start line
	if step == Step.READY and signal_given and touching:
		var ly := course.start_line_y
		if prev_tip.y < ly and fork_tip().y >= ly:
			_fault("fork_start", NAN, NAN, "", h3(fork_tip(), 0.0), h3(Vector2(fork_tip().x, ly), 0.0))
	if touching and not _ground_touching:
		if step == Step.UNLOADED:
			if _back_line_under_fork():
				if gear != 0:
					_deduct("touch_gear", 5)
				if absf(speed) > 0.05:
					_deduct("touch_moving", 5)
				step = Step.TOUCHED
			else:
				var gap := minf(absf(fork_tip().x - course.back_line_x), absf(fork_heel().x - course.back_line_x))
				_fault("touch_wrong", gap * 100.0, 0.0, "cm", h3(fork_mid(), 0.0), h3(Vector2(course.back_line_x, fork_mid().y), 0.0))
		elif step >= Step.TO_LOAD and step < Step.FINISHED:
			_fault("fork_ground", lift * 100.0, 0.0, "cm", h3(fork_mid(), 0.3), h3(fork_mid(), 0.0))
		elif step == Step.FINISHED and not _park_line_under_fork():
			_deduct("park_line", 5)
	_ground_touching = touching


func _check_travel_rules(ds: float) -> void:
	if step == Step.READY or step >= Step.FINISHED:
		return
	var in_travel := front_in_travel()
	# (11) leaving a work zone without the moving pallet
	if step == Step.TO_LOAD and in_travel:
		_fault("no_pallet", NAN, NAN, "", h3(pos), h3(course.drum_pos))
	if (step == Step.UNLOADED or step == Step.TOUCHED) and fork_tip().x > course.back_line_x + 0.3:
		_fault("no_pallet2", NAN, NAN, "", h3(fork_tip(), lift), h3(Vector2(course.back_line_x, fork_tip().y), 0.0))
	_check_route(ds, in_travel)
	if not in_travel or front_zone() != "travel":
		return
	# (14) fork above 50 cm in the travel section
	if lift > FORK_HIGH_LIMIT:
		_fault("fork_high", lift * 100.0, FORK_HIGH_LIMIT * 100.0, "cm", h3(fork_mid(), 0.0), h3(fork_mid(), lift))
	if absf(speed) < 0.1:
		return
	if (lift < 0.15 or lift > 0.35) and step != Step.UNLOADED and step != Step.TOUCHED:
		_deduct("height_%d" % step, 5, lift * 100.0, 30.0, "cm")
	if carried and tilt < 1.0:
		_deduct("tilt_%d" % step, 5, tilt, 1.0, "°")


## (3) drive the course as drawn: loaded forward via the centre and the north half of the ring,
## back in reverse via the centre and the south half.
func _check_route(ds: float, in_travel: bool) -> void:
	var q := pos - course.center
	if step == Step.LOADED:
		if q.length() < course.hw + 0.8:
			center_seen = true
		if center_seen and q.y > course.r_in - 1.0:
			north_seen = true
		if in_travel and ds < 0.0:
			wrong_dist += -ds
		var wrong := q.y < -(course.hw + 1.0) and course.inside(pos) and not course.box.has_point(pos)
		if course.zone_at(pos) == "work2" and not north_seen:
			wrong = true
		if wrong or wrong_dist > COURSE_SLACK:
			_fault("course", wrong_dist if not wrong else NAN, COURSE_SLACK if not wrong else NAN, "m" if not wrong else "")
	elif step == Step.RELOADED:
		if q.length() < course.hw + 0.8:
			center_seen = true
		if center_seen and q.y < -(course.r_in - 1.0):
			south_seen = true
		if in_travel and ds > 0.0:
			wrong_dist += ds
		var wrong := q.y > course.hw + 1.0 and pos.x > course.back_line_x + 0.5 and not course.box.has_point(pos) and not course.conn.has_point(pos)
		if course.box.has_point(pos) and not south_seen:
			wrong = true
		if wrong or wrong_dist > COURSE_SLACK:
			_fault("course", wrong_dist if not wrong else NAN, COURSE_SLACK if not wrong else NAN, "m" if not wrong else "")
	elif step == Step.TOUCHED or step == Step.UNLOADED:
		center_seen = false
		wrong_dist = 0.0


func _check_progress(prev_pos: Vector2) -> void:
	var ly := course.start_line_y
	if step == Step.READY and prev_pos.y < ly and pos.y >= ly:
		if not signal_given:
			_fault("early")
		step = Step.TO_LOAD
		running = true
	elif step == Step.RETURNED and prev_pos.y > ly and pos.y <= ly:
		step = Step.FINISHED
		running = false
	elif step == Step.FINISHED:
		if absf(speed) < 0.01 and gear == 0 and park_brake and lift <= 0.001:
			step = Step.PARKED
			done = true
