class_name WorldIcons
extends RefCounted
## Iconos 3D de las siete regiones del mundo bíblico y las figuras de estado (candado, estrella,
## aros de luz, flecha). Cada icono se construye en un MeshKit con la base en y = 0 y centrado en
## (0, 0); lo que brilla (ventanas, llamas, rayos de luz) va en un segundo MeshKit "glow" que se
## dibuja con mezcla aditiva y sin luz.
##
##   tree     Jardín del Edén   el árbol de la vida con frutos dorados
##   ark      Arca de Noé       el arca con su cabina, una jirafa, palomas y un arcoíris
##   pyramid  Egipto            tres pirámides con la punta dorada y un obelisco
##   tent     Desierto del Sinaí campamento de tiendas, fogata y la roca con agua
##   mountain Monte Sinaí       el monte con nubes, luz celestial y las tablas de la ley
##   temple   Jerusalén         el templo con columnas de bronce, cúpula dorada y muralla
##   stable   Belén             el establo con el pesebre iluminado y la estrella

const ICONS: Array[String] = ["tree", "ark", "pyramid", "tent", "mountain", "temple", "stable"]
const GOLD := Color(0.96, 0.77, 0.30)
const STONE := Color(0.90, 0.84, 0.70)
const WOOD := Color(0.52, 0.35, 0.20)
const STRAW := Color(0.86, 0.72, 0.38)


## Agrega el icono ("tree", "ark", ...) y devuelve su altura (hasta dónde llega por arriba).
## Un nombre desconocido no agrega nada y devuelve 4.0.
static func add_icon(kit: MeshKit, glow: MeshKit, icon: String, rng: RandomNumberGenerator) -> float:
	match icon:
		"tree":
			return _icon_tree(kit, glow, rng)
		"ark":
			return _icon_ark(kit, glow, rng)
		"pyramid":
			return _icon_pyramid(kit, glow, rng)
		"tent":
			return _icon_tent(kit, glow, rng)
		"mountain":
			return _icon_mountain(kit, glow, rng)
		"temple":
			return _icon_temple(kit, glow, rng)
		"stable":
			return _icon_stable(kit, glow, rng)
	return 4.0


## Vegetación y decorado alrededor del icono, dentro de la plataforma de la región (radio 8.5).
## "density" va de 0.55 (calidad baja) a 1.3 (alta).
static func add_decor(kit: MeshKit, glow: MeshKit, icon: String, rng: RandomNumberGenerator,
		density: float) -> void:
	match icon:
		"tree":
			_decor_tree(kit, rng, density)
		"ark":
			_decor_ark(kit, rng, density)
		"pyramid":
			_decor_pyramid(kit, rng, density)
		"tent":
			_decor_tent(kit, rng, density)
		"mountain":
			_decor_mountain(kit, rng, density)
		"temple":
			_decor_temple(kit, rng, density)
		"stable":
			_decor_stable(kit, glow, rng, density)


# ---------------------------------------------------------------- Iconos

static func _icon_tree(kit: MeshKit, glow: MeshKit, rng: RandomNumberGenerator) -> float:
	var bark := Color(0.46, 0.31, 0.18)
	kit.cylinder(Vector3.ZERO, 1.25, 0.75, 4.4, 8, bark, false)
	for i in 6:
		var angle: float = TAU * float(i) / 6.0 + 0.3
		kit.beam(Vector3(cos(angle) * 0.7, 0.5, sin(angle) * 0.7),
				Vector3(cos(angle) * 1.9, 0.0, sin(angle) * 1.9), 0.5, 0.45, bark.darkened(0.1))
	var leaf := Color(0.32, 0.66, 0.30)
	kit.sphere(Vector3(0.0, 6.4, 0.0), Vector3(3.9, 2.7, 3.9), leaf, 10, 5, 0.12, rng, PI, leaf.darkened(0.25))
	for i in 5:
		var angle: float = TAU * float(i) / 5.0
		var tint: Color = MeshKit.vary_color(leaf.lightened(0.05), 0.05, rng)
		kit.sphere(Vector3(cos(angle) * 2.6, 5.3 + rng.randf_range(-0.2, 0.5), sin(angle) * 2.6),
				Vector3(2.0, 1.5, 2.0), tint, 8, 4, 0.15, rng, PI, tint.darkened(0.2))
	for i in 10:
		var angle: float = rng.randf_range(0.0, TAU)
		var spread: float = rng.randf_range(1.6, 3.4)
		var fruit: Color = Color(0.98, 0.78, 0.25)
		if i % 2 == 1:
			fruit = Color(0.90, 0.25, 0.22)
		kit.sphere(Vector3(cos(angle) * spread, rng.randf_range(4.8, 6.9), sin(angle) * spread),
				Vector3(0.28, 0.28, 0.28), fruit, 5, 3)
	glow.sphere(Vector3(0.0, 6.4, 0.0), Vector3(4.8, 3.5, 4.8), Color(1.0, 0.95, 0.6, 0.13), 10, 5)
	return 9.6


static func _icon_ark(kit: MeshKit, glow: MeshKit, rng: RandomNumberGenerator) -> float:
	var dark := Color(0.30, 0.19, 0.10)
	var hull := PackedVector2Array([Vector2(-5.2, -2.2), Vector2(2.4, -2.5), Vector2(5.0, -1.2),
			Vector2(6.0, 0.0), Vector2(5.0, 1.2), Vector2(2.4, 2.5), Vector2(-5.2, 2.2)])
	var keel := PackedVector2Array()
	for point in hull:
		keel.append(Vector2(point.x * 0.78, point.y * 0.72))
	kit.extrude(keel, -0.9, 0.2, dark, dark)
	kit.extrude(hull, 0.2, 1.9, WOOD, WOOD.lightened(0.1))
	var wall := Color(0.62, 0.44, 0.26)
	kit.box(Vector3(-0.6, 3.1, 0.0), Vector3(6.0, 2.4, 3.4), wall, wall.lightened(0.05))
	kit.gable(Vector3(-0.6, 4.3, 0.0), Vector3(6.6, 1.7, 4.0), Color(0.38, 0.25, 0.15), wall.darkened(0.1))
	kit.box(Vector3(2.45, 2.8, 0.0), Vector3(0.06, 1.8, 1.0), dark)
	for x in [-2.4, 0.0, 1.6]:
		kit.box(Vector3(float(x), 3.4, 1.72), Vector3(0.8, 0.7, 0.06), dark)
		kit.box(Vector3(float(x), 3.4, -1.72), Vector3(0.8, 0.7, 0.06), dark)
	AnimalKit.make(kit, rng, "jirafa", Vector3(4.0, 1.9, -0.2), PI * 0.5, 0.75)
	AnimalKit.dove(kit, Vector3(-0.6, 6.0, 0.0), 0.4, 1.4)
	AnimalKit.dove(kit, Vector3(-5.2, 2.0, 0.0), -0.4, 1.2)
	# Arcoíris detrás del arca (Génesis 9:13).
	var colors: Array[Color] = [Color(0.95, 0.25, 0.25, 0.5), Color(0.98, 0.60, 0.20, 0.5),
			Color(0.98, 0.90, 0.30, 0.5), Color(0.40, 0.80, 0.35, 0.5), Color(0.30, 0.55, 0.95, 0.5),
			Color(0.60, 0.40, 0.85, 0.5)]
	for k in colors.size():
		var radius: float = 9.2 - float(k) * 0.4
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 13:
			var angle: float = PI * float(i) / 12.0
			points.append(Vector3(cos(angle) * radius, sin(angle) * radius - 0.6, -4.8))
			radii.append(0.22)
		glow.tube(points, radii, colors[k], 5)
	return 7.2


static func _icon_pyramid(kit: MeshKit, _glow: MeshKit, rng: RandomNumberGenerator) -> float:
	var sand := Color(0.88, 0.74, 0.46)
	var cap := Color(0.97, 0.80, 0.32)
	# Cada pirámide: (mitad del lado de la base, altura) y su posición (x, z).
	var sizes: Array[Vector2] = [Vector2(3.8, 5.4), Vector2(2.4, 3.4), Vector2(1.6, 2.2)]
	var at: Array[Vector2] = [Vector2(0.6, -0.8), Vector2(-4.4, 2.2), Vector2(3.8, 3.0)]
	for i in sizes.size():
		var half: float = sizes[i].x
		var height: float = sizes[i].y
		var base := Vector3(at[i].x, 0.0, at[i].y)
		kit.pyramid(base, half, height, MeshKit.vary_color(sand, 0.04, rng))
		kit.pyramid(base + Vector3(0.0, height * 0.84, 0.0), half * 0.19, height * 0.2, cap)
	kit.box(Vector3(1.0, 0.45, 3.2), Vector3(1.4, 0.9, 0.12), Color(0.20, 0.13, 0.08))
	PropKit.obelisk(kit, Vector3(5.4, 0.0, -3.4), 0.5, 4.2, sand.lightened(0.06), cap)
	return 6.4


static func _icon_tent(kit: MeshKit, glow: MeshKit, rng: RandomNumberGenerator) -> float:
	var cloth_a := Color(0.62, 0.40, 0.26)
	var cloth_b := Color(0.82, 0.62, 0.38)
	PropKit.tent(kit, Vector3(0.0, 0.0, -0.4), 0.3, 3.6, cloth_a)
	PropKit.tent(kit, Vector3(-5.0, 0.0, 2.2), -0.6, 2.4, cloth_b)
	PropKit.tent(kit, Vector3(4.8, 0.0, 2.8), 0.9, 2.6, cloth_b.darkened(0.08))
	kit.cylinder(Vector3(0.0, 4.1, -0.4), 0.07, 0.05, 1.3, 5, PropKit.DARK_WOOD)
	kit.box(Vector3(0.45, 5.15, -0.4), Vector3(0.8, 0.5, 0.05), Color(0.85, 0.25, 0.20))
	# Fogata con su llama.
	PropKit.torch(kit, Vector3(2.4, 0.0, 4.4), 0.9)
	glow.cone(Vector3(2.4, 1.15, 4.4), 0.32, 0.9, 5, Color(1.0, 0.62, 0.2, 0.9))
	glow.sphere(Vector3(2.4, 1.3, 4.4), Vector3(1.0, 0.8, 1.0), Color(1.0, 0.7, 0.3, 0.14), 8, 4)
	# La roca de Horeb con su charco de agua (Éxodo 17).
	PropKit.rock(kit, rng, Vector3(-5.2, 0.0, -4.0), 1.9, Color(0.58, 0.48, 0.38))
	kit.disc(Vector3(-3.6, 0.04, -3.0), 1.3, Color(0.30, 0.62, 0.86), 14)
	AnimalKit.make(kit, rng, "burro", Vector3(-2.4, 0.0, 4.6), 0.8, 1.3)
	return 5.6


static func _icon_mountain(kit: MeshKit, glow: MeshKit, _rng: RandomNumberGenerator) -> float:
	var rock := Color(0.55, 0.45, 0.36)
	var strata: Array[Color] = [rock, rock.lightened(0.08), rock.lightened(0.16)]
	kit.cylinder(Vector3.ZERO, 6.0, 3.6, 4.0, 7, strata[0], true, false, rock.darkened(0.05))
	kit.cylinder(Vector3(0.0, 4.0, 0.0), 3.6, 1.9, 3.4, 7, strata[1], true, false, rock, 0.4)
	kit.cylinder(Vector3(0.0, 7.4, 0.0), 1.9, 0.0, 3.0, 7, strata[2], false, false, Color(0.0, 0.0, 0.0, 0.0), 0.9)
	kit.cylinder(Vector3(-4.6, 0.0, 1.6), 3.0, 0.0, 5.6, 6, rock.darkened(0.1))
	kit.cylinder(Vector3(4.4, 0.0, 2.0), 2.6, 0.0, 4.6, 6, rock.lightened(0.04))
	# Las tablas de la ley en la cima.
	var tablet := Color(0.84, 0.82, 0.76)
	kit.box(Vector3(-0.42, 10.9, 0.0), Vector3(0.7, 1.0, 0.18), tablet)
	kit.box(Vector3(0.42, 10.9, 0.0), Vector3(0.7, 1.0, 0.18), tablet.darkened(0.04))
	kit.dome(Vector3(-0.42, 11.4, 0.0), 0.35, tablet, 8, 2, 0.8)
	kit.dome(Vector3(0.42, 11.4, 0.0), 0.35, tablet.darkened(0.04), 8, 2, 0.8)
	# Nubes alrededor de la ladera y luz celestial que baja de lo alto.
	glow.sphere(Vector3(0.0, 7.2, 0.0), Vector3(5.4, 0.7, 5.4), Color(1.0, 1.0, 1.0, 0.26), 12, 3)
	glow.sphere(Vector3(-2.0, 5.0, 3.0), Vector3(3.0, 0.5, 2.0), Color(1.0, 1.0, 1.0, 0.2), 8, 3)
	glow.cylinder(Vector3(0.0, 10.4, 0.0), 0.8, 0.25, 7.0, 8, Color(1.0, 0.9, 0.5, 0.2), false)
	glow.sphere(Vector3(0.0, 11.0, 0.0), Vector3(1.8, 1.8, 1.8), Color(1.0, 0.92, 0.55, 0.18), 8, 4)
	return 11.8


static func _icon_temple(kit: MeshKit, glow: MeshKit, _rng: RandomNumberGenerator) -> float:
	var bronze := Color(0.72, 0.50, 0.24)
	kit.box(Vector3(0.0, 0.35, 0.0), Vector3(11.0, 0.7, 8.0), STONE.darkened(0.08), STONE)
	kit.box(Vector3(0.0, 0.95, 0.0), Vector3(9.0, 0.5, 6.4), STONE, STONE.lightened(0.05))
	kit.box(Vector3(0.0, 2.7, -1.0), Vector3(7.0, 3.0, 4.8), STONE, STONE.lightened(0.04))
	kit.box(Vector3(0.0, 4.3, -1.0), Vector3(7.4, 0.25, 5.2), STONE.darkened(0.06))
	for i in 6:
		var x: float = -2.5 + float(i)
		PropKit.column(kit, Vector3(x, 1.2, 2.6), 0.32, 3.0, STONE)
	kit.box(Vector3(0.0, 4.4, 2.6), Vector3(6.4, 0.35, 1.2), STONE.darkened(0.04))
	kit.place(Vector3(0.0, 4.58, 2.6), PI * 0.5)
	kit.gable(Vector3.ZERO, Vector3(1.2, 1.1, 6.4), STONE, STONE.darkened(0.03))
	kit.pop()
	kit.box(Vector3(0.0, 2.2, 1.42), Vector3(1.4, 2.0, 0.06), PropKit.DOOR)
	kit.box(Vector3(0.0, 5.6, -2.2), Vector3(3.2, 2.4, 2.8), STONE, STONE.lightened(0.04))
	kit.dome(Vector3(0.0, 6.8, -2.2), 1.7, GOLD, 12, 4, 1.0)
	kit.cone(Vector3(0.0, 8.4, -2.2), 0.14, 1.3, 5, GOLD)
	for side in [-1.0, 1.0]:
		var x: float = float(side) * 4.0
		kit.cylinder(Vector3(x, 1.2, 3.6), 0.42, 0.36, 4.6, 8, bronze, false)
		kit.sphere(Vector3(x, 5.9, 3.6), Vector3(0.6, 0.35, 0.6), bronze.lightened(0.1), 6, 3)
	var wall := Color(0.84, 0.76, 0.60)
	PropKit.wall_run(kit, Vector3(-6.2, 0.0, -4.7), Vector3(6.2, 0.0, -4.7), 2.4, 0.6, wall)
	PropKit.tower(kit, Vector3(-6.2, 0.0, -4.7), 0.9, 3.6, wall)
	PropKit.tower(kit, Vector3(6.2, 0.0, -4.7), 0.9, 3.6, wall)
	glow.sphere(Vector3(0.0, 7.4, -2.2), Vector3(2.6, 2.2, 2.6), Color(1.0, 0.9, 0.5, 0.12), 8, 4)
	return 9.8


static func _icon_stable(kit: MeshKit, glow: MeshKit, rng: RandomNumberGenerator) -> float:
	for x in [-3.0, 3.0]:
		for z in [-2.2, 2.2]:
			kit.box(Vector3(float(x), 1.6, float(z)), Vector3(0.4, 3.2, 0.4), WOOD)
	kit.box(Vector3(0.0, 1.5, -2.3), Vector3(6.4, 3.0, 0.3), WOOD.darkened(0.12))
	kit.gable(Vector3(0.0, 3.1, 0.0), Vector3(7.4, 2.0, 5.8), STRAW, STRAW.darkened(0.1))
	kit.box(Vector3(0.0, 0.4, -1.2), Vector3(2.0, 0.5, 0.8), WOOD.darkened(0.05))
	kit.box(Vector3(0.0, 0.72, -1.2), Vector3(1.8, 0.16, 0.65), STRAW)
	AnimalKit.make(kit, rng, "buey", Vector3(-2.0, 0.0, 0.4), PI * 0.5, 1.25)
	AnimalKit.make(kit, rng, "burro", Vector3(2.0, 0.0, 0.2), -PI * 0.5, 1.25)
	PropKit.hay_bale(kit, Vector3(-2.6, 0.0, -1.6), 0.3, STRAW)
	# La luz del pesebre, el rayo y la estrella (Mateo 2:9).
	glow.sphere(Vector3(0.0, 1.0, -1.2), Vector3(0.9, 0.6, 0.9), Color(1.0, 0.92, 0.6, 0.5), 8, 4)
	glow.cylinder(Vector3(0.0, 0.5, 0.0), 1.8, 0.12, 6.8, 10, Color(1.0, 0.95, 0.6, 0.11), false)
	glow.push_xf(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-48.0)), Vector3(0.0, 7.6, 0.0)))
	glow.star(Vector3.ZERO, 1.7, 0.7, Color(1.0, 0.92, 0.5, 0.95))
	glow.pop()
	glow.sphere(Vector3(0.0, 7.6, 0.0), Vector3(2.2, 2.2, 2.2), Color(1.0, 0.95, 0.65, 0.14), 8, 4)
	return 8.4


# ---------------------------------------------------------------- Decorado

## Puntos (x, z) al azar en una corona, separados al menos "min_gap" entre sí.
static func _spots(rng: RandomNumberGenerator, count: int, min_radius: float, max_radius: float,
		min_gap: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var attempts: int = 0
	while points.size() < count and attempts < count * 40:
		attempts += 1
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = rng.randf_range(min_radius, max_radius)
		var spot := Vector2(cos(angle) * radius, sin(angle) * radius)
		var crowded: bool = false
		for other in points:
			if spot.distance_to(other) < min_gap:
				crowded = true
				break
		if not crowded:
			points.append(spot)
	return points


static func _count(base: int, density: float) -> int:
	return maxi(1, roundi(float(base) * density))


static func _decor_tree(kit: MeshKit, rng: RandomNumberGenerator, density: float) -> void:
	var leaf := Color(0.34, 0.64, 0.30)
	for spot in _spots(rng, _count(5, density), 5.4, 7.6, 3.0):
		PropKit.tree_fruit(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.9, 1.3), leaf,
				Color(0.95, 0.40, 0.30))
	for spot in _spots(rng, _count(5, density), 3.8, 7.4, 1.6):
		PropKit.bush(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.9, 1.4), Color(0.28, 0.58, 0.28))
	var flowers: Array[Color] = [Color(0.98, 0.55, 0.65), Color(1.0, 0.88, 0.35), Color(0.96, 0.96, 0.92),
			Color(0.92, 0.35, 0.35)]
	for spot in _spots(rng, _count(12, density), 3.2, 7.6, 0.8):
		PropKit.flower(kit, Vector3(spot.x, 0.0, spot.y), flowers[rng.randi_range(0, 3)], 1.6)


static func _decor_ark(kit: MeshKit, rng: RandomNumberGenerator, density: float) -> void:
	for spot in _spots(rng, _count(5, density), 6.6, 7.8, 2.4):
		PropKit.rock(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.9, 1.5), Color(0.55, 0.55, 0.56))
	for spot in _spots(rng, _count(3, density), 6.6, 7.7, 3.0):
		PropKit.cypress(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.9, 1.2))
	AnimalKit.make(kit, rng, "elefante", Vector3(-7.0, 0.0, 3.2), PI * 0.35, 0.9)
	AnimalKit.make(kit, rng, "elefante", Vector3(-6.2, 0.0, 4.6), PI * 0.2, 0.8)
	AnimalKit.make(kit, rng, "cebra", Vector3(6.8, 0.0, 3.8), -PI * 0.3, 1.1)
	AnimalKit.make(kit, rng, "cebra", Vector3(6.0, 0.0, 5.0), -PI * 0.45, 1.1)


static func _decor_pyramid(kit: MeshKit, rng: RandomNumberGenerator, density: float) -> void:
	for spot in _spots(rng, _count(4, density), 6.0, 7.6, 2.4):
		PropKit.palm(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(1.0, 1.35))
	var dune := Color(0.92, 0.80, 0.52)
	for spot in _spots(rng, 2, 6.2, 7.4, 6.0):
		kit.sphere(Vector3(spot.x, 0.0, spot.y), Vector3(3.0, 0.7, 2.0), dune, 7, 3, 0.1, rng, PI * 0.5)
	for spot in _spots(rng, _count(3, density), 5.0, 7.4, 2.0):
		PropKit.rock(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.6, 1.0), Color(0.72, 0.62, 0.46))
	PropKit.papyrus(kit, rng, Vector3(-1.2, 0.0, 6.6), 1.2)
	PropKit.papyrus(kit, rng, Vector3(-0.2, 0.0, 6.9), 1.0)


static func _decor_tent(kit: MeshKit, rng: RandomNumberGenerator, density: float) -> void:
	for spot in _spots(rng, _count(3, density), 6.2, 7.6, 3.0):
		PropKit.palm(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.95, 1.25))
	for spot in _spots(rng, _count(3, density), 5.4, 7.4, 2.2):
		PropKit.rock(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.6, 1.1), Color(0.70, 0.58, 0.42))
	var dune := Color(0.88, 0.72, 0.46)
	for spot in _spots(rng, 2, 6.6, 7.6, 6.0):
		kit.sphere(Vector3(spot.x, 0.0, spot.y), Vector3(2.6, 0.6, 1.8), dune, 7, 3, 0.1, rng, PI * 0.5)
	AnimalKit.make(kit, rng, "oveja", Vector3(5.8, 0.0, -2.8), 0.6, 1.2)
	AnimalKit.make(kit, rng, "oveja", Vector3(6.6, 0.0, -1.6), -0.4, 1.1)


static func _decor_mountain(kit: MeshKit, rng: RandomNumberGenerator, density: float) -> void:
	for spot in _spots(rng, _count(8, density), 5.4, 7.8, 1.8):
		PropKit.rock(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.8, 1.6), Color(0.52, 0.44, 0.36))
	for spot in _spots(rng, 2, 6.6, 7.6, 4.0):
		PropKit.olive(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.8, 1.0))


static func _decor_temple(kit: MeshKit, rng: RandomNumberGenerator, density: float) -> void:
	var wall := Color(0.86, 0.78, 0.62)
	var houses: Array[Vector2] = [Vector2(-6.4, 4.7), Vector2(6.2, 4.9), Vector2(-7.3, 0.4), Vector2(7.2, 0.2)]
	for i in houses.size():
		PropKit.house_flat(kit, rng, Vector3(houses[i].x, 0.0, houses[i].y), rng.randf_range(-0.4, 0.4),
				rng.randf_range(1.8, 2.4), rng.randf_range(1.6, 2.2), rng.randf_range(1.2, 1.7), wall)
	for spot in _spots(rng, _count(3, density), 5.6, 7.4, 2.4):
		if Vector2(spot.x, spot.y).distance_to(Vector2(0.0, 1.0)) > 6.4 and spot.y > -3.6:
			PropKit.cypress(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.9, 1.2))
	PropKit.olive(kit, rng, Vector3(-3.4, 0.0, 6.6), 0.9)
	PropKit.olive(kit, rng, Vector3(3.6, 0.0, 6.7), 0.85)


static func _decor_stable(kit: MeshKit, glow: MeshKit, rng: RandomNumberGenerator, density: float) -> void:
	var wall := Color(0.78, 0.68, 0.52)
	var roof := Color(0.46, 0.30, 0.22)
	var houses: Array[Vector2] = [Vector2(-6.2, -3.6), Vector2(6.0, -3.2), Vector2(-6.8, 3.0)]
	for i in houses.size():
		PropKit.house_gable(kit, rng, Vector3(houses[i].x, 0.0, houses[i].y), rng.randf_range(-0.5, 0.5),
				2.2, 1.8, 1.4, wall, roof, glow)
	for spot in _spots(rng, _count(3, density), 6.0, 7.6, 3.0):
		PropKit.cypress(kit, rng, Vector3(spot.x, 0.0, spot.y), rng.randf_range(0.8, 1.1), Color(0.12, 0.26, 0.20))
	for i in _count(4, density):
		AnimalKit.make(kit, rng, "oveja", Vector3(rng.randf_range(2.0, 6.0), 0.0, rng.randf_range(3.2, 6.0)),
				rng.randf_range(0.0, TAU), rng.randf_range(1.0, 1.25))
	PropKit.lantern_post(kit, Vector3(-3.4, 0.0, 4.2), 1.8, glow)
	PropKit.lantern_post(kit, Vector3(3.4, 0.0, 4.2), 1.8, glow)
	PropKit.torch(kit, Vector3(0.0, 0.0, 5.8), 1.0)
	glow.cone(Vector3(0.0, 1.25, 5.8), 0.3, 0.85, 5, Color(1.0, 0.62, 0.2, 0.9))


# ---------------------------------------------------------------- Figuras de estado

## Candado dorado que se ve de frente (región bloqueada). Mide unos 2.4 de alto.
static func add_padlock(kit: MeshKit) -> void:
	var gold := Color(0.92, 0.72, 0.24)
	var steel := Color(0.62, 0.64, 0.70)
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var angle: float = PI * float(i) / 8.0
		points.append(Vector3(cos(angle) * 0.62, 1.2 + sin(angle) * 0.72, 0.0))
		radii.append(0.15)
	kit.tube(points, radii, steel, 5)
	kit.box(Vector3(0.0, 0.6, 0.0), Vector3(1.9, 1.5, 0.75), gold, gold.lightened(0.08))
	kit.box(Vector3(0.0, 0.62, 0.4), Vector3(1.6, 1.2, 0.05), gold.darkened(0.12))
	kit.box(Vector3(0.0, 0.72, 0.43), Vector3(0.28, 0.28, 0.05), Color(0.16, 0.10, 0.04))
	kit.box(Vector3(0.0, 0.46, 0.43), Vector3(0.12, 0.34, 0.05), Color(0.16, 0.10, 0.04))


## Aro de luz plano, en el suelo, de radio "radius".
static func add_ring(kit: MeshKit, radius: float, thickness: float, color: Color, sides: int = 40) -> void:
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in sides + 1:
		var angle: float = TAU * float(i) / float(sides)
		points.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
		radii.append(thickness)
	kit.tube(points, radii, color, 4)


## Estrella dorada inclinada hacia la cámara (región completada).
static func add_star(kit: MeshKit, size: float) -> void:
	kit.push_xf(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-48.0)), Vector3.ZERO))
	kit.star(Vector3.ZERO, size, size * 0.42, Color(1.0, 0.86, 0.28, 0.95))
	kit.star(Vector3(0.0, 0.0, -0.05), size * 1.25, size * 0.6, Color(1.0, 0.8, 0.2, 0.3))
	kit.pop()


## Flecha dorada que señala hacia abajo (la próxima región que hay que jugar).
static func add_arrow(kit: MeshKit) -> void:
	var gold := Color(1.0, 0.84, 0.30, 0.95)
	kit.push_xf(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 1.9, 0.0)))
	kit.cone(Vector3.ZERO, 0.95, 1.9, 6, gold)
	kit.pop()
	kit.cylinder(Vector3(0.0, 1.9, 0.0), 0.32, 0.32, 1.5, 6, gold, true)
