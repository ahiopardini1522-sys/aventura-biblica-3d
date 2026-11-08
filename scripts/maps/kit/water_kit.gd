class_name WaterKit
extends RefCounted
## Agua del escenario: shaders sencillos (olas, cascadas, muros de agua) y las mallas que los
## llevan (cintas para los ríos, láminas verticales para las cascadas). Los shaders usan
## solo funciones básicas para funcionar bien en un móvil con el renderizador de compatibilidad.

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.10, 0.36, 0.55, 0.88);
uniform vec4 shallow_color : source_color = vec4(0.36, 0.72, 0.82, 0.78);
uniform float wave_scale = 0.6;
uniform float wave_speed = 0.7;
uniform float flow = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * wave_scale;
	float t = TIME * wave_speed;
	float a = p.x * 1.7 + t + flow * p.y;
	float b = p.y * 2.1 - t * 1.3 + p.x * 0.5;
	float c = (p.x + p.y) * 3.1 + t * 2.0;
	float h = (sin(a) + sin(b) + sin(c)) / 3.0;
	float dx = (cos(a) * 1.7 + cos(c) * 3.1) * 0.06;
	float dz = (cos(b) * 2.1 + cos(c) * 3.1) * 0.06;
	vec3 n = normalize(vec3(-dx, 1.0, -dz));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float k = clamp(0.5 + 0.5 * h, 0.0, 1.0);
	vec4 c4 = mix(deep_color, shallow_color, k);
	ALBEDO = c4.rgb;
	ALPHA = c4.a;
	ROUGHNESS = 0.2;
	SPECULAR = 0.6;
}
"""

const FALL_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 color_a : source_color = vec4(0.88, 0.96, 1.0, 0.88);
uniform vec4 color_b : source_color = vec4(0.45, 0.72, 0.90, 0.70);
uniform float speed = 1.6;
uniform float streaks = 5.0;

void fragment() {
	float streak = fract(UV.y * streaks - TIME * speed + sin(UV.x * 18.0) * 0.12);
	float foam = smoothstep(0.55, 1.0, streak);
	vec4 c4 = mix(color_b, color_a, foam);
	float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x);
	ALBEDO = c4.rgb;
	ALPHA = c4.a * edge;
}
"""

static var _shaders: Dictionary = {}
static var _materials: Dictionary = {}


## Agua de lago, río o mar con olas suaves. "flow" inclina las olas en la dirección de la corriente.
static func water_material(deep: Color, shallow: Color, wave_scale: float = 0.6,
		wave_speed: float = 0.7, flow: float = 0.0) -> ShaderMaterial:
	var key: String = "water_%s_%s_%.2f_%.2f_%.2f" % [deep.to_html(true), shallow.to_html(true),
			wave_scale, wave_speed, flow]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("water", WATER_SHADER)
		m.set_shader_parameter("deep_color", deep)
		m.set_shader_parameter("shallow_color", shallow)
		m.set_shader_parameter("wave_scale", wave_scale)
		m.set_shader_parameter("wave_speed", wave_speed)
		m.set_shader_parameter("flow", flow)
		_materials[key] = m
	return _materials[key]


## Agua que cae en franjas (cascadas y muros de agua del Mar Rojo).
static func fall_material(color_a: Color, color_b: Color, speed: float = 1.6, streaks: float = 5.0) -> ShaderMaterial:
	var key: String = "fall_%s_%s_%.2f_%.2f" % [color_a.to_html(true), color_b.to_html(true), speed, streaks]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("fall", FALL_SHADER)
		m.set_shader_parameter("color_a", color_a)
		m.set_shader_parameter("color_b", color_b)
		m.set_shader_parameter("speed", speed)
		m.set_shader_parameter("streaks", streaks)
		_materials[key] = m
	return _materials[key]


static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var shader := Shader.new()
		shader.code = code
		_shaders[key] = shader
	return _shaders[key]


## Cinta horizontal que sigue un camino (río o arroyo). Mira hacia arriba; U va de 0 a 1
## a lo ancho y V crece con la distancia recorrida.
static func ribbon(path: PackedVector3Array, half_width: float) -> ArrayMesh:
	var count: int = path.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	if count < 2:
		return ArrayMesh.new()
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	var along := PackedFloat32Array()
	var travelled: float = 0.0
	for i in count:
		var tangent: Vector3
		if i == 0:
			tangent = path[1] - path[0]
		elif i == count - 1:
			tangent = path[count - 1] - path[count - 2]
		else:
			tangent = path[i + 1] - path[i - 1]
		tangent.y = 0.0
		if tangent.length_squared() < 0.000001:
			tangent = Vector3(0.0, 0.0, 1.0)
		tangent = tangent.normalized()
		var side := Vector3(-tangent.z, 0.0, tangent.x)
		lefts.append(path[i] - side * half_width)
		rights.append(path[i] + side * half_width)
		if i > 0:
			travelled += path[i].distance_to(path[i - 1])
		along.append(travelled)
	for i in count - 1:
		var v0: float = along[i] / 6.0
		var v1: float = along[i + 1] / 6.0
		_flat_triangle(verts, norms, uvs, lefts[i], rights[i], lefts[i + 1],
				Vector2(0.0, v0), Vector2(1.0, v0), Vector2(0.0, v1))
		_flat_triangle(verts, norms, uvs, rights[i], rights[i + 1], lefts[i + 1],
				Vector2(1.0, v0), Vector2(1.0, v1), Vector2(0.0, v1))
	return _mesh(verts, norms, uvs)


## Lámina vertical o inclinada entre cuatro puntos (cascada o muro de agua). U va de
## izquierda a derecha y V de arriba hacia abajo.
static func sheet(top_left: Vector3, top_right: Vector3, bottom_left: Vector3,
		bottom_right: Vector3, columns: int = 1, rows: int = 1) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols: int = maxi(1, columns)
	var rws: int = maxi(1, rows)
	for r in rws:
		for c in cols:
			var u0: float = float(c) / float(cols)
			var u1: float = float(c + 1) / float(cols)
			var v0: float = float(r) / float(rws)
			var v1: float = float(r + 1) / float(rws)
			var p00: Vector3 = _bilinear(top_left, top_right, bottom_left, bottom_right, u0, v0)
			var p10: Vector3 = _bilinear(top_left, top_right, bottom_left, bottom_right, u1, v0)
			var p01: Vector3 = _bilinear(top_left, top_right, bottom_left, bottom_right, u0, v1)
			var p11: Vector3 = _bilinear(top_left, top_right, bottom_left, bottom_right, u1, v1)
			_any_triangle(verts, norms, uvs, p00, p10, p01, Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1))
			_any_triangle(verts, norms, uvs, p10, p11, p01, Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))
	return _mesh(verts, norms, uvs)


static func _bilinear(tl: Vector3, tr: Vector3, bl: Vector3, br: Vector3, u: float, v: float) -> Vector3:
	var top: Vector3 = tl.lerp(tr, u)
	var bottom: Vector3 = bl.lerp(br, u)
	return top.lerp(bottom, v)


## Triángulo que mira hacia arriba (si el orden dado mira hacia abajo, se invierte).
static func _flat_triangle(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2,
		uc: Vector2) -> void:
	var normal: Vector3 = (c - a).cross(b - a)
	if normal.length_squared() < 0.0000001:
		return
	normal = normal.normalized()
	if normal.y >= 0.0:
		_emit(verts, norms, uvs, a, b, c, ua, ub, uc, normal)
	else:
		_emit(verts, norms, uvs, a, c, b, ua, uc, ub, -normal)


## Triángulo con el orden dado (la lámina se dibuja por los dos lados).
static func _any_triangle(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2,
		uc: Vector2) -> void:
	var normal: Vector3 = (c - a).cross(b - a)
	if normal.length_squared() < 0.0000001:
		return
	_emit(verts, norms, uvs, a, b, c, ua, ub, uc, normal.normalized())


static func _emit(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, normal: Vector3) -> void:
	verts.append(a)
	verts.append(b)
	verts.append(c)
	norms.append(normal)
	norms.append(normal)
	norms.append(normal)
	uvs.append(ua)
	uvs.append(ub)
	uvs.append(uc)


static func _mesh(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
