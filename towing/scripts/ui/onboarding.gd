class_name Onboarding
extends Control
## Three cards on first launch: what the app is, how to drive, what's free.

signal done

const PAGES := [
	{"title": "tow.ob.1", "body": "tow.ob.1.b"},
	{"title": "tow.ob.2", "body": "tow.ob.2.b"},
	{"title": "tow.ob.3", "body": "tow.ob.3.b"},
]

var page := 0
var title_lbl: Label
var body_lbl: Label
var dots: HBoxContainer
var next_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var p := Kit.panel(Kit.BG_SOLID, 26, 28)
	cc.add_child(p)
	var v := Kit.vbox(14)
	v.custom_minimum_size = Vector2(680, 0)
	p.add_child(v)
	title_lbl = Kit.label("", 36, Kit.PRIMARY)
	v.add_child(title_lbl)
	body_lbl = Kit.wrap("", 22, Kit.TEXT, 680)
	v.add_child(body_lbl)
	var row := Kit.hbox(10)
	v.add_child(row)
	dots = Kit.hbox(6)
	row.add_child(dots)
	row.add_child(Kit.spacer())
	row.add_child(Kit.button(Lang.t("tow.ob.skip"), func(): done.emit(), 19, "ghost"))
	next_btn = Kit.button(Lang.t("tow.ob.next"), _next, 22, "primary")
	row.add_child(next_btn)
	_show(0)


func _show(i: int) -> void:
	page = i
	title_lbl.text = Lang.t(PAGES[i].title)
	body_lbl.text = Lang.t(PAGES[i].body)
	for c in dots.get_children():
		c.queue_free()
	for k in PAGES.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(12, 12)
		d.color = Kit.PRIMARY if k == i else Color(1, 1, 1, 0.25)
		dots.add_child(d)
	next_btn.text = Lang.t("tow.ob.go") if i == PAGES.size() - 1 else Lang.t("tow.ob.next")


func _next() -> void:
	if page + 1 >= PAGES.size():
		done.emit()
	else:
		_show(page + 1)
