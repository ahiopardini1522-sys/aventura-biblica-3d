class_name SceneryJerusalen
extends RefCounted
## Escenario de Jerusalén (1 Reyes 6, Mateo 21): la ciudad antigua con sus murallas, torres y una
## puerta al final del camino principal, casas de techo plano, el Templo dorado sobre su
## plataforma con una escalinata, un mercado junto al camino, el monte de los Olivos con sus
## olivos, cipreses y palomas.

const HALF := 110.0
const FAR_Y := -0.6
const ROAD_X := 2.0
const WALL_Z := -30.0
const WALL_LEFT := -46.0
const WALL_RIGHT := 50.0
const WALL_BACK := -82.0
const WALL_HEIGHT := 7.0
const CROSS_Z := -42.0
const TEMPLE := Vector2(2.0, -66.0)
const OLIVES := Vector2(82.0, -8.0)
const LIMESTONE := Color(0.90, 0.84, 0.70)
const GOLD := Color(0.96, 0.80, 0.32)


## Altura del terreno: una gran explanada plana (la ciudad, el camino y el tablero) rodeada de
## colinas, con el monte de los Olivos a la derecha.
static func height_at(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - 2.0) - 50.0, 0.0)
	var dz: float = maxf(maxf(-85.0 - z, z - 20.0), 0.0)
	var basin: float = smoothstep(0.0, 26.0, sqrt(dx * dx + dz * dz))
	var radius: float = sqrt(x * x + z * z)
	var amplitude: float = lerpf(0.6, 9.0, smoothstep(40.0, 100.0, radius))
	var wave_a: float = 0.5 + 0.5 * sin(x * 0.08 + 0.9) * cos(z * 0.07 - 0.2)
	var wave_b: float = 0.5 + 0.5 * sin(x * 0.17 - z * 0.12 + 1.1)
	var hills: float = (wave_a * 0.65 + wave_b * 0.35) * amplitude
	var olives: float = 1.0 - smoothstep(0.0, 32.0, Vector2(x - OLIVES.x, z - OLIVES.y).length())
	var h: float = TerrainKit.PLATEAU_Y + basin * hills + olives * 16.0
	return lerpf(h, FAR_Y, SceneryKit.edge_fade(x, z, HALF))


static func _terrain_color(x: float, z: float, y: float, ground: Color) -> Color:
	var n: float = 0.5 + 0.5 * sin(x * 0.29 + z * 0.21) * sin(z * 0.19 - x * 0.12)
	var base: Color = ground.darkened(0.04).lerp(ground.lightened(0.1), clampf(y / 8.0 + n * 0.35, 0.0, 1.0))
	var grove: float = 1.0 - smoothstep(14.0, 36.0, Vector2(x - OLIVES.x, z - OLIVES.y).length())
	base = base.lerp(Color(0.44, 0.52, 0.30), grove * 0.7)
	if x > WALL_LEFT and x < WALL_RIGHT and z < WALL_Z and z > WALL_BACK:
		base = base.lerp(Color(0.84, 0.78, 0.66), 0.55)
	return base.lerp(ground, SceneryKit.edge_fade(x, z, HALF))


static func _inside_walls(x: float, z: float, margin: float) -> bool:
	return x > WALL_LEFT - margin and x < WALL_RIGHT + margin and z < WALL_Z + margin and z > WALL_BACK - margin


## Sitios para casas dentro de las murallas: fuera de las calles y de la plataforma del Templo.
static func _city_spot_ok(x: float, z: float) -> bool:
	if absf(x - ROAD_X) < 5.0 or absf(z - CROSS_Z) < 3.5:
		return false
	if absf(x - TEMPLE.x) < 26.0 and z < TEMPLE.y + 26.0:
		return false
	return true


static func _nature_ok(x: float, z: float) -> bool:
	if _inside_walls(x, z, 4.0):
		return false
	return absf(x - ROAD_X) > 12.0 or z > 18.0


static func build(root: Node3D, seed_value: int, quality: int, ground: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var density: float = SceneryKit.density(quality)

	SceneryKit.far_ground(root, ground, FAR_Y)
	SceneryKit.terrain(root, HALF, 64, height_at, _terrain_color.bind(ground), "dirt", 0.25)
	SceneryKit.far_mountains(root, rng, 7, Color(0.66, 0.60, 0.54), FAR_Y)

	_add_city(root, rng, density)
	_add_nature(root, rng, density)

	FxKit.birds(root, rng, 3, Vector3(ROAD_X, 0.0, -50.0), 24.0, 17.0, Color(0.98, 0.98, 0.95))
	FxKit.clouds(root, rng, 4 if quality <= 0 else 6, 44.0, 60.0, 150.0)
	FxKit.floaters(root, "Incense", Vector3(TEMPLE.x, 15.0, TEMPLE.y + 6.0), Vector3(1.5, 5.0, 1.5),
			int(14.0 * density), 4.0, Color(0.92, 0.90, 0.88, 0.26), 0.3, 5.0)
	FxKit.floaters(root, "Dust", Vector3(2.0, 2.0, -6.0), Vector3(24.0, 2.0, 18.0),
			int(18.0 * density), 0.7, Color(0.95, 0.88, 0.70, 0.28), 0.02, 9.0)


## La ciudad: murallas con torres y puerta, casas, el Templo, el mercado y los caminos.
static func _add_city(root: Node3D, rng: RandomNumberGenerator, density: float) -> void:
	var stone := MeshKit.new()
	stone.uv_scale = 0.3
	var trim := MeshKit.new()
	var wall_color: Color = LIMESTONE.darkened(0.06)

	_wall(stone, Vector2(WALL_LEFT, WALL_Z), Vector2(ROAD_X - 4.4, WALL_Z), wall_color)
	_wall(stone, Vector2(ROAD_X + 4.4, WALL_Z), Vector2(WALL_RIGHT, WALL_Z), wall_color)
	_wall(stone, Vector2(WALL_RIGHT, WALL_Z), Vector2(WALL_RIGHT, WALL_BACK), wall_color)
	_wall(stone, Vector2(WALL_RIGHT, WALL_BACK), Vector2(WALL_LEFT, WALL_BACK), wall_color)
	_wall(stone, Vector2(WALL_LEFT, WALL_BACK), Vector2(WALL_LEFT, WALL_Z), wall_color)

	var towers: Array[Vector2] = [Vector2(WALL_LEFT, WALL_Z), Vector2(WALL_RIGHT, WALL_Z),
			Vector2(WALL_RIGHT, WALL_BACK), Vector2(WALL_LEFT, WALL_BACK), Vector2(-30.0, WALL_Z),
			Vector2(-16.0, WALL_Z), Vector2(22.0, WALL_Z), Vector2(36.0, WALL_Z), Vector2(WALL_LEFT, -46.0),
			Vector2(WALL_LEFT, -64.0), Vector2(WALL_RIGHT, -46.0), Vector2(WALL_RIGHT, -64.0),
			Vector2(-30.0, WALL_BACK), Vector2(-12.0, WALL_BACK), Vector2(2.0, WALL_BACK),
			Vector2(18.0, WALL_BACK), Vector2(36.0, WALL_BACK)]
	for spot in towers:
		PropKit.tower(stone, Vector3(spot.x, height_at(spot.x, spot.y) - 0.3, spot.y), 2.2, 10.0, wall_color.lightened(0.03))
	# Puerta de la ciudad: dos torres más altas y un dintel entre ellas.
	for side in [-1.0, 1.0]:
		var gx: float = ROAD_X + float(side) * 4.4
		PropKit.tower(stone, Vector3(gx, height_at(gx, WALL_Z) - 0.3, WALL_Z), 2.4, 12.0, wall_color.lightened(0.05))
	var gate_y: float = height_at(ROAD_X, WALL_Z)
	stone.box(Vector3(ROAD_X, gate_y + 6.2, WALL_Z), Vector3(8.8, 1.6, 2.2), wall_color.lightened(0.05))
	trim.box(Vector3(ROAD_X, gate_y + 7.15, WALL_Z), Vector3(9.0, 0.3, 2.4), GOLD)

	var tints: Array[Color] = [LIMESTONE, Color(0.86, 0.78, 0.62), Color(0.92, 0.88, 0.76), Color(0.82, 0.72, 0.58)]
	var city_area := Rect2(Vector2(WALL_LEFT + 3.0, WALL_BACK + 3.0),
			Vector2(WALL_RIGHT - WALL_LEFT - 6.0, WALL_Z - WALL_BACK - 6.0))
	for spot in SceneryKit.scatter_rect(rng, int(46.0 * density), city_area, 6.5, _city_spot_ok):
		var yaw: float = float(rng.randi_range(0, 3)) * PI * 0.5 + rng.randf_range(-0.12, 0.12)
		PropKit.house_flat(stone, rng, Vector3(spot.x, height_at(spot.x, spot.y) - 0.05, spot.y), yaw,
				rng.randf_range(3.2, 5.4), rng.randf_range(3.0, 4.8), rng.randf_range(2.6, 4.8),
				tints[rng.randi() % tints.size()])

	_add_temple(stone, trim)
	_add_roads(stone)

	# Mercado a los dos lados del camino, delante de la puerta.
	var awnings: Array[Color] = [Color(0.80, 0.22, 0.18), Color(0.20, 0.45, 0.70), Color(0.92, 0.72, 0.20),
			Color(0.35, 0.60, 0.30)]
	for k in 5:
		var z: float = -11.0 - 4.0 * float(k)
		_stall(trim, Vector3(ROAD_X - 5.4, height_at(ROAD_X - 5.4, z) - 0.05, z), PI * 0.5, awnings[k % awnings.size()])
		_stall(trim, Vector3(ROAD_X + 5.4, height_at(ROAD_X + 5.4, z - 2.0) - 0.05, z - 2.0), -PI * 0.5,
				awnings[(k + 2) % awnings.size()])

	root.add_child(stone.instance(TextureKit.material("sandstone", 0.9), "City"))
	root.add_child(trim.instance(TextureKit.plain(0.8), "Trim"))


## Tramo de muralla entre dos puntos del suelo.
static func _wall(kit: MeshKit, a: Vector2, b: Vector2, color: Color) -> void:
	var from := Vector3(a.x, height_at(a.x, a.y) - 0.3, a.y)
	var to := Vector3(b.x, height_at(b.x, b.y) - 0.3, b.y)
	PropKit.wall_run(kit, from, to, WALL_HEIGHT, 1.6, color)


## El Templo: plataforma con escalinata, sala de mármol con techo dorado, pórtico con columnas,
## balaustrada y la torre Antonia en una esquina.
static func _add_temple(stone: MeshKit, trim: MeshKit) -> void:
	var y: float = height_at(TEMPLE.x, TEMPLE.y) - 0.1
	var marble := Color(0.95, 0.92, 0.84)
	stone.box(Vector3(TEMPLE.x, y + 1.5, TEMPLE.y), Vector3(46.0, 3.0, 28.0), LIMESTONE.darkened(0.05),
			LIMESTONE.lightened(0.05))
	for i in 5:
		var rise: float = 2.5 - 0.5 * float(i)
		stone.box(Vector3(TEMPLE.x, y + rise * 0.5, TEMPLE.y + 14.6 + 1.2 * float(i)), Vector3(12.0, rise, 1.2),
				LIMESTONE.lightened(0.02))
	var rail: Color = LIMESTONE.lightened(0.04)
	var top: float = y + 3.0
	PropKit.wall_run(stone, Vector3(TEMPLE.x - 22.5, top, TEMPLE.y - 13.5), Vector3(TEMPLE.x + 22.5, top, TEMPLE.y - 13.5), 1.0, 0.5, rail, false)
	PropKit.wall_run(stone, Vector3(TEMPLE.x - 22.5, top, TEMPLE.y - 13.5), Vector3(TEMPLE.x - 22.5, top, TEMPLE.y + 13.5), 1.0, 0.5, rail, false)
	PropKit.wall_run(stone, Vector3(TEMPLE.x + 22.5, top, TEMPLE.y - 13.5), Vector3(TEMPLE.x + 22.5, top, TEMPLE.y + 13.5), 1.0, 0.5, rail, false)
	PropKit.wall_run(stone, Vector3(TEMPLE.x - 22.5, top, TEMPLE.y + 13.5), Vector3(TEMPLE.x - 6.0, top, TEMPLE.y + 13.5), 1.0, 0.5, rail, false)
	PropKit.wall_run(stone, Vector3(TEMPLE.x + 6.0, top, TEMPLE.y + 13.5), Vector3(TEMPLE.x + 22.5, top, TEMPLE.y + 13.5), 1.0, 0.5, rail, false)

	stone.box(Vector3(TEMPLE.x, top + 6.0, TEMPLE.y - 3.0), Vector3(16.0, 12.0, 20.0), marble, marble.lightened(0.03))
	stone.box(Vector3(TEMPLE.x, top + 7.5, TEMPLE.y + 8.0), Vector3(24.0, 15.0, 3.0), marble.darkened(0.02))
	trim.box(Vector3(TEMPLE.x, top + 12.4, TEMPLE.y - 3.0), Vector3(16.8, 0.8, 20.8), GOLD)
	trim.box(Vector3(TEMPLE.x, top + 15.4, TEMPLE.y + 8.0), Vector3(24.8, 0.8, 3.8), GOLD)
	trim.box(Vector3(TEMPLE.x, top + 4.0, TEMPLE.y + 9.6), Vector3(5.0, 8.0, 0.3), GOLD.darkened(0.08))
	for i in 7:
		var cx: float = TEMPLE.x - 9.0 + 3.0 * float(i)
		PropKit.column(stone, Vector3(cx, top, TEMPLE.y + 10.5), 0.55, 9.0, marble)
	for side in [-1.0, 1.0]:
		trim.pyramid(Vector3(TEMPLE.x + float(side) * 11.6, top + 15.8, TEMPLE.y + 8.0), 0.6, 1.6, GOLD)
	PropKit.tower(stone, Vector3(TEMPLE.x - 21.0, y, TEMPLE.y - 12.0), 3.0, 16.0, LIMESTONE.darkened(0.04))


## Caminos de losas: el principal, desde el tablero hasta el Templo, y una calle que lo cruza.
static func _add_roads(stone: MeshKit) -> void:
	var tones: Array[Color] = [Color(0.80, 0.74, 0.62), Color(0.75, 0.69, 0.58)]
	var ground: float = TerrainKit.PLATEAU_Y
	var index: int = 0
	var z: float = 18.0
	while z > -50.0:
		if absf(z) > 7.2:
			stone.box(Vector3(ROAD_X, ground + 0.06, z), Vector3(3.4, 0.16, 1.9), tones[index % 2])
		index += 1
		z -= 2.0
	var x: float = WALL_LEFT + 3.0
	while x < WALL_RIGHT - 2.0:
		if absf(x - ROAD_X) > 2.4:
			stone.box(Vector3(x, ground + 0.06, CROSS_Z), Vector3(1.9, 0.16, 3.0), tones[index % 2])
		index += 1
		x += 2.0


## Puesto del mercado: cuatro postes, toldo a dos aguas, mostrador y fruta. Mira hacia +Z.
static func _stall(kit: MeshKit, pos: Vector3, yaw: float, awning: Color) -> void:
	kit.place(pos, yaw)
	for sx in [-0.95, 0.95]:
		for sz in [-0.8, 0.8]:
			kit.cylinder(Vector3(float(sx), 0.0, float(sz)), 0.05, 0.05, 2.0, 4, PropKit.DARK_WOOD, false)
	kit.gable(Vector3(0.0, 2.0, 0.0), Vector3(2.4, 0.5, 2.1), awning, awning.darkened(0.1))
	kit.box(Vector3(0.0, 0.45, 0.35), Vector3(1.8, 0.9, 0.7), Color(0.62, 0.46, 0.28), Color(0.74, 0.58, 0.36))
	var goods: Array[Color] = [Color(0.88, 0.24, 0.18), Color(0.96, 0.72, 0.18), Color(0.45, 0.68, 0.28),
			Color(0.62, 0.30, 0.55)]
	for i in 4:
		kit.sphere(Vector3(-0.6 + 0.4 * float(i), 1.0, 0.35), Vector3(0.14, 0.12, 0.14), goods[i], 5, 3)
	kit.pop()


## Olivos del monte de los Olivos, cipreses junto al camino y rocas sueltas.
static func _add_nature(root: Node3D, rng: RandomNumberGenerator, density: float) -> void:
	var kit := MeshKit.new()
	for i in int(44.0 * density):
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(2.0, 28.0)
		var x: float = OLIVES.x + cos(angle) * dist
		var z: float = OLIVES.y + sin(angle) * dist * 0.9
		PropKit.olive(kit, rng, Vector3(x, height_at(x, z) - 0.1, z), rng.randf_range(1.0, 1.7))
	for k in 7:
		var cz: float = -10.0 - 3.0 * float(k)
		for side in [-1.0, 1.0]:
			var cx: float = ROAD_X + float(side) * 9.4
			PropKit.cypress(kit, rng, Vector3(cx, height_at(cx, cz) - 0.1, cz), rng.randf_range(0.9, 1.3))
	for spot in SceneryKit.scatter(rng, int(22.0 * density), 14.0, 48.0, _nature_ok):
		if rng.randf() < 0.5:
			PropKit.olive(kit, rng, Vector3(spot.x, height_at(spot.x, spot.y) - 0.1, spot.y), rng.randf_range(0.9, 1.5))
		else:
			PropKit.rock(kit, rng, Vector3(spot.x, height_at(spot.x, spot.y) - 0.1, spot.y), rng.randf_range(0.7, 1.8),
					Color(0.72, 0.66, 0.56))
	root.add_child(kit.instance(TextureKit.plain(0.9), "Nature"))
