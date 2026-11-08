class_name Kit
extends RefCounted
## Design tokens and widget factories shared by every screen: deep-blue glass
## panels, sky-blue primary actions, green for pass, amber for warnings.

const BG := Color(0.05, 0.08, 0.13, 0.90)
const BG_SOLID := Color(0.07, 0.10, 0.15, 0.98)
const PANEL := Color(0.09, 0.13, 0.20, 0.86)
const PANEL_LIGHT := Color(0.14, 0.19, 0.27, 0.9)
const STROKE := Color(1, 1, 1, 0.10)
const TEXT := Color(0.97, 0.98, 1.0)
const MUTED := Color(0.70, 0.76, 0.85)
const PRIMARY := Color(0.20, 0.58, 1.0)
const PRIMARY_DARK := Color(0.12, 0.40, 0.80)
const GREEN := Color(0.22, 0.78, 0.50)
const AMBER := Color(1.0, 0.72, 0.18)
const RED := Color(0.96, 0.36, 0.34)
const GOLD := Color(1.0, 0.82, 0.30)
const LOCK := Color(0.22, 0.26, 0.33, 0.9)

static var font: Font
static var theme: Theme


static func setup() -> void:
	if theme:
		return
	font = load("res://fonts/GowunDodum-Regular.ttf")
	var fv := FontVariation.new()
	fv.base_font = font
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR", "sans-serif"])
	fv.fallbacks = [sys]
	font = fv
	theme = Theme.new()
	theme.default_font = fv
	theme.default_font_size = 22
	theme.set_stylebox("normal", "Button", sb(PANEL_LIGHT, 14, 10))
	theme.set_stylebox("hover", "Button", sb(PANEL_LIGHT.lightened(0.08), 14, 10))
	theme.set_stylebox("pressed", "Button", sb(PANEL_LIGHT.darkened(0.2), 14, 10))
	theme.set_stylebox("disabled", "Button", sb(Color(PANEL_LIGHT, 0.45), 14, 10))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", Color(TEXT, 0.4))
	theme.set_stylebox("panel", "PanelContainer", sb(PANEL, 22, 18))
	theme.set_color("font_color", "Label", TEXT)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(1, 1, 1, 0.14)
	sl.set_corner_radius_all(4)
	sl.content_margin_top = 4
	sl.content_margin_bottom = 4
	theme.set_stylebox("slider", "HSlider", sl)
	var gr := StyleBoxFlat.new()
	gr.bg_color = PRIMARY
	gr.set_corner_radius_all(4)
	theme.set_stylebox("grabber_area", "HSlider", gr)
	theme.set_stylebox("grabber_area_highlight", "HSlider", gr)
	var knob := _circle_tex(14, Color.WHITE)
	theme.set_icon("grabber", "HSlider", knob)
	theme.set_icon("grabber_highlight", "HSlider", knob)
	var chk_on := _circle_tex(14, GREEN)
	var chk_off := _circle_tex(14, Color(1, 1, 1, 0.25))
	theme.set_icon("checked", "CheckButton", chk_on)
	theme.set_icon("unchecked", "CheckButton", chk_off)
	theme.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	theme.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	theme.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	theme.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_hover_color", "CheckButton", TEXT)
	theme.set_color("font_pressed_color", "CheckButton", TEXT)


static func _circle_tex(r: int, c: Color) -> ImageTexture:
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * a))
	return ImageTexture.create_from_image(img)


static func sb(c: Color, r: int, pad := 12, border := STROKE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.content_margin_left = pad + 6
	s.content_margin_right = pad + 6
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	if border.a > 0:
		s.set_border_width_all(1)
		s.border_color = border
	return s


static func label(t: String, size := 22, col := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	return l


static func title(t: String, size := 34) -> Label:
	var l := label(t, size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("outline_size", int(size * 0.18))
	return l


static func wrap(t: String, size := 20, col := TEXT, width := 600.0) -> Label:
	var l := label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


## style: "primary" | "green" | "ghost" | "danger" | "gold" | "" (default panel)
static func button(t: String, cb: Callable, size := 22, style := "") -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", size)
	var col := Color(0, 0, 0, 0)
	match style:
		"primary": col = PRIMARY
		"green": col = GREEN.darkened(0.1)
		"danger": col = RED.darkened(0.2)
		"gold": col = Color(0.85, 0.55, 0.12)
		"ghost": col = Color(1, 1, 1, 0.06)
		"lock": col = LOCK
	if col.a > 0:
		b.add_theme_stylebox_override("normal", sb(col, 14, 10, Color(1, 1, 1, 0.14)))
		b.add_theme_stylebox_override("hover", sb(col.lightened(0.1), 14, 10, Color(1, 1, 1, 0.2)))
		b.add_theme_stylebox_override("pressed", sb(col.darkened(0.2), 14, 10, Color(1, 1, 1, 0.1)))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func panel(col := PANEL, radius := 22, pad := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(col, radius, pad))
	return p


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(h := true) -> Control:
	var c := Control.new()
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func gap(px: float, horizontal := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, 0) if horizontal else Vector2(0, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A small pill with a coloured background.
static func chip(t: String, col: Color, size := 17) -> Label:
	var l := label(t, size)
	l.add_theme_stylebox_override("normal", sb(col, 10, 3, Color(0, 0, 0, 0)))
	return l


static func stars(n: int, size := 20) -> Label:
	var s := ""
	for i in 3:
		s += "★" if i < n else "☆"
	return label(s, size, GOLD if n > 0 else Color(1, 1, 1, 0.35))


static func divider() -> Control:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.08)
	c.custom_minimum_size.y = 1
	return c


static func fmt_time(sec: float) -> String:
	var t := int(sec)
	return "%d:%02d" % [t / 60, t % 60]


static func fmt_date(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%d.%02d.%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]
