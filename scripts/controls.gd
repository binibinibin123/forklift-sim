class_name Controls
extends Control
## 화면 조작부: 핸들, 전후진·리프트·틸트 레버, 가속·브레이크 페달, 버튼.
## 손가락 여러 개를 따로 추적한다(InputEventScreenTouch index).

signal action(name: String)

const PANEL := Color(0.05, 0.06, 0.07, 0.55)
const INK := Color(0.96, 0.96, 0.94)
const DIM := Color(0.96, 0.96, 0.94, 0.55)
const ACCENT := Color(1.0, 0.68, 0.1)
const RED := Color(0.92, 0.25, 0.2)
const GREEN := Color(0.3, 0.8, 0.4)
const WHEEL_TURNS := 1.5          # 끝에서 끝까지 핸들 회전 수의 절반

# 출력 값
var wheel_rot := 0.0              # 라디안, 시계방향 +
var throttle := 0.0
var brake := 0.0
var lift := 0.0
var tilt := 0.0
var gear := 0
var seatbelt := false
var park_brake := true
var buttons := {}                 # name -> {rect, label, on}
var enabled := true

var _touch := {}                  # index -> widget name
var _wheel_last := 0.0
var _rects := {}
var _wheel_c := Vector2.ZERO
var _wheel_r := 150.0
var _font: Font
var _sim_steer := 0.0             # 실제 뒷바퀴 각도(표시용)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_layout.call_deferred()


func steer() -> float:
	return clampf(-wheel_rot / (TAU * WHEEL_TURNS), -1.0, 1.0)


func set_button(name: String, label: String, on := false) -> void:
	if buttons.has(name):
		buttons[name].label = label
		buttons[name].on = on
		queue_redraw()


func reset() -> void:
	wheel_rot = 0.0
	throttle = 0.0
	brake = 0.0
	lift = 0.0
	tilt = 0.0
	gear = 0
	seatbelt = false
	park_brake = true
	_touch.clear()
	queue_redraw()


func _layout() -> void:
	var vs := get_viewport_rect().size
	size = vs
	var W := vs.x
	var H := vs.y
	_wheel_r = clampf(H * 0.21, 110, 170)
	_wheel_c = Vector2(_wheel_r + 50, H - _wheel_r - 40)
	var lh := clampf(H * 0.38, 200, 290)
	var top := H - lh - 30
	_rects = {
		"accel": Rect2(W - 150, top - 20, 120, lh + 20),
		"brake": Rect2(W - 285, top + 40, 120, lh - 40),
		"tilt": Rect2(W - 390, top, 84, lh),
		"lift": Rect2(W - 495, top, 84, lh),
		"gear": Rect2(W - 600, top, 84, lh),
	}
	var bw := 128.0
	var bh := 56.0
	var old := buttons.duplicate(true)
	buttons = {
		"seatbelt": {rect = Rect2(20, 20, bw, bh), label = "안전벨트", on = seatbelt},
		"park": {rect = Rect2(20 + bw + 12, 20, bw, bh), label = "주차 브레이크", on = park_brake},
		"signal": {rect = Rect2(20, 20 + bh + 12, bw * 2 + 12, bh), label = "시작 신호", on = false},
		"menu": {rect = Rect2(W - bw - 20, 20, bw, bh), label = "메뉴", on = false},
		"camera": {rect = Rect2(W - 2 * bw - 32, 20, bw, bh), label = "시점", on = false},
		"look": {rect = Rect2(W - 3 * bw - 44, 20, bw, bh), label = "뒤 보기", on = false},
	}
	for b in old:
		if buttons.has(b):
			buttons[b].label = old[b].label
			buttons[b].on = old[b].on
	queue_redraw()


# ---------- 입력 ----------
func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var w := _hit(event.position)
			if w != "":
				_touch[event.index] = w
				_press(w, event.position)
				get_viewport().set_input_as_handled()
		elif _touch.has(event.index):
			_release(_touch[event.index])
			_touch.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _touch.has(event.index):
		_drag(_touch[event.index], event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: gear = 1
			KEY_2: gear = 0
			KEY_3: gear = -1
			KEY_B: _toggle("seatbelt")
			KEY_P: _toggle("park")
			KEY_C: action.emit("camera")
			KEY_V: action.emit("look")
			KEY_ENTER: action.emit("signal")
		queue_redraw()


func _hit(p: Vector2) -> String:
	for b in buttons:
		if buttons[b].rect.has_point(p):
			return "btn:" + b
	if p.distance_to(_wheel_c) < _wheel_r * 1.15:
		return "wheel"
	for k in _rects:
		if _rects[k].grow(14).has_point(p):
			return k
	return ""


func _press(w: String, p: Vector2) -> void:
	if w.begins_with("btn:"):
		var b := w.substr(4)
		if b == "seatbelt" or b == "park":
			_toggle(b)
		else:
			action.emit(b)
		return
	if w == "wheel":
		_wheel_last = (p - _wheel_c).angle()
		return
	_drag(w, p)


func _toggle(b: String) -> void:
	if b == "seatbelt":
		seatbelt = not seatbelt
		buttons.seatbelt.on = seatbelt
	elif b == "park":
		park_brake = not park_brake
		buttons.park.on = park_brake
	action.emit(b)
	queue_redraw()


func _drag(w: String, p: Vector2) -> void:
	var r: Rect2 = _rects.get(w, Rect2())
	match w:
		"wheel":
			var a := (p - _wheel_c).angle()
			wheel_rot = clampf(wheel_rot + wrapf(a - _wheel_last, -PI, PI), -TAU * WHEEL_TURNS, TAU * WHEEL_TURNS)
			_wheel_last = a
		"accel":
			throttle = clampf(1.0 - (p.y - r.position.y) / r.size.y, 0.15, 1.0)
		"brake":
			brake = clampf(1.0 - (p.y - r.position.y) / r.size.y, 0.25, 1.0)
		"lift", "tilt":
			var v := clampf((p.y - r.get_center().y) / (r.size.y * 0.42), -1.0, 1.0)
			if absf(v) < 0.12:
				v = 0.0
			if w == "lift":
				lift = v
			else:
				tilt = v
		"gear":
			var f := (p.y - r.position.y) / r.size.y
			gear = 1 if f < 0.36 else (-1 if f > 0.64 else 0)
	queue_redraw()


func _release(w: String) -> void:
	match w:
		"accel": throttle = 0.0
		"brake": brake = 0.0
		"lift": lift = 0.0
		"tilt": tilt = 0.0
	queue_redraw()


## 키보드(데스크톱 시험용) 연속 입력
func poll_keys(dt: float) -> void:
	if not enabled:
		return
	var k := false
	if Input.is_key_pressed(KEY_A):
		wheel_rot -= dt * 6.0
		k = true
	if Input.is_key_pressed(KEY_D):
		wheel_rot += dt * 6.0
		k = true
	wheel_rot = clampf(wheel_rot, -TAU * WHEEL_TURNS, TAU * WHEEL_TURNS)
	if not _touch.values().has("accel"):
		throttle = 1.0 if Input.is_key_pressed(KEY_W) else 0.0
	if not _touch.values().has("brake"):
		brake = 1.0 if Input.is_key_pressed(KEY_S) else 0.0
	if not _touch.values().has("lift"):
		lift = (1.0 if Input.is_key_pressed(KEY_R) else 0.0) - (1.0 if Input.is_key_pressed(KEY_F) else 0.0)
	if not _touch.values().has("tilt"):
		tilt = (1.0 if Input.is_key_pressed(KEY_T) else 0.0) - (1.0 if Input.is_key_pressed(KEY_G) else 0.0)
	if k or throttle > 0 or brake > 0 or lift != 0 or tilt != 0:
		queue_redraw()


func show_steer(s: float) -> void:
	if absf(s - _sim_steer) > 0.001:
		_sim_steer = s
		queue_redraw()


# ---------- 그리기 ----------
func _text(p: Vector2, t: String, fs := 22, c := INK, align := HORIZONTAL_ALIGNMENT_CENTER, w := -1.0) -> void:
	draw_string(_font, p, t, align, w, fs, c)


func _draw() -> void:
	if _rects.is_empty():
		return
	# 버튼
	for b in buttons:
		var d: Dictionary = buttons[b]
		if b == "signal" and d.label == "":
			continue
		var col := PANEL
		if d.on:
			col = Color(ACCENT, 0.85) if b != "park" else Color(RED, 0.8)
		if b == "signal":
			col = Color(GREEN, 0.85)
		draw_rect(d.rect, col)
		draw_rect(d.rect, Color(1, 1, 1, 0.25), false, 2.0)
		_text(Vector2(d.rect.position.x, d.rect.get_center().y + 8), d.label, 22, INK, HORIZONTAL_ALIGNMENT_CENTER, d.rect.size.x)

	# 핸들
	draw_circle(_wheel_c, _wheel_r, Color(0, 0, 0, 0.22))
	draw_arc(_wheel_c, _wheel_r - 12, 0, TAU, 64, Color(0.12, 0.12, 0.13, 0.95), 22.0)
	draw_arc(_wheel_c, _wheel_r - 12, 0, TAU, 64, Color(1, 1, 1, 0.12), 2.0)
	for i in 3:
		var a := wheel_rot + PI / 2 + i * TAU / 3
		draw_line(_wheel_c, _wheel_c + Vector2(cos(a), sin(a)) * (_wheel_r - 20), Color(0.12, 0.12, 0.13, 0.9), 12.0)
	draw_circle(_wheel_c, 26, Color(0.15, 0.15, 0.16, 0.95))
	var ka := wheel_rot - PI / 2
	draw_circle(_wheel_c + Vector2(cos(ka), sin(ka)) * (_wheel_r - 12), 20, RED)
	# 뒷바퀴 방향 표시(위에서 본 지게차)
	var ic := _wheel_c + Vector2(_wheel_r + 60, -_wheel_r + 50)
	draw_rect(Rect2(ic + Vector2(-16, -34), Vector2(32, 68)), Color(ACCENT, 0.9))
	draw_rect(Rect2(ic + Vector2(-14, -50), Vector2(5, 16)), INK)
	draw_rect(Rect2(ic + Vector2(9, -50), Vector2(5, 16)), INK)
	for sx in [-22, 22]:
		draw_rect(Rect2(ic + Vector2(sx - 4, -32), Vector2(8, 18)), Color(0.1, 0.1, 0.1))
		var rp: Vector2 = ic + Vector2(sx, 22)
		var ra := _sim_steer * Sim.MAX_STEER
		var dv := Vector2(sin(ra), cos(ra)) * 10
		draw_line(rp - dv, rp + dv, Color(0.1, 0.1, 0.1), 8.0)
	_text(ic + Vector2(-60, 64), "뒷바퀴", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, 120)

	# 레버
	_lever("gear", ["전진", "중립", "후진"])
	_spring_lever("lift", lift, "리프트", "내림", "올림")
	_spring_lever("tilt", tilt, "틸트", "숙임", "젖힘")
	# 페달
	_pedal("brake", brake, "브레이크", RED)
	_pedal("accel", throttle, "가속", GREEN)


func _lever(k: String, names: Array) -> void:
	var r: Rect2 = _rects[k]
	draw_rect(r, PANEL)
	var ys := [r.position.y + r.size.y * 0.18, r.get_center().y, r.position.y + r.size.y * 0.82]
	draw_line(Vector2(r.get_center().x, ys[0]), Vector2(r.get_center().x, ys[2]), Color(1, 1, 1, 0.3), 6.0)
	var idx := 0 if gear == 1 else (2 if gear == -1 else 1)
	for i in 3:
		var on := i == idx
		_text(Vector2(r.position.x, ys[i] + 8), names[i], 21 if on else 18, ACCENT if on else DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	draw_circle(Vector2(r.get_center().x, ys[idx] - 22), 12, ACCENT)
	_text(Vector2(r.position.x, r.position.y - 10), "전후진", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _spring_lever(k: String, v: float, title: String, up: String, down: String) -> void:
	var r: Rect2 = _rects[k]
	draw_rect(r, PANEL)
	var c := r.get_center()
	draw_line(Vector2(c.x, r.position.y + 30), Vector2(c.x, r.end.y - 30), Color(1, 1, 1, 0.3), 6.0)
	var ky := c.y + v * r.size.y * 0.42
	draw_line(Vector2(c.x, c.y), Vector2(c.x, ky), ACCENT, 10.0)
	draw_circle(Vector2(c.x, ky), 20, ACCENT if v != 0.0 else Color(0.85, 0.85, 0.85))
	_text(Vector2(r.position.x, r.position.y + 22), "▲" + up, 17, DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_text(Vector2(r.position.x, r.end.y - 8), "▼" + down, 17, DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_text(Vector2(r.position.x, r.position.y - 10), title, 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _pedal(k: String, v: float, title: String, col: Color) -> void:
	var r: Rect2 = _rects[k]
	draw_rect(r, PANEL)
	for i in 6:
		var y := r.position.y + 20 + i * (r.size.y - 40) / 5.0
		draw_line(Vector2(r.position.x + 16, y), Vector2(r.end.x - 16, y), Color(1, 1, 1, 0.12), 4.0)
	if v > 0:
		var h := r.size.y * v
		draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), Color(col, 0.55))
	_text(Vector2(r.position.x, r.position.y - 10), title, 18, DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
