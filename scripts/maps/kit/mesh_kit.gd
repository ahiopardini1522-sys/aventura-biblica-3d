class_name MeshKit
extends RefCounted
## Constructor de mallas low poly. Junta muchas piezas (cajas, conos, esferas, tubos, techos...)
## en UNA sola malla con color por vértice y coordenadas de textura planares, para dibujar un
## escenario entero con muy pocas llamadas de dibujo (importante en un móvil de gama media).
##
## Todas las piezas se colocan en el espacio local actual ("xf"): con place() y pop() se
## mueve, gira y escala lo que se agregue después. Las caras salen siempre hacia afuera:
## cada triángulo se orienta comparando su normal con una dirección de referencia, así que
## el orden en que se den los vértices no importa.

## Transformación que se aplica a todo lo que se agrega.
var xf: Transform3D = Transform3D.IDENTITY
## Repeticiones de la textura por metro (UVs planares según la cara dominante).
var uv_scale: float = 0.5
## Si es verdadero, en las caras verticales la textura se gira un cuarto de vuelta (las vetas
## de los tablones quedan horizontales, como en el casco de un barco).
var side_uv_swap: bool = false

var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _cols := PackedColorArray()
var _uvs := PackedVector2Array()
var _stack: Array[Transform3D] = []


func is_empty() -> bool:
	return _verts.is_empty()


func vertex_count() -> int:
	return _verts.size()


func triangle_count() -> int:
	return floori(float(_verts.size()) / 3.0)


func clear() -> void:
	_verts.clear()
	_norms.clear()
	_cols.clear()
	_uvs.clear()
	_stack.clear()
	xf = Transform3D.IDENTITY


# ---------------------------------------------------------------- Colocación

## Mueve, gira (alrededor de Y, en radianes) y escala lo que se agregue a continuación.
## Se deshace con pop().
func place(pos: Vector3, yaw: float = 0.0, scale_vec: Vector3 = Vector3.ONE) -> void:
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(scale_vec)
	push_xf(Transform3D(basis, pos))


func push_xf(local: Transform3D) -> void:
	_stack.append(xf)
	xf = xf * local


func pop() -> void:
	if _stack.is_empty():
		xf = Transform3D.IDENTITY
		return
	xf = _stack.pop_back()


# ---------------------------------------------------------------- Triángulos

## Un triángulo. "outward" es un desplazamiento que sale del cuerpo hacia esa cara (por
## ejemplo, del centro del cuerpo al centro de la cara): si el orden de los vértices deja la
## cara mirando hacia adentro, se invierte.
func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, outward: Vector3) -> void:
	var wa: Vector3 = xf * a
	var wb: Vector3 = xf * b
	var wc: Vector3 = xf * c
	var normal: Vector3 = (wc - wa).cross(wb - wa)
	var length: float = normal.length()
	if length < 0.0000001:
		return
	normal /= length
	var want: Vector3 = xf.basis * outward
	if normal.dot(want) < 0.0:
		var swap: Vector3 = wb
		wb = wc
		wc = swap
		normal = -normal
	_push(wa, wb, wc, normal, color)


## Un triángulo cuyo orden de vértices ya es el correcto (horario visto desde afuera).
## Si la transformación actual refleja la pieza, se corrige sola.
func tri_raw(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var wa: Vector3 = xf * a
	var wb: Vector3 = xf * b
	var wc: Vector3 = xf * c
	if xf.basis.determinant() < 0.0:
		var swap: Vector3 = wb
		wb = wc
		wc = swap
	var normal: Vector3 = (wc - wa).cross(wb - wa)
	var length: float = normal.length()
	if length < 0.0000001:
		return
	_push(wa, wb, wc, normal / length, color)


## Un cuadrilátero (a, b, c, d en orden alrededor). Misma regla de orientación que tri().
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, outward: Vector3) -> void:
	tri(a, b, c, color, outward)
	tri(a, c, d, color, outward)


func _push(a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color) -> void:
	var mode: int = 2
	var ax: float = absf(n.x)
	var ay: float = absf(n.y)
	var az: float = absf(n.z)
	if ay >= ax and ay >= az:
		mode = 0
	elif ax >= az:
		mode = 1
	_add_vertex(a, n, color, mode)
	_add_vertex(b, n, color, mode)
	_add_vertex(c, n, color, mode)


func _add_vertex(p: Vector3, n: Vector3, color: Color, mode: int) -> void:
	_verts.append(p)
	_norms.append(n)
	_cols.append(color)
	var uv: Vector2 = Vector2(p.x, p.z)
	if mode == 1:
		uv = Vector2(p.z, -p.y)
		if side_uv_swap:
			uv = Vector2(-p.y, p.z)
	elif mode == 2:
		uv = Vector2(p.x, -p.y)
		if side_uv_swap:
			uv = Vector2(-p.y, p.x)
	_uvs.append(uv * uv_scale)


# ---------------------------------------------------------------- Piezas

## Caja alineada con los ejes (en el espacio local). "top_color" con alfa 0 = igual que el resto.
func box(center: Vector3, size: Vector3, color: Color, top_color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var h: Vector3 = size * 0.5
	var top: Color = color
	if top_color.a > 0.0:
		top = top_color
	var x0: float = center.x - h.x
	var x1: float = center.x + h.x
	var y0: float = center.y - h.y
	var y1: float = center.y + h.y
	var z0: float = center.z - h.z
	var z1: float = center.z + h.z
	# +y
	quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), top, Vector3.UP)
	# -y
	quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), color, Vector3.DOWN)
	# +x
	quad(Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), color, Vector3.RIGHT)
	# -x
	quad(Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), color, Vector3.LEFT)
	# +z
	quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), color, Vector3.BACK)
	# -z
	quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), color, Vector3.FORWARD)


## Cilindro, cono truncado o cono (radius_top = 0) con el eje en Y, apoyado en "base".
## "phase" gira la figura (con 4 lados y PI/4 las caras quedan alineadas con los ejes).
func cylinder(base: Vector3, radius_bottom: float, radius_top: float, height: float, sides: int,
		color: Color, cap_top: bool = true, cap_bottom: bool = false,
		top_color: Color = Color(0.0, 0.0, 0.0, 0.0), phase: float = 0.0) -> void:
	var count: int = maxi(3, sides)
	var center: Vector3 = base + Vector3(0.0, height * 0.5, 0.0)
	var ring_bottom: Array[Vector3] = []
	var ring_top: Array[Vector3] = []
	for j in count:
		var angle: float = phase + TAU * float(j) / float(count)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		ring_bottom.append(base + dir * radius_bottom)
		ring_top.append(base + Vector3(0.0, height, 0.0) + dir * radius_top)
	var apex: Vector3 = base + Vector3(0.0, height, 0.0)
	var pointed: bool = radius_top <= 0.0001
	var cap_color: Color = color
	if top_color.a > 0.0:
		cap_color = top_color
	for j in count:
		var j2: int = (j + 1) % count
		var face_center: Vector3 = (ring_bottom[j] + ring_bottom[j2] + ring_top[j] + ring_top[j2]) * 0.25
		if pointed:
			tri(ring_bottom[j], ring_bottom[j2], apex, color, face_center - center)
		else:
			quad(ring_bottom[j], ring_bottom[j2], ring_top[j2], ring_top[j], color, face_center - center)
			if cap_top:
				tri(apex, ring_top[j], ring_top[j2], cap_color, Vector3.UP)
		if cap_bottom:
			tri(base, ring_bottom[j], ring_bottom[j2], color, Vector3.DOWN)


## Cono con la punta hacia arriba.
func cone(base: Vector3, radius: float, height: float, sides: int, color: Color) -> void:
	cylinder(base, radius, 0.0, height, sides, color, false, false)


## Pirámide de base cuadrada alineada con los ejes ("half" es la mitad del lado de la base).
func pyramid(base: Vector3, half: float, height: float, color: Color) -> void:
	cylinder(base, half * 1.41421356, 0.0, height, 4, color, false, false, Color(0.0, 0.0, 0.0, 0.0), PI * 0.25)


## Tronco de pirámide de base cuadrada (obeliscos, torres, muros inclinados).
func frustum(base: Vector3, half_bottom: float, half_top: float, height: float, color: Color,
		top_color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	cylinder(base, half_bottom * 1.41421356, half_top * 1.41421356, height, 4, color, true, false,
			top_color, PI * 0.25)


## Esfera achatada o alargada (radios por eje) de pocas caras. Con "jitter" y un generador
## aleatorio queda irregular, como una roca o la copa de un árbol. "low_color" (alfa > 0)
## pinta la parte baja con otro tono. "lat_end" = PI/2 da una media esfera (cúpula).
func sphere(center: Vector3, radii: Vector3, color: Color, segments: int = 8, rings: int = 5,
		jitter: float = 0.0, rng: RandomNumberGenerator = null, lat_end: float = PI,
		low_color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var seg_count: int = maxi(3, segments)
	var ring_count: int = maxi(2, rings)
	var grid: Array[Vector3] = []
	for i in ring_count + 1:
		var lat: float = lat_end * float(i) / float(ring_count)
		var ring_radius: float = sin(lat)
		var y: float = cos(lat)
		var first_jit: float = 1.0
		if jitter > 0.0 and rng != null:
			first_jit = 1.0 + rng.randf_range(-jitter, jitter)
		for j in seg_count:
			var jit: float = first_jit
			var on_pole: bool = i == 0 or (i == ring_count and lat_end >= PI - 0.001)
			if jitter > 0.0 and rng != null and j > 0 and not on_pole:
				jit = 1.0 + rng.randf_range(-jitter, jitter)
			var angle: float = TAU * float(j) / float(seg_count)
			grid.append(center + Vector3(cos(angle) * ring_radius * radii.x * jit,
					y * radii.y * jit, sin(angle) * ring_radius * radii.z * jit))
	var use_low: bool = low_color.a > 0.0
	for i in ring_count:
		var mid: float = (float(i) + 0.5) / float(ring_count)
		var tint: Color = color
		if use_low:
			tint = color.lerp(low_color, mid)
		for j in seg_count:
			var j2: int = (j + 1) % seg_count
			var p00: Vector3 = grid[i * seg_count + j]
			var p01: Vector3 = grid[i * seg_count + j2]
			var p10: Vector3 = grid[(i + 1) * seg_count + j]
			var p11: Vector3 = grid[(i + 1) * seg_count + j2]
			tri(p00, p01, p11, tint, (p00 + p01 + p11) / 3.0 - center)
			tri(p00, p11, p10, tint, (p00 + p11 + p10) / 3.0 - center)


## Cúpula: media esfera apoyada en "base".
func dome(base: Vector3, radius: float, color: Color, segments: int = 12, rings: int = 4,
		height_scale: float = 1.0) -> void:
	sphere(base, Vector3(radius, radius * height_scale, radius), color, segments, rings, 0.0,
			null, PI * 0.5)


## Techo a dos aguas: la cumbrera corre a lo largo de X. "size" = (largo, alto, ancho).
func gable(base_center: Vector3, size: Vector3, color: Color,
		gable_color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var ends: Color = color
	if gable_color.a > 0.0:
		ends = gable_color
	var e00: Vector3 = base_center + Vector3(-hx, 0.0, -hz)
	var e10: Vector3 = base_center + Vector3(hx, 0.0, -hz)
	var e01: Vector3 = base_center + Vector3(-hx, 0.0, hz)
	var e11: Vector3 = base_center + Vector3(hx, 0.0, hz)
	var r0: Vector3 = base_center + Vector3(-hx, size.y, 0.0)
	var r1: Vector3 = base_center + Vector3(hx, size.y, 0.0)
	quad(e01, e11, r1, r0, color, Vector3(0.0, 0.5, 1.0))
	quad(e00, e10, r1, r0, color, Vector3(0.0, 0.5, -1.0))
	tri(e00, e01, r0, ends, Vector3(-1.0, 0.0, 0.0))
	tri(e10, e11, r1, ends, Vector3(1.0, 0.0, 0.0))


## Tubo que sigue una polilínea (cuerda, arcoíris, raíz, serpiente enroscada).
## "radii" tiene un radio por punto. Con "caps" se cierran los dos extremos.
func tube(points: PackedVector3Array, radii: PackedFloat32Array, color: Color, sides: int = 6,
		caps: bool = false, end_color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var count: int = points.size()
	var side_count: int = maxi(3, sides)
	if count < 2 or radii.size() < count:
		return
	var rings: Array[Vector3] = []
	for i in count:
		var tangent: Vector3
		if i == 0:
			tangent = points[1] - points[0]
		elif i == count - 1:
			tangent = points[count - 1] - points[count - 2]
		else:
			tangent = points[i + 1] - points[i - 1]
		if tangent.length_squared() < 0.0000001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var up: Vector3 = Vector3.UP - tangent * Vector3.UP.dot(tangent)
		if up.length_squared() < 0.0001:
			up = Vector3.RIGHT - tangent * Vector3.RIGHT.dot(tangent)
		up = up.normalized()
		var side: Vector3 = tangent.cross(up)
		for j in side_count:
			var angle: float = TAU * float(j) / float(side_count)
			rings.append(points[i] + (up * cos(angle) + side * sin(angle)) * radii[i])
	for i in count - 1:
		var tint: Color = color
		if end_color.a > 0.0:
			tint = color.lerp(end_color, float(i) / float(count - 1))
		var axis: Vector3 = (points[i] + points[i + 1]) * 0.5
		for j in side_count:
			var j2: int = (j + 1) % side_count
			var a: Vector3 = rings[i * side_count + j]
			var b: Vector3 = rings[i * side_count + j2]
			var c: Vector3 = rings[(i + 1) * side_count + j2]
			var d: Vector3 = rings[(i + 1) * side_count + j]
			var face_center: Vector3 = (a + b + c + d) * 0.25
			quad(a, b, c, d, tint, face_center - axis)
	if caps:
		for j in side_count:
			var j2: int = (j + 1) % side_count
			tri(points[0], rings[j], rings[j2], color, points[0] - points[1])
			var last: int = (count - 1) * side_count
			tri(points[count - 1], rings[last + j], rings[last + j2], color,
					points[count - 1] - points[count - 2])


## Prisma a partir de un polígono en el plano XZ (puede ser cóncavo). La tapa de arriba lleva
## "top_color". Sirve para muros curvos, riberas, plataformas y tejados planos.
func extrude(polygon: PackedVector2Array, y0: float, y1: float, color: Color,
		top_color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var count: int = polygon.size()
	if count < 3:
		return
	var cap: Color = color
	if top_color.a > 0.0:
		cap = top_color
	var area: float = 0.0
	for i in count:
		var p: Vector2 = polygon[i]
		var q: Vector2 = polygon[(i + 1) % count]
		area += p.x * q.y - q.x * p.y
	var flip: float = 1.0
	if area < 0.0:
		flip = -1.0
	for i in count:
		var p: Vector2 = polygon[i]
		var q: Vector2 = polygon[(i + 1) % count]
		var edge: Vector2 = q - p
		var outward := Vector3(edge.y, 0.0, -edge.x) * flip
		var a := Vector3(p.x, y0, p.y)
		var b := Vector3(q.x, y0, q.y)
		var c := Vector3(q.x, y1, q.y)
		var d := Vector3(p.x, y1, p.y)
		quad(a, b, c, d, color, outward)
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	var k: int = 0
	while k + 2 < triangles.size():
		var pa: Vector2 = polygon[triangles[k]]
		var pb: Vector2 = polygon[triangles[k + 1]]
		var pc: Vector2 = polygon[triangles[k + 2]]
		tri(Vector3(pa.x, y1, pa.y), Vector3(pb.x, y1, pb.y), Vector3(pc.x, y1, pc.y), cap, Vector3.UP)
		k += 3


## Disco plano mirando hacia arriba.
func disc(center: Vector3, radius: float, color: Color, sides: int = 12) -> void:
	var count: int = maxi(3, sides)
	for j in count:
		var a0: float = TAU * float(j) / float(count)
		var a1: float = TAU * float(j + 1) / float(count)
		tri(center, center + Vector3(cos(a0), 0.0, sin(a0)) * radius,
				center + Vector3(cos(a1), 0.0, sin(a1)) * radius, color, Vector3.UP)


## Viga: una caja que va del punto "from" al punto "to", con sección (ancho, alto).
func beam(from: Vector3, to: Vector3, width: float, height: float, color: Color) -> void:
	var delta: Vector3 = to - from
	var length: float = delta.length()
	if length < 0.0001:
		return
	var direction: Vector3 = delta / length
	var up: Vector3 = Vector3.UP
	if absf(direction.y) > 0.98:
		up = Vector3.RIGHT
	var basis := Basis.looking_at(direction, up)
	push_xf(Transform3D(basis, (from + to) * 0.5))
	box(Vector3.ZERO, Vector3(width, height, length), color)
	pop()


## Estrella plana de cinco puntas en el plano XY, mirando hacia +Z (se ve por los dos lados).
func star(center: Vector3, outer: float, inner: float, color: Color) -> void:
	var points: Array[Vector3] = []
	for i in 10:
		var radius: float = outer
		if i % 2 == 1:
			radius = inner
		var angle: float = PI * 0.5 + TAU * float(i) / 10.0
		points.append(center + Vector3(cos(angle) * radius, sin(angle) * radius, 0.0))
	for i in 10:
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % 10]
		tri(center, a, b, color, Vector3.BACK)
		tri(center, a, b, color, Vector3.FORWARD)


# ---------------------------------------------------------------- Resultado

## Malla con todo lo agregado (vacía si no se agregó nada).
func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_COLOR] = _cols
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Nodo listo para agregar a la escena. Sin sombras propias (el sol solo sombrea el tablero).
func instance(material: Material, node_name: String = "Mesh") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = commit()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Color un poco distinto del original (variedad en bosques, rocas y casas).
static func vary_color(color: Color, amount: float, rng: RandomNumberGenerator) -> Color:
	var shift: float = rng.randf_range(-amount, amount)
	return Color(clampf(color.r + shift, 0.0, 1.0), clampf(color.g + shift * 0.8, 0.0, 1.0),
			clampf(color.b + shift * 0.6, 0.0, 1.0), color.a)
