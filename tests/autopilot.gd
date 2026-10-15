class_name Autopilot
extends RefCounted
## 테스트용 자동 운전: 코스를 끝까지 돌 수 있는지 확인한다.

var sim: Sim
var log_points: PackedVector2Array = []


func _init(s: Sim) -> void:
	sim = s


## 꺾인 선을 반지름 r로 둥글게 깎아 촘촘한 점으로
static func rounded(points: Array, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(points[0])
	for i in range(1, points.size() - 1):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var c: Vector2 = points[i + 1]
		var d1 := (b - a).normalized()
		var d2 := (c - b).normalized()
		var p1 := b - d1 * r
		var p2 := b + d2 * r
		for k in 11:
			var t := k / 10.0
			out.append(p1.lerp(b, t).lerp(b.lerp(p2, t), t))
	out.append(points[-1])
	var dense := PackedVector2Array()
	for i in out.size() - 1:
		var n := int(ceil(out[i].distance_to(out[i + 1]) / 0.05))
		for k in n:
			dense.append(out[i].lerp(out[i + 1], float(k) / maxi(n, 1)))
	dense.append(out[-1])
	return dense


func _steer_toward(path: PackedVector2Array, reverse: bool, look := 0.9) -> float:
	var p := sim.pos
	var best := 0
	var bd := INF
	for i in path.size():
		var d := p.distance_squared_to(path[i])
		if d < bd:
			bd = d
			best = i
	var target := path[-1]
	for i in range(best, path.size()):
		if p.distance_to(path[i]) >= look:
			target = path[i]
			break
	var m := sim.dir() * (-1.0 if reverse else 1.0)
	var to := target - p
	if to.length() < 0.01:
		return 0.0
	var alpha := m.angle_to(to)
	var k: float = 2.0 * sin(alpha) / maxf(to.length(), 0.3)
	var tan_d: float = k * Sim.WHEELBASE * (-1.0 if reverse else 1.0)
	return clampf(atan(tan_d) / Sim.MAX_STEER, -1.0, 1.0)


func _tick(inp: Dictionary) -> void:
	sim.update(1.0 / 60.0, inp)
	log_points.append(sim.pos)


## 레버를 써서 포크 높이·틸트를 맞춘다(서 있는 상태)
func set_fork(h: float, tilt_deg: float) -> void:
	for i in 1200:
		var l := -1.0 if h <= 0.0 else clampf((h - sim.lift) * 20.0, -1.0, 1.0)
		var t := clampf((tilt_deg - sim.tilt) * 2.0, -1.0, 1.0)
		if h > 0.0 and absf(h - sim.lift) < 0.004 and absf(tilt_deg - sim.tilt) < 0.2:
			return
		if sim.lift <= 0.0 and h <= 0.0 and absf(tilt_deg - sim.tilt) < 0.2:
			return
		_tick({lift = l, tilt = t, brake = 1.0})
		if sim.done:
			return


func stop() -> void:
	for i in 300:
		if absf(sim.speed) < 0.005:
			return
		_tick({brake = 1.0, steer = sim.steer})


## stop_fn(sim)이 true가 될 때까지 경로를 따라감
func drive(path: PackedVector2Array, reverse: bool, stop_fn: Callable, max_speed := 1.0) -> void:
	sim.gear = -1 if reverse else 1
	for i in 60 * 120:
		if sim.done or stop_fn.call(sim):
			break
		var st := _steer_toward(path, reverse)
		var v := absf(sim.speed)
		var want := max_speed * (1.0 - 0.6 * absf(st))
		var thr := 1.0 if v < want else 0.0
		var br := 0.0 if v < want + 0.15 else 0.5
		_tick({steer = st, throttle = thr, brake = br})
	stop()
	if OS.has_environment("SIM_DEBUG"):
		print("drive end rev=", reverse, " pos=", sim.pos, " hd=", rad_to_deg(sim.heading), " step=", sim.step, " lift=", sim.lift, " eng=", sim.engaged, " car=", sim.carried, " t=", sim.t_exam)
