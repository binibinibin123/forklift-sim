class_name Course
extends RefCounted
## The 지게차운전기능사 실기 course from the Q-Net public exam drawing (data/course.json).
## Drivable area = start box ∪ opening ∪ ring (outer R 9.4D, inner R 7.2D) ∪ cross arms
## (2.2D wide) ∪ stub to the unloading place. Distances in metres, y = towards the drum.

var D := 1.2
var box := Rect2()          # 주차선 .. 화물적재선
var conn := Rect2()         # box wall opening (2.6D) into the ring
var stub := Rect2()         # 작업구역② stub, ends at 화물하차선
var center := Vector2.ZERO  # ring centre
var r_out := 0.0
var r_in := 0.0
var hw := 0.0               # half arm width
var park_line_y := 0.0      # 주차보조선
var start_line_y := 0.0     # 출발선 / 도착선
var load_line_y := 0.0      # 화물적재선 (top of the box)
var unload_line_x := 0.0    # 화물하차선 (end of the stub)
var back_line_x := 0.0      # 후진선 (inner circle on the arm)
var opening := Vector2.ZERO # y range of the box wall opening

var start_pos := Vector2.ZERO
var start_heading := PI / 2
var drum_pos := Vector2.ZERO
var drum_radius := 0.29
var drum_height := 0.9
var pallet_start := Vector2.ZERO        # 이동 파렛트 on the drum
var pallet_start_heading := PI / 2
var guide_pos := Vector2.ZERO           # 표준 파렛트 (the reference pallet in 작업구역②)
var guide_heading := 0.0
var unload_target := Vector2.ZERO       # = guide_pos: the moving pallet goes on top of it
var unload_heading := 0.0
var time_limit := 240.0
var start_limit := 60.0


static func load_default() -> Course:
	var c := Course.new()
	var f := FileAccess.open("res://data/course.json", FileAccess.READ)
	c.parse(JSON.parse_string(f.get_as_text()))
	return c


func parse(d: Dictionary) -> void:
	D = float(d.D_m)
	var bw := float(d.box.width_D) * D
	var park := float(d.box.park_D) * D
	var to_start := float(d.box.to_start_D) * D
	var w1: Array = d.box.work1_D
	park_line_y = park
	start_line_y = park + to_start
	var mid_y := start_line_y + float(w1[1]) * D         # ring centre height (opening centre)
	load_line_y = mid_y + float(w1[0]) * D
	box = Rect2(-bw * 0.5, 0.0, bw, load_line_y)
	r_out = float(d.circle.outer_R_D) * D
	r_in = float(d.circle.inner_R_D) * D
	hw = float(d.circle.arm_width_D) * D * 0.5
	center = Vector2(box.position.x - r_out, mid_y)       # ring touches the box wall
	var oh := float(d.opening_D) * D * 0.5
	opening = Vector2(mid_y - oh, mid_y + oh)
	conn = Rect2(box.position.x - 0.4, mid_y - oh, 0.4, oh * 2.0)
	var sl := float(d.stub.length_D) * D
	var sw := float(d.stub.width_D) * D
	unload_line_x = center.x - r_out - sl
	stub = Rect2(unload_line_x, mid_y - sw * 0.5, sl + 0.25, sw)
	back_line_x = center.x - r_in
	drum_radius = float(d.drum.radius)
	drum_height = float(d.drum.height)
	drum_pos = Vector2(0.0, load_line_y + drum_radius)
	pallet_start = drum_pos
	pallet_start_heading = PI / 2
	# 표준 파렛트 sits a/2 beyond the 화물하차선 (a = front axle centre to the fork's inner face)
	guide_pos = Vector2(unload_line_x - Sim.CARRIAGE * 0.5 - Sim.PALLET * 0.5, mid_y)
	guide_heading = 0.0
	unload_target = guide_pos
	unload_heading = 0.0
	# the forklift starts in the parking area with its forks over the 주차보조선
	start_pos = Vector2(0.0, park_line_y - (Sim.CARRIAGE + Sim.FORK_LEN * 0.5))
	start_heading = PI / 2
	time_limit = float(d.time_limit)
	start_limit = float(d.start_limit)


func _in_rect(r: Rect2, p: Vector2) -> bool:
	return p.x >= r.position.x and p.x <= r.end.x and p.y >= r.position.y and p.y <= r.end.y


func _in_ring(p: Vector2) -> bool:
	var q := p - center
	var r := q.length()
	if r > r_out:
		return false
	return r >= r_in or absf(q.x) <= hw or absf(q.y) <= hw


func inside(p: Vector2) -> bool:
	return _in_rect(box, p) or _in_rect(conn, p) or _in_rect(stub, p) or _in_ring(p)


## "work1" (작업구역①), "work2" (작업구역②), "park" (주차구역) or "travel" (주행구간)
func zone_at(p: Vector2) -> String:
	if _in_rect(box, p):
		if p.y >= start_line_y:
			return "work1"
		if p.y <= park_line_y:
			return "park"
		return "travel"
	if p.x >= unload_line_x and p.x <= back_line_x and absf(p.y - center.y) <= hw:
		return "work2"
	return "travel"


func bounds() -> Rect2:
	var b := box.merge(stub)
	b = b.merge(Rect2(center - Vector2(r_out, r_out), Vector2(r_out, r_out) * 2.0))
	return b.grow_individual(Sim.PALLET + Sim.CARRIAGE, 0.0, 0.0, drum_radius * 2.0)


## Distance (m) from p to the nearest course edge when p is inside; negative outside.
func edge_dist(p: Vector2) -> float:
	var best := -1.0
	for r in [box, conn, stub]:
		if _in_rect(r, p):
			best = maxf(best, minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y)))
	var q := p - center
	var rr := q.length()
	if rr <= r_out:
		if rr >= r_in:
			best = maxf(best, minf(rr - r_in, r_out - rr))
		if absf(q.x) <= hw:
			best = maxf(best, minf(hw - absf(q.x), r_out - rr))
		if absf(q.y) <= hw:
			best = maxf(best, minf(hw - absf(q.y), r_out - rr))
	return best


## Nearest point on the course edge (sampled), for measurement lines.
func nearest_edge_point(p: Vector2) -> Vector2:
	var best := p
	var bd := INF
	for pl in boundary_polylines():
		for q: Vector2 in pl:
			var d := q.distance_squared_to(p)
			if d < bd:
				bd = d
				best = q
	return best


var _poly_cache: Array = []


## Painted course edges as polylines (each an Array of Vector2).
func boundary_polylines(step := 0.1) -> Array:
	if not _poly_cache.is_empty():
		return _poly_cache
	var edges := []   # each: Array of [point, outward normal]
	for r in [box, conn, stub]:
		var cs := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			var a: Vector2 = cs[i]
			var b: Vector2 = cs[(i + 1) % 4]
			var dd := (b - a).normalized()
			edges.append(_sample_line(a, b, Vector2(dd.y, -dd.x), step))
	edges.append(_sample_arc(r_out, 1.0, step))
	edges.append(_sample_arc(r_in, -1.0, step))
	for s in [-1.0, 1.0]:
		var x0 := center.x - r_out
		var x1 := center.x + r_out
		edges.append(_sample_line(Vector2(x0, center.y + s * hw), Vector2(x1, center.y + s * hw), Vector2(0, s), step))
		edges.append(_sample_line(Vector2(center.x + s * hw, center.y - r_out), Vector2(center.x + s * hw, center.y + r_out), Vector2(s, 0), step))
	var out := []
	for e in edges:
		var run := []
		for pn in e:
			var p: Vector2 = pn[0]
			var n: Vector2 = pn[1]
			var edge := inside(p - n * 0.02) and not inside(p + n * 0.02)
			if edge:
				run.append(p)
			elif run.size() > 1:
				out.append(run)
				run = []
			else:
				run = []
		if run.size() > 1:
			out.append(run)
	_poly_cache = out
	return out


func _sample_line(a: Vector2, b: Vector2, n: Vector2, step: float) -> Array:
	var out := []
	var k := int(ceil(a.distance_to(b) / step))
	for j in k + 1:
		out.append([a.lerp(b, float(j) / k), n])
	return out


func _sample_arc(r: float, sign: float, step: float) -> Array:
	var out := []
	var k := int(ceil(TAU * r / step))
	for j in k + 1:
		var ang := TAU * j / k
		var u := Vector2(cos(ang), sin(ang))
		out.append([center + u * r, u * sign])
	return out


## Old name kept for callers that want plain segments.
func boundary_segments() -> Array:
	var segs := []
	for pl in boundary_polylines():
		for i in pl.size() - 1:
			segs.append([pl[i], pl[i + 1]])
	return segs
