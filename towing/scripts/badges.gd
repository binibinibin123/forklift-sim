class_name Badges
extends RefCounted
## Achievements earned from the save data. Checked after every finished run.

const ALL := [
	{"id": "first_run", "title": "첫 주행", "desc": "코스를 한 번 끝까지 달렸어요", "icon": "🚚"},
	{"id": "first_pass", "title": "첫 합격", "desc": "모의시험에 처음 합격했어요", "icon": "✅"},
	{"id": "perfect", "title": "무감점", "desc": "감점 없이 100점으로 통과", "icon": "💯"},
	{"id": "small_pass", "title": "소형견인", "desc": "소형견인 모의시험 합격", "icon": "🚐"},
	{"id": "wrecker_pass", "title": "구난", "desc": "구난 모의시험 합격", "icon": "🔧"},
	{"id": "large_pass", "title": "대형견인", "desc": "대형견인 모의시험 합격", "icon": "🚛"},
	{"id": "triple", "title": "1종 특수 마스터", "desc": "세 면허 모의시험을 모두 합격", "icon": "🏆"},
	{"id": "drills", "title": "훈련장 졸업", "desc": "후진 훈련 3종을 모두 통과", "icon": "🎓"},
	{"id": "ten_runs", "title": "연습벌레", "desc": "10번 주행", "icon": "🔟"},
	{"id": "fifty_runs", "title": "베테랑", "desc": "50번 주행", "icon": "🎖"},
	{"id": "hour", "title": "한 시간", "desc": "총 1시간 연습", "icon": "⏱"},
	{"id": "no_jackknife", "title": "꺾이지 않는", "desc": "대형견인 방향전환을 감점 없이 통과", "icon": "📐"},
]


static func info(id: String) -> Dictionary:
	for b in ALL:
		if b.id == id:
			return b
	return {}


## Returns the ids newly earned by this run.
static func check(store: TowStore, key: String, score: int, passed: bool, disqualified: String) -> Array:
	var got := []
	var d := store.data
	var parts := key.split("/")
	var kind: String = parts[0]
	var id: String = parts[1]
	var want := ["first_run"]
	if passed and id == "exam":
		want.append("first_pass")
		want.append(kind + "_pass")
		if int(d.best.get("small/exam", -1)) >= Exam.PASS and int(d.best.get("wrecker/exam", -1)) >= Exam.PASS and int(d.best.get("large/exam", -1)) >= Exam.PASS:
			want.append("triple")
	if passed and score >= 100 and disqualified == "":
		want.append("perfect")
		if kind == "large" and id in ["garage", "exam"]:
			want.append("no_jackknife")
	if int(d.runs) >= 10:
		want.append("ten_runs")
	if int(d.runs) >= 50:
		want.append("fifty_runs")
	if float(d.drive_time) >= 3600.0:
		want.append("hour")
	var all_drills := true
	for drill in TowDrills.LIST:
		if int(d.best.get("small/" + drill.id, -1)) < Exam.PASS:
			all_drills = false
	if all_drills:
		want.append("drills")
	for w in want:
		if store.earn_badge(w):
			got.append(w)
	return got
