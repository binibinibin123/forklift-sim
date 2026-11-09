class_name TowRules
extends RefCounted
## The scoring rows the app grades for the Class 1 special (towing) skills
## test, with the source each row comes from. Exam.gd applies them; the
## rulebook tab lists them and the result screen prints them as a score sheet.
##
## pts per licence: an int = points deducted each time, "dq" = disqualified,
## missing = the row does not apply to that licence.
## src: "law" = 도로교통법 시행규칙 별표 24, "app" = this app's own boundary
## judgement (the law's wording leaves the exact distance to the examiner).

const ROWS := [
	{"id": "start_late", "codes": ["start_late"], "title": "tow.r.start_late", "crit": "tow.r.start_late.c",
		"pts": {"small": "dq", "wrecker": "dq", "large": "dq"}, "src": "law"},
	{"id": "seatbelt", "codes": ["seatbelt"], "title": "tow.r.seatbelt", "crit": "tow.r.seatbelt.c",
		"pts": {"small": "dq", "wrecker": "dq", "large": "dq"}, "src": "law"},
	{"id": "line", "codes": ["line"], "title": "tow.r.line", "crit": "tow.r.line.c",
		"pts": {"small": 10, "wrecker": 10, "large": 20}, "src": "law"},
	{"id": "time", "codes": ["time"], "title": "tow.r.time", "crit": "tow.r.time.c",
		"pts": {"small": 10, "wrecker": 10, "large": 20}, "src": "law"},
	{"id": "confirm", "codes": ["confirm"], "title": "tow.r.confirm", "crit": "tow.r.confirm.c",
		"pts": {"large": 20}, "src": "law"},
	{"id": "jackknife", "codes": ["jackknife"], "title": "tow.r.jackknife", "crit": "tow.r.jackknife.c",
		"pts": {"small": "dq", "wrecker": "dq", "large": "dq"}, "src": "law"},
	{"id": "order", "codes": ["order"], "title": "tow.r.order", "crit": "tow.r.order.c",
		"pts": {"wrecker": 10, "large": 10}, "src": "law"},
	{"id": "collide", "codes": ["collide"], "title": "tow.r.collide", "crit": "tow.r.collide.c",
		"pts": {"wrecker": "dq", "large": "dq"}, "src": "law"},
	{"id": "off_course", "codes": ["off_course", "yard_out"], "title": "tow.r.off", "crit": "tow.r.off.c",
		"pts": {"small": "dq", "wrecker": "dq", "large": "dq"}, "src": "app"},
]


static func rows_for(kind: String) -> Array:
	return ROWS.filter(func(r): return r.pts.has(kind))


static func row(id: String) -> Dictionary:
	for r in ROWS:
		if r.id == id:
			return r
	return {}


static func row_for_code(code: String) -> Dictionary:
	for r in ROWS:
		if code in r.codes:
			return r
	return {}


static func source(r: Dictionary) -> String:
	return Lang.t("tow.src.law") if r.src == "law" else Lang.t("tow.src.app")


## "실격", "-10", "-20 (즉시 불합격)" for one licence.
static func points_text(r: Dictionary, kind: String) -> String:
	var p = r.pts.get(kind, null)
	if p == null:
		return "—"
	if str(p) == "dq":
		return Lang.t("tow.r.dq")
	var s := "-%d" % int(p)
	if kind == "large" and int(p) >= 20:
		s += " " + Lang.t("tow.r.instant_fail")
	return s


## What this run scored on one row: "실격", "-20", "0".
static func run_text(r: Dictionary, exam: Exam) -> String:
	if not exam.dq_info.is_empty() and str(exam.dq_info.get("code", "")) in r.codes:
		return Lang.t("tow.r.dq")
	var sum := 0
	for d in exam.deductions:
		if str(d.get("code", "")) in r.codes:
			sum += int(d.points)
	return ("-%d" % sum) if sum > 0 else "0"


## "23 s > 20 s", "18 cm < 20 cm", or the violation's own detail line.
static func measure_text(v: Dictionary) -> String:
	if str(v.get("detail", "")) != "":
		return str(v.detail)
	if float(v.get("measured", -1.0)) < 0.0:
		return ""
	var u: String = v.get("unit", "")
	var unit: String = {"s": Lang.t("tow.u.s"), "cm": " cm", "deg": "°"}.get(u, "")
	var mv := float(v.measured)
	var lv := float(v.limit)
	var m := "%d" % roundi(mv)
	var l := "%d" % roundi(lv)
	if u == "s":
		# seconds: whole limit, measured with enough decimals to show it is over
		l = ("%d" % roundi(lv)) if is_equal_approx(lv, roundf(lv)) else ("%.1f" % lv)
		m = ("%.2f" % mv) if absf(mv - lv) < 1.0 else ("%.1f" % mv)
	elif absf(mv - lv) < 1.0:
		m = "%.1f" % mv
	return "%s%s %s %s%s" % [m, unit, v.get("cmp", ""), l, unit]


## One line for the freeze frame: "실격: 출발 지연 · 20.02초 > 20초  (별표24)"
static func headline(v: Dictionary) -> String:
	var head := Lang.t("tow.ex.dq_prefix") if bool(v.get("dq", false)) else ("-%d  " % int(v.get("points", 0)))
	var m := measure_text(v)
	var r := row_for_code(str(v.get("code", "")))
	var src := Lang.t("tow.src.short_law") if r.get("src", "") == "law" else Lang.t("tow.src.short_app")
	return "%s%s%s  (%s)" % [head, v.get("text", ""), ("  ·  " + m) if m != "" else "", src]
