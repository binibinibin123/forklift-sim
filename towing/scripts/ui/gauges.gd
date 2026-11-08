class_name HitchGauge
extends Control
## The articulation (hitch) angle between tractor and trailer as a dial with
## green / amber / red zones. Trailer reversing lives and dies by this angle,
## and nothing in a real cab shows it, so the gauge is the app's teaching aid.

var beta := 0.0          # radians, positive = trailer to the left of the tractor
var coupled := true
var limit := deg_to_rad(88.0)


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.78)
	var r := minf(size.x * 0.46, size.y * 0.7)
	var f := Kit.font
	# background
	draw_circle(c, r + 6, Color(0.05, 0.08, 0.13, 0.75))
	# zones: angle on the dial = beta mapped to -100..+100 degrees of arc
	var k := deg_to_rad(100.0) / limit
	var zones := [[-limit, -deg_to_rad(60), Kit.RED], [-deg_to_rad(60), -deg_to_rad(30), Kit.AMBER],
		[-deg_to_rad(30), deg_to_rad(30), Kit.GREEN], [deg_to_rad(30), deg_to_rad(60), Kit.AMBER], [deg_to_rad(60), limit, Kit.RED]]
	for z in zones:
		var a0: float = -PI / 2 - z[1] * k
		var a1: float = -PI / 2 - z[0] * k
		draw_arc(c, r, a0, a1, 24, Color(z[2], 0.85 if coupled else 0.25), 9.0, true)
	# ticks every 30 degrees
	for deg in [-90, -60, -30, 0, 30, 60, 90]:
		var a := -PI / 2 - deg_to_rad(deg) * k
		var d := Vector2.from_angle(a)
		draw_line(c + d * (r - 10), c + d * (r - 16), Color(1, 1, 1, 0.5), 2.0, true)
	# needle
	var b := clampf(beta, -limit, limit) if coupled else 0.0
	var an := -PI / 2 - b * k
	var nd := Vector2.from_angle(an)
	draw_line(c, c + nd * (r - 20), Color.WHITE, 4.0, true)
	draw_circle(c, 6.0, Color.WHITE)
	var deg := absf(rad_to_deg(b))
	var txt := "히치각 %d°" % int(round(deg)) if coupled else "분리됨"
	var col := Kit.GREEN if deg < 30 else (Kit.AMBER if deg < 60 else Kit.RED)
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 18).x
	draw_string(f, Vector2(c.x - w * 0.5, size.y - 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col if coupled else Kit.MUTED)
	if coupled and deg > 60:
		var warn := "잭나이프 주의"
		var ww := f.get_string_size(warn, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
		draw_string(f, Vector2(c.x - ww * 0.5, c.y - r * 0.35), warn, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Kit.RED)
