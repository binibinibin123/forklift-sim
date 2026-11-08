class_name Cluster
extends Control
## Compact instrument cluster: speed, gear, steering angle and the brake /
## reverse lamp indicators, drawn as one glass tile.

var speed_kmh := 0.0
var reverse := false
var steer_text := ""
var braking := false
var throttle := false


func _draw() -> void:
	var f := Kit.font
	var sbx := StyleBoxFlat.new()
	sbx.bg_color = Color(0.05, 0.08, 0.13, 0.78)
	sbx.set_corner_radius_all(16)
	sbx.border_color = Color(1, 1, 1, 0.12)
	sbx.set_border_width_all(1)
	draw_style_box(sbx, Rect2(Vector2.ZERO, size))
	# gear badge
	var gcol := Kit.RED if reverse else Kit.GREEN
	var gr := Rect2(Vector2(12, 12), Vector2(44, 44))
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(gcol, 0.9)
	gsb.set_corner_radius_all(10)
	draw_style_box(gsb, gr)
	var g := "R" if reverse else "D"
	var gw := f.get_string_size(g, HORIZONTAL_ALIGNMENT_CENTER, -1, 30).x
	draw_string(f, gr.position + Vector2((44 - gw) * 0.5, 33), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
	# speed
	var sp := "%d" % int(round(speed_kmh))
	draw_string(f, Vector2(68, 44), sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)
	var spw := f.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(f, Vector2(68 + spw + 6, 44), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Kit.MUTED)
	# speed bar
	var bar := Rect2(Vector2(12, 64), Vector2(size.x - 24, 6))
	draw_rect(bar, Color(1, 1, 1, 0.1))
	var frac := clampf(speed_kmh / 12.0, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, 6)), Kit.PRIMARY if not reverse else Kit.AMBER)
	# steering text and lamps
	draw_string(f, Vector2(12, size.y - 10), steer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Kit.MUTED)
	var lx := size.x - 16
	draw_circle(Vector2(lx, size.y - 16), 6, Kit.RED if braking else Color(Kit.RED, 0.2))
	draw_circle(Vector2(lx - 18, size.y - 16), 6, Color(0.9, 0.95, 1.0) if reverse else Color(1, 1, 1, 0.15))
