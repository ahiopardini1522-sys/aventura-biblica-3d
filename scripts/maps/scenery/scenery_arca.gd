class_name SceneryArca
extends RefCounted
## Escenario del Arca de Noé (Génesis 6-8): el tablero está sobre la cubierta de una gran arca de
## madera, con su cabina, barandillas, animales de dos en dos, heno y barriles. Alrededor hay
## un mar con olas, las montañas nevadas del Ararat al fondo, un arcoíris, nubes y palomas.

const WATER_Y := -3.6
const DECK_Y := -0.3
const HULL_BOTTOM := -7.5
const WOOD := Color(0.58, 0.40, 0.22)
const DARK := Color(0.20, 0.12, 0.06)


## Contorno de la cubierta visto desde arriba (x, z): popa cuadrada a la izquierda y proa a la derecha.
static func hull_outline() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-19.0, -8.5), Vector2(-6.0, -10.0), Vector2(8.0, -9.4),
			Vector2(17.0, -7.6), Vector2(24.0, -3.4), Vector2(26.0, 0.0), Vector2(24.0, 3.4),
			Vector2(17.0, 7.6), Vector2(8.0, 9.4), Vector2(-6.0, 10.0), Vector2(-19.0, 8.5)])


static func build(root: Node3D, seed_value: int, quality: int, _ground: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	_add_sea(root)
	_add_hull(root)
	_add_animals(root, rng, quality)
	_add_mountains(root, rng)
	_add_rainbow(root)

	FxKit.birds(root, rng, 2 if quality <= 0 else 3, Vector3(4.0, 0.0, 0.0), 15.0, 10.0, Color(0.99, 0.99, 0.96))
	FxKit.clouds(root, rng, 6 if quality <= 0 else 9, 38.0, 56.0, 150.0, Color(0.93, 0.95, 1.0, 0.9))
	FxKit.floaters(root, "Bruma", Vector3(0.0, -2.2, 0.0), Vector3(42.0, 0.9, 42.0),
			int(22.0 * SceneryKit.density(quality)), 6.0, Color(1.0, 1.0, 1.0, 0.14), 0.02, 10.0)


static func _add_sea(root: Node3D) -> void:
	var kit := MeshKit.new()
	kit.disc(Vector3(0.0, WATER_Y, 0.0), 260.0, Color.WHITE, 48)
	var sea: MeshInstance3D = kit.instance(WaterKit.water_material(Color(0.07, 0.27, 0.44, 0.94),
			Color(0.25, 0.56, 0.70, 0.88), 0.32, 0.5, 0.0), "Sea")
	root.add_child(sea)


static func _add_hull(root: Node3D) -> void:
	var kit := MeshKit.new()
	kit.uv_scale = 0.45
	kit.side_uv_swap = true
	var hull: PackedVector2Array = hull_outline()
	kit.extrude(hull, HULL_BOTTOM, DECK_Y, WOOD, Color(0.66, 0.48, 0.28))
	# Franja oscura (brea) a la altura del agua: el mismo contorno, algo más grande.
	var band := PackedVector2Array()
	for point in hull:
		band.append(Vector2(3.0 + (point.x - 3.0) * 1.012, point.y * 1.03))
	kit.extrude(band, WATER_Y - 1.0, WATER_Y + 0.3, Color(0.24, 0.15, 0.08))
	_add_rails(kit, hull)
	_add_cabin(kit)
	var node: MeshInstance3D = kit.instance(TextureKit.material("planks", 0.9), "Ark")
	root.add_child(node)


## Barandilla de postes y vigas alrededor de la cubierta (más baja por delante, para no tapar el tablero).
static func _add_rails(kit: MeshKit, hull: PackedVector2Array) -> void:
	var rail_color := Color(0.50, 0.33, 0.18)
	var inset: Array[Vector2] = []
	for point in hull:
		inset.append(Vector2(3.0 + (point.x - 3.0) * 0.985, point.y * 0.972))
	var count: int = inset.size()
	for i in count:
		var a: Vector2 = inset[i]
		var b: Vector2 = inset[(i + 1) % count]
		var middle: Vector2 = (a + b) * 0.5
		var height: float = 0.95
		if middle.y > 4.0:
			height = 0.5
		var pieces: int = maxi(1, int(a.distance_to(b) / 1.8))
		for j in pieces:
			var from: Vector2 = a.lerp(b, float(j) / float(pieces))
			var to: Vector2 = a.lerp(b, float(j + 1) / float(pieces))
			kit.box(Vector3(from.x, DECK_Y + height * 0.5, from.y), Vector3(0.14, height, 0.14), rail_color)
			kit.beam(Vector3(from.x, DECK_Y + height, from.y), Vector3(to.x, DECK_Y + height, to.y), 0.1, 0.08, rail_color)


## Cabina del arca a popa: paredes de madera, tejado a dos aguas, puerta y ventanas.
static func _add_cabin(kit: MeshKit) -> void:
	var wall := Color(0.60, 0.42, 0.24)
	kit.box(Vector3(-14.0, DECK_Y + 2.1, 0.0), Vector3(6.4, 4.2, 12.4), wall, wall.lightened(0.05))
	kit.place(Vector3(-14.0, DECK_Y + 4.2, 0.0), PI * 0.5)
	kit.gable(Vector3.ZERO, Vector3(13.4, 2.4, 7.4), Color(0.38, 0.25, 0.15), wall.darkened(0.1))
	kit.pop()
	kit.box(Vector3(-10.78, DECK_Y + 1.1, 0.0), Vector3(0.08, 2.2, 1.5), DARK)
	for z in [-3.6, 3.6]:
		kit.box(Vector3(-10.78, DECK_Y + 2.7, float(z)), Vector3(0.08, 0.9, 0.9), DARK)
	for x in [-16.2, -11.8]:
		kit.box(Vector3(float(x), DECK_Y + 2.7, 6.23), Vector3(0.9, 0.9, 0.08), DARK)
		kit.box(Vector3(float(x), DECK_Y + 2.7, -6.23), Vector3(0.9, 0.9, 0.08), DARK)


## Animales de dos en dos, heno, barriles y cajas sobre la cubierta; palomas en la barandilla y el tejado.
static func _add_animals(root: Node3D, rng: RandomNumberGenerator, quality: int) -> void:
	var kit := MeshKit.new()
	var y: float = DECK_Y
	var face_board: float = -PI * 0.5
	var pairs: Array = [
		["elefante", Vector3(15.0, y, -4.6), face_board, 1.0],
		["elefante", Vector3(17.6, y, -3.4), face_board + 0.3, 0.9],
		["jirafa", Vector3(20.5, y, 2.0), face_board, 1.0],
		["jirafa", Vector3(21.6, y, 4.6), face_board - 0.3, 0.9],
		["cebra", Vector3(13.4, y, -1.2), face_board + 0.2, 1.0],
		["cebra", Vector3(13.2, y, 1.5), face_board - 0.2, 1.0],
		["leon", Vector3(13.8, y, 5.4), face_board + 0.5, 1.0],
		["leon", Vector3(15.6, y, 6.0), face_board + 0.9, 0.95],
		["buey", Vector3(-8.4, y, -3.4), PI * 0.5, 1.0],
		["buey", Vector3(-8.6, y, 3.2), PI * 0.5 + 0.2, 1.0],
		["oveja", Vector3(-3.6, y, -8.0), 0.2, 1.0],
		["oveja", Vector3(-2.2, y, -8.2), -0.3, 1.0],
		["oveja", Vector3(3.0, y, -8.0), 0.5, 1.0],
		["oveja", Vector3(4.4, y, -7.8), 0.0, 1.0],
		["burro", Vector3(-7.6, y, 7.6), PI * 0.5, 1.0],
		["burro", Vector3(-6.4, y, 8.2), PI * 0.4, 0.95],
	]
	var limit: int = pairs.size() if quality > 0 else pairs.size() - 4
	for i in limit:
		var entry: Array = pairs[i]
		AnimalKit.make(kit, rng, str(entry[0]), entry[1], float(entry[2]), float(entry[3]) * rng.randf_range(0.95, 1.05))

	for bale in [Vector3(18.8, y, -1.4), Vector3(19.9, y, -1.0), Vector3(19.2, y + 0.5, -1.2)]:
		PropKit.hay_bale(kit, bale, rng.randf_range(-0.3, 0.3), Color(0.86, 0.74, 0.38))
	for barrel in [Vector3(-10.0, y, 8.0), Vector3(-9.2, y, 8.3), Vector3(22.0, y, -2.0)]:
		PropKit.barrel(kit, barrel, 0.34, 0.8, Color(0.55, 0.38, 0.20))
	PropKit.crate(kit, Vector3(-10.1, y, -7.8), 0.8, Color(0.62, 0.45, 0.26))
	PropKit.crate(kit, Vector3(-9.2, y, -8.0), 0.65, Color(0.58, 0.41, 0.24))
	PropKit.crate(kit, Vector3(-9.8, y + 0.8, -7.9), 0.55, Color(0.66, 0.48, 0.28))

	for perch in [Vector3(-14.0, y + 6.6, -2.0), Vector3(-14.0, y + 6.6, 2.6), Vector3(-9.8, y + 1.35, -7.9),
			Vector3(-9.2, y + 0.8, 8.3)]:
		AnimalKit.dove(kit, perch, rng.randf_range(0.0, TAU), 1.0)
	root.add_child(kit.instance(TextureKit.plain(0.9), "Animals"))


## Las montañas nevadas del Ararat al fondo, saliendo del mar.
static func _add_mountains(root: Node3D, rng: RandomNumberGenerator) -> void:
	var kit := MeshKit.new()
	var rock := Color(0.52, 0.46, 0.42)
	var snow := Color(0.96, 0.97, 1.0)
	var peaks: Array = [
		[Vector3(-10.0, WATER_Y, -130.0), 70.0, 56.0], [Vector3(48.0, WATER_Y, -118.0), 50.0, 36.0],
		[Vector3(-62.0, WATER_Y, -108.0), 48.0, 31.0], [Vector3(100.0, WATER_Y, -150.0), 55.0, 30.0],
		[Vector3(-110.0, WATER_Y, -150.0), 58.0, 34.0], [Vector3(140.0, WATER_Y, -40.0), 46.0, 24.0],
		[Vector3(-150.0, WATER_Y, -30.0), 44.0, 22.0],
	]
	for entry in peaks:
		var base: Vector3 = entry[0]
		var radius: float = float(entry[1])
		var height: float = float(entry[2])
		kit.cylinder(base, radius, 0.0, height, 8, MeshKit.vary_color(rock, 0.03, rng))
		var cap_start: float = 0.6
		kit.cylinder(base + Vector3(0.0, height * cap_start, 0.0), radius * (1.0 - cap_start) + 0.4, 0.0,
				height * (1.0 - cap_start), 8, snow)
	root.add_child(kit.instance(TextureKit.plain(1.0), "Ararat"))


## Arcoíris de seis franjas detrás de las montañas (el pacto de Dios, Génesis 9:13).
static func _add_rainbow(root: Node3D) -> void:
	var kit := MeshKit.new()
	var colors: Array[Color] = [Color(0.95, 0.25, 0.25, 0.55), Color(0.98, 0.60, 0.20, 0.55),
			Color(0.98, 0.90, 0.30, 0.55), Color(0.40, 0.80, 0.35, 0.55), Color(0.30, 0.55, 0.95, 0.55),
			Color(0.60, 0.40, 0.85, 0.55)]
	for k in colors.size():
		var radius: float = 70.0 - float(k) * 2.9
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 25:
			var angle: float = PI * float(i) / 24.0
			points.append(Vector3(20.0 + cos(angle) * radius, -4.0 + sin(angle) * radius, -100.0))
			radii.append(1.5)
		kit.tube(points, radii, colors[k], 6)
	root.add_child(kit.instance(TextureKit.glow_vertex(false), "Rainbow"))
