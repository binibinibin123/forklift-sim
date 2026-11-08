class_name WheelWidget
extends Control
## On-screen steering wheel. Drag around the centre to turn it; 1.5 turns
## each way reach full lock, like a truck. steer(): -1 (right) .. 1 (left).

const MAX_DEG := 540.0

var angle := 0.0          # degrees, clockwise positive (screen)
var held := false
var sensitivity := 1.0
var _last := 0.0


func steer() -> float:
	return clampf(-angle / MAX_DEG, -1.0, 1.0)


func set_steer(s: float) -> void:
	angle = -s * MAX_DEG
	queue_redraw()


func press(p: Vector2) -> void:
	held = true
	_last = _ang(p)


func drag(p: Vector2) -> void:
	if not held:
		return
	var a := _ang(p)
	angle = clampf(angle + rad_to_deg(wrapf(a - _last, -PI, PI)) * sensitivity, -MAX_DEG, MAX_DEG)
	_last = a
	queue_redraw()


func release() -> void:
	held = false
	queue_redraw()


func _ang(p: Vector2) -> float:
	return (p - size * 0.5).angle()


func turns_text() -> String:
	var t := absf(angle) / 360.0
	if t < 0.05:
		return "핸들 중앙"
	return "%s %.1f바퀴" % ["왼쪽" if angle < 0 else "오른쪽", t]


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0
	var a := deg_to_rad(angle)
	# rim with a leather-like two-tone and a soft shadow
	draw_circle(c + Vector2(0, 3), r + 2, Color(0, 0, 0, 0.25))
	draw_arc(c, r - 10.0, 0, TAU, 72, Color(0.10, 0.12, 0.16, 0.95), 22.0, true)
	draw_arc(c, r - 10.0, 0, TAU, 72, Color(1, 1, 1, 0.08), 22.0, true)
	draw_arc(c, r - 2.0, 0, TAU, 72, Color(1, 1, 1, 0.30 if held else 0.14), 2.0, true)
	draw_arc(c, r - 19.0, 0, TAU, 72, Color(0, 0, 0, 0.35), 1.5, true)
	# grip stitches
	for i in 24:
		var ga := TAU * i / 24.0 + a
		var d := Vector2.from_angle(ga)
		draw_line(c + d * (r - 14.0), c + d * (r - 6.0), Color(1, 1, 1, 0.07), 2.0)
	# three spokes turning with the wheel
	for base in [0.0, PI, PI * 0.5]:
		var d := Vector2.from_angle(base + a)
		draw_line(c + d * r * 0.22, c + d * (r - 16.0), Color(0.10, 0.12, 0.16, 0.95), 16.0, true)
		draw_line(c + d * r * 0.22, c + d * (r - 16.0), Color(1, 1, 1, 0.05), 4.0, true)
	draw_circle(c, r * 0.24, Color(0.12, 0.14, 0.19, 0.98))
	draw_arc(c, r * 0.24, 0, TAU, 40, Color(1, 1, 1, 0.12), 1.5, true)
	# top marker shows how far it is turned
	var top := Vector2.from_angle(-PI * 0.5 + a)
	draw_line(c + top * (r - 20.0), c + top * (r - 1.0), Kit.AMBER, 8.0, true)
	var f := Kit.font
	var txt := turns_text()
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 19).x
	draw_string(f, c + Vector2(-w * 0.5, 7), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 1, 1, 0.9))
