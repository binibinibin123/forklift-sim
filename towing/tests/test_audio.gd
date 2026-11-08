extends SceneTree
## Headless: every sound effect must exist and load; the TowSfx manager must not
## crash with the Dummy audio driver.
## godot --headless --path . -s tests/test_audio.gd

const NAMES := [
	"engine_loop", "reverse_beep", "line_touch", "disqualify", "step_done",
	"pass", "fail", "ui_tap", "ui_confirm", "air_brake", "clunk", "horn",
	"gear", "tyre_scrub",
]

var fails := 0


func _init() -> void:
	var total := 0
	for n in NAMES:
		var path := "res://towing/assets/sfx/%s.wav" % n
		var exists := ResourceLoader.exists(path)
		_check(exists, "%s exists" % n)
		if not exists:
			continue
		var s := load(path) as AudioStreamWAV
		_check(s != null, "%s loads as AudioStreamWAV" % n)
		if s == null:
			continue
		var size := 0
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			size = f.get_length()
		total += size
		var frames := int(round(s.get_length() * s.mix_rate))
		print("  %-13s %5.2f s  %6d bytes  %d Hz  %d frames" % [n, s.get_length(), size, s.mix_rate, frames])
		_check(s.get_length() > 0.05, "%s has length" % n)
		_check(s.mix_rate == 22050, "%s is 22050 Hz" % n)
	print("  total %d bytes" % total)
	_check(total < 2_500_000, "folder under 2.5 MB")
	# Exercise the manager with the Dummy driver.
	var sfx := TowSfx.new()
	root.add_child(sfx)
	var eng := sfx.stream("engine_loop") as AudioStreamWAV
	_check(eng != null and eng.loop_mode == AudioStreamWAV.LOOP_FORWARD, "engine_loop loops forward")
	_check(eng != null and eng.loop_end == int(round(eng.get_length() * eng.mix_rate)), "engine_loop loop_end at end")
	for n in NAMES:
		sfx.play(n, -6.0, 1.1)
	sfx.engine(true, 0.5)
	sfx.engine(true, 1.0)
	sfx.engine(false, 0.0)
	sfx.beep_reverse(true)
	sfx.beep_reverse(false)
	sfx.set_enabled(false)
	_check(not sfx.is_enabled(), "master muted")
	sfx.set_enabled(true)
	_check(sfx.is_enabled(), "master unmuted")
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)
