class_name Badges
extends RefCounted
## Achievements earned from the save data. Checked after every finished run.

const ALL := [
	{"id": "first_run", "title": "tow.badge.first_run", "desc": "tow.badge.first_run.d", "icon": "🚚"},
	{"id": "first_pass", "title": "tow.badge.first_pass", "desc": "tow.badge.first_pass.d", "icon": "✅"},
	{"id": "perfect", "title": "tow.badge.perfect", "desc": "tow.badge.perfect.d", "icon": "💯"},
	{"id": "small_pass", "title": "tow.badge.small_pass", "desc": "tow.badge.small_pass.d", "icon": "🚐"},
	{"id": "wrecker_pass", "title": "tow.badge.wrecker_pass", "desc": "tow.badge.wrecker_pass.d", "icon": "🔧"},
	{"id": "large_pass", "title": "tow.badge.large_pass", "desc": "tow.badge.large_pass.d", "icon": "🚛"},
	{"id": "triple", "title": "tow.badge.triple", "desc": "tow.badge.triple.d", "icon": "🏆"},
	{"id": "drills", "title": "tow.badge.drills", "desc": "tow.badge.drills.d", "icon": "🎓"},
	{"id": "ten_runs", "title": "tow.badge.ten_runs", "desc": "tow.badge.ten_runs.d", "icon": "🔟"},
	{"id": "fifty_runs", "title": "tow.badge.fifty_runs", "desc": "tow.badge.fifty_runs.d", "icon": "🎖"},
	{"id": "hour", "title": "tow.badge.hour", "desc": "tow.badge.hour.d", "icon": "⏱"},
	{"id": "no_jackknife", "title": "tow.badge.no_jackknife", "desc": "tow.badge.no_jackknife.d", "icon": "📐"},
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
