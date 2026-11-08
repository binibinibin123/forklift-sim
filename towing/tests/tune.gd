extends SceneTree
## Sweep course sizes for the demo line: godot --headless --script res://towing/tests/tune.gd -- small crank fr=4,5 fs=0.5,1
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var kind := a[0]
	var id := a[1]
	var keys := []
	var vals := []
	for x in a.slice(2):
		var kv := x.split("=")
		keys.append(kv[0])
		vals.append(Array(kv[1].split(",")).map(func(v): return float(v)))
	var combos := [{}]
	for i in keys.size():
		var nxt := []
		for c in combos:
			for v in vals[i]:
				var d: Dictionary = c.duplicate()
				d[keys[i]] = v
				nxt.append(d)
		combos = nxt
	for c in combos:
		Courses.tune = c
		var e := Exam.new(kind, id)
		var hits := []
		e.message.connect(func(t, _k): if "검지선" in t or "실격" in t: hits.append("%s %s(%.1f,%.1f)" % [t.substr(0, 6), e.last_hit.get("unit", ""), e.last_hit.get("p", Vector2()).x, e.last_hit.get("p", Vector2()).y]))
		var ap := TowAutopilot.new(e)
		e.start()
		while not e.done and e.t_total < 600.0:
			ap.update(1.0 / 60.0)
			e.update(1.0 / 60.0)
		print("%s score=%d pass=%s t=%.0f %s" % [str(c), e.score, e.passed, e.t_total, " ".join(hits)])
	quit()
