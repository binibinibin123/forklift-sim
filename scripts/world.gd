class_name World
extends Node3D
## 시험장(물류 야드) 3D: 아스팔트, 도색선, 드럼·팔레트, 펜스, 창고, 랙, 소품.
## 2D (x, y) → 3D (x, 높이, -y).

const LINE_W := 0.1
const YELLOW := Color(0.98, 0.78, 0.12)
const WHITE := Color(0.93, 0.93, 0.9)

var course: Course
var pallet: Node3D
var guide: Node3D
var drum: Node3D
var _yard: Rect2            # 펜스 안쪽(2D)


static func v3(p: Vector2, h := 0.0) -> Vector3:
	return Vector3(p.x, h, -p.y)


static func mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	return Mats.plain(c, rough, metal)


static func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, segs := 24, r_bottom := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r if r_bottom < 0 else r_bottom
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, r: float, pos: Vector3, m: Material, segs := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	sm.radial_segments = segs
	sm.rings = int(segs / 2)
	mi.mesh = sm
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


func build(c: Course) -> void:
	course = c
	var b := c.bounds()
	_yard = b.grow_individual(14.0, 9.0, 14.0, 12.0)
	_ground(b)
	_lines(c)
	_drum_and_pallets(c)
	_fence()
	_warehouse()
	_racks()
	_props(b)
	_trees()


# ---------- 바닥 ----------
func _ground(b: Rect2) -> void:
	# 야드 바깥: 흙/풀 (아주 넓게)
	var dirt := Mats.triplanar("concrete", 6.0, 1.0, Color(0.55, 0.52, 0.42))
	var g := box(self, Vector3(600, 0.1, 600), v3(b.get_center(), -0.12), dirt)
	g.name = "Ground"
	# 야드 아스팔트
	var asphalt := Mats.triplanar("asphalt", 5.0, 0.95, Color.WHITE, "asphalt_n")
	if Mats.compat:
		asphalt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		asphalt.albedo_color = Color(0.55, 0.55, 0.56)
	var yard := box(self, Vector3(_yard.size.x, 0.12, _yard.size.y), v3(_yard.get_center(), -0.06), asphalt)
	yard.name = "Yard"
	# 코스 포장면은 조금 밝은 마모 자국(차가 많이 다닌 느낌)
	var worn := Mats.triplanar("asphalt", 3.0, 0.9, Color(1.18, 1.17, 1.14), "asphalt_n")
	if Mats.compat:
		worn.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		worn.albedo_color = Color(0.64, 0.64, 0.63)
	for r in course.rects:
		box(self, Vector3(r.size.x, 0.004, r.size.y), v3(r.get_center(), 0.002), worn)
	# 연석(야드 가장자리)
	var curb := Mats.tex("concrete", Vector3(2, 2, 2), 0.9, 0.0, Color(0.85, 0.85, 0.82))
	for e in _edges(_yard):
		var a: Vector2 = e[0]
		var bb: Vector2 = e[1]
		var mi := box(self, Vector3(a.distance_to(bb), 0.16, 0.3), v3((a + bb) * 0.5, 0.02), curb)
		mi.rotation.y = (bb - a).angle()


static func _edges(r: Rect2) -> Array:
	var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	return [[p[0], p[1]], [p[1], p[2]], [p[2], p[3]], [p[3], p[0]]]


# ---------- 도색선 ----------
func _lines(c: Course) -> void:
	var line_m := Mats.cutout("line_wear", Vector3(0.4, 0.4, 0.4))
	line_m.albedo_color = YELLOW
	line_m.roughness = 0.7
	line_m.metallic = 0.0
	for seg in c.boundary_segments():
		_line(seg[0], seg[1], line_m, 0.006)
	var white := Mats.cutout("line_wear", Vector3(0.4, 0.4, 0.4))
	white.albedo_color = WHITE
	white.roughness = 0.7
	white.metallic = 0.0
	var sr: Rect2 = c.zones["start"]
	_line(Vector2(sr.position.x, c.start_line_y), Vector2(sr.end.x, c.start_line_y), white, 0.008, 0.14)
	var top_r := _rect_containing(Vector2(c.back_line_x, c.unload_target.y))
	_line(Vector2(c.back_line_x, top_r.position.y), Vector2(c.back_line_x, top_r.end.y), white, 0.008, 0.14)
	_square(c.unload_target, c.unload_heading, Sim.PALLET + 0.04, white)
	# 바닥 글씨: 출발/도착, 후진선, 하역
	_floor_text("출발 · 도착", Vector2(0.0, c.start_line_y - 0.5), PI / 2, 0.32)
	_floor_text("후진선", Vector2(c.back_line_x + 0.35, top_r.get_center().y), 0.0, 0.26)
	_floor_text("하역 위치", c.unload_target + Vector2(0, -0.95), 0.0, 0.22)
	# 야드 주차 구획선(코스 밖 장식)
	var faded := Mats.cutout("line_wear", Vector3(0.4, 0.4, 0.4))
	faded.albedo_color = Color(0.85, 0.85, 0.8, 0.9)
	for i in 6:
		var x := _yard.position.x + 2.0 + i * 2.6
		_line(Vector2(x, _yard.end.y - 1.0), Vector2(x, _yard.end.y - 6.0), faded, 0.005, 0.08)


func _floor_text(t: String, p: Vector2, ang: float, px := 0.3) -> void:
	var l := Label3D.new()
	l.text = t
	l.font_size = 96
	l.pixel_size = px / 100.0
	l.modulate = Color(0.93, 0.93, 0.9, 0.9)
	l.outline_size = 0
	l.position = v3(p, 0.012)
	l.rotation = Vector3(-PI / 2, ang - PI / 2, 0)
	l.no_depth_test = false
	l.double_sided = false
	add_child(l)


func _rect_containing(p: Vector2) -> Rect2:
	for r in course.rects:
		if r.has_point(p):
			return r
	return course.rects[0]


func _line(a: Vector2, b: Vector2, m: Material, h := 0.006, w := LINE_W) -> void:
	var mi := box(self, Vector3(a.distance_to(b) + w, h, w), v3((a + b) * 0.5, h * 0.5), m)
	mi.rotation.y = (b - a).angle()


func _square(c: Vector2, ang: float, s: float, m: Material) -> void:
	var h := s * 0.5
	var pts := []
	for k: Vector2 in [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]:
		pts.append(c + k.rotated(ang))
	for i in 4:
		_line(pts[i], pts[(i + 1) % 4], m, 0.007, 0.07)


# ---------- 드럼·팔레트 ----------
func _drum_and_pallets(c: Course) -> void:
	drum = make_drum(c.drum_radius, c.drum_height)
	add_child(drum)
	drum.position = v3(c.drum_pos)
	pallet = make_pallet(Color(0.95, 0.85, 0.7))
	add_child(pallet)
	guide = make_pallet(Color(1.0, 0.8, 0.45))
	add_child(guide)
	guide.position = v3(c.guide_pos)
	guide.rotation.y = c.guide_heading


static func make_drum(r: float, h: float) -> Node3D:
	var n := Node3D.new()
	var body := Mats.tex("drum", Vector3(1, 1, 1), 0.45, 0.35)
	var mi := cyl(n, r, h, Vector3(0, h * 0.5, 0), body, 32)
	mi.rotation.y = PI * 0.5
	var ring := Mats.plain(Color(0.1, 0.3, 0.6), 0.4, 0.5)
	for k in [0.31, 0.62]:
		cyl(n, r + 0.012, 0.035, Vector3(0, h * k, 0), ring, 32)
	var lid := Mats.plain(Color(0.14, 0.36, 0.68), 0.35, 0.5)
	cyl(n, r + 0.01, 0.025, Vector3(0, h - 0.012, 0), lid, 32)
	cyl(n, 0.035, 0.03, Vector3(r * 0.5, h + 0.01, 0), Mats.plain(Color(0.6, 0.6, 0.62), 0.4, 0.8), 12)
	return n


## 1100x1100 목재 팔레트. 원점 = 바닥 가운데.
static func make_pallet(tint: Color) -> Node3D:
	var n := Node3D.new()
	var m := Mats.tex("wood", Vector3(1.2, 1.2, 1.2), 0.85, 0.0, tint)
	var dark := Mats.tex("wood", Vector3(1.2, 1.2, 1.2), 0.9, 0.0, tint.darkened(0.3))
	var s := Sim.PALLET
	for z in [-0.48, 0.0, 0.48]:
		box(n, Vector3(s, 0.022, 0.14), Vector3(0, 0.011, z), dark)
	for x in [-0.48, 0.0, 0.48]:
		for z in [-0.48, 0.0, 0.48]:
			box(n, Vector3(0.14, 0.1, 0.14), Vector3(x, 0.072, z), dark)
	for x in [-0.5, -0.3, -0.1, 0.1, 0.3, 0.5]:
		box(n, Vector3(0.1, 0.022, s), Vector3(x, 0.133, 0), m)
	box(n, Vector3(s, 0.02, 0.14), Vector3(0, 0.112, -0.48), m)
	box(n, Vector3(s, 0.02, 0.14), Vector3(0, 0.112, 0.48), m)
	return n


# ---------- 펜스 ----------
func _fence() -> void:
	var post_m := Mats.plain(Color(0.45, 0.47, 0.5), 0.5, 0.7)
	var mesh_m := Mats.cutout("chainlink", Vector3(1.0, 1.0, 1.0))
	var h := 2.0
	for e in _edges(_yard.grow(0.6)):
		var a: Vector2 = e[0]
		var bb: Vector2 = e[1]
		var len := a.distance_to(bb)
		var d := (bb - a) / len
		var n := int(ceil(len / 3.0))
		for i in n + 1:
			var p := a + d * minf(i * 3.0, len)
			cyl(self, 0.04, h + 0.1, v3(p, (h + 0.1) * 0.5), post_m, 8)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(len, h)
		pm.orientation = PlaneMesh.FACE_Z
		mi.mesh = pm
		var mm := mesh_m.duplicate() as StandardMaterial3D
		mm.uv1_scale = Vector3(len / 1.0, h / 1.0, 1)
		mi.material_override = mm
		mi.position = v3((a + bb) * 0.5, h * 0.5 + 0.05)
		mi.rotation.y = -(bb - a).angle()
		add_child(mi)
		# 위 가로 파이프
		var rail := box(self, Vector3(len, 0.05, 0.05), v3((a + bb) * 0.5, h + 0.05), post_m)
		rail.rotation.y = (bb - a).angle()


# ---------- 창고 ----------
func _warehouse() -> void:
	var cx := _yard.get_center().x
	var y := _yard.end.y + 2.5          # 펜스 너머 북쪽
	var w := 34.0
	var d := 14.0
	var h := 8.0
	var wall := Mats.tex("corrugated", Vector3(w / 2.0, h / 2.0, 1), 0.6, 0.5, Color.WHITE, "corrugated_n")
	var base := Mats.tex("concrete", Vector3(8, 1, 1), 0.9)
	var hub := Node3D.new()
	hub.position = v3(Vector2(cx, y + d * 0.5))
	add_child(hub)
	box(hub, Vector3(w, 1.2, d), Vector3(0, 0.6, 0), base)
	box(hub, Vector3(w, h - 1.2, d), Vector3(0, 1.2 + (h - 1.2) * 0.5, 0), wall)
	var roof := Mats.plain(Color(0.28, 0.3, 0.33), 0.7, 0.3)
	box(hub, Vector3(w + 0.8, 0.3, d + 0.8), Vector3(0, h + 0.15, 0), roof)
	for i in 5:
		box(hub, Vector3(0.6, 0.6, d + 1.0), Vector3(-w * 0.4 + i * w * 0.2, h + 0.5, 0), roof)
	# 롤러 셔터 3개 + 파란 띠 + 간판
	var door := Mats.plain(Color(0.78, 0.8, 0.82), 0.5, 0.6)
	var stripe := Mats.plain(Color(0.1, 0.35, 0.7), 0.6)
	for i in 3:
		var x := -w * 0.3 + i * w * 0.3
		box(hub, Vector3(5.0, 4.6, 0.12), Vector3(x, 2.3, d * 0.5 + 0.02), door)
		for k in 9:
			box(hub, Vector3(5.0, 0.04, 0.14), Vector3(x, 0.5 + k * 0.5, d * 0.5 + 0.03), Mats.plain(Color(0.6, 0.62, 0.65), 0.6, 0.5))
	box(hub, Vector3(w, 0.5, 0.1), Vector3(0, h - 1.0, d * 0.5 + 0.03), stripe)
	var sign := Label3D.new()
	sign.text = "제2물류센터  ·  안전제일"
	sign.font_size = 96
	sign.pixel_size = 0.018
	sign.modulate = Color(0.97, 0.97, 0.95)
	sign.outline_size = 10
	sign.outline_modulate = Color(0.08, 0.2, 0.4)
	sign.position = Vector3(0, h - 1.0, d * 0.5 + 0.1)
	hub.add_child(sign)
	# 창고 앞 가로등 2개
	for x in [-w * 0.45, w * 0.45]:
		_lamp(Vector2(cx + x, y - 1.5))


func _lamp(p: Vector2) -> void:
	var m := Mats.plain(Color(0.35, 0.37, 0.4), 0.5, 0.7)
	cyl(self, 0.08, 7.0, v3(p, 3.5), m, 10)
	box(self, Vector3(1.2, 0.08, 0.08), v3(p + Vector2(0.5, 0), 6.95), m)
	box(self, Vector3(0.5, 0.12, 0.3), v3(p + Vector2(1.0, 0), 6.9), m)
	box(self, Vector3(0.44, 0.02, 0.24), v3(p + Vector2(1.0, 0), 6.83), Mats.emissive(Color(1.0, 0.95, 0.8), 0.8))


# ---------- 팔레트 랙 ----------
func _racks() -> void:
	var x := _yard.end.x - 3.0
	var y0 := _yard.position.y + 3.0
	var frame := Mats.plain(Color(0.1, 0.35, 0.7), 0.5, 0.4)
	var beam := Mats.plain(Color(0.95, 0.5, 0.1), 0.5, 0.4)
	var cardboard := Mats.tex("cardboard", Vector3(1, 1, 1), 0.9)
	var rack := Node3D.new()
	rack.position = v3(Vector2(x, y0 + 7.0))
	add_child(rack)
	var bays := 5
	var bay_w := 2.8
	var depth := 1.1
	for i in bays + 1:
		var z := -7.0 + i * bay_w
		for dx in [-depth * 0.5, depth * 0.5]:
			box(rack, Vector3(0.09, 4.5, 0.09), Vector3(dx, 2.25, z), frame)
		box(rack, Vector3(depth, 0.06, 0.06), Vector3(0, 0.3, z), frame)
		box(rack, Vector3(depth, 0.06, 0.06), Vector3(0, 2.3, z), frame)
	for i in bays:
		var zc := -7.0 + (i + 0.5) * bay_w
		for lvl in [0.3, 2.3]:
			for dx in [-depth * 0.5, depth * 0.5]:
				box(rack, Vector3(0.1, 0.12, bay_w), Vector3(dx, lvl + 0.06, zc), beam)
			# 팔레트 + 상자 (몇 칸은 비움)
			if (i + int(lvl)) % 3 == 1:
				continue
			for k in 2:
				var zz := zc - 0.65 + k * 1.3
				var p := make_pallet(Color(0.85, 0.75, 0.6))
				p.position = Vector3(0, lvl + 0.12, zz)
				rack.add_child(p)
				var bh := 0.6 + 0.3 * ((i + k) % 3)
				box(rack, Vector3(0.95, bh, 1.0), Vector3(0, lvl + 0.27 + bh * 0.5, zz), cardboard)
	# 랙 끝 안전 가드(노란색)
	for z in [-7.2, 7.2]:
		box(rack, Vector3(depth + 0.4, 0.4, 0.1), Vector3(0, 0.2, z), Mats.plain(YELLOW, 0.6))


# ---------- 소품 ----------
func _props(b: Rect2) -> void:
	# 감독관 천막 + 책상·의자 (서쪽)
	var tent := Node3D.new()
	tent.position = v3(Vector2(_yard.position.x + 4.5, b.position.y + 2.0))
	add_child(tent)
	var pole := Mats.plain(Color(0.8, 0.8, 0.82), 0.4, 0.7)
	for dx in [-1.5, 1.5]:
		for dz in [-1.5, 1.5]:
			cyl(tent, 0.03, 2.4, Vector3(dx, 1.2, dz), pole, 8)
	var canopy := Mats.plain(Color(0.9, 0.9, 0.88), 0.8)
	box(tent, Vector3(3.4, 0.05, 3.4), Vector3(0, 2.42, 0), canopy)
	cyl(tent, 0.0, 0.7, Vector3(0, 2.8, 0), canopy, 4, 2.45)
	box(tent, Vector3(1.4, 0.05, 0.7), Vector3(0, 0.75, 0), Mats.plain(Color(0.85, 0.82, 0.75), 0.7))
	for dx in [-0.6, 0.6]:
		box(tent, Vector3(0.05, 0.72, 0.05), Vector3(dx, 0.36, 0.3), pole)
		box(tent, Vector3(0.05, 0.72, 0.05), Vector3(dx, 0.36, -0.3), pole)
	for dx in [-0.4, 0.4]:
		box(tent, Vector3(0.45, 0.05, 0.45), Vector3(dx, 0.45, 0.9), Mats.plain(Color(0.2, 0.2, 0.22), 0.6))
		box(tent, Vector3(0.45, 0.45, 0.05), Vector3(dx, 0.68, 1.12), Mats.plain(Color(0.2, 0.2, 0.22), 0.6))
	# 콘(코스 모서리 바깥)
	var cone_m := Mats.plain(Color(1.0, 0.42, 0.1), 0.65)
	var cone_w := Mats.plain(Color(0.95, 0.95, 0.92), 0.6)
	var bb := b.grow(1.6)
	for p in [bb.position, Vector2(bb.end.x, bb.position.y), bb.end, Vector2(bb.position.x, bb.end.y), Vector2(bb.get_center().x, bb.end.y)]:
		var n := Node3D.new()
		n.position = v3(p)
		add_child(n)
		box(n, Vector3(0.4, 0.04, 0.4), Vector3(0, 0.02, 0), Mats.plain(Color(0.15, 0.15, 0.15), 0.9))
		cyl(n, 0.04, 0.55, Vector3(0, 0.3, 0), cone_m, 12, 0.17)
		cyl(n, 0.09, 0.08, Vector3(0, 0.33, 0), cone_w, 12, 0.11)
	# 드럼 더미(동쪽), 타이어 더미(남서)
	for i in 4:
		var dm := make_drum(0.29, 0.9)
		dm.position = v3(Vector2(_yard.end.x - 7.5 + (i % 2) * 0.65, _yard.position.y + 1.6 + int(i / 2) * 0.65))
		add_child(dm)
	var tire := Mats.tex("tire", Vector3(6, 1, 1), 0.95)
	for i in 3:
		var t := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.22
		tm.outer_radius = 0.42
		t.mesh = tm
		t.material_override = tire
		t.position = v3(Vector2(_yard.position.x + 2.0, _yard.end.y - 2.5), 0.1 + i * 0.2)
		add_child(t)
	# 주차된 지게차(초록) — 야드 남동쪽
	var parked := ForkliftView.new()
	parked.paint = "paint_green"
	parked.position = v3(Vector2(_yard.end.x - 3.5, _yard.position.y + 10.5))
	parked.rotation.y = PI * 0.5
	add_child(parked)
	# 안전 표지판 2개
	_sign(Vector2(b.position.x - 2.0, b.end.y + 1.2), "지게차 작업 중\n보행자 출입 금지")
	_sign(Vector2(b.end.x + 1.5, b.position.y - 0.5), "실기 시험장\n제한속도 10")


func _sign(p: Vector2, t: String) -> void:
	var m := Mats.plain(Color(0.5, 0.52, 0.55), 0.5, 0.7)
	cyl(self, 0.03, 1.8, v3(p, 0.9), m, 8)
	var board := box(self, Vector3(0.9, 0.6, 0.03), v3(p, 1.6), Mats.plain(Color(0.98, 0.85, 0.15), 0.6))
	board.rotation.y = PI
	var l := Label3D.new()
	l.text = t
	l.font_size = 64
	l.pixel_size = 0.009
	l.modulate = Color(0.08, 0.08, 0.08)
	l.position = v3(p, 1.6) + Vector3(0, 0, 0.02)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.rotation.y = PI
	add_child(l)


# ---------- 나무(펜스 밖) ----------
func _trees() -> void:
	var trunk := Mats.plain(Color(0.36, 0.26, 0.18), 0.9)
	var leaf_a := Mats.plain(Color(0.22, 0.42, 0.18), 0.95)
	var leaf_b := Mats.plain(Color(0.3, 0.5, 0.2), 0.95)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 42
	var out := _yard.grow(3.5)
	for i in 26:
		var p: Vector2
		match i % 3:
			0: p = Vector2(out.position.x - rnd.randf_range(0, 5), rnd.randf_range(out.position.y, out.end.y))
			1: p = Vector2(out.end.x + rnd.randf_range(0, 5), rnd.randf_range(out.position.y, out.end.y))
			_: p = Vector2(rnd.randf_range(out.position.x, out.end.x), out.position.y - rnd.randf_range(0, 6))
		var h := rnd.randf_range(3.5, 6.0)
		var n := Node3D.new()
		n.position = v3(p)
		add_child(n)
		cyl(n, 0.12, h * 0.5, Vector3(0, h * 0.25, 0), trunk, 8, 0.18)
		var lm := leaf_a if i % 2 == 0 else leaf_b
		sphere(n, h * 0.32, Vector3(0, h * 0.62, 0), lm, 10)
		sphere(n, h * 0.24, Vector3(h * 0.15, h * 0.78, h * 0.1), lm, 8)
		sphere(n, h * 0.22, Vector3(-h * 0.14, h * 0.74, -h * 0.12), lm, 8)


func sync(sim: Sim) -> void:
	pallet.position = v3(sim.pallet_pos, sim.pallet_base)
	pallet.rotation.y = sim.pallet_heading
	pallet.rotation.z = 0.25 if sim.pallet_fallen else 0.0
