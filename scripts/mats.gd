class_name Mats
extends RefCounted
## 재질 모음. 텍스처는 textures/ 의 절차 생성 PNG(tools/make_textures.py).

static var _cache := {}
static var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"


static func plain(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func tex(name: String, scale := Vector3.ONE, rough := 0.85, metal := 0.0, tint := Color.WHITE, normal := "") -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s|%s" % [name, scale, rough, metal, tint, normal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://textures/%s.png" % name)
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.uv1_scale = scale
	if normal != "":
		m.normal_enabled = true
		m.normal_texture = load("res://textures/%s.png" % normal)
		m.normal_scale = 0.6
	_cache[key] = m
	return m


## 바닥처럼 넓은 면: 월드 좌표 기준 삼면 투영으로 어느 크기 상자에도 같은 밀도.
static func triplanar(name: String, meters_per_tile := 4.0, rough := 0.9, tint := Color.WHITE, normal := "") -> StandardMaterial3D:
	var m := tex(name, Vector3.ONE / meters_per_tile, rough, 0.0, tint, normal).duplicate() as StandardMaterial3D
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	return m


static func emissive(c: Color, strength := 1.5) -> StandardMaterial3D:
	var m := plain(c, 0.4)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = strength
	return m


static func glass(c := Color(0.6, 0.75, 0.85, 0.35)) -> StandardMaterial3D:
	var m := plain(c, 0.05, 0.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func cutout(name: String, scale := Vector3.ONE) -> StandardMaterial3D:
	var m := tex(name, scale, 0.6, 0.6).duplicate() as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
