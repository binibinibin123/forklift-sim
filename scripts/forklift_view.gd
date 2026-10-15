class_name ForkliftView
extends Node3D
## 지게차 3D 모델(코드 생성). 원점 = 앞축 가운데 바닥, 로컬 +X = 앞, +Z = 오른쪽.

const BODY := Color(0.97, 0.62, 0.08)
const DARK := Color(0.16, 0.16, 0.17)
const STEEL := Color(0.32, 0.33, 0.35)

var mast: Node3D
var carriage: Node3D
var rear_pivots: Array[Node3D] = []
var wheel_meshes: Array[Node3D] = []
var beacon: MeshInstance3D
var steering_wheel: Node3D
var cab_eye: Node3D


func _ready() -> void:
	var body := World.mat(BODY, 0.5, 0.1)
	var dark := World.mat(DARK, 0.8)
	var steel := World.mat(STEEL, 0.5, 0.6)
	var tire := World.mat(Color(0.08, 0.08, 0.08), 0.95)
	# 차체
	World.box(self, Vector3(2.1, 0.62, 1.12), Vector3(-0.95, 0.62, 0), body)
	World.box(self, Vector3(0.55, 1.0, 1.14), Vector3(-2.05, 0.75, 0), dark)          # 카운터웨이트
	World.box(self, Vector3(0.5, 0.12, 1.16), Vector3(-2.05, 1.3, 0), body)
	World.box(self, Vector3(1.2, 0.16, 0.9), Vector3(-0.6, 0.98, 0), dark)            # 바닥 발판
	# 좌석
	World.box(self, Vector3(0.48, 0.12, 0.5), Vector3(-1.15, 1.12, 0), dark)
	World.box(self, Vector3(0.1, 0.55, 0.5), Vector3(-1.42, 1.42, 0), dark)
	# 운전석 가드
	for x in [-0.12, -1.62]:
		for z in [-0.5, 0.5]:
			World.box(self, Vector3(0.07, 1.2, 0.07), Vector3(x, 1.55, z), steel)
	for i in 6:
		World.box(self, Vector3(1.58, 0.04, 0.05), Vector3(-0.87, 2.16, -0.48 + i * 0.192), steel)
	World.box(self, Vector3(1.6, 0.06, 0.06), Vector3(-0.87, 2.16, -0.5), steel)
	World.box(self, Vector3(1.6, 0.06, 0.06), Vector3(-0.87, 2.16, 0.5), steel)
	beacon = World.cyl(self, 0.07, 0.1, Vector3(-1.5, 2.25, 0), World.mat(Color(1, 0.5, 0.05), 0.3))
	var bm := beacon.material_override as StandardMaterial3D
	bm.emission_enabled = true
	bm.emission = Color(1, 0.45, 0.0)
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
	World.cyl(steering_wheel, 0.025, 0.08, Vector3(0, 0.04, 0.14), World.mat(Color(0.8, 0.1, 0.1)))  # 노브
	World.box(self, Vector3(0.08, 0.4, 0.08), Vector3(-0.5, 1.2, -0.12), dark)
	# 레버 3개
	for i in 3:
		World.box(self, Vector3(0.025, 0.28, 0.025), Vector3(-0.42, 1.28, 0.18 + i * 0.07), dark)
	# 바퀴
	for z in [-0.49, 0.49]:
		var w := World.cyl(self, 0.33, 0.24, Vector3(0, 0.33, z), tire)
		w.rotation.x = PI / 2
		wheel_meshes.append(w)
	for z in [-0.46, 0.46]:
		var piv := Node3D.new()
		piv.position = Vector3(-Sim.WHEELBASE, 0.27, z)
		add_child(piv)
		var w := World.cyl(piv, 0.27, 0.2, Vector3.ZERO, tire)
		w.rotation.x = PI / 2
		rear_pivots.append(piv)
		wheel_meshes.append(w)
	# 마스트(틸트 축은 앞축 위)
	mast = Node3D.new()
	mast.position = Vector3(0.28, 0.35, 0)
	add_child(mast)
	for z in [-0.36, 0.36]:
		World.box(mast, Vector3(0.12, 2.3, 0.08), Vector3(0.0, 1.1, z), steel)
		World.box(mast, Vector3(0.1, 2.2, 0.06), Vector3(0.1, 1.15, z * 0.85), steel)
	World.box(mast, Vector3(0.1, 0.1, 0.8), Vector3(0.0, 2.2, 0), steel)
	World.box(mast, Vector3(0.1, 0.1, 0.8), Vector3(0.0, 0.0, 0), steel)
	World.cyl(mast, 0.04, 1.6, Vector3(0.0, 0.8, 0), World.mat(Color(0.75, 0.75, 0.78), 0.3, 0.9))  # 리프트 실린더
	# 캐리지 + 포크 (y = 포크 바닥 높이 - 마스트 높이)
	carriage = Node3D.new()
	mast.add_child(carriage)
	var fork_m := World.mat(Color(0.2, 0.2, 0.22), 0.6, 0.5)
	var heel := Sim.CARRIAGE - 0.28
	World.box(carriage, Vector3(0.06, 0.45, 1.0), Vector3(heel - 0.05, 0.3, 0), fork_m)
	for i in 4:
		World.box(carriage, Vector3(0.04, 0.9, 0.04), Vector3(heel - 0.06, 0.95, -0.42 + i * 0.28), fork_m)    # 백레스트
	World.box(carriage, Vector3(0.04, 0.04, 1.0), Vector3(heel - 0.06, 1.38, 0), fork_m)
	for z in [-Sim.FORK_SIDE, Sim.FORK_SIDE]:
		World.box(carriage, Vector3(Sim.FORK_LEN, Sim.FORK_T, 0.1), Vector3(heel + Sim.FORK_LEN * 0.5, Sim.FORK_T * 0.5, z), fork_m)
		World.box(carriage, Vector3(Sim.FORK_T, 0.5, 0.1), Vector3(heel + Sim.FORK_T * 0.5, 0.25, z), fork_m)
	cab_eye = Node3D.new()
	cab_eye.position = Vector3(-1.1, 2.0, 0.0)
	add_child(cab_eye)


func sync(sim: Sim, dt: float) -> void:
	position = World.v3(sim.pos)
	rotation.y = sim.heading
	mast.rotation.z = deg_to_rad(sim.tilt)
	carriage.position.y = sim.lift - mast.position.y
	for p in rear_pivots:
		p.rotation.y = -sim.steer * Sim.MAX_STEER
	steering_wheel.rotation.y = 0.0
	steering_wheel.get_child(0).rotation.y = sim.steer * PI * 3.0
	steering_wheel.get_child(1).rotation.y = sim.steer * PI * 3.0
	steering_wheel.get_child(2).position = Vector3(0.14 * sin(sim.steer * PI * 3.0), 0.04, 0.14 * cos(sim.steer * PI * 3.0))
	beacon.rotation.y += dt * 8.0
