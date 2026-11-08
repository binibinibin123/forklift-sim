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
	var exit := Kit.button("나가기", func(): exit_pressed.emit(), 20, "ghost")
	bar.add_child(exit)
	step_lbl = Kit.chip("", Color(0.05, 0.08, 0.13, 0.7), 20)
	bar.add_child(step_lbl)
	pips = Kit.hbox(4)
	bar.add_child(pips)
	bar.add_child(Kit.spacer())
	timer_lbl = Kit.label("3:00", 32)
	timer_lbl.add_theme_stylebox_override("normal", Kit.sb(Color(0.05, 0.08, 0.13, 0.7), 12, 4))
	bar.add_child(timer_lbl)
	score_lbl = Kit.label("100점", 32)
	score_lbl.add_theme_stylebox_override("normal", Kit.sb(Color(0.05, 0.08, 0.13, 0.7), 12, 4))
	bar.add_child(score_lbl)
	bar.add_child(Kit.spacer())
	cam_btn = Kit.button("", func(): camera_pressed.emit(), 19, "ghost")
	bar.add_child(cam_btn)
	guide_btn = Kit.button("", func(): guide_pressed.emit(), 19, "ghost")
	bar.add_child(guide_btn)
	pause_btn = Kit.button("일시정지", func(): pause_pressed.emit(), 19, "ghost")
	bar.add_child(pause_btn)
	demo_tag = Kit.chip("모범 주행 보는 중", Kit.GREEN.darkened(0.3), 20)
	add_child(demo_tag)
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
	gas.label = "가속"
	gas.color = Color(0.14, 0.19, 0.27)
	brk = PedalWidget.new()
	brk.label = "브레이크"
	brk.color = Color(0.36, 0.13, 0.14)
	gear = PedalWidget.new()
	gear.label = "D"
	gear.sub = "기어"
	gear.tap = true
	gear.color = Kit.GREEN.darkened(0.45)
	gear.tapped.connect(func(): gear_toggled.emit())
	center_btn = PedalWidget.new()
	center_btn.label = "핸들 풀기"
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
	row.add_child(Kit.button("출발", func(): start_pressed.emit(), 26, "primary"))
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
	pv.add_child(Kit.label("일시정지", 34, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	pv.add_child(Kit.button("계속하기", func(): resume_pressed.emit(), 24, "primary"))
	pv.add_child(Kit.button("처음부터", func(): restart_pressed.emit(), 22))
	pv.add_child(Kit.button("나가기", func(): exit_pressed.emit(), 22, "ghost"))
	# replay bar
	replay_bar = Kit.panel(Kit.BG_SOLID, 18, 12)
	replay_bar.visible = false
	add_child(replay_bar)
	var rv := Kit.vbox(6)
	rv.custom_minimum_size.x = 760
	replay_bar.add_child(rv)
	var rh := Kit.hbox(10)
	rv.add_child(rh)
	rh.add_child(Kit.label("리플레이", 22, Kit.PRIMARY))
	replay_time = Kit.label("0:00 / 0:00", 20, Kit.MUTED)
	rh.add_child(replay_time)
	rh.add_child(Kit.spacer())
	rh.add_child(Kit.button("이전 실수", func(): _jump(-1), 18, "ghost"))
	replay_play_btn = Kit.button("일시정지", func(): replay_play.emit(replay_play_btn.text == "재생"), 18, "ghost")
	rh.add_child(replay_play_btn)
	rh.add_child(Kit.button("다음 실수", func(): _jump(1), 18, "ghost"))
	rh.add_child(Kit.button("닫기", func(): replay_close.emit(), 18, "ghost"))
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
	score_lbl.text = "%d점" % exam.score
	score_lbl.visible = not free_run
	score_lbl.add_theme_color_override("font_color", Kit.RED if exam.score < Exam.PASS else Kit.TEXT)
	cam_btn.text = "시점 · " + cam_name
	guide_btn.text = "궤적 " + ("켬" if guide_on else "끔")
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
	coach_lbl.text = "코치: " + t
	coach_lbl.add_theme_stylebox_override("normal", Kit.sb(Color(0.05, 0.08, 0.13, 0.82), 14, 8, {"bad": Kit.RED, "warn": Kit.AMBER}.get(kind, Kit.PRIMARY)))
	coach_lbl.visible = true
	coach_lbl.reset_size()
	coach_lbl.position.x = (size.x - coach_lbl.size.x) * 0.5
	coach_t = 4.0


func show_tips(exam: Exam, demo: bool) -> void:
	var s := exam.step
	tips_title.text = ("모범 주행 · " if demo else "") + s.title + ("" if exam.practice else "  (%d/%d)" % [exam.index + 1, exam.steps.size()])
	tips_coach.text = s.get("coach", "")
	var lines := []
	for t in s.get("tips", []):
		lines.append("· " + t)
	if not s.get("free_run", false):
		var lim := int(exam.limit)
		var rules := "제한 시간 %d분." % (lim / 60)
		if s.type == "course":
			rules += " 검지선을 밟으면 %s." % ("20점 감점으로 바로 불합격" if exam.is_large() else "10점 감점")
		else:
			rules += " 작업 순서가 틀리면 10점 감점."
		if exam.index == 0 and not exam.practice:
			rules += " 20초 안에 출발하지 않으면 실격."
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
	check_box.add_child(Kit.label("다음 작업을 순서대로 누르세요", 22, Kit.PRIMARY))
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
		b.text = ("✓ " if font.has_char("✓".unicode_at(0)) else "완료  ") + item
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


func show_replay(length: float, marks: Array) -> void:
	_replay_len = maxf(length, 0.1)
	_replay_marks = marks
	replay_bar.visible = true
	replay_slider.set_value_no_signal(0.0)
	replay_play_btn.text = "일시정지"
	replay_marks.queue_redraw()
	replay_bar.reset_size()
	_layout()


func replay_tick(t: float, playing: bool) -> void:
	replay_slider.set_value_no_signal(clampf(t / _replay_len, 0.0, 1.0))
	replay_time.text = "%s / %s" % [Kit.fmt_time(t), Kit.fmt_time(_replay_len)]
	replay_play_btn.text = "일시정지" if playing else "재생"


func hide_replay() -> void:
	replay_bar.visible = false
