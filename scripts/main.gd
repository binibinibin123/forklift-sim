extends Node3D
## 실기 채점관 — home (two exam cards) and the forklift exam: scene, HUD, freeze frame,
## rulebook, score sheet, replay. The towing exam lives in res://towing/main.tscn.

enum State { MENU, RUN, FREEZE, RESULT, REPLAY }
enum Cam { CAB, CHASE, SIDE, TOP }
enum Mode { PRACTICE, EXAM, DRILL, RULE }

const INK := UiKit.INK
const ACCENT := UiKit.ACCENT
const RED := UiKit.RED
const GREEN := UiKit.GREEN
const SUPPORT_URL := "https://binibinibin123.github.io/gentive-app-support/forklift-sim/support.html"
const SIGNAL_WAIT := 3.0          # exam day: seconds from "ready" to the whistle

var course: Course
var sim: Sim
var world: World
var fork: ForkliftView
var cam: Camera3D
var cam_mode := Cam.CAB
var look_back := false
var marker: Node3D
var state := State.MENU
var mode := Mode.PRACTICE
var exam := false
var drill: Dictionary = {}
var drills: Array = []
var signal_wait := 0.0

# replay recording: [pos, heading, steer, lift, tilt, pallet_pos, pallet_heading, pallet_base, fallen, t_exam]
var frames: Array = []
var replay_i := 0.0
var replay_from := 0
var freeze_item: Dictionary = {}
var freeze_is_fault := false
var freeze_frame := 0

var ui: Control
var controls: Controls
var hud: Label
var step_label: Label
var step_dots: Control
var gauge: Control
var toast: Label
var toast_t := 0.0
var big: Label
var minimap: Control
var menu_panel: Control
var result_panel: Control
var result_body: VBoxContainer
var result_course: CourseView
var replay_bar: Control
var replay_slider: HSlider
var freeze_panel: Control
var freeze_body: VBoxContainer
var freeze_slider: HSlider
var overlay: Control
var screens := {}
var _faults_seen := 0
var _deduct_seen := 0
var store := ForkliftSave.new()
var unlock: ExamUnlock
var sfx: Sfx
var stats_label: Label
var _args := {}
var _shot_frames := -1
var _menu_angle := 0.6
var _slider_lock := false


func _ready() -> void:
	# run arguments (screenshots in CI) are read only in debug builds
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			var kv := a.split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.get("app", "") == "towing":
		_open_towing.call_deferred()
		return
	store.load_data()
	unlock = ExamUnlock.shared()
	sfx = Sfx.new()
	add_child(sfx)
	_apply_settings()
	course = Course.load_default()
	drills = Drills.list(course)
	sim = Sim.new(course, true)
	_build_scene()
	_build_ui()
	_show_menu()
	if _args.has("shot"):
		_setup_shot()


func _open_towing() -> void:
	get_tree().change_scene_to_file("res://towing/main.tscn")


func _apply_settings() -> void:
	sfx.enabled = bool(store.data.sound)
	sfx.haptics = bool(store.data.haptics)
	if controls:
		controls.sens = float(store.data.steer_sens)


# ---------- scene ----------
func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.52, 0.86)
	sm.sky_horizon_color = Color(0.8, 0.86, 0.93)
	sm.ground_horizon_color = Color(0.62, 0.64, 0.62)
	sm.ground_bottom_color = Color(0.4, 0.42, 0.4)
	sm.sun_angle_max = 20.0
	sm.sun_curve = 0.12
	sm.sky_cover = load("res://textures/clouds.png")
	sm.sky_cover_modulate = Color(1, 1, 1, 0.85)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	if not Mats.compat:
		e.fog_enabled = true
		e.fog_light_color = Color(0.78, 0.84, 0.92)
		e.fog_density = 0.004
		e.fog_sky_affect = 0.2
		e.ssao_enabled = true
		e.ssao_intensity = 1.5
		e.glow_enabled = true
		e.glow_intensity = 0.35
		e.glow_bloom = 0.05
		e.glow_hdr_threshold = 1.2
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -38, 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.25
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	add_child(sun)

	world = World.new()
	add_child(world)
	world.build(course)
	fork = ForkliftView.new()
	add_child(fork)

	marker = Node3D.new()
	add_child(marker)
	var mm := World.mat(Color(0.2, 0.9, 1.0, 0.75), 0.4)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.emission_enabled = true
	mm.emission = Color(0.1, 0.6, 0.8)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.0
	cm.height = 0.45
	cone.mesh = cm
	cone.material_override = mm
	marker.add_child(cone)

	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = 300.0
	add_child(cam)
	cam.current = true


# ---------- UI ----------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	ui.add_child(overlay)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-330, 10)
	top.custom_minimum_size = Vector2(660, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 2)
	ui.add_child(top)
	hud = UiKit.label(top, "", 34)
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label = UiKit.label(top, "", 21, Color(0.85, 0.95, 1.0))
	step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_label.custom_minimum_size = Vector2(660, 0)
	step_dots = Control.new()
	step_dots.custom_minimum_size = Vector2(660, 16)
	step_dots.draw.connect(_draw_step_dots)
	top.add_child(step_dots)

	gauge = Control.new()
	gauge.position = Vector2(20, 150)
	gauge.size = Vector2(250, 250)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.draw.connect(_draw_gauge)
	ui.add_child(gauge)

	big = UiKit.label(ui, "", 64, ACCENT)
	big.set_anchors_preset(Control.PRESET_CENTER)
	big.position = Vector2(-500, -60)
	big.custom_minimum_size = Vector2(1000, 0)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	toast = UiKit.label(ui, "", 30, RED)
	toast.set_anchors_preset(Control.PRESET_CENTER)
	toast.position = Vector2(-400, -150)
	toast.custom_minimum_size = Vector2(800, 0)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	minimap = Minimap.new()
	minimap.setup(self)
	ui.add_child(minimap)

	controls = Controls.new()
	ui.add_child(controls)
	controls.action.connect(_on_action)
	controls.sens = float(store.data.steer_sens)

	_build_menu()
	_build_result()
	_build_freeze()
	_build_replay_bar()


func _build_menu() -> void:
	menu_panel = Control.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(menu_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.07, 0.08, 0.78)
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.custom_minimum_size = Vector2(930, 0)
	shade.size = Vector2(930, 720)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_panel.add_child(shade)
	var stripe := ColorRect.new()   # safety-yellow edge
	stripe.color = Color(1.0, 0.77, 0.0)
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.position.x = 930
	stripe.custom_minimum_size = Vector2(6, 0)
	stripe.size = Vector2(6, 720)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_panel.add_child(stripe)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	menu_panel.add_child(margin)
	var mv := UiKit.vbox(margin, 10)
	var head := UiKit.hbox(mv, 14)
	UiKit.label(head, Lang.t("app.name"), 44)
	var sub := UiKit.label(head, Lang.t("app.tagline"), 19, UiKit.DIM, false)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats_label = UiKit.label(mv, "", 18, Color(1, 1, 1, 0.72), false)
	var cards := UiKit.hbox(mv, 18)
	# forklift card
	var fc := _card(cards, Lang.t("home.fl.title"), Lang.t("home.fl.meta"), Lang.t("home.fl.note"), Color(1.0, 0.77, 0.0))
	var fg := GridContainer.new()
	fg.columns = 2
	fg.add_theme_constant_override("h_separation", 10)
	fg.add_theme_constant_override("v_separation", 10)
	fc.add_child(fg)
	var bs := Vector2(198, 54)
	UiKit.button(fg, Lang.t("home.exam_day"), _start_exam, Color(1.0, 0.77, 0.0), bs, 20)
	UiKit.button(fg, Lang.t("home.practice"), _start_practice, Color(0.36, 0.62, 0.95), bs, 20)
	UiKit.ghost(fg, Lang.t("home.drills"), func(): _open("drills"), bs, 20)
	UiKit.ghost(fg, Lang.t("home.rulebook"), func(): _open("rules"), bs, 20)
	# towing card
	var tc := _card(cards, Lang.t("home.tow.title"), Lang.t("home.tow.meta"), Lang.t("home.tow.note"), Color(0.45, 0.75, 1.0))
	UiKit.spacer(tc, 4)
	var tb := UiKit.button(tc, Lang.t("home.tow.open"), _open_towing, Color(0.45, 0.75, 1.0), Vector2(386, 54), 20)
	tb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tc.get_parent().get_parent().visible = not OS.has_feature("web")   # the Toss mini-app ships the forklift exam only
	var row := UiKit.hbox(mv, 10)
	UiKit.ghost(row, Lang.t("home.records"), func(): _open("records"), Vector2(150, 48), 19)
	UiKit.ghost(row, Lang.t("home.settings"), func(): _open("settings"), Vector2(150, 48), 19)
	UiKit.ghost(row, "한국어 / English", _toggle_lang, Vector2(200, 48), 19)
	var link := LinkButton.new()
	link.text = Lang.t("home.support")
	link.add_theme_font_size_override("font_size", 16)
	link.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	link.pressed.connect(func(): OS.shell_open(SUPPORT_URL))
	link.visible = not OS.has_feature("toss")
	row.add_child(link)
	UiKit.para(mv, Lang.t("home.disclaimer"), 15, Color(1, 1, 1, 0.5), 850)


func _card(parent: Node, title: String, meta: String, note: String, col: Color) -> VBoxContainer:
	var p := UiKit.panel(parent, Color(1, 1, 1, 0.07), 16, 20)
	p.custom_minimum_size = Vector2(426, 0)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.border_width_top = 4
	sb.border_color = col
	var v := UiKit.vbox(p, 8)
	UiKit.para(v, title, 26, INK, 386)
	UiKit.label(v, meta, 18, col, false)
	UiKit.para(v, note, 16, UiKit.DIM, 386)
	return v


func _toggle_lang() -> void:
	Lang.set_code("en" if Lang.current() == "ko" else "ko")
	get_tree().reload_current_scene()


func _build_result() -> void:
	result_panel = Control.new()
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(result_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(center)
	var rp := UiKit.panel(center, Color(0.93, 0.92, 0.88, 0.97), 6, 20)
	var row := UiKit.hbox(rp, 22)
	result_body = UiKit.vbox(row, 4)
	result_body.custom_minimum_size = Vector2(780, 0)
	result_course = CourseView.new()
	result_course.setup(course, 15.0)
	result_course.show_dims = false
	result_course.show_routes = false
	result_course.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(result_course)


func _build_freeze() -> void:
	freeze_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.07, 0.92)
	sb.border_width_left = 8
	sb.border_color = RED
	sb.set_content_margin_all(18)
	freeze_panel.add_theme_stylebox_override("panel", sb)
	freeze_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	freeze_panel.position = Vector2(-560, -250)
	freeze_panel.custom_minimum_size = Vector2(1120, 0)
	ui.add_child(freeze_panel)
	freeze_body = UiKit.vbox(freeze_panel, 6)
	freeze_panel.visible = false


func _build_replay_bar() -> void:
	replay_bar = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.8)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(12)
	replay_bar.add_theme_stylebox_override("panel", sb)
	replay_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	replay_bar.position = Vector2(-420, -96)
	replay_bar.custom_minimum_size = Vector2(840, 0)
	ui.add_child(replay_bar)
	var h := UiKit.hbox(replay_bar, 14)
	replay_slider = HSlider.new()
	replay_slider.custom_minimum_size = Vector2(560, 40)
	replay_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	replay_slider.value_changed.connect(func(v):
		if not _slider_lock:
			replay_i = v)
	h.add_child(replay_slider)
	UiKit.ghost(h, Lang.t("replay.close"), _end_replay, Vector2(220, 52))


# ---------- sub screens ----------
func _open(name: String) -> void:
	_close_screens()
	var s := UiKit.screen(ui, Lang.t("screen." + name), _close_screens)
	screens[name] = s.root
	menu_panel.visible = false
	match name:
		"drills": _fill_drills(s.body)
		"rules": _fill_rules(s)
		"records": _fill_records(s.body)
		"settings": _fill_settings(s.body)
	sfx.play("click")


func _close_screens() -> void:
	for k in screens:
		screens[k].queue_free()
	screens.clear()
	menu_panel.visible = state == State.MENU


func _fill_drills(body: VBoxContainer) -> void:
	UiKit.para(body, Lang.t("drills.intro"), 19, UiKit.DIM, 1300)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	body.add_child(grid)
	for i in drills.size():
		var d: Dictionary = drills[i]
		var p := UiKit.panel(grid, Color(1, 1, 1, 0.06), 16, 18)
		p.custom_minimum_size = Vector2(470, 0)
		var v := UiKit.vbox(p, 6)
		var head := UiKit.hbox(v, 10)
		UiKit.label(head, "%d" % (i + 1), 30, ACCENT)
		var t := UiKit.label(head, Lang.t("drill.%s" % d.id), 26)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiKit.para(v, Lang.t("drill.%s.d" % d.id), 18, INK, 430)
		var rec: Dictionary = store.data.drills.get(d.id, {})
		var done := int(rec.get("done", 0))
		var info := Lang.t("drills.never") if done == 0 else Lang.t("drills.count", [done, int(rec.get("clean", 0))])
		if float(rec.get("best_time", -1.0)) >= 0:
			info += Lang.t("drills.best", [_clock(float(rec.best_time))])
		UiKit.label(v, info, 16, UiKit.DIM, false)
		var sb := UiKit.button(v, Lang.t("ui.start"), _start_drill.bind(d), ACCENT, Vector2(200, 50), 20)
		sb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


## Rulebook: official disqualification rows with source, the estimated deductions, the course drawing.
func _fill_rules(s: Dictionary) -> void:
	var body: VBoxContainer = s.body
	var tabs := UiKit.hbox(s.head, 8)
	var pages := {}
	var names := ["dq", "ded", "plan"]
	var first: String = names[clampi(int(_args.get("tab", "0")), 0, 2)]
	for n in names:
		var v := UiKit.vbox(body, 8)
		v.visible = n == first
		pages[n] = v
		UiKit.ghost(tabs, Lang.t("rules.tab." + n), func():
			for k in pages:
				pages[k].visible = k == n
			s.scroll.scroll_vertical = 0, Vector2(170, 46), 18)
	# official rows
	var src := UiKit.panel(pages.dq, Color(1.0, 0.77, 0.0, 0.12), 10, 12)
	UiKit.para(src, Lang.t("rules.source"), 17, INK, 1400)
	for r in ExamRules.ROWS:
		var p := UiKit.panel(pages.dq, Color(1, 1, 1, 0.05), 10, 10)
		var h := UiKit.hbox(p, 14)
		var n := UiKit.label(h, "(%d)" % r.n, 20, ACCENT, false)
		n.custom_minimum_size = Vector2(54, 0)
		var t := UiKit.para(h, Lang.t("rule." + r.id), 19, INK, 860)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var chip := UiKit.chip(h, Lang.t("rules.checked") if r.checked else Lang.t("rules.not_checked"), GREEN if r.checked else UiKit.DIM, 15)
		chip.custom_minimum_size = Vector2(190, 0)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if r.checked:
			var b := UiKit.button(h, Lang.t("rules.drill"), _start_rule.bind(r.id), Color(0.36, 0.62, 0.95), Vector2(170, 46), 18)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# estimated deductions
	UiKit.para(pages.ded, Lang.t("rules.ded_intro"), 18, UiKit.DIM, 1400)
	for code in ExamRules.DEDUCTIONS:
		var h := UiKit.hbox(pages.ded, 12)
		UiKit.chip(h, "-%d" % ExamRules.DEDUCTIONS[code], ACCENT, 15)
		var l := UiKit.para(h, Lang.t("d." + code) + "  ·  " + Lang.t("part." + ExamRules.DEDUCTION_PART[code]), 19, INK, 1200)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# drawing and order
	var row := UiKit.hbox(pages.plan, 20)
	var cv := CourseView.new()
	cv.setup(course, 21.0)
	cv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(cv)
	var ov := UiKit.vbox(row, 8)
	for i in 8:
		var h := UiKit.hbox(ov, 10)
		UiKit.label(h, "%d" % (i + 1), 22, ACCENT, false)
		var l := UiKit.para(h, Lang.t("order.%d" % (i + 1)), 18, INK, 560)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _fill_records(body: VBoxContainer) -> void:
	var h: Array = store.data.history
	var runs := int(store.data.runs)
	var passes := int(store.data.passes)
	var row := UiKit.hbox(body, 14)
	_stat(row, Lang.t("rec.exams"), str(runs))
	_stat(row, Lang.t("rec.passes"), str(passes))
	_stat(row, Lang.t("rec.rate"), ("%d%%" % int(100.0 * passes / runs)) if runs > 0 else "-")
	_stat(row, Lang.t("rec.best"), str(int(store.data.best)) if int(store.data.best) >= 0 else "-")
	UiKit.spacer(body, 6)
	if h.is_empty():
		UiKit.para(body, Lang.t("rec.empty"), 20, UiKit.DIM, 1200)
		return
	var head := UiKit.hbox(body, 0)
	for col in [["rec.date", 230], ["rec.mode", 230], ["rec.result", 120], ["rec.score", 100], ["rec.load", 90], ["rec.unload", 90], ["rec.time", 100], ["rec.note", 400]]:
		var l := UiKit.label(head, Lang.t(col[0]), 17, UiKit.DIM, false)
		l.custom_minimum_size = Vector2(col[1], 0)
	UiKit.rule(body)
	for e in h:
		var r := UiKit.hbox(body, 0)
		var passed := bool(e.get("pass", false))
		var m := str(e.get("mode", ""))
		var mname := Lang.t("mode." + m) if Lang.has("mode." + m) else "-"
		if e.has("title"):
			var tk := "drill." + str(e.title)
			var rk := "rule." + str(e.title)
			mname += " · " + (Lang.t(tk) if Lang.has(tk) else ("(%s)" % str(e.title).substr(1) if Lang.has(rk) else str(e.title)))
		var cells := [
			[str(e.get("ts", "")), 230, INK],
			[mname, 230, INK],
			[Lang.t("res.pass") if passed else Lang.t("res.fail"), 120, GREEN if passed else RED],
			["%d" % int(e.get("score", 0)), 100, INK],
			["%d/45" % int(e.get("load", 0)), 90, INK],
			["%d/55" % int(e.get("unload", 0)), 90, INK],
			[_clock(float(e.get("time", 0))), 100, INK],
			[str(e.get("note", "")), 400, UiKit.DIM],
		]
		for c in cells:
			var l := UiKit.label(r, c[0], 18, c[2], false)
			l.custom_minimum_size = Vector2(c[1], 0)
			l.clip_text = true


func _stat(parent: Node, k: String, v: String) -> void:
	var p := UiKit.panel(parent, Color(1, 1, 1, 0.06), 14, 14)
	p.custom_minimum_size = Vector2(220, 0)
	var vb := UiKit.vbox(p, 2)
	UiKit.label(vb, k, 16, UiKit.DIM, false)
	UiKit.label(vb, v, 30, ACCENT, false)


func _fill_settings(body: VBoxContainer) -> void:
	var pl := UiKit.panel(body, Color(1, 1, 1, 0.06), 14, 16)
	var hl := UiKit.hbox(pl, 16)
	var vl := UiKit.vbox(hl, 2)
	vl.custom_minimum_size = Vector2(520, 0)
	UiKit.label(vl, Lang.t("set.lang"), 22, INK, false)
	UiKit.label(vl, Lang.t("set.lang.d"), 16, UiKit.DIM, false)
	for c in [["ko", "한국어"], ["en", "English"]]:
		var b := UiKit.button(hl, c[1], func():
			Lang.set_code(c[0])
			get_tree().reload_current_scene(), ACCENT if Lang.current() == c[0] else Color(1, 1, 1, 0.14), Vector2(150, 46), 19)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_setting_toggle(body, Lang.t("set.sound"), Lang.t("set.sound.d"), "sound")
	_setting_toggle(body, Lang.t("set.haptics"), Lang.t("set.haptics.d"), "haptics")
	var p := UiKit.panel(body, Color(1, 1, 1, 0.06), 14, 16)
	var h := UiKit.hbox(p, 16)
	var v := UiKit.vbox(h, 2)
	v.custom_minimum_size = Vector2(520, 0)
	UiKit.label(v, Lang.t("set.steer"), 22, INK, false)
	UiKit.label(v, Lang.t("set.steer.d"), 16, UiKit.DIM, false)
	var sl := HSlider.new()
	sl.min_value = 0.6
	sl.max_value = 1.4
	sl.step = 0.1
	sl.value = float(store.data.steer_sens)
	sl.custom_minimum_size = Vector2(360, 40)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sl)
	var val := UiKit.label(h, "%.1f" % sl.value, 22, ACCENT, false)
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(x):
		store.data.steer_sens = x
		val.text = "%.1f" % x
		store.save()
		_apply_settings())
	var p2 := UiKit.panel(body, Color(1, 1, 1, 0.06), 14, 16)
	var h2 := UiKit.hbox(p2, 16)
	var v2 := UiKit.vbox(h2, 2)
	v2.custom_minimum_size = Vector2(520, 0)
	UiKit.label(v2, Lang.t("set.cam"), 22, INK, false)
	UiKit.label(v2, Lang.t("set.cam.d"), 16, UiKit.DIM, false)
	var ob := OptionButton.new()
	for i in 4:
		ob.add_item(Lang.t("cam.%d" % i))
	ob.selected = int(store.data.cam)
	ob.add_theme_font_size_override("font_size", 20)
	ob.custom_minimum_size = Vector2(200, 46)
	ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ob.item_selected.connect(func(i):
		store.data.cam = i
		store.save())
	h2.add_child(ob)
	UiKit.spacer(body, 6)
	UiKit.para(body, Lang.t("set.keys"), 16, UiKit.DIM, 1300)


func _setting_toggle(body: VBoxContainer, title: String, desc: String, key: String) -> void:
	var p := UiKit.panel(body, Color(1, 1, 1, 0.06), 14, 16)
	var h := UiKit.hbox(p, 16)
	var v := UiKit.vbox(h, 2)
	v.custom_minimum_size = Vector2(520, 0)
	UiKit.label(v, title, 22, INK, false)
	UiKit.label(v, desc, 16, UiKit.DIM, false)
	var b := UiKit.button(h, "", func(): pass, ACCENT, Vector2(120, 46), 19)
	var refresh := func():
		var on := bool(store.data[key])
		b.text = Lang.t("ui.on") if on else Lang.t("ui.off")
		b.modulate = Color(1, 1, 1, 1.0 if on else 0.45)
	b.pressed.connect(func():
		store.data[key] = not bool(store.data[key])
		store.save()
		_apply_settings()
		refresh.call())
	refresh.call()


# ---------- menu and start ----------
func _refresh_stats() -> void:
	var runs := int(store.data.runs)
	stats_label.text = Lang.t("home.stats", [int(store.data.best), runs, int(store.data.passes)]) if runs > 0 else Lang.t("home.stats_none")


func _show_menu() -> void:
	state = State.MENU
	_close_screens()
	_refresh_stats()
	menu_panel.visible = true
	result_panel.visible = false
	freeze_panel.visible = false
	replay_bar.visible = false
	controls.visible = false
	controls.enabled = false
	big.text = ""
	sim.reset()
	sim.lift = 0.0
	frames.clear()
	cam_mode = Cam.CHASE
	sfx.stop_all()


func _start_practice() -> void:
	_start(Mode.PRACTICE)


func _start_exam() -> void:
	_start(Mode.EXAM)


func _start_drill(d: Dictionary) -> void:
	drill = d
	_start(Mode.DRILL)


func _start_rule(rule_id: String) -> void:
	drill = Drills.rule_drill(course, rule_id)
	if drill.is_empty():
		return
	_start(Mode.RULE)


func _start(m: Mode) -> void:
	_close_screens()
	mode = m
	exam = m == Mode.EXAM
	sim.exam = exam
	if m == Mode.DRILL or m == Mode.RULE:
		sim.start_drill(drill)
	else:
		sim.reset()
	controls.reset()
	controls.seatbelt = sim.seatbelt
	controls.park_brake = sim.park_brake
	controls.gear = sim.gear
	frames.clear()
	_faults_seen = 0
	_deduct_seen = 0
	toast.text = ""
	big.text = ""
	state = State.RUN
	menu_panel.visible = false
	result_panel.visible = false
	freeze_panel.visible = false
	replay_bar.visible = false
	controls.visible = true
	controls.enabled = true
	controls.set_button("signal", "")
	signal_wait = SIGNAL_WAIT if exam else 0.0
	if m == Mode.PRACTICE:
		sim.give_signal()
	cam_mode = int(store.data.cam) as Cam
	look_back = false
	_sync_controls_buttons()
	if m == Mode.DRILL:
		_toast(Lang.t("drill.%s.tip" % drill.id), Color(0.85, 0.95, 1.0), 6.0)
	elif m == Mode.RULE:
		_toast(Lang.t("rdrill.%s" % drill.rule), Color(0.85, 0.95, 1.0), 7.0)
	elif exam:
		_toast(Lang.t("exam.ready"), Color(0.85, 0.95, 1.0), SIGNAL_WAIT)
	sfx.play("click")


func _sync_controls_buttons() -> void:
	controls.set_button("seatbelt", Lang.t("ctl.seatbelt") + (" O" if controls.seatbelt else " X"), controls.seatbelt)
	controls.set_button("park", Lang.t("ctl.park") + (" ON" if controls.park_brake else " OFF"), controls.park_brake)
	controls.set_button("camera", Lang.t("cam.%d" % cam_mode))
	controls.set_button("look", Lang.t("ctl.look_fwd") if look_back else Lang.t("ctl.look_back"), look_back)


func _on_action(name: String) -> void:
	match name:
		"camera":
			cam_mode = (cam_mode + 1) % 4 as Cam
		"look":
			look_back = not look_back
		"menu":
			_show_menu()
			return
		"horn":
			sfx.play("horn")
			sim.horn_count += 1
		"seatbelt", "park":
			sfx.play("click")
	_sync_controls_buttons()


func _toast(t: String, c := RED, secs := 3.0) -> void:
	toast.text = t
	toast.add_theme_color_override("font_color", c)
	toast_t = secs


# ---------- loop ----------
func _physics_process(dt: float) -> void:
	if state != State.RUN:
		return
	# exam day: the examiner's whistle after a short wait
	if exam and not sim.signal_given:
		signal_wait -= dt
		if signal_wait <= 0.0:
			sim.give_signal()
			sfx.play("whistle")
			sfx.buzz(80)
			_toast(Lang.t("exam.whistle"), GREEN, 2.5)
	controls.poll_keys(dt)
	sim.seatbelt = controls.seatbelt
	sim.park_brake = controls.park_brake
	sim.gear = controls.gear
	var prev_step := sim.step
	sim.update(dt, {
		steer = controls.steer(),
		throttle = controls.throttle,
		brake = controls.brake,
		lift = controls.lift,
		tilt = controls.tilt,
	})
	controls.show_steer(sim.steer)
	_record()
	var graded := exam or mode == Mode.RULE
	while _faults_seen < sim.faults.size():
		var f: Dictionary = sim.faults[_faults_seen]
		_faults_seen += 1
		sfx.play("buzzer")
		sfx.buzz(220)
		if graded:
			_freeze(f, true)
			return
		_toast(Lang.t("res.dq_note") + f.msg)
	while _deduct_seen < sim.deductions.size():
		var d: Dictionary = sim.deductions[_deduct_seen]
		_deduct_seen += 1
		sfx.play("thud")
		sfx.buzz(60)
		if exam:
			_freeze(d, false)
			return
		_toast(Lang.t("res.ded_note", [d.pts]) + d.msg, ACCENT)
	if sim.step != prev_step and not sim.done:
		sfx.play("chime")
		sfx.buzz(40)
	sfx.update(sim, true, dt, controls.lift, controls.tilt, controls.throttle)
	if sim.done:
		_show_result()


func _record() -> void:
	frames.append([sim.pos, sim.heading, sim.steer, sim.lift, sim.tilt, sim.pallet_pos, sim.pallet_heading, sim.pallet_base, sim.pallet_fallen, sim.t_exam])


func _process(dt: float) -> void:
	if state == State.REPLAY:
		_replay_step(dt)
	if state != State.RUN:
		sfx.update(sim, false, dt, 0, 0, 0)
	_sync_models(dt)
	_update_marker(dt)
	_update_camera(dt)
	_update_hud(dt)
	minimap.queue_redraw()
	overlay.queue_redraw()
	if _shot_frames >= 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			_take_shot()


func _sync_models(dt: float) -> void:
	world.sync(sim)
	fork.sync(sim, dt)
	if sim.carried:
		var axis := fork.global_transform.basis.z.normalized()
		var ang := deg_to_rad(sim.tilt)
		var piv := fork.mast.global_position
		var t := world.pallet.global_transform
		t.origin = piv + (t.origin - piv).rotated(axis, ang)
		t.basis = Basis(axis, ang) * t.basis
		world.pallet.global_transform = t


func _update_marker(dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var p := Vector3.ZERO
	var show := state == State.RUN and not exam
	match sim.step:
		Sim.Step.READY: p = World.v3(Vector2(0, course.start_line_y), 1.2)
		Sim.Step.TO_LOAD, Sim.Step.RELOADED: p = World.v3(course.drum_pos, 2.0)
		Sim.Step.LOADED, Sim.Step.TOUCHED: p = World.v3(course.guide_pos, 1.2)
		Sim.Step.UNLOADED: p = World.v3(Vector2(course.back_line_x, course.center.y), 1.2)
		Sim.Step.RETURNED: p = World.v3(Vector2(0, course.start_line_y), 1.2)
		Sim.Step.FINISHED: p = World.v3(Vector2(0, course.park_line_y), 1.2)
		_: show = false
	marker.visible = show
	marker.position = p + Vector3(0, sin(t * 3.0) * 0.12, 0)


func _update_camera(dt: float) -> void:
	var fwd := World.v3(sim.dir())
	var base := World.v3(sim.pos)
	var k := 1.0 - exp(-dt * 6.0)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	if state == State.FREEZE and not freeze_item.is_empty():
		var a := _m3(freeze_item.get("ma", Vector3.INF), sim.pos)
		var b := _m3(freeze_item.get("mb", Vector3.INF), sim.pos)
		var mid := (a + b) * 0.5
		var side := World.v3(sim.right())
		cam.global_position = mid + side * 4.2 - fwd * 3.0 + Vector3(0, 2.6, 0)
		cam.look_at(mid, Vector3.UP)
		cam.fov = 55.0
		return
	match cam_mode:
		Cam.CAB:
			var eye := fork.cab_eye.global_position
			cam.global_position = eye
			var look := fwd if not look_back else -fwd
			cam.look_at(eye + look * 4.0 + Vector3(0, -1.3 if not look_back else -1.0, 0), Vector3.UP)
			cam.fov = 72.0
		Cam.CHASE:
			var back := -fwd if not look_back else fwd
			var want := base + back * 6.5 + Vector3(0, 4.2, 0)
			cam.global_position = cam.global_position.lerp(want, k) if state != State.MENU else want
			cam.look_at(base + fwd * 1.5 + Vector3(0, 0.8, 0), Vector3.UP)
			cam.fov = 62.0
		Cam.SIDE:
			var r := World.v3(sim.right())
			var tip := World.v3(sim.fork_mid(), sim.lift)
			cam.global_position = tip + r * 3.2 + Vector3(0, 0.5, 0) - fwd * 0.6
			cam.look_at(tip + Vector3(0, 0.1, 0), Vector3.UP)
			cam.fov = 55.0
		Cam.TOP:
			var c := course.bounds().get_center()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = course.bounds().size.y + 2.0
			cam.global_position = World.v3(c, 40.0)
			cam.rotation = Vector3(-PI / 2, 0, 0)
	if state == State.MENU:
		_menu_angle += dt * 0.12
		var c2 := base + Vector3(0, 1.1, 0)
		var eye := c2 + Vector3(cos(_menu_angle) * 7.5, 2.4, sin(_menu_angle) * 7.5)
		cam.global_position = eye
		cam.look_at(c2, Vector3.UP)
		cam.fov = 50.0
		cam.h_offset = 3.6


## Measurement point (x, y, height) in sim space -> 3D.
static func _m3(m, fallback: Vector2) -> Vector3:
	if typeof(m) != TYPE_VECTOR3 or m == Vector3.INF:
		return World.v3(fallback, 0.3)
	return World.v3(Vector2(m.x, m.y), m.z)


func _rule_n(rule_id: String) -> int:
	for r in ExamRules.ROWS:
		if r.id == rule_id:
			return r.n
	return 0


func _update_hud(dt: float) -> void:
	var playing := state == State.RUN or state == State.REPLAY or state == State.FREEZE
	hud.visible = playing
	step_label.visible = state == State.RUN
	step_dots.visible = state == State.RUN and mode != Mode.DRILL and mode != Mode.RULE
	gauge.visible = playing
	minimap.visible = state == State.RUN or state == State.REPLAY
	if state != State.MENU:
		cam.h_offset = 0.0
	if toast_t > 0:
		toast_t -= dt
		if toast_t <= 0:
			toast.text = ""
	big.visible = state == State.RUN
	if not playing:
		return
	var t := sim.t_exam
	big.text = ""
	if state == State.REPLAY:
		hud.text = Lang.t("hud.replay", [_clock(t)])
	elif state == State.FREEZE:
		hud.text = Lang.t("hud.freeze", [_clock(t)])
	elif exam:
		if not sim.signal_given:
			hud.text = Lang.t("hud.wait")
			big.text = "%d" % int(ceil(signal_wait))
		elif sim.step == Sim.Step.READY:
			var left := course.start_limit - sim.t_signal
			hud.text = Lang.t("hud.start_left", [int(ceil(left))])
			big.text = "%d" % int(ceil(left))
			big.add_theme_color_override("font_color", RED if left < 15.0 else ACCENT)
		elif sim.step >= Sim.Step.FINISHED:
			hud.text = Lang.t("hud.stopped", [_clock(t)])
		else:
			hud.text = Lang.t("hud.left", [_clock_tenths(maxf(course.time_limit - t, 0.0))])
	elif mode == Mode.DRILL:
		hud.text = Lang.t("hud.drill", [_clock(sim.t_total)])
		step_label.text = Lang.t("drill.%s" % drill.id)
	elif mode == Mode.RULE:
		hud.text = Lang.t("hud.drill", [_clock(sim.t_total)])
		step_label.text = "(%d) %s" % [_rule_n(drill.rule), Lang.t("rule." + drill.rule)]
	else:
		hud.text = Lang.t("hud.practice", [_clock(t)])
	if mode != Mode.DRILL and mode != Mode.RULE:
		step_label.text = sim.instruction()
	step_dots.queue_redraw()
	gauge.queue_redraw()


func _draw_step_dots() -> void:
	var n := Sim.Step.PARKED
	var w := 22.0
	var x0 := step_dots.size.x * 0.5 - n * w * 0.5
	for i in n:
		var c := Color(1, 1, 1, 0.25)
		if i < sim.step:
			c = GREEN
		elif i == sim.step:
			c = ACCENT
		step_dots.draw_circle(Vector2(x0 + i * w + w * 0.5, 8), 5.0 if i != sim.step else 7.0, c)


## Examiner panel: what the examiner looks at, in cm, against the limits.
func _draw_gauge() -> void:
	var f := gauge.get_theme_default_font()
	var g := gauge
	g.draw_rect(Rect2(Vector2.ZERO, g.size), Color(0.05, 0.06, 0.08, 0.62))
	g.draw_rect(Rect2(0, 0, 4, g.size.y), Color(1.0, 0.77, 0.0))
	g.draw_string(f, Vector2(16, 24), Lang.t("hud.examiner"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.DIM)
	var bx := 18.0
	var by := 36.0
	var bh := g.size.y - 52.0
	g.draw_rect(Rect2(bx, by, 14, bh), Color(1, 1, 1, 0.12))
	var y_of := func(h: float) -> float: return by + bh - clampf(h, 0.0, 1.0) * bh
	g.draw_rect(Rect2(bx, y_of.call(0.3), 14, y_of.call(0.2) - y_of.call(0.3)), Color(GREEN, 0.5))
	g.draw_line(Vector2(bx - 3, y_of.call(0.5)), Vector2(bx + 17, y_of.call(0.5)), RED, 2.0)
	var travel := sim.front_in_travel() and sim.front_zone() == "travel"
	var lc := INK
	if travel and (sim.lift < 0.15 or sim.lift > 0.35):
		lc = ACCENT
	if travel and sim.lift > 0.45:
		lc = RED
	var ly: float = y_of.call(sim.lift)
	g.draw_rect(Rect2(bx - 2, ly - 3, 18, 6), lc)
	var x := 46.0
	var rows := [[Lang.t("hud.fork", [roundi(sim.lift * 100)]), lc]]
	var wl := sim.wheel_line_cm()
	rows.append([Lang.t("hud.line", [maxi(roundi(wl), 0)]), RED if wl < 10 else (ACCENT if wl < 25 else INK)])
	var po := sim.pallet_offset_cm()
	if po >= 0.0 and (sim.step == Sim.Step.LOADED or sim.step == Sim.Step.UNLOADED or sim.step == Sim.Step.TOUCHED):
		rows.append([Lang.t("hud.pallet", [roundi(po)]), RED if po > 20 else (ACCENT if po > 12 else GREEN)])
	rows.append([Lang.t("hud.tilt", [sim.tilt]), INK if not sim.carried or sim.tilt >= 1.0 else ACCENT])
	rows.append(["%.1f km/h" % (absf(sim.speed) * 3.6), INK])
	var gk: String = {1: "f", 0: "n", -1: "r"}[sim.gear]
	rows.append([Lang.t("gear." + gk), ACCENT if sim.gear != 0 else UiKit.DIM])
	rows.append([Lang.t("zone." + ("travel" if travel else sim.front_zone())), UiKit.DIM])
	for i in rows.size():
		g.draw_string(f, Vector2(x, 54 + i * 28), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, rows[i][1])


## Freeze-frame measurement line, drawn over the 3D view.
func _draw_overlay() -> void:
	if state != State.FREEZE or freeze_item.is_empty():
		return
	if int(replay_i) < freeze_frame - 1:
		return   # scrubbed back: show the run, not the measurement
	var a := _m3(freeze_item.get("ma", Vector3.INF), sim.pos)
	var b := _m3(freeze_item.get("mb", Vector3.INF), sim.pos)
	if cam.is_position_behind(a) or cam.is_position_behind(b):
		return
	var pa := cam.unproject_position(a)
	var pb := cam.unproject_position(b)
	var col := RED if freeze_is_fault else ACCENT
	overlay.draw_line(pa, pb, Color(0, 0, 0, 0.6), 9.0)
	overlay.draw_line(pa, pb, col, 5.0)
	for p in [pa, pb]:
		overlay.draw_circle(p, 9.0, col)
		overlay.draw_circle(p, 4.0, Color.WHITE)
	var m := ExamRules.measured(freeze_item)
	if m != "":
		var f := overlay.get_theme_default_font()
		var mid := (pa + pb) * 0.5 + Vector2(18, -18)
		overlay.draw_string_outline(f, mid, m, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 8, Color(0, 0, 0, 0.8))
		overlay.draw_string(f, mid, m, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)


static func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


static func _clock_tenths(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


# ---------- freeze frame ----------
func _freeze(item: Dictionary, is_fault: bool) -> void:
	state = State.FREEZE
	freeze_item = item
	freeze_is_fault = is_fault
	freeze_frame = frames.size() - 1
	controls.visible = false
	controls.enabled = false
	sfx.update(sim, false, 0.0, 0, 0, 0)
	for c in freeze_body.get_children():
		c.queue_free()
	var sb: StyleBoxFlat = freeze_panel.get_theme_stylebox("panel")
	sb.border_color = RED if is_fault else ACCENT
	var head := UiKit.hbox(freeze_body, 14)
	var kind := Lang.t("res.dq") if is_fault else Lang.t("res.ded", [item.pts])
	UiKit.chip(head, kind, RED if is_fault else ACCENT, 20)
	var t := UiKit.label(head, item.msg, 28, INK, false)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var m := ExamRules.measured(item)
	var line := (m + "   ·   ") if m != "" else ""
	line += ExamRules.cite(item.code) if is_fault else Lang.t("res.estimate")
	UiKit.label(freeze_body, line, 21, Color(1.0, 0.85, 0.5) if is_fault else UiKit.DIM, false)
	var row := UiKit.hbox(freeze_body, 14)
	var sl := UiKit.label(row, Lang.t("freeze.scrub"), 17, UiKit.DIM, false)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	freeze_slider = HSlider.new()
	freeze_slider.custom_minimum_size = Vector2(560, 40)
	freeze_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var from := maxi(0, frames.size() - 60 * 8)
	freeze_slider.min_value = from
	freeze_slider.max_value = maxi(frames.size() - 1, from + 1)
	freeze_slider.step = 1
	freeze_slider.value = frames.size() - 1
	freeze_slider.value_changed.connect(func(v):
		replay_i = v
		_apply_frame(int(v)))
	row.add_child(freeze_slider)
	if is_fault:
		UiKit.button(row, Lang.t("freeze.sheet"), _show_result, ACCENT, Vector2(220, 52), 20)
	else:
		UiKit.button(row, Lang.t("freeze.continue"), _unfreeze, GREEN, Vector2(200, 52), 20)
	replay_i = frames.size() - 1
	freeze_panel.visible = true
	toast.text = ""


func _unfreeze() -> void:
	_apply_frame(freeze_frame)
	freeze_panel.visible = false
	freeze_item = {}
	state = State.RUN
	controls.visible = true
	controls.enabled = true


# ---------- result: score sheet ----------
func _show_result() -> void:
	if state == State.FREEZE:
		_apply_frame(freeze_frame)
	state = State.RESULT
	freeze_panel.visible = false
	sfx.update(sim, false, 0.0, 0, 0, 0)
	var ts := Time.get_datetime_string_from_system(false, true).substr(0, 16).replace("T", " ")
	var passed := sim.passed()
	var is_drill := mode == Mode.DRILL or mode == Mode.RULE
	if is_drill:
		var clean := sim.faults.is_empty() and sim.deductions.is_empty()
		store.drill_done(drill.id, sim.t_total, clean)
		store.add_history({"ts": ts, "mode": "drill", "title": drill.id, "score": 0, "load": 0, "unload": 0, "pass": sim.faults.is_empty(), "time": sim.t_total,
			"note": Lang.t("res.clean") if clean else (sim.faults[0].msg if not sim.faults.is_empty() else Lang.t("res.ded_count", [sim.deductions.size()]))})
	elif sim.step >= Sim.Step.TO_LOAD:
		if exam:
			store.data.runs = int(store.data.runs) + 1
			if passed:
				store.data.passes = int(store.data.passes) + 1
			if sim.faults.is_empty():
				store.data.best = maxi(int(store.data.best), sim.score())
		store.add_history({"ts": ts, "mode": "exam" if exam else "practice", "score": sim.score() if sim.faults.is_empty() else 0,
			"load": sim.part_score("load"), "unload": sim.part_score("unload"), "pass": passed, "time": sim.t_exam,
			"note": sim.faults[0].msg if not sim.faults.is_empty() else (Lang.t("res.ded_count", [sim.deductions.size()]) if not sim.deductions.is_empty() else Lang.t("res.clean"))})
	sfx.play("chime" if (passed or (is_drill and sim.faults.is_empty())) else "buzzer")
	sfx.buzz(120)
	controls.visible = false
	controls.enabled = false
	result_panel.visible = true
	for c in result_body.get_children():
		c.queue_free()
	_fill_sheet(result_body, passed, is_drill)
	var trail := PackedVector2Array()
	for i in range(0, frames.size(), 6):
		trail.append(frames[i][0])
	result_course.trail = trail
	result_course.fault_pos = sim.faults.map(func(f): return f.pos)
	result_course.queue_redraw()


const PAPER_INK := Color(0.1, 0.1, 0.12)
const PAPER_DIM := Color(0.1, 0.1, 0.12, 0.6)
const PAPER_RED := Color(0.78, 0.12, 0.1)
const PAPER_GREEN := Color(0.1, 0.5, 0.2)


func _fill_sheet(v: VBoxContainer, passed: bool, is_drill: bool) -> void:
	var head := UiKit.hbox(v, 16)
	var title := UiKit.label(head, Lang.t("sheet.title"), 24, PAPER_INK, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mode_name := Lang.t("mode.exam") if exam else (Lang.t("mode.practice") if not is_drill else Lang.t("mode.drill"))
	UiKit.label(head, "%s · %s / %s" % [mode_name, _clock(sim.t_exam if not is_drill else sim.t_total), _clock(course.time_limit)], 18, PAPER_DIM, false)
	UiKit.label(v, Lang.t("sheet.sub"), 15, PAPER_DIM, false)
	_sheet_rule(v)
	var verdict := ""
	var vcol := PAPER_INK
	if is_drill:
		verdict = Lang.t("res.drill_ok") if sim.faults.is_empty() else Lang.t("res.dq")
		vcol = PAPER_GREEN if sim.faults.is_empty() else PAPER_RED
	else:
		var unfinished := sim.faults.is_empty() and sim.step < Sim.Step.PARKED
		verdict = Lang.t("res.pass") if passed else (Lang.t("res.stopped") if unfinished else Lang.t("res.fail"))
		vcol = PAPER_GREEN if passed else (PAPER_DIM if unfinished else PAPER_RED)
	for part in ["load", "unload"]:
		var ph := UiKit.hbox(v, 8)
		var pl := UiKit.label(ph, Lang.t("sheet.part." + part), 20, PAPER_INK, false)
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiKit.label(ph, "%d / %d" % [sim.part_score(part), Sim.PART_MAX[part]], 20, PAPER_INK, false)
		var any := false
		for d in sim.deductions:
			if d.part != part:
				continue
			any = true
			var r := UiKit.hbox(v, 8)
			var pts := UiKit.label(r, "   -%d" % d.pts, 17, PAPER_RED, false)
			pts.custom_minimum_size = Vector2(60, 0)
			var m := ExamRules.measured(d)
			UiKit.label(r, d.msg + ("  (" + m + ")" if m != "" else "") + "  · " + Lang.t("res.estimate"), 17, PAPER_INK, false)
		if not any:
			UiKit.label(v, "   " + Lang.t("sheet.no_ded"), 16, PAPER_DIM, false)
	_sheet_rule(v)
	var checked := ExamRules.ROWS.filter(func(r): return r.checked).size()
	if sim.faults.is_empty():
		UiKit.label(v, Lang.t("sheet.dq_none", [checked, ExamRules.ROWS.size()]), 18, PAPER_GREEN, false)
	else:
		var f: Dictionary = sim.faults[0]
		var r := UiKit.hbox(v, 8)
		var dl := UiKit.label(r, Lang.t("res.dq"), 18, PAPER_RED, false)
		dl.custom_minimum_size = Vector2(60, 0)
		var m := ExamRules.measured(f)
		UiKit.para(r, "%s%s  ·  %s  (%s)" % [f.msg, ("  " + m) if m != "" else "", ExamRules.cite(f.code), _clock(f.t)], 18, PAPER_INK, 680)
		UiKit.label(v, Lang.t("sheet.dq_rule"), 15, PAPER_DIM, false)
	_sheet_rule(v)
	var tot := UiKit.hbox(v, 12)
	var tl := UiKit.label(tot, Lang.t("sheet.total"), 22, PAPER_INK, false)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.label(tot, "%d" % (sim.score() if sim.faults.is_empty() else 0), 40, PAPER_INK, false)
	var pm := UiKit.label(tot, Lang.t("sheet.pass_mark", [Sim.PASS_MARK]), 17, PAPER_DIM, false)
	pm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stamp := UiKit.label(tot, verdict, 40, vcol, false)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.spacer(v, 6)
	var rr := UiKit.hbox(v, 12)
	UiKit.button(rr, Lang.t("res.again"), func(): _start(mode), ACCENT, Vector2(200, 54), 20)
	UiKit.button(rr, Lang.t("res.replay"), _start_replay, Color(0.25, 0.45, 0.8), Vector2(170, 54), 20)
	UiKit.button(rr, Lang.t("res.menu"), _show_menu, Color(0.25, 0.26, 0.28), Vector2(150, 54), 20)


func _sheet_rule(v: VBoxContainer) -> void:
	UiKit.rule(v, Color(0.1, 0.1, 0.12, 0.35))


# ---------- replay ----------
func _start_replay() -> void:
	if frames.is_empty():
		return
	state = State.REPLAY
	result_panel.visible = false
	replay_bar.visible = true
	replay_from = 0
	if not sim.faults.is_empty():
		var ft: float = sim.faults[0].t
		for i in frames.size():
			if frames[i][9] >= ft - 5.0:
				replay_from = i
				break
	replay_i = replay_from
	replay_slider.min_value = 0
	replay_slider.max_value = frames.size() - 1
	cam_mode = Cam.CHASE


func _replay_step(dt: float) -> void:
	replay_i += dt * 60.0
	if replay_i >= frames.size():
		replay_i = replay_from
	_slider_lock = true
	replay_slider.value = replay_i
	_slider_lock = false
	_apply_frame(int(replay_i))


func _apply_frame(i: int) -> void:
	if frames.is_empty():
		return
	var f: Array = frames[clampi(i, 0, frames.size() - 1)]
	sim.pos = f[0]
	sim.heading = f[1]
	sim.steer = f[2]
	sim.lift = f[3]
	sim.tilt = f[4]
	sim.pallet_pos = f[5]
	sim.pallet_heading = f[6]
	sim.pallet_base = f[7]
	sim.pallet_fallen = f[8]
	sim.t_exam = f[9]


func _end_replay() -> void:
	replay_bar.visible = false
	replay_i = frames.size() - 1
	_apply_frame(int(replay_i))
	state = State.RESULT
	result_panel.visible = true


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			AudioServer.set_bus_mute(0, true)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			AudioServer.set_bus_mute(0, false)


# ---------- screenshots (debug builds only) ----------
# -- shot=path scene=menu|cab|chase|side|top|result|freeze|icon|drills|rules|records|settings
#    [stop=n] [mode=exam] [tab=n] [rule=rN] [lang=en]
func _setup_shot() -> void:
	var scene: String = _args.get("scene", "menu")
	if scene in ["drills", "rules", "records", "settings"]:
		_open(scene)
	elif scene == "freeze":
		_start_rule(_args.get("rule", "r14"))
		var how: Dictionary = {"r14": {lift = 1.0}, "r15": {lift = -1.0}, "r18": {lift = 1.0}, "r12": {lift = -1.0}, "r13": {lift = -1.0}}.get(drill.rule, {throttle = 0.5})
		sim.gear = 1 if how.has("throttle") else 0
		for i in 60 * 15:
			sim.update(1.0 / 60.0, how)
			_record()
			if not sim.faults.is_empty():
				_faults_seen = 1
				_freeze(sim.faults[0], true)
				break
		set_physics_process(false)
	elif scene != "menu":
		_start(Mode.EXAM if _args.get("mode", "practice") == "exam" else Mode.PRACTICE)
		var stop_at: int = int(_args.get("stop", "2"))
		var ap = load("res://tests/autopilot.gd").new(sim)
		var T = load("res://tests/test_sim.gd")
		T.run_until(sim, ap, stop_at)
		controls.seatbelt = sim.seatbelt
		controls.park_brake = sim.park_brake
		controls.gear = sim.gear
		controls.wheel_rot = -sim.steer * TAU * Controls.WHEEL_TURNS
		controls.show_steer(sim.steer)
		state = State.RUN
		toast.text = ""
		big.text = ""
		match scene:
			"cab": cam_mode = Cam.CAB
			"chase": cam_mode = Cam.CHASE
			"side": cam_mode = Cam.SIDE
			"top": cam_mode = Cam.TOP
			"result":
				sim.done = true
				for q in ap.log_points:
					frames.append([q, 0.0, 0.0, 0.0, 0.0, Vector2.ZERO, 0.0, 0.0, false, sim.t_exam])
				_show_result()
			"icon":
				ui.visible = false
				marker.visible = false
				cam_mode = Cam.CHASE
		_sync_controls_buttons()
		set_physics_process(false)
		for i in 60:
			_update_camera(1.0)
		if scene == "icon":
			set_process(false)
			_sync_models(0.0)
			var r := World.v3(sim.right())
			var f := World.v3(sim.dir())
			var c := World.v3(sim.pos) + f * 0.4 + Vector3(0, 1.1, 0)
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 38.0
			cam.global_position = c + f * 3.6 - r * 3.4 + Vector3(0, 1.2, 0)
			cam.look_at(c, Vector3.UP)
			RenderingServer.frame_post_draw.connect(func():
				if _shot_frames <= 0: return
				_shot_frames -= 1
				if _shot_frames == 0: _take_shot(), CONNECT_DEFERRED)
	_shot_frames = 20


func _take_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_args.shot)
	get_tree().quit()
