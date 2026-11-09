class_name CourseView
extends Control
## Course plan drawn from the Q-Net drawing: D-unit dimensions, forward (solid) and
## reverse (dashed) lines, the run's trail and fault marks. Rulebook and score sheet.

var course: Course
var show_dims := true
var show_routes := true
var trail: PackedVector2Array = []
var fault_pos: Array = []
var scale_px := 20.0

const PAD := 30.0
const FILL := Color(0.52, 0.53, 0.52)
const BG := Color(0.33, 0.34, 0.35)
const YEL := Color(0.98, 0.78, 0.12)
const FWD := Color(0.4, 0.85, 1.0)
const REV := Color(1.0, 0.62, 0.3)


func setup(c: Course, px := 20.0, label_room := 0.0) -> void:
	course = c
	scale_px = px
	custom_minimum_size = c.bounds().size * scale_px + Vector2(PAD * 2 + label_room, PAD * 2)
	queue_redraw()


func _to(p: Vector2) -> Vector2:
	var b := course.bounds()
	return Vector2((p.x - b.position.x) * scale_px + PAD, (b.end.y - p.y) * scale_px + PAD)


func _rect(r: Rect2, col: Color) -> void:
	draw_rect(Rect2(_to(Vector2(r.position.x, r.end.y)), r.size * scale_px), col)


func _draw() -> void:
	if course == null:
		return
	var c := course
	var f := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	# surface
	for r in [c.box, c.conn, c.stub]:
		_rect(r, FILL)
	var n := 120
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var u0 := Vector2(cos(a0), sin(a0))
		var u1 := Vector2(cos(a1), sin(a1))
		draw_colored_polygon(PackedVector2Array([_to(c.center + u0 * c.r_in), _to(c.center + u0 * c.r_out), _to(c.center + u1 * c.r_out), _to(c.center + u1 * c.r_in)]), FILL)
	var L := sqrt(c.r_out * c.r_out - c.hw * c.hw)
	_rect(Rect2(c.center + Vector2(-L, -c.hw), Vector2(2 * L, 2 * c.hw)), FILL)
	_rect(Rect2(c.center + Vector2(-c.hw, -L), Vector2(2 * c.hw, 2 * L)), FILL)
	# edges and white lines
	for pl in c.boundary_polylines():
		var pts := PackedVector2Array()
		for p in pl:
			pts.append(_to(p))
		draw_polyline(pts, YEL, 2.0)
	var bx := c.box
	var cy := c.center.y
	for seg in [[Vector2(bx.position.x, c.start_line_y), Vector2(bx.end.x, c.start_line_y)],
			[Vector2(bx.position.x, c.park_line_y), Vector2(bx.end.x, c.park_line_y)],
			[Vector2(c.back_line_x, cy - c.hw), Vector2(c.back_line_x, cy + c.hw)]]:
		draw_line(_to(seg[0]), _to(seg[1]), Color.WHITE, 3.0)
	# pallets and drum
	_square(c.guide_pos, c.guide_heading, Sim.PALLET, Color(0.95, 0.75, 0.3), 0.0, true)
	draw_circle(_to(c.drum_pos), maxf(c.drum_radius * scale_px, 4.0), Color(0.2, 0.45, 0.85))
	_square(c.pallet_start, c.pallet_start_heading, Sim.PALLET, Color(0.9, 0.7, 0.45), 2.0)
	if show_routes:
		_route(Route.line_path(Vector2(0.35, c.start_pos.y), Vector2(0.35, c.drum_pos.y - 1.2)), FWD, false)
		_route(Route.line_path(Vector2(-0.35, c.drum_pos.y - 1.2), Vector2(-0.35, 9.6)), REV, true)
		_route(Route.forward(c, 9.6), FWD, false)
		_route(Route.reverse(c), REV, true)
	if show_dims:
		_labels(f)
	_overlays()


func _labels(f: Font) -> void:
	var c := course
	var cy := c.center.y
	var w := Color(1, 1, 1, 0.92)
	var dim := Color(1, 1, 1, 0.7)
	_text(f, Vector2(c.box.end.x + 0.3, c.start_line_y), Lang.t("course.start_line"), w, 14)
	_text(f, Vector2(c.box.end.x + 0.3, c.park_line_y), Lang.t("course.park_line"), w, 14)
	_text(f, Vector2(c.box.end.x + 0.3, c.load_line_y), Lang.t("course.load_line"), w, 14)
	_text(f, Vector2(c.box.end.x + 0.3, 1.0), Lang.t("course.park_zone"), dim, 13)
	_text(f, Vector2(c.back_line_x + 0.3, cy + c.hw + 0.5), Lang.t("course.back_line"), w, 14)
	_text(f, Vector2(c.unload_line_x - 1.4, cy + c.hw + 1.2), Lang.t("course.guide"), Color(1, 0.88, 0.6), 13)
	_text(f, Vector2(c.drum_pos.x - 3.0, c.drum_pos.y + 1.1), Lang.t("course.drum"), Color(0.7, 0.85, 1.0), 13)
	_text(f, c.center + Vector2(-2.2, -c.r_out + 1.6), "R 9.4D = %.2f m" % c.r_out, dim, 13)
	_text(f, c.center + Vector2(2.0, 3.0), "R 7.2D", dim, 13)
	_text(f, c.center + Vector2(c.hw + 0.3, c.r_in - 1.2), "2.2D", dim, 13)
	_text(f, Vector2(c.box.end.x + 0.3, cy), "2.4D × (4+2+3+3)D", dim, 12)
	_text(f, Vector2(c.unload_line_x, c.center.y - c.r_out - 0.4), Lang.t("course.dims", [c.D]), dim, 13)
	_text(f, Vector2(c.center.x - 6.0, c.center.y + c.r_out + 0.6), Lang.t("course.fwd_rev"), dim, 13)


func _text(f: Font, p: Vector2, t: String, col: Color, fs: int) -> void:
	draw_string_outline(f, _to(p), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6))
	draw_string(f, _to(p), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


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


func _route(path: PackedVector2Array, col: Color, dashed: bool) -> void:
	var pts := PackedVector2Array()
	for i in range(0, path.size(), 4):
		pts.append(_to(path[i]))
	pts.append(_to(path[-1]))
	if dashed:
		for i in range(0, pts.size() - 1, 4):
			draw_line(pts[i], pts[mini(i + 2, pts.size() - 1)], Color(col, 0.9), 2.5)
	else:
		draw_polyline(pts, Color(col, 0.9), 2.5)
	var a: Vector2 = pts[maxi(pts.size() - 4, 0)]
	var bb: Vector2 = pts[-1]
	var d := (bb - a).normalized()
	var nn := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([bb + d * 9, bb - d * 5 + nn * 7, bb - d * 5 - nn * 7]), col)
