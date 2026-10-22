extends Node3D
## 지게차 실기 3D — 메인: 장면, UI, 상태(메뉴/주행/결과/리플레이), 소리.

enum State { MENU, RUN, RESULT, REPLAY }
enum Cam { CAB, CHASE, SIDE, TOP }
enum Mode { PRACTICE, EXAM, DRILL }
const CAM_NAMES := ["운전석", "뒤에서", "포크 옆", "위에서"]

const INK := UiKit.INK
const ACCENT := UiKit.ACCENT
const RED := UiKit.RED
const GREEN := UiKit.GREEN
const SUPPORT_URL := "https://binibinibin123.github.io/gentive-app-support/forklift-sim/support.html"

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

# 리플레이
var frames: Array = []
var replay_i := 0.0
var replay_from := 0

# UI
var ui: Control
var controls: Controls
var hud: Label
var step_label: Label
var step_dots: Control
var gauge: Control
var toast: Label
var toast_t := 0.0
var minimap: Control
var menu_panel: Control
var result_panel: Control
var result_body: VBoxContainer
var result_course: CourseView
var replay_bar: Control
var screens := {}          # name -> root Control
var _faults_seen := 0
var _deduct_seen := 0
var store := Store.new()
var iap: Iap
var sfx: Sfx
var exam_btn: Button
var unlock_btn: Button
var restore_btn: Button
var stats_label: Label
var unlock_panel: Control
var unlock_text: Label
var _args := {}
var _shot_frames := -1
var _menu_angle := 0.6


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	store.load_data()
	iap = Iap.new()
	add_child(iap)
	iap.changed.connect(func(_on): _refresh_lock())
	iap.price_known.connect(func(_p): _refresh_lock())
	iap.failed.connect(func(): _toast("구매를 마치지 못했어요. 잠시 뒤 다시 해 주세요.", Color(1, 0.8, 0.4)))
	iap.setup(store, _args.has("locked"))
	sfx = Sfx.new()
	add_child(sfx)
	_apply_settings()
	course = Course.load_default()
	drills = Drills.list(course)
	sim = Sim.new(course, true)
	_build_scene()
	_build_ui()
	_refresh_lock()
	_show_menu()
	if _args.has("shot"):
		_setup_shot()


func _apply_settings() -> void:
	sfx.enabled = bool(store.data.sound)
	sfx.haptics = bool(store.data.haptics)
	if controls:
		controls.sens = float(store.data.steer_sens)


# ---------- 장면 ----------
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

	# 위 가운데: 시간·단계·진행 점
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
	gauge.size = Vector2(150, 190)
	gauge.draw.connect(_draw_gauge)
	ui.add_child(gauge)

	toast = UiKit.label(ui, "", 30, RED)
	toast.set_anchors_preset(Control.PRESET_CENTER)
	toast.position = Vector2(-400, -120)
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
	_build_unlock()
	replay_bar = HBoxContainer.new()
	replay_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	replay_bar.position = Vector2(-140, -100)
	ui.add_child(replay_bar)
	UiKit.ghost(replay_bar, "리플레이 닫기", _end_replay, Vector2(220, 56))


func _build_menu() -> void:
	menu_panel = Control.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(menu_panel)
	# 왼쪽 그라데이션 띠
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.55)
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.custom_minimum_size = Vector2(600, 0)
	shade.size = Vector2(600, 720)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_panel.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 20)
	menu_panel.add_child(margin)
	var mv := UiKit.vbox(margin, 8)
	var kicker := UiKit.label(mv, "지게차운전기능사 실기", 19, ACCENT)
	var title := UiKit.label(mv, "지게차 실기 3D", 54)
	UiKit.para(mv, "실제 코스 순서대로 운전하고, 실격·감점 기준으로 채점받는 연습장", 20, UiKit.DIM, 540)
	UiKit.spacer(mv, 4)
	stats_label = UiKit.label(mv, "", 19, Color(1, 1, 1, 0.8))
	UiKit.spacer(mv, 4)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	mv.add_child(grid)
	var bs := Vector2(250, 66)
	UiKit.button(grid, "연습 코스", _start_practice, ACCENT, bs)
	exam_btn = UiKit.button(grid, "모의시험 4분", _start_exam, Color(0.95, 0.42, 0.2), bs)
	UiKit.button(grid, "단계 드릴", func(): _open("drills"), UiKit.BLUE, bs)
	UiKit.button(grid, "학습 노트", func(): _open("learn"), Color(0.55, 0.85, 0.6), bs)
	UiKit.ghost(grid, "기록", func(): _open("records"), bs)
	UiKit.ghost(grid, "설정", func(): _open("settings"), bs)
	UiKit.spacer(mv, 2)
	var row2 := UiKit.hbox(mv, 10)
	unlock_btn = UiKit.button(row2, "전체 해제", _buy, Color(0.45, 0.85, 0.5), Vector2(200, 50), 20)
	restore_btn = UiKit.ghost(row2, "구매 복원", func(): iap.restore(), Vector2(140, 50), 19)
	var link := LinkButton.new()
	link.text = "지원 · 개인정보 처리방침"
	link.add_theme_font_size_override("font_size", 16)
	link.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	link.pressed.connect(func(): OS.shell_open(SUPPORT_URL))
	link.visible = not OS.has_feature("toss")   # 토스 미니앱은 바깥 링크 금지
	mv.add_child(link)
	UiKit.para(mv, "실제 장비와 조작감은 다릅니다. 코스 순서와 실격·감점 기준을 몸에 익히는 용도예요.", 15, Color(1, 1, 1, 0.5), 520)
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_result() -> void:
	result_panel = Control.new()
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(result_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(center)
	var rp := UiKit.panel(center, UiKit.PANEL, 20, 24)
	var row := UiKit.hbox(rp, 26)
	result_body = UiKit.vbox(row, 8)
	result_body.custom_minimum_size = Vector2(640, 0)
	result_course = CourseView.new()
	result_course.setup(course, 18.0)
	result_course.show_dims = false
	result_course.show_routes = false
	row.add_child(result_course)


func _build_unlock() -> void:
	unlock_panel = CenterContainer.new()
	unlock_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(unlock_panel)
	var up := UiKit.panel(unlock_panel)
	var uv := UiKit.vbox(up, 16)
	var ut := UiKit.label(uv, "전체 해제", 36, ACCENT)
	ut.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_text = UiKit.para(uv, "", 23, INK, 720)
	unlock_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ur := UiKit.hbox(uv, 16, true)
	UiKit.button(ur, "해제하기", _buy, Color(0.45, 0.85, 0.5))
	UiKit.ghost(ur, "구매 복원", func(): iap.restore())
	UiKit.ghost(ur, "닫기", _show_menu)
	unlock_panel.visible = false


# ---------- 서브 화면 ----------
func _open(name: String) -> void:
	_close_screens()
	var s := UiKit.screen(ui, {"drills": "단계 드릴", "learn": "학습 노트", "records": "기록", "settings": "설정"}[name], _close_screens)
	screens[name] = s.root
	menu_panel.visible = false
	match name:
		"drills": _fill_drills(s.body)
		"learn": _fill_learn(s)
		"records": _fill_records(s.body)
		"settings": _fill_settings(s.body)
	sfx.play("click")


func _close_screens() -> void:
	for k in screens:
		screens[k].queue_free()
	screens.clear()
	menu_panel.visible = state == State.MENU


func _fill_drills(body: VBoxContainer) -> void:
	UiKit.para(body, "코스를 구간별로 잘라 반복합니다. 구간 끝에 닿으면 바로 결과가 나와요.", 19, UiKit.DIM, 1200)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	body.add_child(grid)
	for i in drills.size():
		var d: Dictionary = drills[i]
		var locked: bool = not d.free and not iap.unlocked
		var p := UiKit.panel(grid, Color(1, 1, 1, 0.06), 16, 18)
		p.custom_minimum_size = Vector2(470, 0)
		var v := UiKit.vbox(p, 6)
		var head := UiKit.hbox(v, 10)
		UiKit.label(head, "%d" % (i + 1), 30, ACCENT)
		var t := UiKit.label(head, d.title, 26)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if locked:
			UiKit.chip(head, "해제 필요", Color(1, 1, 1, 0.6), 14)
		UiKit.para(v, d.desc, 18, INK, 430)
		var rec: Dictionary = store.data.drills.get(d.id, {})
		var done := int(rec.get("done", 0))
		var info := "아직 안 해봤어요" if done == 0 else "%d회 · 무실격 %d회" % [done, int(rec.get("clean", 0))]
		if float(rec.get("best_time", -1.0)) >= 0:
			info += " · 최고 %s" % _clock(float(rec.best_time))
		UiKit.label(v, info, 16, UiKit.DIM, false)
		var sb := UiKit.button(v, "시작", _start_drill.bind(d), ACCENT if not locked else Color(1, 1, 1, 0.14), Vector2(200, 50), 20)
		sb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _fill_learn(s: Dictionary) -> void:
	var body: VBoxContainer = s.body
	var tabs := UiKit.hbox(s.head, 8)
	var pages := {}
	var names := ["시험 개요", "코스 순서", "실격 사유", "감점 항목", "코스 도면", "요령"]
	var first: String = names[int(_args.get("tab", "0"))]
	for n in names:
		var v := UiKit.vbox(body, 10)
		v.visible = n == first
		pages[n] = v
		var b := UiKit.ghost(tabs, n, func():
			for k in pages:
				pages[k].visible = k == n
			s.scroll.scroll_vertical = 0, Vector2(130, 46), 18)
	# 개요
	for item in Learn.OVERVIEW:
		var p := UiKit.panel(pages["시험 개요"], Color(1, 1, 1, 0.06), 14, 16)
		var h := UiKit.hbox(p, 16)
		var k := UiKit.label(h, item[0], 21, ACCENT, false)
		k.custom_minimum_size = Vector2(120, 0)
		UiKit.para(h, item[1], 20, INK, 1180)
	# 순서
	for item in Learn.ORDER:
		var p := UiKit.panel(pages["코스 순서"], Color(1, 1, 1, 0.06), 14, 16)
		var v := UiKit.vbox(p, 4)
		UiKit.label(v, item[0], 23, ACCENT, false)
		UiKit.para(v, item[1], 20, INK, 1300)
	# 실격
	UiKit.para(pages["실격 사유"], "하나라도 해당하면 그 자리에서 실격(불합격)입니다. 이 앱의 모의시험도 같은 기준으로 끝납니다.", 19, UiKit.DIM, 1300)
	for item in Learn.FAULTS:
		var h := UiKit.hbox(pages["실격 사유"], 12)
		UiKit.chip(h, item[1], RED, 15)
		var l := UiKit.para(h, item[0], 20, INK, 1150)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 감점
	UiKit.para(pages["감점 항목"], "실격은 아니지만 점수가 깎이는 항목. 상차 작업 45점, 하차 작업 55점에서 빼고 60점 이상이면 합격입니다.", 19, UiKit.DIM, 1300)
	for item in Learn.DEDUCTIONS:
		var h := UiKit.hbox(pages["감점 항목"], 12)
		UiKit.chip(h, "-%d" % item[1], ACCENT, 15)
		var l := UiKit.para(h, item[0], 20, INK, 1150)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 도면
	var cv := CourseView.new()
	cv.setup(course, 30.0)
	cv.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pages["코스 도면"].add_child(cv)
	UiKit.para(pages["코스 도면"], "파란 선이 전진 동선, 주황 선이 후진 동선입니다. 흰 선은 출발·도착선과 후진선, 노란 선은 밟으면 실격인 코스 경계선.", 18, UiKit.DIM, 1300)
	# 요령
	for i in Learn.TIPS.size():
		var h := UiKit.hbox(pages["요령"], 12)
		UiKit.label(h, "%d" % (i + 1), 24, ACCENT, false)
		var l := UiKit.para(h, Learn.TIPS[i], 20, INK, 1200)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _fill_records(body: VBoxContainer) -> void:
	var h: Array = store.data.history
	var runs := int(store.data.runs)
	var passes := int(store.data.passes)
	var row := UiKit.hbox(body, 14)
	_stat(row, "모의시험", "%d회" % runs)
	_stat(row, "합격", "%d회" % passes)
	_stat(row, "합격률", ("%d%%" % int(100.0 * passes / runs)) if runs > 0 else "-")
	_stat(row, "최고 점수", ("%d점" % int(store.data.best)) if int(store.data.best) >= 0 else "-")
	UiKit.spacer(body, 6)
	if h.is_empty():
		UiKit.para(body, "아직 기록이 없어요. 모의시험이나 연습 코스를 끝까지 돌면 여기에 쌓입니다.", 20, UiKit.DIM, 1200)
		return
	var head := UiKit.hbox(body, 0)
	for col in [["날짜", 230], ["모드", 110], ["결과", 110], ["점수", 100], ["상차", 90], ["하차", 90], ["시간", 100], ["비고", 400]]:
		var l := UiKit.label(head, col[0], 17, UiKit.DIM, false)
		l.custom_minimum_size = Vector2(col[1], 0)
	UiKit.rule(body)
	for e in h:
		var r := UiKit.hbox(body, 0)
		var passed := bool(e.get("pass", false))
		var cells := [
			[str(e.get("ts", "")), 230, INK],
			[{"exam": "모의시험", "practice": "연습", "drill": "드릴"}.get(e.get("mode", ""), "-") + ("" if e.get("mode", "") != "drill" else " · " + str(e.get("title", ""))), 110 if e.get("mode", "") != "drill" else 330, INK],
			["합격" if passed else "불합격", 110, GREEN if passed else RED],
			["%d" % int(e.get("score", 0)), 100, INK],
			["%d/45" % int(e.get("load", 0)), 90, INK],
			["%d/55" % int(e.get("unload", 0)), 90, INK],
			[_clock(float(e.get("time", 0))), 100, INK],
			[str(e.get("note", "")), 400, UiKit.DIM],
		]
		if e.get("mode", "") == "drill":
			cells.remove_at(5)
			cells.remove_at(4)
			cells.remove_at(3)
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
	_setting_toggle(body, "효과음", "엔진·후진 경고음·유압음·경음기", "sound")
	_setting_toggle(body, "진동", "실격·감점·출발 신호 때 짧게 진동 (휴대폰)", "haptics")
	# 핸들 감도
	var p := UiKit.panel(body, Color(1, 1, 1, 0.06), 14, 16)
	var h := UiKit.hbox(p, 16)
	var v := UiKit.vbox(h, 2)
	v.custom_minimum_size = Vector2(520, 0)
	UiKit.label(v, "핸들 감도", 22, INK, false)
	UiKit.label(v, "낮으면 핸들을 많이 돌려야 하고, 높으면 조금만 돌려도 크게 꺾입니다.", 16, UiKit.DIM, false)
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
	# 기본 시점
	var p2 := UiKit.panel(body, Color(1, 1, 1, 0.06), 14, 16)
	var h2 := UiKit.hbox(p2, 16)
	var v2 := UiKit.vbox(h2, 2)
	v2.custom_minimum_size = Vector2(520, 0)
	UiKit.label(v2, "시작 시점", 22, INK, false)
	UiKit.label(v2, "주행을 시작할 때의 카메라. 주행 중에도 버튼으로 바꿀 수 있어요.", 16, UiKit.DIM, false)
	var ob := OptionButton.new()
	for n in CAM_NAMES:
		ob.add_item(n)
	ob.selected = int(store.data.cam)
	ob.add_theme_font_size_override("font_size", 20)
	ob.custom_minimum_size = Vector2(200, 46)
	ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ob.item_selected.connect(func(i):
		store.data.cam = i
		store.save())
	h2.add_child(ob)
	UiKit.spacer(body, 6)
	UiKit.para(body, "키보드(데스크톱): W 가속 · S 브레이크 · A/D 핸들 · 1/2/3 전진·중립·후진 · R/F 리프트 · T/G 틸트 · B 안전벨트 · P 주차 브레이크 · C 시점 · V 뒤 보기 · H 경음기 · Enter 출발 신호", 16, UiKit.DIM, 1300)


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
		b.text = "켜짐" if on else "꺼짐"
		b.modulate = Color(1, 1, 1, 1.0 if on else 0.45)
	b.pressed.connect(func():
		store.data[key] = not bool(store.data[key])
		store.save()
		_apply_settings()
		refresh.call())
	refresh.call()


# ---------- 메뉴·시작 ----------
func _refresh_lock() -> void:
	if not unlock_btn:
		return
	var price := iap.price if iap.price != "" else ""
	unlock_btn.visible = not iap.unlocked
	restore_btn.visible = not iap.unlocked
	unlock_btn.text = ("전체 해제 " + price).strip_edges()
	exam_btn.text = "모의시험 4분" if iap.unlocked else "모의시험 (해제 필요)"
	var best := int(store.data.best)
	var runs := int(store.data.runs)
	stats_label.text = ("모의시험 최고 %d점 · %d회 중 합격 %d회" % [best, runs, int(store.data.passes)]) if runs > 0 else "첫 모의시험을 기다리고 있어요"
	if iap.unlocked and unlock_panel.visible:
		unlock_panel.visible = false
		_toast("전체 해제됐어요. 고마워요!", GREEN)
		_show_menu()


func _buy() -> void:
	iap.buy()


func _show_unlock(why: String) -> void:
	state = State.RESULT
	controls.visible = false
	controls.enabled = false
	menu_panel.visible = false
	result_panel.visible = false
	unlock_panel.visible = true
	var price := (" (" + iap.price + ")") if iap.price != "" else ""
	unlock_text.text = why + "\n\n한 번 결제%s로 연습 코스 전체, 단계 드릴 6종, 4분 모의시험 채점, 실격 지점 리플레이를 계속 쓸 수 있어요. 광고나 구독은 없어요." % price


func _show_menu() -> void:
	state = State.MENU
	_close_screens()
	unlock_panel.visible = false
	_refresh_lock()
	menu_panel.visible = true
	result_panel.visible = false
	replay_bar.visible = false
	controls.visible = false
	controls.enabled = false
	sim.reset()
	sim.lift = 0.0
	frames.clear()
	cam_mode = Cam.CHASE
	sfx.stop_all()


func _start_practice() -> void:
	_start(Mode.PRACTICE)


func _start_exam() -> void:
	if not iap.unlocked:
		_show_unlock("모의시험은 전체 해제 후 쓸 수 있어요.")
		return
	_start(Mode.EXAM)


func _start_drill(d: Dictionary) -> void:
	if not d.free and not iap.unlocked:
		_show_unlock("이 드릴은 전체 해제 후 쓸 수 있어요. 1·2번 드릴은 무료예요.")
		return
	drill = d
	_start(Mode.DRILL)


func _start(m: Mode) -> void:
	_close_screens()
	unlock_panel.visible = false
	mode = m
	exam = m == Mode.EXAM
	sim.exam = exam
	if m == Mode.DRILL:
		sim.start_drill(drill)
	else:
		sim.reset()
	controls.reset()
	controls.seatbelt = sim.seatbelt
	controls.park_brake = sim.park_brake
	frames.clear()
	_faults_seen = 0
	_deduct_seen = 0
	toast.text = ""
	state = State.RUN
	menu_panel.visible = false
	result_panel.visible = false
	replay_bar.visible = false
	controls.visible = true
	controls.enabled = true
	controls.set_button("signal", "시작 신호" if exam else "")
	if not exam:
		sim.give_signal()
	cam_mode = int(store.data.cam) as Cam
	look_back = false
	_sync_controls_buttons()
	if m == Mode.DRILL:
		_toast(drill.tip, Color(0.85, 0.95, 1.0), 6.0)
	sfx.play("click")


func _sync_controls_buttons() -> void:
	controls.set_button("seatbelt", "안전벨트 " + ("O" if controls.seatbelt else "X"), controls.seatbelt)
	controls.set_button("park", "주차브레이크 " + ("ON" if controls.park_brake else "OFF"), controls.park_brake)
	controls.set_button("camera", CAM_NAMES[cam_mode])
	controls.set_button("look", "앞 보기" if look_back else "뒤 보기", look_back)


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
		"signal":
			if state == State.RUN and exam and not sim.signal_given:
				sim.give_signal()
				sfx.play("whistle")
				sfx.buzz(80)
				controls.set_button("signal", "")
				_toast("삐익! 1분 안에 출발선을 지나세요", GREEN)
	_sync_controls_buttons()


func _toast(t: String, c := RED, secs := 3.0) -> void:
	toast.text = t
	toast.add_theme_color_override("font_color", c)
	toast_t = secs


# ---------- 루프 ----------
func _physics_process(dt: float) -> void:
	if state != State.RUN:
		return
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
	frames.append([sim.pos, sim.heading, sim.steer, sim.lift, sim.tilt, sim.pallet_pos, sim.pallet_heading, sim.pallet_base, sim.pallet_fallen, sim.t_exam])
	while _faults_seen < sim.faults.size():
		var f: Dictionary = sim.faults[_faults_seen]
		_faults_seen += 1
		_toast(("실격: " if exam else "실격 사유: ") + f.msg)
		sfx.play("buzzer")
		sfx.buzz(220)
	while _deduct_seen < sim.deductions.size():
		var d: Dictionary = sim.deductions[_deduct_seen]
		_deduct_seen += 1
		_toast("감점 -%d: %s" % [d.pts, d.msg], ACCENT)
		sfx.play("thud")
		sfx.buzz(60)
	if sim.step != prev_step and not sim.done:
		sfx.play("chime")
		sfx.buzz(40)
	sfx.update(sim, true, dt, controls.lift, controls.tilt, controls.throttle)
	if sim.done:
		_show_result()
	elif mode != Mode.DRILL and not iap.unlocked and sim.step >= Sim.Step.UNLOADED:
		sfx.play("chime")
		_show_unlock("잘했어요! 무료 연습은 하역까지예요. 후진선 터치부터 주차까지 남은 코스는 전체 해제 후 이어서 연습할 수 있어요.")


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
	if _shot_frames >= 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			_take_shot()


## 3D 모델 위치. 들고 있는 팔레트는 마스트 틸트만큼 같이 기울인다.
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
		Sim.Step.LOADED: p = World.v3(course.unload_target, 1.2)
		Sim.Step.UNLOADED: p = World.v3(Vector2(course.back_line_x, course.unload_target.y), 1.2)
		Sim.Step.TOUCHED: p = World.v3(course.unload_target, 1.2)
		Sim.Step.RETURNED: p = World.v3(Vector2(0, course.start_line_y), 1.2)
		_: show = false
	marker.visible = show
	marker.position = p + Vector3(0, sin(t * 3.0) * 0.12, 0)


func _update_camera(dt: float) -> void:
	var fwd := World.v3(sim.dir())
	var base := World.v3(sim.pos)
	var k := 1.0 - exp(-dt * 6.0)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
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
			cam.size = course.bounds().size.y + 4.0
			cam.global_position = World.v3(c, 30.0)
			cam.rotation = Vector3(-PI / 2, 0, 0)
	if state == State.MENU:
		# 메뉴: 출발 위치의 지게차를 천천히 도는 카메라 (오른쪽 화면에 보이게 조금 비껴서)
		_menu_angle += dt * 0.12
		var c2 := base + Vector3(0, 1.1, 0)
		var eye := c2 + Vector3(cos(_menu_angle) * 7.5, 2.4, sin(_menu_angle) * 7.5)
		cam.global_position = eye
		cam.look_at(c2, Vector3.UP)
		cam.fov = 50.0
		cam.h_offset = -2.2


func _update_hud(dt: float) -> void:
	var playing := state == State.RUN or state == State.REPLAY
	hud.visible = playing
	step_label.visible = state == State.RUN
	step_dots.visible = state == State.RUN and mode != Mode.DRILL
	gauge.visible = playing
	minimap.visible = playing
	cam.h_offset = 0.0 if state != State.MENU else cam.h_offset
	if toast_t > 0:
		toast_t -= dt
		if toast_t <= 0:
			toast.text = ""
	if not playing:
		return
	var t := sim.t_exam
	if state == State.REPLAY:
		hud.text = "리플레이  %s" % _clock(t)
	elif exam:
		if not sim.signal_given:
			hud.text = "모의시험 · 준비"
		elif sim.step == Sim.Step.READY:
			hud.text = "출발까지 %d초" % int(ceil(course.start_limit - sim.t_signal))
		else:
			hud.text = "남은 시간 %s" % _clock(maxf(course.time_limit - t, 0.0))
	elif mode == Mode.DRILL:
		hud.text = "드릴 · %s · %s" % [drill.title, _clock(sim.t_total)]
	else:
		hud.text = "연습 · %s" % _clock(t)
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


func _draw_gauge() -> void:
	var f := gauge.get_theme_default_font()
	var g := gauge
	g.draw_rect(Rect2(Vector2.ZERO, g.size), Color(0.05, 0.06, 0.08, 0.55))
	# 포크 높이 막대 (0~100cm, 20~30 초록 띠, 50 빨간 선)
	var bx := 14.0
	var by := 14.0
	var bh := g.size.y - 28.0
	g.draw_rect(Rect2(bx, by, 16, bh), Color(1, 1, 1, 0.12))
	var y_of := func(h: float) -> float: return by + bh - clampf(h, 0.0, 1.0) * bh
	g.draw_rect(Rect2(bx, y_of.call(0.3), 16, y_of.call(0.2) - y_of.call(0.3)), Color(GREEN, 0.5))
	g.draw_line(Vector2(bx - 3, y_of.call(0.5)), Vector2(bx + 19, y_of.call(0.5)), RED, 2.0)
	var lc := INK
	var z := sim.zone()
	if z == "travel" and (sim.lift < 0.15 or sim.lift > 0.35):
		lc = ACCENT
	if z == "travel" and sim.lift > 0.45:
		lc = RED
	var ly: float = y_of.call(sim.lift)
	g.draw_rect(Rect2(bx - 2, ly - 3, 20, 6), lc)
	g.draw_string(f, Vector2(40, 32), "포크 %d cm" % roundi(sim.lift * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, lc)
	g.draw_string(f, Vector2(40, 66), "틸트 %+.0f°" % sim.tilt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK if not sim.carried or sim.tilt >= 1.0 else ACCENT)
	g.draw_string(f, Vector2(40, 100), "%.1f km/h" % (absf(sim.speed) * 3.6), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	var g_names := {1: "전진", 0: "중립", -1: "후진"}
	g.draw_string(f, Vector2(40, 134), g_names[sim.gear], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ACCENT if sim.gear != 0 else UiKit.DIM)
	g.draw_string(f, Vector2(40, 168), "뒤로 젖힘" if sim.tilt >= 1.0 else ("앞으로 숙임" if sim.tilt <= -1.0 else "수직"), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiKit.DIM)


static func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# ---------- 결과·리플레이 ----------
func _show_result() -> void:
	state = State.RESULT
	sfx.update(sim, false, 0.0, 0, 0, 0)
	var ts := Time.get_datetime_string_from_system(false, true).substr(0, 16).replace("T", " ")
	var passed := sim.passed()
	if mode == Mode.DRILL:
		var clean := sim.faults.is_empty() and sim.deductions.is_empty()
		store.drill_done(drill.id, sim.t_total, clean)
		store.add_history({"ts": ts, "mode": "drill", "title": drill.title, "score": 0, "load": 0, "unload": 0, "pass": sim.faults.is_empty(), "time": sim.t_total,
			"note": "무실격·무감점" if clean else ("감점 %d" % sim.deductions.size() if sim.faults.is_empty() else sim.faults[0].msg)})
	elif sim.step >= Sim.Step.TO_LOAD:
		if exam:
			store.data.runs = int(store.data.runs) + 1
			if passed:
				store.data.passes = int(store.data.passes) + 1
			if sim.faults.is_empty():
				store.data.best = maxi(int(store.data.best), sim.score())
		store.add_history({"ts": ts, "mode": "exam" if exam else "practice", "score": sim.score() if sim.faults.is_empty() else 0,
			"load": sim.part_score("load"), "unload": sim.part_score("unload"), "pass": passed, "time": sim.t_exam,
			"note": sim.faults[0].msg if not sim.faults.is_empty() else ("감점 %d건" % sim.deductions.size() if not sim.deductions.is_empty() else "무감점")})
	sfx.play("chime" if (passed or (mode == Mode.DRILL and sim.faults.is_empty())) else "buzzer")
	sfx.buzz(120)
	controls.visible = false
	controls.enabled = false
	result_panel.visible = true
	for c in result_body.get_children():
		c.queue_free()
	var v := result_body
	var head := UiKit.hbox(v, 16)
	if mode == Mode.DRILL:
		var ok := sim.faults.is_empty()
		UiKit.label(head, "드릴 완료" if ok else "실격", 44, GREEN if ok else RED)
		var sub := UiKit.label(head, "%s · %s" % [drill.title, _clock(sim.t_total)], 22, UiKit.DIM, false)
		sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		var unfinished := sim.faults.is_empty() and sim.step < Sim.Step.PARKED
		UiKit.label(head, "합격" if passed else ("중단" if unfinished else "불합격"), 44, GREEN if passed else (UiKit.DIM if unfinished else RED))
		var sub := UiKit.label(head, "%s · %s" % ["모의시험" if exam else "연습 코스", _clock(sim.t_exam)], 22, UiKit.DIM, false)
		sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if mode != Mode.DRILL:
		var sheet := UiKit.hbox(v, 10)
		_score_box(sheet, "상차 작업", sim.part_score("load"), 45)
		_score_box(sheet, "하차 작업", sim.part_score("unload"), 55)
		_score_box(sheet, "합계", sim.score() if sim.faults.is_empty() else 0, 100, true)
		if not sim.faults.is_empty():
			UiKit.label(v, "실격이면 점수와 상관없이 불합격입니다.", 16, UiKit.DIM, false)
	UiKit.rule(v)
	var list := UiKit.vbox(v, 4)
	for f in sim.faults:
		var h := UiKit.hbox(list, 10)
		UiKit.chip(h, "실격", RED, 15)
		var l := UiKit.para(h, "%s  (%s)" % [f.msg, _clock(f.t)], 19, INK, 540)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for d in sim.deductions:
		var h := UiKit.hbox(list, 10)
		UiKit.chip(h, "-%d" % d.pts, ACCENT, 15)
		var l := UiKit.para(h, d.msg, 19, INK, 540)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if sim.faults.is_empty() and sim.deductions.is_empty():
		UiKit.label(list, "감점 없이 끝냈어요. 실전에서도 이 속도면 충분합니다.", 20, GREEN, false)
	elif not sim.faults.is_empty() and sim.step < Sim.Step.PARKED:
		UiKit.label(list, "리플레이로 실격 5초 전부터 다시 볼 수 있어요.", 16, UiKit.DIM, false)
	UiKit.spacer(v, 4)
	var rr := UiKit.hbox(v, 12)
	UiKit.button(rr, "다시 하기", func(): _start(mode), ACCENT, Vector2(200, 58))
	UiKit.button(rr, "리플레이", _start_replay, UiKit.BLUE, Vector2(170, 58))
	UiKit.ghost(rr, "메뉴", _show_menu, Vector2(140, 58))
	# 궤적 지도
	var trail := PackedVector2Array()
	for i in range(0, frames.size(), 6):
		trail.append(frames[i][0])
	result_course.trail = trail
	result_course.fault_pos = sim.faults.map(func(f): return f.pos)
	result_course.queue_redraw()


func _score_box(parent: Node, name: String, got: int, max_pts: int, total := false) -> void:
	var p := UiKit.panel(parent, Color(1, 1, 1, 0.06) if not total else Color(ACCENT, 0.16), 14, 12)
	p.custom_minimum_size = Vector2(200, 0)
	var vb := UiKit.vbox(p, 0)
	UiKit.label(vb, name, 16, UiKit.DIM, false)
	var h := UiKit.hbox(vb, 4)
	UiKit.label(h, "%d" % got, 36, ACCENT if total else INK, false)
	var m := UiKit.label(h, "/ %d" % max_pts, 18, UiKit.DIM, false)
	m.size_flags_vertical = Control.SIZE_SHRINK_END


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
	cam_mode = Cam.CHASE


func _replay_step(dt: float) -> void:
	replay_i += dt * 60.0
	if replay_i >= frames.size():
		replay_i = replay_from
	var f: Array = frames[int(replay_i)]
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
	_replay_step(0.0)
	state = State.RESULT
	result_panel.visible = true


## 앱이 뒤로 가면 소리를 바로 멈추고, 돌아오면 다시 켠다.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			AudioServer.set_bus_mute(0, true)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			AudioServer.set_bus_mute(0, false)


# ---------- 스크린샷(개발용): -- shot=경로 scene=menu|cab|chase|side|top|result|icon|drills|learn|records|settings|unlock ----------
func _setup_shot() -> void:
	var scene: String = _args.get("scene", "menu")
	if scene in ["drills", "learn", "records", "settings"]:
		_open(scene)
	elif scene == "unlock":
		_show_unlock("모의시험은 전체 해제 후 쓸 수 있어요.")
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
		_sync_controls_buttons()
		state = State.RUN
		toast.text = ""
		match scene:
			"cab": cam_mode = Cam.CAB
			"chase": cam_mode = Cam.CHASE
			"side": cam_mode = Cam.SIDE
			"top": cam_mode = Cam.TOP
			"result":
				sim.done = true
				for q in ap.log_points:
					frames.append([q, 0.0, 0.0, 0.0, 0.0, Vector2.ZERO, 0.0, 0.0, false, 0.0])
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
