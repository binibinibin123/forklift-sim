class_name Sfx
extends Node
## 코드로 합성한 소리: 엔진 루프, 후진 경고음, 유압음, 경음기, 호루라기, 부저, 차임. 햅틱 포함.

var enabled := true
var haptics := true
var _p := {}          # name -> AudioStreamPlayer
var _rpm := 0.0


func _ready() -> void:
	_add("engine", _engine_loop(), -14.0, true)
	_add("beeper", _beeper_loop(), -12.0, true)
	_add("hydro", _hydro_loop(), -18.0, true)
	_add("horn", _tone([[420.0, 0.55]], 0.5, false, true, 2.0), -6.0)
	_add("whistle", _tone([[2900.0, 0.12], [0.0, 0.05], [2900.0, 0.5]], 0.35, true), -8.0)
	_add("buzzer", _tone([[220.0, 0.45]], 0.3, false, true), -6.0)
	_add("chime", _tone([[880.0, 0.14], [1175.0, 0.3]], 0.3), -8.0)
	_add("click", _tone([[1500.0, 0.03]], 0.2), -12.0)
	_add("thud", _tone([[70.0, 0.12]], 0.6, false, true), -6.0)


func _add(name: String, w: AudioStreamWAV, db: float, loop := false) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = w
	p.volume_db = db
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2
	add_child(p)
	_p[name] = p


func play(name: String) -> void:
	if enabled and _p.has(name):
		_p[name].play()


func buzz(ms: int) -> void:
	if haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


## 매 프레임: 엔진·경고음·유압음을 상태에 맞춰 조절
func update(sim: Sim, running: bool, dt: float, lift_in: float, tilt_in: float, throttle: float) -> void:
	var eng: AudioStreamPlayer = _p.engine
	if not enabled or not running:
		for k in ["engine", "beeper", "hydro"]:
			if _p[k].playing:
				_p[k].stop()
		return
	if not eng.playing:
		eng.play()
	var want := 0.25 + 0.55 * throttle + 0.25 * absf(sim.speed) / Sim.MAX_FWD + (0.25 if absf(lift_in) + absf(tilt_in) > 0 else 0.0)
	_rpm = move_toward(_rpm, clampf(want, 0.25, 1.3), dt * 1.6)
	eng.pitch_scale = 0.75 + _rpm * 0.7
	eng.volume_db = -16.0 + _rpm * 8.0
	var beep: AudioStreamPlayer = _p.beeper
	var reversing := sim.gear == -1 and not sim.park_brake
	if reversing and not beep.playing:
		beep.play()
	elif not reversing and beep.playing:
		beep.stop()
	var hyd: AudioStreamPlayer = _p.hydro
	var hydro := absf(lift_in) + absf(tilt_in) > 0.05
	if hydro and not hyd.playing:
		hyd.play()
	elif not hydro and hyd.playing:
		hyd.stop()


func stop_all() -> void:
	for k in _p:
		_p[k].stop()


# ---------- 합성 ----------
const RATE := 22050


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var x := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = x & 0xff
		data[i * 2 + 1] = (x >> 8) & 0xff
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


static func _engine_loop() -> AudioStreamWAV:
	var n := RATE  # 1초, 기본 주파수 정수배라 매끄럽게 이어짐
	var s := PackedFloat32Array()
	s.resize(n)
	var f := 36.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		v += sin(TAU * f * t) * 0.5
		v += sin(TAU * f * 2 * t) * 0.3
		v += sin(TAU * f * 3 * t + 0.4) * 0.18
		v += sin(TAU * f * 4.0 * t) * 0.1
		v += signf(sin(TAU * f * t)) * 0.08           # 디젤 '탁탁' 느낌
		var noise := rng.randf_range(-1, 1)
		lp += (noise - lp) * 0.08
		v += lp * 0.25
		s[i] = v * 0.5
	return _wav(s)


static func _beeper_loop() -> AudioStreamWAV:
	var n := int(RATE * 0.8)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var on := t < 0.32
		var env := minf(1.0, minf(i / 150.0, (int(RATE * 0.32) - i) / 300.0)) if on else 0.0
		s[i] = sin(TAU * 1250.0 * t) * 0.6 * maxf(env, 0.0)
	return _wav(s)


static func _hydro_loop() -> AudioStreamWAV:
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1, 1)
		lp += (noise - lp) * 0.3
		s[i] = (sin(TAU * 95.0 * t) * 0.35 + sin(TAU * 190.0 * t) * 0.2 + lp * 0.5) * 0.5
	return _wav(s)


static func _tone(parts: Array, vol: float, trill := false, square := false, harm := 0.0) -> AudioStreamWAV:
	var s := PackedFloat32Array()
	for part in parts:
		var f: float = part[0]
		var n := int(RATE * float(part[1]))
		for i in n:
			var t := float(i) / RATE
			var env := minf(1.0, minf(i / 200.0, (n - i) / 400.0))
			var ff := f * (1.0 + (0.03 * sin(TAU * 28.0 * t) if trill else 0.0))
			var v := sin(TAU * ff * t)
			if harm > 0:
				v = (sin(TAU * ff * t) + sin(TAU * ff * 1.5 * t) * 0.6 + sin(TAU * ff * 2.0 * t) * 0.4) / harm
			if square:
				v = signf(v) * 0.6
			if f <= 0.0:
				v = 0.0
			s.append(v * env * vol)
	return _wav(s)
