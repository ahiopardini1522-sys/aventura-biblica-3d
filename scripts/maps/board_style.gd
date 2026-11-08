class_name BoardStyle
extends RefCounted
## El aspecto 3D propio de cada tipo de tablero: cómo es cada casilla, cómo es el borde y de qué
## colores son las escaleras y las serpientes. No es el mismo tablero con otros colores:
##   garden   (Edén)             losas de piedra con musgo y flores, seto alrededor
##   deck     (Arca de Noé)      cubierta de tablones con ranuras, borda de barco
##   causeway (Egipto)           bloques de arenisca con friso dorado y muro bajo
##   sand     (Desierto)         losas de arena, con unas piedras en las esquinas
##   rock     (Monte Sinaí)      lajas irregulares de roca, bloques de piedra alrededor
##   city     (Jerusalén)        adoquines en cuatro piezas y muralla con almenas
##   village  (Belén)            tierra con piedras redondas y una cerca de madera con faroles
## Todas las casillas de un tablero se juntan en una sola malla (ver BoardBuilder).

const STYLES: Array[String] = ["garden", "deck", "causeway", "sand", "rock", "city", "village"]


## El estilo pedido, o "sand" si no se conoce.
static func normalize(style: String) -> String:
	if STYLES.has(style):
		return style
	return "sand"


## Textura (de TextureKit) que da relieve a la superficie del tablero.
static func texture_kind(style: String) -> String:
	match style:
		"garden":
			return "grass"
		"deck":
			return "dirt"
		"causeway":
			return "sandstone"
		"rock":
			return "rock"
		"city":
			return "stone"
		"village":
			return "dirt"
	return "sand"


## Repeticiones de la textura por metro. En Egipto se elige para que las juntas de los bloques
## coincidan con los huecos entre casillas.
static func texture_scale(style: String) -> float:
	match style:
		"garden":
			return 0.55
		"deck":
			return 0.7
		"causeway":
			return 0.46
		"rock":
			return 0.9
		"city":
			return 0.6
		"village":
			return 0.8
	return 0.5


## Colores de la escalera por estilo: [largueros, peldaños].
const LADDER_COLORS := {
	"garden": [Color(0.34, 0.56, 0.26), Color(0.62, 0.44, 0.24)],
	"deck": [Color(0.42, 0.28, 0.15), Color(0.82, 0.72, 0.46)],
	"causeway": [Color(0.74, 0.54, 0.26), Color(0.90, 0.74, 0.36)],
	"sand": [Color(0.58, 0.38, 0.19), Color(0.58, 0.38, 0.19)],
	"rock": [Color(0.50, 0.46, 0.42), Color(0.72, 0.66, 0.58)],
	"city": [Color(0.84, 0.80, 0.70), Color(0.62, 0.56, 0.46)],
	"village": [Color(0.50, 0.34, 0.20), Color(0.66, 0.48, 0.28)],
}

## Colores de las siete serpientes de cada estilo.
const SNAKE_COLORS := {
	"garden": [Color(0.30, 0.65, 0.30), Color(0.55, 0.72, 0.22), Color(0.20, 0.50, 0.35),
			Color(0.78, 0.62, 0.18), Color(0.82, 0.30, 0.24), Color(0.30, 0.55, 0.62), Color(0.48, 0.36, 0.62)],
	"deck": [Color(0.20, 0.55, 0.62), Color(0.25, 0.40, 0.66), Color(0.40, 0.32, 0.62),
			Color(0.18, 0.60, 0.50), Color(0.58, 0.30, 0.50), Color(0.30, 0.62, 0.68), Color(0.22, 0.34, 0.50)],
	"causeway": [Color(0.82, 0.62, 0.20), Color(0.70, 0.42, 0.16), Color(0.24, 0.22, 0.20),
			Color(0.62, 0.18, 0.14), Color(0.34, 0.55, 0.38), Color(0.86, 0.74, 0.34), Color(0.50, 0.30, 0.12)],
	"sand": [Color(0.30, 0.65, 0.30), Color(0.82, 0.50, 0.20), Color(0.58, 0.36, 0.72),
			Color(0.20, 0.60, 0.64), Color(0.80, 0.28, 0.25), Color(0.62, 0.64, 0.22), Color(0.30, 0.40, 0.66)],
	"rock": [Color(0.55, 0.42, 0.30), Color(0.42, 0.38, 0.36), Color(0.66, 0.36, 0.22),
			Color(0.36, 0.30, 0.28), Color(0.70, 0.52, 0.30), Color(0.50, 0.26, 0.20), Color(0.32, 0.36, 0.40)],
	"city": [Color(0.80, 0.50, 0.20), Color(0.55, 0.36, 0.68), Color(0.20, 0.55, 0.55),
			Color(0.78, 0.28, 0.25), Color(0.62, 0.62, 0.22), Color(0.30, 0.40, 0.66), Color(0.42, 0.60, 0.30)],
	"village": [Color(0.40, 0.58, 0.35), Color(0.58, 0.42, 0.64), Color(0.35, 0.52, 0.66),
			Color(0.66, 0.34, 0.30), Color(0.58, 0.60, 0.30), Color(0.30, 0.38, 0.62), Color(0.68, 0.50, 0.28)],
}


## Colores de la escalera: [largueros, peldaños].
static func ladder_colors(style: String) -> Array[Color]:
	return _colors_of(LADDER_COLORS, style)


## Colores de las siete serpientes de un tablero.
static func snake_colors(style: String) -> Array[Color]:
	return _colors_of(SNAKE_COLORS, style)


static func _colors_of(table: Dictionary, style: String) -> Array[Color]:
	var result: Array[Color] = []
	var raw: Array = table[normalize(style)]
	for entry in raw:
		result.append(entry)
	return result


# ---------------------------------------------------------------- Casillas

## Agrega la casilla centrada en "center" (x, z; la cara superior queda en TILE_HEIGHT).
static func add_tile(kit: MeshKit, style: String, center: Vector3, color: Color, rng: RandomNumberGenerator) -> void:
	kit.place(Vector3(center.x, 0.0, center.z))
	match style:
		"garden":
			_tile_garden(kit, color, rng)
		"deck":
			_tile_deck(kit, color, rng)
		"causeway":
			_tile_causeway(kit, color)
		"rock":
			_tile_rock(kit, color, rng)
		"city":
			_tile_city(kit, color, rng)
		"village":
			_tile_village(kit, color, rng)
		_:
			_tile_sand(kit, color)
	kit.pop()


## Rectángulo plano que mira hacia arriba (franjas, juntas, manchas).
static func _flat_rect(kit: MeshKit, x0: float, z0: float, x1: float, z1: float, y: float, color: Color) -> void:
	kit.quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), color, Vector3.UP)


static func _tile_sand(kit: MeshKit, color: Color) -> void:
	var h: float = BoardLayout.TILE_HEIGHT
	kit.frustum(Vector3.ZERO, 0.5, 0.48, h, color.darkened(0.2), color)


## Losa de piedra con el borde biselado, a veces con una mancha de musgo o una florecilla.
static func _tile_garden(kit: MeshKit, color: Color, rng: RandomNumberGenerator) -> void:
	var h: float = BoardLayout.TILE_HEIGHT
	kit.frustum(Vector3.ZERO, 0.5, 0.46, h, color.darkened(0.24), color)
	if rng.randf() < 0.45:
		var corner: float = -1.0 if rng.randf() < 0.5 else 1.0
		kit.disc(Vector3(corner * 0.34, h + 0.006, corner * 0.34), rng.randf_range(0.10, 0.17),
				MeshKit.vary_color(Color(0.30, 0.55, 0.26), 0.08, rng), 7)
	if rng.randf() < 0.22:
		var petals: Array[Color] = [Color(0.98, 0.95, 0.85), Color(0.98, 0.82, 0.30), Color(0.95, 0.55, 0.65),
				Color(0.70, 0.60, 0.95)]
		PropKit.flower(kit, Vector3(0.36, h, 0.36), petals[rng.randi() % petals.size()], 0.9)


## Cuatro tablones a lo largo de X con una ranura entre ellos (la que deja ver el marco oscuro).
static func _tile_deck(kit: MeshKit, color: Color, rng: RandomNumberGenerator) -> void:
	var h: float = BoardLayout.TILE_HEIGHT
	for i in 4:
		var plank: Color = MeshKit.vary_color(color, 0.06, rng)
		kit.box(Vector3(0.0, h * 0.5, -0.375 + 0.25 * float(i)), Vector3(1.0, h, 0.226), plank.darkened(0.2), plank)


## Bloque de arenisca con un friso dorado en el borde.
static func _tile_causeway(kit: MeshKit, color: Color) -> void:
	var h: float = BoardLayout.TILE_HEIGHT
	var gold := Color(0.90, 0.72, 0.28)
	kit.box(Vector3(0.0, h * 0.5, 0.0), Vector3(1.0, h, 1.0), color.darkened(0.2), color)
	var y: float = h + 0.006
	_flat_rect(kit, -0.45, -0.46, 0.45, -0.41, y, gold)
	_flat_rect(kit, -0.45, 0.41, 0.45, 0.46, y, gold)
	_flat_rect(kit, -0.46, -0.41, -0.41, 0.41, y, gold)
	_flat_rect(kit, 0.41, -0.41, 0.46, 0.41, y, gold)


## Laja irregular de ocho lados: las esquinas dejan ver la roca oscura del marco.
static func _tile_rock(kit: MeshKit, color: Color, rng: RandomNumberGenerator) -> void:
	var h: float = BoardLayout.TILE_HEIGHT
	var points := PackedVector2Array()
	for i in 8:
		var angle: float = PI / 8.0 + TAU * float(i) / 8.0 + rng.randf_range(-0.07, 0.07)
		var radius: float = rng.randf_range(0.49, 0.545)
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	kit.extrude(points, 0.0, h, color.darkened(0.22), MeshKit.vary_color(color, 0.03, rng))


## Adoquín en cuatro piezas con juntas finas.
static func _tile_city(kit: MeshKit, color: Color, rng: RandomNumberGenerator) -> void:
	var h: float = BoardLayout.TILE_HEIGHT
	for ix in [-1.0, 1.0]:
		for iz in [-1.0, 1.0]:
			var stone: Color = MeshKit.vary_color(color, 0.045, rng)
			kit.box(Vector3(float(ix) * 0.25, h * 0.5, float(iz) * 0.25), Vector3(0.48, h, 0.48),
					stone.darkened(0.2), stone)


## Tierra apisonada con cuatro piedras redondas.
static func _tile_village(kit: MeshKit, color: Color, rng: RandomNumberGenerator) -> void:
	var h: float = BoardLayout.TILE_HEIGHT
	var soil: Color = color.darkened(0.45)
	kit.box(Vector3(0.0, h * 0.4, 0.0), Vector3(1.0, h * 0.8, 1.0), soil.darkened(0.1), soil)
	var spots: Array[Vector2] = [Vector2(-0.25, -0.25), Vector2(0.25, -0.25), Vector2(-0.25, 0.25), Vector2(0.25, 0.25)]
	for spot in spots:
		var stone: Color = MeshKit.vary_color(color, 0.06, rng)
		kit.cylinder(Vector3(spot.x + rng.randf_range(-0.03, 0.03), 0.0, spot.y + rng.randf_range(-0.03, 0.03)),
				0.24, 0.22, h, 7, stone.darkened(0.2), true, false, stone)


# ---------------------------------------------------------------- Borde del tablero

## Decoración sobre el marco. "glow" recibe las luces (faroles). Cuida que lo que queda delante
## del tablero sea bajo para no tapar la primera fila.
static func add_frame_decor(kit: MeshKit, glow: MeshKit, style: String, size: Vector2,
		rng: RandomNumberGenerator, frame_color: Color) -> void:
	var ex: float = size.x * 0.5 + BoardLayout.FRAME_MARGIN * 0.5
	var ez: float = size.y * 0.5 + BoardLayout.FRAME_MARGIN * 0.5
	match style:
		"garden":
			_frame_garden(kit, ex, ez, rng)
		"deck":
			_frame_deck(kit, ex, ez, frame_color)
		"causeway":
			_frame_causeway(kit, ex, ez)
		"rock":
			_frame_rock(kit, ex, ez, rng, frame_color)
		"city":
			_frame_city(kit, ex, ez)
		"village":
			_frame_village(kit, glow, ex, ez, frame_color)
		_:
			_frame_sand(kit, ex, ez, rng, frame_color)


## Puntos a lo largo del rectángulo del marco, separados unos "step" metros.
static func _perimeter(ex: float, ez: float, step: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var nx: int = maxi(2, roundi(2.0 * ex / step))
	var nz: int = maxi(2, roundi(2.0 * ez / step))
	for i in nx:
		var x: float = -ex + 2.0 * ex * float(i) / float(nx)
		points.append(Vector2(x, -ez))
		points.append(Vector2(-x, ez))
	for j in nz:
		var z: float = -ez + 2.0 * ez * float(j) / float(nz)
		points.append(Vector2(ex, z))
		points.append(Vector2(-ex, -z))
	return points


## Cuatro paredes bajas (una por lado) que rodean el tablero.
static func _low_walls(kit: MeshKit, ex: float, ez: float, height: float, thickness: float, color: Color,
		top: Color) -> void:
	var half_h: float = height * 0.5
	kit.box(Vector3(0.0, half_h, -ez), Vector3(2.0 * ex + thickness, height, thickness), color, top)
	kit.box(Vector3(0.0, half_h, ez), Vector3(2.0 * ex + thickness, height, thickness), color, top)
	kit.box(Vector3(-ex, half_h, 0.0), Vector3(thickness, height, 2.0 * ez - thickness), color, top)
	kit.box(Vector3(ex, half_h, 0.0), Vector3(thickness, height, 2.0 * ez - thickness), color, top)


## Almenas pequeñas sobre una pared baja entre dos puntos del suelo.
static func _merlons(kit: MeshKit, from: Vector2, to: Vector2, base_y: float, size: float, color: Color) -> void:
	var delta: Vector2 = to - from
	var length: float = delta.length()
	var count: int = maxi(2, roundi(length / (size * 2.0)))
	for i in count:
		var t: float = (float(i) + 0.5) / float(count)
		var spot: Vector2 = from + delta * t
		kit.box(Vector3(spot.x, base_y + size * 0.5, spot.y), Vector3(size, size, size), color)


static func _frame_garden(kit: MeshKit, ex: float, ez: float, rng: RandomNumberGenerator) -> void:
	var petals: Array[Color] = [Color(0.98, 0.95, 0.85), Color(0.98, 0.82, 0.30), Color(0.95, 0.55, 0.65),
			Color(0.95, 0.40, 0.35)]
	for p in _perimeter(ex, ez, 0.55):
		var leaf: Color = MeshKit.vary_color(Color(0.22, 0.48, 0.22), 0.08, rng)
		kit.sphere(Vector3(p.x, 0.1, p.y), Vector3(0.27, 0.2, 0.27), leaf, 6, 4, 0.14, rng)
		if rng.randf() < 0.18:
			PropKit.flower(kit, Vector3(p.x, 0.26, p.y), petals[rng.randi() % petals.size()], 1.0)


static func _frame_deck(kit: MeshKit, ex: float, ez: float, frame_color: Color) -> void:
	var wood: Color = frame_color.lightened(0.05)
	_low_walls(kit, ex, ez, 0.22, 0.16, wood.darkened(0.1), wood)
	for p in _perimeter(ex, ez, 1.8):
		kit.cylinder(Vector3(p.x, 0.0, p.y), 0.07, 0.06, 0.55, 6, wood.darkened(0.15), true, false, wood)
	for corner in [Vector2(-ex, -ez), Vector2(ex, -ez), Vector2(-ex, ez), Vector2(ex, ez)]:
		kit.sphere(Vector3(corner.x, 0.58, corner.y), Vector3(0.09, 0.09, 0.09), wood.lightened(0.1), 6, 4)


static func _frame_causeway(kit: MeshKit, ex: float, ez: float) -> void:
	var stone := Color(0.86, 0.72, 0.46)
	var gold := Color(0.92, 0.74, 0.28)
	_low_walls(kit, ex, ez, 0.26, 0.2, stone.darkened(0.12), stone)
	_low_walls(kit, ex, ez, 0.275, 0.1, gold, gold)
	for corner in [Vector2(-ex, -ez), Vector2(ex, -ez), Vector2(-ex, ez), Vector2(ex, ez)]:
		kit.box(Vector3(corner.x, 0.35, corner.y), Vector3(0.36, 0.7, 0.36), stone.darkened(0.08), stone)
		kit.box(Vector3(corner.x, 0.735, corner.y), Vector3(0.42, 0.07, 0.42), gold)


static func _frame_sand(kit: MeshKit, ex: float, ez: float, rng: RandomNumberGenerator, frame_color: Color) -> void:
	for p in _perimeter(ex, ez, 2.4):
		PropKit.rock(kit, rng, Vector3(p.x, -0.05, p.y), rng.randf_range(0.14, 0.22), frame_color.lightened(0.22))


static func _frame_rock(kit: MeshKit, ex: float, ez: float, rng: RandomNumberGenerator, frame_color: Color) -> void:
	for p in _perimeter(ex, ez, 0.8):
		PropKit.rock(kit, rng, Vector3(p.x, -0.05, p.y), rng.randf_range(0.22, 0.36), frame_color.lightened(0.2))


static func _frame_city(kit: MeshKit, ex: float, ez: float) -> void:
	var wall := Color(0.86, 0.80, 0.66)
	_low_walls(kit, ex, ez, 0.3, 0.3, wall.darkened(0.06), wall.lightened(0.04))
	_merlons(kit, Vector2(-ex, -ez), Vector2(ex, -ez), 0.3, 0.14, wall.darkened(0.03))
	_merlons(kit, Vector2(-ex, ez), Vector2(ex, ez), 0.3, 0.14, wall.darkened(0.03))
	_merlons(kit, Vector2(-ex, -ez), Vector2(-ex, ez), 0.3, 0.14, wall.darkened(0.03))
	_merlons(kit, Vector2(ex, -ez), Vector2(ex, ez), 0.3, 0.14, wall.darkened(0.03))
	for corner in [Vector2(-ex, -ez), Vector2(ex, -ez), Vector2(-ex, ez), Vector2(ex, ez)]:
		PropKit.tower(kit, Vector3(corner.x, 0.0, corner.y), 0.3, 0.9, wall.lightened(0.03))


## Cerca de madera con dos travesaños y un farol en cada esquina.
static func _frame_village(kit: MeshKit, glow: MeshKit, ex: float, ez: float, frame_color: Color) -> void:
	var wood: Color = frame_color.lightened(0.22)
	for p in _perimeter(ex, ez, 1.2):
		kit.cylinder(Vector3(p.x, 0.0, p.y), 0.05, 0.045, 0.55, 5, wood.darkened(0.1), true, false, wood)
	var a := Vector3(-ex, 0.0, -ez)
	var b := Vector3(ex, 0.0, -ez)
	var c := Vector3(ex, 0.0, ez)
	var d := Vector3(-ex, 0.0, ez)
	for level in [0.2, 0.4]:
		var y: float = float(level)
		kit.beam(a + Vector3(0.0, y, 0.0), b + Vector3(0.0, y, 0.0), 0.05, 0.05, wood)
		kit.beam(b + Vector3(0.0, y, 0.0), c + Vector3(0.0, y, 0.0), 0.05, 0.05, wood)
		kit.beam(c + Vector3(0.0, y, 0.0), d + Vector3(0.0, y, 0.0), 0.05, 0.05, wood)
		kit.beam(d + Vector3(0.0, y, 0.0), a + Vector3(0.0, y, 0.0), 0.05, 0.05, wood)
	for corner in [a, b, c, d]:
		PropKit.lantern_post(kit, corner, 0.85, glow)
