class_name AnimalKit
extends RefCounted
## Animales low poly para los escenarios (elefante, jirafa, león, cebra, oveja, burro, buey y
## paloma). Cada uno mira hacia +Z cuando "yaw" es 0 y se agrega a un MeshKit, así que un
## rebaño entero cabe en una sola malla.

const IVORY := Color(0.95, 0.92, 0.82)
const BLACK := Color(0.10, 0.09, 0.09)


static func _legs(kit: MeshKit, spots: Array, height: float, radius: float, color: Color) -> void:
	for entry in spots:
		var spot: Vector2 = entry
		kit.cylinder(Vector3(spot.x, 0.0, spot.y), radius, radius * 0.8, height, 5, color, false)


## Un animal por nombre: "elefante", "jirafa", "leon", "cebra", "oveja", "burro", "buey", "paloma".
static func make(kit: MeshKit, rng: RandomNumberGenerator, kind: String, pos: Vector3, yaw: float, size: float) -> void:
	match kind:
		"elefante":
			elephant(kit, rng, pos, yaw, size)
		"jirafa":
			giraffe(kit, rng, pos, yaw, size)
		"leon":
			lion(kit, rng, pos, yaw, size)
		"cebra":
			zebra(kit, rng, pos, yaw, size)
		"oveja":
			sheep(kit, rng, pos, yaw, size)
		"burro":
			donkey(kit, rng, pos, yaw, size)
		"buey":
			ox(kit, rng, pos, yaw, size)
		"paloma":
			dove(kit, pos, yaw, size)


static func elephant(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, yaw: float, size: float) -> void:
	kit.place(pos, yaw, Vector3(size, size, size))
	var skin := Color(0.56, 0.56, 0.60)
	var dark: Color = skin.darkened(0.2)
	_legs(kit, [Vector2(-0.45, 0.65), Vector2(0.45, 0.65), Vector2(-0.45, -0.65), Vector2(0.45, -0.65)], 1.1, 0.24, dark)
	kit.sphere(Vector3(0.0, 1.55, 0.0), Vector3(0.85, 0.8, 1.2), skin, 8, 5, 0.04, rng)
	kit.sphere(Vector3(0.0, 1.75, 1.2), Vector3(0.5, 0.5, 0.55), skin, 7, 4)
	var trunk_points := PackedVector3Array([Vector3(0.0, 1.55, 1.65), Vector3(0.0, 1.15, 1.95),
			Vector3(0.0, 0.65, 2.05), Vector3(0.0, 0.3, 1.9)])
	var trunk_radii := PackedFloat32Array([0.2, 0.17, 0.13, 0.09])
	kit.tube(trunk_points, trunk_radii, skin, 6, true)
	kit.sphere(Vector3(0.58, 1.8, 1.0), Vector3(0.07, 0.42, 0.36), skin.lightened(0.04), 6, 3)
	kit.sphere(Vector3(-0.58, 1.8, 1.0), Vector3(0.07, 0.42, 0.36), skin.lightened(0.04), 6, 3)
	kit.beam(Vector3(0.28, 1.35, 1.55), Vector3(0.34, 1.1, 2.15), 0.07, 0.07, IVORY)
	kit.beam(Vector3(-0.28, 1.35, 1.55), Vector3(-0.34, 1.1, 2.15), 0.07, 0.07, IVORY)
	kit.beam(Vector3(0.0, 1.6, -1.15), Vector3(0.0, 0.95, -1.25), 0.05, 0.05, dark)
	kit.pop()


static func giraffe(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, yaw: float, size: float) -> void:
	kit.place(pos, yaw, Vector3(size, size, size))
	var coat := Color(0.90, 0.70, 0.30)
	var spot := Color(0.52, 0.31, 0.10)
	_legs(kit, [Vector2(-0.28, 0.55), Vector2(0.28, 0.55), Vector2(-0.28, -0.55), Vector2(0.28, -0.55)], 1.55, 0.08, coat)
	kit.sphere(Vector3(0.0, 1.95, 0.0), Vector3(0.42, 0.5, 0.85), coat, 8, 5, 0.03, rng)
	kit.beam(Vector3(0.0, 2.2, 0.55), Vector3(0.0, 4.1, 1.05), 0.26, 0.26, coat)
	kit.sphere(Vector3(0.0, 4.2, 1.25), Vector3(0.16, 0.17, 0.3), coat, 6, 4)
	kit.box(Vector3(0.06, 4.45, 1.15), Vector3(0.04, 0.16, 0.04), spot)
	kit.box(Vector3(-0.06, 4.45, 1.15), Vector3(0.04, 0.16, 0.04), spot)
	for i in 9:
		var t: float = rng.randf()
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		if i < 5:
			kit.box(Vector3(side * 0.4, 1.7 + rng.randf_range(0.0, 0.5), rng.randf_range(-0.6, 0.6)),
					Vector3(0.06, 0.2, 0.22), spot)
		else:
			kit.box(Vector3(side * 0.13, 2.4 + t * 1.5, 0.6 + t * 0.45), Vector3(0.06, 0.16, 0.16), spot)
	kit.beam(Vector3(0.0, 2.1, -0.85), Vector3(0.0, 1.3, -1.0), 0.04, 0.04, spot)
	kit.pop()


static func lion(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, yaw: float, size: float) -> void:
	kit.place(pos, yaw, Vector3(size, size, size))
	var coat := Color(0.82, 0.62, 0.30)
	var mane := Color(0.46, 0.28, 0.12)
	_legs(kit, [Vector2(-0.22, 0.5), Vector2(0.22, 0.5), Vector2(-0.22, -0.5), Vector2(0.22, -0.5)], 0.55, 0.1, coat)
	kit.sphere(Vector3(0.0, 0.85, 0.0), Vector3(0.36, 0.38, 0.75), coat, 7, 4, 0.04, rng)
	kit.sphere(Vector3(0.0, 1.0, 0.7), Vector3(0.44, 0.44, 0.3), mane, 7, 4, 0.1, rng)
	kit.sphere(Vector3(0.0, 0.98, 0.95), Vector3(0.24, 0.22, 0.24), coat, 6, 4)
	kit.box(Vector3(0.0, 0.9, 1.17), Vector3(0.14, 0.1, 0.12), coat.darkened(0.15))
	var tail_points := PackedVector3Array([Vector3(0.0, 0.9, -0.7), Vector3(0.0, 0.85, -1.05), Vector3(0.0, 0.55, -1.3)])
	var tail_radii := PackedFloat32Array([0.05, 0.04, 0.035])
	kit.tube(tail_points, tail_radii, coat, 4, true)
	kit.sphere(Vector3(0.0, 0.5, -1.33), Vector3(0.09, 0.09, 0.12), mane, 5, 3)
	kit.pop()


static func zebra(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, yaw: float, size: float) -> void:
	kit.place(pos, yaw, Vector3(size, size, size))
	var coat := Color(0.94, 0.94, 0.92)
	_legs(kit, [Vector2(-0.22, 0.6), Vector2(0.22, 0.6), Vector2(-0.22, -0.6), Vector2(0.22, -0.6)], 0.95, 0.07, coat)
	kit.sphere(Vector3(0.0, 1.25, 0.0), Vector3(0.36, 0.42, 0.85), coat, 8, 5, 0.02, rng)
	kit.beam(Vector3(0.0, 1.5, 0.6), Vector3(0.0, 2.05, 1.0), 0.2, 0.2, coat)
	kit.sphere(Vector3(0.0, 2.1, 1.2), Vector3(0.13, 0.15, 0.3), coat, 6, 4)
	kit.beam(Vector3(0.0, 2.2, 0.85), Vector3(0.0, 1.55, 0.5), 0.05, 0.09, BLACK)
	for i in 5:
		var z: float = -0.6 + 0.3 * float(i)
		var radius: float = 0.36 * sqrt(maxf(0.0, 1.0 - (z / 0.85) * (z / 0.85))) + 0.015
		kit.push_xf(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 1.25, z - 0.03)))
		kit.cylinder(Vector3.ZERO, radius * 1.18, radius * 1.18, 0.07, 8, BLACK, false)
		kit.pop()
	for i in 3:
		kit.box(Vector3(0.0, 1.62 + 0.18 * float(i), 0.65 + 0.12 * float(i)), Vector3(0.22, 0.05, 0.05), BLACK)
	kit.pop()


static func sheep(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, yaw: float, size: float) -> void:
	kit.place(pos, yaw, Vector3(size, size, size))
	var wool := Color(0.96, 0.95, 0.90)
	var face := Color(0.22, 0.18, 0.15)
	_legs(kit, [Vector2(-0.12, 0.2), Vector2(0.12, 0.2), Vector2(-0.12, -0.2), Vector2(0.12, -0.2)], 0.3, 0.04, face)
	kit.sphere(Vector3(0.0, 0.52, 0.0), Vector3(0.3, 0.27, 0.42), wool, 6, 4, 0.1, rng)
	kit.box(Vector3(0.0, 0.62, 0.5), Vector3(0.13, 0.15, 0.17), face)
	kit.box(Vector3(0.1, 0.7, 0.45), Vector3(0.1, 0.04, 0.05), face)
	kit.box(Vector3(-0.1, 0.7, 0.45), Vector3(0.1, 0.04, 0.05), face)
	kit.pop()


static func donkey(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, yaw: float, size: float) -> void:
	kit.place(pos, yaw, Vector3(size, size, size))
	var coat := Color(0.55, 0.50, 0.45)
	var light := Color(0.82, 0.78, 0.70)
	_legs(kit, [Vector2(-0.2, 0.45), Vector2(0.2, 0.45), Vector2(-0.2, -0.45), Vector2(0.2, -0.45)], 0.7, 0.07, coat.darkened(0.1))
	kit.sphere(Vector3(0.0, 0.95, 0.0), Vector3(0.32, 0.36, 0.65), coat, 7, 4, 0.03, rng)
	kit.beam(Vector3(0.0, 1.1, 0.45), Vector3(0.0, 1.5, 0.78), 0.18, 0.18, coat)
	kit.sphere(Vector3(0.0, 1.52, 0.92), Vector3(0.13, 0.15, 0.27), coat, 6, 4)
	kit.box(Vector3(0.0, 1.45, 1.15), Vector3(0.14, 0.1, 0.1), light)
	kit.beam(Vector3(0.07, 1.62, 0.8), Vector3(0.1, 1.98, 0.76), 0.06, 0.03, coat)
	kit.beam(Vector3(-0.07, 1.62, 0.8), Vector3(-0.1, 1.98, 0.76), 0.06, 0.03, coat)
	kit.beam(Vector3(0.0, 1.0, -0.62), Vector3(0.0, 0.5, -0.75), 0.05, 0.05, coat.darkened(0.15))
	kit.pop()


static func ox(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, yaw: float, size: float) -> void:
	kit.place(pos, yaw, Vector3(size, size, size))
	var coat := Color(0.50, 0.32, 0.18)
	_legs(kit, [Vector2(-0.24, 0.5), Vector2(0.24, 0.5), Vector2(-0.24, -0.5), Vector2(0.24, -0.5)], 0.6, 0.09, coat.darkened(0.2))
	kit.sphere(Vector3(0.0, 0.98, 0.0), Vector3(0.42, 0.44, 0.78), coat, 7, 4, 0.03, rng)
	kit.sphere(Vector3(0.0, 1.0, 0.85), Vector3(0.22, 0.24, 0.3), coat, 6, 4)
	kit.box(Vector3(0.0, 0.88, 1.12), Vector3(0.22, 0.14, 0.12), coat.lightened(0.15))
	kit.beam(Vector3(0.16, 1.2, 0.85), Vector3(0.34, 1.4, 0.82), 0.06, 0.06, IVORY)
	kit.beam(Vector3(-0.16, 1.2, 0.85), Vector3(-0.34, 1.4, 0.82), 0.06, 0.06, IVORY)
	kit.beam(Vector3(0.0, 1.1, -0.75), Vector3(0.0, 0.5, -0.85), 0.05, 0.05, coat.darkened(0.25))
	kit.pop()


## Paloma posada (o en el aire con las alas abiertas si "open_wings" es verdadero).
static func dove(kit: MeshKit, pos: Vector3, yaw: float, size: float, open_wings: bool = false) -> void:
	kit.place(pos, yaw, Vector3(size, size, size))
	var white := Color(0.98, 0.98, 0.95)
	kit.sphere(Vector3(0.0, 0.12, 0.0), Vector3(0.1, 0.1, 0.2), white, 6, 3)
	kit.sphere(Vector3(0.0, 0.22, 0.17), Vector3(0.07, 0.07, 0.08), white, 5, 3)
	kit.box(Vector3(0.0, 0.2, 0.26), Vector3(0.03, 0.025, 0.05), Color(0.95, 0.65, 0.25))
	kit.box(Vector3(0.0, 0.1, -0.24), Vector3(0.08, 0.02, 0.16), white.darkened(0.06))
	if open_wings:
		kit.beam(Vector3(0.08, 0.16, 0.0), Vector3(0.45, 0.32, -0.05), 0.12, 0.02, white)
		kit.beam(Vector3(-0.08, 0.16, 0.0), Vector3(-0.45, 0.32, -0.05), 0.12, 0.02, white)
	else:
		kit.box(Vector3(0.1, 0.14, -0.02), Vector3(0.03, 0.08, 0.2), white.darkened(0.05))
		kit.box(Vector3(-0.1, 0.14, -0.02), Vector3(0.03, 0.08, 0.2), white.darkened(0.05))
	kit.pop()
