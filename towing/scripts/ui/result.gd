class_name ResultScreen
extends Control
## The debrief after a run: verdict, score ring, stars, every deduction with
## its time, new best / badges, and what to do next.

signal retry_pressed
signal next_pressed
signal replay_pressed
signal home_pressed

var panel: PanelContainer
var title_lbl: Label
var ring: Control
var ring_score := 100
var ring_pass := true
var stars_lbl: Label
var meta_lbl: Label
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
	panel = Kit.panel(Kit.BG_SOLID, 24, 24)
	cc.add_child(panel)
	var h := Kit.hbox(26)
	panel.add_child(h)
	# left: ring + verdict
	var left := Kit.vbox(8)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(left)
	title_lbl = Kit.label("합격", 44, Kit.GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(title_lbl)
	ring = Control.new()
	ring.custom_minimum_size = Vector2(170, 170)
	ring.draw.connect(_draw_ring)
	left.add_child(ring)
	stars_lbl = Kit.stars(3, 30)
	stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(stars_lbl)
	meta_lbl = Kit.label("", 18, Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(meta_lbl)
	# right: breakdown + actions
	var right := Kit.vbox(8)
	right.custom_minimum_size.x = 470
	h.add_child(right)
	right.add_child(Kit.label("채점 내역", 22, Kit.PRIMARY))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(470, 190)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	body = Kit.vbox(4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	badge_row = Kit.hbox(8)
	right.add_child(badge_row)
	right.add_child(Kit.spacer(false))
	var btns := Kit.hbox(10)
	right.add_child(btns)
	replay_btn = Kit.button("리플레이", func(): replay_pressed.emit(), 21, "ghost")
	btns.add_child(replay_btn)
	btns.add_child(Kit.button("다시 하기", func(): retry_pressed.emit(), 21))
	next_btn = Kit.button("다음 코스", func(): next_pressed.emit(), 21, "primary")
	btns.add_child(next_btn)
	btns.add_child(Kit.button("목록", func(): home_pressed.emit(), 21, "ghost"))


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
	var sub := "점"
	ring.draw_string(f, c + Vector2(w * 0.5 + 2, 18), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Kit.MUTED)


func show_result(exam: Exam, rec: Dictionary, new_badges: Array, has_next: bool, demo: bool) -> void:
	var ok := exam.passed
	var free_run: bool = exam.step.get("free_run", false)
	title_lbl.text = "합격" if ok else ("실격" if exam.disqualified != "" else "불합격")
	if free_run:
		title_lbl.text = "자유 연습 종료"
	title_lbl.add_theme_color_override("font_color", Kit.GREEN if ok else Kit.RED)
	ring_score = exam.score
	ring_pass = ok
	ring.queue_redraw()
	var st := int(rec.get("stars", TowStore.stars_for(exam.score, ok, exam.disqualified != "")))
	stars_lbl.text = Kit.stars(st).text
	stars_lbl.add_theme_color_override("font_color", Kit.GOLD if st > 0 else Color(1, 1, 1, 0.35))
	var meta := "%s 소요" % Kit.fmt_time(exam.t_total)
	if rec.get("better", false):
		meta += "  ·  최고 기록!"
	elif rec.has("best"):
		meta += "  ·  최고 %d점" % int(rec.best)
	if demo:
		meta = "모범 주행 · 기록되지 않아요"
	meta_lbl.text = meta
	for c in body.get_children():
		c.queue_free()
	if exam.disqualified != "":
		body.add_child(_row("실격", exam.disqualified, Kit.RED))
	for d in exam.deductions:
		body.add_child(_row("-%d" % d.points, d.text, Kit.AMBER))
	if exam.deductions.is_empty() and exam.disqualified == "":
		body.add_child(_row("", "감점 없이 통과했어요. 완벽해요!" if ok else "", Kit.GREEN))
	if not free_run:
		body.add_child(Kit.wrap("합격 기준 %d점. 실제 시험은 시험장 안내를 따르세요." % Exam.PASS, 16, Kit.MUTED, 440))
	for c in badge_row.get_children():
		c.queue_free()
	for id in new_badges:
		var b := Badges.info(id)
		badge_row.add_child(Kit.chip("%s %s 획득" % [b.get("icon", ""), b.get("title", id)], Kit.GOLD.darkened(0.45), 17))
	next_btn.visible = has_next
	replay_btn.visible = not free_run
	visible = true
	panel.reset_size()


func _row(tag: String, text: String, col: Color) -> Control:
	var h := Kit.hbox(8)
	if tag != "":
		var t := Kit.label(tag, 18, col)
		t.custom_minimum_size.x = 44
		h.add_child(t)
	var l := Kit.wrap(text, 18, Kit.TEXT if tag != "" else col, 400)
	h.add_child(l)
	return h
