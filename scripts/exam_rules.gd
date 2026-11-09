class_name ExamRules
extends RefCounted
## The forklift exam's rule rows as the app grades them.
## Source: 큐넷 공개문제 지게차운전기능사 「코스운전 및 작업」, 수험자 유의사항 10) 나) 실격 (1)~(18),
## posted 2025-12-22 (research/qnet_forklift_public_exam.pdf). Row text is paraphrased (Lang "rule.rN").
## The public exam lists no deduction items, only 화물상차작업 45 / 화물하차작업 55,
## so DEDUCTIONS are this app's estimate and are labelled that way on screen.

const SOURCE_DATE := "2025-12-22"
const PASS_MARK := 60

## n = item number in 10) 나); codes = Sim fault codes graded under it; checked = the app measures it.
const ROWS := [
	{id = "r1", n = 1, codes = [], checked = false},
	{id = "r2", n = 2, codes = ["timeout"], checked = true},
	{id = "r3", n = 3, codes = ["course", "early", "skip_touch", "wrong_place"], checked = true},
	{id = "r4", n = 4, codes = ["start_late"], checked = true},
	{id = "r5", n = 5, codes = [], checked = false},
	{id = "r6", n = 6, codes = ["fork_start"], checked = true},
	{id = "r7", n = 7, codes = ["line", "line_start"], checked = true},
	{id = "r8", n = 8, codes = ["drop"], checked = true},
	{id = "r9", n = 9, codes = ["pallet_push"], checked = true},
	{id = "r10", n = 10, codes = ["drum_touch"], checked = true},
	{id = "r11", n = 11, codes = ["no_pallet", "no_pallet2"], checked = true},
	{id = "r12", n = 12, codes = ["fork_ground", "pallet_ground"], checked = true},
	{id = "r13", n = 13, codes = ["touch_wrong"], checked = true},
	{id = "r14", n = 14, codes = ["fork_high"], checked = true},
	{id = "r15", n = 15, codes = ["offset"], checked = true},
	{id = "r16", n = 16, codes = ["pushed_off"], checked = true},
	{id = "r17", n = 17, codes = ["std_push"], checked = true},
	{id = "r18", n = 18, codes = ["shallow"], checked = true},
]

## Estimated deductions (code -> points), shown as "추정".
const DEDUCTIONS := {
	"seatbelt": 5,
	"height": 5,
	"tilt": 5,
	"touch_gear": 5,
	"touch_moving": 5,
	"park_line": 5,
}

## Which score-sheet part each estimated deduction usually falls in.
const DEDUCTION_PART := {
	"seatbelt": "load",
	"height": "both",
	"tilt": "both",
	"touch_gear": "unload",
	"touch_moving": "unload",
	"park_line": "unload",
}


static func row_of(code: String) -> Dictionary:
	for r in ROWS:
		if code in r.codes:
			return r
	return {}


static func all_codes() -> Array:
	var out := []
	for r in ROWS:
		out.append_array(r.codes)
	return out


## "큐넷 공개문제 10)나)(14)" style citation for a fault code.
static func cite(code: String) -> String:
	var r := row_of(code)
	if r.is_empty():
		return Lang.t("rules.src_short")
	return Lang.t("rules.cite", [r.n])


## "포크 높이 54 cm > 50 cm" style measured line, or "" when nothing was measured.
static func measured(f: Dictionary) -> String:
	var v = f.get("val", NAN)
	if typeof(v) != TYPE_FLOAT or is_nan(v):
		return ""
	var lim = f.get("lim", NAN)
	var unit: String = f.get("unit", "")
	var u := Lang.t("unit." + unit) if unit != "" else ""
	var vs := _num(v, unit)
	var key := "m." + str(f.code)
	if not Lang.has(key):
		key = "m.generic"
	if typeof(lim) == TYPE_FLOAT and not is_nan(lim):
		return Lang.t(key, [vs + u, _num(lim, unit) + u])
	return Lang.t(key, [vs + u, ""])


static func _num(v: float, unit: String) -> String:
	if unit == "s":
		return "%.1f" % v
	if unit == "m":
		return "%.1f" % v
	return "%d" % roundi(v)
