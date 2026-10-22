class_name CourseView
extends Control
## 코스 도면(치수·동선). 학습 화면과 결과 화면에서 사용.

var course: Course
var show_dims := true
var show_routes := true
var trail: PackedVector2Array = []       # 주행 궤적(결과 화면)
var fault_pos: Array = []                # 실격 지점
var scale_px := 26.0

const PAD := 44.0


func setup(c: Course, px := 26.0) -> void:
	course = c
	scale_px = px
	var b := c.bounds()
	custom_minimum_size = b.size * scale_px + Vector2(PAD * 2, PAD * 2)
	queue_redraw()


func _to(p: Vector2) -> Vector2:
	var b := course.bounds()
	return Vector2((p.x - b.position.x) * scale_px + PAD, (b.end.y - p.y) * scale_px + PAD)


func _draw() -> void:
	if course == null:
		return
	var f := get_theme_default_font()
	var b := course.bounds()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.36, 0.37, 0.38, 1.0))
	for r in course.rects:
		draw_rect(Rect2(_to(Vector2(r.position.x, r.end.y)), r.size * scale_px), Color(0.5, 0.51, 0.5))
	for seg in course.boundary_segments():
		draw_line(_to(seg[0]), _to(seg[1]), Color(0.98, 0.78, 0.12), 3.0)
	# 출발선·후진선
	var sr: Rect2 = course.zones["start"]
	draw_line(_to(Vector2(sr.position.x, course.start_line_y)), _to(Vector2(sr.end.x, course.start_line_y)), Color.WHITE, 3.0)
	var top_r := course.rects[4]
	draw_line(_to(Vector2(course.back_line_x, top_r.position.y)), _to(Vector2(course.back_line_x, top_r.end.y)), Color.WHITE, 3.0)
	# 하역 표시, 표준 팔레트, 드럼
	_square(course.unload_target, course.unload_heading, Sim.PALLET + 0.04, Color.WHITE, 2.0)
	_square(course.guide_pos, course.guide_heading, Sim.PALLET, Color(0.95, 0.75, 0.3), 0.0, true)
	draw_circle(_to(course.drum_pos), course.drum_radius * scale_px, Color(0.15, 0.4, 0.75))
	_square(course.pallet_start, course.pallet_start_heading, Sim.PALLET, Color(0.85, 0.65, 0.4), 2.0)
	# 글씨
	if show_dims:
		_labels(f, sr, top_r)
	if show_routes:
		var fwd := [Vector2(0, 2.6), Vector2(0, 6.4), Vector2(-6.6, 6.4), Vector2(-6.6, 13.6), Vector2(5.0, 13.6)]
		_route(fwd, Color(0.4, 0.85, 1.0), "전진")
		var rev := [Vector2(4.4, 14.4), Vector2(-5.8, 14.4), Vector2(-5.8, 7.2), Vector2(0.8, 7.2), Vector2(0.8, 2.0)]
		_route(rev, Color(1.0, 0.6, 0.3), "후진")
	if show_dims:
		for i in course.rects.size():
			var r: Rect2 = course.rects[i]
			var c := _to(Vector2(r.get_center().x, r.end.y))
			draw_string(f, c + Vector2(-26, 16), "%.1f m" % r.size.x, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))
			var cl := _to(Vector2(r.position.x, r.get_center().y))
			draw_string(f, cl + Vector2(4, 4), "%.1f" % r.size.y, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))
		draw_string(f, Vector2(8, size.y - 10), "※ 치수는 공개 자료 기준 추정치. 시험장마다 조금씩 다를 수 있어요.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
	_overlays()


func _labels(f: Font, sr: Rect2, top_r: Rect2) -> void:
	draw_string(f, _to(Vector2(sr.position.x, course.start_line_y - 0.5)), "출발·도착선", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(f, _to(Vector2(course.back_line_x + 0.1, top_r.end.y + 0.3)), "후진선", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(f, _to(Vector2(course.drum_pos.x + 0.5, course.drum_pos.y)), "드럼+팔레트", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(f, _to(Vector2(course.unload_target.x - 1.0, course.unload_target.y - 1.0)), "하역 위치", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(f, _to(Vector2(course.guide_pos.x - 0.6, course.guide_pos.y + 0.9)), "표준 팔레트", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.6))


func _overlays() -> void:
	if trail.size() > 1:
		var pts := PackedVector2Array()
		for p in trail:
			pts.append(_to(p))
		draw_polyline(pts, Color(0.3, 1.0, 0.6, 0.9), 2.5)
	for p in fault_pos:
		var q := _to(p)
		draw_circle(q, 9, Color(0.95, 0.25, 0.2))
		draw_line(q + Vector2(-5, -5), q + Vector2(5, 5), Color.WHITE, 2.0)
		draw_line(q + Vector2(-5, 5), q + Vector2(5, -5), Color.WHITE, 2.0)


func _square(c: Vector2, ang: float, s: float, col: Color, w: float, fill := false) -> void:
	var h := s * 0.5
	var pts := PackedVector2Array()
	for k: Vector2 in [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]:
		pts.append(_to(c + k.rotated(ang)))
	if fill:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, w)


func _route(pts: Array, col: Color, name: String) -> void:
	var sp := PackedVector2Array()
	for p in pts:
		sp.append(_to(p))
	draw_polyline(sp, Color(col, 0.85), 4.0)
	var a: Vector2 = sp[-2]
	var bb: Vector2 = sp[-1]
	var d := (bb - a).normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([bb + d * 10, bb - d * 6 + n * 8, bb - d * 6 - n * 8]), col)
	draw_string(get_theme_default_font(), sp[1] + Vector2(6, -6), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
