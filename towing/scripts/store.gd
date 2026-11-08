class_name TowStore
extends RefCounted
## Local save: best scores, run history, settings, badges, cached unlock.

const PATH := "user://towing.json"
const HISTORY_MAX := 200

var data := {
	"best": {},          # "small/exam" -> best score
	"stars": {},         # "small/crank" -> 0..3
	"runs": 0,           # finished runs
	"passes": 0,
	"drive_time": 0.0,   # seconds spent driving
	"history": [],       # newest last: {d, key, score, ok, t, dq}
	"badges": {},        # id -> unix time earned
	"onboarded": false,
	"settings": {
		"camera": "chase",
		"guide": true,
		"sound": true,
		"voice": true,
		"haptic": true,
		"sens": 1.0,       # steering sensitivity
		"lefty": false,    # wheel on the right, pedals on the left
		"minimap": true,
	},
	"unlocked": false,   # cached 전체 해제; StoreKit is the source of truth
}


func load_data() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in parsed:
			if k == "settings" and parsed[k] is Dictionary:
				for sk in parsed[k]:
					data.settings[sk] = parsed[k][sk]
			else:
				data[k] = parsed[k]
	# the old save kept camera/guide at the top level
	if data.has("camera"):
		data.settings.camera = data.camera
	if data.has("guide"):
		data.settings.guide = data.guide


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func setting(key: String, default = null):
	return data.settings.get(key, default)


func set_setting(key: String, value) -> void:
	data.settings[key] = value
	save()


## Stars for one run: 3 = no deductions, 2 = passed, 1 = finished, 0 = disqualified.
static func stars_for(score: int, passed: bool, disqualified: bool) -> int:
	if disqualified:
		return 0
	if score >= 100:
		return 3
	return 2 if passed else 1


## Records a finished run. Returns {better: bool, stars: int, best: int}.
func record(key: String, score: int, passed: bool, seconds: float, disqualified: String = "") -> Dictionary:
	data.runs = int(data.runs) + 1
	if passed:
		data.passes = int(data.passes) + 1
	data.drive_time = float(data.drive_time) + seconds
	var best := int(data.best.get(key, -1))
	var better := score > best
	if better:
		data.best[key] = score
	var st := stars_for(score, passed, disqualified != "")
	if st > int(data.stars.get(key, 0)):
		data.stars[key] = st
	var hist: Array = data.history
	hist.append({"d": Time.get_unix_time_from_system(), "key": key, "score": score, "ok": passed, "t": int(seconds), "dq": disqualified})
	while hist.size() > HISTORY_MAX:
		hist.pop_front()
	save()
	return {"better": better, "stars": st, "best": int(data.best.get(key, score))}


func earn_badge(id: String) -> bool:
	if data.badges.has(id):
		return false
	data.badges[id] = Time.get_unix_time_from_system()
	save()
	return true


func stars(key: String) -> int:
	return int(data.stars.get(key, 0))


func best(key: String) -> int:
	return int(data.best.get(key, -1))


func pass_rate() -> float:
	var r := int(data.runs)
	return 0.0 if r == 0 else float(data.passes) / r
