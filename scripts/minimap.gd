class_name Minimap
extends Control
## Small course map at the top right: edges, pallets, drum and the forklift.

var main: Node
const S := 6.0   # px per m


func setup(m: Node) -> void:
	main = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)


func _to(p: Vector2, b: Rect2) -> Vector2:
	return Vector2((p.x - b.position.x) * S, (b.end.y - p.y) * S) + Vector2(8, 8)


func _draw() -> void:
	var c: Course = main.course
	var sim: Sim = main.sim
	var b := c.bounds()
	var sz := b.size * S + Vector2(16, 16)
	position = Vector2(get_parent().size.x - sz.x - 20, 92)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.45))
	for pl in c.boundary_polylines():
		var pts := PackedVector2Array()
		for p in pl:
			pts.append(_to(p, b))
		draw_polyline(pts, Color(0.98, 0.8, 0.2, 0.9), 1.5)
	draw_line(_to(Vector2(c.box.position.x, c.start_line_y), b), _to(Vector2(c.box.end.x, c.start_line_y), b), Color.WHITE, 2.0)
	draw_line(_to(Vector2(c.back_line_x, c.center.y - c.hw), b), _to(Vector2(c.back_line_x, c.center.y + c.hw), b), Color.WHITE, 2.0)
	draw_circle(_to(c.drum_pos, b), 3.0, Color(0.2, 0.45, 0.9))
	var g := _to(c.guide_pos, b)
	draw_rect(Rect2(g - Vector2(3, 3), Vector2(6, 6)), Color(0.95, 0.75, 0.3))
	var pc := _to(sim.pallet_pos, b)
	draw_rect(Rect2(pc - Vector2(4, 4), Vector2(8, 8)), Color(0.75, 0.5, 0.25))
	var p := _to(sim.pos, b)
	var d := Vector2(sim.dir().x, -sim.dir().y)
	var r := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([p + d * 7, p - d * 14 + r * 5, p - d * 14 - r * 5]), Color(1.0, 0.65, 0.1))
