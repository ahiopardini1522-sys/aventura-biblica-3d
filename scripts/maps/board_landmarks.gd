class_name BoardLandmarks
extends RefCounted
## La puerta de salida y la puerta de llegada de cada tablero, con el aspecto de su escenario:
##   garden   arco de flores / Árbol de la Vida con fruto dorado
##   deck     pasarela del barco con cuerdas / arcoíris con la paloma
##   causeway pilonos de arenisca / obeliscos con el disco solar alado
##   rock     mojón de piedras con bandera / pilares de roca con las tablas de la Ley y un haz de luz
##   city     puerta de la ciudad con torres / pórtico del Templo con frontón dorado
##   village  faroles con un estandarte / el establo con la estrella de Belén
##   sand     asta con bandera / puerta dorada con una esfera de luz
## Cada función agrega piezas a "kit" (con luz) y a "glow" (brillos, sin luz) y devuelve la altura
## a la que va el rótulo ("INICIO" o "META"). La salida se coloca justo a la izquierda de la
## casilla 1 (+x hacia el tablero, +z hacia la cámara); la meta, sobre el centro de su casilla.

const GOLD := Color(0.92, 0.74, 0.28)
const TIMBER := Color(0.42, 0.28, 0.16)
const LIGHT_ORB := Color(1.0, 0.86, 0.45, 0.95)


static func add_start(kit: MeshKit, glow: MeshKit, style: String, rng: RandomNumberGenerator, accent: Color) -> float:
	match style:
		"garden":
			return _start_garden(kit)
		"deck":
			return _start_deck(kit, accent)
		"causeway":
			return _start_causeway(kit)
		"rock":
			return _start_rock(kit, rng, accent)
		"city":
			return _start_city(kit)
		"village":
			return _start_village(kit, glow)
	return _start_sand(kit, accent)


static func add_goal(kit: MeshKit, glow: MeshKit, style: String, rng: RandomNumberGenerator, accent: Color) -> float:
	match style:
		"garden":
			return _goal_garden(kit, glow, rng)
		"deck":
			return _goal_deck(kit)
		"causeway":
			return _goal_causeway(kit, glow)
		"rock":
			return _goal_rock(kit, glow, rng)
		"city":
			return _goal_city(kit, glow)
		"village":
			return _goal_village(kit, glow)
	return _goal_sand(kit, glow, accent)


## Arco de media circunferencia en un plano vertical que corta el eje X. Va de z = -radius a z = +radius.
static func _arch_points(center_y: float, radius: float, rise: float, steps: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in steps + 1:
		var angle: float = PI * float(i) / float(steps)
		points.append(Vector3(0.0, center_y + sin(angle) * rise, -cos(angle) * radius))
	return points


static func _same_radius(count: int, radius: float) -> PackedFloat32Array:
	var radii := PackedFloat32Array()
	for i in count:
		radii.append(radius)
	return radii


# ---------------------------------------------------------------- Salidas

static func _start_garden(kit: MeshKit) -> float:
	var leaf := Color(0.26, 0.55, 0.26)
	for side in [-1.0, 1.0]:
		kit.cylinder(Vector3(0.0, 0.0, float(side) * 0.5), 0.06, 0.05, 1.35, 6, TIMBER, false)
	var arch: PackedVector3Array = _arch_points(1.3, 0.5, 0.42, 8)
	kit.tube(arch, _same_radius(arch.size(), 0.07), leaf, 5)
	var petals: Array[Color] = [Color(0.98, 0.95, 0.85), Color(0.98, 0.82, 0.30), Color(0.95, 0.55, 0.65),
			Color(0.95, 0.40, 0.35)]
	for i in 7:
		var angle: float = PI * float(i + 1) / 8.0
		kit.sphere(Vector3(0.0, 1.3 + sin(angle) * 0.42 + 0.05, -cos(angle) * 0.5), Vector3(0.07, 0.07, 0.07),
				petals[i % petals.size()], 5, 3)
	return 2.25


static func _start_deck(kit: MeshKit, flag: Color) -> float:
	var wood := Color(0.55, 0.38, 0.20)
	kit.beam(Vector3(-0.95, -0.12, 0.0), Vector3(0.18, 0.1, 0.0), 0.85, 0.07, wood)
	for i in 4:
		kit.box(Vector3(-0.7 + 0.25 * float(i), -0.02 + 0.045 * float(i), 0.0), Vector3(0.05, 0.05, 0.9), wood.darkened(0.25))
	for side in [-1.0, 1.0]:
		kit.cylinder(Vector3(-0.1, 0.05, float(side) * 0.42), 0.05, 0.045, 0.75, 6, wood.darkened(0.2), false)
	var rope := PackedVector3Array()
	for i in 7:
		var t: float = float(i) / 6.0
		rope.append(Vector3(-0.1, 0.78 - 0.14 * sin(PI * t), -0.42 + 0.84 * t))
	kit.tube(rope, _same_radius(rope.size(), 0.018), Color(0.82, 0.72, 0.48), 4)
	kit.cylinder(Vector3(-0.1, 0.05, 0.42), 0.03, 0.025, 1.5, 5, wood.darkened(0.3), false)
	kit.box(Vector3(-0.1, 1.38, 0.2), Vector3(0.03, 0.26, 0.4), flag)
	return 2.0


static func _start_causeway(kit: MeshKit) -> float:
	var stone := Color(0.86, 0.72, 0.46)
	for side in [-1.0, 1.0]:
		var z: float = float(side) * 0.55
		kit.frustum(Vector3(0.0, 0.0, z), 0.26, 0.19, 1.25, stone, stone.lightened(0.05))
		kit.box(Vector3(0.0, 1.29, z), Vector3(0.44, 0.08, 0.44), GOLD)
	kit.box(Vector3(0.0, 1.1, 0.0), Vector3(0.3, 0.2, 0.9), stone.lightened(0.04))
	kit.box(Vector3(0.0, 1.22, 0.0), Vector3(0.32, 0.04, 0.92), GOLD)
	kit.sphere(Vector3(0.0, 1.5, 0.0), Vector3(0.05, 0.2, 0.2), GOLD, 8, 4)
	return 2.1


static func _start_rock(kit: MeshKit, rng: RandomNumberGenerator, flag: Color) -> float:
	var stone := Color(0.60, 0.55, 0.50)
	var heights: Array[float] = [0.16, 0.42, 0.65, 0.84]
	var sizes: Array[float] = [0.4, 0.32, 0.25, 0.18]
	for i in 4:
		kit.sphere(Vector3(rng.randf_range(-0.04, 0.04), heights[i], rng.randf_range(-0.04, 0.04)),
				Vector3(sizes[i], sizes[i] * 0.62, sizes[i] * 0.95), MeshKit.vary_color(stone, 0.06, rng), 6, 3, 0.12, rng)
	kit.cylinder(Vector3(0.0, 0.9, 0.0), 0.03, 0.025, 1.0, 5, TIMBER, false)
	kit.box(Vector3(0.0, 1.7, 0.2), Vector3(0.03, 0.26, 0.4), flag)
	return 2.25


static func _start_city(kit: MeshKit) -> float:
	var wall := Color(0.86, 0.80, 0.66)
	for side in [-1.0, 1.0]:
		PropKit.tower(kit, Vector3(0.0, 0.0, float(side) * 0.58), 0.27, 1.45, wall)
	kit.box(Vector3(0.0, 1.2, 0.0), Vector3(0.32, 0.3, 0.95), wall.lightened(0.04))
	kit.box(Vector3(0.0, 1.38, 0.0), Vector3(0.34, 0.06, 0.97), GOLD)
	return 2.35


static func _start_village(kit: MeshKit, glow: MeshKit) -> float:
	for side in [-1.0, 1.0]:
		PropKit.lantern_post(kit, Vector3(0.0, 0.0, float(side) * 0.5), 1.5, glow)
	kit.box(Vector3(0.0, 1.45, 0.0), Vector3(0.1, 0.1, 1.1), TIMBER)
	kit.box(Vector3(0.0, 1.1, 0.0), Vector3(0.03, 0.55, 0.7), Color(0.55, 0.2, 0.2))
	return 2.2


static func _start_sand(kit: MeshKit, flag: Color) -> float:
	kit.cylinder(Vector3.ZERO, 0.05, 0.04, 2.1, 8, Color(0.85, 0.82, 0.74), false)
	kit.box(Vector3(0.0, 1.85, 0.33), Vector3(0.04, 0.34, 0.62), flag)
	return 2.5


# ---------------------------------------------------------------- Metas

static func _goal_garden(kit: MeshKit, glow: MeshKit, rng: RandomNumberGenerator) -> float:
	var leaf := Color(0.24, 0.56, 0.26)
	for side in [-1.0, 1.0]:
		var x: float = float(side) * 0.42
		kit.cylinder(Vector3(x, 0.0, 0.0), 0.11, 0.07, 1.5, 6, TIMBER, false)
		kit.sphere(Vector3(x, 1.75, 0.0), Vector3(0.36, 0.3, 0.36), MeshKit.vary_color(leaf, 0.08, rng), 7, 4, 0.12, rng)
	for i in 5:
		kit.sphere(Vector3(-0.28 + 0.14 * float(i), 1.62, 0.0), Vector3(0.14, 0.1, 0.14), leaf, 5, 3)
	var fruits: Array[Vector3] = [Vector3(-0.5, 1.9, 0.25), Vector3(0.45, 1.85, 0.2), Vector3(-0.38, 1.6, 0.3),
			Vector3(0.5, 1.6, -0.2)]
	for fruit in fruits:
		kit.sphere(fruit, Vector3(0.06, 0.06, 0.06), Color(0.98, 0.78, 0.2), 5, 3)
	glow.sphere(Vector3(0.0, 2.0, 0.0), Vector3(0.17, 0.17, 0.17), LIGHT_ORB, 10, 6)
	return 2.7


static func _goal_deck(kit: MeshKit) -> float:
	var wood := Color(0.45, 0.30, 0.16)
	for side in [-1.0, 1.0]:
		kit.cylinder(Vector3(float(side) * 0.42, 0.0, 0.0), 0.07, 0.06, 1.5, 6, wood, false)
	var bands: Array[Color] = [Color(0.90, 0.25, 0.22), Color(0.96, 0.58, 0.20), Color(0.98, 0.84, 0.25),
			Color(0.36, 0.70, 0.32), Color(0.28, 0.52, 0.86), Color(0.58, 0.40, 0.78)]
	for k in 6:
		var radius: float = 0.46 - 0.04 * float(k)
		var points := PackedVector3Array()
		for i in 9:
			var angle: float = PI * float(i) / 8.0
			points.append(Vector3(cos(angle) * radius, 1.5 + sin(angle) * radius, 0.0))
		kit.tube(points, _same_radius(points.size(), 0.022), bands[k], 4)
	AnimalKit.dove(kit, Vector3(0.0, 2.08, 0.0), 0.0, 0.7)
	return 2.75


static func _goal_causeway(kit: MeshKit, glow: MeshKit) -> float:
	var stone := Color(0.86, 0.72, 0.46)
	for side in [-1.0, 1.0]:
		var x: float = float(side) * 0.42
		kit.frustum(Vector3(x, 0.0, 0.0), 0.12, 0.075, 1.4, stone, stone.lightened(0.05))
		kit.pyramid(Vector3(x, 1.4, 0.0), 0.075, 0.14, GOLD)
		kit.box(Vector3(float(side) * 0.3, 1.85, 0.0), Vector3(0.26, 0.05, 0.04), GOLD)
	kit.box(Vector3(0.0, 1.52, 0.0), Vector3(1.0, 0.14, 0.2), stone.lightened(0.04))
	kit.box(Vector3(0.0, 1.61, 0.0), Vector3(1.02, 0.03, 0.22), GOLD)
	kit.sphere(Vector3(0.0, 1.85, 0.0), Vector3(0.18, 0.18, 0.04), GOLD, 10, 6)
	glow.sphere(Vector3(0.0, 1.85, 0.08), Vector3(0.24, 0.24, 0.1), Color(1.0, 0.85, 0.4, 0.5), 10, 5)
	return 2.55


static func _goal_rock(kit: MeshKit, glow: MeshKit, rng: RandomNumberGenerator) -> float:
	var stone := Color(0.60, 0.55, 0.50)
	var tablet := Color(0.88, 0.85, 0.78)
	for side in [-1.0, 1.0]:
		var x: float = float(side) * 0.42
		var heights: Array[float] = [0.25, 0.62, 0.98, 1.3]
		var sizes: Array[float] = [0.26, 0.22, 0.18, 0.15]
		for i in 4:
			kit.sphere(Vector3(x, heights[i], 0.0), Vector3(sizes[i], sizes[i] * 1.2, sizes[i]),
					MeshKit.vary_color(stone, 0.06, rng), 6, 4, 0.15, rng)
		kit.box(Vector3(float(side) * 0.18, 1.72, 0.0), Vector3(0.3, 0.5, 0.07), tablet)
		kit.sphere(Vector3(float(side) * 0.18, 1.97, 0.0), Vector3(0.15, 0.1, 0.035), tablet, 6, 3)
	kit.box(Vector3(0.0, 1.4, 0.0), Vector3(0.9, 0.12, 0.2), stone.darkened(0.1))
	glow.cylinder(Vector3(0.0, 1.45, 0.0), 0.36, 0.12, 1.3, 8, Color(1.0, 0.92, 0.55, 0.2), false)
	glow.sphere(Vector3(0.0, 1.8, 0.08), Vector3(0.2, 0.2, 0.1), Color(1.0, 0.9, 0.5, 0.45), 8, 5)
	return 3.1


static func _goal_city(kit: MeshKit, glow: MeshKit) -> float:
	var marble := Color(0.95, 0.92, 0.84)
	for side in [-1.0, 1.0]:
		PropKit.column(kit, Vector3(float(side) * 0.42, 0.0, 0.0), 0.085, 1.5, marble, marble.lightened(0.04))
	kit.box(Vector3(0.0, 1.57, 0.0), Vector3(1.1, 0.14, 0.22), marble)
	kit.gable(Vector3(0.0, 1.64, 0.0), Vector3(1.2, 0.36, 0.3), GOLD, GOLD.darkened(0.08))
	glow.sphere(Vector3(0.0, 2.2, 0.0), Vector3(0.14, 0.14, 0.14), LIGHT_ORB, 10, 6)
	return 2.85


static func _goal_village(kit: MeshKit, glow: MeshKit) -> float:
	var straw := Color(0.80, 0.68, 0.34)
	for sx in [-0.5, 0.5]:
		for sz in [-0.35, 0.35]:
			kit.cylinder(Vector3(float(sx), 0.0, float(sz)), 0.05, 0.045, 1.35, 5, TIMBER, false)
	kit.gable(Vector3(0.0, 1.3, 0.0), Vector3(1.4, 0.45, 0.95), straw, straw.darkened(0.08))
	var star := Color(1.0, 0.93, 0.55, 1.0)
	glow.star(Vector3(0.0, 2.25, 0.0), 0.3, 0.12, star)
	glow.place(Vector3(0.0, 2.25, 0.0), PI * 0.5)
	glow.star(Vector3.ZERO, 0.3, 0.12, star)
	glow.pop()
	glow.sphere(Vector3(0.0, 2.25, 0.0), Vector3(0.28, 0.28, 0.28), Color(1.0, 0.95, 0.6, 0.35), 8, 5)
	return 3.0


static func _goal_sand(kit: MeshKit, glow: MeshKit, gold: Color) -> float:
	for side in [-1.0, 1.0]:
		kit.cylinder(Vector3(float(side) * 0.42, 0.0, 0.0), 0.1, 0.08, 1.5, 10, gold, true)
	kit.box(Vector3(0.0, 1.58, 0.0), Vector3(1.1, 0.16, 0.2), gold)
	glow.sphere(Vector3(0.0, 1.92, 0.0), Vector3(0.17, 0.17, 0.17), LIGHT_ORB, 12, 6)
	return 2.5
