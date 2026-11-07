class_name MeshFactory
extends RefCounted
## Materiales y mallas procedurales compartidos por el menú y el tablero.
## Todo es geometría creada por código: no hacen falta modelos externos todavía.


static func material(color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


## Material sin sombreado con mezcla aditiva: sirve para luces, halos y brillos.
static func glow_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m


## Material que usa el color de cada vértice (terrenos y serpientes).
static func vertex_color_material(roughness: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	return m


## Tubo de sección circular que sigue una polilínea (cuerpo de las serpientes).
## Los triángulos van en sentido horario visto desde afuera, que es lo que Godot
## considera cara frontal.
static func tube(points: PackedVector3Array, radii: PackedFloat32Array,
		colors: PackedColorArray, sides: int = 8) -> ArrayMesh:
	var count: int = points.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(count * sides)
	norms.resize(count * sides)
	cols.resize(count * sides)
	for i in count:
		var tangent: Vector3
		if i == 0:
			tangent = points[1] - points[0]
		elif i == count - 1:
			tangent = points[count - 1] - points[count - 2]
		else:
			tangent = points[i + 1] - points[i - 1]
		tangent = tangent.normalized()
		var up: Vector3 = Vector3.UP - tangent * Vector3.UP.dot(tangent)
		if up.length_squared() < 0.0001:
			up = Vector3.RIGHT - tangent * Vector3.RIGHT.dot(tangent)
		up = up.normalized()
		var side: Vector3 = tangent.cross(up)
		for j in sides:
			var angle: float = TAU * float(j) / float(sides)
			var dir: Vector3 = up * cos(angle) + side * sin(angle)
			var k: int = i * sides + j
			verts[k] = points[i] + dir * radii[i]
			norms[k] = dir
			cols[k] = colors[i]
	for i in count - 1:
		for j in sides:
			var j2: int = (j + 1) % sides
			var a: int = i * sides + j
			var b: int = i * sides + j2
			var c: int = (i + 1) * sides + j
			var d: int = (i + 1) * sides + j2
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Cinta horizontal que sigue una polilínea (por ejemplo el agua del río).
## "left" y "right" son los bordes de cada tramo, ya calculados por quien llama.
static func ribbon(left: PackedVector3Array, right: PackedVector3Array) -> ArrayMesh:
	var count: int = left.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in count - 1:
		var a: Vector3 = left[i]
		var b: Vector3 = right[i]
		var c: Vector3 = left[i + 1]
		var d: Vector3 = right[i + 1]
		# Horario visto desde arriba: (a, b, c) y (b, d, c).
		for v in [a, b, c, b, d, c]:
			verts.append(v)
			norms.append(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
