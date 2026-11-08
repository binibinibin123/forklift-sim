class_name Coach
extends RefCounted
## The in-car instructor: short situational advice as a caption and, when the
## device can, spoken aloud with the system's Korean voice (no audio files).
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
		for v in DisplayServer.tts_get_voices_for_language("ko"):
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
			say("jack", "너무 꺾였어요. 전진해서 펴세요", 6.0, "bad")
		elif beta > 45.0:
			say("bend", "많이 꺾이고 있어요. 핸들을 반대로 풀어 주세요", 8.0, "warn")
	if exam.step.type == "course":
		for c in exam.step.confirms:
			if exam.touched.has(c.id):
				continue
			var d: float = Exam._seg_dist(r.pos, c.a, c.b)
			if d < 6.0:
				say("confirm_" + c.id, "%s이 가까워요. 바퀴로 꼭 밟으세요" % c.label, 20.0)
		var rem := exam.remaining()
		if rem < 30.0 and rem > 28.0:
			say("time", "30초 남았어요", 60.0, "warn")
	elif exam.step.type == "couple" and not exam.aligned:
		var e := exam.couple_error()
		if e.along < 2.0 and e.along > 0.3 and absf(r.v) > 0.6:
			say("slow", "거의 닿았어요. 아주 천천히", 10.0, "warn")
		elif absf(e.side) > 0.6 and e.along < 5.0 and e.along > 0.5:
			say("side", "%s으로 치우쳤어요" % ("왼쪽" if e.side > 0 else "오른쪽"), 8.0)


func on_step(exam: Exam) -> void:
	reset()
	var s := exam.step
	match s.id:
		"crank":
			say("intro", "굴절코스예요. 바깥쪽으로 크게 돌면 뒷바퀴가 안쪽 선을 넘지 않아요", 1.0)
		"curve":
			say("intro", "곡선코스예요. 속도를 줄이고 핸들을 부드럽게 돌리세요", 1.0)
		"garage":
			say("intro", "방향전환이에요. 트레일러 후진은 핸들을 반대로, 조금씩", 1.0)
		"couple":
			say("intro", "연결이에요. 후진으로 일직선을 맞추고, 닿기 전에 멈추세요", 1.0)
		"uncouple":
			say("intro", "분리예요. 구역 안에 세우고 순서대로 작업하세요", 1.0)
		_:
			say("intro", s.get("coach", s.title + " 시작"), 1.0)
