class_name Rig
extends RefCounted
## Kinematic towing vehicle: a steered tractor (bicycle model on its rear axle)
## and an optional towed unit hinged at the hitch. All in metres on the ground
## plane, x/y as in Vector2; heading 0 points along +x, counter-clockwise.
##
## Tractor: x' = v cos(th), y' = v sin(th), th' = v tan(delta) / L
## Hitch:   c metres behind the rear axle (negative = ahead of it)
## Trailer: phi' = (v sin(beta) - c th' cos(beta)) / D, beta = th - phi

const SPECS := {
	"small": {   # 1-ton truck + small trailer over 750 kg (소형견인)
		"name": "tow.spec.small",
		"L": 2.64, "width": 1.74, "front_oh": 1.2, "rear_oh": 1.3, "track": 1.48,
		"c": 1.45, "max_steer": 36.0, "rear_tandem": 0.0, "cab_len": 1.9, "color": Color(0.16, 0.38, 0.78),
		"trailer": {"D": 3.3, "width": 2.0, "front": 1.0, "back": 5.1, "track": 1.72, "tandem": 0.0, "lifted_front": false, "kind": "caravan"},
	},
	"wrecker": {   # 5-ton wrecker lifting a 1-ton truck by its front wheels (구난)
		"name": "tow.spec.wrecker",
		"L": 4.0, "width": 2.3, "front_oh": 1.35, "rear_oh": 2.05, "track": 1.85,
		"c": 2.7, "max_steer": 38.0, "rear_tandem": 0.0, "cab_len": 2.1, "color": Color(0.92, 0.55, 0.1),
		"trailer": {"D": 2.64, "width": 1.74, "front": -1.2, "back": 3.95, "track": 1.48, "tandem": 0.0, "lifted_front": true, "kind": "truck"},
	},
	"large": {   # tractor + 40 ft two-axle semi-trailer (대형견인)
		"name": "tow.spec.large",
		"L": 3.9, "width": 2.49, "front_oh": 1.45, "rear_oh": 1.05, "track": 1.9,
		"c": 0.0, "max_steer": 40.0, "rear_tandem": 1.3, "cab_len": 2.3, "color": Color(0.8, 0.12, 0.12),
		"trailer": {"D": 8.8, "width": 2.49, "front": -1.2, "back": 11.0, "track": 1.9, "tandem": 1.3, "lifted_front": false, "kind": "box"},
	},
}

const MAX_FWD := 3.0      # m/s (~11 km/h), exam yards are slow
const MAX_REV := 1.6
const ACCEL := 1.4
const COAST := 0.8
const BRAKE := 4.5
const STEER_RATE := 0.75  # steering input units per second at full wheel speed (for the autopilot)
const JACKKNIFE := deg_to_rad(88.0)   # coupling hits the cab past this

var kind := "small"
var spec: Dictionary
var tspec: Dictionary     # towed unit spec, empty when uncoupled
var coupled := true

var pos := Vector2.ZERO   # tractor rear axle centre
var th := 0.0             # tractor heading
var phi := 0.0            # trailer heading
var v := 0.0              # signed speed of the rear axle
var steer := 0.0          # -1..1, positive turns left (counter-clockwise)
var throttle := 0.0       # 0..1
var brake := 0.0          # 0..1
var reverse := false      # gear: false = D, true = R
var odometer := 0.0
var jackknifed := false


func _init(k: String = "small") -> void:
	kind = k
	spec = SPECS[k]
	tspec = spec.trailer
	coupled = true


func copy() -> Rig:
	var r := Rig.new(kind)
	r.coupled = coupled
	r.pos = pos
	r.th = th
	r.phi = phi
	r.v = v
	r.steer = steer
	r.reverse = reverse
	return r


func set_pose(p: Vector2, heading: float, trailer_heading: float = INF) -> void:
	pos = p
	th = heading
	phi = heading if trailer_heading == INF else trailer_heading
	v = 0.0
	jackknifed = false


func uncouple() -> void:
	coupled = false


func couple(trailer_heading: float) -> void:
	coupled = true
	phi = trailer_heading


func delta() -> float:
	return steer * deg_to_rad(spec.max_steer)


func hitch() -> Vector2:
	return pos - spec.c * Vector2(cos(th), sin(th))


func trailer_axle() -> Vector2:
	return hitch() - tspec.D * Vector2(cos(phi), sin(phi))


func beta() -> float:
	return wrapf(th - phi, -PI, PI)


func speed_kmh() -> float:
	return absf(v) * 3.6


func step(dt: float) -> void:
	# Speed: pedal accelerates in the chosen gear; brake and coasting slow down.
	var target_dir := -1.0 if reverse else 1.0
	var vmax := MAX_REV if reverse else MAX_FWD
	if brake > 0.01:
		v = move_toward(v, 0.0, BRAKE * brake * dt)
	elif throttle > 0.01:
		if v * target_dir < -0.01:   # moving against the gear: stop first
			v = move_toward(v, 0.0, BRAKE * dt)
		else:
			v = move_toward(v, target_dir * vmax * throttle, ACCEL * dt)
	else:
		v = move_toward(v, 0.0, COAST * dt)
	var n := 4
	var h := dt / n
	for i in n:
		_integrate(h)


func _integrate(h: float) -> void:
	var d := delta()
	var thd: float = v * tan(d) / spec.L
	if coupled:
		var b := th - phi
		var phid: float = (v * sin(b) - spec.c * thd * cos(b)) / tspec.D
		phi += phid * h
	pos += v * Vector2(cos(th), sin(th)) * h
	th += thd * h
	odometer += absf(v) * h
	if coupled and absf(beta()) > JACKKNIFE:
		jackknifed = true
		# the coupling stops the hinge from folding further
		phi = th - signf(beta()) * JACKKNIFE


## Ground contact points of every tyre on the ground, with labels.
## Returns Array of {p: Vector2, unit: "tractor"/"trailer", axle: "front"/"rear"}
func wheels() -> Array:
	var out := []
	var f := Vector2(cos(th), sin(th))
	var l := Vector2(-f.y, f.x)
	var ht: float = spec.track * 0.5
	var front: Vector2 = pos + f * spec.L
	out.append({"p": front + l * ht, "unit": "tractor", "axle": "front", "side": "L"})
	out.append({"p": front - l * ht, "unit": "tractor", "axle": "front", "side": "R"})
	for o in _axle_offsets(spec.rear_tandem):
		var r: Vector2 = pos + f * o
		out.append({"p": r + l * ht, "unit": "tractor", "axle": "rear", "side": "L"})
		out.append({"p": r - l * ht, "unit": "tractor", "axle": "rear", "side": "R"})
	if coupled:
		var tf := Vector2(cos(phi), sin(phi))
		var tl := Vector2(-tf.y, tf.x)
		var tt: float = tspec.track * 0.5
		var ax := trailer_axle()
		for o in _axle_offsets(tspec.tandem):
			var r2: Vector2 = ax + tf * o
			out.append({"p": r2 + tl * tt, "unit": "trailer", "axle": "rear", "side": "L"})
			out.append({"p": r2 - tl * tt, "unit": "trailer", "axle": "rear", "side": "R"})
	return out


func _axle_offsets(tandem: float) -> Array:
	if tandem <= 0.0:
		return [0.0]
	return [tandem * 0.5, -tandem * 0.5]


## Body outline corners (for drawing and off-course checks).
func tractor_corners() -> PackedVector2Array:
	var f := Vector2(cos(th), sin(th))
	var l := Vector2(-f.y, f.x)
	var w: float = spec.width * 0.5
	var a: Vector2 = pos + f * (spec.L + spec.front_oh)
	var b: Vector2 = pos - f * spec.rear_oh
	return PackedVector2Array([a + l * w, a - l * w, b - l * w, b + l * w])


func trailer_corners() -> PackedVector2Array:
	var f := Vector2(cos(phi), sin(phi))
	var l := Vector2(-f.y, f.x)
	var w: float = tspec.width * 0.5
	var hp := hitch()
	var a: Vector2 = hp - f * tspec.front
	var b: Vector2 = hp - f * tspec.back
	return PackedVector2Array([a + l * w, a - l * w, b - l * w, b + l * w])
