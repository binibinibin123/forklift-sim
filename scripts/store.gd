class_name Store
extends RefCounted
## 기기 저장: 최고 점수, 기록, 설정, 해제 상태 캐시.

const PATH := "user://save.json"
const HISTORY_MAX := 40

var data := {
	"best": -1,          # 모의시험 최고 점수
	"runs": 0,
	"passes": 0,
	"sound": true,
	"haptics": true,
	"steer_sens": 1.0,   # 핸들 감도 0.6~1.4
	"cam": 0,            # 기본 시점
	"history": [],       # {ts, mode, score, load, unload, pass, time, faults}
	"drills": {},        # id -> {done, best_time, clean}
	"unlocked": false,   # 전체 해제 캐시; StoreKit이 기준
}


func load_data() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in parsed:
			data[k] = parsed[k]


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func add_history(e: Dictionary) -> void:
	var h: Array = data.history
	h.push_front(e)
	while h.size() > HISTORY_MAX:
		h.pop_back()
	save()


func drill_done(id: String, t: float, clean: bool) -> void:
	var d: Dictionary = data.drills
	var cur: Dictionary = d.get(id, {done = 0, best_time = -1.0, clean = 0})
	cur.done = int(cur.done) + 1
	if clean:
		cur.clean = int(cur.clean) + 1
		if float(cur.best_time) < 0 or t < float(cur.best_time):
			cur.best_time = t
	d[id] = cur
	save()
