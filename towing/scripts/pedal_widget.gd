class_name PedalWidget
extends Control
## A hold-to-press pedal (or a tap button when tap is true).

signal tapped

var label := ""
var sub := ""
var color := Color(0.14, 0.19, 0.27)
var held := false
var tap := false
var kind := "pedal"   # pedal | button


func press(_p: Vector2) -> void:
	held = true
	if tap:
		tapped.emit()
	queue_redraw()


func drag(_p: Vector2) -> void:
	pass


func release() -> void:
	held = false
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.lightened(0.22) if held else color
	sb.bg_color.a = 0.94
	sb.set_corner_radius_all(18)
	sb.border_color = Color(1, 1, 1, 0.55 if held else 0.16)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	draw_style_box(sb, r)
	var f := Kit.font
	if not tap:   # tread ridges
		var n := 5
		for i in n:
			var y := size.y * (0.22 + i * 0.11)
			draw_line(Vector2(size.x * 0.2, y), Vector2(size.x * 0.8, y), Color(1, 1, 1, 0.10), 5.0)
		draw_line(Vector2(size.x * 0.2, size.y * 0.22), Vector2(size.x * 0.8, size.y * 0.22), Color(1, 1, 1, 0.2), 2.0)
	var fs := 32 if label.length() <= 2 else 23
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var ty := size.y * 0.5 + fs * 0.35 if sub == "" else size.y * 0.5 + fs * 0.1
	if not tap:
		ty = size.y - 26.0
	draw_string(f, Vector2((size.x - w) * 0.5, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if sub != "":
		var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
		draw_string(f, Vector2((size.x - sw) * 0.5, ty + 22), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Kit.MUTED)
