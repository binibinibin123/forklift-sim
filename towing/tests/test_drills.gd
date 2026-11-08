extends SceneTree
## Runs every drill's demo through the TowAutopilot and prints the outcome.

func _init() -> void:
	for d in TowDrills.LIST:
		if d.id == "free":
			continue
		var e := Exam.new("small", d.id)
		var p := TowAutopilot.new(e)
		e.message.connect(func(t, _k): print("    %6.1fs %s" % [e.t_total, t]))
		e.start()
		var t := 0.0
		while not e.done and t < 400.0:
			p.update(1.0 / 60.0)
			e.update(1.0 / 60.0)
			t += 1.0 / 60.0
		print("%s: done=%s passed=%s score=%d dq=%s t=%.1f" % [d.id, e.done, e.passed, e.score, e.disqualified, e.t_total])
	quit()
