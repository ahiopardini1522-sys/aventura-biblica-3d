class_name SceneryBelen
extends RefCounted
## Escenario de Belén (Lucas 2): una aldea de piedra en la noche con la estrella luminosa sobre
## el establo, cielo estrellado y luna, ventanas encendidas, una fogata de pastores con sus
## ovejas, linternas a lo largo del camino y luciérnagas.

const HALF := 110.0
const FAR_Y := -0.6
const LANE_X := 0.0
const STABLE := Vector2(0.0, -46.0)
const STAR_POS := Vector3(0.0, 40.0, -50.0)
const CAMPFIRE := Vector2(15.0, -6.5)
## Casas que se colocan a mano, cerca del tablero, para que se vean desde la cámara normal.
const NEAR_HOUSES := [Vector2(-6.0, -11.5), Vector2(9.5, -12.0), Vector2(23.0, 3.0), Vector2(-11.0, 2.5)]


## Altura del terreno: explanada plana en la aldea y colinas de Judea alrededor.
static func height_at(x: float, z: float) -> float:
	var radius: float = sqrt(x * x + z * z)
	var amplitude: float = lerpf(0.5, 8.0, smoothstep(26.0, 80.0, radius))
	var wave_a: float = 0.5 + 0.5 * sin(x * 0.075 + 0.4) * cos(z * 0.065 - 0.8)
	var wave_b: float = 0.5 + 0.5 * sin(x * 0.15 - z * 0.14 + 2.4)
	var hills: float = (wave_a * 0.65 + wave_b * 0.35) * amplitude
	var dx: float = maxf(absf(x - 2.0) - 26.0, 0.0)
	var dz: float = maxf(maxf(-60.0 - z, z - 14.0), 0.0)
	var basin: float = smoothstep(0.0, 18.0, sqrt(dx * dx + dz * dz))
	var h: float = TerrainKit.PLATEAU_Y + basin * hills
	return lerpf(h, FAR_Y, SceneryKit.edge_fade(x, z, HALF))


static func _terrain_color(x: float, z: float, y: float, ground: Color) -> Color:
	var n: float = 0.5 + 0.5 * sin(x * 0.3 + z * 0.2) * sin(z * 0.24 - x * 0.1)
	var grass: Color = Color(0.14, 0.26, 0.22).lerp(Color(0.20, 0.34, 0.27), clampf(y / 7.0 + n * 0.4, 0.0, 1.0))
	var base: Color = ground.lerp(grass, 0.7)
	return base.lerp(ground, SceneryKit.edge_fade(x, z, HALF))


static func _near_a_house(x: float, z: float) -> bool:
	for entry in NEAR_HOUSES:
		var house: Vector2 = entry
		if Vector2(x - house.x, z - house.y).length() < 8.0:
			return true
	return false


static func _village_spot_ok(x: float, z: float) -> bool:
	if absf(x - LANE_X) < 5.0 or _near_a_house(x, z):
		return false
	if Vector2(x - STABLE.x, z - STABLE.y).length() < 12.0:
		return false
	return Vector2(x - CAMPFIRE.x, z - CAMPFIRE.y).length() > 7.0


static func _nature_ok(x: float, z: float) -> bool:
	if x > -28.0 and x < 32.0 and z < -8.0 and z > -62.0:
		return false
	return Vector2(x - CAMPFIRE.x, z - CAMPFIRE.y).length() > 8.0


static func build(root: Node3D, seed_value: int, quality: int, ground: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var density: float = SceneryKit.density(quality)

	SceneryKit.far_ground(root, ground, FAR_Y)
	SceneryKit.terrain(root, HALF, 64, height_at, _terrain_color.bind(ground), "grass", 0.3)
	SceneryKit.far_mountains(root, rng, 7, Color(0.16, 0.20, 0.34), FAR_Y)
	FxKit.star_dome(root, rng, 150 if quality <= 0 else 260)
	FxKit.glow_ball(root, Vector3(-70.0, 62.0, -150.0), 7.0, Color(0.88, 0.92, 1.0, 0.85))

	_add_village(root, rng, density, quality)
	_add_stable(root, rng, quality)
	_add_star(root)
	_add_nature(root, rng, density)

	FxKit.floaters(root, "Fireflies", Vector3(2.0, 2.0, -6.0), Vector3(24.0, 2.0, 18.0), int(34.0 * density),
			0.2, Color(1.0, 0.95, 0.5, 1.0), 0.0, 6.0, true)
	FxKit.clouds(root, rng, 3 if quality <= 0 else 5, 46.0, 62.0, 150.0, Color(0.30, 0.34, 0.52, 0.7))


static func _add_light(root: Node3D, pos: Vector3, energy: float, light_range: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.name = "WarmLight"
	light.position = pos
	light.light_energy = energy
	light.omni_range = light_range
	light.light_color = color
	light.shadow_enabled = false
	root.add_child(light)


## Casas con las ventanas encendidas, el camino de tierra con sus linternas y los pastores.
static func _add_village(root: Node3D, rng: RandomNumberGenerator, density: float, quality: int) -> void:
	var kit := MeshKit.new()
	kit.uv_scale = 0.35
	var glow := MeshKit.new()
	var walls: Array[Color] = [Color(0.80, 0.72, 0.58), Color(0.74, 0.66, 0.54), Color(0.84, 0.78, 0.64)]
	var roofs: Array[Color] = [Color(0.46, 0.28, 0.20), Color(0.40, 0.30, 0.24), Color(0.52, 0.34, 0.22)]

	for entry in NEAR_HOUSES:
		var spot: Vector2 = entry
		var facing: float = PI * 0.5 if spot.x < LANE_X else -PI * 0.5
		_house(kit, glow, rng, spot, facing, walls, roofs)
	var area := Rect2(Vector2(-24.0, -58.0), Vector2(50.0, 46.0))
	for spot in SceneryKit.scatter_rect(rng, int(14.0 * density), area, 7.5, _village_spot_ok):
		var facing: float = PI * 0.5 if spot.x < LANE_X else -PI * 0.5
		_house(kit, glow, rng, spot, facing + rng.randf_range(-0.2, 0.2), walls, roofs)

	# Camino de tierra hasta el establo, con linternas a los lados.
	var dirt := Color(0.34, 0.29, 0.25)
	var z: float = 8.0
	var index: int = 0
	while z > -42.0:
		if absf(z) > 7.2:
			kit.box(Vector3(LANE_X, TerrainKit.PLATEAU_Y + 0.05, z), Vector3(3.0, 0.14, 1.9), dirt.lightened(0.05 * float(index % 2)))
		index += 1
		z -= 2.0
	for k in 6:
		var lz: float = -9.0 - 6.0 * float(k)
		var lx: float = LANE_X + (2.6 if k % 2 == 0 else -2.6)
		PropKit.lantern_post(kit, Vector3(lx, height_at(lx, lz) - 0.05, lz), 2.0, glow)

	# Fogata de los pastores con sus ovejas.
	var fire := Vector3(CAMPFIRE.x, height_at(CAMPFIRE.x, CAMPFIRE.y), CAMPFIRE.y)
	kit.cylinder(fire + Vector3(0.0, -0.05, 0.0), 0.8, 0.7, 0.22, 8, Color(0.30, 0.28, 0.27))
	kit.beam(fire + Vector3(-0.5, 0.25, -0.2), fire + Vector3(0.5, 0.3, 0.2), 0.14, 0.14, PropKit.DARK_WOOD)
	kit.beam(fire + Vector3(-0.4, 0.3, 0.3), fire + Vector3(0.4, 0.25, -0.3), 0.14, 0.14, PropKit.DARK_WOOD)
	glow.cone(fire + Vector3(0.0, 0.2, 0.0), 0.5, 1.1, 6, Color(1.0, 0.58, 0.14, 0.9))
	glow.sphere(fire + Vector3(0.0, 0.55, 0.0), Vector3(0.22, 0.3, 0.22), Color(1.0, 0.9, 0.5, 0.9), 6, 3)
	for i in 7:
		var angle: float = TAU * float(i) / 7.0 + rng.randf_range(-0.3, 0.3)
		var dist: float = rng.randf_range(3.0, 5.5)
		var sx: float = CAMPFIRE.x + cos(angle) * dist
		var sz: float = CAMPFIRE.y + sin(angle) * dist
		AnimalKit.make(kit, rng, "oveja", Vector3(sx, height_at(sx, sz), sz), rng.randf_range(0.0, TAU), rng.randf_range(0.95, 1.2))
	for side in [-1.0, 1.0]:
		var px: float = CAMPFIRE.x + float(side) * 2.0
		_shepherd(kit, Vector3(px, height_at(px, CAMPFIRE.y + 0.6), CAMPFIRE.y + 0.6), -float(side) * PI * 0.5)

	root.add_child(kit.instance(TextureKit.plain(0.9), "Village"))
	root.add_child(glow.instance(TextureKit.glow_vertex(true), "VillageGlow"))
	if quality > 0:
		_add_light(root, fire + Vector3(0.0, 1.3, 0.0), 1.3, 12.0, Color(1.0, 0.62, 0.30))


static func _house(kit: MeshKit, glow: MeshKit, rng: RandomNumberGenerator, spot: Vector2, yaw: float,
		walls: Array[Color], roofs: Array[Color]) -> void:
	PropKit.house_gable(kit, rng, Vector3(spot.x, height_at(spot.x, spot.y) - 0.05, spot.y), yaw,
			rng.randf_range(3.2, 4.6), rng.randf_range(3.0, 4.2), rng.randf_range(2.2, 3.0),
			walls[rng.randi() % walls.size()], roofs[rng.randi() % roofs.size()], glow)


## Pastor sentado: túnica, cabeza con pañuelo y bastón.
static func _shepherd(kit: MeshKit, pos: Vector3, yaw: float) -> void:
	kit.place(pos, yaw)
	kit.cylinder(Vector3.ZERO, 0.3, 0.2, 1.2, 6, Color(0.50, 0.36, 0.24), true)
	kit.sphere(Vector3(0.0, 1.4, 0.0), Vector3(0.17, 0.19, 0.17), Color(0.80, 0.62, 0.46), 6, 4)
	kit.box(Vector3(0.0, 1.52, -0.02), Vector3(0.4, 0.1, 0.4), Color(0.85, 0.82, 0.74))
	kit.beam(Vector3(0.42, 0.0, 0.1), Vector3(0.38, 1.9, 0.1), 0.05, 0.05, PropKit.DARK_WOOD)
	kit.pop()


## El establo: techo de paja sobre postes, muros de piedra, pesebre con heno luminoso, el buey,
## el burro y las ovejas, linternas a la entrada y una luz cálida.
static func _add_stable(root: Node3D, rng: RandomNumberGenerator, quality: int) -> void:
	var kit := MeshKit.new()
	var glow := MeshKit.new()
	var y: float = height_at(STABLE.x, STABLE.y)
	var cz: float = STABLE.y
	var stone := Color(0.46, 0.41, 0.36)
	var timber := Color(0.42, 0.28, 0.16)
	var straw := Color(0.86, 0.74, 0.36)
	kit.box(Vector3(0.0, y + 0.15, cz), Vector3(10.0, 0.3, 8.0), stone.darkened(0.08), stone)
	kit.sphere(Vector3(0.0, y + 1.8, cz - 4.2), Vector3(6.5, 3.4, 2.6), stone, 8, 4, 0.14, rng, PI, stone.darkened(0.2))
	kit.box(Vector3(0.0, y + 1.5, cz - 3.2), Vector3(8.4, 2.6, 0.5), stone)
	kit.box(Vector3(-4.1, y + 1.2, cz - 0.6), Vector3(0.5, 2.2, 5.4), stone)
	kit.box(Vector3(4.1, y + 1.2, cz - 0.6), Vector3(0.5, 2.2, 5.4), stone)
	for sx in [-4.2, 4.2]:
		for sz in [-3.2, 3.0]:
			kit.cylinder(Vector3(float(sx), y + 0.3, cz + float(sz)), 0.14, 0.12, 2.6, 5, timber, false)
	kit.gable(Vector3(0.0, y + 2.9, cz), Vector3(10.6, 1.9, 8.8), Color(0.72, 0.60, 0.30), Color(0.60, 0.50, 0.28))
	kit.box(Vector3(0.0, y + 0.55, cz - 1.4), Vector3(1.8, 0.5, 0.8), timber, timber.lightened(0.1))
	kit.box(Vector3(0.0, y + 0.85, cz - 1.4), Vector3(1.6, 0.18, 0.6), straw)
	glow.box(Vector3(0.0, y + 0.98, cz - 1.4), Vector3(1.3, 0.1, 0.45), Color(1.0, 0.86, 0.5, 0.8))
	AnimalKit.make(kit, rng, "buey", Vector3(-2.5, y + 0.3, cz - 0.8), PI * 0.5, 1.0)
	AnimalKit.make(kit, rng, "burro", Vector3(2.5, y + 0.3, cz - 0.6), -PI * 0.5, 1.0)
	AnimalKit.make(kit, rng, "oveja", Vector3(-1.6, y + 0.3, cz + 1.6), 0.6, 1.0)
	AnimalKit.make(kit, rng, "oveja", Vector3(1.4, y + 0.3, cz + 1.8), -0.5, 1.0)
	PropKit.hay_bale(kit, Vector3(-3.2, y + 0.3, cz + 1.0), 0.4, straw)
	PropKit.hay_bale(kit, Vector3(3.3, y + 0.3, cz + 0.9), -0.3, straw)
	PropKit.lantern_post(kit, Vector3(-4.4, y + 0.3, cz + 3.8), 2.4, glow)
	PropKit.lantern_post(kit, Vector3(4.4, y + 0.3, cz + 3.8), 2.4, glow)
	root.add_child(kit.instance(TextureKit.plain(0.95), "Stable"))
	root.add_child(glow.instance(TextureKit.glow_vertex(true), "StableGlow"))
	if quality > 0:
		_add_light(root, Vector3(0.0, y + 2.2, cz + 0.5), 1.6, 14.0, Color(1.0, 0.72, 0.40))


## La estrella de Belén: dos estrellas cruzadas con un halo y un haz de luz que baja al establo.
static func _add_star(root: Node3D) -> void:
	var glow := MeshKit.new()
	var gold := Color(1.0, 0.93, 0.55, 1.0)
	glow.star(STAR_POS, 4.6, 1.9, gold)
	glow.place(STAR_POS, PI * 0.5)
	glow.star(Vector3.ZERO, 4.6, 1.9, gold)
	glow.pop()
	glow.sphere(STAR_POS, Vector3(2.4, 2.4, 2.4), Color(1.0, 0.95, 0.65, 0.5), 8, 5)
	root.add_child(glow.instance(TextureKit.glow_vertex(true), "BethlehemStar"))
	var y: float = height_at(STABLE.x, STABLE.y)
	FxKit.beam(root, Vector3(STABLE.x, y + 3.0, STABLE.y), STAR_POS.y - y - 4.0, 4.2, 0.7,
			Color(1.0, 0.92, 0.55, 0.30), 8)


## Olivos, cipreses, arbustos y rocas en las colinas, fuera de la aldea.
static func _add_nature(root: Node3D, rng: RandomNumberGenerator, density: float) -> void:
	var kit := MeshKit.new()
	for spot in SceneryKit.scatter(rng, int(40.0 * density), 14.0, 72.0, _nature_ok):
		var pos := Vector3(spot.x, height_at(spot.x, spot.y) - 0.1, spot.y)
		var roll: float = rng.randf()
		if roll < 0.4:
			PropKit.olive(kit, rng, pos, rng.randf_range(0.9, 1.6))
		elif roll < 0.7:
			PropKit.cypress(kit, rng, pos, rng.randf_range(0.9, 1.4))
		elif roll < 0.85:
			PropKit.bush(kit, rng, pos, rng.randf_range(0.9, 1.5), Color(0.18, 0.34, 0.24))
		else:
			PropKit.rock(kit, rng, pos, rng.randf_range(0.7, 1.8), Color(0.40, 0.38, 0.38))
	root.add_child(kit.instance(TextureKit.plain(0.9), "Nature"))
