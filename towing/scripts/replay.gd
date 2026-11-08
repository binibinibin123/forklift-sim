class_name Replay
extends RefCounted
## Records a run (rig poses at 10 Hz plus the moments something was deducted)
## so the result screen can play it back and jump to each mistake.

const RATE := 0.1

var frames: Array = []     # [{t, pos, th, phi, coupled, parked, ppos, pth, steer, v, rev}]
var marks: Array = []      # [{t, text, points}]
var duration := 0.0
var _acc := RATE


func clear() -> void:
	frames.clear()
	marks.clear()
	duration = 0.0
	_acc = RATE


func sample(exam: Exam, dt: float) -> void:
	_acc += dt
	duration = exam.t_total
	if _acc < RATE:
		return
	_acc = 0.0
	var r := exam.rig
	frames.append({"t": exam.t_total, "pos": r.pos, "th": r.th, "phi": r.phi, "coupled": r.coupled,
		"parked": exam.trailer_parked, "ppos": exam.trailer_pos, "pth": exam.trailer_th,
		"steer": r.steer, "v": r.v, "rev": r.reverse, "step": exam.index})


func mark(exam: Exam, text: String, points: int) -> void:
	marks.append({"t": exam.t_total, "text": text, "points": points})


func frame_at(t: float) -> Dictionary:
	if frames.is_empty():
		return {}
	var lo := 0
	var hi := frames.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if frames[mid].t < t:
			lo = mid + 1
		else:
			hi = mid
	var b: Dictionary = frames[lo]
	if lo == 0:
		return b
	var a: Dictionary = frames[lo - 1]
	var span: float = maxf(b.t - a.t, 1e-4)
	var k := clampf((t - a.t) / span, 0.0, 1.0)
	if a.coupled != b.coupled or a.parked != b.parked or a.step != b.step:
		return b
	return {"t": t, "pos": a.pos.lerp(b.pos, k), "th": lerp_angle(a.th, b.th, k), "phi": lerp_angle(a.phi, b.phi, k),
		"coupled": b.coupled, "parked": b.parked, "ppos": b.ppos, "pth": b.pth,
		"steer": lerpf(a.steer, b.steer, k), "v": lerpf(a.v, b.v, k), "rev": b.rev, "step": b.step}


## Puts a recorded frame onto a rig (the exam's own rig, after the run ended).
static func apply(f: Dictionary, rig: Rig) -> void:
	if f.is_empty():
		return
	rig.pos = f.pos
	rig.th = f.th
	rig.phi = f.phi
	rig.coupled = f.coupled
	rig.steer = f.steer
	rig.v = f.v
	rig.reverse = f.rev
