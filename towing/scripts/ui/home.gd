class_name HomeScreen
extends Control
## The menu over the 3D hero scene: a bottom tab bar (코스 · 모의시험 ·
## 훈련장 · 배우기 · 기록 · 설정) and a glass panel on the right whose content
## follows the tab. The left side keeps the title and the unlock buttons.

signal run_requested(kind: String, id: String, demo: bool)
signal unlock_requested
signal restore_requested
signal lessons_requested
signal forklift_requested
signal setting_changed(key: String, value)
signal tab_changed(tab: String)

const TABS := [["courses", "코스 연습"], ["exam", "모의시험"], ["drills", "훈련장"], ["learn", "배우기"], ["records", "기록"], ["settings", "설정"]]
const KINDS := ["small", "wrecker", "large"]
const KIND_NAME := {"small": "소형견인", "wrecker": "구난", "large": "대형견인"}
const KIND_DESC := {
	"small": "1톤 화물차 + 소형 트레일러. 굴절 → 곡선 → 방향전환",
	"wrecker": "5톤 구난차. 피견인차 연결 → 굴절 → 곡선 → 분리 → 방향전환",
	"large": "트랙터 + 40피트 트레일러. 연결 → 방향전환 → 분리",
}

var store: TowStore
var purchases: Purchases
var tab := "courses"
var content: VBoxContainer
var tab_btns := {}
var unlock_btn: Button
var restore_btn: Button
var free_check: Callable   # (kind, id) -> bool
var version := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := Kit.hbox(20)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -74
	add_child(row)
	var left := Kit.vbox(8)
	left.custom_minimum_size.x = 400
	row.add_child(left)
	left.add_child(Kit.gap(10))
	var back := Kit.button("‹ 지게차 실기", func(): forklift_requested.emit(), 18, "ghost")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(back)
	left.add_child(Kit.title("견인 기능시험 3D", 50))
	var st := Kit.title("1종 특수 · 소형견인 · 구난 · 대형견인", 22)
	st.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	left.add_child(st)
	left.add_child(Kit.spacer(false))
	var note := Kit.title("실제 채점 기준 · 코치 안내 · 리플레이", 18)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	left.add_child(note)
	var btns := Kit.hbox(8)
	left.add_child(btns)
	unlock_btn = Kit.button("전체 해제", func(): unlock_requested.emit(), 21, "gold")
	btns.add_child(unlock_btn)
	restore_btn = Kit.button("구매 복원", func(): restore_requested.emit(), 18, "ghost")
	btns.add_child(restore_btn)
	var panel := Kit.panel(Kit.PANEL, 24, 16)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	content = Kit.vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	# bottom tab bar
	var bar := Kit.panel(Kit.BG_SOLID, 20, 6)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -64
	add_child(bar)
	var th := Kit.hbox(6)
	bar.add_child(th)
	for t in TABS:
		var b := Kit.button(t[1], func(): select_tab(t[0]), 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		th.add_child(b)
		tab_btns[t[0]] = b


func select_tab(t: String) -> void:
	tab = t
	for k in tab_btns:
		var b: Button = tab_btns[k]
		b.add_theme_stylebox_override("normal", Kit.sb(Kit.PRIMARY if k == t else Color(1, 1, 1, 0.04), 14, 8, Color(0, 0, 0, 0)))
	refresh()
	tab_changed.emit(t)


func refresh() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	var open := purchases.unlocked
	unlock_btn.visible = not open
	restore_btn.visible = not open
	unlock_btn.text = "전체 해제 %s" % purchases.price if purchases.price != "" else "전체 해제"
	match tab:
		"courses": _courses(open)
		"exam": _exams(open)
		"drills": _drills(open)
		"learn": _learn()
		"records": _records()
		"settings": _settings()


func _head(t: String, sub := "") -> void:
	var h := Kit.hbox(10)
	h.add_child(Kit.label(t, 28))
	if sub != "":
		var s := Kit.label(sub, 17, Kit.MUTED)
		s.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(s)
	content.add_child(h)


func _lock_tag(ok: bool) -> Control:
	return Kit.chip("무료" if ok else "잠김", Kit.GREEN.darkened(0.4) if ok else Kit.LOCK, 15)


# ---------------------------------------------------------------- tabs

func _courses(open: bool) -> void:
	_head("코스 연습", "코스 하나씩 연습하거나 모범 주행을 보세요")
	for k in KINDS:
		var card := Kit.panel(Kit.PANEL_LIGHT, 18, 14)
		content.add_child(card)
		var v := Kit.vbox(8)
		card.add_child(v)
		var head := Kit.hbox(10)
		v.add_child(head)
		head.add_child(Kit.label(KIND_NAME[k], 26))
		var sub := Kit.label(Rig.SPECS[k].name, 17, Kit.MUTED)
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(sub)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 8)
		v.add_child(grid)
		for p in Courses.practice_list(k):
			var ok: bool = open or free_check.call(k, p.id)
			var key := "%s/%s" % [k, p.id]
			var rowp := Kit.panel(Color(0, 0, 0, 0.22), 14, 8)
			rowp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(rowp)
			var hh := Kit.hbox(8)
			rowp.add_child(hh)
			var tv := Kit.vbox(2)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hh.add_child(tv)
			var th := Kit.hbox(6)
			tv.add_child(th)
			th.add_child(Kit.label(p.title, 20))
			if not ok:
				th.add_child(_lock_tag(false))
			var bh := Kit.hbox(6)
			tv.add_child(bh)
			bh.add_child(Kit.stars(store.stars(key), 16))
			var best := store.best(key)
			bh.add_child(Kit.label("최고 %d점" % best if best >= 0 else "기록 없음", 15, Kit.MUTED))
			hh.add_child(Kit.button("연습", func(): run_requested.emit(k, p.id, false), 18, "primary" if ok else "lock"))
			hh.add_child(Kit.button("모범", func(): run_requested.emit(k, p.id, true), 18, "ghost" if ok else "lock"))


func _exams(open: bool) -> void:
	_head("모의시험", "실제 순서와 채점 기준 그대로")
	for k in KINDS:
		var key := "%s/exam" % k
		var card := Kit.panel(Kit.PANEL_LIGHT, 18, 14)
		content.add_child(card)
		var h := Kit.hbox(14)
		card.add_child(h)
		var v := Kit.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var th := Kit.hbox(8)
		v.add_child(th)
		th.add_child(Kit.label(KIND_NAME[k] + " 모의시험", 26))
		if not open:
			th.add_child(_lock_tag(false))
		var best := store.best(key)
		if best >= Exam.PASS:
			th.add_child(Kit.chip("합격", Kit.GREEN.darkened(0.4), 15))
		v.add_child(Kit.wrap(KIND_DESC[k], 17, Kit.MUTED, 480))
		var bh := Kit.hbox(8)
		v.add_child(bh)
		bh.add_child(Kit.stars(store.stars(key), 17))
		bh.add_child(Kit.label("최고 %d점" % best if best >= 0 else "아직 응시 전", 16, Kit.MUTED))
		var steps := Courses.exam_steps(k)
		var lim := 0.0
		for s in steps:
			lim += s.time_limit
		bh.add_child(Kit.label("· %d단계 · 제한 %d분" % [steps.size(), int(lim / 60)], 16, Kit.MUTED))
		h.add_child(Kit.button("시작", func(): run_requested.emit(k, "exam", false), 22, "primary" if open else "lock"))
	var info := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
	content.add_child(info)
	var iv := Kit.vbox(4)
	info.add_child(iv)
	iv.add_child(Kit.label("채점 기준 요약", 20, Kit.PRIMARY))
	iv.add_child(Kit.wrap("· 100점 만점, 90점 이상 합격. 출발 지시 후 20초 안에 출발하지 않으면 실격.\n· 소형견인·구난: 코스당 3분, 검지선 접촉 -10점, 시간 초과 -10점 후 3분 추가, 확인선 미접촉·잭나이프·코스 이탈 실격.\n· 대형견인: 연결·방향전환·분리 각 5분, 검지선 접촉 -20점으로 즉시 불합격, 예각 꺾임 실격.\n· 연결·분리 작업은 순서가 틀리면 -10점 (1회).\n도로교통공단 안내를 바탕으로 했고, 코스 치수는 시험장마다 달라 근사치예요.", 16, Kit.TEXT, 560))


func _drills(open: bool) -> void:
	_head("훈련장", "후진 감각을 드릴로 익혀요 (소형 트레일러)")
	for d in TowDrills.LIST:
		var ok: bool = open or bool(d.free)
		var key := "small/%s" % d.id
		var card := Kit.panel(Kit.PANEL_LIGHT, 18, 12)
		content.add_child(card)
		var h := Kit.hbox(14)
		card.add_child(h)
		var v := Kit.vbox(3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var th := Kit.hbox(8)
		v.add_child(th)
		th.add_child(Kit.label(d.title, 24))
		th.add_child(_lock_tag(ok) if (bool(d.free) or not ok) else Kit.gap(0))
		v.add_child(Kit.wrap(d.desc, 17, Kit.MUTED, 460))
		if d.id != "free":
			var bh := Kit.hbox(8)
			v.add_child(bh)
			bh.add_child(Kit.stars(store.stars(key), 16))
			var best := store.best(key)
			bh.add_child(Kit.label("최고 %d점" % best if best >= 0 else "기록 없음", 15, Kit.MUTED))
		h.add_child(Kit.button("시작", func(): run_requested.emit("small", d.id, false), 20, "primary" if ok else "lock"))
		if d.id != "free":
			h.add_child(Kit.button("모범", func(): run_requested.emit("small", d.id, true), 18, "ghost" if ok else "lock"))


func _learn() -> void:
	_head("배우기", "트레일러가 움직이는 원리를 그림으로")
	for l in LessonsScreen.LESSONS:
		var card := Kit.panel(Kit.PANEL_LIGHT, 18, 12)
		content.add_child(card)
		var h := Kit.hbox(14)
		card.add_child(h)
		var v := Kit.vbox(3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(Kit.label(l.title, 24))
		v.add_child(Kit.wrap(l.lines[0], 17, Kit.MUTED, 500))
		h.add_child(Kit.button("보기", func(): lessons_requested.emit(), 20, "primary"))


func _records() -> void:
	_head("기록", "연습한 만큼 쌓여요")
	var d := store.data
	var stats := Kit.panel(Kit.PANEL_LIGHT, 18, 12)
	content.add_child(stats)
	var sh := Kit.hbox(18)
	stats.add_child(sh)
	for pair in [["주행 횟수", "%d회" % int(d.runs)], ["합격", "%d회" % int(d.passes)], ["합격률", "%d%%" % int(round(store.pass_rate() * 100))], ["연습 시간", Kit.fmt_time(float(d.drive_time))]]:
		var v := Kit.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sh.add_child(v)
		v.add_child(Kit.label(pair[1], 30, Kit.PRIMARY))
		v.add_child(Kit.label(pair[0], 15, Kit.MUTED))
	# weakness analysis
	var counts := {}
	for h in d.history:
		if h.get("dq", "") != "":
			counts["실격"] = int(counts.get("실격", 0)) + 1
	var weak := _weakness()
	if not weak.is_empty():
		var wp := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
		content.add_child(wp)
		var wv := Kit.vbox(4)
		wp.add_child(wv)
		wv.add_child(Kit.label("자주 하는 실수", 20, Kit.AMBER))
		for w in weak:
			wv.add_child(Kit.label("· %s  %d회" % [w[0], w[1]], 17))
	# badges
	var bp := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
	content.add_child(bp)
	var bv := Kit.vbox(6)
	bp.add_child(bv)
	bv.add_child(Kit.label("배지  %d / %d" % [d.badges.size(), Badges.ALL.size()], 20, Kit.GOLD))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	bv.add_child(flow)
	for b in Badges.ALL:
		var got: bool = d.badges.has(b.id)
		var c := Kit.chip("%s %s" % [b.icon, b.title], Kit.GOLD.darkened(0.5) if got else Color(1, 1, 1, 0.06), 16)
		c.tooltip_text = b.desc
		if not got:
			c.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		flow.add_child(c)
	# history
	var hp := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
	content.add_child(hp)
	var hv := Kit.vbox(4)
	hp.add_child(hv)
	hv.add_child(Kit.label("최근 주행", 20, Kit.PRIMARY))
	var hist: Array = d.history
	if hist.is_empty():
		hv.add_child(Kit.label("아직 기록이 없어요. 첫 코스를 달려 보세요.", 17, Kit.MUTED))
	for i in range(hist.size() - 1, maxi(hist.size() - 15, 0) - 1, -1):
		var h: Dictionary = hist[i]
		var row := Kit.hbox(10)
		hv.add_child(row)
		row.add_child(Kit.label(Kit.fmt_date(int(h.d)), 15, Kit.MUTED))
		var nm := Kit.label(_key_name(str(h.key)), 17)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(Kit.label("%d점" % int(h.score), 17, Kit.GREEN if bool(h.ok) else Kit.RED))
		row.add_child(Kit.label(Kit.fmt_time(float(h.t)), 15, Kit.MUTED))


func _weakness() -> Array:
	# count deduction kinds from the saved history's disqualification text and
	# from the best-effort "last deductions" list main keeps per run
	var counts := {}
	for h in store.data.history:
		for r in h.get("why", []):
			counts[r] = int(counts.get(r, 0)) + 1
		if h.get("dq", "") != "":
			var dq := "실격: " + str(h.dq)
			counts[dq] = int(counts.get(dq, 0)) + 1
	var arr := []
	for k in counts:
		arr.append([k, counts[k]])
	arr.sort_custom(func(a, b): return a[1] > b[1])
	return arr.slice(0, 4)


func _key_name(key: String) -> String:
	var parts := key.split("/")
	if parts.size() < 2:
		return key
	var id: String = parts[1]
	if id == "exam":
		return KIND_NAME.get(parts[0], parts[0]) + " 모의시험"
	if TowDrills.is_drill(id):
		return TowDrills.info(id).get("title", id)
	var s := Courses.step_by_id(parts[0], id)
	return KIND_NAME.get(parts[0], parts[0]) + " " + str(s.get("title", id))


func _settings() -> void:
	_head("설정")
	var p := Kit.panel(Kit.PANEL_LIGHT, 18, 12)
	content.add_child(p)
	var v := Kit.vbox(6)
	p.add_child(v)
	_toggle(v, "효과음", "sound")
	_toggle(v, "코치 음성 안내", "voice")
	_toggle(v, "진동", "haptic")
	_toggle(v, "미니맵", "minimap")
	_toggle(v, "궤적선 기본 켬", "guide")
	_toggle(v, "왼손잡이 배치 (핸들 오른쪽)", "lefty")
	var sh := Kit.hbox(10)
	v.add_child(sh)
	var sl_lbl := Kit.label("핸들 감도", 19)
	sl_lbl.custom_minimum_size.x = 220
	sh.add_child(sl_lbl)
	var sl := HSlider.new()
	sl.min_value = 0.6
	sl.max_value = 1.6
	sl.step = 0.1
	sl.value = float(store.setting("sens", 1.0))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size.y = 30
	sl.value_changed.connect(func(val): setting_changed.emit("sens", val))
	sh.add_child(sl)
	var ch := Kit.hbox(10)
	v.add_child(ch)
	var cl := Kit.label("기본 시점", 19)
	cl.custom_minimum_size.x = 220
	ch.add_child(cl)
	for pair in [["chase", "뒤에서"], ["top", "위에서"], ["driver", "운전석"]]:
		var cur: bool = str(store.setting("camera", "chase")) == pair[0]
		ch.add_child(Kit.button(pair[1], func(): setting_changed.emit("camera", pair[0]); refresh(), 17, "primary" if cur else "ghost"))
	var p2 := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
	content.add_child(p2)
	var v2 := Kit.vbox(6)
	p2.add_child(v2)
	v2.add_child(Kit.label("구매", 20, Kit.PRIMARY))
	var ph := Kit.hbox(8)
	v2.add_child(ph)
	if purchases.unlocked:
		ph.add_child(Kit.label("전체 해제됨. 고마워요!", 18, Kit.GREEN))
	else:
		ph.add_child(Kit.button("전체 해제", func(): unlock_requested.emit(), 18, "gold"))
	ph.add_child(Kit.button("구매 복원", func(): restore_requested.emit(), 18, "ghost"))
	var p3 := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
	content.add_child(p3)
	var v3 := Kit.vbox(6)
	p3.add_child(v3)
	v3.add_child(Kit.label("정보", 20, Kit.PRIMARY))
	var lh := Kit.hbox(8)
	v3.add_child(lh)
	lh.add_child(Kit.button("개인정보 처리방침", func(): OS.shell_open("https://binibinibin123.github.io/gentive-app-support/forklift-sim/privacy.html"), 16, "ghost"))
	lh.add_child(Kit.button("고객 지원", func(): OS.shell_open("https://binibinibin123.github.io/gentive-app-support/forklift-sim/support.html"), 16, "ghost"))
	v3.add_child(Kit.wrap("지게차·견인 실기 3D %s · 도로교통공단과 관계없는 개인 개발 앱이에요. 채점 기준은 공단 안내를 바탕으로 했고 코스 치수는 근사치예요." % version, 15, Kit.MUTED, 560))


func _toggle(v: VBoxContainer, text: String, key: String) -> void:
	var cb := CheckButton.new()
	cb.text = "  " + text
	cb.add_theme_font_size_override("font_size", 19)
	cb.button_pressed = bool(store.setting(key, true))
	cb.toggled.connect(func(on): setting_changed.emit(key, on))
	v.add_child(cb)
