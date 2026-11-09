class_name Drills
extends RefCounted
## Start states for Sim.start_drill(): six course stages, and one drill per graded rule
## that sets up the moment just before that violation (rulebook rows open these).

const REACH := Sim.CARRIAGE + Sim.FORK_LEN - Sim.PALLET * 0.5   # front axle -> pallet centre, full insertion


## Course stages, in exam order.
static func list(c: Course) -> Array:
	var cy := c.center.y
	var ux := Route.unload_x(c)
	return [
		{id = "start", pos = c.start_pos, heading = c.start_heading, lift = 0.0, step = Sim.Step.READY, goal = Sim.Step.TO_LOAD,
			seatbelt = false, park_brake = true},
		{id = "load", pos = Vector2(0.0, 10.6), heading = PI / 2, lift = 0.25, step = Sim.Step.TO_LOAD, goal = Sim.Step.LOADED},
		{id = "forward", pos = Vector2(0.0, 9.5), heading = PI / 2, lift = 0.25, tilt = 4.0, carried = true,
			step = Sim.Step.LOADED, goal = Sim.Step.UNLOADED},
		{id = "touch", pos = Vector2(ux, cy), heading = PI, lift = Sim.PALLET_H + 0.04, step = Sim.Step.UNLOADED, goal = Sim.Step.TOUCHED,
			pallet = c.guide_pos, pallet_heading = c.guide_heading, pallet_base = Sim.PALLET_H, engaged = true},
		{id = "reverse", pos = Vector2(Route.touch_x(c), cy), heading = PI, lift = 0.0, step = Sim.Step.TOUCHED, goal = Sim.Step.RETURNED,
			pallet = c.guide_pos, pallet_heading = c.guide_heading, pallet_base = Sim.PALLET_H},
		{id = "park", pos = Vector2(0.0, 11.0), heading = PI / 2, lift = 0.25, step = Sim.Step.RETURNED, goal = Sim.Step.PARKED,
			pallet = c.pallet_start, pallet_heading = c.pallet_start_heading, pallet_base = c.drum_height},
	]


static func by_id(c: Course, id: String) -> Dictionary:
	for d in list(c):
		if d.id == id:
			return d
	return {}


## One drill per checked rule row; they stop at the first fault like the exam.
static func rule_drill(c: Course, rule_id: String) -> Dictionary:
	var cy := c.center.y
	var cx := c.center.x
	var ux := Route.unload_x(c)
	var rm := Route.mid_r(c)
	var near_drum := c.drum_pos.y - REACH
	var d := {}
	match rule_id:
		"r2":
			d = {pos = Vector2(ux + 1.6, cy), heading = PI, lift = 0.25, tilt = 4.0, carried = true, step = Sim.Step.LOADED,
				goal = Sim.Step.UNLOADED, route = ["center", "north"], t_exam = 230.0}
		"r3":
			d = {pos = Vector2(cx + 3.0, cy), heading = PI, lift = 0.25, tilt = 4.0, carried = true, step = Sim.Step.LOADED, goal = Sim.Step.UNLOADED}
		"r4":
			d = {pos = c.start_pos, heading = c.start_heading, lift = 0.0, step = Sim.Step.READY, goal = Sim.Step.TO_LOAD,
				park_brake = true, t_signal = 48.0}
		"r6":
			d = {pos = c.start_pos, heading = c.start_heading, lift = 0.0, step = Sim.Step.READY, goal = Sim.Step.TO_LOAD}
		"r7":
			var a := deg_to_rad(118.0)
			d = {pos = c.center + Vector2(cos(a), sin(a)) * rm, heading = a + PI / 2 - deg_to_rad(14.0), lift = 0.25, tilt = 4.0,
				carried = true, step = Sim.Step.LOADED, goal = Sim.Step.UNLOADED, route = ["center", "north"]}
		"r8":
			d = {pos = Vector2(0.0, near_drum - 0.25), heading = PI / 2, lift = c.drum_height + 0.04, step = Sim.Step.TO_LOAD, goal = Sim.Step.LOADED,
				engaged = false}
		"r9":
			d = {pos = Vector2(0.0, 11.4), heading = PI / 2, lift = c.drum_height + 0.11, step = Sim.Step.TO_LOAD, goal = Sim.Step.LOADED}
		"r10":
			d = {pos = Vector2(0.25, 11.4), heading = PI / 2, lift = 0.6, step = Sim.Step.TO_LOAD, goal = Sim.Step.LOADED}
		"r11":
			d = {pos = Vector2(-0.6, cy), heading = PI, lift = 0.25, step = Sim.Step.TO_LOAD, goal = Sim.Step.LOADED}
		"r12":
			d = {pos = Vector2(cx + 5.0, cy), heading = PI, lift = 0.12, tilt = 4.0, carried = true, step = Sim.Step.LOADED, goal = Sim.Step.UNLOADED}
		"r13":
			d = {pos = Vector2(c.unload_line_x + 2.6, cy), heading = PI, lift = 0.1, step = Sim.Step.UNLOADED, goal = Sim.Step.TOUCHED,
				pallet = c.guide_pos, pallet_heading = c.guide_heading, pallet_base = Sim.PALLET_H}
		"r14":
			d = {pos = Vector2(cx, cy + 3.5), heading = PI / 2, lift = 0.42, tilt = 4.0, carried = true, step = Sim.Step.LOADED,
				goal = Sim.Step.UNLOADED, route = ["center"]}
		"r15":
			d = {pos = Vector2(ux, cy + 0.23), heading = PI, lift = 0.3, tilt = 0.0, carried = true, step = Sim.Step.LOADED,
				goal = Sim.Step.UNLOADED, route = ["center", "north"]}
		"r16":
			d = {pos = Vector2(ux + 0.25, cy), heading = PI, lift = Sim.PALLET_H + 0.045, step = Sim.Step.TOUCHED, goal = Sim.Step.RELOADED,
				pallet = c.guide_pos, pallet_heading = c.guide_heading, pallet_base = Sim.PALLET_H, engaged = true}
		"r17":
			d = {pos = Vector2(ux + 1.25, cy), heading = PI, lift = 0.08, step = Sim.Step.TOUCHED, goal = Sim.Step.RELOADED,
				pallet = c.guide_pos, pallet_heading = c.guide_heading, pallet_base = Sim.PALLET_H}
		"r18":
			d = {pos = Vector2(0.0, near_drum - 0.35), heading = PI / 2, lift = c.drum_height + 0.04, step = Sim.Step.TO_LOAD, goal = Sim.Step.LOADED,
				pallet = c.pallet_start, pallet_heading = c.pallet_start_heading, pallet_base = c.drum_height, engaged = true}
		_:
			return {}
	d.id = rule_id
	d.rule = rule_id
	d.exam = true
	return d
