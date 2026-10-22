class_name Sim
extends RefCounted
## 지게차 주행·화물·채점 시뮬레이션. 화면과 무관한 순수 로직(헤드리스 테스트 대상).
## 좌표: 2D 평면(x, y), y = 코스 위쪽. 3D에서는 (x, 높이, -y).

# ---- 차량 치수 (3톤 카운터밸런스형 기준 추정) ----
const WHEELBASE := 1.7
const TRACK_F := 0.98
const TRACK_R := 0.92
const TIRE_HALF_W := 0.11
const TIRE_HALF_L := 0.3
const MAX_STEER := deg_to_rad(65.0)
const STEER_RATE := 1.6          # 핸들 → 뒷바퀴 각도 추종 속도(/s)
const CARRIAGE := 0.55           # 앞축 → 포크 뿌리
const FORK_LEN := 1.07
const FORK_SIDE := 0.35          # 포크 좌우 간격의 절반
const FORK_T := 0.045
const MAX_LIFT := 3.0
const LIFT_SPEED := 0.3
const TILT_MIN := -6.0           # 앞으로 숙임
const TILT_MAX := 10.0           # 뒤로 젖힘
const TILT_SPEED := 4.0
const MAX_FWD := 2.2
const MAX_REV := 1.8
const ACCEL := 1.1
const BRAKE_DECEL := 4.0
const DRAG := 0.5

# ---- 팔레트 ----
const PALLET := 1.1
const PALLET_H := 0.144
const OPEN_LO := 0.02            # 포크 바닥이 들어갈 수 있는 높이 범위(팔레트 바닥 기준)
const OPEN_HI := 0.077
const CARRY_AT := 0.077          # 이보다 높으면 포크가 상판을 받쳐 듦

# ---- 진행 단계 ----
enum Step { READY, TO_LOAD, LOADED, UNLOADED, TOUCHED, RELOADED, RETURNED, FINISHED, PARKED }
const STEP_TEXT := {
	Step.READY: "안전벨트를 매고 포크를 20~30cm 올린 뒤 출발선을 지나세요",
	Step.TO_LOAD: "드럼 위 팔레트에 포크를 끝까지 넣고 들어 올리세요",
	Step.LOADED: "전진 코스로 하역 장소까지 가서 표시선 안에 내려놓으세요",
	Step.UNLOADED: "후진해서 포크 가운데를 후진선에 맞추고 중립 후 포크를 바닥에 대세요",
	Step.TOUCHED: "다시 팔레트를 싣고 후진으로 코스를 돌아가세요",
	Step.RELOADED: "후진 코스로 돌아가 드럼 위에 팔레트를 내려놓으세요",
	Step.RETURNED: "후진으로 출발선을 지나세요",
	Step.FINISHED: "중립, 포크 바닥, 주차 브레이크로 주차하세요",
	Step.PARKED: "종료",
}

var course: Course
var exam := true                 # false면 연습: 실격이어도 계속

# 차량 상태
var pos := Vector2.ZERO          # 앞축 가운데
var heading := PI / 2
var speed := 0.0                 # +전진 / -후진
var steer := 0.0                 # 뒷바퀴 각도 비율 -1..1 (+면 왼쪽으로 돎)
var lift := 0.0                  # 포크 바닥 높이(m)
var tilt := 0.0                  # 도(+ 뒤로 젖힘)
var gear := 0                    # 1 전진, 0 중립, -1 후진
var park_brake := true
var seatbelt := false

# 팔레트
var pallet_pos := Vector2.ZERO
var pallet_heading := 0.0
var pallet_base := 0.9
var engaged := false             # 포크가 팔레트 구멍 안에 있음
var carried := false
var carry_local := Vector2.ZERO  # 들었을 때 차량 기준 팔레트 위치
var carry_dang := 0.0
var pallet_fallen := false
var drum_fallen := false

# 채점
var step := Step.READY
var signal_given := false
var t_signal := 0.0              # 출발 신호 후 경과
var t_exam := 0.0                # 출발선 통과 후 경과
var running := false             # 시계가 도는 중
var done := false
var deductions: Array = []       # {t, code, msg, pts}
var faults: Array = []           # 실격 사유 {t, code, msg, pos}
var _once := {}
var _last_fault := {}
var t_total := 0.0
var _line_touching := false
var _ground_touching := false
var drill_goal := -1              # 드릴: 이 단계에 닿으면 끝
var horn_count := 0
const PART_LOAD := "load"         # 상차 작업 45점: 출발~적재~전진 주행
const PART_UNLOAD := "unload"     # 하차 작업 55점: 하역~후진선~복귀~주차
const PART_MAX := {"load": 45, "unload": 55}


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


## 드릴: 코스 중간 상태에서 시작. d = {pos, heading, step, goal, lift?, tilt?, carried?, pallet?, pallet_heading?, pallet_base?, engaged?, seatbelt?}
func start_drill(d: Dictionary) -> void:
	reset()
	seatbelt = d.get("seatbelt", true)
	park_brake = d.get("park_brake", false)
	signal_given = true
	pos = d.pos
	heading = d.heading
	lift = d.get("lift", 0.25)
	tilt = d.get("tilt", 0.0)
	step = d.step
	running = step > Step.READY
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


# ---------- 기하 ----------
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


## 바퀴 4개: [위치, 방향각]
func wheels() -> Array:
	var d := dir()
	var r := right()
	var ra := rear_axle()
	var rear_ang := heading - steer * MAX_STEER
	return [
		[pos + r * TRACK_F * 0.5, heading],
		[pos - r * TRACK_F * 0.5, heading],
		[ra + r * TRACK_R * 0.5, rear_ang],
		[ra - r * TRACK_R * 0.5, rear_ang],
	]


## 팔레트 기준 좌표로 변환
func _to_pallet(p: Vector2, c: Vector2, ang: float) -> Vector2:
	return (p - c).rotated(-ang)


func _in_pallet(p: Vector2, c: Vector2, ang: float, margin := 0.0) -> bool:
	var l := _to_pallet(p, c, ang)
	var h := PALLET * 0.5 + margin
	return abs(l.x) <= h and abs(l.y) <= h


static func _wrap_quarter(a: float) -> float:
	# -PI/4..PI/4 로 (사방에서 꽂을 수 있는 정사각 팔레트)
	return fposmod(a + PI / 4, PI / 2) - PI / 4


func zone() -> String:
	return course.zone_at(fork_heel())


# ---------- 기록 ----------
func _deduct(code: String, msg: String, pts: int) -> void:
	if _once.has(code):
		return
	_once[code] = true
	deductions.append({t = t_exam, code = code, msg = msg, pts = pts, part = part_of_step(step)})


func _fault(code: String, msg: String) -> void:
	if OS.has_environment("SIM_DEBUG"):
		print("FAULT ", code, " pos=", pos, " hd=", rad_to_deg(heading), " zone=", zone(), " lift=", lift, " base=", pallet_base, " carried=", carried, " eng=", engaged, " step=", step)
		print_stack()
	# 시험: 첫 실격에서 끝. 연습: 같은 사유는 2초에 한 번만 기록
	if _last_fault.has(code) and t_total - _last_fault[code] < 2.0:
		return
	_last_fault[code] = t_total
	faults.append({t = t_exam, code = code, msg = msg, pos = pos})
	if exam:
		done = true
		running = false


func score() -> int:
	return part_score(PART_LOAD) + part_score(PART_UNLOAD)


func passed() -> bool:
	return step == Step.PARKED and faults.is_empty() and score() >= 60


func instruction() -> String:
	return STEP_TEXT[step]


# ---------- 한 프레임 ----------
## inp: steer(-1..1, +왼쪽), throttle(0..1), brake(0..1), lift(-1..1), tilt(-1..1, +젖힘)
func update(dt: float, inp: Dictionary) -> void:
	if done:
		return
	t_total += dt
	if signal_given and step == Step.READY:
		t_signal += dt
		if t_signal > course.start_limit:
			_fault("start_late", "출발 신호 후 1분 안에 출발선을 지나지 못함")
	if running:
		t_exam += dt
		if t_exam > course.time_limit:
			_fault("timeout", "시험 시간 %d초 초과" % int(course.time_limit))

	# 레버
	var lift_in: float = inp.get("lift", 0.0)
	var new_lift := clampf(lift + lift_in * LIFT_SPEED * dt, 0.0, MAX_LIFT)
	if engaged and not carried:
		new_lift = maxf(new_lift, pallet_base + OPEN_LO)
	tilt = clampf(tilt + float(inp.get("tilt", 0.0)) * TILT_SPEED * dt, TILT_MIN, TILT_MAX)

	# 조향
	var target_steer := clampf(inp.get("steer", 0.0), -1.0, 1.0)
	steer = move_toward(steer, target_steer, STEER_RATE * dt)

	# 속도
	var throttle: float = inp.get("throttle", 0.0)
	var brake: float = inp.get("brake", 0.0)
	if park_brake:
		brake = 1.0
	var acc := 0.0
	if gear != 0:
		acc = throttle * ACCEL * gear
	acc -= DRAG * speed
	speed += acc * dt
	var bd := brake * BRAKE_DECEL * dt
	speed = move_toward(speed, 0.0, bd)
	speed = clampf(speed, -MAX_REV, MAX_FWD)
	if gear == 1 and speed < 0 or gear == -1 and speed > 0:
		speed = move_toward(speed, 0.0, BRAKE_DECEL * dt)

	# 이동 (앞바퀴 고정, 뒷바퀴 조향)
	var prev_pos := pos
	var prev_heading := heading
	var prev_lift := lift
	var ds := speed * dt
	pos += dir() * ds
	heading += ds * tan(steer * MAX_STEER) / WHEELBASE
	lift = new_lift

	if speed > 0.05 and not seatbelt and step <= Step.TO_LOAD:
		_fault("seatbelt", "안전벨트를 매지 않고 출발함")

	# 화물 처리. 막히면 이전 자세로 되돌림.
	if not _update_pallet():
		pos = prev_pos
		heading = prev_heading
		lift = prev_lift
		speed = 0.0
		_update_pallet_follow()

	_check_lines()
	_check_ground()
	_check_travel_rules()
	_check_progress(prev_pos)
	if drill_goal >= 0 and step >= drill_goal and not done:
		done = true
		running = false


## false = 충돌로 움직임을 막아야 함
func _update_pallet() -> bool:
	if pallet_fallen:
		return true
	var d := dir()
	var tips := [fork_tip() + right() * FORK_SIDE, fork_tip() - right() * FORK_SIDE]
	var heels := [fork_heel() + right() * FORK_SIDE, fork_heel() - right() * FORK_SIDE]

	# 포크가 드럼에 닿음
	for i in 2:
		if lift < course.drum_height:
			for k in 6:
				var p: Vector2 = heels[i].lerp(tips[i], k / 5.0)
				if p.distance_to(course.drum_pos) < course.drum_radius + 0.03:
					_fault("drum_touch", "포크로 드럼을 건드림")
					return false

	# 포크 뿌리(캐리지)가 드럼·팔레트에 부딪힘
	for k in 5:
		var p: Vector2 = heels[0].lerp(heels[1], k / 4.0)
		if p.distance_to(course.drum_pos) < course.drum_radius + 0.02:
			_fault("drum_touch", "지게차 앞부분이 드럼에 부딪힘")
			return false
		if not engaged and not carried and lift < pallet_base + PALLET_H and lift + 1.2 > pallet_base \
				and _in_pallet(p, pallet_pos, pallet_heading):
			_fault("pallet_push", "지게차 앞부분이 팔레트를 밀어냄")
			return false

	# 표준(노란) 팔레트와 충돌
	if lift < PALLET_H:
		for i in 2:
			if _in_pallet(tips[i], course.guide_pos, course.guide_heading):
				_fault("guide_push", "포크로 표준 팔레트를 밀어냄")
				return false
	if carried and pallet_base < PALLET_H + 0.02 and _pallets_overlap(pallet_pos, pallet_heading, course.guide_pos, course.guide_heading):
		_fault("guide_push", "화물로 표준 팔레트를 밀어냄")
		return false

	if carried:
		_update_pallet_follow()
		pallet_base = lift - CARRY_AT
		# 내려놓기
		var surf := _surface_under(pallet_pos)
		if surf < 0.0:
			if pallet_base < course.drum_height:
				_fault("drum_hit", "화물이 드럼에 걸림")
				return false
		elif pallet_base <= surf:
			pallet_base = surf
			carried = false
			_on_placed(surf > 0.0)
		return true

	# 꽂혀 있지 않은 팔레트
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
				_fault("pallet_push", "포크가 팔레트 구멍에 맞지 않아 팔레트를 밀어냄")
				return false
		return true

	# 꽂혀 있음
	var depth := (fork_tip() - pallet_pos).dot(d) + PALLET * 0.5
	if depth <= 0.0:
		engaged = false
		return true
	var lateral2 := absf((pallet_pos - fork_heel()).dot(right()))
	if absf(dang) > deg_to_rad(15.0) or lateral2 > 0.22:
		_fault("pallet_drag", "포크로 팔레트를 비틀어 밀어냄")
		return false
	if depth > FORK_LEN + 0.02:
		# 포크 뿌리가 팔레트를 밂
		var push := depth - FORK_LEN
		pallet_pos += d * push
		if pallet_base > 0.0 and pallet_pos.distance_to(course.drum_pos) > 0.4:
			_drop("팔레트가 드럼에서 밀려 떨어짐")
	if lift - pallet_base > CARRY_AT:
		if depth < FORK_LEN - 0.2:
			_fault("shallow", "포크를 팔레트에 20cm 넘게 덜 넣고 들어 올림")
		carried = true
		carry_local = (pallet_pos - pos).rotated(-heading)
		carry_dang = pallet_heading - heading
		if step == Step.TO_LOAD:
			step = Step.LOADED
		elif step == Step.TOUCHED:
			step = Step.RELOADED
		elif step == Step.UNLOADED:
			_fault("skip_touch", "후진선 터치 동작 없이 화물을 다시 실음")
	return true


func _update_pallet_follow() -> void:
	if carried:
		pallet_pos = pos + carry_local.rotated(heading)
		pallet_heading = heading + carry_dang
		pallet_base = lift - CARRY_AT


## 팔레트를 놓을 수 있는 높이. 드럼 가장자리에 걸치면 -1.
func _surface_under(c: Vector2) -> float:
	var dd := c.distance_to(course.drum_pos)
	if dd < 0.32:
		return course.drum_height
	if dd < PALLET * 0.5 + course.drum_radius:
		return -1.0
	return 0.0


func _pallets_overlap(a: Vector2, aa: float, b: Vector2, ba: float) -> bool:
	# 모서리 검사(근사)
	var h := PALLET * 0.5 - 0.02
	for s: Vector2 in [Vector2(h, h), Vector2(-h, h), Vector2(h, -h), Vector2(-h, -h), Vector2.ZERO]:
		if _in_pallet(a + s.rotated(aa), b, ba):
			return true
	return false


func _drop(msg: String) -> void:
	pallet_fallen = true
	carried = false
	engaged = false
	pallet_base = 0.0
	_fault("drop", msg)


## 놓인 팔레트 모서리가 기준에서 얼마나 벗어났나(m)
func _corner_offset(c: Vector2, ang: float, tc: Vector2, tang: float) -> float:
	var h := PALLET * 0.5
	var worst := 0.0
	for s: Vector2 in [Vector2(h, h), Vector2(-h, h), Vector2(h, -h), Vector2(-h, -h)]:
		var best := INF
		# 팔레트는 정사각형이라 90도 돌려 놓은 것도 같은 자리
		for k in 4:
			var p := c + s.rotated(ang)
			var q := tc + s.rotated(tang + k * PI / 2)
			best = minf(best, p.distance_to(q))
		worst = maxf(worst, best)
	return worst


func _on_placed(on_drum: bool) -> void:
	var z := course.zone_at(pallet_pos)
	if step == Step.LOADED:
		if z != "unload" or on_drum:
			_fault("wrong_place", "하역 장소가 아닌 곳에 화물을 내려놓음")
			return
		if _corner_offset(pallet_pos, pallet_heading, course.unload_target, course.unload_heading) > 0.2:
			_fault("offset", "하역 표시선에서 20cm 넘게 어긋나게 내려놓음")
		step = Step.UNLOADED
	elif step == Step.RELOADED:
		if not on_drum:
			_fault("wrong_place", "드럼이 아닌 곳에 화물을 내려놓음")
			return
		if pallet_pos.distance_to(course.pallet_start) > 0.2:
			_fault("offset", "드럼 위에 20cm 넘게 어긋나게 내려놓음")
		step = Step.RETURNED


func _check_lines() -> void:
	var touching := false
	for w in wheels():
		var c: Vector2 = w[0]
		var a: float = w[1]
		var f := Vector2(cos(a), sin(a)) * TIRE_HALF_L
		var s := Vector2(sin(a), -cos(a)) * TIRE_HALF_W
		for p in [c + f + s, c + f - s, c - f + s, c - f - s]:
			if not course.inside(p):
				touching = true
	if touching and not _line_touching:
		_fault("line", "바퀴가 코스 선을 밟음")
	_line_touching = touching


func _check_ground() -> void:
	var touching := lift <= 0.001 and not engaged
	if touching and not _ground_touching and step == Step.UNLOADED:
		var near_back := absf(fork_mid().x - course.back_line_x) < 0.3 and course.zone_at(fork_mid()) == "travel"
		if near_back:
			if gear != 0:
				_deduct("touch_gear", "후진선 정지 후 기어를 중립에 두지 않음", 5)
			if absf(speed) > 0.05:
				_deduct("touch_moving", "완전히 서기 전에 포크를 내림", 5)
			step = Step.TOUCHED
		else:
			_fault("touch_wrong", "후진선이 아닌 곳에 포크가 닿음")
	elif touching and absf(speed) > 0.02 and step >= Step.TO_LOAD and step < Step.FINISHED:
		_fault("fork_ground", "주행 중 포크가 바닥에 닿음")
	_ground_touching = touching


func _check_travel_rules() -> void:
	if step == Step.READY or step >= Step.FINISHED:
		return
	var z := zone()
	if z != "travel":
		return
	if step == Step.TO_LOAD and course.zone_at(pos) == "travel":
		_fault("no_pallet", "팔레트를 싣지 않고 작업 구역을 벗어남")
	if absf(speed) < 0.1:
		return
	if lift > 0.5:
		_fault("fork_high", "주행 구간에서 포크를 50cm 넘게 올림")
	elif (lift < 0.15 or lift > 0.35) and step != Step.UNLOADED and step != Step.TOUCHED:
		_deduct("height_%d" % step, "주행 중 포크 높이(20~30cm)를 지키지 않음", 5)
	if carried and tilt < 1.0:
		_deduct("tilt_%d" % step, "화물을 싣고 틸트를 뒤로 젖히지 않고 주행", 5)


func _check_progress(prev_pos: Vector2) -> void:
	var ly := course.start_line_y
	if step == Step.READY and prev_pos.y < ly and pos.y >= ly:
		if not signal_given:
			_fault("early", "출발 신호 전에 출발함")
		step = Step.TO_LOAD
		running = true
	elif step == Step.RETURNED and prev_pos.y > ly and pos.y <= ly:
		step = Step.FINISHED
		running = false
	elif step == Step.FINISHED:
		if absf(speed) < 0.01 and gear == 0 and park_brake and lift <= 0.001:
			step = Step.PARKED
			done = true
