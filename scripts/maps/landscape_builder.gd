class_name LandscapeBuilder
extends RefCounted
## Paisaje bíblico procedural para el fondo del menú: dunas, un río sinuoso y
## montañas lejanas en estilo "low poly". Las mallas se calculan una sola vez
## y se reutilizan en todas las pantallas del menú.

const HALF_SIZE := 80.0
const CELLS := 72
const WATER_LEVEL := 0.15
const RIVER_HALF_WIDTH := 4.0
const RIVER_WATER_HALF_WIDTH := 6.2

static var _dunes: FastNoiseLite
static var _ridges: FastNoiseLite
static var _terrain: ArrayMesh
static var _river: ArrayMesh


## Eje del río (x) para una coordenada z.
static func river_center_x(z: float) -> float:
	return 7.0 * sin(z * 0.045) + 2.5 * sin(z * 0.12 + 1.3) - 5.0


## Altura del terreno en (x, z).
static func height_at(x: float, z: float) -> float:
	_setup_noise()
	var h: float = _dunes.get_noise_2d(x, z) * 5.5 + 2.2
	var dist_river: float = absf(x - river_center_x(z))
	var channel: float = 1.0 - smoothstep(RIVER_HALF_WIDTH * 0.7, RIVER_HALF_WIDTH * 2.8, dist_river)
	h = lerpf(h, WATER_LEVEL - 1.1, channel)
	var radius: float = Vector2(x, z).length()
	var mountain: float = smoothstep(44.0, 76.0, radius)
	var ridge: float = 1.0 - absf(_ridges.get_noise_2d(x, z))
	h += mountain * (pow(ridge, 1.8) * 34.0 + 4.0)
	return h


static func terrain_mesh() -> ArrayMesh:
	if _terrain != null:
		return _terrain
	_setup_noise()
	var n: int = CELLS
	var step: float = HALF_SIZE * 2.0 / float(n)
	var stride: int = n + 1
	var heights := PackedFloat32Array()
	heights.resize(stride * stride)
	for iz in stride:
		for ix in stride:
			heights[iz * stride + ix] = height_at(-HALF_SIZE + float(ix) * step, -HALF_SIZE + float(iz) * step)

	var total: int = n * n * 6
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(total)
	norms.resize(total)
	cols.resize(total)
	var w: int = 0
	for iz in n:
		for ix in n:
			var x0: float = -HALF_SIZE + float(ix) * step
			var z0: float = -HALF_SIZE + float(iz) * step
			var a := Vector3(x0, heights[iz * stride + ix], z0)
			var b := Vector3(x0 + step, heights[iz * stride + ix + 1], z0)
			var c := Vector3(x0, heights[(iz + 1) * stride + ix], z0 + step)
			var d := Vector3(x0 + step, heights[(iz + 1) * stride + ix + 1], z0 + step)
			# Sentido horario visto desde arriba: (a, b, c) y (b, d, c).
			w = _emit_triangle(verts, norms, cols, w, a, b, c, ix * 31 + iz * 17)
			w = _emit_triangle(verts, norms, cols, w, b, d, c, ix * 31 + iz * 17 + 7)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	_terrain = ArrayMesh.new()
	_terrain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _terrain


static func river_mesh() -> ArrayMesh:
	if _river != null:
		return _river
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var z: float = -HALF_SIZE
	while z <= HALF_SIZE + 0.01:
		var cx: float = river_center_x(z)
		left.append(Vector3(cx - RIVER_WATER_HALF_WIDTH, WATER_LEVEL, z))
		right.append(Vector3(cx + RIVER_WATER_HALF_WIDTH, WATER_LEVEL, z))
		z += 2.0
	_river = MeshFactory.ribbon(left, right)
	return _river


static func _setup_noise() -> void:
	if _dunes != null:
		return
	_dunes = FastNoiseLite.new()
	_dunes.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dunes.seed = 11
	_dunes.frequency = 0.02
	_dunes.fractal_octaves = 3
	_ridges = FastNoiseLite.new()
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridges.seed = 23
	_ridges.frequency = 0.03
	_ridges.fractal_octaves = 4


static func _emit_triangle(verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, w: int, a: Vector3, b: Vector3, c: Vector3, salt: int) -> int:
	# Con el sentido horario de Godot, la normal hacia arriba es (c - a) x (b - a).
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	var centroid: Vector3 = (a + b + c) / 3.0
	var jitter: float = float(posmod(salt * 2654435, 1000)) / 1000.0 - 0.5
	var color: Color = _terrain_color(centroid, jitter * 0.09)
	verts[w] = a
	verts[w + 1] = b
	verts[w + 2] = c
	for k in 3:
		norms[w + k] = normal
		cols[w + k] = color
	return w + 3


static func _terrain_color(p: Vector3, jitter: float) -> Color:
	var dist_river: float = absf(p.x - river_center_x(p.z))
	var sand_dark := Color(0.78, 0.55, 0.32)
	var sand_light := Color(0.94, 0.80, 0.55)
	var rock_dark := Color(0.46, 0.35, 0.31)
	var rock_light := Color(0.78, 0.66, 0.56)
	var grass := Color(0.38, 0.57, 0.26)
	var wet := Color(0.55, 0.45, 0.30)
	var c: Color = sand_dark.lerp(sand_light, clampf((p.y + 1.0) / 8.0, 0.0, 1.0))
	var rockiness: float = smoothstep(9.0, 18.0, p.y)
	c = c.lerp(rock_dark.lerp(rock_light, smoothstep(18.0, 38.0, p.y)), rockiness)
	var oasis: float = (1.0 - smoothstep(5.5, 13.0, dist_river)) * (1.0 - rockiness) * smoothstep(-0.8, 1.2, p.y)
	c = c.lerp(grass, oasis * 0.85)
	if p.y < WATER_LEVEL + 0.5:
		c = c.lerp(wet, 0.8)
	if jitter > 0.0:
		return c.lightened(jitter)
	return c.darkened(-jitter)
