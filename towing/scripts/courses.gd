class_name Courses
extends RefCounted
## Exam course layouts per licence, in metres on the ground plane.
##
## Sources (2026-10-15): 도로교통공단 safedriving.or.kr 제1종 특수 기능시험 안내
## (소형견인·구난: 굴절·곡선·방향전환, 대형견인: 연결·코스·분리, 90점 합격,
## 20초 내 미출발 실격), 학원 안내(대형견인 연결·코스·분리 각 5분, 감점),
## 나무위키 시험 해설(소형견인·구난 코스당 3분, 시간 초과 10점 감점 후 3분 추가,
## 대형견인 A·B 확인선, 20점 감점 즉시 불합격, 예각 꺾임 실격).
## Exact course dimensions are not published in a form we could read, so the
## sizes below are practice approximations scaled to each vehicle.

const LINE_HIT := 0.2   # tyre centre this close to a line = touching it

static var tune := {}   # size overrides for tuning runs (tests/tune.gd)


static func exam_steps(kind: String) -> Array:
	match kind:
		"small":
			return [crank("small", Vector2(0, 0)), curve("small", Vector2(40, 0)), garage("small", Vector2(80, 0))]
		"wrecker":
			return [couple("wrecker", Vector2(-40, 0)), crank("wrecker", Vector2(0, 0)), curve("wrecker", Vector2(45, 0)),
				uncouple("wrecker", Vector2(95, 0)), garage("wrecker", Vector2(135, 0))]
		"large":
			return [couple("large", Vector2(-40, 0)), garage("large", Vector2(0, 0)), uncouple("large", Vector2(60, 0))]
	return []


static func practice_list(kind: String) -> Array:
	var out := []
	for s in exam_steps(kind):
		out.append({"id": s.id, "title": s.title})
	return out


static func step_by_id(kind: String, id: String) -> Dictionary:
	for s in exam_steps(kind):
		if s.id == id:
			return s
	if TowDrills.is_drill(id):
		return TowDrills.step(kind, id)
	return {}


# ---------------------------------------------------------------- geometry

## Left and right boundary lines of a lane of width w around a centre polyline.
static func offset_lines(center: PackedVector2Array, w: float) -> Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := center.size()
	for i in n:
		var nrm: Vector2
		var scale := 1.0
		if i == 0:
			nrm = _normal(center[0], center[1])
		elif i == n - 1:
			nrm = _normal(center[n - 2], center[n - 1])
		else:
			var n1 := _normal(center[i - 1], center[i])
			var n2 := _normal(center[i], center[i + 1])
			nrm = (n1 + n2).normalized()
			scale = 1.0 / maxf(nrm.dot(n1), 0.3)
		left.append(center[i] + nrm * w * 0.5 * scale)
		right.append(center[i] - nrm * w * 0.5 * scale)
	return [left, right]


static func _normal(a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	return Vector2(-d.y, d.x)


static func arc(c: Vector2, r: float, a0: float, a1: float, steps: int = 18) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		out.append(c + r * Vector2(cos(a), sin(a)))
	return out


static func _shift(arr, o: Vector2):
	if arr is PackedVector2Array:
		var out := PackedVector2Array()
		for p in arr:
			out.append(p + o)
		return out
	if arr is Vector2:
		return arr + o
	return arr


static func _place(step: Dictionary, o: Vector2) -> Dictionary:
	var lines := []
	for l in step.lines:
		lines.append(_shift(l, o))
	step.lines = lines
	var paint := []
	for l in step.get("paint", []):
		paint.append(_shift(l, o))
	step.paint = paint
	for c in step.get("confirms", []):
		c.a += o
		c.b += o
	if step.has("finish"):
		step.finish.a += o
		step.finish.b += o
	step.start.pos += o
	if step.has("trailer_pose"):
		step.trailer_pose.pos += o
	if step.has("zone"):
		step.zone = _shift(step.zone, o)
	for seg in step.get("demo", []):
		seg.path = _shift(seg.path, o)
	if step.has("asphalt"):
		var rects := []
		for r in step.asphalt:
			rects.append(Rect2(r.position + o, r.size))
		step.asphalt = rects
	step.origin = o
	return step


static func _bounds(lines: Array, pad: float) -> Rect2:
	var r := Rect2(lines[0][0], Vector2.ZERO)
	for l in lines:
		for p in l:
			r = r.expand(p)
	return r.grow(pad)


static func _rig_len(kind: String) -> float:
	var s: Dictionary = Rig.SPECS[kind]
	return s.L + s.front_oh + s.c + s.trailer.back


# ---------------------------------------------------------------- courses

static func _size(kind: String) -> Dictionary:
	var z := _base_size(kind)
	z.merge(tune, true)
	return z


static func _base_size(kind: String) -> Dictionary:
	match kind:
		"wrecker":
			return {"cw": 6.4, "ca": 13.0, "cb": 16.0, "cc": 14.0, "sw": 5.6, "sr": 11.0, "fr": 6.0, "fs": 0.6, "sk": 0.08,
				"gw_road": 10.0, "g_width": 4.0, "g_conf": 5.0, "g_rev_r": 7.0}
		"large":
			return {"gw_road": 18.0, "g_width": 4.6, "g_conf": 12.4, "g_rev_r": 10.0}
	return {"cw": 5.4, "ca": 12.0, "cb": 13.0, "cc": 12.0, "sw": 4.6, "sr": 9.0, "fr": 4.2, "fs": 0.5, "sk": 0.1,
		"gw_road": 9.0, "g_width": 3.6, "g_conf": 4.6, "g_rev_r": 5.5}


## 굴절코스: a lane with two right-angle bends (right, then left), driven forward.
static func crank(kind: String, o: Vector2) -> Dictionary:
	var z := _size(kind)
	var lead := _rig_len(kind) + 3.0
	var center := PackedVector2Array([Vector2(0, -lead), Vector2(0, z.ca), Vector2(z.cb, z.ca), Vector2(z.cb, z.ca + z.cc + _rig_len(kind) + 3.0)])
	var lr := offset_lines(center, z.cw)
	var fin_y: float = z.ca + z.cc
	var demo_path := fillet_path(PackedVector2Array([Vector2(0, -lead + 4.0), Vector2(0, z.ca), Vector2(z.cb, z.ca),
		Vector2(z.cb, fin_y + _rig_len(kind) + 10.0)]), z.fr, z.fs)
	var step := {
		"id": "crank", "type": "course", "title": "굴절코스", "kind": kind,
		"time_limit": 180.0,
		"lines": lr,
		"confirms": [],
		"finish": {"a": Vector2(z.cb - z.cw * 0.5, fin_y), "b": Vector2(z.cb + z.cw * 0.5, fin_y), "dir": Vector2(0, 1), "who": "last"},
		"start": {"pos": Vector2(0, -lead + _rig_len(kind) - _front_len(kind) + 1.0), "th": PI / 2},
		"demo": [{"dir": 1, "path": demo_path, "until": "finish"}],
		"asphalt": [_bounds(lr, 3.0)],
		"tips": [
			"꺾이는 곳 직전에 바깥쪽으로 붙어서 들어가세요. 트레일러 바퀴는 트럭보다 안쪽으로 돌아요.",
			"트럭 앞바퀴가 모서리를 지나고 나서 핸들을 크게 감으면 트레일러 뒷바퀴가 안쪽 선을 덜 밟아요.",
			"두 번째 굴절에서 트레일러 뒷바퀴 탈선이 가장 많아요. 사이드미러로 트레일러 바퀴를 보세요.",
		],
	}
	return _place(step, o)


## A polyline with each corner replaced by an arc of radius r, every arc
## moved s metres towards the outside of its bend (wide entry, late apex).
static func fillet_path(pts: PackedVector2Array, r: float, s: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var d1 := (pts[i] - pts[i - 1]).normalized()
		var d2 := (pts[i + 1] - pts[i]).normalized()
		var turn := signf(d1.cross(d2))
		var l1 := Vector2(-d1.y, d1.x)
		var l2 := Vector2(-d2.y, d2.x)
		var p := pts[i] - l1 * turn * s - l2 * turn * s
		var t1 := p - d1 * r
		var cen := t1 + l1 * turn * r
		var a0 := (t1 - cen).angle()
		var sweep := turn * absf(d1.angle_to(d2))
		out.append_array(arc(cen, r, a0, a0 + sweep, 12))
	out.append(pts[pts.size() - 1])
	return out


static func _front_len(kind: String) -> float:
	var s: Dictionary = Rig.SPECS[kind]
	return s.L + s.front_oh


## 곡선코스: an S bend (left arc, then right arc), driven forward.
static func curve(kind: String, o: Vector2) -> Dictionary:
	var z := _size(kind)
	var lead := _rig_len(kind) + 3.0
	var r: float = z.sr
	var center := _s_bend(r, lead, _rig_len(kind))
	var lr := offset_lines(center, z.sw)
	var top: float = center[center.size() - 1].y - 5.0 - _rig_len(kind)
	var xend: float = center[center.size() - 1].x
	var step := {
		"id": "curve", "type": "course", "title": "곡선코스", "kind": kind,
		"time_limit": 180.0,
		"lines": lr,
		"confirms": [],
		"finish": {"a": Vector2(xend - z.sw * 0.5, top), "b": Vector2(xend + z.sw * 0.5, top), "dir": Vector2(0, 1), "who": "last"},
		"start": {"pos": Vector2(0, -lead + _rig_len(kind) - _front_len(kind) + 1.0), "th": PI / 2},
		"demo": [{"dir": 1, "path": _s_demo(center, z.sw * z.sk), "until": "finish"}],
		"asphalt": [_bounds(lr, 3.0)],
		"tips": [
			"곡선에서는 트럭을 바깥쪽 선 가까이 두세요. 트레일러는 안쪽으로 파고들어요.",
			"핸들은 한 번에 크게 꺾지 말고 곡선을 따라 조금씩 감고 풀어 주세요.",
			"S자 가운데에서 방향이 바뀔 때 핸들을 반대로 넘기기 전에 트레일러가 따라왔는지 보세요.",
		],
	}
	return _place(step, o)


## Centre line of an S bend: up, 60° left arc, 60° right arc, up.
static func _s_bend(r: float, lead: float, rig_len: float) -> PackedVector2Array:
	var ang := deg_to_rad(70.0)
	var p := PackedVector2Array([Vector2(0, -lead)])
	# left arc: centre to the left (-x) of the start point
	var c1 := Vector2(-r, 0)
	p.append_array(arc(c1, r, 0.0, ang, 14))
	var mid: Vector2 = p[p.size() - 1]
	# right arc: centre mirrored across the hand-over point
	var c2 := mid + (mid - c1)
	var a0 := (mid - c2).angle()
	var arc2 := arc(c2, r, a0, a0 - ang, 14)
	for i in arc2.size():
		if i > 0:
			p.append(arc2[i])
	var e: Vector2 = p[p.size() - 1]
	p.append(e + Vector2(0, rig_len + 8.0))
	return p


static func _s_demo(center: PackedVector2Array, k: float) -> PackedVector2Array:
	# Ride a little to the outside of each arc so the trailer tracks the middle.
	var out := PackedVector2Array()
	var n := center.size()
	for i in n:
		var p: Vector2 = center[i]
		if i > 0 and i < n - 1:
			var a: Vector2 = center[i - 1]
			var b: Vector2 = center[i + 1]
			var turn := signf((p - a).cross(b - p))
			var nrm := _normal(a, b)
			p += nrm * -turn * k
		out.append(p)
	return out


## 방향전환코스: drive up past a bay on the right, reverse into it until the
## rear wheels touch the confirm line, then drive out to the left and finish.
## For the large rig the A line at the top must be touched by a front wheel
## before reversing, and the bay holds the B line.
static func garage(kind: String, o: Vector2) -> Dictionary:
	var z := _size(kind)
	var spec: Dictionary = Rig.SPECS[kind]
	var solo := kind == "wrecker"   # the wrecker runs this course after dropping the car
	var rw: float = z.gw_road
	var gw: float = z.g_width
	var r: float = z.g_rev_r                    # reverse arc of the backing unit's axle
	var xr := rw * 0.5
	var back: float = 0.0 if solo else spec.c + spec.trailer.D   # rear axle -> trailer axle
	var gy := _rig_len(kind) + 4.0              # bay centre along the road
	var x0: float = xr - 0.4 - r                # lane the rig pulls up in
	var top: float = gy + r + 1.5 + back + spec.L + spec.front_oh + 1.5
	var bottom := -6.0
	var depth: float = z.g_conf + 1.2
	var conf_x: float = xr + z.g_conf
	var lines := []
	# left edge of the road, top end, right edge with the bay cut in
	lines.append(PackedVector2Array([Vector2(-xr, bottom), Vector2(-xr, top), Vector2(xr, top),
		Vector2(xr, gy + gw * 0.5), Vector2(xr + depth, gy + gw * 0.5), Vector2(xr + depth, gy - gw * 0.5),
		Vector2(xr, gy - gw * 0.5), Vector2(xr, bottom)]))
	var confirms := []
	if kind == "large":
		confirms.append({"id": "A", "label": "A 확인선", "a": Vector2(-xr, top - 1.6), "b": Vector2(xr, top - 1.6), "who": "tractor_front"})
	confirms.append({"id": "B", "label": "B 확인선" if kind == "large" else "확인선", "a": Vector2(conf_x, gy - gw * 0.5), "b": Vector2(conf_x, gy + gw * 0.5), "who": "tractor_rear" if solo else "trailer_rear"})
	# demo: up the lane, back into the bay, out to the left and down
	var stop_y: float = top - 1.6 - spec.L if kind == "large" else gy + r + 1.5 + back
	var demo := []
	demo.append({"dir": 1, "path": PackedVector2Array([Vector2(x0, bottom - 40.0), Vector2(x0, top + 20.0)]), "until": "A" if kind == "large" else "stop", "stop": stop_y})
	var rev := PackedVector2Array([Vector2(x0, top + 10.0)])
	rev.append_array(arc(Vector2(x0 + r, gy + r), r, PI, PI * 1.5, 16))
	rev.append(Vector2(conf_x + 8.0, gy))
	demo.append({"dir": -1, "path": rev, "until": "B", "follow": "tractor" if solo else "trailer"})
	var ro: float = spec.L / tan(deg_to_rad(spec.max_steer)) * 1.5
	var x_out := minf(0.0, xr + 0.5 - ro)
	if kind == "large":   # pull the trailer out of the bay before turning
		ro = 5.8
		x_out = 0.5 - ro
	var out := PackedVector2Array([Vector2(conf_x + 4.0, gy)])
	out.append_array(arc(Vector2(x_out + ro, gy - ro), ro, PI * 0.5, PI, 12))
	out.append(Vector2(x_out, bottom - 60.0))
	demo.append({"dir": 1, "path": out, "until": "finish"})
	var step := {
		"id": "garage", "type": "course", "title": "방향전환코스", "kind": kind,
		"time_limit": 300.0 if kind == "large" else 180.0,
		"lines": lines,
		"confirms": confirms,
		"finish": {"a": Vector2(-xr, 0.0), "b": Vector2(xr, 0.0), "dir": Vector2(0, -1), "who": "tractor_front_axle", "after": "B"},
		"start": {"pos": Vector2(x0, -2.0 - spec.L - spec.front_oh), "th": PI / 2},
		"demo": demo,
		"asphalt": [Rect2(Vector2(-xr - 3.0, bottom - _rig_len(kind) - 6.0), Vector2(rw + 5.0 + depth, top - bottom + _rig_len(kind) + 9.0))],
		"tips": _garage_tips(kind),
		"solo": solo,
	}
	return _place(step, o)


static func _garage_tips(kind: String) -> Array:
	var t := [
		"트레일러 후진은 핸들을 반대로: 트레일러 꼬리를 오른쪽으로 보내려면 핸들을 왼쪽으로 먼저 감아요.",
		"트레일러가 원하는 만큼 꺾이기 시작하면 핸들을 반대로 풀어 트럭이 트레일러를 따라가게 하세요.",
		"후진 중에 많이 틀어졌으면 무리하지 말고 조금 전진해서 펴고 다시 후진하세요.",
	]
	match kind:
		"large":
			t.push_front("A 확인선은 앞바퀴로 꼭 밟고, B 확인선까지 3분 30초 안에 들어오는 게 목표예요.")
			t.append("트랙터와 트레일러가 예각(직각보다 더)으로 꺾이면 바로 실격이에요.")
		"wrecker":
			t = ["구난차만 단독으로 하는 코스예요. 차고 안 확인선을 뒷바퀴로 밟고 나오세요.",
				"차체가 길어서 회전 반경이 커요. 차고 입구를 지나 충분히 올라간 뒤 후진하세요."]
	return t


# ---------------------------------------------------------------- coupling

const COUPLE_STEPS := {
	"large": ["트랙터를 트레일러 앞에 일직선으로 맞추기", "후진해 킹핀 결합 (철컥)", "살짝 당겨 결합 확인", "에어호스·전기선 연결", "랜딩기어 올리기"],
	"wrecker": ["언더리프트 내리기", "바퀴 받침(포크)을 앞바퀴에 맞추기", "바퀴 고정 스트랩 걸기", "안전 체인 연결", "언더리프트 들어 올리기"],
}
const UNCOUPLE_STEPS := {
	"large": ["주차 브레이크 채우기", "랜딩기어 내리기", "에어호스·전기선 분리", "킹핀 해제 레버 당기기", "천천히 전진해 빠져나오기"],
	"wrecker": ["주차 브레이크 채우기", "언더리프트 내리기", "안전 체인 풀기", "바퀴 고정 스트랩 풀기", "언더리프트 올리고 전진"],
}


static func couple(kind: String, o: Vector2) -> Dictionary:
	var spec: Dictionary = Rig.SPECS[kind]
	var t: Dictionary = spec.trailer
	# trailer parked pointing +y; its hitch point sits at the origin
	var start_gap := 7.0
	var hitch_y := 0.0
	var tractor_axle_y: float = hitch_y + spec.c + start_gap
	var step := {
		"id": "couple", "type": "couple", "title": "연결" if kind == "large" else "피견인차 연결", "kind": kind,
		"time_limit": 300.0,
		"lines": [],
		"paint": [PackedVector2Array([Vector2(-3.5, -t.back - 2.0), Vector2(-3.5, 18.0)]), PackedVector2Array([Vector2(3.5, -t.back - 2.0), Vector2(3.5, 18.0)])],
		"trailer_pose": {"pos": Vector2(0, hitch_y), "th": PI / 2},
		"start": {"pos": Vector2(0.55, tractor_axle_y), "th": PI / 2 + deg_to_rad(5.0)},
		"checklist": COUPLE_STEPS[kind].slice(2) if kind == "large" else COUPLE_STEPS[kind],
		"demo": [{"dir": -1, "path": PackedVector2Array([Vector2(0, 30.0), Vector2(0, hitch_y + spec.c), Vector2(0, -20.0)]), "until": "coupled"}],
		"asphalt": [Rect2(Vector2(-6, -t.back - 4.0), Vector2(12, t.back + 26.0))],
		"tips": ["후진하면서 차 뒤를 트레일러(피견인차) 앞과 일직선으로 맞추세요." if kind == "large" else "구난차 뒤를 피견인차 앞범퍼 정중앙에 맞춰 천천히 후진하세요.",
			"거의 닿으면 아주 천천히. 너무 세게 밀면 충돌로 실격이에요.",
			"맞춰지면 순서대로 연결 작업을 고르세요. 순서가 틀리면 감점이에요."],
	}
	return _place(step, o)


static func uncouple(kind: String, o: Vector2) -> Dictionary:
	var spec: Dictionary = Rig.SPECS[kind]
	var zone_len := _rig_len(kind) + 2.0
	var zone := PackedVector2Array([Vector2(-2.6, 2.0), Vector2(2.6, 2.0), Vector2(2.6, 2.0 + zone_len), Vector2(-2.6, 2.0 + zone_len)])
	var lead := _rig_len(kind) + 2.0
	var step := {
		"id": "uncouple", "type": "uncouple", "title": "분리" if kind == "large" else "피견인차 분리", "kind": kind,
		"time_limit": 300.0,
		"lines": [],
		"paint": [zone + PackedVector2Array([zone[0]])],
		"zone": zone,
		"start": {"pos": Vector2(0, -lead + spec.c + spec.trailer.back - 2.0), "th": PI / 2},
		"checklist": UNCOUPLE_STEPS[kind],
		"demo": [{"dir": 1, "path": PackedVector2Array([Vector2(0, -40), Vector2(0, 80)]), "until": "zone"}],
		"asphalt": [Rect2(Vector2(-6, -lead - 14.0), Vector2(12, lead + zone_len + 30.0))],
		"tips": ["주차 구역 안에 트레일러까지 다 들어오게 세우세요.", "분리는 순서가 중요해요. 랜딩기어를 내리기 전에 킹핀을 풀면 안 돼요." if kind == "large" else "언더리프트를 내린 뒤에 고정 장치를 풀어야 해요."],
	}
	return _place(step, o)
