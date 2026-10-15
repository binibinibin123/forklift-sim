class_name Minimap
extends Control
## 오른쪽 위 작은 코스 지도

var main: Node
const S := 11.0   # px per m


func setup(m: Node) -> void:
	main = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)


func _to(p: Vector2, b: Rect2) -> Vector2:
	return Vector2((p.x - b.position.x) * S, (b.end.y - p.y) * S) + Vector2(10, 10)


func _draw() -> void:
	var c: Course = main.course
	var sim: Sim = main.sim
	var b := c.bounds()
	var sz := b.size * S + Vector2(20, 20)
	position = Vector2(get_parent().size.x - sz.x - 20, 92)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.45))
	for r in c.rects:
		var a := _to(Vector2(r.position.x, r.end.y), b)
		draw_rect(Rect2(a, r.size * S), Color(0.75, 0.75, 0.72, 0.85))
	draw_line(_to(Vector2(-1.5, c.start_line_y), b), _to(Vector2(1.5, c.start_line_y), b), Color.WHITE, 2.0)
	draw_circle(_to(c.drum_pos, b), c.drum_radius * S + 1, Color(0.2, 0.45, 0.9))
	var pc := _to(sim.pallet_pos, b)
	draw_rect(Rect2(pc - Vector2(6, 6), Vector2(12, 12)), Color(0.75, 0.5, 0.25))
	var p := _to(sim.pos, b)
	var d := Vector2(sim.dir().x, -sim.dir().y)
	var r := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([p + d * 10, p - d * 22 + r * 7, p - d * 22 - r * 7])
	draw_colored_polygon(pts, Color(1.0, 0.65, 0.1))
