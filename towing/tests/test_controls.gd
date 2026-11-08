extends SceneTree
## Drives the real UI with mouse events: dragging the wheel turns it,
## holding the pedal moves the truck, the gear button toggles reverse.

var main: Node
var frame := 0
var fails := 0


func _init() -> void:
	main = load("res://towing/main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1


func _mouse(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	Input.parse_input_event(e)


func _move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


func _process(_d: float) -> bool:
	frame += 1
	match frame:
		5:
			main._go("small", "crank", false)
			main._start_step()
		10:
			var c: Vector2 = main.wheel.get_global_rect().get_center()
			var r: float = main.wheel.size.x * 0.4
			_mouse(c + Vector2(0, -r), true)
			# drag a quarter turn anticlockwise (to the left)
			for i in 10:
				var a := -PI / 2 - (PI / 2) * (i + 1) / 10.0
				_move(c + Vector2(cos(a), sin(a)) * r)
		12:
			var c2: Vector2 = main.wheel.get_global_rect().get_center()
			_mouse(c2, false)
			_check(main.wheel.steer() > 0.1, "wheel turned left by a drag (steer %.2f)" % main.wheel.steer())
			_mouse(main.gas.get_global_rect().get_center(), true)
		30:
			_check(main.exam.rig.v > 0.3, "holding the pedal drives forward (v %.2f)" % main.exam.rig.v)
			_check(main.exam.rig.th > PI / 2 + 0.01, "the truck turns left on the screen too (heading %.2f)" % main.exam.rig.th)
			_mouse(main.gas.get_global_rect().get_center(), false)
			_mouse(main.gear.get_global_rect().get_center(), true)
			_mouse(main.gear.get_global_rect().get_center(), false)
		32:
			_check(main.gear.label == "R", "gear button switches to R")
			print("FAILURES: %d" % fails)
			quit(1 if fails else 0)
	return false
