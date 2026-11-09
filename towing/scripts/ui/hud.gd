class_name Hud
extends Control
## The driving screen: top bar (exit, step, clock, score, camera, guide,
## pause), instrument cluster, hitch-angle gauge, minimap, steering wheel,
## pedals, the step briefing, the coupling checklist, coach captions, the
## pause sheet and the replay bar.

signal exit_pressed
signal pause_pressed
signal resume_pressed
signal restart_pressed
signal camera_pressed
signal guide_pressed
signal start_pressed
signal checklist_pick(item: String)
signal gear_toggled
signal replay_seek(t: float)
signal replay_play(on: bool)
signal replay_close
signal seatbelt_pressed
signal freeze_scrub(t: float)
signal freeze_continue
signal freeze_result

var wheel: WheelWidget
var gas: PedalWidget
var brk: PedalWidget
var gear: PedalWidget
var center_btn: PedalWidget
var cluster: Cluster
var hitch: HitchGauge
var minimap: MiniMap
var step_lbl: Label
var timer_lbl: Label
var score_lbl: Label
var cam_btn: Button
var guide_btn: Button
var pause_btn: Button
var demo_tag: Label
var pips: HBoxContainer
var coach_lbl: Label
var coach_t := 0.0
var toast: Label
var toast_t := 0.0
var tips_panel: PanelContainer
var tips_title: Label
var tips_body: Label
var tips_coach: Label
var check_panel: PanelContainer
var check_box: VBoxContainer
var pause_panel: Control
var replay_bar: PanelContainer
var replay_slider: HSlider
var replay_play_btn: Button
var replay_time: Label
var replay_marks: Control
var _replay_marks: Array = []
var _replay_len := 1.0
var lefty := false
var minimap_on := true
var mirror_rects: Array = []   # TextureRects placed by main
var belt_btn: Button
var examiner: PanelContainer   # live examiner panel
var ex_lines: Array = []       # its labels
var start_lbl: Label           # big 20 s start countdown
var freeze_panel: PanelContainer
var freeze_title: Label
var freeze_body: Label
var freeze_slider: HSlider
var freeze_time: Label
var freeze_go: Button
var freeze_res: Button
var freeze_overlay: Control
var freeze_v := {}             # the violation on screen
var freeze_from := 0.0
var freeze_to := 1.0
var project: Callable          # Vector2 ground point -> screen point (main's camera)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top()
	_build_controls()
	_build_overlays()
	resized.connect(_layout)
	_layout()


func widgets() -> Array:
	return [wheel, gas, brk, gear, center_btn]


# ---------------------------------------------------------------- build

func _build_top() -> void:
	var bar := Kit.hbox(8)
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(bar)
	var exit := Kit.button(Lang.t("tow.hud.exit"), func(): exit_pressed.emit(), 20, "ghost")
	bar.add_child(exit)
	belt_btn = Kit.button("", func(): seatbelt_pressed.emit(), 19, "ghost")
	bar.add_child(belt_btn)
	step_lbl = Kit.chip("", Color(0.05, 0.08, 0.13, 0.7), 20)
	bar.add_child(step_lbl)
	pips = Kit.hbox(4)
	bar.add_child(pips)
	bar.add_child(Kit.spacer())
	timer_lbl = Kit.label("3:00", 32)
	timer_lbl.add_theme_stylebox_override("normal", Kit.sb(Color(0.05, 0.08, 0.13, 0.7), 12, 4))
	bar.add_child(timer_lbl)
	score_lbl = Kit.label(Lang.t("tow.home.points", [100]), 32)
	score_lbl.add_theme_stylebox_override("normal", Kit.sb(Color(0.05, 0.08, 0.13, 0.7), 12, 4))
	bar.add_child(score_lbl)
	bar.add_child(Kit.spacer())
	cam_btn = Kit.button("", func(): camera_pressed.emit(), 19, "ghost")
	bar.add_child(cam_btn)
	guide_btn = Kit.button("", func(): guide_pressed.emit(), 19, "ghost")
	bar.add_child(guide_btn)
	pause_btn = Kit.button(Lang.t("tow.hud.pause"), func(): pause_pressed.emit(), 19, "ghost")
	bar.add_child(pause_btn)
	demo_tag = Kit.chip(Lang.t("tow.hud.demo"), Kit.GREEN.darkened(0.3), 20)
	add_child(demo_tag)
	# live examiner panel: closest tyre to a line, clock against the limit, points
	examiner = Kit.panel(Color(0.05, 0.08, 0.13, 0.78), 12, 10)
	examiner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(examiner)
	var ev := Kit.vbox(2)
	ev.custom_minimum_size.x = 250
	examiner.add_child(ev)
	ev.add_child(Kit.label(Lang.t("tow.hud.examiner"), 15, Kit.PRIMARY))
	for i in 4:
		var l := Kit.label("", 17)
		ev.add_child(l)
		ex_lines.append(l)
	start_lbl = Kit.label("", 40, Kit.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	start_lbl.add_theme_stylebox_override("normal", Kit.sb(Color(0, 0, 0, 0.7), 16, 14, Kit.AMBER))
	start_lbl.visible = false
	add_child(start_lbl)
	coach_lbl = Kit.label("", 24, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	coach_lbl.add_theme_stylebox_override("normal", Kit.sb(Color(0.05, 0.08, 0.13, 0.8), 14, 8, Kit.PRIMARY))
	coach_lbl.visible = false
	add_child(coach_lbl)
	toast = Kit.label("", 28, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	toast.add_theme_stylebox_override("normal", Kit.sb(Color(0, 0, 0, 0.72), 14, 12, Color(0, 0, 0, 0)))
	toast.visible = false
	add_child(toast)


func _build_controls() -> void:
	minimap = MiniMap.new()
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.clip_contents = true
	add_child(minimap)
	hitch = HitchGauge.new()
	hitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hitch)
	cluster = Cluster.new()
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cluster)
	wheel = WheelWidget.new()
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wheel)
	gas = PedalWidget.new()
	gas.label = Lang.t("tow.hud.gas")
	gas.color = Color(0.14, 0.19, 0.27)
	brk = PedalWidget.new()
	brk.label = Lang.t("tow.hud.brake")
	brk.color = Color(0.36, 0.13, 0.14)
	gear = PedalWidget.new()
	gear.label = "D"
	gear.sub = Lang.t("tow.hud.gear")
	gear.tap = true
	gear.color = Kit.GREEN.darkened(0.45)
	gear.tapped.connect(func(): gear_toggled.emit())
	center_btn = PedalWidget.new()
	center_btn.label = Lang.t("tow.hud.center")
	center_btn.tap = true
	center_btn.color = Color(0.14, 0.19, 0.27)
	center_btn.tapped.connect(func(): wheel.set_steer(0.0))
	for w in [gas, brk, gear, center_btn]:
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(w)


func _build_overlays() -> void:
	# step briefing
	tips_panel = Kit.panel(Kit.BG_SOLID, 22, 22)
	add_child(tips_panel)
	var v := Kit.vbox(10)
	v.custom_minimum_size = Vector2(720, 0)
	tips_panel.add_child(v)
	tips_title = Kit.label("", 32)
	v.add_child(tips_title)
	tips_coach = Kit.wrap("", 20, Kit.PRIMARY, 720)
	v.add_child(tips_coach)
	tips_body = Kit.wrap("", 21, Color(1, 1, 1, 0.88), 720)
	v.add_child(tips_body)
	v.add_child(Kit.gap(4))
	var row := Kit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(Kit.button(Lang.t("tow.hud.go"), func(): start_pressed.emit(), 26, "primary"))
	# coupling checklist
	check_panel = Kit.panel(Kit.BG_SOLID, 18, 14)
	add_child(check_panel)
	check_box = Kit.vbox(6)
	check_box.custom_minimum_size.x = 440
	check_panel.add_child(check_box)
	check_panel.visible = false
	# pause sheet
	pause_panel = Control.new()
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	add_child(pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(cc)
	var pp := Kit.panel(Kit.BG_SOLID, 22, 24)
	cc.add_child(pp)
	var pv := Kit.vbox(12)
	pv.custom_minimum_size.x = 360
	pp.add_child(pv)
	pv.add_child(Kit.label(Lang.t("tow.hud.pause"), 34, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	pv.add_child(Kit.button(Lang.t("tow.hud.resume"), func(): resume_pressed.emit(), 24, "primary"))
	pv.add_child(Kit.button(Lang.t("tow.hud.restart"), func(): restart_pressed.emit(), 22))
	pv.add_child(Kit.button(Lang.t("tow.hud.exit"), func(): exit_pressed.emit(), 22, "ghost"))
	# replay bar
	replay_bar = Kit.panel(Kit.BG_SOLID, 18, 12)
	replay_bar.visible = false
	add_child(replay_bar)
	var rv := Kit.vbox(6)
	rv.custom_minimum_size.x = 760
	replay_bar.add_child(rv)
	var rh := Kit.hbox(10)
	rv.add_child(rh)
	rh.add_child(Kit.label(Lang.t("tow.res.replay"), 22, Kit.PRIMARY))
	replay_time = Kit.label("0:00 / 0:00", 20, Kit.MUTED)
	rh.add_child(replay_time)
	rh.add_child(Kit.spacer())
	rh.add_child(Kit.button(Lang.t("tow.hud.prev"), func(): _jump(-1), 18, "ghost"))
	replay_play_btn = Kit.button(Lang.t("tow.hud.pause"), func(): replay_play.emit(replay_play_btn.text == Lang.t("tow.hud.play")), 18, "ghost")
	rh.add_child(replay_play_btn)
	rh.add_child(Kit.button(Lang.t("tow.hud.next"), func(): _jump(1), 18, "ghost"))
	rh.add_child(Kit.button(Lang.t("tow.ui.close"), func(): replay_close.emit(), 18, "ghost"))
	var sl_holder := Control.new()
	sl_holder.custom_minimum_size.y = 34
	rv.add_child(sl_holder)
	replay_marks = Control.new()
	replay_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	replay_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_marks.draw.connect(_draw_marks)
	sl_holder.add_child(replay_marks)
	replay_slider = HSlider.new()
	replay_slider.set_anchors_preset(Control.PRESET_FULL_RECT)
	replay_slider.min_value = 0.0
	replay_slider.max_value = 1.0
	replay_slider.step = 0.001
	replay_slider.value_changed.connect(func(v): replay_seek.emit(v * _replay_len))
	sl_holder.add_child(replay_slider)
	_build_freeze()


## The failure freeze frame: what was measured against which rule, a
## measurement line drawn over the 3D view, and a scrub bar over the last
## seconds of the recording.
func _build_freeze() -> void:
	freeze_overlay = Control.new()
	freeze_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	freeze_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	freeze_overlay.draw.connect(_draw_freeze)
	freeze_overlay.visible = false
	add_child(freeze_overlay)
	freeze_panel = Kit.panel(Kit.BG_SOLID, 18, 16)
	freeze_panel.visible = false
	add_child(freeze_panel)
	var v := Kit.vbox(8)
	v.custom_minimum_size.x = 820
	freeze_panel.add_child(v)
	freeze_title = Kit.label("", 26, Kit.RED)
	v.add_child(freeze_title)
	freeze_body = Kit.wrap("", 18, Kit.TEXT, 820)
	v.add_child(freeze_body)
	var sh := Kit.hbox(10)
	v.add_child(sh)
	sh.add_child(Kit.label(Lang.t("tow.fz.scrub"), 16, Kit.MUTED))
	freeze_slider = HSlider.new()
	freeze_slider.min_value = 0.0
	freeze_slider.max_value = 1.0
	freeze_slider.step = 0.001
	freeze_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	freeze_slider.custom_minimum_size.y = 34
	freeze_slider.value_changed.connect(func(x): freeze_scrub.emit(lerpf(freeze_from, freeze_to, x)))
	sh.add_child(freeze_slider)
	freeze_time = Kit.label("", 16, Kit.MUTED)
	sh.add_child(freeze_time)
	var bh := Kit.hbox(10)
	bh.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(bh)
	freeze_go = Kit.button(Lang.t("tow.fz.continue"), func(): freeze_continue.emit(), 22, "primary")
	bh.add_child(freeze_go)
	freeze_res = Kit.button(Lang.t("tow.fz.result"), func(): freeze_result.emit(), 22, "primary")
	bh.add_child(freeze_res)


func show_freeze(v: Dictionary, from_t: float, to_t: float, finished: bool) -> void:
	freeze_v = v
	freeze_from = from_t
	freeze_to = maxf(to_t, from_t + 0.01)
	var dq := bool(v.get("dq", false))
	freeze_title.text = (Lang.t("tow.fz.dq") if dq else Lang.t("tow.fz.deduct", [int(v.get("points", 0))])) + "  " + str(v.get("text", ""))
	freeze_title.add_theme_color_override("font_color", Kit.RED if dq else Kit.AMBER)
	var r := TowRules.row_for_code(str(v.get("code", "")))
	var lines := []
	var m := TowRules.measure_text(v)
	if m != "":
		lines.append(Lang.t("tow.fz.measured", [m]))
	if not r.is_empty():
		lines.append(Lang.t("tow.fz.rule", [Lang.t(r.crit), TowRules.points_text(r, str(v.get("kind", "small")))]))
		lines.append(TowRules.source(r))
	freeze_body.text = "\n".join(lines)
	freeze_go.visible = not finished
	freeze_res.visible = finished
	freeze_slider.set_value_no_signal(1.0)
	freeze_tick(to_t)
	freeze_panel.visible = true
	freeze_overlay.visible = true
	freeze_panel.reset_size()
	set_controls_visible(false)
	_layout()


func freeze_tick(t: float) -> void:
	freeze_time.text = "%s / %s" % [Kit.fmt_time(t), Kit.fmt_time(freeze_to)]
	freeze_overlay.queue_redraw()


func hide_freeze() -> void:
	freeze_panel.visible = false
	freeze_overlay.visible = false
	freeze_v = {}


func freeze_open() -> bool:
	return freeze_panel.visible


func _draw_freeze() -> void:
	if freeze_v.is_empty() or not project.is_valid():
		return
	var a: Vector2 = freeze_v.get("a", Vector2.ZERO)
	var b: Vector2 = freeze_v.get("b", Vector2.ZERO)
	var col := Kit.RED if bool(freeze_v.get("dq", false)) else Kit.AMBER
	var pa: Vector2 = project.call(a)
	var pb: Vector2 = project.call(b)
	var f := Kit.font
	if a.distance_to(b) < 0.01:
		# no distance to show: ring the spot
		freeze_overlay.draw_arc(pa, 34.0, 0, TAU, 40, col, 4.0, true)
		return
	freeze_overlay.draw_line(pa, pb, Color(0, 0, 0, 0.6), 9.0, true)
	freeze_overlay.draw_line(pa, pb, col, 4.0, true)
	var n := (pb - pa).orthogonal().normalized() * 12.0
	for p in [pa, pb]:
		freeze_overlay.draw_line(p - n, p + n, col, 4.0, true)
	freeze_overlay.draw_circle(pa, 7.0, Color.WHITE)
	var txt := TowRules.measure_text(freeze_v)
	if txt != "":
		var mid := (pa + pb) * 0.5 + n.normalized() * 34.0
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		freeze_overlay.draw_rect(Rect2(mid - Vector2(w * 0.5 + 10, 28), Vector2(w + 20, 40)), Color(0, 0, 0, 0.75))
		freeze_overlay.draw_string(f, mid - Vector2(w * 0.5, -2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)


func _draw_marks() -> void:
	var w := replay_marks.size.x
	for m in _replay_marks:
		var x := clampf(float(m.t) / _replay_len, 0.0, 1.0) * (w - 14.0) + 7.0
		replay_marks.draw_circle(Vector2(x, replay_marks.size.y * 0.5), 7.0, Kit.RED)


func _jump(dir: int) -> void:
	var cur := replay_slider.value * _replay_len
	var best := -1.0
	if dir > 0:
		for m in _replay_marks:
			if float(m.t) > cur + 0.5 and (best < 0.0 or float(m.t) < best):
				best = float(m.t)
	else:
		for m in _replay_marks:
			if float(m.t) < cur - 0.5 and float(m.t) > best:
				best = float(m.t)
	if best >= 0.0:
		replay_slider.value = maxf(best - 3.0, 0.0) / _replay_len


# ---------------------------------------------------------------- layout

func _layout() -> void:
	var s := size
	var ws := clampf(s.y * 0.48, 220.0, 320.0)
	var left_x := 0.0 if not lefty else s.x - ws
	wheel.size = Vector2(ws, ws)
	wheel.position = Vector2(left_x, s.y - ws)
	center_btn.size = Vector2(124, 54)
	center_btn.position = Vector2(ws + 8 if not lefty else s.x - ws - 132, s.y - 58)
	var px := s.x - 118.0 if not lefty else 0.0
	gas.size = Vector2(118, 190)
	gas.position = Vector2(px, s.y - 190)
	brk.size = Vector2(130, 140)
	brk.position = Vector2(px - 140 if not lefty else px + 128, s.y - 140)
	gear.size = Vector2(104, 92)
	gear.position = Vector2(brk.position.x + 13, s.y - 140 - 104)
	cluster.size = Vector2(250, 96)
	cluster.position = Vector2(s.x - 262 if not lefty else 12, s.y - 190 - 104 - 104)
	hitch.size = Vector2(170, 120)
	hitch.position = Vector2((s.x - hitch.size.x) * 0.5, s.y - 128)
	minimap.size = Vector2(190, 190)
	minimap.position = Vector2(s.x * 0.5 + 310, 62)
	minimap.visible = minimap_on
	demo_tag.position = Vector2((s.x - demo_tag.size.x) * 0.5, s.y - 150)
	examiner.position = Vector2(s.x * 0.5 - 310 - examiner.size.x, 62)
	start_lbl.position = Vector2((s.x - start_lbl.size.x) * 0.5, s.y * 0.36)
	if freeze_panel:
		freeze_panel.position = Vector2((s.x - freeze_panel.size.x) * 0.5, s.y - freeze_panel.size.y - 10)
	coach_lbl.position = Vector2((s.x - coach_lbl.size.x) * 0.5, 64)
	toast.position = Vector2((s.x - toast.size.x) * 0.5, 124)
	tips_panel.position = ((s - tips_panel.size) * 0.5).floor()
	check_panel.position = Vector2(s.x - check_panel.size.x - 8, 66)
	replay_bar.position = Vector2((s.x - replay_bar.size.x) * 0.5, s.y - replay_bar.size.y - 8)


func _process(dt: float) -> void:
	toast_t -= dt
	if toast.visible and toast_t <= 0.0:
		toast.visible = false
	coach_t -= dt
	if coach_lbl.visible and coach_t <= 0.0:
		coach_lbl.visible = false


# ---------------------------------------------------------------- updates

func set_lefty(on: bool) -> void:
	lefty = on
	_layout()


func set_step(exam: Exam, demo: bool) -> void:
	step_lbl.text = exam.progress_text()
	for c in pips.get_children():
		c.queue_free()
	if not exam.practice:
		for i in exam.steps.size():
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(14, 14)
			dot.color = Kit.GREEN if i < exam.index else (Kit.PRIMARY if i == exam.index else Color(1, 1, 1, 0.25))
			pips.add_child(dot)
	demo_tag.visible = demo
	minimap.set_step(exam.step)
	minimap.rig = exam.rig


func update(exam: Exam, driving: bool, cam_name: String, guide_on: bool, braking: bool) -> void:
	if exam == null:
		return
	var free_run: bool = exam.step.get("free_run", false)
	var rem := maxf(exam.remaining(), 0.0)
	timer_lbl.text = Kit.fmt_time(exam.t_step) if free_run else Kit.fmt_time(rem)
	timer_lbl.add_theme_color_override("font_color", Kit.RED if rem < 30 and not free_run else Kit.TEXT)
	score_lbl.text = Lang.t("tow.home.points", [exam.score])
	score_lbl.visible = not free_run
	score_lbl.add_theme_color_override("font_color", Kit.RED if exam.score < Exam.PASS else Kit.TEXT)
	cam_btn.text = Lang.t("tow.hud.cam", [cam_name])
	guide_btn.text = Lang.t("tow.hud.guide_on") if guide_on else Lang.t("tow.hud.guide_off")
	set_belt(exam.seatbelt)
	_update_examiner(exam, free_run)
	if not freeze_open():
		for w in widgets():
			w.visible = true
			w.modulate.a = 1.0 if driving else 0.45
	var r := exam.rig
	cluster.speed_kmh = r.speed_kmh()
	cluster.reverse = r.reverse
	cluster.steer_text = wheel.turns_text()
	cluster.braking = braking
	cluster.queue_redraw()
	hitch.beta = r.beta()
	hitch.coupled = r.coupled
	hitch.limit = Rig.JACKKNIFE
	hitch.queue_redraw()
	minimap.parked = exam.trailer_parked
	minimap.parked_pos = exam.trailer_pos
	minimap.parked_th = exam.trailer_th
	minimap.queue_redraw()
	if not driving and gear.label != ("R" if r.reverse else "D"):
		set_gear(r.reverse)


func set_belt(on: bool) -> void:
	belt_btn.text = Lang.t("tow.hud.belt_on") if on else Lang.t("tow.hud.belt_off")
	belt_btn.add_theme_color_override("font_color", Kit.GREEN if on else Kit.RED)


func _update_examiner(exam: Exam, free_run: bool) -> void:
	examiner.visible = not free_run and cluster.visible
	var near := exam.closest_wheel_to_line()
	if not near.is_empty():
		var cm := roundi(float(near.d) * 100.0)
		ex_lines[0].text = Lang.t("tow.hud.ex_line", [cm, roundi(Courses.LINE_HIT * 100.0)])
		ex_lines[0].add_theme_color_override("font_color", Kit.RED if cm <= 20 else (Kit.AMBER if cm < 50 else Kit.TEXT))
	elif exam.step.type == "couple" and exam.trailer_parked:
		var e := exam.couple_error()
		ex_lines[0].text = Lang.t("tow.hud.ex_couple", [roundi(float(e.along) * 100.0), roundi(float(e.side) * 100.0)])
		ex_lines[0].add_theme_color_override("font_color", Kit.TEXT)
	else:
		ex_lines[0].text = Lang.t("tow.hud.ex_none")
		ex_lines[0].add_theme_color_override("font_color", Kit.MUTED)
	ex_lines[1].text = Lang.t("tow.hud.ex_clock", [Kit.fmt_time(exam.t_step), Kit.fmt_time(exam.step.time_limit)])
	var lost := 100 - exam.score
	ex_lines[2].text = Lang.t("tow.hud.ex_points", [lost, exam.score, Exam.PASS])
	ex_lines[2].add_theme_color_override("font_color", Kit.RED if exam.score < Exam.PASS else Kit.TEXT)
	if exam.rig.coupled:
		ex_lines[3].text = Lang.t("tow.hud.ex_hitch", [roundi(absf(rad_to_deg(exam.rig.beta()))), roundi(rad_to_deg(Rig.JACKKNIFE))])
	else:
		ex_lines[3].text = Lang.t("tow.hud.ex_solo")
	examiner.reset_size()
	# exam-day start window: 20 s after the 출발 press
	var waiting := not exam.practice and exam.index == 0 and not exam.moved and not exam.done and exam.t_wait > 0.0
	start_lbl.visible = waiting and not freeze_open()
	if waiting:
		start_lbl.text = Lang.t("tow.hud.start_in", [int(ceil(Exam.START_GRACE - exam.t_wait))])
		start_lbl.reset_size()
		start_lbl.position.x = (size.x - start_lbl.size.x) * 0.5


func set_gear(rev: bool) -> void:
	gear.label = "R" if rev else "D"
	gear.color = Kit.RED.darkened(0.45) if rev else Kit.GREEN.darkened(0.45)
	gear.queue_redraw()


func show_toast(t: String, kind: String) -> void:
	toast.text = t
	toast.add_theme_color_override("font_color", {"bad": Color(1, 0.6, 0.55), "good": Color(0.6, 1, 0.7), "warn": Kit.AMBER}.get(kind, Kit.TEXT))
	toast.visible = true
	toast.reset_size()
	toast.position.x = (size.x - toast.size.x) * 0.5
	toast_t = 2.4


func show_coach(t: String, kind: String) -> void:
	coach_lbl.text = Lang.t("tow.hud.coach") + t
	coach_lbl.add_theme_stylebox_override("normal", Kit.sb(Color(0.05, 0.08, 0.13, 0.82), 14, 8, {"bad": Kit.RED, "warn": Kit.AMBER}.get(kind, Kit.PRIMARY)))
	coach_lbl.visible = true
	coach_lbl.reset_size()
	coach_lbl.position.x = (size.x - coach_lbl.size.x) * 0.5
	coach_t = 4.0


func show_tips(exam: Exam, demo: bool) -> void:
	var s := exam.step
	tips_title.text = (Lang.t("tow.hud.demo_prefix") if demo else "") + s.title + ("" if exam.practice else "  (%d/%d)" % [exam.index + 1, exam.steps.size()])
	tips_coach.text = s.get("coach", "")
	var lines := []
	for t in s.get("tips", []):
		lines.append("· " + t)
	if not s.get("free_run", false):
		var lim := int(exam.limit)
		var rules := Lang.t("tow.hud.r_limit", [lim / 60])
		if s.type == "course":
			rules += " " + (Lang.t("tow.hud.r_line_large") if exam.is_large() else Lang.t("tow.hud.r_line"))
		else:
			rules += " " + Lang.t("tow.hud.r_order")
		if exam.index == 0 and not exam.practice:
			rules += " " + Lang.t("tow.hud.r_start")
		if not exam.seatbelt:
			rules += " " + Lang.t("tow.hud.r_belt")
		lines.append(rules)
	tips_body.text = "\n".join(lines)
	tips_panel.visible = true
	tips_panel.reset_size()
	_layout()


func hide_tips() -> void:
	tips_panel.visible = false


func show_checklist(items: Array, seed: int, disabled: bool, font: Font) -> void:
	for c in check_box.get_children():
		c.queue_free()
	check_box.add_child(Kit.label(Lang.t("tow.hud.check_head"), 22, Kit.PRIMARY))
	var shuffled := items.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	for it in shuffled:
		var b := Kit.button(it, Callable(), 21)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _pick(b, it, font))
		b.disabled = disabled
		check_box.add_child(b)
	check_panel.visible = true
	check_panel.reset_size()
	_layout()


var _pick_cb: Callable


func _pick(b: Button, item: String, font: Font) -> void:
	checklist_pick.emit(item)
	if _pick_result:
		b.disabled = true
		b.text = ("✓ " if font.has_char("✓".unicode_at(0)) else Lang.t("tow.hud.done_mark")) + item
		b.add_theme_color_override("font_disabled_color", Kit.GREEN)
	else:
		var tw := create_tween()
		b.modulate = Color(1, 0.4, 0.4)
		tw.tween_property(b, "modulate", Color.WHITE, 0.6)


var _pick_result := false


func set_pick_result(ok: bool, keep_open: bool) -> void:
	_pick_result = ok
	if not keep_open:
		check_panel.visible = false


func hide_checklist() -> void:
	check_panel.visible = false


func set_paused(on: bool) -> void:
	pause_panel.visible = on


func set_controls_visible(on: bool) -> void:
	for w in widgets():
		w.visible = on
	cluster.visible = on
	hitch.visible = on
	if examiner:
		examiner.visible = on



func show_replay(length: float, marks: Array) -> void:
	_replay_len = maxf(length, 0.1)
	_replay_marks = marks
	replay_bar.visible = true
	replay_slider.set_value_no_signal(0.0)
	replay_play_btn.text = Lang.t("tow.hud.pause")
	replay_marks.queue_redraw()
	replay_bar.reset_size()
	_layout()


func replay_tick(t: float, playing: bool) -> void:
	replay_slider.set_value_no_signal(clampf(t / _replay_len, 0.0, 1.0))
	replay_time.text = "%s / %s" % [Kit.fmt_time(t), Kit.fmt_time(_replay_len)]
	replay_play_btn.text = Lang.t("tow.hud.pause") if playing else Lang.t("tow.hud.play")


func hide_replay() -> void:
	replay_bar.visible = false
