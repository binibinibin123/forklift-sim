extends SceneTree
## Headless smoke run of the real towing screens: every home tab in both
## languages, every rulebook drill for every licence, a freeze frame on a
## line touch (scrub + continue), and the score sheet after a disqualification.
## godot --headless --path . --audio-driver Dummy --script res://towing/tests/test_screens.gd

var main: Node
var frame := 0
var fails := 0
var stage := 0


func _init() -> void:
	Lang.code = "ko"
	main = load("res://towing/main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	print("  ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1


func _process(_d: float) -> bool:
	frame += 1
	if frame == 3:
		for code in ["ko", "en"]:
			Lang.code = code
			for t in HomeScreen.TABS:
				main.home.select_tab(t[0])
				_check(main.home.content.get_child_count() > 0, "%s: home tab %s has content" % [code, t[0]])
			main.home.rule_kind = "large"
			main.home.select_tab("rulebook")
		Lang.code = "ko"
		_check(not main.unlock_panel.visible and not main.home.unlock_btn.visible, "paywall off: no purchase UI")
		for r in TowRules.ROWS:
			for k in ["small", "wrecker", "large"]:
				if not r.pts.has(k):
					continue
				main.start_rule_drill(r.id, k)
				_check(main.exam != null and not main.exam.done and main.screen == "drive", "rule drill %s / %s starts live" % [r.id, k])
		main.start_rule_drill("jackknife", "small")
		_check(absf(rad_to_deg(main.exam.rig.beta())) > 55.0, "jackknife drill starts already folded (%.0f°)" % absf(rad_to_deg(main.exam.rig.beta())))
		main.start_rule_drill("order", "large")
		_check(main.exam.aligned and main.hud.check_panel.visible, "order drill opens the checklist")
		# line touch: hold the gas with the wheel straight before the bend
		main.start_rule_drill("line", "small")
		main._start_step()
		main.autodrive = true
		main.hud.wheel.set_steer(0.0)
		stage = 1
	elif stage == 1:
		if main.freeze_on:
			_check(main.hud.freeze_open() and str(main.freeze_v.get("code", "")) == "line", "line touch freezes the run")
			_check(main.paused, "frozen run is paused")
			_check("cm" in main.hud.freeze_body.text, "freeze shows the measured distance: " + main.hud.freeze_body.text.replace("\n", " | "))
			var pos_before: Vector2 = main.exam.rig.pos
			main._freeze_scrub(maxf(float(main.freeze_v.t) - 3.0, 0.0))
			_check(main.exam.rig.pos.distance_to(pos_before) > 0.3, "scrubbing moves the rig back")
			main._close_freeze()
			_check(main.exam.rig.pos.distance_to(pos_before) < 0.01 and not main.paused, "continue restores the live pose and runs on")
			main.autodrive = false
			# exam-day start window, run out: disqualified and the score sheet
			main.start_rule_drill("start_late", "small")
			main._start_step()
			stage = 2
		elif frame > 900:
			_check(false, "line touch freezes the run (timed out)")
			stage = 3
	elif stage == 2:
		if main.freeze_on:
			_check(str(main.freeze_v.code) == "start_late" and main.hud.freeze_res.visible, "start window: disqualified, freeze offers the score sheet")
			main.hud.freeze_result.emit()
			main.result.show_result(main.exam, {}, [], false, false)
			_check(main.screen == "result", "score sheet shown")
			_check(main.result.body.get_child_count() > 6, "score sheet has rows")
			stage = 3
		elif frame > 2000:
			_check(false, "start window disqualifies (timed out)")
			stage = 3
	elif stage == 3:
		print("FAILURES: %d" % fails)
		quit(1 if fails else 0)
	return false
