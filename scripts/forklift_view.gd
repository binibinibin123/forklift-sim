class_name ForkliftView
extends Node3D
## 지게차 3D 모델(코드 생성, 2.5t 카운터밸런스형). 원점 = 앞축 가운데 바닥, 로컬 +X = 앞, +Z = 오른쪽.

const DARK := Color(0.16, 0.16, 0.17)
const STEEL := Color(0.55, 0.56, 0.58)

var paint := "paint_orange"      # textures/<paint>.png (차체 도장)

var mast: Node3D                 # 바깥 마스트(틸트 축)
var inner_mast: Node3D           # 2단 안쪽 마스트(캐리지가 높이 올라가면 같이 상승)
var carriage: Node3D
var rear_pivots: Array[Node3D] = []
var wheel_meshes: Array[Node3D] = []
var beacon: MeshInstance3D
var steering_wheel: Node3D
var cab_eye: Node3D
var headlights: Array[MeshInstance3D] = []
var _chains: Array[MeshInstance3D] = []
var _wheel_spin := 0.0

const INNER_START := 1.3         # 포크 높이가 이보다 높으면 안쪽 마스트가 올라감


func _ready() -> void:
	var body := Mats.tex(paint, Vector3(2, 2, 2), 0.42, 0.15)
	var body_dark := Mats.tex("paint_dark", Vector3(2, 2, 2), 0.6, 0.2)
	var dark := Mats.plain(DARK, 0.8)
	var steel := Mats.plain(STEEL, 0.45, 0.75)
	var chrome := Mats.plain(Color(0.82, 0.83, 0.85), 0.2, 0.95)
	var rubber := Mats.plain(Color(0.06, 0.06, 0.06), 0.95)
	var tire := Mats.tex("tire", Vector3(5, 1, 1), 0.95)
	var glass := Mats.glass(Color(0.7, 0.82, 0.9, 0.14))

	# ---- 차체 ----
	World.box(self, Vector3(1.95, 0.5, 1.12), Vector3(-0.9, 0.56, 0), body)               # 메인 후드
	World.box(self, Vector3(1.0, 0.18, 1.1), Vector3(-1.4, 0.9, 0), body)                 # 엔진 후드 윗면
	var hood_lip := World.box(self, Vector3(0.9, 0.16, 1.1), Vector3(-1.72, 0.86, 0), body)
	hood_lip.rotation.z = deg_to_rad(-12)
	World.box(self, Vector3(1.2, 0.18, 1.0), Vector3(-0.65, 0.98, 0), body_dark)          # 바닥 발판(고무 매트)
	World.box(self, Vector3(0.5, 0.04, 0.95), Vector3(0.05, 0.86, 0), body_dark)          # 앞 발판
	for z in [-0.58, 0.58]:                                                                # 옆 스텝
		World.box(self, Vector3(0.55, 0.05, 0.1), Vector3(-0.55, 0.42, z), steel)
		World.box(self, Vector3(0.55, 0.05, 0.1), Vector3(-0.55, 0.7, z), steel)
	# 카운터웨이트(뒤, 둥근 느낌으로 3단)
	World.box(self, Vector3(0.6, 0.95, 1.16), Vector3(-2.05, 0.72, 0), body_dark)
	World.box(self, Vector3(0.5, 0.5, 1.2), Vector3(-2.15, 0.65, 0), body_dark)
	World.box(self, Vector3(0.55, 0.14, 1.18), Vector3(-2.05, 1.27, 0), body)
	World.cyl(self, 0.055, 0.6, Vector3(-2.38, 0.95, 0), body_dark, 12).rotation.x = PI / 2  # 견인핀 바
	World.box(self, Vector3(0.16, 0.08, 0.3), Vector3(-2.33, 0.45, 0), steel)              # 견인 고리
	# 번호판·후미등
	World.box(self, Vector3(0.02, 0.12, 0.34), Vector3(-2.37, 1.08, 0), Mats.plain(Color(0.95, 0.95, 0.9), 0.5))
	for z in [-0.48, 0.48]:
		World.box(self, Vector3(0.03, 0.08, 0.12), Vector3(-2.37, 1.18, z), Mats.emissive(Color(0.9, 0.1, 0.05), 0.6))
		World.box(self, Vector3(0.03, 0.08, 0.1), Vector3(-2.37, 1.18, z * 0.72), Mats.emissive(Color(1.0, 0.6, 0.1), 0.5))
	# LPG 탱크(뒤 상단)
	var lpg := World.cyl(self, 0.17, 0.75, Vector3(-2.0, 1.52, 0), Mats.plain(Color(0.85, 0.85, 0.83), 0.35, 0.6), 20)
	lpg.rotation.x = PI / 2
	for z in [-0.28, 0.28]:
		World.box(self, Vector3(0.1, 0.2, 0.04), Vector3(-2.0, 1.4, z), steel)
	# 배기관
	World.cyl(self, 0.03, 0.5, Vector3(-2.2, 0.9, -0.62), steel, 10).rotation.x = PI / 2
	# 흙받이(앞바퀴)
	for z in [-0.49, 0.49]:
		World.box(self, Vector3(0.55, 0.06, 0.3), Vector3(0.0, 0.7, z), body)
		World.box(self, Vector3(0.08, 0.26, 0.3), Vector3(0.26, 0.56, z), body)

	# ---- 좌석·계기 ----
	World.box(self, Vector3(0.5, 0.14, 0.52), Vector3(-1.15, 1.13, 0), Mats.plain(Color(0.12, 0.12, 0.13), 0.9))
	World.box(self, Vector3(0.12, 0.6, 0.52), Vector3(-1.42, 1.45, 0), Mats.plain(Color(0.12, 0.12, 0.13), 0.9))
	World.box(self, Vector3(0.02, 0.5, 0.06), Vector3(-1.34, 1.42, 0.2), Mats.plain(Color(0.9, 0.5, 0.05), 0.7))   # 안전벨트
	World.box(self, Vector3(0.3, 0.3, 0.75), Vector3(-0.42, 1.2, 0), body_dark)             # 대시보드
	World.box(self, Vector3(0.02, 0.1, 0.24), Vector3(-0.56, 1.3, -0.12), Mats.emissive(Color(0.2, 0.7, 0.9), 0.6))  # 계기 화면
	# 핸들
	steering_wheel = Node3D.new()
	add_child(steering_wheel)
	steering_wheel.position = Vector3(-0.62, 1.42, -0.12)
	steering_wheel.rotation.z = deg_to_rad(-35)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.15
	tm.outer_radius = 0.18
	ring.mesh = tm
	ring.material_override = dark
	steering_wheel.add_child(ring)
	World.box(steering_wheel, Vector3(0.03, 0.03, 0.3), Vector3.ZERO, dark)
	World.cyl(steering_wheel, 0.025, 0.08, Vector3(0, 0.04, 0.14), Mats.plain(Color(0.8, 0.1, 0.1), 0.5))  # 노브
	World.cyl(self, 0.03, 0.42, Vector3(-0.5, 1.2, -0.12), dark, 10).rotation.z = deg_to_rad(-35)
	# 유압 레버 3개(검정 손잡이)
	for i in 3:
		World.box(self, Vector3(0.025, 0.28, 0.025), Vector3(-0.42, 1.44, 0.16 + i * 0.07), steel)
		World.sphere(self, 0.025, Vector3(-0.42, 1.59, 0.16 + i * 0.07), dark, 8)
	# 페달
	for z in [-0.3, -0.18, 0.08]:
		World.box(self, Vector3(0.12, 0.02, 0.08), Vector3(-0.3, 1.0, z), dark).rotation.z = deg_to_rad(35)

	# ---- 운전석 가드(오버헤드 가드) ----
	for x in [-0.15, -1.62]:
		for z in [-0.52, 0.52]:
			World.box(self, Vector3(0.07, 1.25, 0.07), Vector3(x, 1.57, z), body)
	World.box(self, Vector3(1.6, 0.07, 0.07), Vector3(-0.88, 2.2, -0.52), body)
	World.box(self, Vector3(1.6, 0.07, 0.07), Vector3(-0.88, 2.2, 0.52), body)
	World.box(self, Vector3(0.07, 0.07, 1.1), Vector3(-0.15, 2.2, 0), body)
	World.box(self, Vector3(0.07, 0.07, 1.1), Vector3(-1.62, 2.2, 0), body)
	for i in 7:
		World.box(self, Vector3(1.5, 0.03, 0.04), Vector3(-0.88, 2.22, -0.45 + i * 0.15), steel)
	# 앞 유리창 (반투명)
	World.box(self, Vector3(0.015, 1.1, 1.0), Vector3(-0.18, 1.62, 0), glass)
	# 사이드미러
	for z in [-0.66, 0.66]:
		World.box(self, Vector3(0.02, 0.1, 0.08), Vector3(-0.3, 1.9, z * 1.1), dark)
		World.box(self, Vector3(0.015, 0.015, 0.14), Vector3(-0.22, 1.9, z * 1.0), steel)
	# 경광등 + 작업등
	beacon = World.cyl(self, 0.07, 0.11, Vector3(-1.5, 2.3, 0.3), Mats.emissive(Color(1, 0.5, 0.05), 1.2), 16)
	World.cyl(self, 0.08, 0.03, Vector3(-1.5, 2.23, 0.3), dark, 16)
	for z in [-0.42, 0.42]:
		var hl := World.cyl(self, 0.06, 0.05, Vector3(-0.12, 2.1, z), Mats.emissive(Color(1, 0.97, 0.85), 1.5), 14)
		hl.rotation.z = PI / 2
		headlights.append(hl)
		World.box(self, Vector3(0.1, 0.14, 0.14), Vector3(-0.16, 2.1, z), dark)
	# 앞 헤드라이트(마스트 옆)
	for z in [-0.62, 0.62]:
		var hl := World.cyl(self, 0.055, 0.04, Vector3(0.15, 0.95, z), Mats.emissive(Color(1, 0.97, 0.85), 1.5), 14)
		hl.rotation.z = PI / 2
		headlights.append(hl)
		World.box(self, Vector3(0.06, 0.13, 0.13), Vector3(0.12, 0.95, z), body_dark)

	# ---- 바퀴 ----
	for z in [-0.49, 0.49]:
		var hub := Node3D.new()
		hub.position = Vector3(0, 0.33, z)
		add_child(hub)
		_wheel(hub, 0.33, 0.24, tire, chrome, dark)
		wheel_meshes.append(hub)
	for z in [-0.46, 0.46]:
		var piv := Node3D.new()
		piv.position = Vector3(-Sim.WHEELBASE, 0.27, z)
		add_child(piv)
		var hub := Node3D.new()
		piv.add_child(hub)
		_wheel(hub, 0.27, 0.2, tire, chrome, dark)
		rear_pivots.append(piv)
		wheel_meshes.append(hub)
	# 뒤 차축
	World.cyl(self, 0.05, 0.9, Vector3(-Sim.WHEELBASE, 0.27, 0), dark, 10).rotation.x = PI / 2

	# ---- 마스트(2단) ----
	mast = Node3D.new()
	mast.position = Vector3(0.28, 0.35, 0)
	add_child(mast)
	var rail := Mats.tex("paint_dark", Vector3(1, 1, 1), 0.5, 0.3)
	for z in [-0.4, 0.4]:
		World.box(mast, Vector3(0.14, 2.3, 0.1), Vector3(0.0, 1.1, z), rail)              # 바깥 레일
	World.box(mast, Vector3(0.12, 0.12, 0.9), Vector3(0.0, 2.2, 0), rail)
	World.box(mast, Vector3(0.12, 0.12, 0.9), Vector3(0.0, 0.0, 0), rail)
	World.box(mast, Vector3(0.12, 0.12, 0.9), Vector3(0.0, 1.1, 0), rail)
	# 틸트 실린더 2개(차체 ↔ 마스트)
	for z in [-0.46, 0.46]:
		var tc := World.cyl(self, 0.045, 0.6, Vector3(-0.15, 0.85, z), chrome, 12)
		tc.rotation.z = deg_to_rad(60)
		var tb := World.cyl(self, 0.06, 0.4, Vector3(-0.38, 0.72, z), body_dark, 12)
		tb.rotation.z = deg_to_rad(60)
	inner_mast = Node3D.new()
	mast.add_child(inner_mast)
	for z in [-0.3, 0.3]:
		World.box(inner_mast, Vector3(0.1, 2.2, 0.08), Vector3(0.08, 1.15, z), rail)       # 안쪽 레일
	World.box(inner_mast, Vector3(0.1, 0.1, 0.7), Vector3(0.08, 2.25, 0), rail)
	# 리프트 실린더 + 체인 풀리
	World.cyl(inner_mast, 0.055, 2.0, Vector3(0.08, 1.0, 0), body_dark, 14)
	World.cyl(inner_mast, 0.035, 2.0, Vector3(0.08, 1.9, 0), chrome, 12)
	for z in [-0.12, 0.12]:
		var pulley := World.cyl(inner_mast, 0.09, 0.03, Vector3(0.08, 2.3, z), steel, 16)
		pulley.rotation.x = PI / 2
	# 캐리지 + 포크
	carriage = Node3D.new()
	mast.add_child(carriage)
	var fork_m := Mats.plain(Color(0.2, 0.2, 0.22), 0.55, 0.6)
	var heel := Sim.CARRIAGE - 0.28
	World.box(carriage, Vector3(0.06, 0.5, 1.0), Vector3(heel - 0.05, 0.32, 0), fork_m)      # 캐리지 판
	World.box(carriage, Vector3(0.06, 0.06, 1.0), Vector3(heel - 0.05, 0.08, 0), fork_m)
	for i in 5:                                                                               # 백레스트
		World.box(carriage, Vector3(0.04, 0.95, 0.04), Vector3(heel - 0.08, 0.98, -0.44 + i * 0.22), fork_m)
	World.box(carriage, Vector3(0.04, 0.04, 1.0), Vector3(heel - 0.08, 1.45, 0), fork_m)
	World.box(carriage, Vector3(0.04, 0.04, 1.0), Vector3(heel - 0.08, 1.0, 0), fork_m)
	for z in [-Sim.FORK_SIDE, Sim.FORK_SIDE]:
		World.box(carriage, Vector3(Sim.FORK_LEN, Sim.FORK_T, 0.1), Vector3(heel + Sim.FORK_LEN * 0.5, Sim.FORK_T * 0.5, z), fork_m)
		World.box(carriage, Vector3(Sim.FORK_T, 0.55, 0.1), Vector3(heel + Sim.FORK_T * 0.5, 0.27, z), fork_m)
		# 포크 끝 테이퍼
		var tip := World.box(carriage, Vector3(0.12, Sim.FORK_T * 0.5, 0.1), Vector3(heel + Sim.FORK_LEN + 0.05, Sim.FORK_T * 0.25, z), fork_m)
		tip.rotation.z = deg_to_rad(-8)
	# 리프트 체인(캐리지 위 ↔ 풀리). sync에서 길이 갱신
	var chain_m := Mats.plain(Color(0.3, 0.3, 0.32), 0.6, 0.7)
	for z in [-0.12, 0.12]:
		var ch := World.box(mast, Vector3(0.02, 1.0, 0.025), Vector3(heel - 0.02, 1.0, z), chain_m)
		_chains.append(ch)

	cab_eye = Node3D.new()
	cab_eye.position = Vector3(-1.1, 2.0, 0.0)
	add_child(cab_eye)


static func _wheel(hub: Node3D, r: float, w: float, tire: Material, rim: Material, dark: Material) -> void:
	var t := World.cyl(hub, r, w, Vector3.ZERO, tire, 28)
	t.rotation.x = PI / 2
	var rm := World.cyl(hub, r * 0.58, w + 0.01, Vector3.ZERO, rim, 20)
	rm.rotation.x = PI / 2
	var hb := World.cyl(hub, r * 0.22, w + 0.04, Vector3.ZERO, dark, 12)
	hb.rotation.x = PI / 2
	for i in 5:
		var bolt := World.cyl(hub, r * 0.04, w + 0.05, Vector3(cos(i * TAU / 5) * r * 0.38, sin(i * TAU / 5) * r * 0.38, 0), dark, 6)
		bolt.rotation.x = PI / 2


func sync(sim: Sim, dt: float) -> void:
	position = World.v3(sim.pos)
	rotation.y = sim.heading
	mast.rotation.z = deg_to_rad(sim.tilt)
	carriage.position.y = sim.lift - mast.position.y
	inner_mast.position.y = maxf(0.0, sim.lift - INNER_START)
	var top := inner_mast.position.y + 2.3
	for ch in _chains:
		var bottom := carriage.position.y + 1.45
		var len := maxf(0.05, top - bottom)
		(ch.mesh as BoxMesh).size.y = len
		ch.position.y = bottom + len * 0.5
	for p in rear_pivots:
		p.rotation.y = -sim.steer * Sim.MAX_STEER
	steering_wheel.get_child(0).rotation.y = sim.steer * PI * 3.0
	steering_wheel.get_child(1).rotation.y = sim.steer * PI * 3.0
	steering_wheel.get_child(2).position = Vector3(0.14 * sin(sim.steer * PI * 3.0), 0.04, 0.14 * cos(sim.steer * PI * 3.0))
	_wheel_spin += sim.speed * dt / 0.3
	for i in wheel_meshes.size():
		wheel_meshes[i].rotation.z = -_wheel_spin
	beacon.rotation.y += dt * 8.0
