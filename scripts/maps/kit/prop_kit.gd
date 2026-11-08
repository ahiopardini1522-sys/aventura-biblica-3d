class_name PropKit
extends RefCounted
## Piezas decorativas low poly que se agregan a un MeshKit: árboles, rocas, flores, casas,
## torres, muros, columnas, obeliscos, tiendas, barriles... Cada función coloca la pieza
## donde se le pide y deja el MeshKit como estaba, así que se pueden combinar libremente
## para construir un escenario entero dentro de unas pocas mallas.

const TRUNK := Color(0.40, 0.27, 0.15)
const DARK_WOOD := Color(0.30, 0.19, 0.10)
const DOOR := Color(0.25, 0.15, 0.08)


# ---------------------------------------------------------------- Vegetación

## Árbol de copa redonda.
static func tree_round(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, size: float,
		leaf: Color, trunk: Color = TRUNK) -> void:
	kit.place(pos, rng.randf_range(0.0, TAU), Vector3(size, size, size))
	var trunk_height: float = rng.randf_range(1.5, 2.1)
	kit.cylinder(Vector3.ZERO, 0.28, 0.2, trunk_height, 6, trunk, false)
	var crown: Color = MeshKit.vary_color(leaf, 0.05, rng)
	kit.sphere(Vector3(0.0, trunk_height + 0.9, 0.0), Vector3(1.7, 1.4, 1.7), crown, 7, 4, 0.18, rng,
			PI, crown.darkened(0.25))
	kit.sphere(Vector3(rng.randf_range(-0.7, 0.7), trunk_height + 1.7, rng.randf_range(-0.7, 0.7)),
			Vector3(1.1, 0.95, 1.1), crown.lightened(0.08), 6, 3, 0.15, rng, PI, crown)
	kit.pop()


## Árbol frutal: copa redonda con frutos de colores.
static func tree_fruit(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, size: float,
		leaf: Color, fruit: Color) -> void:
	tree_round(kit, rng, pos, size, leaf)
	kit.place(pos, 0.0, Vector3(size, size, size))
	for i in 7:
		var angle: float = rng.randf_range(0.0, TAU)
		var spread: float = rng.randf_range(0.8, 1.45)
		var height: float = rng.randf_range(2.0, 3.3)
		kit.box(Vector3(cos(angle) * spread, height, sin(angle) * spread), Vector3(0.2, 0.2, 0.2),
				MeshKit.vary_color(fruit, 0.05, rng))
	kit.pop()


## Ciprés: columna verde oscura estrecha y alta.
static func cypress(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, size: float,
		leaf: Color = Color(0.15, 0.34, 0.21)) -> void:
	kit.place(pos, rng.randf_range(0.0, TAU), Vector3(size, size, size))
	kit.cylinder(Vector3.ZERO, 0.16, 0.12, 0.7, 5, TRUNK, false)
	kit.cylinder(Vector3(0.0, 0.5, 0.0), 0.8, 0.0, 2.2, 7, MeshKit.vary_color(leaf, 0.03, rng))
	kit.cylinder(Vector3(0.0, 1.8, 0.0), 0.6, 0.0, 2.4, 7, MeshKit.vary_color(leaf.lightened(0.06), 0.03, rng))
	kit.pop()


## Olivo: tronco retorcido y copa plana gris verdosa.
static func olive(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, size: float) -> void:
	kit.place(pos, rng.randf_range(0.0, TAU), Vector3(size, size, size))
	var points := PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.12, 0.6, 0.05),
			Vector3(-0.1, 1.2, -0.05), Vector3(0.05, 1.7, 0.1)])
	var radii := PackedFloat32Array([0.24, 0.2, 0.16, 0.13])
	kit.tube(points, radii, Color(0.38, 0.30, 0.22), 5, true)
	var leaf := Color(0.47, 0.54, 0.34)
	kit.sphere(Vector3(0.0, 2.0, 0.0), Vector3(1.5, 0.75, 1.5), MeshKit.vary_color(leaf, 0.04, rng),
			7, 3, 0.15, rng, PI, leaf.darkened(0.2))
	kit.sphere(Vector3(0.6, 1.8, 0.3), Vector3(0.9, 0.5, 0.9), MeshKit.vary_color(leaf.lightened(0.05), 0.04, rng),
			6, 3, 0.15, rng)
	kit.pop()


## Palmera datilera con frutos.
static func palm(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, size: float) -> void:
	kit.place(pos, rng.randf_range(0.0, TAU), Vector3(size, size, size))
	var lean := Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.7, 0.7))
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 5:
		var t: float = float(i) / 4.0
		points.append(Vector3(lean.x * t * t, 3.4 * t, lean.z * t * t))
		radii.append(lerpf(0.22, 0.13, t))
	kit.tube(points, radii, Color(0.45, 0.33, 0.20), 5, true)
	var top: Vector3 = points[4]
	var frond := Color(0.28, 0.58, 0.24)
	for i in 8:
		var angle: float = TAU * float(i) / 8.0 + rng.randf_range(-0.2, 0.2)
		var tip: Vector3 = top + Vector3(cos(angle) * 1.9, -0.7 + rng.randf_range(-0.2, 0.3), sin(angle) * 1.9)
		kit.beam(top + Vector3(0.0, 0.1, 0.0), tip, 0.5, 0.04, MeshKit.vary_color(frond, 0.05, rng))
	kit.sphere(top + Vector3(0.15, -0.2, 0.1), Vector3(0.12, 0.12, 0.12), Color(0.32, 0.20, 0.10), 5, 3)
	kit.pop()


## Papiro: tallos finos con una sombrilla de hojas arriba (orillas del Nilo).
static func papyrus(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, size: float) -> void:
	kit.place(pos, rng.randf_range(0.0, TAU), Vector3(size, size, size))
	var green := Color(0.40, 0.62, 0.28)
	for i in 3:
		var angle: float = TAU * float(i) / 3.0 + rng.randf_range(-0.4, 0.4)
		var top := Vector3(cos(angle) * 0.35, rng.randf_range(1.5, 2.2), sin(angle) * 0.35)
		kit.beam(Vector3.ZERO, top, 0.05, 0.05, green)
		kit.disc(top, 0.4, MeshKit.vary_color(green.lightened(0.08), 0.04, rng), 6)
	kit.pop()


## Arbusto redondo.
static func bush(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, size: float, color: Color) -> void:
	var tint: Color = MeshKit.vary_color(color, 0.05, rng)
	kit.sphere(pos + Vector3(0.0, 0.3 * size, 0.0), Vector3(0.7, 0.5, 0.7) * size, tint, 6, 3, 0.2, rng,
			PI, tint.darkened(0.2))


## Roca irregular.
static func rock(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, size: float, color: Color) -> void:
	var tint: Color = MeshKit.vary_color(color, 0.06, rng)
	var squash: float = rng.randf_range(0.5, 0.85)
	kit.sphere(pos + Vector3(0.0, 0.3 * size * squash, 0.0),
			Vector3(rng.randf_range(0.8, 1.2), squash, rng.randf_range(0.7, 1.1)) * size, tint, 6, 3, 0.25,
			rng, PI, tint.darkened(0.18))


## Florecilla de cuatro pétalos sobre el suelo.
static func flower(kit: MeshKit, pos: Vector3, color: Color, size: float = 1.0) -> void:
	kit.cylinder(pos, 0.1 * size, 0.0, 0.22 * size, 4, color, false)


# ---------------------------------------------------------------- Construcciones

## Casa de muros lisos y techo a dos aguas. Con "glow" las ventanas se dibujan como luz.
static func house_gable(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, yaw: float,
		width: float, depth: float, height: float, wall: Color, roof: Color,
		glow: MeshKit = null) -> void:
	kit.place(pos, yaw)
	var tint: Color = MeshKit.vary_color(wall, 0.04, rng)
	kit.box(Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth), tint)
	kit.gable(Vector3(0.0, height, 0.0), Vector3(width + 0.4, height * 0.55, depth + 0.4),
			MeshKit.vary_color(roof, 0.04, rng), tint.darkened(0.04))
	kit.box(Vector3(0.0, 0.55, depth * 0.5 + 0.01), Vector3(0.55, 1.1, 0.06), DOOR)
	if glow != null:
		glow.place(pos, yaw)
		glow.box(Vector3(width * 0.28, height * 0.58, depth * 0.5 + 0.02), Vector3(0.38, 0.38, 0.05),
				Color(1.0, 0.78, 0.40, 0.9))
		glow.box(Vector3(-width * 0.28, height * 0.58, depth * 0.5 + 0.02), Vector3(0.38, 0.38, 0.05),
				Color(1.0, 0.78, 0.40, 0.9))
		glow.pop()
	else:
		kit.box(Vector3(width * 0.28, height * 0.58, depth * 0.5 + 0.02), Vector3(0.36, 0.36, 0.05), DOOR)
		kit.box(Vector3(-width * 0.28, height * 0.58, depth * 0.5 + 0.02), Vector3(0.36, 0.36, 0.05), DOOR)
	kit.pop()


## Casa de techo plano con un pequeño muro alrededor (arquitectura antigua de Oriente).
static func house_flat(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, yaw: float,
		width: float, depth: float, height: float, wall: Color, glow: MeshKit = null) -> void:
	kit.place(pos, yaw)
	var tint: Color = MeshKit.vary_color(wall, 0.04, rng)
	kit.box(Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth), tint, tint.lightened(0.06))
	kit.box(Vector3(0.0, height + 0.08, 0.0), Vector3(width + 0.14, 0.16, depth + 0.14), tint.darkened(0.08))
	kit.box(Vector3(0.0, 0.5, depth * 0.5 + 0.01), Vector3(0.5, 1.0, 0.06), DOOR)
	if glow != null:
		glow.place(pos, yaw)
		glow.box(Vector3(width * 0.3, height * 0.62, depth * 0.5 + 0.02), Vector3(0.34, 0.34, 0.05),
				Color(1.0, 0.78, 0.40, 0.9))
		glow.pop()
	else:
		kit.box(Vector3(width * 0.3, height * 0.62, depth * 0.5 + 0.02), Vector3(0.32, 0.32, 0.05), DOOR)
	if rng.randf() < 0.5:
		kit.box(Vector3(-width * 0.2, height + 0.4, -depth * 0.15), Vector3(width * 0.3, 0.5, depth * 0.3),
				tint.darkened(0.04), tint.lightened(0.08))
	kit.pop()


## Torre redonda con techo cónico (o plana con almenas si "roof" es transparente).
static func tower(kit: MeshKit, pos: Vector3, radius: float, height: float, wall: Color,
		roof: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	kit.place(pos)
	kit.cylinder(Vector3.ZERO, radius, radius * 0.92, height, 8, wall, true, false, wall.lightened(0.05))
	if roof.a > 0.0:
		kit.cylinder(Vector3(0.0, height, 0.0), radius * 1.3, 0.0, radius * 1.6, 8, roof)
	else:
		for i in 8:
			var angle: float = TAU * float(i) / 8.0
			kit.box(Vector3(cos(angle) * radius * 0.88, height + 0.2, sin(angle) * radius * 0.88),
					Vector3(radius * 0.3, 0.4, radius * 0.3), wall.darkened(0.04))
	kit.pop()


## Tramo de muro recto con almenas arriba, de un punto a otro (los puntos están en el suelo).
static func wall_run(kit: MeshKit, from: Vector3, to: Vector3, height: float, thickness: float,
		color: Color, merlons: bool = true) -> void:
	var delta: Vector3 = to - from
	delta.y = 0.0
	var length: float = delta.length()
	if length < 0.01:
		return
	var direction: Vector3 = delta / length
	kit.push_xf(Transform3D(Basis.looking_at(direction, Vector3.UP), (from + to) * 0.5))
	kit.box(Vector3(0.0, height * 0.5, 0.0), Vector3(thickness, height, length), color, color.lightened(0.06))
	if merlons:
		var count: int = maxi(2, int(length / 0.9))
		var slot: float = length / float(count)
		for i in count:
			var z: float = -length * 0.5 + (float(i) + 0.5) * slot
			kit.box(Vector3(0.0, height + 0.22, z), Vector3(thickness, 0.44, slot * 0.55), color.darkened(0.03))
	kit.pop()


## Columna con base y capitel.
static func column(kit: MeshKit, base: Vector3, radius: float, height: float, color: Color,
		cap_color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var cap: Color = color.lightened(0.06)
	if cap_color.a > 0.0:
		cap = cap_color
	kit.box(base + Vector3(0.0, 0.09, 0.0), Vector3(radius * 2.5, 0.18, radius * 2.5), cap)
	kit.cylinder(base + Vector3(0.0, 0.18, 0.0), radius, radius * 0.88, height - 0.4, 8, color, false)
	kit.box(base + Vector3(0.0, height - 0.11, 0.0), Vector3(radius * 2.6, 0.22, radius * 2.6), cap)


## Obelisco con la punta dorada.
static func obelisk(kit: MeshKit, base: Vector3, half: float, height: float, color: Color,
		tip_color: Color) -> void:
	kit.frustum(base, half, half * 0.62, height, color)
	kit.pyramid(base + Vector3(0.0, height, 0.0), half * 0.62, half * 0.95, tip_color)


## Tienda de campaña de pastor: cono bajo con la entrada oscura.
static func tent(kit: MeshKit, pos: Vector3, yaw: float, size: float, color: Color) -> void:
	kit.place(pos, yaw)
	kit.cylinder(Vector3.ZERO, size, 0.05, size * 1.15, 6, color, false)
	kit.box(Vector3(0.0, size * 0.32, size * 0.8), Vector3(size * 0.34, size * 0.62, 0.05), DOOR)
	kit.pop()


static func barrel(kit: MeshKit, pos: Vector3, radius: float, height: float, color: Color) -> void:
	kit.cylinder(pos, radius, radius * 0.9, height, 8, color, true)
	kit.cylinder(pos + Vector3(0.0, height * 0.3, 0.0), radius * 1.02, radius * 1.02, 0.05, 8, DARK_WOOD, false)
	kit.cylinder(pos + Vector3(0.0, height * 0.7, 0.0), radius * 1.02, radius * 1.02, 0.05, 8, DARK_WOOD, false)


static func crate(kit: MeshKit, pos: Vector3, size: float, color: Color) -> void:
	kit.box(pos + Vector3(0.0, size * 0.5, 0.0), Vector3(size, size, size), color)


## Fardo de heno o paja.
static func hay_bale(kit: MeshKit, pos: Vector3, yaw: float, color: Color) -> void:
	kit.place(pos, yaw)
	kit.box(Vector3(0.0, 0.25, 0.0), Vector3(0.9, 0.5, 0.5), color)
	kit.box(Vector3(0.0, 0.25, 0.0), Vector3(0.92, 0.08, 0.52), color.darkened(0.2))
	kit.pop()


## Poste con una cazoleta arriba (antorcha o brasero). La llama se agrega aparte, como luz.
static func torch(kit: MeshKit, pos: Vector3, height: float = 1.5) -> void:
	kit.cylinder(pos, 0.06, 0.05, height, 5, DARK_WOOD, false)
	kit.cylinder(pos + Vector3(0.0, height, 0.0), 0.2, 0.12, 0.22, 6, Color(0.30, 0.26, 0.22), true)


## Farol: poste con una cajita para la luz arriba (la luz se agrega aparte).
static func lantern_post(kit: MeshKit, pos: Vector3, height: float, glow: MeshKit = null) -> void:
	kit.cylinder(pos, 0.05, 0.04, height, 5, DARK_WOOD, false)
	kit.box(pos + Vector3(0.0, height + 0.12, 0.0), Vector3(0.22, 0.04, 0.22), DARK_WOOD)
	if glow != null:
		glow.box(pos + Vector3(0.0, height + 0.02, 0.0), Vector3(0.14, 0.18, 0.14), Color(1.0, 0.8, 0.4, 0.95))


## Puerta monumental: dos pilares, dintel y frontón.
static func gateway(kit: MeshKit, base: Vector3, width: float, height: float, thickness: float,
		color: Color, top_color: Color) -> void:
	var pillar: float = thickness
	kit.box(base + Vector3(-width * 0.5 + pillar * 0.5, height * 0.5, 0.0), Vector3(pillar, height, thickness), color)
	kit.box(base + Vector3(width * 0.5 - pillar * 0.5, height * 0.5, 0.0), Vector3(pillar, height, thickness), color)
	kit.box(base + Vector3(0.0, height + 0.12, 0.0), Vector3(width + 0.2, 0.28, thickness * 1.2), top_color)
	kit.gable(base + Vector3(0.0, height + 0.26, 0.0), Vector3(width + 0.3, 0.45, thickness * 1.2), top_color)
