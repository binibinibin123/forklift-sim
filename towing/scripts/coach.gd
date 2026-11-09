class_name Coach
extends RefCounted
## The in-car instructor: short situational advice as a caption and, when the
## device can, spoken aloud with the system voice for the app language (no audio files).
## Advice is rate-limited per topic so it never nags.

signal spoke(text: String, kind: String)

var voice_on := true
var _voice_id := ""
var _last := {}        # topic -> time
var _t := 0.0
var _tts_ok := false


func _init() -> void:
	_tts_ok = DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
	if _tts_ok:
		# the voice follows the app language; no matching voice = captions only
		for v in DisplayServer.tts_get_voices_for_language(Lang.current()):
			_voice_id = v
			break
		if _voice_id == "":
			_tts_ok = false


func tick(dt: float) -> void:
	_t += dt


## Says something once per `cooldown` seconds for the given topic.
func say(topic: String, text: String, cooldown := 8.0, kind := "info") -> bool:
	if _last.has(topic) and _t - float(_last[topic]) < cooldown:
		return false
	_last[topic] = _t
	spoke.emit(text, kind)
	if voice_on and _tts_ok:
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(text, _voice_id, 60, 1.0, 1.1)
	return true


func stop() -> void:
	if _tts_ok:
		DisplayServer.tts_stop()


func reset() -> void:
	_last.clear()
	stop()


## Looks at the rig and the exam step every simulation tick.
func watch(exam: Exam) -> void:
	if exam == null or exam.done:
		return
	var r := exam.rig
	var beta := absf(rad_to_deg(r.beta()))
	if r.coupled and r.reverse and absf(r.v) > 0.1:
		if beta > 70.0:
			say("jack", Lang.t("tow.coach.jack"), 6.0, "bad")
		elif beta > 45.0:
			say("bend", Lang.t("tow.coach.bend"), 8.0, "warn")
	if exam.step.type == "course":
		for c in exam.step.confirms:
			if exam.touched.has(c.id):
				continue
			var d: float = Exam._seg_dist(r.pos, c.a, c.b)
			if d < 6.0:
				say("confirm_" + c.id, Lang.t("tow.coach.confirm") % c.label, 20.0)
		var rem := exam.remaining()
		if rem < 30.0 and rem > 28.0:
			say("time", Lang.t("tow.coach.time"), 60.0, "warn")
	elif exam.step.type == "couple" and not exam.aligned:
		var e := exam.couple_error()
		if e.along < 2.0 and e.along > 0.3 and absf(r.v) > 0.6:
			say("slow", Lang.t("tow.coach.slow"), 10.0, "warn")
		elif absf(e.side) > 0.6 and e.along < 5.0 and e.along > 0.5:
			say("side", Lang.t("tow.coach.side") % (Lang.t("tow.coach.left") if e.side > 0 else Lang.t("tow.coach.right")), 8.0)


func on_step(exam: Exam) -> void:
	reset()
	var s := exam.step
	match s.id:
		"crank":
			say("intro", Lang.t("tow.coach.crank"), 1.0)
		"curve":
			say("intro", Lang.t("tow.coach.curve"), 1.0)
		"garage":
			say("intro", Lang.t("tow.coach.garage"), 1.0)
		"couple":
			say("intro", Lang.t("tow.coach.couple"), 1.0)
		"uncouple":
			say("intro", Lang.t("tow.coach.uncouple"), 1.0)
		_:
			say("intro", s.get("coach", s.title + Lang.t("tow.coach.start")), 1.0)
