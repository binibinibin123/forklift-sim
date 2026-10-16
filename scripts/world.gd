class_name World
extends Node3D
## 코스·드럼·팔레트 3D 모델(코드로 생성). 2D (x, y) → 3D (x, 높이, -y).

const LINE_W := 0.09
const YELLOW := Color(0.98, 0.78, 0.1)
const WHITE := Color(0.95, 0.95, 0.92)

var course: Course
var pallet: Node3D
var guide: Node3D
var drum: Node3D


static func v3(p: Vector2, h := 0.0) -> Vector3:
	return Vector3(p.x, h, -p.y)


static func mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, segs := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


func build(c: Course) -> void:
	course = c
	var b := c.bounds().grow(6.0)
	# 바닥
	var ground := box(self, Vector3(400, 0.1, 400), v3(b.get_center(), -0.05), mat(Color(0.42, 0.43, 0.42), 0.95))
	ground.name = "Ground"
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# 웹(토스) 빌드: 호환 렌더러에서 400m 바닥이 하얗게 떠서 조명 없이 그린다.
		ground.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 코스 포장면(조금 밝게)
	var lane_m := mat(Color(0.56, 0.57, 0.55), 0.9)
	for r in c.rects:
		box(self, Vector3(r.size.x, 0.004, r.size.y), v3(r.get_center(), 0.002), lane_m)
	# 경계선
	var line_m := mat(YELLOW, 0.6)
	for seg in c.boundary_segments():
		_line(seg[0], seg[1], line_m, 0.006)
	# 출발선, 후진선
	var white := mat(WHITE, 0.6)
	var sr: Rect2 = c.zones["start"]
	_line(Vector2(sr.position.x, c.start_line_y), Vector2(sr.end.x, c.start_line_y), white, 0.008, 0.12)
	var top_r := _rect_containing(Vector2(c.back_line_x, c.unload_target.y))
	_line(Vector2(c.back_line_x, top_r.position.y), Vector2(c.back_line_x, top_r.end.y), white, 0.008, 0.12)
	# 하역 표시(팔레트 자리 네모)
	_square(c.unload_target, c.unload_heading, Sim.PALLET + 0.04, white)
	# 드럼
	drum = Node3D.new()
	add_child(drum)
	drum.position = v3(c.drum_pos)
	var drum_m := mat(Color(0.12, 0.33, 0.62), 0.45, 0.4)
	cyl(drum, c.drum_radius, c.drum_height, Vector3(0, c.drum_height * 0.5, 0), drum_m)
	var ring_m := mat(Color(0.09, 0.25, 0.48), 0.4, 0.5)
	for h in [0.3, 0.6]:
		cyl(drum, c.drum_radius + 0.012, 0.03, Vector3(0, h, 0), ring_m)
	# 팔레트
	pallet = make_pallet(Color(0.72, 0.55, 0.33))
	add_child(pallet)
	guide = make_pallet(Color(0.95, 0.75, 0.1))
	add_child(guide)
	guide.position = v3(c.guide_pos)
	guide.rotation.y = c.guide_heading
	# 주변 소품: 감독석 콘, 울타리 기둥
	var cone_m := mat(Color(1.0, 0.4, 0.1), 0.7)
	for p in [Vector2(b.position.x + 3, b.position.y + 3), Vector2(b.end.x - 3, b.position.y + 3), Vector2(b.position.x + 3, b.end.y - 3), Vector2(b.end.x - 3, b.end.y - 3)]:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.18
		cm.height = 0.5
		cone.mesh = cm
		cone.material_override = cone_m
		cone.position = v3(p, 0.25)
		add_child(cone)


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
		_line(pts[i], pts[(i + 1) % 4], m, 0.007, 0.06)


## 1100x1100 팔레트. 원점 = 바닥 가운데. 구멍은 로컬 X 방향(앞뒤)과 Z 방향 모두.
static func make_pallet(c: Color) -> Node3D:
	var n := Node3D.new()
	var m := mat(c, 0.85)
	var dark := mat(c.darkened(0.25), 0.9)
	var s := Sim.PALLET
	# 아래 판
	for z in [-0.48, 0.0, 0.48]:
		box(n, Vector3(s, 0.022, 0.14), Vector3(0, 0.011, z), dark)
	# 블록 9개
	for x in [-0.48, 0.0, 0.48]:
		for z in [-0.48, 0.0, 0.48]:
			box(n, Vector3(0.14, 0.1, 0.14), Vector3(x, 0.072, z), dark)
	# 윗판
	for x in [-0.5, -0.3, -0.1, 0.1, 0.3, 0.5]:
		box(n, Vector3(0.1, 0.022, s), Vector3(x * 1.0, 0.133, 0), m)
	box(n, Vector3(s, 0.02, 0.14), Vector3(0, 0.112, -0.48), m)
	box(n, Vector3(s, 0.02, 0.14), Vector3(0, 0.112, 0.48), m)
	return n


func sync(sim: Sim) -> void:
	pallet.position = v3(sim.pallet_pos, sim.pallet_base)
	pallet.rotation.y = sim.pallet_heading
	if sim.pallet_fallen:
		pallet.rotation.z = 0.25
	else:
		pallet.rotation.z = 0.0
