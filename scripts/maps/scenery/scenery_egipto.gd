class_name SceneryEgipto
extends RefCounted
## Escenario de Egipto y el Éxodo (Éxodo 14): el tablero está sobre el fondo seco del mar Rojo,
## entre dos murallas de agua. Al fondo se ven las pirámides, el pilón de un templo con sus
## obeliscos y la esfinge; en el lecho quedan carros del ejército del faraón, corales y conchas.

const HALF := 120.0
const FAR_Y := -0.6
const CORRIDOR_CENTER := 2.0
const CORRIDOR_HALF := 15.0
const WALL_TOP := 15.0
const Z_BACK := -70.0
const Z_FRONT := 50.0
const SAND := Color(0.88, 0.74, 0.48)
const GOLD := Color(0.95, 0.78, 0.30)
const PYLON_Z := -46.0


## 1 dentro del pasillo seco (el lecho del mar entre las dos murallas de agua) y 0 fuera de él.
static func corridor_mask(x: float) -> float:
	return 1.0 - smoothstep(CORRIDOR_HALF - 1.0, CORRIDOR_HALF + 5.0, absf(x - CORRIDOR_CENTER))


static func _corridor_length_mask(z: float) -> float:
	return smoothstep(Z_BACK - 20.0, Z_BACK + 5.0, z) * (1.0 - smoothstep(Z_FRONT - 5.0, Z_FRONT + 20.0, z))


## Altura del terreno: plano bajo el tablero, casi plano en el pasillo y dunas fuera de él.
static func height_at(x: float, z: float) -> float:
	var radius: float = sqrt(x * x + z * z)
	var amplitude: float = lerpf(0.3, 6.0, smoothstep(14.0, 70.0, radius))
	var wave_a: float = 0.5 + 0.5 * sin(x * 0.07 + z * 0.05 + 1.0)
	var wave_b: float = 0.5 + 0.5 * sin(x * 0.13 - z * 0.09 + 2.2)
	var dunes: float = (wave_a * 0.65 + wave_b * 0.35) * amplitude
	var flat: float = corridor_mask(x) * _corridor_length_mask(z)
	var h: float = TerrainKit.PLATEAU_Y + TerrainKit.board_mask(x, z) * dunes * (1.0 - flat * 0.9)
	return lerpf(h, FAR_Y, SceneryKit.edge_fade(x, z, HALF))


static func _terrain_color(x: float, z: float, y: float, ground: Color) -> Color:
	var n: float = 0.5 + 0.5 * sin(x * 0.29 + z * 0.19) * sin(z * 0.21 - x * 0.13)
	var base: Color = ground.darkened(0.06).lerp(ground.lightened(0.12), clampf(y / 6.0 + n * 0.4, 0.0, 1.0))
	base = base.lerp(Color(0.70, 0.58, 0.40), corridor_mask(x) * _corridor_length_mask(z) * 0.5)
	return base.lerp(ground, SceneryKit.edge_fade(x, z, HALF))


static func _accept_palm(x: float, z: float) -> bool:
	return z < Z_BACK - 4.0 or z > Z_FRONT + 4.0 or absf(x - CORRIDOR_CENTER) > CORRIDOR_HALF + 16.0


static func build(root: Node3D, seed_value: int, quality: int, ground: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var density: float = SceneryKit.density(quality)

	SceneryKit.far_ground(root, ground, FAR_Y)
	SceneryKit.terrain(root, HALF, 64, height_at, _terrain_color.bind(ground), "sand", 0.3)

	_add_water_walls(root)
	_add_monuments(root, rng)
	_add_seabed(root, rng, density)

	FxKit.birds(root, rng, 2 if quality <= 0 else 3, Vector3(CORRIDOR_CENTER, 0.0, -20.0), 18.0, 12.0,
			Color(0.96, 0.96, 0.92))
	FxKit.clouds(root, rng, 4 if quality <= 0 else 6, 42.0, 60.0, 150.0, Color(1.0, 0.98, 0.94, 0.85))
	var spray_amount: int = int(24.0 * density)
	for x in [CORRIDOR_CENTER - CORRIDOR_HALF, CORRIDOR_CENTER + CORRIDOR_HALF]:
		FxKit.floaters(root, "Spray", Vector3(float(x), 1.8, -10.0), Vector3(1.4, 1.8, 60.0), spray_amount, 3.0,
				Color(1.0, 1.0, 1.0, 0.22), 0.15, 3.5)
	FxKit.floaters(root, "Dust", Vector3(CORRIDOR_CENTER, 2.0, -6.0), Vector3(24.0, 2.0, 22.0),
			int(20.0 * density), 0.8, Color(0.92, 0.80, 0.62, 0.30), 0.02, 9.0)


## Las dos murallas de agua del mar Rojo: un volumen azul oscuro y, delante, una lámina con
## franjas de espuma que bajan sin parar.
static func _add_water_walls(root: Node3D) -> void:
	var slabs := MeshKit.new()
	var length: float = Z_FRONT - Z_BACK
	var center_z: float = (Z_FRONT + Z_BACK) * 0.5
	var thickness: float = 13.7
	var left_edge: float = CORRIDOR_CENTER - CORRIDOR_HALF
	var right_edge: float = CORRIDOR_CENTER + CORRIDOR_HALF
	var deep := Color(0.05, 0.26, 0.45)
	var foam := Color(0.80, 0.93, 0.98)
	var size := Vector3(thickness, WALL_TOP + 1.0, length)
	slabs.box(Vector3(left_edge - 0.3 - thickness * 0.5, (WALL_TOP - 1.0) * 0.5, center_z), size, deep, foam)
	slabs.box(Vector3(right_edge + 0.3 + thickness * 0.5, (WALL_TOP - 1.0) * 0.5, center_z), size, deep, foam)
	root.add_child(slabs.instance(TextureKit.plain(0.5), "SeaVolume"))

	var material: ShaderMaterial = WaterKit.fall_material(Color(0.78, 0.95, 1.0, 0.80), Color(0.10, 0.42, 0.68, 0.62), 0.9, 4.0)
	for edge in [left_edge, right_edge]:
		var x: float = edge
		var wall := MeshInstance3D.new()
		wall.name = "WaterWall"
		wall.mesh = WaterKit.sheet(Vector3(x, WALL_TOP, Z_BACK), Vector3(x, WALL_TOP, Z_FRONT),
				Vector3(x, -0.3, Z_BACK), Vector3(x, -0.3, Z_FRONT), 8, 1)
		wall.material_override = material
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wall)


## Pirámides, esfinge, pilón del templo con sus obeliscos, hileras de columnas y antorchas.
static func _add_monuments(root: Node3D, rng: RandomNumberGenerator) -> void:
	var stone := MeshKit.new()
	stone.uv_scale = 0.28
	var glow := MeshKit.new()

	var pyramids: Array = [[Vector2(-40.0, -125.0), 32.0, 40.0], [Vector2(12.0, -132.0), 26.0, 33.0],
			[Vector2(60.0, -112.0), 20.0, 25.0], [Vector2(-85.0, -95.0), 11.0, 14.0],
			[Vector2(100.0, -95.0), 9.0, 11.0]]
	for entry in pyramids:
		var spot: Vector2 = entry[0]
		var half: float = float(entry[1])
		var height: float = float(entry[2])
		var base := Vector3(spot.x, height_at(spot.x, spot.y) - 1.0, spot.y)
		stone.pyramid(base, half, height, MeshKit.vary_color(SAND, 0.03, rng))
		stone.pyramid(base + Vector3(0.0, height * 0.88, 0.0), half * 0.125, height * 0.12, GOLD)

	_add_sphinx(stone, Vector3(-52.0, height_at(-52.0, -80.0) - 0.6, -80.0), 1.6)

	# Pilón del templo: dos torres inclinadas con cornisa dorada, dintel y mástiles.
	for side in [-1.0, 1.0]:
		var cx: float = CORRIDOR_CENTER + float(side) * 10.0
		var ground_y: float = height_at(cx, PYLON_Z) - 0.5
		stone.place(Vector3(cx, ground_y, PYLON_Z), 0.0, Vector3(1.7, 1.0, 0.55))
		stone.frustum(Vector3.ZERO, 3.0, 2.5, 15.0, SAND.darkened(0.04), SAND.lightened(0.08))
		stone.pop()
		stone.box(Vector3(cx, ground_y + 15.2, PYLON_Z), Vector3(9.8, 0.5, 3.5), GOLD)
		for k in [-1.0, 1.0]:
			var mast_x: float = cx + float(k) * 3.0
			stone.beam(Vector3(mast_x, ground_y + 15.4, PYLON_Z + 2.1), Vector3(mast_x, ground_y + 22.0, PYLON_Z + 2.1),
					0.14, 0.14, PropKit.DARK_WOOD)
			stone.box(Vector3(mast_x, ground_y + 20.8, PYLON_Z + 2.1), Vector3(0.9, 1.6, 0.05),
					Color(0.80, 0.18, 0.15) if side < 0.0 else Color(0.95, 0.92, 0.85))
	var lintel_y: float = height_at(CORRIDOR_CENTER, PYLON_Z) - 0.5
	stone.box(Vector3(CORRIDOR_CENTER, lintel_y + 12.0, PYLON_Z), Vector3(10.4, 2.4, 2.6), SAND.lightened(0.04), SAND.lightened(0.1))
	for side in [-1.0, 1.0]:
		var ox: float = CORRIDOR_CENTER + float(side) * 3.7
		PropKit.obelisk(stone, Vector3(ox, height_at(ox, PYLON_Z + 6.0) - 0.3, PYLON_Z + 6.0), 0.9, 9.0, SAND.lightened(0.04), GOLD)

	# Hileras de columnas a los lados del pasillo, camino del pilón.
	for k in 5:
		var z: float = -14.0 - 6.0 * float(k)
		for side in [-1.0, 1.0]:
			var x: float = CORRIDOR_CENTER + float(side) * 11.5
			PropKit.column(stone, Vector3(x, height_at(x, z) - 0.2, z), 0.5, 5.2, SAND.lightened(0.02))
	# Antorchas con llama junto a la entrada del templo.
	for side in [-1.0, 1.0]:
		for z in [-26.0, -38.0]:
			var tx: float = CORRIDOR_CENTER + float(side) * 5.0
			var tz: float = float(z)
			var top: Vector3 = Vector3(tx, height_at(tx, tz) - 0.2, tz)
			PropKit.torch(stone, top, 1.6)
			glow.sphere(top + Vector3(0.0, 1.85, 0.0), Vector3(0.24, 0.36, 0.24), Color(1.0, 0.62, 0.20, 0.9), 6, 4)

	root.add_child(stone.instance(TextureKit.material("sandstone", 0.9), "Monuments"))
	root.add_child(glow.instance(TextureKit.glow_vertex(true), "Flames"))


## Esfinge acostada que mira hacia +Z (hacia la cámara).
static func _add_sphinx(kit: MeshKit, pos: Vector3, size: float) -> void:
	kit.place(pos, 0.0, Vector3(size, size, size))
	var stone: Color = SAND.darkened(0.03)
	kit.sphere(Vector3(0.0, 2.2, -2.5), Vector3(2.2, 2.0, 6.0), stone, 8, 5)
	kit.box(Vector3(-1.1, 0.7, 4.6), Vector3(1.0, 1.4, 5.0), stone.lightened(0.03))
	kit.box(Vector3(1.1, 0.7, 4.6), Vector3(1.0, 1.4, 5.0), stone.lightened(0.03))
	kit.box(Vector3(0.0, 3.6, 3.2), Vector3(2.6, 3.0, 2.2), stone)
	kit.sphere(Vector3(0.0, 6.0, 3.5), Vector3(1.6, 1.9, 1.6), stone.lightened(0.05), 8, 5)
	kit.box(Vector3(0.0, 5.7, 2.7), Vector3(3.6, 3.2, 0.8), Color(0.22, 0.36, 0.68))
	kit.box(Vector3(0.0, 5.8, 5.0), Vector3(0.3, 0.8, 0.3), stone.darkened(0.08))
	kit.pop()


## Lo que dejó el mar en el fondo seco: carros del faraón, corales, conchas, rocas y, lejos,
## palmeras en las orillas.
static func _add_seabed(root: Node3D, rng: RandomNumberGenerator, density: float) -> void:
	var kit := MeshKit.new()
	var chariots: Array = [[Vector2(-8.5, -10.5), 0.6, 0.25], [Vector2(13.5, -12.5), -0.9, -0.3],
			[Vector2(-3.0, -20.0), 2.4, 0.35], [Vector2(7.0, -27.0), 0.2, -0.2]]
	for entry in chariots:
		var spot: Vector2 = entry[0]
		_chariot(kit, Vector3(spot.x, height_at(spot.x, spot.y) - 0.05, spot.y), float(entry[1]), float(entry[2]))

	var coral_colors: Array[Color] = [Color(0.92, 0.45, 0.40), Color(0.95, 0.62, 0.38), Color(0.86, 0.40, 0.58)]
	for spot in _corridor_spots(rng, int(18.0 * density), -36.0, 4.0):
		_coral(kit, rng, Vector3(spot.x, height_at(spot.x, spot.y) - 0.05, spot.y), coral_colors[rng.randi() % coral_colors.size()])
	for spot in _corridor_spots(rng, int(26.0 * density), -36.0, 4.0):
		kit.cone(Vector3(spot.x, height_at(spot.x, spot.y) - 0.02, spot.y), 0.13, 0.22, 5, Color(0.97, 0.93, 0.85))
	for spot in _corridor_spots(rng, int(18.0 * density), -36.0, 4.0):
		PropKit.rock(kit, rng, Vector3(spot.x, height_at(spot.x, spot.y) - 0.1, spot.y), rng.randf_range(0.5, 1.3),
				Color(0.66, 0.55, 0.42))

	var palm_spots: Array[Vector2] = SceneryKit.scatter(rng, int(30.0 * density), 36.0, 88.0, _accept_palm)
	for spot in palm_spots:
		PropKit.palm(kit, rng, Vector3(spot.x, height_at(spot.x, spot.y) - 0.1, spot.y), rng.randf_range(1.0, 1.5))
	root.add_child(kit.instance(TextureKit.plain(0.9), "Seabed"))


## Puntos al azar dentro del pasillo, fuera del tablero, del dado y de la franja de la cámara.
static func _corridor_spots(rng: RandomNumberGenerator, count: int, z_min: float, z_max: float) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var attempts: int = 0
	while spots.size() < count and attempts < count * 40:
		attempts += 1
		var x: float = rng.randf_range(CORRIDOR_CENTER - CORRIDOR_HALF + 1.0, CORRIDOR_CENTER + CORRIDOR_HALF - 1.0)
		var z: float = rng.randf_range(z_min, z_max)
		if SceneryKit.is_clear_zone(x, z, 1.0):
			continue
		spots.append(Vector2(x, z))
	return spots


## Carro de guerra volcado a medias: suelo, tres paredes con filo dorado, varas y dos ruedas.
static func _chariot(kit: MeshKit, pos: Vector3, yaw: float, tilt: float) -> void:
	var wood := Color(0.50, 0.34, 0.18)
	var trim := Color(0.88, 0.70, 0.26)
	kit.place(pos, yaw)
	kit.push_xf(Transform3D(Basis(Vector3.BACK, tilt), Vector3.ZERO))
	kit.box(Vector3(0.0, 0.62, 0.0), Vector3(1.3, 0.12, 1.1), wood)
	kit.box(Vector3(0.0, 0.98, -0.5), Vector3(1.3, 0.6, 0.1), wood, trim)
	kit.box(Vector3(-0.6, 0.98, 0.0), Vector3(0.1, 0.6, 1.1), wood, trim)
	kit.box(Vector3(0.6, 0.98, 0.0), Vector3(0.1, 0.6, 1.1), wood, trim)
	kit.beam(Vector3(0.0, 0.62, 0.5), Vector3(0.0, 0.7, 2.7), 0.1, 0.1, PropKit.DARK_WOOD)
	for side in [-1.0, 1.0]:
		kit.push_xf(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(float(side) * 0.74, 0.5, 0.0)))
		kit.cylinder(Vector3(0.0, -0.06, 0.0), 0.5, 0.5, 0.12, 10, PropKit.DARK_WOOD, true, true)
		kit.cylinder(Vector3(0.0, -0.1, 0.0), 0.13, 0.13, 0.2, 6, trim, true, true)
		kit.pop()
	kit.pop()
	kit.pop()


## Coral: unas ramas gruesas que salen de un mismo punto, con la punta más clara.
static func _coral(kit: MeshKit, rng: RandomNumberGenerator, pos: Vector3, color: Color) -> void:
	for i in 4:
		var angle: float = rng.randf_range(0.0, TAU)
		var lean := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.15, 0.45)
		var rise: float = rng.randf_range(0.5, 1.1)
		var tip: Vector3 = pos + lean + Vector3(0.0, rise, 0.0)
		kit.beam(pos, tip, 0.12, 0.12, MeshKit.vary_color(color, 0.06, rng))
		kit.sphere(tip, Vector3(0.12, 0.1, 0.12), color.lightened(0.1), 5, 3)
