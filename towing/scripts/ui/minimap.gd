class_name MiniMap
extends Control
## A 2D plan view of the current step: asphalt, lines, confirm lines, finish,
## the rig's outline and wheels, plus an optional trail. Used as the HUD
## minimap, in the replay and in the lessons' animated diagrams.

var step: Dictionary = {}
var rig: Rig
var parked := false
var parked_pos := Vector2.ZERO
var parked_th := 0.0
var trail: PackedVector2Array = PackedVector2Array()
var marks: Array = []            # [{pos: Vector2, color}]
var follow := true               # centre on the rig instead of the whole step
var zoom := 1.0
var north_up := true
var rounded := true
var show_frame := true
var heading_up := false          # rotate so the tractor points up (HUD)

var _scale := 1.0
var _center := Vector2.ZERO
var _rot := 0.0


func set_step(s: Dictionary) -> void:
	step = s
	queue_redraw()


func _bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for a in step.get("asphalt", []):
		r = a if first else r.merge(a)
		first = false
	if first:
		return Rect2(-20, -20, 40, 40)
	return r


func _w2s(p: Vector2) -> Vector2:
	var d := p - _center
	if _rot != 0.0:
		d = d.rotated(_rot)
	return size * 0.5 + Vector2(d.x, -d.y) * _scale


func _draw() -> void:
	if step.is_empty():
		return
	var b := _bounds()
	_rot = 0.0
	if follow and rig:
		_center = rig.pos if not rig.coupled else (rig.pos + rig.trailer_axle()) * 0.5
		var span: float = {"small": 30.0, "wrecker": 36.0, "large": 52.0}.get(rig.kind, 34.0) / zoom
		_scale = minf(size.x, size.y) / span
		if heading_up:
			_rot = PI / 2 - rig.th
	else:
		_center = b.get_center()
		_scale = minf(size.x / b.size.x, size.y / b.size.y) * 0.92 / zoom
	if show_frame:
		var sbx := StyleBoxFlat.new()
		sbx.bg_color = Color(0.05, 0.08, 0.13, 0.78)
		sbx.set_corner_radius_all(16 if rounded else 0)
		sbx.border_color = Color(1, 1, 1, 0.12)
		sbx.set_border_width_all(1)
		draw_style_box(sbx, Rect2(Vector2.ZERO, size))
	# clip everything to the frame
	var cl := RenderingServer.canvas_item_create()
	draw_set_transform(Vector2.ZERO)
	for a in step.get("asphalt", []):
		_poly(_rect_poly(a), Color(0.30, 0.33, 0.38, 0.9))
	for l in step.get("paint", []):
		_polyline(l, Color(1, 1, 1, 0.35), 1.5)
	for l in step.get("lines", []):
		_polyline(l, Color(1, 1, 1, 0.95), 2.5)
	for c in step.get("confirms", []):
		_polyline(PackedVector2Array([c.a, c.b]), Kit.PRIMARY, 4.0)
	if step.has("finish") and not step.get("free_run", false):
		_polyline(PackedVector2Array([step.finish.a, step.finish.b]), Kit.AMBER, 3.0)
	if step.has("zone"):
		_polyline(step.zone + PackedVector2Array([step.zone[0]]), Color(1, 1, 1, 0.5), 1.5)
	if trail.size() > 1:
		var pts := PackedVector2Array()
		for p in trail:
			pts.append(_w2s(p))
		draw_polyline(pts, Color(0.3, 0.9, 1.0, 0.7), 2.0, true)
	for m in marks:
		draw_circle(_w2s(m.pos), 5.0, m.color)
	if rig:
		if rig.coupled:
			_poly(rig.trailer_corners(), Color(0.93, 0.93, 0.9, 0.95))
		elif parked:
			var tmp := rig.copy()
			tmp.coupled = true
			tmp.pos = parked_pos + rig.spec.c * Vector2(cos(parked_th), sin(parked_th))
			tmp.th = parked_th
			tmp.phi = parked_th
			_poly(tmp.trailer_corners(), Color(0.93, 0.93, 0.9, 0.95))
		_poly(rig.tractor_corners(), rig.spec.color.lightened(0.15))
		for w in rig.wheels():
			draw_circle(_w2s(w.p), maxf(_scale * 0.35, 2.0), Color(0.05, 0.05, 0.06))
		# heading tick
		var f := Vector2(cos(rig.th), sin(rig.th))
		var nose: Vector2 = rig.pos + f * (rig.spec.L + rig.spec.front_oh)
		draw_line(_w2s(nose), _w2s(nose + f * 1.2), Kit.AMBER, 2.0, true)


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _poly(pts: PackedVector2Array, c: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_w2s(p))
	if out.size() >= 3:
		draw_colored_polygon(out, c)


func _polyline(l: PackedVector2Array, c: Color, w: float) -> void:
	if l.size() < 2:
		return
	var out := PackedVector2Array()
	for p in l:
		out.append(_w2s(p))
	draw_polyline(out, c, w, true)
