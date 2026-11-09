class_name HomeScreen
extends Control
## The towing exam hub over the 3D yard: a bottom tab bar (모의시험 · 규정표 ·
## 코스 연습 · 훈련장 · 배우기 · 기록 · 설정) and a glass panel on the right
## whose content follows the tab. The left side keeps the title and the way
## back to the app's two-exam home.

signal run_requested(kind: String, id: String, demo: bool)
signal rule_drill_requested(rule_id: String, kind: String)
signal unlock_requested
signal restore_requested
signal lessons_requested
signal forklift_requested
signal setting_changed(key: String, value)
signal tab_changed(tab: String)
signal language_changed(code: String)

const TABS := [["exam", "tow.tab.exam"], ["rulebook", "tow.tab.rulebook"], ["courses", "tow.tab.courses"], ["drills", "tow.tab.drills"],
	["learn", "tow.tab.learn"], ["records", "tow.tab.records"], ["settings", "tow.tab.settings"]]
const KINDS := ["small", "wrecker", "large"]

var store: TowStore
var purchases: Purchases
var tab := "exam"
var rule_kind := "small"
var content: VBoxContainer
var tab_btns := {}
var unlock_btn: Button
var restore_btn: Button
var free_check: Callable   # (kind, id) -> bool
var version := ""


static func kind_name(k: String) -> String:
	return Lang.t("tow.kind." + k)


static func paywall() -> bool:
	return ExamUnlock.paywall_on()


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
	var back := Kit.button(Lang.t("tow.home.back"), func(): forklift_requested.emit(), 18, "ghost")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(back)
	left.add_child(Kit.title(Lang.t("tow.home.title"), 44))
	var st := Kit.title(Lang.t("tow.home.sub"), 21)
	st.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	left.add_child(st)
	left.add_child(Kit.spacer(false))
	var note := Kit.title(Lang.t("tow.home.note"), 18)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	left.add_child(note)
	var btns := Kit.hbox(8)
	left.add_child(btns)
	unlock_btn = Kit.button(Lang.t("tow.buy.unlock"), func(): unlock_requested.emit(), 21, "gold")
	btns.add_child(unlock_btn)
	restore_btn = Kit.button(Lang.t("tow.buy.restore"), func(): restore_requested.emit(), 18, "ghost")
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
		var b := Kit.button(Lang.t(t[1]), func(): select_tab(t[0]), 19)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		th.add_child(b)
		tab_btns[t[0]] = b


func select_tab(t: String) -> void:
	if not tab_btns.has(t):
		t = "exam"
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
	var open := purchases.unlocked or not paywall()
	unlock_btn.visible = paywall() and not open
	restore_btn.visible = paywall() and not open
	unlock_btn.text = (Lang.t("tow.buy.unlock") + " " + purchases.price).strip_edges()
	match tab:
		"courses": _courses(open)
		"exam": _exams(open)
		"rulebook": _rulebook()
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
	return Kit.chip(Lang.t("tow.buy.free") if ok else Lang.t("tow.buy.locked"), Kit.GREEN.darkened(0.4) if ok else Kit.LOCK, 15)


func _best_text(best: int, none_key := "tow.home.no_record") -> String:
	return Lang.t("tow.home.best", [best]) if best >= 0 else Lang.t(none_key)


# ---------------------------------------------------------------- tabs

func _courses(open: bool) -> void:
	_head(Lang.t("tow.tab.courses"), Lang.t("tow.home.courses_sub"))
	for k in KINDS:
		var card := Kit.panel(Kit.PANEL_LIGHT, 18, 14)
		content.add_child(card)
		var v := Kit.vbox(8)
		card.add_child(v)
		var head := Kit.hbox(10)
		v.add_child(head)
		head.add_child(Kit.label(kind_name(k), 26))
		var sub := Kit.label(Lang.t(Rig.SPECS[k].name), 17, Kit.MUTED)
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
			bh.add_child(Kit.label(_best_text(store.best(key)), 15, Kit.MUTED))
			hh.add_child(Kit.button(Lang.t("tow.home.practice"), func(): run_requested.emit(k, p.id, false), 18, "primary" if ok else "lock"))
			hh.add_child(Kit.button(Lang.t("tow.home.demo"), func(): run_requested.emit(k, p.id, true), 18, "ghost" if ok else "lock"))


func _exams(open: bool) -> void:
	_head(Lang.t("tow.home.exam_head"), Lang.t("tow.home.exam_sub"))
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
		th.add_child(Kit.label(Lang.t("tow.home.exam_card", [kind_name(k)]), 26))
		if not open:
			th.add_child(_lock_tag(false))
		var best := store.best(key)
		if best >= Exam.PASS:
			th.add_child(Kit.chip(Lang.t("tow.res.pass"), Kit.GREEN.darkened(0.4), 15))
		v.add_child(Kit.wrap(Lang.t("tow.kind_desc." + k), 17, Kit.MUTED, 520))
		var bh := Kit.hbox(8)
		v.add_child(bh)
		bh.add_child(Kit.stars(store.stars(key), 17))
		bh.add_child(Kit.label(_best_text(best, "tow.home.not_taken"), 16, Kit.MUTED))
		var steps := Courses.exam_steps(k)
		var per := 0
		for s in steps:
			if s.type == "course":
				per = int(s.time_limit / 60)
		bh.add_child(Kit.label(Lang.t("tow.home.exam_meta", [steps.size(), per]), 16, Kit.MUTED))
		h.add_child(Kit.button(Lang.t("tow.home.start"), func(): run_requested.emit(k, "exam", false), 22, "primary" if open else "lock"))
	var info := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
	content.add_child(info)
	var iv := Kit.vbox(4)
	info.add_child(iv)
	iv.add_child(Kit.label(Lang.t("tow.home.summary_head"), 20, Kit.PRIMARY))
	iv.add_child(Kit.wrap(Lang.t("tow.home.summary"), 16, Kit.TEXT, 600))
	var rb := Kit.button(Lang.t("tow.home.open_rulebook"), func(): select_tab("rulebook"), 18, "ghost")
	rb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	iv.add_child(rb)


## The official rows the app grades, per licence; a tap starts a drill that
## reproduces that violation.
func _rulebook() -> void:
	_head(Lang.t("tow.rb.head"), Lang.t("tow.rb.sub"))
	var kh := Kit.hbox(8)
	content.add_child(kh)
	for k in KINDS:
		kh.add_child(Kit.button(kind_name(k), func(): rule_kind = k; refresh(), 18, "primary" if k == rule_kind else "ghost"))
	var src := Kit.wrap(Lang.t("tow.rb.source"), 15, Kit.MUTED, 640)
	content.add_child(src)
	var head := Kit.hbox(10)
	content.add_child(head)
	for col in [[Lang.t("tow.rb.col_item"), 300], [Lang.t("tow.rb.col_pts"), 130], [Lang.t("tow.rb.col_app"), 120], [Lang.t("tow.rb.col_drill"), 120]]:
		var l := Kit.label(col[0], 15, Kit.MUTED)
		l.custom_minimum_size.x = col[1]
		head.add_child(l)
	for r in TowRules.rows_for(rule_kind):
		var rp := Kit.panel(Kit.PANEL_LIGHT, 14, 10)
		content.add_child(rp)
		var h := Kit.hbox(10)
		rp.add_child(h)
		var tv := Kit.vbox(2)
		tv.custom_minimum_size.x = 300
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tv)
		tv.add_child(Kit.label(Lang.t(r.title), 19))
		tv.add_child(Kit.wrap(Lang.t(r.crit), 15, Kit.MUTED, 300))
		tv.add_child(Kit.label(TowRules.source(r), 13, Color(1, 1, 1, 0.5)))
		var pts := TowRules.points_text(r, rule_kind)
		var pl := Kit.label(pts, 19, Kit.RED if pts == Lang.t("tow.r.dq") else Kit.AMBER)
		pl.custom_minimum_size.x = 130
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pl)
		var ck := Kit.chip(Lang.t("tow.rb.checked"), Kit.GREEN.darkened(0.45), 14)
		ck.custom_minimum_size.x = 120
		ck.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ck)
		var b := Kit.button(Lang.t("tow.rb.try"), func(): rule_drill_requested.emit(r.id, rule_kind), 17, "primary")
		b.custom_minimum_size.x = 120
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	content.add_child(Kit.wrap(Lang.t("tow.rb.pass_note", [Exam.PASS]), 15, Kit.MUTED, 640))


func _drills(open: bool) -> void:
	_head(Lang.t("tow.tab.drills"), Lang.t("tow.home.drills_sub"))
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
		th.add_child(Kit.label(Lang.t(d.title), 24))
		if paywall() and (bool(d.free) or not ok):
			th.add_child(_lock_tag(ok))
		v.add_child(Kit.wrap(Lang.t(d.desc), 17, Kit.MUTED, 460))
		if d.id != "free":
			var bh := Kit.hbox(8)
			v.add_child(bh)
			bh.add_child(Kit.stars(store.stars(key), 16))
			bh.add_child(Kit.label(_best_text(store.best(key)), 15, Kit.MUTED))
		h.add_child(Kit.button(Lang.t("tow.home.start"), func(): run_requested.emit("small", d.id, false), 20, "primary" if ok else "lock"))
		if d.id != "free":
			h.add_child(Kit.button(Lang.t("tow.home.demo"), func(): run_requested.emit("small", d.id, true), 18, "ghost" if ok else "lock"))


func _learn() -> void:
	_head(Lang.t("tow.tab.learn"), Lang.t("tow.home.learn_sub"))
	for l in LessonsScreen.LESSONS:
		var card := Kit.panel(Kit.PANEL_LIGHT, 18, 12)
		content.add_child(card)
		var h := Kit.hbox(14)
		card.add_child(h)
		var v := Kit.vbox(3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(Kit.label(Lang.t(l.title), 24))
		v.add_child(Kit.wrap(Lang.t(l.lines[0]), 17, Kit.MUTED, 500))
		h.add_child(Kit.button(Lang.t("tow.home.view"), func(): lessons_requested.emit(), 20, "primary"))


func _records() -> void:
	_head(Lang.t("tow.tab.records"), Lang.t("tow.home.records_sub"))
	var d := store.data
	var stats := Kit.panel(Kit.PANEL_LIGHT, 18, 12)
	content.add_child(stats)
	var sh := Kit.hbox(18)
	stats.add_child(sh)
	for pair in [[Lang.t("tow.home.runs"), Lang.t("tow.home.count", [int(d.runs)])], [Lang.t("tow.home.passes"), Lang.t("tow.home.count", [int(d.passes)])],
			[Lang.t("tow.home.rate"), "%d%%" % int(round(store.pass_rate() * 100))], [Lang.t("tow.home.drive_time"), Kit.fmt_time(float(d.drive_time))]]:
		var v := Kit.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sh.add_child(v)
		v.add_child(Kit.label(pair[1], 30, Kit.PRIMARY))
		v.add_child(Kit.label(pair[0], 15, Kit.MUTED))
	var weak := _weakness()
	if not weak.is_empty():
		var wp := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
		content.add_child(wp)
		var wv := Kit.vbox(4)
		wp.add_child(wv)
		wv.add_child(Kit.label(Lang.t("tow.home.weak"), 20, Kit.AMBER))
		for w in weak:
			wv.add_child(Kit.label("· %s  %s" % [w[0], Lang.t("tow.home.count", [w[1]])], 17))
	var bp := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
	content.add_child(bp)
	var bv := Kit.vbox(6)
	bp.add_child(bv)
	bv.add_child(Kit.label(Lang.t("tow.home.badges", [d.badges.size(), Badges.ALL.size()]), 20, Kit.GOLD))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	bv.add_child(flow)
	for b in Badges.ALL:
		var got: bool = d.badges.has(b.id)
		var c := Kit.chip("%s %s" % [b.icon, Lang.t(b.title)], Kit.GOLD.darkened(0.5) if got else Color(1, 1, 1, 0.06), 16)
		c.tooltip_text = Lang.t(b.desc)
		if not got:
			c.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		flow.add_child(c)
	var hp := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
	content.add_child(hp)
	var hv := Kit.vbox(4)
	hp.add_child(hv)
	hv.add_child(Kit.label(Lang.t("tow.home.recent"), 20, Kit.PRIMARY))
	var hist: Array = d.history
	if hist.is_empty():
		hv.add_child(Kit.label(Lang.t("tow.home.no_history"), 17, Kit.MUTED))
	for i in range(hist.size() - 1, maxi(hist.size() - 15, 0) - 1, -1):
		var h: Dictionary = hist[i]
		var row := Kit.hbox(10)
		hv.add_child(row)
		row.add_child(Kit.label(Kit.fmt_date(int(h.d)), 15, Kit.MUTED))
		var nm := Kit.label(_key_name(str(h.key)), 17)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(Kit.label(Lang.t("tow.home.points", [int(h.score)]), 17, Kit.GREEN if bool(h.ok) else Kit.RED))
		row.add_child(Kit.label(Kit.fmt_time(float(h.t)), 15, Kit.MUTED))


func _weakness() -> Array:
	# count the saved reasons per run (what main stored as "why") and the
	# disqualification reason
	var counts := {}
	for h in store.data.history:
		for r in h.get("why", []):
			counts[r] = int(counts.get(r, 0)) + 1
		if h.get("dq", "") != "":
			var dq := Lang.t("tow.ex.dq_prefix") + str(h.dq)
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
		return Lang.t("tow.home.exam_card", [kind_name(parts[0])])
	if TowDrills.is_drill(id):
		return Lang.t(TowDrills.info(id).get("title", id))
	var s := Courses.step_by_id(parts[0], id)
	return kind_name(parts[0]) + " " + str(s.get("title", id))


func _settings() -> void:
	_head(Lang.t("tow.tab.settings"))
	var lp := Kit.panel(Kit.PANEL_LIGHT, 18, 12)
	content.add_child(lp)
	var lh := Kit.hbox(10)
	lp.add_child(lh)
	var ll := Kit.label(Lang.t("tow.set.language"), 19)
	ll.custom_minimum_size.x = 220
	lh.add_child(ll)
	for pair in [["ko", "한국어"], ["en", "English"]]:
		var cur: bool = Lang.current() == pair[0]
		lh.add_child(Kit.button(pair[1], func(): if not cur: language_changed.emit(pair[0]), 17, "primary" if cur else "ghost"))
	var p := Kit.panel(Kit.PANEL_LIGHT, 18, 12)
	content.add_child(p)
	var v := Kit.vbox(6)
	p.add_child(v)
	_toggle(v, Lang.t("tow.set.sound"), "sound")
	_toggle(v, Lang.t("tow.set.voice"), "voice")
	_toggle(v, Lang.t("tow.set.haptic"), "haptic")
	_toggle(v, Lang.t("tow.set.minimap"), "minimap")
	_toggle(v, Lang.t("tow.set.guide"), "guide")
	_toggle(v, Lang.t("tow.set.lefty"), "lefty")
	var sh := Kit.hbox(10)
	v.add_child(sh)
	var sl_lbl := Kit.label(Lang.t("tow.set.sens"), 19)
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
	var cl := Kit.label(Lang.t("tow.set.camera"), 19)
	cl.custom_minimum_size.x = 220
	ch.add_child(cl)
	for c in ["chase", "top", "driver"]:
		var cur: bool = str(store.setting("camera", "chase")) == c
		ch.add_child(Kit.button(Lang.t("tow.cam." + c), func(): setting_changed.emit("camera", c); refresh(), 17, "primary" if cur else "ghost"))
	if paywall():
		var p2 := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
		content.add_child(p2)
		var v2 := Kit.vbox(6)
		p2.add_child(v2)
		v2.add_child(Kit.label(Lang.t("tow.buy.head"), 20, Kit.PRIMARY))
		var ph := Kit.hbox(8)
		v2.add_child(ph)
		if purchases.unlocked:
			ph.add_child(Kit.label(Lang.t("tow.buy.done"), 18, Kit.GREEN))
		else:
			ph.add_child(Kit.button(Lang.t("tow.buy.unlock"), func(): unlock_requested.emit(), 18, "gold"))
		ph.add_child(Kit.button(Lang.t("tow.buy.restore"), func(): restore_requested.emit(), 18, "ghost"))
	var p3 := Kit.panel(Color(0, 0, 0, 0.22), 14, 12)
	content.add_child(p3)
	var v3 := Kit.vbox(6)
	p3.add_child(v3)
	v3.add_child(Kit.label(Lang.t("tow.set.info"), 20, Kit.PRIMARY))
	var lk := Kit.hbox(8)
	v3.add_child(lk)
	lk.add_child(Kit.button(Lang.t("tow.set.privacy"), func(): OS.shell_open("https://binibinibin123.github.io/gentive-app-support/forklift-sim/privacy.html"), 16, "ghost"))
	lk.add_child(Kit.button(Lang.t("tow.set.support"), func(): OS.shell_open("https://binibinibin123.github.io/gentive-app-support/forklift-sim/support.html"), 16, "ghost"))
	v3.add_child(Kit.wrap(Lang.t("tow.set.about", [version]), 15, Kit.MUTED, 600))


func _toggle(v: VBoxContainer, text: String, key: String) -> void:
	var cb := CheckButton.new()
	cb.text = "  " + text
	cb.add_theme_font_size_override("font_size", 19)
	cb.button_pressed = bool(store.setting(key, true))
	cb.toggled.connect(func(on): setting_changed.emit(key, on))
	v.add_child(cb)
