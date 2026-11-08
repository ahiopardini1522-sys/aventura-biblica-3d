class_name TextureKit
extends RefCounted
## Texturas pequeñas (64 x 64) hechas por código: hierba, arena, piedra, ladrillos, tablones...
## y los materiales que las usan. Son neutras (tonos de gris claro): el color de cada objeto
## viene del color por vértice de la malla, y la textura solo le agrega relieve. Todo se
## guarda en caché, así que cada textura y cada material se crean una sola vez.

const SIZE := 64
## Ganancia que compensa que las texturas son algo más oscuras que el color liso.
const GAIN := 1.12

static var _textures: Dictionary = {}
static var _materials: Dictionary = {}
static var _dot: ImageTexture


## Nombres de las texturas disponibles.
static func kinds() -> Array[String]:
	return ["grass", "sand", "dirt", "stone", "rock", "cobble", "bricks", "planks", "sandstone", "plaster"]


static func texture(kind: String) -> ImageTexture:
	if not _textures.has(kind):
		_textures[kind] = _build(kind)
	return _textures[kind]


## Material con textura que usa el color por vértice de la malla como color base.
static func material(kind: String, roughness: float = 0.9) -> StandardMaterial3D:
	var key: String = "%s_%.2f" % [kind, roughness]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = texture(kind)
		m.albedo_color = Color(GAIN, GAIN, GAIN, 1.0)
		m.roughness = roughness
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_materials[key] = m
	return _materials[key]


## Material liso que usa solo el color por vértice.
static func plain(roughness: float = 0.9) -> StandardMaterial3D:
	var key: String = "plain_%.2f" % roughness
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = roughness
		_materials[key] = m
	return _materials[key]


## Material sin sombreado y con mezcla aditiva que usa el color por vértice (luces, estrellas,
## haces de luz, brillos). No le afecta la niebla.
static func glow_vertex(additive: bool = true) -> StandardMaterial3D:
	var key: String = "glow_vertex_%s" % str(additive)
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.set("disable_fog", true)
		_materials[key] = m
	return _materials[key]


## Material de las partículas: punto suave que mira siempre a la cámara.
static func particle_material(additive: bool = false) -> StandardMaterial3D:
	var key: String = "particle_%s" % str(additive)
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = soft_dot()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]


## Punto blanco con los bordes difusos (para partículas).
static func soft_dot() -> ImageTexture:
	if _dot == null:
		var pixels: int = 32
		var image := Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
		for y in pixels:
			for x in pixels:
				var u: float = (float(x) + 0.5) / float(pixels) * 2.0 - 1.0
				var v: float = (float(y) + 0.5) / float(pixels) * 2.0 - 1.0
				var alpha: float = 1.0 - smoothstep(0.0, 1.0, sqrt(u * u + v * v))
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
		_dot = ImageTexture.create_from_image(image)
	return _dot


# ---------------------------------------------------------------- Generación

static func _build(kind: String) -> ImageTexture:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var shade: float = clampf(_shade(kind, x, y), 0.0, 1.0)
			image.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Brillo (0 a 1) del píxel (x, y) de cada textura. Todas son repetibles sin costuras.
static func _shade(kind: String, x: int, y: int) -> float:
	var u: float = (float(x) + 0.5) / float(SIZE)
	var v: float = (float(y) + 0.5) / float(SIZE)
	match kind:
		"grass":
			var value: float = 0.80 + 0.20 * _fbm(u, v, 8, 3, 11)
			var speck: float = _hash(x, y, 5)
			if speck > 0.93:
				value *= 0.86
			if speck > 0.985:
				value *= 1.15
			return value
		"sand":
			var grain: float = _fbm(u, v, 12, 2, 21)
			var ripple: float = sin((u * 2.0 + grain * 0.6) * TAU) * 0.04
			return 0.90 + 0.10 * grain + ripple
		"dirt":
			var base: float = 0.76 + 0.24 * _fbm(u, v, 6, 3, 31)
			var pebble: float = _hash(x, y, 9)
			if pebble > 0.965:
				base *= 0.75
			return base
		"stone":
			return _stone(u, v, 5, 41, 0.12, 0.55)
		"rock":
			return _stone(u, v, 4, 51, 0.2, 0.42) * (0.82 + 0.18 * _fbm(u, v, 6, 3, 52))
		"cobble":
			return _stone(u, v, 6, 61, 0.2, 0.5)
		"bricks":
			var row: int = y >> 3
			var shift: int = 0
			if row % 2 == 1:
				shift = 8
			var bx: int = (x + shift) & 15
			var by: int = y & 7
			if bx == 0 or by == 0:
				return 0.56
			var brick_id: float = _hash((x + shift) >> 4, row, 71)
			return 0.78 + 0.22 * brick_id - 0.06 * _fbm(u, v, 16, 2, 72)
		"planks":
			var plank: int = x >> 4
			if (x & 15) == 0:
				return 0.5
			var tone: float = 0.80 + 0.2 * _hash(plank, 3, 81)
			var grain: float = _noise(u * 4.0, v * 2.0, 4, 2, 82)
			var knot: float = _noise(u * 8.0, v * 8.0, 8, 8, 83)
			return tone * (0.88 + 0.12 * grain) - maxf(0.0, knot - 0.82) * 0.5
		"sandstone":
			var block_row: int = y >> 4
			var offset: int = 0
			if block_row % 2 == 1:
				offset = 16
			var cx: int = (x + offset) & 31
			var cy: int = y & 15
			if cx == 0 or cy == 0:
				return 0.68
			var block_id: float = _hash((x + offset) >> 5, block_row, 91)
			return 0.84 + 0.16 * block_id - 0.05 * _fbm(u, v, 10, 2, 92)
		"plaster":
			return 0.90 + 0.10 * _fbm(u, v, 6, 3, 101)
	return 0.9


## Piedras irregulares separadas por grietas (ruido celular repetible).
static func _stone(u: float, v: float, cells: int, seed_value: int, crack: float, crack_dark: float) -> float:
	var info: Vector3 = _cells(u, v, cells, seed_value)
	var edge: float = info.y - info.x
	var line: float = smoothstep(0.0, crack, edge)
	var tone: float = 0.80 + 0.20 * info.z
	return lerpf(crack_dark, 1.0, line) * tone


## Devuelve (distancia al punto más cercano, distancia al segundo, número aleatorio de la celda).
static func _cells(u: float, v: float, cells: int, seed_value: int) -> Vector3:
	var px: float = u * float(cells)
	var py: float = v * float(cells)
	var cx: int = floori(px)
	var cy: int = floori(py)
	var best: float = 9.0
	var second: float = 9.0
	var best_id: float = 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var gx: int = cx + ox
			var gy: int = cy + oy
			var wx: int = posmod(gx, cells)
			var wy: int = posmod(gy, cells)
			var fx: float = float(gx) + _hash(wx, wy, seed_value)
			var fy: float = float(gy) + _hash(wx, wy, seed_value + 17)
			var distance: float = Vector2(px - fx, py - fy).length()
			if distance < best:
				second = best
				best = distance
				best_id = _hash(wx, wy, seed_value + 33)
			elif distance < second:
				second = distance
	return Vector3(best, second, best_id)


## Número pseudoaleatorio (0 a 1) que depende solo de la posición en la cuadrícula.
static func _hash(ix: int, iy: int, seed_value: int) -> float:
	var h: int = ix * 374761393 + iy * 668265263 + seed_value * 144665
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## Ruido de valores suave y repetible: x e y en unidades de celda, con "px" y "py" celdas por lado.
static func _noise(x: float, y: float, px: int, py: int, seed_value: int) -> float:
	var x0: int = floori(x)
	var y0: int = floori(y)
	var fx: float = x - float(x0)
	var fy: float = y - float(y0)
	var sx: float = fx * fx * (3.0 - 2.0 * fx)
	var sy: float = fy * fy * (3.0 - 2.0 * fy)
	var a: float = _hash(posmod(x0, px), posmod(y0, py), seed_value)
	var b: float = _hash(posmod(x0 + 1, px), posmod(y0, py), seed_value)
	var c: float = _hash(posmod(x0, px), posmod(y0 + 1, py), seed_value)
	var d: float = _hash(posmod(x0 + 1, px), posmod(y0 + 1, py), seed_value)
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


## Suma de varias capas de ruido (cada una con el doble de detalle y la mitad de fuerza).
static func _fbm(u: float, v: float, period: int, octaves: int, seed_value: int) -> float:
	var total: float = 0.0
	var amplitude: float = 0.5
	var norm: float = 0.0
	var cells: int = period
	for octave in octaves:
		total += amplitude * _noise(u * float(cells), v * float(cells), cells, cells, seed_value + octave * 7)
		norm += amplitude
		amplitude *= 0.5
		cells *= 2
	return total / norm
