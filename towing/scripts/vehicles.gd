class_name VehicleView
extends Node3D
## 3D look of a Rig: tractor and towed unit built from simple shapes, moved
## every frame from the simulation. Ground (x, y) maps to world (x, 0, -y);
## a body's local +X points forward and local -Z is its left side, so
## rotation.y = heading.

var rig: Rig
var kind := ""
var tractor := Node3D.new()
var towed := Node3D.new()
var front_wheels: Array[Node3D] = []
var spin_wheels: Array[Node3D] = []
var towed_spin: Array[Node3D] = []
var landing_gear: Node3D
var underlift: Node3D
var mirror_l := Node3D.new()     # mirror camera mounts on the cab
var mirror_r := Node3D.new()
var driver_eye := Node3D.new()
var _mats := {}
var cur_layer := 1   # render layer for new parts: 2 = cab shell (hidden in the driver view), 4 = dashboard (driver view only)


func setup(r: Rig) -> void:
	rig = r
	kind = r.kind
	for c in get_children():
		c.queue_free()
	front_wheels.clear()
	spin_wheels.clear()
	towed_spin.clear()
	tractor = Node3D.new()
	towed = Node3D.new()
	mirror_l = Node3D.new()
	mirror_r = Node3D.new()
	driver_eye = Node3D.new()
	add_child(tractor)
	add_child(towed)
	match kind:
		"small":
			_truck(tractor, r.spec, r.spec.color, true)
			_caravan(towed, r.tspec)
		"wrecker":
			_wrecker(tractor, r.spec)
			_towed_truck(towed, r.tspec)
		"large":
			_tractor_unit(tractor, r.spec)
			_semi(towed, r.tspec)


func sync(parked: bool, parked_pos: Vector2, parked_th: float) -> void:
	tractor.position = Vector3(rig.pos.x, 0, -rig.pos.y)
	tractor.rotation.y = rig.th
	var d := rig.delta()
	for w in front_wheels:
		w.rotation.y = d
	var roll := -rig.odometer / 0.45
	for w in spin_wheels:
		w.rotation.z = roll
	towed.visible = rig.coupled or parked
	if rig.coupled:
		var h := rig.hitch()
		towed.position = Vector3(h.x, 0, -h.y)
		towed.rotation.y = rig.phi
		for w in towed_spin:
			w.rotation.z = roll
	elif parked:
		towed.position = Vector3(parked_pos.x, 0, -parked_pos.y)
		towed.rotation.y = parked_th
	if landing_gear:
		landing_gear.visible = not rig.coupled
	if underlift:
		# the towed car's nose rides up on the lift when coupled
		towed.get_child(0).rotation.z = asin(0.42 / rig.tspec.D) if rig.coupled else 0.0


# ---------------------------------------------------------------- materials

func mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [c.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rough := 0.7) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat(c, rough)
	mi.layers = cur_layer
	parent.add_child(mi)
	return mi


func cyl(parent: Node3D, r: float, h: float, pos: Vector3, c: Color, axis := "z") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 18
	mi.mesh = cm
	mi.position = pos
	if axis == "z":
		mi.rotation.x = PI / 2
	elif axis == "x":
		mi.rotation.z = PI / 2
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi


## A tyre on a pivot; returns the pivot (steer around Y, spin around Z).
func wheel(parent: Node3D, pos: Vector3, r: float, w: float, steer := false, spin_list: Array = []) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	var spin := Node3D.new()
	pivot.add_child(spin)
	cyl(spin, r, w, Vector3.ZERO, Color(0.08, 0.08, 0.09))
	cyl(spin, r * 0.55, w + 0.02, Vector3.ZERO, Color(0.75, 0.76, 0.78))
	box(spin, Vector3(r * 0.9, r * 0.18, w + 0.04), Vector3.ZERO, Color(0.45, 0.46, 0.48))  # hub mark shows rolling
	if steer:
		front_wheels.append(pivot)
	spin_list.append(spin)
	return pivot


func _wheels_for(parent: Node3D, xs: Array, track: float, r: float, w: float, steer: bool, spin_list: Array) -> void:
	for x in xs:
		for side in [-1, 1]:
			wheel(parent, Vector3(x, r, side * track * 0.5), r, w, steer, spin_list)


func _cab(parent: Node3D, spec: Dictionary, c: Color, height: float, front_x: float) -> void:
	var cl: float = spec.cab_len
	var w: float = spec.width
	var cx := front_x - cl * 0.5
	cur_layer = 2
	box(parent, Vector3(cl, height, w), Vector3(cx, 0.55 + height * 0.5, 0), c, 0.45)
	# windscreen and side windows
	var glass := Color(0.12, 0.18, 0.24)
	box(parent, Vector3(0.06, height * 0.42, w * 0.9), Vector3(front_x + 0.01, 0.55 + height * 0.68, 0), glass, 0.1)
	for side in [-1, 1]:
		box(parent, Vector3(cl * 0.5, height * 0.38, 0.04), Vector3(front_x - cl * 0.3, 0.55 + height * 0.68, side * (w * 0.5 + 0.005)), glass, 0.1)
	# bumper, lights
	box(parent, Vector3(0.18, 0.3, w), Vector3(front_x + 0.05, 0.55, 0), Color(0.2, 0.2, 0.22))
	for side in [-1, 1]:
		box(parent, Vector3(0.05, 0.14, 0.32), Vector3(front_x + 0.03, 0.85, side * (w * 0.5 - 0.25)), Color(1, 0.97, 0.85), 0.2)
	cur_layer = 4   # what the driver sees: dashboard, bonnet edge, A-pillars
	box(parent, Vector3(0.3, 0.08, w * 0.92), Vector3(front_x - 0.05, 0.55 + height * 0.08, 0), Color(0.16, 0.16, 0.18))
	for side in [-1, 1]:
		var pillar := box(parent, Vector3(0.08, height * 0.55, 0.08), Vector3(front_x - 0.12, 0.55 + height * 0.72, side * w * 0.46), c.darkened(0.3))
		pillar.rotation.z = deg_to_rad(18)
	box(parent, Vector3(cl * 0.9, 0.05, w * 0.95), Vector3(cx, 0.55 + height - 0.03, 0), Color(0.75, 0.75, 0.72))
	box(parent, Vector3(0.6, 0.06, w * 0.95), Vector3(front_x + 0.25, 0.55 + height * 0.3, 0), c)
	cur_layer = 1
	# mirrors on arms; the mirror cameras hang off these mounts
	for side in [-1, 1]:
		var mx := front_x - 0.35
		var mz: float = side * (w * 0.5 + 0.28)
		cur_layer = 2   # the housing would fill the driver view; the mirror image shows instead
		box(parent, Vector3(0.08, 0.36, 0.16), Vector3(mx, 0.55 + height * 0.62, mz), Color(0.1, 0.1, 0.1))
		cur_layer = 1
		var mount := mirror_l if side < 0 else mirror_r   # local -z is the left side
		mount.position = Vector3(mx - 0.05, 0.55 + height * 0.62, mz + side * 0.05)
		parent.add_child(mount)
	# Korean trucks are left-hand drive: driver on the left (local -z)
	driver_eye.position = Vector3(front_x - cl * 0.45, 0.55 + height * 0.62, -w * 0.22)
	parent.add_child(driver_eye)


# ---------------------------------------------------------------- vehicles

func _truck(p: Node3D, s: Dictionary, c: Color, with_hitch: bool) -> void:
	var front: float = s.L + s.front_oh
	var back: float = -s.rear_oh
	_cab(p, s, c, 1.25, front)
	# chassis and cargo bed
	box(p, Vector3(front - back - 0.3, 0.2, 0.8), Vector3((front + back) * 0.5, 0.5, 0), Color(0.15, 0.15, 0.16))
	var bed_front: float = front - s.cab_len - 0.08
	var bed_len := bed_front - back
	var bx := (bed_front + back) * 0.5
	box(p, Vector3(bed_len, 0.12, s.width), Vector3(bx, 0.78, 0), Color(0.55, 0.57, 0.6))
	for side in [-1, 1]:
		box(p, Vector3(bed_len, 0.38, 0.05), Vector3(bx, 1.03, side * (s.width * 0.5 - 0.02)), Color(0.72, 0.74, 0.77))
	box(p, Vector3(0.05, 0.38, s.width), Vector3(back + 0.02, 1.03, 0), Color(0.72, 0.74, 0.77))
	box(p, Vector3(0.05, 0.5, s.width), Vector3(bed_front, 1.09, 0), Color(0.72, 0.74, 0.77))
	for side in [-1, 1]:
		box(p, Vector3(0.05, 0.12, 0.25), Vector3(back - 0.01, 0.72, side * (s.width * 0.5 - 0.2)), Color(0.85, 0.05, 0.05), 0.3)
	_wheels_for(p, [s.L], s.track, 0.36, 0.22, true, spin_wheels)
	_wheels_for(p, [0.0], s.track, 0.36, 0.3, false, spin_wheels)
	if with_hitch:
		box(p, Vector3(s.c - s.rear_oh + 0.1, 0.1, 0.1), Vector3(-(s.c + s.rear_oh) * 0.5, 0.5, 0), Color(0.2, 0.2, 0.2))
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		ball.mesh = sm
		ball.position = Vector3(-s.c, 0.6, 0)
		ball.material_override = mat(Color(0.8, 0.8, 0.82), 0.3, 0.8)
		p.add_child(ball)


func _caravan(p: Node3D, t: Dictionary) -> void:
	var f: float = -t.front
	var b: float = -t.back
	var len := f - b
	var cx := (f + b) * 0.5
	var white := Color(0.94, 0.94, 0.92)
	box(p, Vector3(len, 1.9, t.width), Vector3(cx, 0.45 + 0.95 + 0.05, 0), white, 0.5)
	box(p, Vector3(len - 0.6, 0.12, t.width + 0.01), Vector3(cx, 1.1, 0), Color(0.2, 0.45, 0.75))   # stripe
	box(p, Vector3(1.0, 0.45, 0.02), Vector3(cx + 0.6, 1.65, t.width * 0.5 + 0.005), Color(0.15, 0.2, 0.25), 0.1)
	box(p, Vector3(0.6, 1.5, 0.02), Vector3(cx - 0.9, 1.2, t.width * 0.5 + 0.005), Color(0.82, 0.82, 0.8))   # door
	# A-frame drawbar to the coupler at the hitch (origin)
	for side in [-1, 1]:
		var a := Vector3(0, 0.6, 0)
		var bpt := Vector3(f, 0.55, side * 0.6)
		var mid := (a + bpt) * 0.5
		var bar := box(p, Vector3(a.distance_to(bpt), 0.08, 0.08), mid, Color(0.2, 0.2, 0.22))
		bar.rotation.y = -atan2(bpt.z - a.z, bpt.x - a.x)
	box(p, Vector3(0.2, 0.14, 0.14), Vector3(-0.05, 0.62, 0), Color(0.15, 0.15, 0.15))
	cyl(p, 0.06, 0.4, Vector3(f + 0.3, 0.3, 0), Color(0.3, 0.3, 0.3), "y")   # jockey wheel post
	box(p, Vector3(0.05, 0.12, 0.3), Vector3(b - 0.01, 0.75, t.width * 0.5 - 0.25), Color(0.85, 0.05, 0.05), 0.3)
	box(p, Vector3(0.05, 0.12, 0.3), Vector3(b - 0.01, 0.75, -t.width * 0.5 + 0.25), Color(0.85, 0.05, 0.05), 0.3)
	_wheels_for(p, [-t.D], t.track, 0.33, 0.2, false, towed_spin)


func _wrecker(p: Node3D, s: Dictionary) -> void:
	var front: float = s.L + s.front_oh
	var back: float = -s.rear_oh
	_cab(p, s, s.color, 1.45, front)
	box(p, Vector3(front - back - 0.2, 0.3, 0.95), Vector3((front + back) * 0.5, 0.65, 0), Color(0.15, 0.15, 0.16))
	var deck_front: float = front - s.cab_len - 0.1
	var dx := (deck_front + back) * 0.5
	box(p, Vector3(deck_front - back, 0.45, s.width), Vector3(dx, 1.05, 0), Color(0.3, 0.3, 0.33))
	# boom
	var boom := box(p, Vector3(3.6, 0.35, 0.4), Vector3(dx - 0.1, 1.75, 0), Color(0.95, 0.75, 0.1))
	boom.rotation.z = deg_to_rad(14)
	box(p, Vector3(0.3, 0.8, 0.3), Vector3(deck_front - 0.5, 1.6, 0), Color(0.2, 0.2, 0.2))
	# light bar
	box(p, Vector3(0.25, 0.12, s.width * 0.8), Vector3(front - 0.6, 2.06, 0), Color(1.0, 0.55, 0.0), 0.2)
	# underlift arm reaching back to the hitch point
	underlift = Node3D.new()
	p.add_child(underlift)
	box(underlift, Vector3(s.c - s.rear_oh + 0.4, 0.18, 0.3), Vector3(-(s.c + s.rear_oh) * 0.5 - 0.1, 0.55, 0), Color(0.95, 0.75, 0.1))
	box(underlift, Vector3(0.3, 0.12, 1.7), Vector3(-s.c, 0.5, 0), Color(0.2, 0.2, 0.22))
	_wheels_for(p, [s.L], s.track, 0.48, 0.3, true, spin_wheels)
	_wheels_for(p, [0.0], s.track, 0.48, 0.45, false, spin_wheels)


func _towed_truck(p: Node3D, t: Dictionary) -> void:
	# a 1-ton truck pointing forward; its front axle sits on the lift at the hitch
	var body := Node3D.new()   # pivots on its rear axle so the nose can be lifted
	body.position = Vector3(-t.D, 0, 0)
	p.add_child(body)
	var s := {"L": t.D, "front_oh": 0.9, "rear_oh": t.back - t.D, "width": t.width, "track": t.track, "cab_len": 1.9, "c": 0.0}
	var inner := Node3D.new()
	body.add_child(inner)
	var n0 := spin_wheels.size()
	var saved_eye := driver_eye
	var saved_l := mirror_l
	var saved_r := mirror_r
	driver_eye = Node3D.new()
	mirror_l = Node3D.new()
	mirror_r = Node3D.new()
	var fw := front_wheels.duplicate()
	_truck(inner, s, Color(0.9, 0.9, 0.92), false)
	front_wheels = fw   # the towed car's wheels do not follow our steering
	driver_eye = saved_eye
	mirror_l = saved_l
	mirror_r = saved_r
	while spin_wheels.size() > n0:
		towed_spin.append(spin_wheels.pop_back())


func _tractor_unit(p: Node3D, s: Dictionary) -> void:
	var front: float = s.L + s.front_oh
	var back: float = -s.rear_oh - s.rear_tandem * 0.5
	_cab(p, s, s.color, 2.0, front)
	box(p, Vector3(0.7, 0.9, s.width), Vector3(front - s.cab_len - 0.35, 1.4, 0), s.color.darkened(0.25), 0.5)   # sleeper
	box(p, Vector3(front - back, 0.3, 0.95), Vector3((front + back) * 0.5, 0.75, 0), Color(0.15, 0.15, 0.16))
	cyl(p, 0.7, 0.12, Vector3(-s.c, 1.08, 0), Color(0.12, 0.12, 0.12), "y")   # fifth wheel
	for side in [-1, 1]:
		cyl(p, 0.12, 1.4, Vector3(front - s.cab_len - 0.2, 2.2, side * (s.width * 0.5 - 0.15)), Color(0.75, 0.75, 0.78), "y")   # stacks
		box(p, Vector3(1.0, 0.45, 0.5), Vector3(s.L * 0.45, 0.75, side * (s.width * 0.5 - 0.25)), Color(0.7, 0.7, 0.72), 0.3)   # tanks
	_wheels_for(p, [s.L], s.track, 0.52, 0.32, true, spin_wheels)
	_wheels_for(p, [s.rear_tandem * 0.5, -s.rear_tandem * 0.5], s.track, 0.52, 0.55, false, spin_wheels)


func _semi(p: Node3D, t: Dictionary) -> void:
	var f: float = -t.front
	var b: float = -t.back
	var len := f - b
	var cx := (f + b) * 0.5
	var h := 2.6
	box(p, Vector3(len, h, t.width), Vector3(cx, 1.25 + h * 0.5, 0), Color(0.22, 0.42, 0.58), 0.6)
	for i in int(len / 0.6):   # corrugation ribs
		box(p, Vector3(0.08, h - 0.1, t.width + 0.04), Vector3(b + 0.3 + i * 0.6, 1.25 + h * 0.5, 0), Color(0.19, 0.37, 0.52), 0.6)
	box(p, Vector3(len, 0.25, 1.0), Vector3(cx, 1.12, 0), Color(0.12, 0.12, 0.13))
	box(p, Vector3(0.06, h, t.width), Vector3(b - 0.02, 1.25 + h * 0.5, 0), Color(0.3, 0.32, 0.34))
	for side in [-1, 1]:
		box(p, Vector3(0.05, 0.15, 0.3), Vector3(b - 0.06, 1.0, side * (t.width * 0.5 - 0.25)), Color(0.85, 0.05, 0.05), 0.3)
	cyl(p, 0.06, 0.2, Vector3(0, 1.0, 0), Color(0.6, 0.6, 0.6), "y")   # kingpin
	landing_gear = Node3D.new()
	p.add_child(landing_gear)
	for side in [-1, 1]:
		box(landing_gear, Vector3(0.14, 1.0, 0.14), Vector3(-2.0, 0.6, side * 0.8), Color(0.2, 0.2, 0.2))
		box(landing_gear, Vector3(0.35, 0.08, 0.3), Vector3(-2.0, 0.08, side * 0.8), Color(0.2, 0.2, 0.2))
	_wheels_for(p, [-t.D + t.tandem * 0.5, -t.D - t.tandem * 0.5], t.track, 0.5, 0.55, false, towed_spin)
