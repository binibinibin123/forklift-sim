class_name WorldProps
extends RefCounted
## Scenery around the exam yard: a suburban Korean 운전면허시험장 with a
## blue-roofed examiner building, visitor parking, an observation tower, a
## waiting shelter, light poles, a green mesh fence, a tree-lined road to the
## south, hedges, a treeline and low hills. Everything is batched into a few
## meshes (one per material group) and cached per yard layout, so a rebuild
## only re-adds nodes. All props stay outside the asphalt pads.

const BLUE := Color(0.1, 0.33, 0.66)       # roofs / signage blue
const BLUE_DARK := Color(0.08, 0.25, 0.5)
const CREAM := Color(0.9, 0.89, 0.84)
const STEEL := Color(0.6, 0.62, 0.64)
const GLASS := Color(0.2, 0.3, 0.42)
const FENCE_GREEN := Color(0.18, 0.4, 0.26)
const WOOD := Color(0.5, 0.36, 0.22)

static var _cache := {}      # layout key -> [{mesh, mat, shadow}]
static var _fence_tex: Texture2D

var world: TowWorld
var all: Rect2
var out: Array = []
var rng := RandomNumberGenerator.new()

# layout (ground coordinates)
var apron: Rect2
var fence: Rect2
var fore: Rect2          # concrete forecourt south of the yard
var bpos: Vector2        # examiner building centre
var bsize := Vector3(16.0, 7.4, 9.0)
var gate := Vector2.ZERO # x range of the gate in the south fence
var road_y := 0.0        # road centre line (ground y)
const ROAD_W := 8.0
const WALK_W := 2.5


static func build(w: TowWorld, yard: Rect2) -> void:
	var p := WorldProps.new()
	p.world = w
	p.all = yard
	p.rng.seed = 1234
	p._layout()
	var key := str(yard)
	if _cache.has(key):
		for e in _cache[key]:
			w.add_mesh(e.mesh, Vector3.ZERO, e.mat, 0.0, Vector3.ONE, e.shadow)
	else:
		p._ground()
		p._building()
		p._tower()
		p._shelter()
		p._flags()
		p._parking()
		p._light_poles()
		p._fence()
		p._barriers()
		p._trees()
		p._hills()
		_cache[key] = p.out
	p._labels()


func _layout() -> void:
	apron = all.grow(4.0)
	fence = Rect2(all.position.x - 9.0, all.position.y - 33.0, all.size.x + 18.0, all.size.y + 42.0)
	var fx1 := minf(all.end.x + 2.0, all.position.x + 92.0)
	fore = Rect2(all.position.x - 2.0, all.position.y - 30.0, fx1 - (all.position.x - 2.0), 24.0)
	bpos = Vector2(all.position.x + 12.0, all.position.y - 19.5)
	gate = Vector2(bpos.x + 10.0, bpos.x + 16.0)
	road_y = fence.position.y - 2.4 - WALK_W - ROAD_W * 0.5


func _emit(b: TowWorld.Batch, m: Material, shadow := true) -> void:
	var mi := b.commit(world, m, shadow)
	if mi:
		out.append({"mesh": mi.mesh, "mat": m, "shadow": shadow})


func _emit_quad(r: Rect2, y: float, m: Material) -> void:
	var mi := world.quad(r, y, m)
	out.append({"mesh": mi.mesh, "mat": m, "shadow": false})


func _emit_lines(st: SurfaceTool, c: Color) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var m := world.paint_mat(c)
	world.add_mesh(mesh, Vector3.ZERO, m, 0.0, Vector3.ONE, false)
	out.append({"mesh": mesh, "mat": m, "shadow": false})


func _sphere(r := 1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


# ---------------------------------------------------------------- ground

func _ground() -> void:
	var conc := world.concrete_mat()
	_emit_quad(fore, TowWorld.Y_APRON, conc)
	# driveway from the gate to the road, across the hedge line and footpath
	var dx0 := gate.x - 1.0
	var dx1 := gate.y + 1.0
	_emit_quad(Rect2(dx0, road_y + ROAD_W * 0.5, dx1 - dx0, fore.position.y - (road_y + ROAD_W * 0.5)), TowWorld.Y_APRON + 0.002, conc)
	# road with footpaths on both sides
	var rx0 := fence.position.x - 70.0
	var rx1 := fence.end.x + 70.0
	_emit_quad(Rect2(rx0, road_y - ROAD_W * 0.5, rx1 - rx0, ROAD_W), TowWorld.Y_APRON, world.asphalt_mat())
	_emit_quad(Rect2(rx0, road_y + ROAD_W * 0.5, rx1 - rx0, WALK_W), TowWorld.Y_APRON + 0.001, conc)
	_emit_quad(Rect2(rx0, road_y - ROAD_W * 0.5 - WALK_W, rx1 - rx0, WALK_W), TowWorld.Y_APRON + 0.001, conc)
	# road kerbs
	var kb := TowWorld.Batch.new()
	var kc := Color(0.8, 0.8, 0.77)
	for yy in [road_y + ROAD_W * 0.5, road_y - ROAD_W * 0.5]:
		kb.box(Vector3((rx0 + rx1) * 0.5, 0.06, -yy), Vector3(rx1 - rx0, 0.12, 0.25), kc)
	_emit(kb, world.vmat(0.8))
	# road markings: yellow dashed centre line, white edge lines
	var yel := SurfaceTool.new()
	yel.begin(Mesh.PRIMITIVE_TRIANGLES)
	world._polyline_into(yel, PackedVector2Array([Vector2(rx0, road_y), Vector2(rx1, road_y)]), 0.15, TowWorld.Y_LINE, true, 3.0, 8.0)
	_emit_lines(yel, TowWorld.YELLOW)
	var wh := SurfaceTool.new()
	wh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for yy in [road_y + ROAD_W * 0.5 - 0.3, road_y - ROAD_W * 0.5 + 0.3]:
		world._polyline_into(wh, PackedVector2Array([Vector2(rx0, yy), Vector2(rx1, yy)]), 0.15, TowWorld.Y_LINE, false)
	# pedestrian crossing in front of the gate
	for i in 7:
		var x := dx0 + 0.5 + i * 1.0
		world._polyline_into(wh, PackedVector2Array([Vector2(x, road_y - 3.0), Vector2(x, road_y + 3.0)]), 0.5, TowWorld.Y_LINE, false)
	_emit_lines(wh, TowWorld.WHITE)


# ---------------------------------------------------------------- buildings

func _building() -> void:
	var p := bpos
	var sz := bsize
	var walls := TowWorld.Batch.new()
	var c := TowWorld.w(p, sz.y * 0.5)
	walls.box(c, sz, CREAM)
	# plinth, floor band and corner pilasters
	walls.box(TowWorld.w(p, 0.3), Vector3(sz.x + 0.3, 0.6, sz.z + 0.3), Color(0.55, 0.56, 0.56))
	walls.box(TowWorld.w(p, 3.75), Vector3(sz.x + 0.16, 0.35, sz.z + 0.16), Color(0.97, 0.97, 0.96))
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			walls.box(TowWorld.w(p + Vector2(sx * sz.x * 0.5, sy * sz.z * 0.5), sz.y * 0.5), Vector3(0.5, sz.y, 0.5), Color(0.97, 0.97, 0.96))
	# stair block and entrance canopy on the yard (north) face
	var north := p + Vector2(0, sz.z * 0.5)
	walls.box(TowWorld.w(north + Vector2(0, 0.8), 0.1), Vector3(5.0, 0.2, 1.6), Color(0.6, 0.6, 0.6))
	walls.box(TowWorld.w(north + Vector2(0, 0.4), 0.25), Vector3(5.0, 0.1, 0.8), Color(0.6, 0.6, 0.6))
	walls.box(TowWorld.w(north + Vector2(0, 1.4), 3.1), Vector3(6.0, 0.22, 2.8), Color(0.97, 0.97, 0.96))
	walls.box(TowWorld.w(north + Vector2(0, 1.4), 3.3), Vector3(6.2, 0.18, 3.0), BLUE)
	walls.box(TowWorld.w(north + Vector2(-2.6, 2.6), 1.6), Vector3(0.14, 3.2, 0.14), STEEL)
	walls.box(TowWorld.w(north + Vector2(2.6, 2.6), 1.6), Vector3(0.14, 3.2, 0.14), STEEL)
	# sign board above the entrance
	walls.box(TowWorld.w(north + Vector2(0, 0.12), 6.4), Vector3(9.0, 1.3, 0.2), Color(0.98, 0.98, 0.97))
	walls.box(TowWorld.w(north + Vector2(0, 0.1), 6.4), Vector3(9.1, 1.38, 0.18), BLUE)
	# rooftop parapet and plant room
	walls.box(TowWorld.w(p, sz.y + 0.2), Vector3(sz.x + 0.4, 0.4, sz.z + 0.4), Color(0.97, 0.97, 0.96))
	walls.box(TowWorld.w(p + Vector2(-4.5, -1.5), sz.y + 1.1), Vector3(3.0, 2.2, 2.6), CREAM)
	_emit(walls, world.vmat(0.8))
	# blue hipped roof over the main block
	var roof := TowWorld.Batch.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(sz.x + 1.4, 2.4, sz.z + 1.4)
	roof.add(pm, Transform3D(Basis.IDENTITY, TowWorld.w(p, sz.y + 0.4 + 1.2)), BLUE)
	roof.box(TowWorld.w(p, sz.y + 0.45), Vector3(sz.x + 1.6, 0.14, sz.z + 1.6), BLUE_DARK)
	roof.box(TowWorld.w(p + Vector2(-4.5, -1.5), sz.y + 2.3), Vector3(3.4, 0.16, 3.0), BLUE)
	_emit(roof, world.vmat(0.45, 0.25))
	# windows: white frames with dark reflective glass, two floors, north + south
	var frames := TowWorld.Batch.new()
	var glass := TowWorld.Batch.new()
	for side: int in [-1, 1]:
		var zf: float = -(p.y + side * sz.z * 0.5)
		for floor_i in 2:
			var yc := 1.9 + floor_i * 3.4
			for k in 7:
				var x := p.x - sz.x * 0.5 + 1.6 + k * 2.1
				if side > 0 and floor_i == 0 and absf(x - p.x) < 2.6:
					continue
				frames.box(Vector3(x, yc, zf + side * 0.04), Vector3(1.75, 1.55, 0.08), Color(0.97, 0.97, 0.96))
				glass.box(Vector3(x, yc, zf + side * 0.08), Vector3(1.55, 1.35, 0.06), GLASS)
				frames.box(Vector3(x, yc - 0.85, zf + side * 0.12), Vector3(1.9, 0.08, 0.22), Color(0.97, 0.97, 0.96))
	for side: int in [-1, 1]:
		var xf: float = p.x + side * sz.x * 0.5
		for floor_i in 2:
			var yc := 1.9 + floor_i * 3.4
			for k in 3:
				var zc := -(p.y - sz.z * 0.5 + 1.7 + k * 2.8)
				frames.box(Vector3(xf + side * 0.04, yc, zc), Vector3(0.08, 1.55, 1.75), Color(0.97, 0.97, 0.96))
				glass.box(Vector3(xf + side * 0.08, yc, zc), Vector3(0.06, 1.35, 1.55), GLASS)
	# glass entrance door
	glass.box(Vector3(p.x, 1.4, -(p.y + sz.z * 0.5) - 0.06), Vector3(2.6, 2.6, 0.08), GLASS)
	frames.box(Vector3(p.x, 1.4, -(p.y + sz.z * 0.5) - 0.03), Vector3(2.8, 2.8, 0.06), STEEL)
	_emit(frames, world.vmat(0.6))
	_emit(glass, world.vmat(0.12, 0.7, "glass"))
	# low hedges flanking the entrance stairs and along the building front
	var hedge := TowWorld.Batch.new()
	for sx: int in [-1, 1]:
		hedge.box(TowWorld.w(north + Vector2(sx * 5.2, 0.8), 0.45), Vector3(4.6, 0.9, 1.0), Color(0.26, 0.46, 0.2))
	_emit(hedge, _hedge_mat())


func _labels() -> void:
	var north := bpos + Vector2(0, bsize.z * 0.5)
	var l := Label3D.new()
	l.text = "운전면허시험장"
	l.font = load("res://fonts/IBMPlexSansKR-Medium.ttf")
	l.font_size = 96
	l.pixel_size = 0.0105
	l.modulate = Color(0.06, 0.26, 0.58)
	l.position = TowWorld.w(north + Vector2(0, 0.24), 6.4)
	l.rotation_degrees = Vector3(0, 180, 0)
	world.add_child(l)
	var l2 := Label3D.new()
	l2.text = "장내기능시험 코스"
	l2.font = l.font
	l2.font_size = 56
	l2.pixel_size = 0.0072
	l2.modulate = Color(0.97, 0.97, 0.96)
	l2.position = TowWorld.w(north + Vector2(0, 1.4), 2.78)
	l2.rotation_degrees = Vector3(0, 180, 0)
	world.add_child(l2)
	var l3 := Label3D.new()
	l3.text = "대기실"
	l3.font = l.font
	l3.font_size = 48
	l3.pixel_size = 0.006
	l3.modulate = Color(0.97, 0.97, 0.96)
	var sp := _shelter_pos()
	l3.position = TowWorld.w(sp + Vector2(0, 1.3), 2.55)
	l3.rotation_degrees = Vector3(0, 180, 0)
	world.add_child(l3)


func _hedge_mat() -> StandardMaterial3D:
	var alb := TowWorld.noise_tex("hedge_a", 0.06, 61, TowWorld.ramp([
		[0.0, Color(0.14, 0.3, 0.1)], [0.5, Color(0.24, 0.44, 0.17)], [1.0, Color(0.38, 0.56, 0.24)]]), false, 256, 4, FastNoiseLite.TYPE_CELLULAR)
	var nrm := TowWorld.noise_tex("hedge_n", 0.1, 62, null, true, 256, 3, FastNoiseLite.TYPE_CELLULAR)
	var m := world.tex_mat("hedge", alb, nrm, 0.95, 0.8)
	m.vertex_color_use_as_albedo = false
	m.uv1_scale = Vector3(2.5, 2.5, 2.5)
	return m


func _tower() -> void:
	var p := Vector2(all.end.x + 6.0, all.get_center().y)
	var b := TowWorld.Batch.new()
	var legs := 1.2
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			b.add(TowWorld._cyl(0.1, 0.12, 7.6, 10), Transform3D(Basis.IDENTITY, TowWorld.w(p + Vector2(sx * legs, sy * legs), 3.8)), STEEL)
	for h in [2.4, 4.9]:
		b.box(TowWorld.w(p, h), Vector3(legs * 2.0 + 0.2, 0.1, 0.1), STEEL)
		b.box(TowWorld.w(p, h), Vector3(0.1, 0.1, legs * 2.0 + 0.2), STEEL)
		b.box(TowWorld.w(p + Vector2(0, legs), h), Vector3(legs * 2.0 + 0.2, 0.1, 0.1), STEEL)
		b.box(TowWorld.w(p + Vector2(0, -legs), h), Vector3(legs * 2.0 + 0.2, 0.1, 0.1), STEEL)
	# stair tower
	b.box(TowWorld.w(p + Vector2(-1.9, 0), 3.8), Vector3(0.9, 7.6, 1.4), Color(0.7, 0.72, 0.74))
	# cabin with glass band and blue roof
	b.box(TowWorld.w(p, 7.9), Vector3(3.4, 0.6, 3.4), Color(0.97, 0.97, 0.96))
	b.box(TowWorld.w(p, 9.95), Vector3(3.5, 0.35, 3.5), Color(0.97, 0.97, 0.96))
	b.box(TowWorld.w(p, 7.6), Vector3(4.6, 0.1, 4.6), STEEL)           # walkway
	for sx: int in [-1, 1]:
		b.box(TowWorld.w(p + Vector2(sx * 2.25, 0), 8.1), Vector3(0.05, 0.9, 4.5), STEEL)
		b.box(TowWorld.w(p + Vector2(0, sx * 2.25), 8.1), Vector3(4.5, 0.9, 0.05), STEEL)
	_emit(b, world.vmat(0.6, 0.2))
	var g := TowWorld.Batch.new()
	g.box(TowWorld.w(p, 9.0), Vector3(3.3, 1.6, 3.3), GLASS)
	_emit(g, world.vmat(0.12, 0.7, "glass"))
	var r := TowWorld.Batch.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(4.2, 1.0, 4.2)
	r.add(pm, Transform3D(Basis.IDENTITY, TowWorld.w(p, 10.6)), BLUE)
	_emit(r, world.vmat(0.45, 0.25))


func _shelter_pos() -> Vector2:
	return Vector2(bpos.x + 18.0, all.position.y - 10.5)


func _shelter() -> void:
	var p := _shelter_pos()
	var b := TowWorld.Batch.new()
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			b.add(TowWorld._cyl(0.07, 0.07, 2.6, 10), Transform3D(Basis.IDENTITY, TowWorld.w(p + Vector2(sx * 2.4, sy * 1.2), 1.3)), STEEL)
	b.box(TowWorld.w(p, 2.62), Vector3(5.6, 0.06, 3.2), Color(0.97, 0.97, 0.96))
	# back wall (south) and bench
	b.box(TowWorld.w(p + Vector2(0, -1.25), 1.3), Vector3(5.2, 2.6, 0.06), Color(0.85, 0.87, 0.88))
	for sx: int in [-1, 1]:
		b.box(TowWorld.w(p + Vector2(sx * 1.5, -0.7), 0.22), Vector3(0.08, 0.44, 0.45), STEEL)
	_emit(b, world.vmat(0.6, 0.2))
	var r := TowWorld.Batch.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(5.8, 0.55, 3.4)
	r.add(pm, Transform3D(Basis.IDENTITY, TowWorld.w(p, 2.95)), BLUE)
	_emit(r, world.vmat(0.45, 0.25))
	var wood := TowWorld.Batch.new()
	for i in 3:
		wood.box(TowWorld.w(p + Vector2(0, -0.85 + i * 0.16), 0.46), Vector3(3.6, 0.04, 0.12), WOOD)
	wood.box(TowWorld.w(p + Vector2(0, -1.15), 0.85), Vector3(3.6, 0.3, 0.04), WOOD)
	# two benches beside the building as well
	var bb := bpos + Vector2(-9.5, 5.6)
	for k in 2:
		var q := bb + Vector2(k * 2.6, 0)
		for i in 3:
			wood.box(TowWorld.w(q + Vector2(0, -0.2 + i * 0.16), 0.46), Vector3(1.8, 0.04, 0.12), WOOD)
	_emit(wood, world.vmat(0.7))
	var legs := TowWorld.Batch.new()
	for k in 2:
		var q := bb + Vector2(k * 2.6, 0)
		for sx: int in [-1, 1]:
			legs.box(TowWorld.w(q + Vector2(sx * 0.75, 0), 0.22), Vector3(0.06, 0.44, 0.4), Color(0.2, 0.2, 0.22))
	_emit(legs, world.vmat(0.6, 0.3))


func _flags() -> void:
	var base := bpos + Vector2(-11.5, 5.0)
	var b := TowWorld.Batch.new()
	var f := TowWorld.Batch.new()
	for i in 3:
		var q := base + Vector2(i * 1.6, 0)
		b.add(TowWorld._cyl(0.035, 0.06, 9.0, 10), Transform3D(Basis.IDENTITY, TowWorld.w(q, 4.5)), Color(0.85, 0.86, 0.88))
		b.add(TowWorld._cyl(0.08, 0.08, 0.1, 10), Transform3D(Basis.IDENTITY, TowWorld.w(q, 9.03)), Color(0.95, 0.8, 0.3))
		b.add(TowWorld._cyl(0.3, 0.35, 0.3, 12), Transform3D(Basis.IDENTITY, TowWorld.w(q, 0.15)), Color(0.6, 0.6, 0.6))
		var col: Color = [Color(0.97, 0.97, 0.96), BLUE, Color(0.97, 0.97, 0.96)][i]
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.5, 1.0)
		pm.subdivide_width = 6
		pm.orientation = PlaneMesh.FACE_Z
		f.add(pm, TowWorld.xf(TowWorld.w(q + Vector2(0.85, 0), 8.3), Vector3.ONE, 0.35 + i * 0.1), col)
		if i == 1:
			# white emblem disc on the blue flag
			f.add(TowWorld._cyl(0.22, 0.22, 0.02, 16), TowWorld.xf(TowWorld.w(q + Vector2(0.85, 0.03), 8.3), Vector3.ONE, 0.35 + i * 0.1, PI / 2), Color(0.97, 0.97, 0.96))
	_emit(b, world.vmat(0.4, 0.5))
	var fm := world.vmat(0.8, 0.0, "flag")
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_emit(f, fm)


# ---------------------------------------------------------------- parking

func _parking() -> void:
	var x0 := gate.y + 3.0
	var x1 := fore.end.x - 3.0
	var depth := 5.0
	var bw := 2.5
	var n := int(floor((x1 - x0) / bw))
	if n < 2:
		return
	n = mini(n, 18)
	var y0 := fore.position.y + 0.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n + 1:
		var x := x0 + i * bw
		world._polyline_into(st, PackedVector2Array([Vector2(x, y0), Vector2(x, y0 + depth)]), 0.12, TowWorld.Y_LINE, false)
	world._polyline_into(st, PackedVector2Array([Vector2(x0, y0 + depth), Vector2(x0 + n * bw, y0 + depth)]), 0.12, TowWorld.Y_LINE, false)
	_emit_lines(st, TowWorld.WHITE)
	# wheel stops
	var ws := TowWorld.Batch.new()
	for i in n:
		ws.box(TowWorld.w(Vector2(x0 + (i + 0.5) * bw, y0 + 0.9), 0.07), Vector3(1.6, 0.14, 0.25), Color(0.85, 0.82, 0.3))
	_emit(ws, world.vmat(0.7))
	# cars
	var palette := [Color(0.93, 0.93, 0.92), Color(0.72, 0.74, 0.77), Color(0.1, 0.1, 0.12), Color(0.93, 0.93, 0.92),
		Color(0.14, 0.26, 0.5), Color(0.6, 0.12, 0.12), Color(0.4, 0.42, 0.45), Color(0.93, 0.93, 0.92), Color(0.2, 0.2, 0.2)]
	var body := TowWorld.Batch.new()
	var glass := TowWorld.Batch.new()
	var wheels := TowWorld.Batch.new()
	var ci := 0
	for i in n:
		if rng.randf() > 0.6:
			continue
		var cx := x0 + (i + 0.5) * bw
		var cy := y0 + depth * 0.5 + 0.1
		var yaw := rng.randf_range(-0.03, 0.03)
		_car(body, glass, wheels, TowWorld.w(Vector2(cx, cy)), yaw, palette[ci % palette.size()])
		ci += 1
	_emit(body, world.vmat(0.35, 0.3, "car"))
	_emit(glass, world.vmat(0.1, 0.8, "glass"))
	_emit(wheels, world.vmat(0.85))


## A rounded sedan: capsule body, ellipsoid glasshouse, painted roof cap.
func _car(body: TowWorld.Batch, glass: TowWorld.Batch, wheels: TowWorld.Batch, at: Vector3, yaw: float, col: Color) -> void:
	var cap := CapsuleMesh.new()
	cap.radius = 0.86
	cap.height = 4.4
	cap.radial_segments = 14
	cap.rings = 4
	body.add(cap, TowWorld.xf(at + Vector3(0, 0.8, 0), Vector3(1.0, 0.6, 1.0), yaw, PI / 2), col)
	var cab := _sphere(1.0)
	cab.radial_segments = 16
	cab.rings = 8
	glass.add(cab, TowWorld.xf(at + Vector3(0, 1.08, 0.15).rotated(Vector3.UP, yaw), Vector3(0.78, 0.56, 1.2), yaw), GLASS)
	body.add(cab, TowWorld.xf(at + Vector3(0, 1.2, 0.15).rotated(Vector3.UP, yaw), Vector3(0.68, 0.5, 1.0), yaw), col)
	# dark sills / underbody shadow line
	var bm := BoxMesh.new()
	bm.size = Vector3(1.75, 0.22, 3.6)
	body.add(bm, TowWorld.xf(at + Vector3(0, 0.38, 0), Vector3.ONE, yaw), Color(0.08, 0.08, 0.09))
	var wm := TowWorld._cyl(0.33, 0.33, 0.24, 14)
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			var off := Vector3(sx * 0.8, 0.33, sz * 1.35).rotated(Vector3.UP, yaw)
			wheels.add(wm, TowWorld.xf(at + off, Vector3.ONE, yaw + PI / 2, PI / 2), Color(0.06, 0.06, 0.06))
	var hub := TowWorld._cyl(0.18, 0.18, 0.26, 10)
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			var off := Vector3(sx * 0.8, 0.33, sz * 1.35).rotated(Vector3.UP, yaw)
			wheels.add(hub, TowWorld.xf(at + off, Vector3.ONE, yaw + PI / 2, PI / 2), Color(0.7, 0.7, 0.72))


# ---------------------------------------------------------------- site furniture

func _light_poles() -> void:
	var b := TowWorld.Batch.new()
	var lamps := TowWorld.Batch.new()
	var pts := []
	var yn := all.end.y + 7.5
	var ys := all.position.y - 7.5
	var x := all.position.x - 2.0
	while x < all.end.x + 2.0:
		pts.append([Vector2(x, yn), -PI / 2])
		pts.append([Vector2(x, ys), PI / 2])
		x += 28.0
	var yv := all.position.y + 10.0
	while yv < all.end.y - 4.0:
		pts.append([Vector2(all.position.x - 7.5, yv), 0.0])
		pts.append([Vector2(all.end.x + 7.5, yv), PI])
		yv += 28.0
	# road lamps on the far footpath
	var rx := fence.position.x - 40.0
	while rx < fence.end.x + 40.0:
		pts.append([Vector2(rx, road_y - ROAD_W * 0.5 - 1.6), -PI / 2])
		rx += 32.0
	for e in pts:
		var p: Vector2 = e[0]
		var yaw: float = e[1]   # arm points along +x rotated by yaw (toward the yard)
		b.add(TowWorld._cyl(0.07, 0.11, 8.0, 10), Transform3D(Basis.IDENTITY, TowWorld.w(p, 4.0)), STEEL)
		b.add(TowWorld._cyl(0.2, 0.24, 0.5, 10), Transform3D(Basis.IDENTITY, TowWorld.w(p, 0.25)), Color(0.5, 0.5, 0.5))
		var arm := BoxMesh.new()
		arm.size = Vector3(1.8, 0.09, 0.09)
		b.add(arm, TowWorld.xf(TowWorld.w(p, 7.95) + Vector3(0.9, 0, 0).rotated(Vector3.UP, yaw), Vector3.ONE, yaw), STEEL)
		var head := BoxMesh.new()
		head.size = Vector3(0.9, 0.18, 0.36)
		b.add(head, TowWorld.xf(TowWorld.w(p, 7.9) + Vector3(1.75, 0, 0).rotated(Vector3.UP, yaw), Vector3.ONE, yaw), Color(0.72, 0.74, 0.76))
		var lens := BoxMesh.new()
		lens.size = Vector3(0.8, 0.04, 0.28)
		lamps.add(lens, TowWorld.xf(TowWorld.w(p, 7.79) + Vector3(1.75, 0, 0).rotated(Vector3.UP, yaw), Vector3.ONE, yaw), Color(0.95, 0.96, 0.9))
	_emit(b, world.vmat(0.55, 0.4))
	var lm := world.vmat(0.3, 0.0, "lamp")
	lm.emission_enabled = true
	lm.emission = Color(0.9, 0.92, 0.85)
	lm.emission_energy_multiplier = 0.5
	_emit(lamps, lm, false)


func _fence() -> void:
	var posts := TowWorld.Batch.new()
	var rails := TowWorld.Batch.new()
	var panels := SurfaceTool.new()
	panels.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 1.8
	var corners := [fence.position, Vector2(fence.end.x, fence.position.y), fence.end, Vector2(fence.position.x, fence.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var d := (b - a).normalized()
		var len := a.distance_to(b)
		var n := int(ceil(len / 3.0))
		var step := len / n
		for k in n + 1:
			var p := a + d * step * k
			posts.add(TowWorld._cyl(0.045, 0.045, h, 8), Transform3D(Basis.IDENTITY, TowWorld.w(p, h * 0.5)), FENCE_GREEN)
		for k in n:
			var p0 := a + d * step * k
			var p1 := a + d * step * (k + 1)
			if i == 0 and p0.x >= gate.x - 0.1 and p1.x <= gate.y + 0.1:
				continue
			var mid := (p0 + p1) * 0.5
			var yaw := -atan2(d.y, d.x)
			rails.box(TowWorld.w(mid, h - 0.03), Vector3(step, 0.06, 0.06), FENCE_GREEN, yaw)
			rails.box(TowWorld.w(mid, 0.06), Vector3(step, 0.06, 0.06), FENCE_GREEN, yaw)
			_panel(panels, p0, p1, 0.1, h - 0.06)
	# gate pillars with caps
	for gx in [gate.x, gate.y]:
		rails.box(TowWorld.w(Vector2(gx, fence.position.y), 1.1), Vector3(0.5, 2.2, 0.5), Color(0.6, 0.6, 0.58))
		rails.box(TowWorld.w(Vector2(gx, fence.position.y), 2.28), Vector3(0.62, 0.16, 0.62), BLUE)
	# open sliding gate parked along the fence east of the opening
	var gl := gate.y - gate.x
	rails.box(TowWorld.w(Vector2(gate.y + gl * 0.5 + 0.5, fence.position.y + 0.35), 1.0), Vector3(gl, 0.06, 0.06), STEEL)
	rails.box(TowWorld.w(Vector2(gate.y + gl * 0.5 + 0.5, fence.position.y + 0.35), 1.9), Vector3(gl, 0.06, 0.06), STEEL)
	_panel(panels, Vector2(gate.y + 0.5, fence.position.y + 0.35), Vector2(gate.y + gl + 0.5, fence.position.y + 0.35), 0.15, 1.85)
	_emit(posts, world.vmat(0.5, 0.3))
	_emit(rails, world.vmat(0.5, 0.3))
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = _fence_texture()
	pm.albedo_color = Color(0.3, 0.52, 0.36)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.roughness = 0.6
	pm.metallic = 0.3
	pm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mesh := panels.commit()
	world.add_mesh(mesh, Vector3.ZERO, pm, 0.0, Vector3.ONE, false)
	out.append({"mesh": mesh, "mat": pm, "shadow": false})
	# hedge outside the south fence, with a break at the gate
	var hedge := TowWorld.Batch.new()
	var hy := fence.position.y - 1.1
	var hx := fence.position.x + 1.0
	while hx < fence.end.x - 1.0:
		var seg_end := minf(hx + 11.0, fence.end.x - 1.0)
		if not (seg_end < gate.x - 2.0 or hx > gate.y + 2.0):
			# split around the gate
			if hx < gate.x - 2.0:
				hedge.box(TowWorld.w(Vector2((hx + gate.x - 2.0) * 0.5, hy), 0.5), Vector3(gate.x - 2.0 - hx, 1.0, 0.9), Color(0.26, 0.46, 0.2))
			if seg_end > gate.y + 2.0:
				hedge.box(TowWorld.w(Vector2((gate.y + 2.0 + seg_end) * 0.5, hy), 0.5), Vector3(seg_end - gate.y - 2.0, 1.0, 0.9), Color(0.26, 0.46, 0.2))
		else:
			hedge.box(TowWorld.w(Vector2((hx + seg_end) * 0.5, hy), 0.5), Vector3(seg_end - hx, 1.0, 0.9), Color(0.26, 0.46, 0.2))
		hx = seg_end + 1.2
	_emit(hedge, _hedge_mat())


func _panel(st: SurfaceTool, a: Vector2, b: Vector2, y0: float, y1: float) -> void:
	var len := a.distance_to(b)
	var pa := TowWorld.w(a, y0)
	var pb := TowWorld.w(b, y0)
	var pc := TowWorld.w(b, y1)
	var pd := TowWorld.w(a, y1)
	var d := (b - a).normalized()
	var nrm := Vector3(-d.y, 0, -d.x)
	var uv_scale := 1.0 / 0.4   # tiles every 40 cm
	for v in [[pa, Vector2(0, y1 * uv_scale)], [pb, Vector2(len * uv_scale, y1 * uv_scale)], [pc, Vector2(len * uv_scale, y0 * uv_scale)],
		[pa, Vector2(0, y1 * uv_scale)], [pc, Vector2(len * uv_scale, y0 * uv_scale)], [pd, Vector2(0, y0 * uv_scale)]]:
		st.set_normal(nrm)
		st.set_uv(v[1])
		st.add_vertex(v[0])


## Chain-link style grid, alpha outside the wires, with mipmaps so distant
## fence fades to a soft tint instead of shimmering.
static func _fence_texture() -> Texture2D:
	if _fence_tex:
		return _fence_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			# diamond mesh: two diagonal wire families
			var u := float(x) / size
			var v := float(y) / size
			var d1 := absf(fposmod(u + v, 1.0) - 0.5)
			var d2 := absf(fposmod(u - v, 1.0) - 0.5)
			var wire := d1 > 0.47 or d2 > 0.47
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if wire else 0.0))
	img.generate_mipmaps()
	_fence_tex = ImageTexture.create_from_image(img)
	return _fence_tex


## Cone row along the south dirt strip and tyre stacks along the north one.
func _barriers() -> void:
	var cones := TowWorld.Batch.new()
	var y := all.position.y - 5.1
	var x := fore.position.x + 4.0
	while x < fore.end.x - 4.0:
		var p := Vector2(x + rng.randf_range(-0.2, 0.2), y + rng.randf_range(-0.15, 0.15))
		cones.add(TowWorld._cyl(0.03, 0.16, 0.62, 12), Transform3D(Basis.IDENTITY, TowWorld.w(p, 0.33)), Color(1.0, 0.4, 0.05))
		cones.add(TowWorld._cyl(0.085, 0.11, 0.1, 12), Transform3D(Basis.IDENTITY, TowWorld.w(p, 0.42)), Color(0.97, 0.97, 0.96))
		var base := BoxMesh.new()
		base.size = Vector3(0.38, 0.04, 0.38)
		cones.add(base, Transform3D(Basis.IDENTITY, TowWorld.w(p, 0.02)), Color(0.1, 0.1, 0.1))
		x += 4.0
	_emit(cones, world.vmat(0.6))
	var tyres := TowWorld.Batch.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.38
	tm.rings = 14
	tm.ring_segments = 8
	var ty := all.end.y + 5.0
	var tx := all.position.x + 6.0
	while tx < all.end.x - 6.0:
		var p := Vector2(tx + rng.randf_range(-0.3, 0.3), ty)
		var stack := 2 + (1 if rng.randf() < 0.4 else 0)
		for k in stack:
			tyres.add(tm, TowWorld.xf(TowWorld.w(p, 0.1 + k * 0.2), Vector3.ONE, rng.randf() * PI, PI / 2), Color(0.08, 0.08, 0.085))
		tx += 7.0
	_emit(tyres, world.vmat(0.9))


# ---------------------------------------------------------------- vegetation

## Tree templates: parts of [kind, offset, scale, shade]; kind 0 = ellipsoid, 1 = cone.
func _template(i: int) -> Array:
	match i % 4:
		0:   # round zelkova-like
			return [[0, Vector3(0, 3.4, 0), Vector3(1.9, 1.7, 1.9), 0.0], [0, Vector3(0.8, 4.2, 0.4), Vector3(1.3, 1.2, 1.3), 0.2],
				[0, Vector3(-0.7, 4.3, -0.5), Vector3(1.2, 1.1, 1.2), -0.15], [2, Vector3(0, 1.3, 0), Vector3(0.22, 2.6, 0.22), 0.0]]
		1:   # tall and narrow (poplar / ginkgo)
			return [[0, Vector3(0, 4.2, 0), Vector3(1.2, 2.6, 1.2), 0.1], [0, Vector3(0, 6.3, 0), Vector3(0.8, 1.5, 0.8), 0.3],
				[2, Vector3(0, 1.5, 0), Vector3(0.18, 3.0, 0.18), 0.0]]
		2:   # wide spreading
			return [[0, Vector3(0, 3.0, 0), Vector3(2.4, 1.4, 2.4), -0.1], [0, Vector3(1.3, 3.6, 0.7), Vector3(1.5, 1.1, 1.5), 0.15],
				[0, Vector3(-1.3, 3.5, -0.6), Vector3(1.4, 1.0, 1.4), 0.05], [2, Vector3(0, 1.2, 0), Vector3(0.28, 2.4, 0.28), 0.0]]
		_:   # pine
			return [[1, Vector3(0, 3.6, 0), Vector3(1.5, 3.0, 1.5), -0.3], [1, Vector3(0, 5.6, 0), Vector3(1.0, 2.2, 1.0), -0.2],
				[2, Vector3(0, 1.3, 0), Vector3(0.2, 2.6, 0.2), 0.0]]


func _tree(b: TowWorld.Batch, p: Vector2, s: float, tpl: int, hue: float) -> void:
	var yaw := rng.randf() * TAU
	var base := Color(0.2, 0.42, 0.17).lerp(Color(0.44, 0.6, 0.22), hue)
	for part in _template(tpl):
		var kind: int = part[0]
		var off: Vector3 = part[1] * s
		var sc: Vector3 = part[2] * s
		var pos := TowWorld.w(p) + off.rotated(Vector3.UP, yaw)
		match kind:
			0:
				b.add(_sphere(1.0), TowWorld.xf(pos, sc, yaw), base.lightened(part[3] * 0.5) if part[3] > 0 else base.darkened(-part[3] * 0.5))
			1:
				var cone := TowWorld._cyl(0.02, 1.0, 1.0, 10)
				b.add(cone, TowWorld.xf(pos, sc, yaw), Color(0.14, 0.33, 0.17).lightened(0.1 + part[3]))
			_:
				b.add(TowWorld._cyl(0.8, 1.0, 1.0, 8), TowWorld.xf(pos, sc, yaw), Color(0.36, 0.27, 0.19))


func _trees() -> void:
	var b := TowWorld.Batch.new()
	var i := 0
	# inside the compound: along the north, west and east fence lines
	var x := all.position.x - 4.0
	while x < all.end.x + 4.0:
		_tree(b, Vector2(x + rng.randf_range(-0.6, 0.6), all.end.y + 7.6), rng.randf_range(0.85, 1.2), i, rng.randf())
		i += 1
		x += 9.0
	var y := all.position.y + 6.0
	while y < all.end.y + 2.0:
		_tree(b, Vector2(all.position.x - 7.6, y), rng.randf_range(0.85, 1.15), i, rng.randf())
		if absf(y - all.get_center().y) > 7.0:
			_tree(b, Vector2(all.end.x + 7.6, y), rng.randf_range(0.85, 1.15), i + 1, rng.randf())
		i += 2
		y += 10.0
	# behind the building and near the parking lot
	for k in 4:
		_tree(b, bpos + Vector2(-10.0 + k * 1.5, -6.5 + (k % 2) * 2.0), rng.randf_range(0.9, 1.2), k, rng.randf())
	_tree(b, Vector2(fore.end.x - 2.0, fore.position.y + 10.0), 1.1, 2, 0.6)
	_tree(b, Vector2(fore.end.x - 2.0, fore.position.y + 19.0), 1.0, 0, 0.3)
	# street trees on both footpaths of the road
	var rx := fence.position.x - 60.0
	while rx < fence.end.x + 60.0:
		if rx < gate.x - 4.0 or rx > gate.y + 4.0:
			_tree(b, Vector2(rx, road_y + ROAD_W * 0.5 + WALK_W + 0.9), rng.randf_range(0.9, 1.25), 1 if (int(rx / 10) % 3 == 0) else 0, rng.randf())
		_tree(b, Vector2(rx + 5.0, road_y - ROAD_W * 0.5 - WALK_W - 0.9), rng.randf_range(0.9, 1.25), 2 if (int(rx / 10) % 2 == 0) else 1, rng.randf())
		rx += 10.0
	# loose groves beyond the fence
	for k in 30:
		var px := rng.randf_range(fence.position.x - 30.0, fence.end.x + 30.0)
		var py := fence.end.y + rng.randf_range(6.0, 30.0)
		_tree(b, Vector2(px, py), rng.randf_range(0.9, 1.5), k, rng.randf())
	for k in 10:
		var side := -1.0 if k % 2 == 0 else 1.0
		var px := (fence.position.x - rng.randf_range(10.0, 30.0)) if side < 0 else (fence.end.x + rng.randf_range(10.0, 30.0))
		var py := rng.randf_range(fence.position.y, fence.end.y)
		_tree(b, Vector2(px, py), rng.randf_range(1.0, 1.5), k, rng.randf())
	_emit(b, world.vmat(0.9))
	# distant treeline ring: big soft canopies
	var tl := TowWorld.Batch.new()
	var ring := fence.grow(70.0)
	var corners := [ring.position, Vector2(ring.end.x, ring.position.y), ring.end, Vector2(ring.position.x, ring.end.y)]
	for s in 4:
		var a: Vector2 = corners[s]
		var c: Vector2 = corners[(s + 1) % 4]
		var d := (c - a).normalized()
		var len := a.distance_to(c)
		var t := 0.0
		while t < len:
			var p := a + d * t + Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0))
			var sc := Vector3(rng.randf_range(5.0, 8.0), rng.randf_range(5.0, 9.0), rng.randf_range(5.0, 8.0))
			var col := Color(0.2, 0.36, 0.22).lerp(Color(0.34, 0.48, 0.26), rng.randf())
			tl.add(_sphere(1.0), TowWorld.xf(TowWorld.w(p, sc.y * 0.55), sc, rng.randf() * TAU), col)
			t += 7.5
	_emit(tl, world.vmat(0.95))


func _hills() -> void:
	var b := TowWorld.Batch.new()
	var c := fence.get_center()
	for k in 9:
		var ang := k * TAU / 9.0 + rng.randf_range(-0.15, 0.15)
		var dist := rng.randf_range(330.0, 470.0)
		var p := c + Vector2(cos(ang), sin(ang)) * dist
		var r := rng.randf_range(140.0, 260.0)
		var hgt := rng.randf_range(0.11, 0.19)
		var col := Color(0.4, 0.52, 0.44).lerp(Color(0.5, 0.6, 0.62), rng.randf() * 0.6)
		b.add(_sphere(1.0), TowWorld.xf(TowWorld.w(p, -r * hgt * 0.15), Vector3(r, r * hgt, r * rng.randf_range(0.7, 1.0)), rng.randf() * TAU), col)
	_emit(b, world.vmat(1.0), false)
