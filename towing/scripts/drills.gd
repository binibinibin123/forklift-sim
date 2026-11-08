class_name TowDrills
extends RefCounted
## 훈련장: short reversing drills with the small rig, scored like a course
## (line touches -10, pass at 90). Built from the same step dictionaries as
## the exam courses so Exam, TowAutopilot and TowWorld handle them unchanged.

const LIST := [
	{"id": "straight_back", "title": "직진 후진", "desc": "트레일러를 흔들리지 않게 20 m 똑바로 후진", "free": true},
	{"id": "back_90", "title": "90도 후진", "desc": "오른쪽 주차칸으로 직각 후진", "free": false},
	{"id": "s_back", "title": "S자 후진", "desc": "구불구불한 통로를 후진으로 통과", "free": false},
	{"id": "free", "title": "자유 연습", "desc": "넓은 마당에서 마음껏 연결·후진 연습", "free": false},
]


static func is_drill(id: String) -> bool:
	for d in LIST:
		if d.id == id:
			return true
	return false


static func info(id: String) -> Dictionary:
	for d in LIST:
		if d.id == id:
			return d
	return {}


static func step(kind: String, id: String, o := Vector2.ZERO) -> Dictionary:
	match id:
		"straight_back":
			return _straight(kind, o)
		"back_90":
			return _back90(kind, o)
		"s_back":
			return _sback(kind, o)
		"free":
			return _free(kind, o)
	return {}


static func _rig_len(kind: String) -> float:
	var s: Dictionary = Rig.SPECS[kind]
	return s.L + s.front_oh + s.c + s.trailer.back


## A straight lane; back the whole rig down it and cross the line at the end.
static func _straight(kind: String, o: Vector2) -> Dictionary:
	var spec: Dictionary = Rig.SPECS[kind]
	var w: float = spec.trailer.width + 1.4
	var len := 20.0
	var lead := _rig_len(kind) + 2.0
	var lines := [PackedVector2Array([Vector2(-w * 0.5, len + lead), Vector2(-w * 0.5, 0.0)]),
		PackedVector2Array([Vector2(w * 0.5, len + lead), Vector2(w * 0.5, 0.0)])]
	var step := {
		"id": "straight_back", "type": "course", "title": "직진 후진", "kind": kind, "time_limit": 120.0,
		"lines": lines, "confirms": [],
		"finish": {"a": Vector2(-w * 0.5, 0.0), "b": Vector2(w * 0.5, 0.0), "dir": Vector2(0, -1), "who": "last"},
		"start": {"pos": Vector2(0, len + spec.c + spec.trailer.back + 1.0), "th": PI / 2},
		"demo": [{"dir": -1, "path": PackedVector2Array([Vector2(0, len + 30.0), Vector2(0, -30.0)]), "until": "finish", "follow": "trailer"}],
		"asphalt": [Rect2(Vector2(-w * 0.5 - 4.0, -8.0), Vector2(w + 8.0, len + lead + 12.0))],
		"tips": ["트레일러가 한쪽으로 가기 시작하면 핸들을 그쪽으로 아주 조금만 돌려 바로잡아요.",
			"핸들을 크게 돌릴수록 트레일러는 빨리 꺾여요. 작게, 자주."],
		"coach": "직진 후진이에요. 사이드미러로 트레일러를 보며 작게 바로잡으세요",
	}
	return Courses._place(step, o)


## Back from a road into a bay on the right at 90 degrees.
static func _back90(kind: String, o: Vector2) -> Dictionary:
	var spec: Dictionary = Rig.SPECS[kind]
	var rw := 8.0
	var bw: float = spec.trailer.width + 1.6
	var depth: float = spec.trailer.back + 1.5
	var r := 5.0
	var xr := rw * 0.5
	var gy := _rig_len(kind) + 2.0
	var top: float = gy + r + 2.0 + spec.c + spec.trailer.D + spec.L + spec.front_oh + 2.0
	var lines := [PackedVector2Array([Vector2(-xr, -4.0), Vector2(-xr, top), Vector2(xr, top),
		Vector2(xr, gy + bw * 0.5), Vector2(xr + depth, gy + bw * 0.5), Vector2(xr + depth, gy - bw * 0.5),
		Vector2(xr, gy - bw * 0.5), Vector2(xr, -4.0)])]
	var conf_x: float = xr + depth - 1.2
	var x0 := xr - 0.4 - r
	var rev := PackedVector2Array([Vector2(x0, top + 10.0)])
	rev.append_array(Courses.arc(Vector2(x0 + r, gy + r), r, PI, PI * 1.5, 16))
	rev.append(Vector2(conf_x + 8.0, gy))
	var step := {
		"id": "back_90", "type": "course", "title": "90도 후진", "kind": kind, "time_limit": 180.0,
		"lines": lines,
		"confirms": [{"id": "B", "label": "확인선", "a": Vector2(conf_x, gy - bw * 0.5), "b": Vector2(conf_x, gy + bw * 0.5), "who": "trailer_rear"}],
		"finish": {"a": Vector2(conf_x, gy - bw * 0.5), "b": Vector2(conf_x, gy + bw * 0.5), "dir": Vector2(1, 0), "who": "last", "after": "B"},
		"start": {"pos": Vector2(x0, -2.0 - spec.L - spec.front_oh + 4.0), "th": PI / 2},
		"demo": [{"dir": 1, "path": PackedVector2Array([Vector2(x0, -40.0), Vector2(x0, top + 20.0)]), "until": "stop", "stop": gy + r + 2.0 + spec.c + spec.trailer.D},
			{"dir": -1, "path": rev, "until": "finish", "follow": "trailer"}],
		"asphalt": [Rect2(Vector2(-xr - 3.0, -8.0 - _rig_len(kind)), Vector2(rw + 5.0 + depth, top + 12.0 + _rig_len(kind)))],
		"tips": ["칸 입구를 지나 트레일러 바퀴가 입구보다 한 차 길이쯤 위에 올 때까지 올라가세요.",
			"핸들을 왼쪽으로 감아 트레일러 꼬리를 오른쪽 칸으로 보내고, 꺾이기 시작하면 바로 풀어요."],
		"coach": "90도 후진이에요. 꼬리를 보낼 반대쪽으로 핸들을 먼저 감으세요",
	}
	return Courses._place(step, o)


## An S-shaped lane taken in reverse.
static func _sback(kind: String, o: Vector2) -> Dictionary:
	var spec: Dictionary = Rig.SPECS[kind]
	var w: float = spec.trailer.width + 2.4
	var r := 11.0
	var lead := _rig_len(kind) + 3.0
	var center := PackedVector2Array([Vector2(0, lead * 2.0 + 4.0), Vector2(0, 0)])
	var a0 := Courses.arc(Vector2(r, 0), r, PI, PI * 1.5, 14)
	center.append_array(a0.slice(1))
	var a1 := Courses.arc(Vector2(r, -2.0 * r), r, PI * 0.5, 0.0, 14)
	center.append_array(a1.slice(1))
	center.append(Vector2(2.0 * r, -2.0 * r - lead - 6.0))
	var lr := Courses.offset_lines(center, w)
	var last := center[center.size() - 1]
	var end_y := last.y + lead + 2.0
	var step := {
		"id": "s_back", "type": "course", "title": "S자 후진", "kind": kind, "time_limit": 240.0,
		"lines": [lr[0], lr[1]], "confirms": [],
		"finish": {"a": Vector2(2.0 * r - w * 0.5, end_y), "b": Vector2(2.0 * r + w * 0.5, end_y), "dir": Vector2(0, -1), "who": "last"},
		"start": {"pos": Vector2(0, lead + 2.0 + spec.c + spec.trailer.back), "th": PI / 2},
		"demo": [{"dir": -1, "path": _reverse_path(center, 40.0), "until": "finish", "follow": "trailer"}],
		"asphalt": [Courses._bounds([lr[0], lr[1]], 8.0)],
		"tips": ["트레일러 꼬리가 갈 방향의 반대로 핸들을 돌려 커브에 넣고, 바로 되돌려 따라가게 하세요.",
			"한 번에 한 커브만 생각하세요. 꺾임이 커지면 멈추고 조금 전진해 펴세요."],
		"coach": "S자 후진이에요. 꺾임이 커지기 전에 핸들을 되돌리세요",
	}
	return Courses._place(step, o)


static func _reverse_path(center: PackedVector2Array, extra: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.append(center[0] + Vector2(0, extra))
	p.append_array(center)
	var last := center[center.size() - 1]
	p.append(last + Vector2(0, -extra))
	return p


## A wide open yard: no lines, no clock, leave with the exit button.
static func _free(kind: String, o: Vector2) -> Dictionary:
	var spec: Dictionary = Rig.SPECS[kind]
	var half := 45.0
	var step := {
		"id": "free", "type": "course", "title": "자유 연습", "kind": kind, "time_limit": 1e9,
		"lines": [], "confirms": [],
		"paint": [PackedVector2Array([Vector2(-half + 10, -half + 10), Vector2(half - 10, -half + 10), Vector2(half - 10, half - 10), Vector2(-half + 10, half - 10), Vector2(-half + 10, -half + 10)]),
			PackedVector2Array([Vector2(-6, 0), Vector2(6, 0)]), PackedVector2Array([Vector2(0, -6), Vector2(0, 6)])],
		"finish": {"a": Vector2(-half, half + 50.0), "b": Vector2(half, half + 50.0), "dir": Vector2(0, 1), "who": "tractor_front_axle"},
		"start": {"pos": Vector2(0, -spec.L), "th": PI / 2},
		"demo": [{"dir": 1, "path": PackedVector2Array([Vector2(0, -60), Vector2(0, 60)]), "until": "finish"}],
		"asphalt": [Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0))],
		"tips": ["점수도 시간도 없어요. 핸들 방향과 트레일러 움직임의 관계를 몸으로 익히세요."],
		"coach": "자유 연습이에요. 시간 제한 없이 마음껏 해 보세요",
		"free_run": true,
	}
	return Courses._place(step, o)
