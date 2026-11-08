class_name TerrainKit
extends RefCounted
## Relieve del terreno de un escenario: una cuadrícula de unos 60 x 60 cuadros cuyas alturas
## y colores salen de dos funciones que da cada escenario. Los triángulos llevan sombreado
## plano (estilo low poly) y el centro queda plano para apoyar el tablero.

## Altura del suelo bajo el tablero (la cara superior del suelo antiguo del entorno).
const PLATEAU_Y := -0.3
## Rectángulo plano que ocupan el tablero, su marco y la zona del dado.
const PLATEAU_CENTER_X := 1.9
const PLATEAU_HALF_X := 8.2
const PLATEAU_HALF_Z := 6.4
const PLATEAU_FALLOFF := 8.0


## 0 sobre la plataforma plana del tablero y 1 lejos de ella (con subida suave entre medias).
## Se multiplica por el relieve para que nunca invada el tablero.
static func board_mask(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - PLATEAU_CENTER_X) - PLATEAU_HALF_X, 0.0)
	var dz: float = maxf(absf(z) - PLATEAU_HALF_Z, 0.0)
	return smoothstep(0.0, PLATEAU_FALLOFF, sqrt(dx * dx + dz * dz))


## Malla del terreno entre -half y +half en X y Z. "height_fn(x, z) -> float" da la altura y
## "color_fn(x, z, y) -> Color" el color de cada triángulo (se evalúa en su centro).
static func build(half: float, cells: int, height_fn: Callable, color_fn: Callable,
		uv_scale: float = 0.3) -> ArrayMesh:
	var count: int = maxi(2, cells)
	var stride: int = count + 1
	var step: float = half * 2.0 / float(count)
	var heights := PackedFloat32Array()
	heights.resize(stride * stride)
	for j in stride:
		for i in stride:
			var x: float = -half + float(i) * step
			var z: float = -half + float(j) * step
			heights[j * stride + i] = float(height_fn.call(x, z))

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for j in count:
		for i in count:
			var x0: float = -half + float(i) * step
			var z0: float = -half + float(j) * step
			var p00 := Vector3(x0, heights[j * stride + i], z0)
			var p10 := Vector3(x0 + step, heights[j * stride + i + 1], z0)
			var p01 := Vector3(x0, heights[(j + 1) * stride + i], z0 + step)
			var p11 := Vector3(x0 + step, heights[(j + 1) * stride + i + 1], z0 + step)
			if (i + j) % 2 == 0:
				_triangle(verts, norms, cols, uvs, p00, p01, p11, color_fn, uv_scale)
				_triangle(verts, norms, cols, uvs, p00, p11, p10, color_fn, uv_scale)
			else:
				_triangle(verts, norms, cols, uvs, p00, p01, p10, color_fn, uv_scale)
				_triangle(verts, norms, cols, uvs, p10, p01, p11, color_fn, uv_scale)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Agrega un triángulo orientado hacia arriba, con su color y sus coordenadas de textura.
static func _triangle(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, color_fn: Callable,
		uv_scale: float) -> void:
	var normal: Vector3 = (c - a).cross(b - a)
	if normal.length_squared() < 0.0000001:
		return
	normal = normal.normalized()
	var second: Vector3 = b
	var third: Vector3 = c
	if normal.y < 0.0:
		second = c
		third = b
		normal = -normal
	var center: Vector3 = (a + b + c) / 3.0
	var color: Color = color_fn.call(center.x, center.z, center.y)
	for p in [a, second, third]:
		var point: Vector3 = p
		verts.append(point)
		norms.append(normal)
		cols.append(color)
		uvs.append(Vector2(point.x, point.z) * uv_scale)
