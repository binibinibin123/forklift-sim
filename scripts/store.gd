class_name Store
extends RefCounted
## 기기 저장: 최고 점수, 설정, 해제 상태 캐시.

const PATH := "user://save.json"

var data := {
	"best": -1,          # 모의시험 최고 점수
	"runs": 0,
	"passes": 0,
	"sound": true,
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
