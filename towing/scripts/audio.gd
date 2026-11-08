class_name TowSfx
extends Node
## Tiny sound-effect manager.  Add one instance to the tree (e.g. as an
## autoload) and call:
##   play("step_done")                      one-shot, pooled (<= 8 voices)
##   engine(true, rpm)                      looping diesel; rpm 0..1
##   beep_reverse(true)                     repeating reversing alarm
##   set_enabled(false)                     mute the Master bus
## Streams are loaded lazily from res://towing/assets/sfx/<name>.wav.  Everything is
## safe with the Dummy audio driver and with missing files (a warning is
## pushed once per missing name and the call is ignored).

const DIR := "res://towing/assets/sfx/"
const MAX_VOICES := 8
const BEEP_PERIOD := 1.0
const ENGINE_PITCH_MIN := 0.8
const ENGINE_PITCH_MAX := 1.8
const ENGINE_DB_MIN := -14.0
const ENGINE_DB_MAX := -4.0
const ENGINE_SMOOTH := 6.0  # 1/s, exponential smoothing rate

var _streams := {}  # name -> AudioStream or null (null = known missing)
var _pool: Array[AudioStreamPlayer] = []
var _engine: AudioStreamPlayer
var _engine_on := false
var _engine_pitch_target := ENGINE_PITCH_MIN
var _engine_db_target := ENGINE_DB_MIN
var _beep_on := false
var _beep_t := 0.0


func _process(delta: float) -> void:
	if _engine != null:
		var k := 1.0 - exp(-ENGINE_SMOOTH * delta)
		var db_target := _engine_db_target if _engine_on else -60.0
		_engine.pitch_scale = lerpf(_engine.pitch_scale, _engine_pitch_target, k)
		_engine.volume_db = lerpf(_engine.volume_db, db_target, k)
		if not _engine_on and _engine.playing and _engine.volume_db < -55.0:
			_engine.stop()
	if _beep_on:
		_beep_t += delta
		if _beep_t >= BEEP_PERIOD:
			_beep_t -= BEEP_PERIOD
			play("reverse_beep", -3.0)


## Play a one-shot sound by file name (without ".wav").
func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var s := stream(name)
	if s == null or not is_inside_tree():
		return
	var p := _voice()
	if p == null:
		return
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.01, pitch)
	p.play()


## Drive the looping engine sound.  rpm 0..1 -> pitch 0.8..1.8, -14..-4 dB.
func engine(on: bool, rpm: float) -> void:
	rpm = clampf(rpm, 0.0, 1.0)
	_engine_pitch_target = lerpf(ENGINE_PITCH_MIN, ENGINE_PITCH_MAX, rpm)
	_engine_db_target = lerpf(ENGINE_DB_MIN, ENGINE_DB_MAX, rpm)
	if on and not _engine_on:
		var s := stream("engine_loop")
		if s == null or not is_inside_tree():
			return
		_ensure_engine()
		_engine.stream = s
		_engine.volume_db = -60.0
		_engine.pitch_scale = _engine_pitch_target
		_engine.play()
	elif not on and _engine_on and not is_inside_tree() and _engine != null:
		_engine.stop()  # no _process to fade it out
	_engine_on = on


## Mute / unmute everything through the Master bus.
func set_enabled(on: bool) -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, not on)


func is_enabled() -> bool:
	var idx := AudioServer.get_bus_index("Master")
	return idx < 0 or not AudioServer.is_bus_mute(idx)


## Repeat the reversing alarm every second while on.
func beep_reverse(on: bool) -> void:
	if on and not _beep_on:
		_beep_t = 0.0
		play("reverse_beep", -3.0)
	_beep_on = on


## Lazily load a stream; sets up looping on the engine sound.
func stream(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path := DIR + name + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null:
		push_warning("TowSfx: missing sound '%s' (%s)" % [name, path])
	elif name == "engine_loop" and s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(round(w.get_length() * w.mix_rate))
	_streams[name] = s
	return s


func _ensure_engine() -> void:
	if _engine == null:
		_engine = AudioStreamPlayer.new()
		_engine.name = "Engine"
		_engine.bus = "Master"
		add_child(_engine)


func _voice() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	if _pool.size() < MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % _pool.size()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
		return p
	# all voices busy: steal the oldest one (round robin)
	var p: AudioStreamPlayer = _pool.pop_front()
	_pool.append(p)
	p.stop()
	return p
