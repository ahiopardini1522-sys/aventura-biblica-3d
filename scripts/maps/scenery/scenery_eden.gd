class_name SceneryEden
extends RefCounted
## Escenario del Jardín del Edén (Génesis 2:8-17): colinas verdes, un río que nace en una
## cascada, árboles frutales, flores, el árbol del conocimiento con la serpiente enroscada,
## aves en vuelo, polen en el aire y niebla de agua junto a la cascada.

const HALF := 92.0
const WATER_Y := -0.78
const BED_Y := -1.6
const FAR_Y := -1.5
const CLIFF_CENTER := Vector2(-23.0, -29.0)
const CLIFF_HALF := Vector2(13.0, 6.0)
const CLIFF_HEIGHT := 11.0
const KNOWLEDGE_TREE := Vector2(-11.0, -12.0)


## Centro del río en cada z (nace en la poza de la cascada y baja hacia la cámara).
static func river_x(z: float) -> float:
	var pool_shift: float = -3.0 * (1.0 - smoothstep(-17.0, -9.0, z))
	return -19.5 + 3.2 * sin(z * 0.075 + 0.6) + pool_shift


## Altura del acantilado de la cascada sobre el suelo base (0 lejos de él).
static func cliff_height(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - CLIFF_CENTER.x) - CLIFF_HALF.x, 0.0)
	var dz: float = maxf(absf(z - CLIFF_CENTER.y) - CLIFF_HALF.y, 0.0)
	return CLIFF_HEIGHT * (1.0 - smoothstep(0.0, 6.0, sqrt(dx * dx + dz * dz)))


static func _river_t(x: float, z: float) -> float:
	var fade: float = smoothstep(-19.5, -16.5, z)
	var distance: float = absf(x - river_x(z))
	return (1.0 - smoothstep(2.0, 4.6, distance)) * fade


## Altura del terreno en (x, z): plano bajo el tablero, colinas suaves, acantilado y cauce.
static func height_at(x: float, z: float) -> float:
	var radius: float = sqrt(x * x + z * z)
	var amplitude: float = lerpf(0.5, 6.5, smoothstep(14.0, 62.0, radius))
	var wave: float = 0.5 + 0.5 * sin(x * 0.09 + 1.3) * cos(z * 0.07 - 0.4)
	var wave2: float = 0.5 + 0.5 * sin(x * 0.17 - z * 0.13 + 2.0)
	var hills: float = (wave * 0.7 + wave2 * 0.3) * amplitude
	var h: float = TerrainKit.PLATEAU_Y + TerrainKit.board_mask(x, z) * hills
	h = maxf(h, TerrainKit.PLATEAU_Y + cliff_height(x, z))
	h = lerpf(h, BED_Y, _river_t(x, z))
	return lerpf(h, FAR_Y, SceneryKit.edge_fade(x, z, HALF))


static func _terrain_color(x: float, z: float, y: float, ground: Color) -> Color:
	var n: float = 0.5 + 0.5 * sin(x * 0.31 + z * 0.17) * sin(z * 0.23 - x * 0.11)
	var base: Color = ground.darkened(0.08).lerp(ground.lightened(0.14), clampf(y / 5.0 + n * 0.35, 0.0, 1.0))
	var bank: float = absf(x - river_x(z))
	if z > -19.0 and bank < 6.5 and y < -0.1:
		base = base.lerp(Color(0.70, 0.62, 0.42), (1.0 - smoothstep(3.0, 6.5, bank)) * 0.75)
	var cliff: float = cliff_height(x, z)
	var face: float = smoothstep(0.4, 2.0, cliff) * (1.0 - smoothstep(10.2, 10.95, cliff))
	base = base.lerp(Color(0.55, 0.50, 0.44), face * 0.85)
	return base.lerp(ground, SceneryKit.edge_fade(x, z, HALF))


static func _accept_spot(x: float, z: float) -> bool:
	if z > -19.5 and absf(x - river_x(z)) < 7.5:
		return false
	if cliff_height(x, z) > 0.3:
		return false
	if Vector2(x - KNOWLEDGE_TREE.x, z - KNOWLEDGE_TREE.y).length() < 4.5:
		return false
	return true


static func build(root: Node3D, seed_value: int, quality: int, ground: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var density: float = SceneryKit.density(quality)

	SceneryKit.far_ground(root, ground, FAR_Y)
	SceneryKit.terrain(root, HALF, 64, height_at, _terrain_color.bind(ground), "grass", 0.32)
	SceneryKit.far_mountains(root, rng, 7, Color(0.50, 0.66, 0.80), FAR_Y)

	_add_vegetation(root, rng, density)
	_add_flowers(root, rng, density)
	_add_water(root, rng)

	var birds_count: int = 2 if quality <= 0 else 4
	FxKit.birds(root, rng, birds_count, Vector3(0.0, 0.0, -6.0), 17.0, 11.0, Color(0.97, 0.97, 0.93))
	FxKit.clouds(root, rng, 6 if quality <= 0 else 8, 40.0, 58.0, 150.0)
	FxKit.floaters(root, "Pollen", Vector3(0.0, 2.8, -4.0), Vector3(26.0, 2.6, 22.0),
			int(34.0 * density), 0.17, Color(1.0, 0.95, 0.62, 0.9), 0.03, 9.0)
	FxKit.floaters(root, "Mist", Vector3(-23.0, 1.6, -16.5), Vector3(3.6, 1.2, 1.6),
			int(16.0 * density), 3.2, Color(1.0, 1.0, 1.0, 0.30), 0.12, 3.6)


static func _add_vegetation(root: Node3D, rng: RandomNumberGenerator, density: float) -> void:
	var leaves: Array[Color] = [Color(0.30, 0.62, 0.26), Color(0.36, 0.70, 0.28),
			Color(0.24, 0.55, 0.30), Color(0.44, 0.74, 0.30)]
	var fruits: Array[Color] = [Color(0.88, 0.20, 0.16), Color(0.98, 0.62, 0.12),
			Color(0.98, 0.86, 0.22), Color(0.80, 0.24, 0.52)]
	var trees := MeshKit.new()

	var near_spots: Array[Vector2] = SceneryKit.scatter(rng, int(15.0 * density), 9.0, 24.0, _accept_spot)
	for spot in near_spots:
		var pos := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		PropKit.tree_fruit(trees, rng, pos, rng.randf_range(0.9, 1.25), leaves[rng.randi() % leaves.size()],
				fruits[rng.randi() % fruits.size()])

	var far_spots: Array[Vector2] = SceneryKit.scatter(rng, int(62.0 * density), 18.0, 78.0, _accept_spot)
	for spot in far_spots:
		var pos := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var size: float = rng.randf_range(1.0, 1.9)
		PropKit.tree_round(trees, rng, pos, size, leaves[rng.randi() % leaves.size()])

	var bush_spots: Array[Vector2] = SceneryKit.scatter(rng, int(36.0 * density), 8.0, 40.0, _accept_spot)
	for spot in bush_spots:
		var flowering: bool = rng.randf() < 0.25
		var color: Color = Color(0.86, 0.46, 0.62) if flowering else Color(0.22, 0.50, 0.26)
		PropKit.bush(trees, rng, Vector3(spot.x, height_at(spot.x, spot.y), spot.y),
				rng.randf_range(0.9, 1.5), color)

	var knowledge := Vector3(KNOWLEDGE_TREE.x, height_at(KNOWLEDGE_TREE.x, KNOWLEDGE_TREE.y), KNOWLEDGE_TREE.y)
	PropKit.tree_fruit(trees, rng, knowledge, 1.5, Color(0.26, 0.58, 0.26), Color(0.92, 0.12, 0.10))
	_add_serpent(trees, knowledge)

	for i in int(18.0 * density):
		var z: float = rng.randf_range(-12.0, 60.0)
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		var x: float = river_x(z) + side * rng.randf_range(4.2, 5.6)
		PropKit.rock(trees, rng, Vector3(x, height_at(x, z), z), rng.randf_range(0.5, 1.1), Color(0.58, 0.55, 0.50))
	for i in 7:
		var angle: float = rng.randf_range(0.0, TAU)
		var x2: float = -23.0 + cos(angle) * rng.randf_range(5.5, 8.0)
		var z2: float = -15.0 + sin(angle) * rng.randf_range(3.5, 5.0)
		PropKit.rock(trees, rng, Vector3(x2, height_at(x2, z2), z2), rng.randf_range(0.9, 1.7), Color(0.55, 0.52, 0.47))

	root.add_child(trees.instance(TextureKit.plain(0.9), "Vegetation"))


## La serpiente enroscada en el tronco del árbol del conocimiento.
static func _add_serpent(kit: MeshKit, base: Vector3) -> void:
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	var steps: int = 22
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var angle: float = t * TAU * 2.5
		points.append(base + Vector3(cos(angle) * 0.56, 0.12 + t * 2.5, sin(angle) * 0.56))
		radii.append(lerpf(0.045, 0.105, smoothstep(0.0, 0.5, t)))
	kit.tube(points, radii, Color(0.34, 0.62, 0.22), 6, true, Color(0.88, 0.76, 0.20))
	var head: Vector3 = points[steps] + Vector3(0.0, 0.06, 0.0)
	kit.sphere(head, Vector3(0.15, 0.1, 0.19), Color(0.88, 0.76, 0.20), 6, 3)
	kit.box(head + Vector3(0.07, 0.09, 0.1), Vector3(0.05, 0.05, 0.05), Color(0.08, 0.06, 0.04))
	kit.box(head + Vector3(-0.07, 0.09, 0.1), Vector3(0.05, 0.05, 0.05), Color(0.08, 0.06, 0.04))


static func _add_flowers(root: Node3D, rng: RandomNumberGenerator, density: float) -> void:
	var petals: Array[Color] = [Color(1.0, 1.0, 1.0), Color(0.98, 0.88, 0.25), Color(0.95, 0.45, 0.60),
			Color(0.62, 0.45, 0.90), Color(0.95, 0.30, 0.25)]
	var kit := MeshKit.new()
	var clusters: Array[Vector2] = SceneryKit.scatter(rng, int(70.0 * density), 7.0, 38.0, _accept_spot)
	for cluster in clusters:
		var color: Color = petals[rng.randi() % petals.size()]
		for k in 6:
			var fx: float = cluster.x + rng.randf_range(-1.1, 1.1)
			var fz: float = cluster.y + rng.randf_range(-1.1, 1.1)
			PropKit.flower(kit, Vector3(fx, height_at(fx, fz) - 0.02, fz), color)
	root.add_child(kit.instance(TextureKit.plain(0.9), "Flowers"))


static func _add_water(root: Node3D, rng: RandomNumberGenerator) -> void:
	var path := PackedVector3Array()
	path.append(Vector3(-23.0, WATER_Y, -17.8))
	path.append(Vector3(-22.6, WATER_Y, -13.5))
	var z: float = -9.0
	while z <= 78.0:
		path.append(Vector3(river_x(z), WATER_Y, z))
		z += 3.0
	var river := MeshInstance3D.new()
	river.name = "River"
	river.mesh = WaterKit.ribbon(path, 4.4)
	river.material_override = WaterKit.water_material(Color(0.10, 0.42, 0.58, 0.90),
			Color(0.38, 0.78, 0.82, 0.80), 0.7, 0.5, 0.0)
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(river)

	# Cascada: láminas de agua que siguen la pendiente del acantilado.
	var fall_material: ShaderMaterial = WaterKit.fall_material(Color(0.90, 0.97, 1.0, 0.90),
			Color(0.45, 0.72, 0.92, 0.72), 1.6, 5.0)
	for i in 5:
		var z0: float = -23.6 + float(i) * 1.2
		var z1: float = z0 + 1.2
		var y0: float = height_at(-23.0, z0) + 0.6
		var y1: float = height_at(-23.0, z1) + 0.6
		var sheet := MeshInstance3D.new()
		sheet.name = "Waterfall"
		sheet.mesh = WaterKit.sheet(Vector3(-25.4, y0, z0), Vector3(-20.6, y0, z0),
				Vector3(-25.4, y1, z1), Vector3(-20.6, y1, z1), 3, 1)
		sheet.material_override = fall_material
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(sheet)
