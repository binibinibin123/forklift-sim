class_name TowWorld
extends Node3D
## The exam yard: sky, light, ground and painted lines for one licence's steps,
## plus the props that make it read as a suburban Korean 운전면허시험장
## (see world_props.gd). Ground (x, y) is world (x, 0, -y), so the yard is
## not mirrored: +y on the ground is "north" (-Z) in 3D.
##
## Mobile renderer: no SSAO/SDFGI; we rely on a physical sky for ambient and
## reflections, soft directional shadows, procedural noise textures and a
## small number of batched meshes (one MeshInstance3D per material group).

const LINE_W := 0.15
const WHITE := Color(0.96, 0.96, 0.94)
const YELLOW := Color(1.0, 0.8, 0.1)
const CONFIRM := Color(0.15, 0.55, 1.0)

## Ground layer heights (metres). Lines sit a few mm above the asphalt.
const Y_GRASS := -0.03
const Y_DIRT := -0.02
const Y_APRON := -0.01
const Y_PAD := 0.0
const Y_LINE := 0.012
const Y_FINISH := 0.013
const Y_CONFIRM := 0.014

static var _tex := {}        # procedural textures, generated once per process
static var _paint_shader: Shader

var _mats := {}
var guide: MeshInstance3D
var guide_mesh := ImmediateMesh.new()
var mesh_count := 0          # MeshInstance3D nodes created by the last build()


func build(steps: Array) -> void:
	for c in get_children():
		c.queue_free()
	mesh_count = 0
	_env()
	# A practice run passes a single step; the yard is still the licence's
	# whole test centre, so lay out and paint every course of that kind.
	var layout := steps
	if not steps.is_empty() and steps[0].has("kind"):
		var full := Courses.exam_steps(steps[0].kind)
		if not full.is_empty():
			layout = full
	var all := Rect2()
	var first := true
	for s in layout:
		for r in s.get("asphalt", []):
			all = r if first else all.merge(r)
			first = false
	_ground(all, layout)
	for s in layout:
		_markings(s)
		_sign(s)
	WorldProps.build(self, all)
	guide = MeshInstance3D.new()
	guide.mesh = guide_mesh
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.vertex_color_use_as_albedo = true
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	guide.material_override = gm
	add_child(guide)


## Predicted wheel tracks for the current steering (learning aid).
func draw_guide(tracks: Array) -> void:
	guide_mesh.clear_surfaces()
	for t in tracks:
		var pts: PackedVector2Array = t.pts
		if pts.size() < 2:
			continue
		guide_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var col: Color = t.color
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x) * 0.11
			var ca := Color(col, col.a * (1.0 - 0.7 * float(i) / pts.size()))
			var cb := Color(col, col.a * (1.0 - 0.7 * float(i + 1) / pts.size()))
			_tri_q(a + n, a - n, b - n, b + n, ca, cb, 0.03)
		guide_mesh.surface_end()


func _tri_q(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, y: float) -> void:
	for v in [[a, ca], [b, ca], [c, cb], [a, ca], [c, cb], [d, cb]]:
		guide_mesh.surface_set_color(v[1])
		guide_mesh.surface_add_vertex(Vector3(v[0].x, y, -v[0].y))


# ---------------------------------------------------------------- helpers
# (also used by WorldProps)

## Ground point to world.
static func w(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, -p.y)


func mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var key := c.to_html() + str(rough) + str(metal)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


## White material that takes its colour from vertex colours (for batches).
func vmat(rough := 0.85, metal := 0.0, key := "") -> StandardMaterial3D:
	var k := "vc" + str(rough) + str(metal) + key
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = rough
		m.metallic = metal
		_mats[k] = m
	return _mats[k]


## Seamless FastNoiseLite texture through a colour ramp (cached per process).
static func noise_tex(key: String, freq: float, seed_: int, ramp: Gradient, normal_map := false, size := 512, octaves := 4, kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.noise_type = kind
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.1
	n.fractal_gain = 0.5
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.seamless_blend_skirt = 0.2
	t.noise = n
	t.generate_mipmaps = true
	if normal_map:
		t.as_normal_map = true
		t.bump_strength = 6.0
	elif ramp:
		t.color_ramp = ramp
	_tex[key] = t
	return t


static func ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	return g


## Textured ground material; UVs are in metres (see quad()), so uv_scale
## is tiles per metre.
func tex_mat(key: String, albedo: Texture2D, normal: Texture2D, rough: float, uv_scale: float, tint := Color.WHITE) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	if normal:
		m.normal_enabled = true
		m.normal_texture = normal
		m.normal_scale = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


func add_mesh(mesh: Mesh, pos: Vector3, m: Material, rot_y := 0.0, scale := Vector3.ONE, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = rot_y
	mi.scale = scale
	mi.material_override = m
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mesh_count += 1
	return mi


## Flat ground quad over a ground rect with metric UVs and tangents.
## Ground y maps to -z, which flips handedness, so the triangles are wound
## clockwise in ground coordinates to come out counter-clockwise (front
## facing) in world space.
func quad(r: Rect2, y: float, m: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := r.position
	var b := r.end
	var pts := [Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(b.x, a.y), Vector2(a.x, a.y), Vector2(a.x, b.y), Vector2(b.x, b.y)]
	for p in pts:
		st.set_normal(Vector3.UP)
		st.set_tangent(Plane(1, 0, 0, 1))
		st.set_uv(Vector2(p.x, -p.y))
		st.add_vertex(w(p, y))
	return add_mesh(st.commit(), Vector3.ZERO, m, 0.0, Vector3.ONE, false)


## Collects many primitive meshes with per-piece colours into one mesh.
class Batch:
	var st := SurfaceTool.new()
	var empty := true

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func add(mesh: Mesh, xf: Transform3D, col := Color.WHITE) -> void:
		var nb := xf.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns = arr[Mesh.ARRAY_NORMAL]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			var count: int = vs.size() if idx == null else idx.size()
			for k in count:
				var i: int = k if idx == null else idx[k]
				st.set_color(col)
				if ns != null:
					st.set_normal((nb * ns[i]).normalized())
				if uvs != null:
					st.set_uv(uvs[i])
				st.add_vertex(xf * vs[i])
				empty = false

	## Axis-aligned box helper (centre, size).
	func box(c: Vector3, size: Vector3, col := Color.WHITE, rot_y := 0.0) -> void:
		var bm := BoxMesh.new()
		bm.size = size
		add(bm, Transform3D(Basis(Vector3.UP, rot_y), c), col)

	func commit(world: TowWorld, m: Material, shadow := true) -> MeshInstance3D:
		if empty:
			return null
		st.generate_tangents()
		return world.add_mesh(st.commit(), Vector3.ZERO, m, 0.0, Vector3.ONE, shadow)


static func xf(pos: Vector3, scale := Vector3.ONE, rot_y := 0.0, rot_x := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, rot_y) * Basis(Vector3.RIGHT, rot_x)
	b = b.scaled(scale)
	return Transform3D(b, pos)


# ---------------------------------------------------------------- sky & light

func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	# A clear early-afternoon sky with a visible sun disc. ProceduralSky is
	# used rather than PhysicalSky because it renders identically on every
	# driver (Mobile, Compatibility) and is cheaper on phones.
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.2, 0.44, 0.84)
	sm.sky_horizon_color = Color(0.72, 0.83, 0.94)
	sm.sky_curve = 0.12
	sm.sky_energy_multiplier = 0.95
	sm.ground_bottom_color = Color(0.33, 0.4, 0.3)
	sm.ground_horizon_color = Color(0.7, 0.78, 0.82)
	sm.ground_curve = 0.03
	sm.ground_energy_multiplier = 0.9
	sm.sun_angle_max = 18.0
	sm.sun_curve = 0.14
	sm.use_debanding = true
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55     # blend the blue sky with warm bounce
	env.ambient_light_color = Color(0.78, 0.74, 0.68)
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.3
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# A whisper of distance haze for depth; keep the yard itself clean.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.1
	env.fog_density = 0.0009
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	env.fog_height = -200.0
	env.fog_height_density = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.06
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -38, 0)
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 1.3
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)


# ---------------------------------------------------------------- ground

func asphalt_mat() -> StandardMaterial3D:
	# tile 7 m: broad tonal patches with finer grain from the octaves
	var alb := noise_tex("asphalt_a", 0.006, 11, ramp([
		[0.0, Color(0.185, 0.185, 0.185)], [0.5, Color(0.215, 0.215, 0.215)],
		[0.8, Color(0.24, 0.24, 0.24)], [1.0, Color(0.265, 0.265, 0.265)]]), false, 512, 6)
	var nrm := noise_tex("asphalt_n", 0.03, 12, null, true, 512, 4, FastNoiseLite.TYPE_CELLULAR)
	var m := tex_mat("asphalt", alb, nrm, 0.96, 0.1)
	m.normal_scale = 0.35
	m.metallic_specular = 0.15
	return m


func concrete_mat() -> StandardMaterial3D:
	var alb := noise_tex("concrete_a", 0.005, 21, ramp([
		[0.0, Color(0.4, 0.4, 0.385)], [0.5, Color(0.46, 0.46, 0.445)], [1.0, Color(0.53, 0.525, 0.505)]]), false, 512, 5)
	var nrm := noise_tex("concrete_n", 0.02, 22, null, true, 512, 4)
	var m := tex_mat("concrete", alb, nrm, 0.9, 0.125)
	m.normal_scale = 0.25
	m.metallic_specular = 0.2
	return m


func grass_mat() -> StandardMaterial3D:
	# tile 18 m: metre-scale patches of darker and yellower grass
	var alb := noise_tex("grass_a", 0.004, 31, ramp([
		[0.0, Color(0.17, 0.3, 0.1)], [0.3, Color(0.24, 0.4, 0.14)],
		[0.6, Color(0.31, 0.47, 0.17)], [0.85, Color(0.38, 0.52, 0.2)], [1.0, Color(0.46, 0.55, 0.24)]]), false, 1024, 5)
	var nrm := noise_tex("grass_n", 0.03, 32, null, true, 512, 4, FastNoiseLite.TYPE_CELLULAR)
	var m := tex_mat("grass", alb, nrm, 0.97, 0.055)
	m.normal_scale = 0.45
	return m


func dirt_mat() -> StandardMaterial3D:
	var alb := noise_tex("dirt_a", 0.008, 41, ramp([
		[0.0, Color(0.36, 0.3, 0.22)], [0.5, Color(0.48, 0.41, 0.31)], [1.0, Color(0.58, 0.52, 0.41)]]), false, 512, 5)
	var nrm := noise_tex("dirt_n", 0.03, 42, null, true, 512, 4, FastNoiseLite.TYPE_CELLULAR)
	var m := tex_mat("dirt", alb, nrm, 0.95, 0.2)
	m.normal_scale = 0.4
	return m


func _ground(all: Rect2, steps: Array) -> void:
	# grass to the horizon, then dirt strip, concrete apron, asphalt pads
	quad(all.grow(700.0), Y_GRASS, grass_mat())
	quad(all.grow(6.0), Y_DIRT, dirt_mat())
	var apron := all.grow(4.0)
	quad(apron, Y_APRON, concrete_mat())
	var asphalt := asphalt_mat()
	for s in steps:
		for r in s.get("asphalt", []):
			quad(r, Y_PAD, asphalt)
	_wear(steps)
	# kerbs along the apron edges
	var kb := Batch.new()
	var kc := Color(0.78, 0.78, 0.75)
	var h := 0.12
	kb.box(Vector3(apron.get_center().x, h * 0.5, -apron.position.y), Vector3(apron.size.x + 0.3, h, 0.3), kc)
	kb.box(Vector3(apron.get_center().x, h * 0.5, -apron.end.y), Vector3(apron.size.x + 0.3, h, 0.3), kc)
	kb.box(Vector3(apron.position.x, h * 0.5, -apron.get_center().y), Vector3(0.3, h, apron.size.y), kc)
	kb.box(Vector3(apron.end.x, h * 0.5, -apron.get_center().y), Vector3(0.3, h, apron.size.y), kc)
	kb.commit(self, vmat(0.8))


## Soft dark tyre-wear and lighter patch blotches on the asphalt, one mesh.
func _wear(steps: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for s in steps:
		for r in s.get("asphalt", []):
			var rr: Rect2 = r
			for i in 7:
				var c := Vector2(rng.randf_range(rr.position.x + 3, rr.end.x - 3), rng.randf_range(rr.position.y + 3, rr.end.y - 3))
				var sz := Vector2(rng.randf_range(3, 7), rng.randf_range(3, 9))
				var dark := rng.randf() < 0.65
				var col := Color(0, 0, 0, rng.randf_range(0.18, 0.35)) if dark else Color(0.55, 0.55, 0.52, rng.randf_range(0.12, 0.22))
				var a := c - sz * 0.5
				var b := c + sz * 0.5
				var pts := [[Vector2(a.x, a.y), Vector2(0, 0)], [Vector2(b.x, b.y), Vector2(1, 1)], [Vector2(b.x, a.y), Vector2(1, 0)],
					[Vector2(a.x, a.y), Vector2(0, 0)], [Vector2(a.x, b.y), Vector2(0, 1)], [Vector2(b.x, b.y), Vector2(1, 1)]]
				for p in pts:
					st.set_normal(Vector3.UP)
					st.set_color(col)
					st.set_uv(p[1])
					st.add_vertex(w(p[0], Y_PAD + 0.004))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _blob_tex()
	m.roughness = 0.9
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_mesh(st.commit(), Vector3.ZERO, m, 0.0, Vector3.ONE, false)


## Radial alpha blob with a noisy edge.
static func _blob_tex() -> Texture2D:
	if _tex.has("blob"):
		return _tex["blob"]
	var n := FastNoiseLite.new()
	n.seed = 3
	n.frequency = 0.03
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(size * 0.5, size * 0.5)) / (size * 0.5)
			var a := clampf(1.0 - d * 1.15 + n.get_noise_2d(x, y) * 0.35, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex["blob"] = t
	return t


# ---------------------------------------------------------------- markings

## Paint shader: tiled noise for brightness variation and chipped edges,
## soft falloff across the width (UV2.y) so edges are not razor crisp.
static func paint_shader() -> Shader:
	if _paint_shader:
		return _paint_shader
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec4 color : source_color = vec4(1.0);
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float chip = 0.22;
void fragment() {
	float n = texture(noise, UV * 0.4).r;
	float n2 = texture(noise, UV * 2.3 + vec2(0.37, 0.11)).r;
	float e = smoothstep(0.0, 0.18, UV2.y) * smoothstep(1.0, 0.82, UV2.y);
	float wear = smoothstep(chip - 0.06, chip + 0.06, n * 0.6 + n2 * 0.4);
	ALBEDO = color.rgb * (0.82 + 0.18 * n2);
	ALPHA = e * mix(0.55, 1.0, wear) * color.a;
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
}
"""
	_paint_shader = s
	return s


func paint_mat(c: Color) -> ShaderMaterial:
	var key := "paint" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = paint_shader()
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("noise", noise_tex("paint_n", 0.05, 51, ramp([[0.0, Color.BLACK], [1.0, Color.WHITE]]), false, 256, 3))
	_mats[key] = m
	return m


func _markings(s: Dictionary) -> void:
	var whites := SurfaceTool.new()
	whites.begin(Mesh.PRIMITIVE_TRIANGLES)
	var poles := Batch.new()
	for l in s.lines:
		_polyline_into(whites, l, LINE_W, Y_LINE, false)
		_poles(poles, l)
	for l in s.get("paint", []):
		_polyline_into(whites, l, 0.12, Y_LINE, true)
	_commit_lines(whites, WHITE)
	poles.commit(self, vmat(0.45))
	if not s.get("confirms", []).is_empty():
		var blues := SurfaceTool.new()
		blues.begin(Mesh.PRIMITIVE_TRIANGLES)
		for c in s.confirms:
			_polyline_into(blues, PackedVector2Array([c.a, c.b]), 0.35, Y_CONFIRM, false)
			_label3d(c.label, (c.a + c.b) * 0.5, 0.02, CONFIRM)
		_commit_lines(blues, CONFIRM)
	if s.has("finish"):
		var yel := SurfaceTool.new()
		yel.begin(Mesh.PRIMITIVE_TRIANGLES)
		_polyline_into(yel, PackedVector2Array([s.finish.a, s.finish.b]), 0.3, Y_FINISH, true)
		_commit_lines(yel, YELLOW)


func _commit_lines(st: SurfaceTool, c: Color) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	add_mesh(mesh, Vector3.ZERO, paint_mat(c), 0.0, Vector3.ONE, false)


func _polyline_into(st: SurfaceTool, l: PackedVector2Array, wd: float, y: float, dashed: bool, dash := 1.0, period := 2.0) -> void:
	for i in l.size() - 1:
		var a := l[i]
		var b := l[i + 1]
		var seg := b - a
		var n := seg.length()
		if n < 0.001:
			continue
		var d := seg / n
		var nrm := Vector2(-d.y, d.x) * wd * 0.5
		var pieces := [[0.0, n]]
		if dashed:
			pieces = []
			var t := 0.0
			while t < n:
				pieces.append([t, minf(t + dash, n)])
				t += period
		for pc in pieces:
			var p0: Vector2 = a + d * (pc[0] - (wd * 0.5 if not dashed else 0.0))
			var p1: Vector2 = a + d * (pc[1] + (wd * 0.5 if not dashed else 0.0))
			var quad_pts := [[p0 + nrm, 0.0], [p1 + nrm, 0.0], [p1 - nrm, 1.0], [p0 + nrm, 0.0], [p1 - nrm, 1.0], [p0 - nrm, 1.0]]
			for v in quad_pts:
				var p: Vector2 = v[0]
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(p.x, -p.y))
				st.set_uv2(Vector2((p - a).dot(d), v[1]))
				st.add_vertex(Vector3(p.x, y, -p.y))


## Orange rubber poles at the corners of the detection lines.
func _poles(b: Batch, l: PackedVector2Array) -> void:
	for i in range(1, l.size() - 1):
		var a := l[i - 1]
		var p := l[i]
		var c := l[i + 1]
		if absf((p - a).normalized().cross((c - p).normalized())) < 0.5:
			continue
		var out := ((p - a).normalized() - (c - p).normalized()).normalized() * 0.45
		_pole(b, p + out)


func _pole(b: Batch, p: Vector2) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.07
	cm.height = 1.1
	cm.radial_segments = 12
	cm.rings = 1
	b.add(cm, Transform3D(Basis.IDENTITY, w(p, 0.55)), Color(1.0, 0.42, 0.04))
	var bm := CylinderMesh.new()
	bm.top_radius = 0.062
	bm.bottom_radius = 0.066
	bm.height = 0.12
	bm.radial_segments = 12
	bm.rings = 1
	b.add(bm, Transform3D(Basis.IDENTITY, w(p, 0.85)), WHITE)
	b.add(bm, Transform3D(Basis.IDENTITY, w(p, 0.6)), WHITE)
	var base := CylinderMesh.new()
	base.top_radius = 0.16
	base.bottom_radius = 0.19
	base.height = 0.05
	base.radial_segments = 12
	base.rings = 1
	b.add(base, Transform3D(Basis.IDENTITY, w(p, 0.025)), Color(0.12, 0.12, 0.12))


func _label3d(text: String, p: Vector2, y: float, c: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://fonts/GowunDodum-Regular.ttf")
	l.font_size = 96
	l.pixel_size = 0.006
	l.modulate = c
	l.outline_size = 18
	l.outline_modulate = Color(0, 0, 0, 0.5)
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = Vector3(p.x, y + 0.01, -p.y + 0.8)
	add_child(l)


## Blue-and-white course sign at each step's start.
func _sign(s: Dictionary) -> void:
	var p: Vector2 = s.start.pos + Vector2(-4.5, 2.0)
	var b := Batch.new()
	var steel := Color(0.62, 0.64, 0.66)
	b.add(_cyl(0.05, 0.05, 2.4, 10), Transform3D(Basis.IDENTITY, w(p + Vector2(-1.0, 0), 1.2)), steel)
	b.add(_cyl(0.05, 0.05, 2.4, 10), Transform3D(Basis.IDENTITY, w(p + Vector2(1.0, 0), 1.2)), steel)
	b.add(_cyl(0.14, 0.16, 0.08, 10), Transform3D(Basis.IDENTITY, w(p + Vector2(-1.0, 0), 0.04)), Color(0.3, 0.3, 0.3))
	b.add(_cyl(0.14, 0.16, 0.08, 10), Transform3D(Basis.IDENTITY, w(p + Vector2(1.0, 0), 0.04)), Color(0.3, 0.3, 0.3))
	b.box(w(p, 2.6), Vector3(2.6, 0.9, 0.06), Color(0.97, 0.97, 0.96))
	b.box(w(p, 2.98), Vector3(2.6, 0.14, 0.07), Color(0.1, 0.36, 0.72))
	b.box(w(p, 2.6), Vector3(2.66, 0.96, 0.05), Color(0.1, 0.36, 0.72))
	b.commit(self, vmat(0.45, 0.2))
	for side in [-1, 1]:
		var l := Label3D.new()
		l.text = s.title
		l.font = load("res://fonts/GowunDodum-Regular.ttf")
		l.font_size = 64
		l.pixel_size = 0.0068
		l.modulate = Color(0.08, 0.3, 0.62)
		l.position = Vector3(p.x, 2.54, -p.y + side * 0.045)
		l.rotation_degrees = Vector3(0, 0 if side > 0 else 180, 0)
		add_child(l)


static func _cyl(top: float, bottom: float, h: float, segs := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c
