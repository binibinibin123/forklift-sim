class_name UiKit
extends RefCounted
## 공통 UI 스타일: 어두운 유리 패널 + 주황 포인트.

const INK := Color(0.96, 0.96, 0.94)
const DIM := Color(0.96, 0.96, 0.94, 0.62)
const PANEL := Color(0.05, 0.06, 0.08, 0.8)
const PANEL_SOFT := Color(1, 1, 1, 0.07)
const ACCENT := Color(1.0, 0.62, 0.08)
const RED := Color(0.95, 0.3, 0.25)
const GREEN := Color(0.35, 0.85, 0.45)
const BLUE := Color(0.45, 0.75, 1.0)


static func label(parent: Node, text: String, fs: int, col := INK, outline := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", 5)
	parent.add_child(l)
	return l


static func para(parent: Node, text: String, fs := 21, col := INK, w := 760.0) -> Label:
	var l := label(parent, text, fs, col, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w, 0)
	return l


static func panel(parent: Node, c := PANEL, radius := 18, margin := 22) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_color = Color(1, 1, 1, 0.12)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


static func vbox(parent: Node, sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v


static func hbox(parent: Node, sep := 12, center := false) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	if center:
		h.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(h)
	return h


static func button(parent: Node, text: String, cb: Callable, col := ACCENT, size := Vector2(260, 64), fs := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", fs)
	var dark := col.get_luminance() > 0.55
	b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.09) if dark else INK)
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.09) if dark else INK)
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.08, 0.09) if dark else INK)
	b.add_theme_color_override("font_focus_color", Color(0.08, 0.08, 0.09) if dark else INK)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col if st != "pressed" else col.darkened(0.2)
		if st == "hover":
			sb.bg_color = col.lightened(0.08)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(10)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## 어두운 보조 버튼
static func ghost(parent: Node, text: String, cb: Callable, size := Vector2(200, 56), fs := 21) -> Button:
	return button(parent, text, cb, Color(1, 1, 1, 0.14), size, fs)


static func chip(parent: Node, text: String, col := ACCENT, fs := 17) -> PanelContainer:
	var p := panel(parent, Color(col, 0.22), 10, 6)
	var l := label(p, text, fs, col, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return p


static func rule(parent: Node, col := Color(1, 1, 1, 0.12)) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, 1)
	parent.add_child(r)
	return r


static func spacer(parent: Node, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	parent.add_child(c)
	return c


## 전체 화면 서브 화면: 뒤로 버튼 + 제목 + 스크롤 내용. 반환: 내용 VBox
static func screen(parent: Control, title: String, on_back: Callable) -> Dictionary:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.86)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	root.add_child(margin)
	var v := vbox(margin, 10)
	var head := hbox(v, 16)
	ghost(head, "←  뒤로", on_back, Vector2(130, 50), 20)
	var t := label(head, title, 34, ACCENT)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := vbox(scroll, 14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return {root = root, body = body, head = head, scroll = scroll}
