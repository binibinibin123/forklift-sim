class_name ResultScreen
extends Control
## The debrief after a run, laid out like the examiner's score sheet: the
## 별표24 rows for this licence (항목 / 기준 / 감점 / this run), the total
## against the 90-point pass mark, every recorded violation with what was
## measured, new best / badges, and what to do next.

signal retry_pressed
signal next_pressed
signal replay_pressed
signal home_pressed

const COLS := [250, 300, 120, 90]   # item, rule, points, this run

var panel: PanelContainer
var title_lbl: Label
var ring: Control
var ring_score := 100
var ring_pass := true
var stars_lbl: Label
var meta_lbl: Label
var sheet_head: Label
var body: VBoxContainer
var next_btn: Button
var replay_btn: Button
var badge_row: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	panel = Kit.panel(Kit.BG_SOLID, 24, 22)
	cc.add_child(panel)
	var h := Kit.hbox(24)
	panel.add_child(h)
	# left: ring + verdict
	var left := Kit.vbox(8)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(left)
	title_lbl = Kit.label(Lang.t("tow.res.pass"), 44, Kit.GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(title_lbl)
	ring = Control.new()
	ring.custom_minimum_size = Vector2(170, 170)
	ring.draw.connect(_draw_ring)
	left.add_child(ring)
	stars_lbl = Kit.stars(3, 30)
	stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(stars_lbl)
	meta_lbl = Kit.label("", 17, Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(meta_lbl)
	# right: the score sheet + actions
	var right := Kit.vbox(6)
	right.custom_minimum_size.x = 800
	h.add_child(right)
	sheet_head = Kit.label("", 22, Kit.PRIMARY)
	right.add_child(sheet_head)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(800, 330)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	body = Kit.vbox(3)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	badge_row = Kit.hbox(8)
	right.add_child(badge_row)
	var btns := Kit.hbox(10)
	right.add_child(btns)
	replay_btn = Kit.button(Lang.t("tow.res.replay"), func(): replay_pressed.emit(), 21, "ghost")
	btns.add_child(replay_btn)
	btns.add_child(Kit.button(Lang.t("tow.res.retry"), func(): retry_pressed.emit(), 21))
	next_btn = Kit.button(Lang.t("tow.res.next"), func(): next_pressed.emit(), 21, "primary")
	btns.add_child(next_btn)
	btns.add_child(Kit.button(Lang.t("tow.res.list"), func(): home_pressed.emit(), 21, "ghost"))


func _draw_ring() -> void:
	var c := ring.size * 0.5
	var r := 72.0
	ring.draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.08), 14.0, true)
	var frac := clampf(ring_score / 100.0, 0.0, 1.0)
	var col := Kit.GREEN if ring_pass else Kit.RED
	if frac > 0.0:
		ring.draw_arc(c, r, -PI / 2, -PI / 2 + TAU * frac, 64, col, 14.0, true)
	# pass mark at 90
	var a90 := -PI / 2 + TAU * 0.9
	ring.draw_line(c + Vector2.from_angle(a90) * (r - 12), c + Vector2.from_angle(a90) * (r + 12), Color(1, 1, 1, 0.5), 2.0)
	var f := Kit.font
	var txt := "%d" % ring_score
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 54).x
	ring.draw_string(f, c + Vector2(-w * 0.5, 18), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color.WHITE)
	ring.draw_string(f, c + Vector2(w * 0.5 + 2, 18), Lang.t("tow.res.pts_unit"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Kit.MUTED)


func show_result(exam: Exam, rec: Dictionary, new_badges: Array, has_next: bool, demo: bool) -> void:
	var ok := exam.passed
	var free_run: bool = exam.step.get("free_run", false)
	title_lbl.text = Lang.t("tow.res.pass") if ok else (Lang.t("tow.r.dq") if exam.disqualified != "" else Lang.t("tow.res.fail"))
	if free_run:
		title_lbl.text = Lang.t("tow.res.free_done")
	title_lbl.add_theme_color_override("font_color", Kit.GREEN if ok else Kit.RED)
	ring_score = exam.score
	ring_pass = ok
	ring.queue_redraw()
	var st := int(rec.get("stars", TowStore.stars_for(exam.score, ok, exam.disqualified != "")))
	stars_lbl.text = Kit.stars(st).text
	stars_lbl.add_theme_color_override("font_color", Kit.GOLD if st > 0 else Color(1, 1, 1, 0.35))
	var meta := Lang.t("tow.res.took", [Kit.fmt_time(exam.t_total)])
	if rec.get("better", false):
		meta += "  ·  " + Lang.t("tow.res.new_best")
	elif rec.has("best"):
		meta += "  ·  " + Lang.t("tow.home.best", [int(rec.best)])
	if demo:
		meta = Lang.t("tow.res.demo")
	meta_lbl.text = meta
	var what := Lang.t("tow.home.exam_card", [HomeScreen.kind_name(exam.kind)]) if not exam.practice else HomeScreen.kind_name(exam.kind) + " · " + str(exam.step.title)
	sheet_head.text = Lang.t("tow.res.sheet", [what])
	for c in body.get_children():
		c.queue_free()
	if not free_run:
		_sheet(exam)
	for c in badge_row.get_children():
		c.queue_free()
	for id in new_badges:
		var b := Badges.info(id)
		badge_row.add_child(Kit.chip(Lang.t("tow.res.badge", [b.get("icon", ""), Lang.t(b.get("title", id))]), Kit.GOLD.darkened(0.45), 17))
	next_btn.visible = has_next
	replay_btn.visible = not free_run
	visible = true
	panel.reset_size()


func _sheet(exam: Exam) -> void:
	body.add_child(_cells([Lang.t("tow.rb.col_item"), Lang.t("tow.res.col_rule"), Lang.t("tow.rb.col_pts"), Lang.t("tow.res.col_run")], Kit.MUTED, 15))
	body.add_child(Kit.divider())
	for r in TowRules.rows_for(exam.kind):
		var run := TowRules.run_text(r, exam)
		var col := Kit.TEXT if run == "0" else (Kit.RED if run == Lang.t("tow.r.dq") else Kit.AMBER)
		body.add_child(_cells([Lang.t(r.title), Lang.t(r.crit), TowRules.points_text(r, exam.kind), run], col, 16, r.src != "law"))
	body.add_child(Kit.divider())
	var total := Kit.hbox(12)
	body.add_child(total)
	total.add_child(Kit.label(Lang.t("tow.res.total", [exam.score]), 22, Kit.GREEN if exam.passed else Kit.RED))
	var pm := Kit.label(Lang.t("tow.res.pass_mark", [Exam.PASS]), 16, Kit.MUTED)
	pm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	total.add_child(pm)
	# what was measured at each violation
	var events: Array = exam.deductions.duplicate()
	if not exam.dq_info.is_empty():
		events.append(exam.dq_info)
	if events.is_empty():
		body.add_child(Kit.label(Lang.t("tow.res.clean"), 17, Kit.GREEN))
	else:
		body.add_child(Kit.label(Lang.t("tow.res.measured"), 16, Kit.PRIMARY))
		for v in events:
			var line := "%s  %s" % [Kit.fmt_time(float(v.get("t", 0.0))), TowRules.headline(v)]
			body.add_child(Kit.wrap(line, 15, Kit.RED if bool(v.get("dq", false)) else Kit.AMBER, 780))
	body.add_child(Kit.wrap(Lang.t("tow.res.src_note"), 13, Color(1, 1, 1, 0.5), 780))


func _cells(texts: Array, col: Color, size: int, app_row := false) -> Control:
	var h := Kit.hbox(10)
	for i in texts.size():
		var t: String = texts[i]
		if i == 0 and app_row:
			t += " *"
		var l := Kit.wrap(t, size, col if i != 1 else Kit.MUTED, COLS[i])
		l.custom_minimum_size.x = COLS[i]
		h.add_child(l)
	return h
