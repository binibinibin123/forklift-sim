class_name TowAutopilot
extends RefCounted
## Drives an Exam by itself: the "모범 주행" demo and the tests.
## Forward: pure pursuit on the tractor's rear axle.
## Reverse with a trailer: pure pursuit on the trailer axle gives a wanted
## hitch angle, and the tractor steers to hold it (the usual trailer-backing
## controller; reversing a trailer is unstable without that feedback).

var exam: Exam
var seg := 0
var path: PackedVector2Array
var phase := ""
var wait := 0.0
var choose_t := 0.0


func _init(e: Exam) -> void:
	exam = e
	e.step_started.connect(func(_i): _reset())
	_reset()


func _reset() -> void:
	seg = 0
	wait = 0.4
	choose_t = 0.0
	_load()


func _load() -> void:
	var demo: Array = exam.step.get("demo", [])
	if seg < demo.size():
		path = demo[seg].path
		phase = "drive"
	else:
		phase = "idle"


func update(dt: float) -> void:
	var rig := exam.rig
	if exam.done:
		return
	if wait > 0.0:
		wait -= dt
		rig.throttle = 0.0
		rig.brake = 1.0
		return
	# checklist: tap the right answers one by one
	if exam.aligned:
		rig.throttle = 0.0
		rig.brake = 1.0
		choose_t += dt
		if choose_t > 0.6:
			choose_t = 0.0
			exam.choose(exam.checklist[exam.check_next])
		return
	if exam.step.type == "uncouple" and exam.pulled_away:
		rig.reverse = false
		rig.brake = 0.0
		rig.throttle = 0.5
		_steer_to(_pursuit_target(rig.pos, rig.th, 4.0), rig.pos, rig.th, rig.spec.L, dt)
		return
	if phase != "drive":
		rig.throttle = 0.0
		rig.brake = 1.0
		return
	var d: Dictionary = exam.step.demo[seg]
	var dir: int = d.dir
	rig.reverse = dir < 0
	# segment end conditions
	if _segment_done(d):
		seg += 1
		wait = 0.8
		_load()
		return
	var follow: String = d.get("follow", "tractor")
	if dir > 0 or not rig.coupled or follow == "tractor" and dir > 0:
		if dir > 0:
			var la: float = 3.0 + rig.spec.L * 0.5
			_steer_to(_pursuit_target(rig.pos, rig.th, la), rig.pos, rig.th, rig.spec.L, dt)
		else:
			# reversing without a trailer: pursue with the axle pointing backwards
			var back := rig.th + PI
			var la2 := 3.0
			var g := _pursuit_target(rig.pos, back, la2)
			var a := wrapf((g - rig.pos).angle() - back, -PI, PI)
			var k := 2.0 * sin(a) / la2
			# going backwards the tractor's own steering acts mirrored
			_steer_rate(-atan(k * rig.spec.L) / deg_to_rad(rig.spec.max_steer), dt)
	else:
		_back_trailer(dt)
	_speed(d, dir)


func _segment_done(d: Dictionary) -> bool:
	var rig := exam.rig
	match d.until:
		"finish":
			return false
		"A", "B":
			return exam.touched.has(d.until)
		"stop":
			return rig.pos.y >= d.stop
		"coupled":
			return false
		"zone":
			return false
	return false


func _speed(d: Dictionary, dir: int) -> void:
	var rig := exam.rig
	rig.brake = 0.0
	var target := 1.4 if dir > 0 else 0.7
	if exam.step.type == "couple":
		var e := exam.couple_error()
		target = clampf(e.along * 0.35, 0.12, 0.8)
		if e.along < 0.12:
			rig.throttle = 0.0
			rig.brake = 1.0
			return
	if exam.step.type == "uncouple":
		# stop with the whole rig inside the zone
		var z: PackedVector2Array = exam.step.zone
		var zone_far := z[2].y
		var front := rig.tractor_corners()[0].y
		var gap: float = zone_far - 0.8 - front
		if gap < 0.25:
			rig.throttle = 0.0
			rig.brake = 1.0
			return
		target = clampf(gap * 0.4, 0.2, 1.4)
	if d.until == "stop":
		var gap2: float = d.stop - rig.pos.y
		target = clampf(gap2 * 0.4, 0.25, target)
	var cur := absf(rig.v)
	rig.throttle = clampf((target - cur) * 2.0 + target / Rig.MAX_FWD, 0.0, 1.0)
	if cur > target + 0.3:
		rig.throttle = 0.0
		rig.brake = 0.5


func _back_trailer(dt: float) -> void:
	var rig := exam.rig
	var ax := rig.trailer_axle()
	var back := rig.phi + PI   # direction the trailer axle travels
	var D: float = rig.tspec.D
	var la := maxf(D * 0.9, 3.0)
	var g := _pursuit_target(ax, back, la)
	var a := wrapf((g - ax).angle() - back, -PI, PI)
	var kappa := 2.0 * sin(a) / la
	# wanted hitch angle for that trailer curvature (steady-state circle)
	var r := 1.0 / maxf(absf(kappa), 1e-4)
	var beta_ss := 0.0
	if absf(kappa) > 1e-4:
		var c: float = rig.spec.c
		var r1 := sqrt(maxf(r * r + D * D - c * c, 0.01))   # tractor rear axle radius
		beta_ss = atan2(D, r) + atan2(c, r1)
		beta_ss *= -signf(kappa)
	beta_ss = clampf(beta_ss, -deg_to_rad(60), deg_to_rad(60))
	var b := rig.beta()
	var tan_d: float = -rig.spec.L * kappa + 2.6 * (b - beta_ss)
	var want := atan(tan_d) / deg_to_rad(rig.spec.max_steer)
	_steer_rate(want, dt)


func _pursuit_target(p: Vector2, heading: float, la: float) -> Vector2:
	# closest point on the path, then walk la metres along it
	var best := 0
	var bd := INF
	var bt := 0.0
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var dd := p.distance_to(a + ab * t)
		if dd < bd:
			bd = dd
			best = i
			bt = t
	var left := la
	var cur := path[best].lerp(path[best + 1], bt)
	var i2 := best
	while i2 < path.size() - 1:
		var nxt := path[i2 + 1]
		var seg_len := cur.distance_to(nxt)
		if seg_len >= left:
			return cur + (nxt - cur).normalized() * left
		left -= seg_len
		cur = nxt
		i2 += 1
	var last := path[path.size() - 1]
	var dirv := (last - path[path.size() - 2]).normalized()
	return last + dirv * left


func _steer_to(g: Vector2, p: Vector2, heading: float, L: float, dt: float) -> void:
	var a := wrapf((g - p).angle() - heading, -PI, PI)
	var la := maxf(p.distance_to(g), 0.5)
	var d := atan(2.0 * L * sin(a) / la)
	_steer_rate(d / deg_to_rad(exam.rig.spec.max_steer), dt)


func _steer_rate(want: float, dt: float) -> void:
	var rig := exam.rig
	rig.steer = move_toward(rig.steer, clampf(want, -1.0, 1.0), 2.0 * dt)
