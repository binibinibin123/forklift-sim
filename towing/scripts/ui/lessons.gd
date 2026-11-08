class_name LessonsScreen
extends Control
## "원리 배우기": short lessons on how a towed unit behaves, each with a
## looping animated plan-view diagram driven by the real vehicle model.

signal closed

const LESSONS := [
	{"id": "opposite", "title": "후진은 반대로", "lines": [
		"트레일러를 후진시킬 때 핸들을 왼쪽으로 돌리면 트레일러 꼬리는 오른쪽으로 갑니다.",
		"트럭 뒤가 왼쪽으로 가면서 연결점이 트레일러를 밀어 꺾기 때문이에요.",
		"그래서 '꼬리를 보내고 싶은 반대 방향으로 핸들을 먼저 감는다'가 기본입니다."],
		"anim": [{"steer": 1.0, "dir": -1, "t": 5.0}, {"steer": 0.0, "dir": 1, "t": 5.0}]},
	{"id": "follow", "title": "꺾이면 따라가기", "lines": [
		"트레일러가 원하는 만큼 꺾였으면 핸들을 반대로 풀어 트럭이 트레일러를 따라가게 합니다.",
		"그대로 두면 각도가 계속 커져 잭나이프가 됩니다.",
		"조금 감고, 꺾이기 시작하면 바로 풀기. 이 리듬이 전부입니다."],
		"anim": [{"steer": 0.8, "dir": -1, "t": 2.2}, {"steer": -0.8, "dir": -1, "t": 3.0}, {"steer": 0.0, "dir": -1, "t": 1.5}, {"steer": 0.0, "dir": 1, "t": 6.0}]},
	{"id": "jack", "title": "잭나이프", "lines": [
		"트럭과 트레일러 사이 각(히치각)이 너무 커지면 더 이상 바로잡을 수 없습니다.",
		"실제 시험에서는 예각으로 꺾이는 순간 실격이에요.",
		"히치각 게이지가 노란 구간에 들어가면 전진해서 펴고 다시 후진하세요."],
		"anim": [{"steer": 1.0, "dir": -1, "t": 7.0}, {"steer": 0.0, "dir": 1, "t": 6.0}]},
	{"id": "pivot", "title": "회전 중심과 내륜차", "lines": [
		"차는 뒷바퀴 축의 연장선 위 한 점을 중심으로 돕니다.",
		"그래서 뒷바퀴와 트레일러 바퀴는 앞바퀴보다 안쪽으로 지나갑니다(내륜차).",
		"굴절·곡선코스에서는 바깥쪽으로 크게 들어가야 뒷바퀴가 안쪽 선을 넘지 않아요."],
		"anim": [{"steer": -0.9, "dir": 1, "t": 6.0}, {"steer": 0.9, "dir": 1, "t": 6.0}]},
]

var map: MiniMap
var rig: Rig
var cur := 0
var seg := 0
var seg_t := 0.0
var title_lbl: Label
var body_lbl: Label
var tabs: Array = []
var trail := PackedVector2Array()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 40)
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 20)
	add_child(m)
	var v := Kit.vbox(12)
	m.add_child(v)
	var top := Kit.hbox(10)
	v.add_child(top)
	top.add_child(Kit.label("원리 배우기", 32))
	top.add_child(Kit.spacer())
	top.add_child(Kit.button("닫기", func(): closed.emit(), 20, "ghost"))
	var row := Kit.hbox(10)
	v.add_child(row)
	for i in LESSONS.size():
		var b := Kit.button(LESSONS[i].title, func(): _select(i), 20)
		row.add_child(b)
		tabs.append(b)
	var h := Kit.hbox(24)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	map = MiniMap.new()
	map.custom_minimum_size = Vector2(440, 380)
	map.follow = false
	map.show_frame = true
	h.add_child(map)
	var right := Kit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	title_lbl = Kit.label("", 30, Kit.PRIMARY)
	right.add_child(title_lbl)
	body_lbl = Kit.wrap("", 22, Kit.TEXT, 560)
	right.add_child(body_lbl)
	_select(0)


func _select(i: int) -> void:
	cur = i
	var l: Dictionary = LESSONS[i]
	title_lbl.text = l.title
	var txt := ""
	for k in l.lines.size():
		txt += "%d. %s\n\n" % [k + 1, l.lines[k]]
	body_lbl.text = txt.strip_edges()
	for k in tabs.size():
		tabs[k].add_theme_stylebox_override("normal", Kit.sb(Kit.PRIMARY if k == i else Kit.PANEL_LIGHT, 14, 10))
	_restart()


func _restart() -> void:
	rig = Rig.new("small")
	rig.set_pose(Vector2(0, 0), PI / 2)
	seg = 0
	seg_t = 0.0
	trail = PackedVector2Array()
	var half := 16.0
	map.step = {"asphalt": [Rect2(Vector2(-half, -half), Vector2(half * 2, half * 2))], "lines": [], "paint": [], "confirms": []}
	map.rig = rig
	map.trail = trail


func _process(dt: float) -> void:
	if not visible or rig == null:
		return
	var anim: Array = LESSONS[cur].anim
	var a: Dictionary = anim[seg]
	rig.steer = move_toward(rig.steer, float(a.steer), dt * 1.5)
	rig.reverse = int(a.dir) < 0
	rig.throttle = 0.5
	rig.step(dt * 1.6)
	if rig.jackknifed:
		rig.jackknifed = false
	seg_t += dt
	if seg_t >= float(a.t):
		seg_t = 0.0
		seg += 1
		if seg >= anim.size():
			_restart()
			return
	trail.append(rig.trailer_axle())
	if trail.size() > 400:
		trail.remove_at(0)
	map.trail = trail
	map.queue_redraw()
