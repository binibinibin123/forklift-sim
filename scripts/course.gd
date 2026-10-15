class_name Course
extends RefCounted
## 시험 코스 데이터(data/course.json). 주행 가능 영역은 직사각형들의 합집합.

var rects: Array[Rect2] = []
var rect_names: Array[String] = []
var zones := {}            # name -> Rect2
var start_line_y := 2.6
var start_pos := Vector2.ZERO
var start_heading := PI / 2
var drum_pos := Vector2.ZERO
var drum_radius := 0.29
var drum_height := 0.9
var pallet_start := Vector2.ZERO
var pallet_start_heading := PI / 2
var unload_target := Vector2.ZERO
var unload_heading := 0.0
var guide_pos := Vector2.ZERO
var guide_heading := 0.0
var back_line_x := 3.6
var time_limit := 240.0
var start_limit := 60.0


static func load_default() -> Course:
	var c := Course.new()
	var f := FileAccess.open("res://data/course.json", FileAccess.READ)
	c.parse(JSON.parse_string(f.get_as_text()))
	return c


static func _rect(d: Dictionary) -> Rect2:
	var x0: float = d.x[0]
	var y0: float = d.y[0]
	return Rect2(x0, y0, float(d.x[1]) - x0, float(d.y[1]) - y0)


static func _v(d: Dictionary) -> Vector2:
	return Vector2(d.x, d.y)


func parse(d: Dictionary) -> void:
	for r in d.rects:
		rects.append(_rect(r))
		rect_names.append(r.name)
	for k in d.zones:
		zones[k] = _rect(d.zones[k])
	start_line_y = d.start_line_y
	start_pos = _v(d.start_pose)
	start_heading = deg_to_rad(d.start_pose.heading_deg)
	drum_pos = _v(d.drum)
	drum_radius = d.drum.radius
	drum_height = d.drum.height
	pallet_start = _v(d.pallet_start)
	pallet_start_heading = deg_to_rad(d.pallet_start.heading_deg)
	unload_target = _v(d.unload_target)
	unload_heading = deg_to_rad(d.unload_target.heading_deg)
	guide_pos = _v(d.guide_pallet)
	guide_heading = deg_to_rad(d.guide_pallet.heading_deg)
	back_line_x = d.back_line_x
	time_limit = d.time_limit
	start_limit = d.start_limit


func inside(p: Vector2) -> bool:
	for r in rects:
		if p.x >= r.position.x and p.x <= r.end.x and p.y >= r.position.y and p.y <= r.end.y:
			return true
	return false


## "load", "unload" 또는 "travel"
func zone_at(p: Vector2) -> String:
	for k in zones:
		if zones[k].has_point(p):
			return k
	return "travel"


func bounds() -> Rect2:
	var b := rects[0]
	for r in rects:
		b = b.merge(r)
	return b


## 합집합의 바깥 경계선(칠할 선). [[a, b], ...]
func boundary_segments(step := 0.05) -> Array:
	var out := []
	for r in rects:
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % 4]
			var d := (b - a).normalized()
			var outward := Vector2(d.y, -d.x)  # 반시계 꼭짓점 순서라 오른쪽이 바깥
			var n := int(ceil(a.distance_to(b) / step))
			var run_start = null
			for j in n + 1:
				var p: Vector2 = a + d * minf(j * step, a.distance_to(b))
				var edge := not inside(p + outward * 0.01)
				if edge and run_start == null:
					run_start = p
				elif not edge and run_start != null:
					out.append([run_start, p])
					run_start = null
			if run_start != null:
				out.append([run_start, b])
	return out
