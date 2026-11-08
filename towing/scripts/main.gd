extends Node3D
## App shell. Owns the 3D scene (yard, vehicles, camera, mirrors) and wires
## the screens (HomeScreen, Hud, ResultScreen, LessonsScreen, Onboarding) to
## the simulation (Exam/Rig/TowAutopilot), the coach, sound, replay recording,
## the save file, badges and the one-time purchase. Landscape only.
##
## Command-line user args (after --) for screenshot and check runs:
##   kind=small|wrecker|large  step=<id> (practice/drill) or exam   demo
##   cam=chase|top|driver  t=<s> fast-forward the demo before showing
##   screen=home|drive|result|replay|unlock|lessons  tab=<home tab>
##   locked   simulate the free version      notch  simulate iPhone insets
##   handoff  after the fast-forward the demo stops and you drive (checks)
##   icon     no UI, a fixed close-up camera (renders the app icon)
##   shot=<png> time=<s>  save a screenshot after <s> seconds and quit

const KINDS := ["small", "wrecker", "large"]
const CAM_NAME := {"chase": "뒤에서", "top": "위에서", "driver": "운전석"}
const FREE := {"small": ["crank", "curve", "straight_back"]}
const SIM_DT := 1.0 / 60.0
const VERSION := "1.0"

var store := TowStore.new()
var purchases: Purchases
var sfx: TowSfx
var coach := Coach.new()
var replay := Replay.new()
var world: TowWorld
var view: VehicleView
var cam: Camera3D
var exam: Exam
var pilot: TowAutopilot
var demo := false
var run_key := ""
var paused := true
var screen := "home"
var cam_mode := "chase"
var guide_on := true

var ui: CanvasLayer
var root: MarginContainer
var home: HomeScreen
var hud: Hud
var result: ResultScreen
var lessons: LessonsScreen
var onboarding: Onboarding
var unlock_panel: PanelContainer
var unlock_dim: ColorRect
var unlock_msg: Label
var mirrors: Array = []      # [{vp, cam, rect, side}]
var touches := {}            # touch index -> widget
var home_rig: Rig
var orbit := 0.0
var font: Font

var replay_t := 0.0
var replay_playing := false
var last_why: Array = []

var shot_path := ""
var shot_time := 0.0
var elapsed := 0.0
var ff_time := 0.0
var force_locked := false
var sim_acc := 0.0
var icon_mode := false
var handoff := false

# test-facing shortcuts (tests/test_controls.gd)
var wheel: WheelWidget:
	get: return hud.wheel
var gas: PedalWidget:
	get: return hud.gas
var brk: PedalWidget:
	get: return hud.brk
var gear: PedalWidget:
	get: return hud.gear


func _ready() -> void:
	store.load_data()
	cam_mode = str(store.setting("camera", "chase"))
	guide_on = bool(store.setting("guide", true))
	coach.voice_on = bool(store.setting("voice", true))
	var start_kind := ""
	var start_step := ""
	var start_screen := "home"
	var start_tab := "courses"
	var start_demo := false
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		var val := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"shot": shot_path = val
			"time": shot_time = float(val)
			"kind": start_kind = val
			"step": start_step = val
			"demo": start_demo = true
			"cam": cam_mode = val
			"t": ff_time = float(val)
			"screen": start_screen = val
			"tab": start_tab = val
			"locked": force_locked = true
			"noguide": guide_on = false
			"icon": icon_mode = true
			"handoff": handoff = true
	Kit.setup()
	font = Kit.font
	purchases = Purchases.new()
	add_child(purchases)
	purchases.setup(store, force_locked)
	purchases.changed.connect(_on_unlock_changed)
	purchases.price_known.connect(func(_p): home.refresh())
	purchases.failed.connect(func(r): _unlock_note("구매가 완료되지 않았어요. " + r, Kit.RED))
	purchases.busy_changed.connect(func(b): if b: _unlock_note("App Store에 연결 중…", Kit.MUTED))
	sfx = TowSfx.new()
	add_child(sfx)
	sfx.set_enabled(bool(store.setting("sound", true)))
	coach.spoke.connect(func(t, k): hud.show_coach(t, k))
	world = TowWorld.new()
	add_child(world)
	view = VehicleView.new()
	add_child(view)
	cam = Camera3D.new()
	cam.fov = 60
	cam.far = 600
	add_child(cam)
	_build_ui()
	if start_kind != "":
		var id := "exam" if start_step == "" else start_step
		_start_run(start_kind, id, start_demo)
		if ff_time > 0.0:
			_fast_forward(ff_time)
		if handoff:
			pilot = null
			demo = false
			hud.demo_tag.visible = false
		if icon_mode:
			ui.visible = false
			for m in mirrors:
				m.rect.visible = false
		if start_screen == "result" or start_screen == "replay":
			_fast_forward(3000.0)
			_on_finished(exam.passed)
			_show("result")
			if start_screen == "replay":
				_enter_replay()
				_seek_replay(ff_time if ff_time > 0.0 else replay.duration * 0.5)
	else:
		_show_home()
		home.select_tab(start_tab)
		match start_screen:
			"unlock": _open_unlock()
			"lessons": _show("lessons")
			"onboarding": _show_onboarding()
			_:
				if not bool(store.data.get("onboarded", false)) and shot_path == "":
					_show_onboarding()


func unlocked() -> bool:
	return purchases.unlocked


func is_free(kind: String, id: String) -> bool:
	return FREE.has(kind) and id in FREE[kind]


# ---------------------------------------------------------------- runs

func _go(kind: String, id: String, as_demo: bool) -> void:
	if not purchases.unlocked and not is_free(kind, id):
		_open_unlock()
		return
	_start_run(kind, id, as_demo)


func _start_run(kind: String, id: String, as_demo: bool) -> void:
	demo = as_demo
	run_key = "%s/%s" % [kind, id]
	exam = Exam.new(kind, "" if id == "exam" else id)
	exam.message.connect(_on_message)
	exam.checklist_ready.connect(_on_checklist)
	exam.finished.connect(_on_finished)
	exam.step_started.connect(_on_step_started)
	world.build(exam.steps)
	view.setup(exam.rig)
	pilot = TowAutopilot.new(exam) if demo else null
	replay.clear()
	last_why = []
	hud.hide_replay()
	hud.set_controls_visible(true)
	hud.set_paused(false)
	exam.start()
	hud.wheel.set_steer(0.0)
	hud.set_gear(false)
	_show("drive")
	_setup_mirrors()
	_on_step_started(0)
	sfx.play("air_brake", -6.0)


func _on_step_started(_i: int) -> void:
	hud.hide_checklist()
	paused = true
	hud.wheel.set_steer(0.0)
	hud.set_step(exam, demo)
	hud.show_tips(exam, demo)
	if demo or exam.step.type == "couple":
		hud.set_gear(true)
	_update_hud()


## The 출발 button on the briefing: the clock runs from here.
func _start_step() -> void:
	hud.hide_tips()
	paused = false
	coach.on_step(exam)
	if exam.step.type == "couple" and pilot == null:
		hud.set_gear(true)
	sfx.play("ui_confirm", -8.0)


func _fast_forward(seconds: float) -> void:
	# demo runs only: drive ahead instantly (screenshots, checks)
	if pilot == null:
		pilot = TowAutopilot.new(exam)
		pilot._reset()
	hud.hide_tips()
	paused = false
	var t := 0.0
	while t < seconds and not exam.done:
		pilot.update(SIM_DT)
		exam.update(SIM_DT)
		replay.sample(exam, SIM_DT)
		t += SIM_DT
	hud.hide_tips()
	paused = false
	view.sync(exam.trailer_parked, exam.trailer_pos, exam.trailer_th)
	_snap_camera()


func _process(dt: float) -> void:
	elapsed += dt
	if shot_path != "" and elapsed >= shot_time and elapsed - dt < shot_time:
		_take_shot()
	if screen == "home" or screen == "lessons":
		_home_scene(dt)
		sfx.engine(false, 0.0)
		sfx.beep_reverse(false)
		return
	if exam == null:
		return
	if screen == "replay":
		_replay_process(dt)
		return
	var braking := false
	if not paused and not exam.done:
		# fixed 60 Hz steps so a slow frame does not change the driving
		sim_acc = minf(sim_acc + dt, 0.25)
		while sim_acc >= SIM_DT and not exam.done:
			sim_acc -= SIM_DT
			if pilot:
				pilot.update(SIM_DT)
				hud.wheel.set_steer(exam.rig.steer)
			else:
				_read_controls()
			exam.update(SIM_DT)
			coach.tick(SIM_DT)
			coach.watch(exam)
			replay.sample(exam, SIM_DT)
		braking = exam.rig.brake > 0.5
	var r := exam.rig
	var running := not paused and not exam.done
	sfx.engine(running, clampf(r.speed_kmh() / 22.0 + r.throttle * 0.35, 0.0, 1.0))
	sfx.beep_reverse(running and r.reverse and absf(r.v) > 0.05)
	if view.has_method("set_lights"):
		view.set_lights(braking or exam.done, r.reverse and running)
	if view.has_method("set_steer_wheel"):
		view.set_steer_wheel(hud.wheel.angle)
	view.sync(exam.trailer_parked, exam.trailer_pos, exam.trailer_th)
	_camera(dt)
	_mirrors()
	_guide()
	_update_hud(braking)


func _read_controls() -> void:
	var rig := exam.rig
	var k_steer := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		k_steer += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		k_steer -= 1.0
	if k_steer != 0.0:
		hud.wheel.set_steer(clampf(hud.wheel.steer() + k_steer * SIM_DT * 0.8, -1, 1))
	rig.steer = hud.wheel.steer()
	var kgas := Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
	var kbrk := Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_SPACE)
	rig.throttle = 0.55 if (hud.gas.held or kgas) else 0.0
	rig.brake = 1.0 if (hud.brk.held or kbrk) else 0.0
	rig.reverse = hud.gear.label == "R"


func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if screen == "drive":
		if e.keycode == KEY_R:
			_toggle_gear()
		elif e.keycode == KEY_C:
			_cycle_cam()
		elif e.keycode == KEY_ESCAPE:
			_toggle_pause()


func _toggle_gear() -> void:
	if pilot or exam == null or exam.done:
		return
	hud.set_gear(hud.gear.label != "R")
	sfx.play("gear", -6.0)
	_haptic(10)


func _haptic(ms: int) -> void:
	if bool(store.setting("haptic", true)) and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ---------------------------------------------------------------- input

func _input(e: InputEvent) -> void:
	if screen != "drive" or paused or pilot != null or (exam and exam.done):
		return
	var touch := DisplayServer.is_touchscreen_available()
	if e is InputEventScreenTouch:
		if e.pressed:
			var w := _widget_at(e.position)
			if w:
				touches[e.index] = w
				w.press(_local(w, e.position))
				get_viewport().set_input_as_handled()
		elif touches.has(e.index):
			touches[e.index].release()
			touches.erase(e.index)
	elif e is InputEventScreenDrag:
		if touches.has(e.index):
			touches[e.index].drag(_local(touches[e.index], e.position))
			get_viewport().set_input_as_handled()
	elif not touch and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var w2 := _widget_at(e.position)
			if w2:
				touches[-1] = w2
				w2.press(_local(w2, e.position))
		elif touches.has(-1):
			touches[-1].release()
			touches.erase(-1)
	elif not touch and e is InputEventMouseMotion and touches.has(-1):
		touches[-1].drag(_local(touches[-1], e.position))


func _widget_at(p: Vector2) -> Control:
	# canvas_items stretch: events arrive in canvas coordinates already
	for w in hud.widgets():
		if w.visible and w.get_global_rect().grow(8).has_point(p):
			return w
	return null


func _local(w: Control, p: Vector2) -> Vector2:
	return p - w.get_global_rect().position


func _release_all() -> void:
	for w in touches.values():
		w.release()
	touches.clear()


# ---------------------------------------------------------------- camera

func _rig_center() -> Vector2:
	var r := exam.rig
	if r.coupled:
		return (r.pos + r.trailer_axle()) * 0.5
	return r.pos


func _snap_camera() -> void:
	_camera(10.0)


func _camera(dt: float) -> void:
	var r := exam.rig
	var k := clampf(dt * 3.0, 0.0, 1.0)
	if icon_mode:
		var c := _rig_center()
		cam.global_position = Vector3(c.x - 3.0, 15.0, -c.y + 9.0)
		cam.look_at(Vector3(c.x + 0.8, 0.0, -c.y - 0.5), Vector3.UP)
		cam.fov = 42
		cam.cull_mask = 0xFFFFF & ~4
		return
	match cam_mode:
		"top":
			var c := _rig_center()
			var h: float = {"small": 24.0, "wrecker": 28.0, "large": 42.0}[r.kind]
			var want := Vector3(c.x, h, -c.y)
			cam.global_position = cam.global_position.lerp(want, k) if dt < 1.0 else want
			cam.look_at(Vector3(cam.global_position.x, 0, cam.global_position.z), Vector3(0, 0, -1))   # north up
			cam.fov = 55
			cam.cull_mask = 0xFFFFF & ~4
		"driver":
			var eye := view.driver_eye.global_position
			cam.global_position = eye
			var fwd := Vector3(cos(r.th), 0, -sin(r.th))
			cam.look_at(eye + fwd * 10.0 + Vector3(0, -2.2, 0), Vector3.UP)
			cam.fov = 75
			cam.cull_mask = 0xFFFFF & ~2
		_:
			cam.cull_mask = 0xFFFFF & ~4
			var dist: float = {"small": 11.0, "wrecker": 13.0, "large": 19.0}[r.kind]
			var hgt: float = {"small": 8.5, "wrecker": 9.5, "large": 13.0}[r.kind]
			var f := Vector2(cos(r.th), sin(r.th))
			var base := r.pos - f * (dist * 0.5)
			if r.coupled:
				base = r.hitch() - Vector2(cos(r.phi), sin(r.phi)) * (r.tspec.D * 0.6 + dist * 0.4)
			var want2 := Vector3(base.x, hgt, -base.y)
			cam.global_position = cam.global_position.lerp(want2, k) if dt < 1.0 else want2
			var look := r.pos + f * 2.0
			cam.look_at(Vector3(look.x, 0.5, -look.y), Vector3.UP)
			cam.fov = 60


func _setup_mirrors() -> void:
	for m in mirrors:
		m.vp.queue_free()
		m.rect.queue_free()
	mirrors.clear()
	for side in ["l", "r"]:
		var vp := SubViewport.new()
		vp.size = Vector2i(300, 210)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var mc := Camera3D.new()
		mc.fov = 38
		mc.cull_mask = 0xFFFFF & ~4
		mc.far = 200
		vp.add_child(mc)
		add_child(vp)
		var tr := TextureRect.new()
		tr.texture = vp.get_texture()
		tr.flip_h = true
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(230, 160)
		tr.size = Vector2(230, 160)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(tr)
		hud.move_child(tr, 0)
		mirrors.append({"vp": vp, "cam": mc, "rect": tr, "side": side})
	_layout_mirrors()


func _layout_mirrors() -> void:
	if hud == null:
		return
	var s := hud.size
	for mm in mirrors:
		var tr: TextureRect = mm.rect
		var x: float = 10.0 if mm.side == "l" else s.x - 10.0 - 230.0
		tr.position = Vector2(x, 100.0)


func _mirrors() -> void:
	var on := (cam_mode == "driver" or cam_mode == "chase" and exam.rig.reverse) and not icon_mode
	for mm in mirrors:
		mm.rect.visible = on
		mm.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		if not on:
			continue
		var mount: Node3D = view.mirror_l if mm.side == "l" else view.mirror_r
		var r := exam.rig
		var f := Vector3(cos(r.th), 0, -sin(r.th))
		var left := Vector3(-sin(r.th), 0, -cos(r.th))
		var out := left if mm.side == "l" else -left
		var o := mount.global_position + out * 0.15
		var look := o - f * 12.0 + out * (2.2 if r.kind != "large" else 3.2) + Vector3(0, -1.4, 0)
		mm.cam.global_position = o
		mm.cam.look_at(look, Vector3.UP)


func _guide() -> void:
	if not guide_on or exam.done or pilot:
		world.draw_guide([])
		return
	var r := exam.rig.copy()
	var dist: float = {"small": 9.0, "wrecker": 11.0, "large": 18.0}[r.kind]
	var dir := -1.0 if r.reverse else 1.0
	r.v = dir * 1.0
	r.throttle = 0.0
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	var c := PackedVector2Array()
	var d := PackedVector2Array()
	var steps := int(dist / 0.25)
	for i in steps:
		var ws := r.wheels()
		a.append(ws[0].p)
		b.append(ws[1].p)
		if r.coupled:
			c.append(ws[ws.size() - 2].p)
			d.append(ws[ws.size() - 1].p)
		r.v = dir * 1.0
		r._integrate(0.25)
	var tracks := [{"pts": a, "color": Color(0.2, 0.9, 1.0, 0.85)}, {"pts": b, "color": Color(0.2, 0.9, 1.0, 0.85)}]
	if r.coupled:
		tracks.append({"pts": c, "color": Color(1.0, 0.6, 0.1, 0.9)})
		tracks.append({"pts": d, "color": Color(1.0, 0.6, 0.1, 0.9)})
	world.draw_guide(tracks)


func _home_scene(dt: float) -> void:
	if home_rig == null:
		return
	orbit += dt * 0.08
	view.sync(false, Vector2.ZERO, 0.0)
	var c := home_rig.pos + Vector2(-3.0, -2.0)
	var p := c + Vector2(cos(orbit), sin(orbit)) * 13.0
	cam.global_position = Vector3(p.x, 4.5, -p.y)
	# the menu panel covers the right 70 % of the screen, so aim to the right of
	# the rig and it lands under the title on the left
	var side := Vector2(-sin(orbit), cos(orbit)) * 5.5
	var look := c + side
	cam.look_at(Vector3(look.x, 1.2, -look.y), Vector3.UP)
	cam.cull_mask = 0xFFFFF & ~4
	cam.fov = 55


# ---------------------------------------------------------------- replay

func _enter_replay() -> void:
	screen = "replay"
	result.visible = false
	hud.visible = true
	hud.set_controls_visible(false)
	hud.hide_checklist()
	hud.show_replay(replay.duration, replay.marks)
	replay_t = 0.0
	replay_playing = true
	sfx.engine(false, 0.0)
	sfx.beep_reverse(false)
	_seek_replay(0.0)


func _seek_replay(t: float) -> void:
	replay_t = clampf(t, 0.0, replay.duration)
	var f := replay.frame_at(replay_t)
	if f.is_empty():
		return
	Replay.apply(f, exam.rig)
	view.sync(bool(f.parked), f.ppos, f.pth)
	hud.wheel.set_steer(exam.rig.steer)
	hud.set_gear(bool(f.rev))
	if int(f.step) != exam.index and int(f.step) < exam.steps.size():
		hud.minimap.set_step(exam.steps[int(f.step)])
	hud.replay_tick(replay_t, replay_playing)
	_snap_camera()
	_mirrors()


func _replay_process(dt: float) -> void:
	if replay_playing:
		replay_t += dt
		if replay_t >= replay.duration:
			replay_t = replay.duration
			replay_playing = false
		var f := replay.frame_at(replay_t)
		if not f.is_empty():
			Replay.apply(f, exam.rig)
			view.sync(bool(f.parked), f.ppos, f.pth)
			hud.wheel.set_steer(exam.rig.steer)
			if (hud.gear.label == "R") != bool(f.rev):
				hud.set_gear(bool(f.rev))
			# a caption at each recorded mistake
			for m in replay.marks:
				if float(m.t) >= replay_t - dt and float(m.t) < replay_t:
					hud.show_toast("%s  -%d" % [m.text, int(m.points)] if int(m.points) > 0 else str(m.text), "bad")
	hud.replay_tick(replay_t, replay_playing)
	var r := exam.rig
	if view.has_method("set_lights"):
		view.set_lights(false, r.reverse)
	_camera(dt)
	_mirrors()
	world.draw_guide([])
	hud.update(exam, false, CAM_NAME.get(cam_mode, ""), guide_on, false)
	hud.minimap.queue_redraw()


func _leave_replay() -> void:
	replay_playing = false
	hud.hide_replay()
	hud.set_controls_visible(true)
	hud.minimap.set_step(exam.step)
	var f := replay.frame_at(replay.duration)
	if not f.is_empty():
		Replay.apply(f, exam.rig)
		view.sync(bool(f.parked), f.ppos, f.pth)
	_show("result")


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var top := Control.new()
	top.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.theme = Kit.theme
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top)
	root = MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(root)
	# home
	home = HomeScreen.new()
	home.store = store
	home.purchases = purchases
	home.free_check = is_free
	home.version = VERSION
	home.run_requested.connect(_go)
	home.unlock_requested.connect(_open_unlock)
	home.restore_requested.connect(func(): sfx.play("ui_tap", -8.0); purchases.restore())
	home.forklift_requested.connect(func(): get_tree().change_scene_to_file("res://main.tscn"))
	home.lessons_requested.connect(func(): sfx.play("ui_tap", -8.0); _show("lessons"))
	home.setting_changed.connect(_on_setting)
	home.tab_changed.connect(func(_t): sfx.play("ui_tap", -10.0))
	root.add_child(home)
	# driving
	hud = Hud.new()
	hud.exit_pressed.connect(_quit_run)
	hud.pause_pressed.connect(_toggle_pause)
	hud.resume_pressed.connect(_toggle_pause)
	hud.restart_pressed.connect(_retry)
	hud.camera_pressed.connect(_cycle_cam)
	hud.guide_pressed.connect(_toggle_guide)
	hud.start_pressed.connect(_start_step)
	hud.checklist_pick.connect(_on_check)
	hud.gear_toggled.connect(_toggle_gear)
	hud.replay_seek.connect(func(t): replay_playing = false; _seek_replay(t))
	hud.replay_play.connect(func(on): replay_playing = on; if on and replay_t >= replay.duration: _seek_replay(0.0))
	hud.replay_close.connect(_leave_replay)
	hud.minimap_on = bool(store.setting("minimap", true))
	root.add_child(hud)   # _ready builds the widgets
	hud.set_lefty(bool(store.setting("lefty", false)))
	hud.wheel.sensitivity = float(store.setting("sens", 1.0))
	hud.resized.connect(_layout_mirrors)
	# result
	result = ResultScreen.new()
	result.retry_pressed.connect(_retry)
	result.next_pressed.connect(_next_course)
	result.replay_pressed.connect(func(): sfx.play("ui_tap", -8.0); _enter_replay())
	result.home_pressed.connect(_quit_run)
	result.visible = false
	root.add_child(result)
	# lessons
	lessons = LessonsScreen.new()
	lessons.closed.connect(func(): _show("home"))
	lessons.visible = false
	root.add_child(lessons)
	_build_unlock()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _safe_margins() -> Vector4:
	# left, right, top, bottom in canvas units
	var vs := get_viewport().get_visible_rect().size
	var ws := Vector2(DisplayServer.window_get_size())
	var sa := Rect2(DisplayServer.get_display_safe_area())
	var l := 0.0
	var r := 0.0
	var b := 0.0
	if OS.has_feature("ios") and ws.x > 0:
		var k := vs.x / ws.x
		l = sa.position.x * k
		r = (ws.x - sa.end.x) * k
		b = (ws.y - sa.end.y) * k
	if "notch" in OS.get_cmdline_user_args():
		l = 118.0
		r = 118.0
		b = 42.0
	return Vector4(maxf(l, 24.0), maxf(r, 24.0), 14.0, maxf(b, 12.0))


func _layout() -> void:
	var m := _safe_margins()
	root.add_theme_constant_override("margin_left", int(m.x))
	root.add_theme_constant_override("margin_right", int(m.y))
	root.add_theme_constant_override("margin_top", int(m.z))
	root.add_theme_constant_override("margin_bottom", int(m.w))
	_layout_mirrors()


func _show(s: String) -> void:
	screen = s
	home.visible = s == "home"
	hud.visible = s == "drive" or s == "result" or s == "replay"
	result.visible = s == "result"
	lessons.visible = s == "lessons"
	unlock_panel.visible = false
	unlock_dim.visible = false
	if s == "home":
		home.refresh()


func _show_home() -> void:
	exam = null
	pilot = null
	coach.stop()
	home_rig = Rig.new("small")
	home_rig.set_pose(Vector2(40, -2), PI / 2 + 0.25, PI / 2 + 0.05)
	world.build(Courses.exam_steps("small"))
	world.draw_guide([])
	view.setup(home_rig)
	if view.has_method("set_lights"):
		view.set_lights(false, false)
	for m in mirrors:
		m.rect.visible = false
		m.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_show("home")


func _show_onboarding() -> void:
	onboarding = Onboarding.new()
	onboarding.done.connect(func():
		store.data.onboarded = true
		store.save()
		onboarding.queue_free()
		onboarding = null
		sfx.play("ui_confirm", -8.0))
	root.add_child(onboarding)


func _on_setting(key: String, value) -> void:
	store.set_setting(key, value)
	match key:
		"sound": sfx.set_enabled(bool(value))
		"voice": coach.voice_on = bool(value)
		"lefty": hud.set_lefty(bool(value))
		"minimap":
			hud.minimap_on = bool(value)
			hud._layout()
		"sens": hud.wheel.sensitivity = float(value)
		"camera": cam_mode = str(value)
		"guide": guide_on = bool(value)
	sfx.play("ui_tap", -10.0)


# ---- driving

func _cycle_cam() -> void:
	var order := ["chase", "top", "driver"]
	cam_mode = order[(order.find(cam_mode) + 1) % order.size()]
	store.set_setting("camera", cam_mode)
	sfx.play("ui_tap", -8.0)
	if exam:
		_snap_camera()


func _toggle_guide() -> void:
	guide_on = not guide_on
	store.set_setting("guide", guide_on)
	sfx.play("ui_tap", -8.0)


func _toggle_pause() -> void:
	if exam == null or exam.done or hud.tips_panel.visible:
		return
	paused = not paused
	_release_all()
	hud.set_paused(paused)
	sfx.play("ui_tap", -8.0)
	if paused:
		coach.stop()


func _update_hud(braking := false) -> void:
	if exam == null:
		return
	hud.update(exam, pilot == null, CAM_NAME.get(cam_mode, ""), guide_on, braking)


func _on_message(t: String, kind: String) -> void:
	hud.show_toast(t, kind)
	if kind == "bad":
		var pts := 0
		var m := RegEx.create_from_string("-(\\d+)$").search(t)
		if m:
			pts = int(m.get_string(1))
		replay.mark(exam, t.split("  -")[0], pts)
		last_why.append(t.split("  -")[0].replace("실격: ", ""))
		if t.begins_with("실격"):
			sfx.play("disqualify", -4.0)
			_haptic(120)
		else:
			sfx.play("line_touch", -4.0)
			sfx.play("tyre_scrub", -10.0)
			_haptic(60)
	elif kind == "good":
		sfx.play("step_done", -6.0)
		_haptic(25)


func _on_checklist(items: Array) -> void:
	hud.show_checklist(items, hash(run_key) + exam.index, pilot != null, font)
	coach.say("checklist", "순서대로 작업하세요", 1.0)


func _on_check(item: String) -> void:
	var ok := exam.choose(item)
	hud.set_pick_result(ok, exam.aligned)
	sfx.play("clunk" if ok else "ui_tap", -4.0 if ok else -6.0)
	if ok:
		_haptic(20)


func _quit_run() -> void:
	paused = true
	_release_all()
	sfx.play("ui_tap", -8.0)
	_show_home()


func _retry() -> void:
	var parts := run_key.split("/")
	_release_all()
	_start_run(parts[0], parts[1], demo)


func _next_course() -> void:
	var nxt := _next_id()
	if nxt == "":
		_quit_run()
		return
	var parts := run_key.split("/")
	_go(parts[0], nxt, demo)


func _next_id() -> String:
	var parts := run_key.split("/")
	if parts[1] == "exam":
		return ""
	if TowDrills.is_drill(parts[1]):
		var ids := []
		for d in TowDrills.LIST:
			if d.id != "free":
				ids.append(d.id)
		var i := ids.find(parts[1])
		return ids[i + 1] if i >= 0 and i + 1 < ids.size() else ""
	var lst := Courses.practice_list(parts[0])
	for i in lst.size():
		if lst[i].id == parts[1]:
			return lst[i + 1].id if i + 1 < lst.size() else ""
	return ""


func _on_finished(ok: bool) -> void:
	_release_all()
	coach.stop()
	hud.hide_checklist()
	sfx.engine(false, 0.0)
	sfx.beep_reverse(false)
	var free_run: bool = exam.step.get("free_run", false)
	var rec := {}
	var new_badges := []
	if not demo and not free_run:
		rec = store.record(run_key, exam.score, ok, exam.t_total, exam.disqualified)
		var hist: Array = store.data.history
		if not hist.is_empty():
			hist[hist.size() - 1]["why"] = last_why.duplicate()
			store.save()
		new_badges = Badges.check(store, run_key, exam.score, ok, exam.disqualified)
	sfx.play("pass" if ok else "fail", -4.0)
	_haptic(80 if ok else 150)
	if ok:
		coach.say("done", "합격이에요. 수고했어요", 0.0, "good")
	elif exam.disqualified != "":
		coach.say("done", "실격이에요. 리플레이로 그 순간을 다시 보세요", 0.0, "bad")
	else:
		coach.say("done", "아쉽게 불합격이에요. 감점 내역을 확인하세요", 0.0, "bad")
	result.show_result(exam, rec, new_badges, _next_id() != "", demo)
	result.visible = false
	get_tree().create_timer(1.2).timeout.connect(func():
		if exam and exam.done and screen == "drive":
			_show("result"))


# ---- unlock

func _build_unlock() -> void:
	unlock_dim = ColorRect.new()
	unlock_dim.color = Color(0, 0, 0, 0.6)
	unlock_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	unlock_dim.visible = false
	root.add_child(unlock_dim)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	unlock_panel = Kit.panel(Kit.BG_SOLID, 22, 26)
	holder.add_child(unlock_panel)
	var v := Kit.vbox(12)
	v.custom_minimum_size = Vector2(640, 0)
	unlock_panel.add_child(v)
	v.add_child(Kit.label("전체 해제", 38, Kit.GOLD))
	v.add_child(Kit.wrap("· 소형견인·구난·대형견인 모의시험 전부\n· 모든 코스 연습과 모범 주행\n· 90도 후진·S자 후진·자유 연습장\n· 연결·분리 작업 연습\n· 지게차 실기 전체 코스와 모의시험도 함께\n한 번 구매로 계속 쓸 수 있어요. 광고는 없어요.", 22, Kit.TEXT, 640))
	unlock_msg = Kit.label("", 17, Kit.MUTED)
	v.add_child(unlock_msg)
	var h := Kit.hbox(12)
	v.add_child(h)
	var buy := Kit.button("구매하기", func(): purchases.buy(), 26, "gold")
	h.add_child(buy)
	h.add_child(Kit.button("구매 복원", func(): purchases.restore(), 22, "ghost"))
	h.add_child(Kit.spacer())
	h.add_child(Kit.button("닫기", func(): unlock_panel.visible = false; unlock_dim.visible = false, 22, "ghost"))
	purchases.price_known.connect(func(p): buy.text = "구매하기  " + p)
	unlock_panel.visible = false


func _open_unlock() -> void:
	unlock_msg.text = ""
	unlock_panel.visible = true
	unlock_dim.visible = true
	sfx.play("ui_tap", -8.0)


func _unlock_note(t: String, col: Color) -> void:
	if unlock_msg:
		unlock_msg.text = t
		unlock_msg.add_theme_color_override("font_color", col)


func _on_unlock_changed(on: bool) -> void:
	if on:
		unlock_panel.visible = false
		unlock_dim.visible = false
		sfx.play("pass", -6.0)
	if screen == "home":
		home.refresh()


# ---------------------------------------------------------------- shots

func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	print("saved ", shot_path)
	get_tree().quit()
