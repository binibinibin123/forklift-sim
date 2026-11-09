class_name Route
extends RefCounted
## The drawing's driving lines as front-axle paths (dense points), used to draw the
## forward (solid) and reverse (dashed) arrows on the course plan and by the test driver.

const STEP := 0.05


static func _line(out: PackedVector2Array, a: Vector2, b: Vector2) -> void:
	var n := maxi(int(ceil(a.distance_to(b) / STEP)), 1)
	for k in n:
		out.append(a.lerp(b, float(k) / n))


static func _arc(out: PackedVector2Array, c: Vector2, r: float, a0: float, a1: float) -> void:
	var n := maxi(int(ceil(absf(a1 - a0) * r / STEP)), 2)
	for k in n:
		var a := lerpf(a0, a1, float(k) / n)
		out.append(c + Vector2(cos(a), sin(a)) * r)


static func mid_r(c: Course) -> float:
	return (c.r_in + c.r_out) * 0.5


## Front axle x where the carried pallet sits over the 표준 파렛트 (full insertion).
static func unload_x(c: Course) -> float:
	return c.guide_pos.x + Sim.CARRIAGE + Sim.FORK_LEN - Sim.PALLET * 0.5


## Front axle x with the fork middle on the 후진선.
static func touch_x(c: Course) -> float:
	return c.back_line_x + Sim.CARRIAGE + Sim.FORK_LEN * 0.5


## Loaded, forward: box -> opening -> arm -> centre -> north arm -> ring (anticlockwise) -> stub.
static func forward(c: Course, from_y := 9.5) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cy := c.center.y
	var cx := c.center.x
	var rm := mid_r(c)
	var r1 := 1.2
	_line(out, Vector2(0, from_y), Vector2(0, cy - r1))
	_arc(out, Vector2(-r1, cy - r1), r1, 0.0, PI / 2)
	var r2 := 1.3
	_line(out, Vector2(-r1, cy), Vector2(cx + r2, cy))
	_arc(out, Vector2(cx + r2, cy + r2), r2, -PI / 2, -PI)
	var r3 := 1.3
	var top_y := cy + sqrt(rm * rm - r3 * r3)
	_line(out, Vector2(cx, cy + r2), Vector2(cx, top_y - r3))
	_arc(out, Vector2(cx - r3, top_y - r3), r3, 0.0, PI / 2)
	var r4 := 1.3
	var a0 := PI / 2 + asin(r3 / rm)
	var a1 := PI - asin(r4 / rm)
	_arc(out, c.center, rm, a0, a1)
	var p := c.center + Vector2(cos(a1), sin(a1)) * rm
	_arc(out, Vector2(p.x - r4, p.y), r4, 0.0, -PI / 2)
	_line(out, Vector2(p.x - r4, cy), Vector2(unload_x(c), cy))
	out.append(Vector2(unload_x(c), cy))
	return out


## Loaded, reverse: stub -> arm -> centre -> south arm -> ring (anticlockwise) -> opening -> box.
## Returns the front-axle path; the forklift moves along it backwards.
static func reverse(c: Course, from_x := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cy := c.center.y
	var cx := c.center.x
	var rm := mid_r(c)
	if from_x == 0.0:
		from_x = unload_x(c)
	var r5 := 1.3
	_line(out, Vector2(from_x, cy), Vector2(cx - r5, cy))
	_arc(out, Vector2(cx - r5, cy - r5), r5, PI / 2, 0.0)
	var r6 := 1.3
	var bot_y := cy - sqrt(rm * rm - r6 * r6)
	_line(out, Vector2(cx, cy - r5), Vector2(cx, bot_y + r6))
	_arc(out, Vector2(cx + r6, bot_y + r6), r6, PI, 3 * PI / 2)
	var end_y := 9.6
	var a0 := -PI / 2 + asin(r6 / rm)
	var a1 := -asin((cy - end_y) / rm)
	_arc(out, c.center, rm, a0, a1)
	var p := c.center + Vector2(cos(a1), sin(a1)) * rm
	var r7 := (0.0 - p.x) * 0.5
	_arc(out, Vector2(p.x + r7, end_y), r7, PI, 0.0)
	out.append(Vector2(0.0, end_y))
	return out


static func line_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	_line(out, a, b)
	out.append(b)
	return out
