extends Node3D
## 지게차 실기 3D: 연습 모드 / 모의시험, 채점, 리플레이.

enum State { MENU, RUN, RESULT, REPLAY }
enum Cam { CAB, CHASE, SIDE, TOP }
const CAM_NAMES := ["운전석", "뒤에서", "포크 옆", "위에서"]

const INK := Color(0.96, 0.96, 0.94)
const PANEL := Color(0.05, 0.06, 0.07, 0.72)
const ACCENT := Color(1.0, 0.68, 0.1)
const RED := Color(0.95, 0.3, 0.25)
const GREEN := Color(0.35, 0.85, 0.45)

var course: Course
var sim: Sim
var world: World
var fork: ForkliftView
var cam: Camera3D
var cam_mode := Cam.CAB
var look_back := false
var marker: Node3D
var state := State.MENU
var exam := false

# 리플레이 기록
var frames: Array = []
var replay_i := 0.0
var replay_from := 0

# UI
var ui: Control
var controls: Controls
var hud: Label
var step_label: Label
var gauge: Label
var toast: Label
var toast_t := 0.0
var minimap: Control
var menu_panel: Control
var result_panel: Control
var result_text: RichTextLabel
var replay_bar: Control
var _faults_seen := 0
var store := Store.new()
var iap: Iap
var sound_btn: Button
var exam_btn: Button
var unlock_btn: Button
var restore_btn: Button
var best_label: Label
var unlock_panel: Control
var unlock_text: Label
var sfx := {}
const SUPPORT_URL := "https://binibinibin123.github.io/gentive-app-support/forklift-sim/support.html"
var _args := {}
var _shot_frames := -1


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
	_make_sounds()
	course = Course.load_default()
	sim = Sim.new(course, true)
	_build_scene()
	_build_ui()
	_refresh_lock()
	_show_menu()
	if _args.has("shot"):
		_setup_shot()


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
func _label(parent: Control, fs: int, col := INK) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _panel(parent: Control, c := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(22)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _button(parent: Control, text: String, cb: Callable, col := ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 68)
	b.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(10)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var sp := sb.duplicate()
	sp.bg_color = col.darkened(0.2)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.08, 0.08))
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.08))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	# 위쪽 가운데: 시간·단계
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-330, 14)
	top.custom_minimum_size = Vector2(660, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top)
	hud = _label(top, 34)
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label = _label(top, 22, Color(0.85, 0.95, 1.0))
	step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_label.custom_minimum_size = Vector2(660, 0)

	# 포크 높이·틸트·속도 계기
	gauge = _label(ui, 24)
	gauge.position = Vector2(20, 150)

	toast = _label(ui, 30, RED)
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

	# 메뉴
	menu_panel = Control.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_panel.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_panel.add_child(center)
	var mp := _panel(center)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 16)
	mp.add_child(mv)
	var title := _label(mv, 48, ACCENT)
	title.text = "지게차 실기 3D"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label(mv, 22)
	sub.text = "지게차운전기능사 실기 코스 순서와 감점 포인트 익히기"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_child(row)
	_button(row, "연습 모드", _start.bind(false), Color(0.55, 0.85, 1.0))
	exam_btn = _button(row, "모의시험 (4분)", _start.bind(true))
	best_label = _label(mv, 20, Color(1, 1, 1, 0.8))
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 20)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_child(row2)
	unlock_btn = _button(row2, "전체 해제", _buy, Color(0.45, 0.85, 0.5))
	restore_btn = _button(row2, "구매 복원", func(): iap.restore(), Color(0.8, 0.8, 0.8))
	sound_btn = _button(row2, "", _toggle_sound, Color(0.8, 0.8, 0.8))
	_sync_sound_btn()
	var link := LinkButton.new()
	link.text = "지원 · 개인정보 처리방침"
	link.add_theme_font_size_override("font_size", 18)
	link.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	link.pressed.connect(func(): OS.shell_open(SUPPORT_URL))
	link.visible = not OS.has_feature("toss")   # 토스 미니앱은 바깥 링크 금지
	mv.add_child(link)
	var note := _label(mv, 17, Color(1, 1, 1, 0.6))
	note.text = "실제 장비와 조작감이 다릅니다. 코스 순서와 실격·감점 기준을 미리 익히는 용도로 쓰세요."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 결과
	result_panel = CenterContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(result_panel)
	var rp := _panel(result_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 14)
	rp.add_child(rv)
	result_text = RichTextLabel.new()
	result_text.bbcode_enabled = true
	result_text.fit_content = true
	result_text.custom_minimum_size = Vector2(720, 0)
	result_text.add_theme_font_size_override("normal_font_size", 24)
	result_text.add_theme_font_size_override("bold_font_size", 44)
	rv.add_child(result_text)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 16)
	rr.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_child(rr)
	_button(rr, "다시 하기", func(): _start(exam))
	_button(rr, "리플레이", _start_replay, Color(0.55, 0.85, 1.0))
	_button(rr, "메뉴", _show_menu, Color(0.8, 0.8, 0.8))

	# 전체 해제 안내
	unlock_panel = CenterContainer.new()
	unlock_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(unlock_panel)
	var up := _panel(unlock_panel)
	var uv := VBoxContainer.new()
	uv.add_theme_constant_override("separation", 16)
	up.add_child(uv)
	var ut := _label(uv, 36, ACCENT)
	ut.text = "전체 해제"
	ut.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_text = _label(uv, 23)
	unlock_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unlock_text.custom_minimum_size = Vector2(720, 0)
	unlock_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ur := HBoxContainer.new()
	ur.add_theme_constant_override("separation", 16)
	ur.alignment = BoxContainer.ALIGNMENT_CENTER
	uv.add_child(ur)
	_button(ur, "해제하기", _buy, Color(0.45, 0.85, 0.5))
	_button(ur, "구매 복원", func(): iap.restore(), Color(0.8, 0.8, 0.8))
	_button(ur, "닫기", _show_menu, Color(0.8, 0.8, 0.8))
	unlock_panel.visible = false

	replay_bar = HBoxContainer.new()
	replay_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	replay_bar.position = Vector2(-140, -100)
	ui.add_child(replay_bar)
	_button(replay_bar, "리플레이 닫기", _end_replay, Color(0.8, 0.8, 0.8))


func _refresh_lock() -> void:
	if not unlock_btn:
		return
	var price := iap.price if iap.price != "" else ""
	unlock_btn.visible = not iap.unlocked
	restore_btn.visible = not iap.unlocked
	unlock_btn.text = ("전체 해제 " + price).strip_edges()
	exam_btn.text = "모의시험 (4분)" if iap.unlocked else "모의시험 (해제 필요)"
	var best := int(store.data.best)
	best_label.text = "모의시험 최고 %d점 · 합격 %d회" % [best, int(store.data.passes)] if best >= 0 else ""
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
	unlock_text.text = why + "\n\n한 번 결제%s로 연습 모드 전체 코스, 4분 모의시험 채점, 실격 지점 리플레이를 계속 쓸 수 있어요. 광고나 구독은 없어요." % price


func _show_menu() -> void:
	state = State.MENU
	unlock_panel.visible = false
	_refresh_lock()
	menu_panel.visible = true
	result_panel.visible = false
	replay_bar.visible = false
	controls.visible = false
	controls.enabled = false
	sim.reset()
	frames.clear()
	cam_mode = Cam.CHASE


func _start(exam_mode: bool) -> void:
	if exam_mode and not iap.unlocked:
		_show_unlock("모의시험은 전체 해제 후 쓸 수 있어요.")
		return
	unlock_panel.visible = false
	exam = exam_mode
	sim.exam = exam
	sim.reset()
	controls.reset()
	frames.clear()
	_faults_seen = 0
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
	cam_mode = Cam.CAB
	look_back = false
	_sync_controls_buttons()


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
		"signal":
			if state == State.RUN and exam and not sim.signal_given:
				sim.give_signal()
				_play("whistle")
				controls.set_button("signal", "")
				_toast("삐익! 1분 안에 출발선을 지나세요", GREEN)
	_sync_controls_buttons()


func _toast(t: String, c := RED) -> void:
	toast.text = t
	toast.add_theme_color_override("font_color", c)
	toast_t = 3.0


# ---------- 루프 ----------
func _physics_process(dt: float) -> void:
	if state != State.RUN:
		return
	controls.poll_keys(dt)
	sim.seatbelt = controls.seatbelt
	sim.park_brake = controls.park_brake
	sim.gear = controls.gear
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
		_play("buzzer")
	if sim.done:
		_show_result()
	elif not iap.unlocked and sim.step >= Sim.Step.UNLOADED:
		_play("chime")
		_show_unlock("잘했어요! 무료 연습은 하역까지예요. 후진선 터치부터 주차까지 남은 코스는 전체 해제 후 이어서 연습할 수 있어요.")


func _process(dt: float) -> void:
	if state == State.REPLAY:
		_replay_step(dt)
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
		var t := Time.get_ticks_msec() / 1000.0 * 0.15
		var c2 := World.v3(course.bounds().get_center())
		cam.global_position = c2 + Vector3(cos(t) * 16.0, 9.0, sin(t) * 16.0)
		cam.look_at(c2, Vector3.UP)
		cam.fov = 60.0


func _update_hud(dt: float) -> void:
	var playing := state == State.RUN or state == State.REPLAY
	hud.visible = playing
	step_label.visible = state == State.RUN
	gauge.visible = playing
	minimap.visible = playing
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
	else:
		hud.text = "연습 · %s" % _clock(t)
	step_label.text = sim.instruction()
	var g_names := {1: "전진", 0: "중립", -1: "후진"}
	gauge.text = "포크 %d cm\n틸트 %+.0f°\n속도 %.1f km/h\n%s" % [roundi(sim.lift * 100), sim.tilt, absf(sim.speed) * 3.6, g_names[sim.gear]]
	var lc := INK
	if sim.zone() == "travel" and (sim.lift < 0.15 or sim.lift > 0.35):
		lc = Color(1.0, 0.75, 0.3)
	if sim.zone() == "travel" and sim.lift > 0.5:
		lc = RED
	gauge.add_theme_color_override("font_color", lc)


static func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# ---------- 결과·리플레이 ----------
func _show_result() -> void:
	state = State.RESULT
	if exam and sim.step >= Sim.Step.TO_LOAD:
		store.data.runs = int(store.data.runs) + 1
		if sim.passed():
			store.data.passes = int(store.data.passes) + 1
		if sim.faults.is_empty():
			store.data.best = maxi(int(store.data.best), sim.score())
		store.save()
	_play("chime" if sim.passed() else "buzzer")
	controls.visible = false
	controls.enabled = false
	result_panel.visible = true
	var s := ""
	if sim.passed():
		s += "[center][b][color=#5ad86f]합격[/color][/b][/center]\n"
	else:
		s += "[center][b][color=#f2564a]불합격[/color][/b][/center]\n"
	s += "[center]점수 %d / 100   ·   시간 %s[/center]\n" % [sim.score(), _clock(sim.t_exam)]
	for f in sim.faults:
		s += "[color=#f2564a]실격[/color]  %s (%s)\n" % [f.msg, _clock(f.t)]
	for d in sim.deductions:
		s += "[color=#ffad1a]-%d[/color]  %s\n" % [d.pts, d.msg]
	if sim.faults.is_empty() and sim.deductions.is_empty():
		s += "[center]감점 없이 끝냈어요.[/center]\n"
	result_text.text = s


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
	var f: Array = frames[-1]
	replay_i = frames.size() - 1
	_replay_step(0.0)
	state = State.RESULT
	result_panel.visible = true


# ---------- 스크린샷(개발용): -- shot=경로 scene=menu|run|cab|side|top|result ----------
func _setup_shot() -> void:
	var scene: String = _args.get("scene", "menu")
	if scene != "menu":
		_start(_args.get("mode", "practice") == "exam")
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
		match scene:
			"cab": cam_mode = Cam.CAB
			"chase": cam_mode = Cam.CHASE
			"side": cam_mode = Cam.SIDE
			"top": cam_mode = Cam.TOP
			"result":
				_show_result()
			"icon":
				ui.visible = false
				marker.visible = false
				cam_mode = Cam.CHASE
			"unlock":
				_show_unlock("모의시험은 전체 해제 후 쓸 수 있어요.")
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


# ---------- 소리(코드로 만든 짧은 효과음) ----------
func _make_sounds() -> void:
	sfx.whistle = _tone([[2900.0, 0.12], [0.0, 0.05], [2900.0, 0.5]], 0.35, true)
	sfx.buzzer = _tone([[220.0, 0.45]], 0.3, false, true)
	sfx.chime = _tone([[880.0, 0.14], [1175.0, 0.3]], 0.3)
	for k in sfx:
		var p := AudioStreamPlayer.new()
		p.stream = sfx[k]
		add_child(p)
		sfx[k] = p


func _toggle_sound() -> void:
	store.data.sound = not bool(store.data.sound)
	store.save()
	_sync_sound_btn()


func _sync_sound_btn() -> void:
	sound_btn.text = "소리 켜짐" if bool(store.data.sound) else "소리 꺼짐"


## 앱이 뒤로 가면 소리를 바로 멈추고, 돌아오면 다시 켠다.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			AudioServer.set_bus_mute(0, true)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			AudioServer.set_bus_mute(0, false)


func _play(name: String) -> void:
	if sfx.has(name) and bool(store.data.sound):
		sfx[name].play()


static func _tone(parts: Array, vol: float, trill := false, square := false) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	for part in parts:
		var f: float = part[0]
		var n := int(rate * float(part[1]))
		for i in n:
			var t := float(i) / rate
			var env := minf(1.0, minf(i / 200.0, (n - i) / 400.0))
			var ff := f * (1.0 + (0.03 * sin(TAU * 28.0 * t) if trill else 0.0))
			var v := sin(TAU * ff * t)
			if square:
				v = signf(v) * 0.6
			if f <= 0.0:
				v = 0.0
			var x := int(clampf(v * env * vol, -1.0, 1.0) * 32767.0)
			data.append(x & 0xff)
			data.append((x >> 8) & 0xff)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
