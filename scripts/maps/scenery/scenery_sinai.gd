class_name ScenerySinai
extends RefCounted
## Escenario del Monte Sinaí (Éxodo 19-20): un valle rocoso con el campamento de Israel y,
## detrás del tablero, la gran montaña con una nube sobre la cumbre y una columna de luz
## celestial. Un sendero de piedras sube por la ladera; hay peñascos, arbustos secos, las
## tablas de la ley al pie del monte, polvo en el aire, águilas y nubes bajas.

const HALF := 110.0
const FAR_Y := -0.5
const PEAK := Vector2(-8.0, -66.0)
const PEAK_HEIGHT := 50.0
const PEAK_RADIUS := 55.0
const CAMP := Vector2(17.0, -17.0)
const TABLETS := Vector2(-3.0, -27.0)
## Otras montañas de la cordillera: x, z, radio y altura.
const MASSIFS := [Vector4(-52.0, -40.0, 30.0, 22.0), Vector4(40.0, -52.0, 34.0, 28.0),
		Vector4(-95.0, 10.0, 34.0, 20.0), Vector4(92.0, 20.0, 30.0, 16.0)]


## Montaña cónica con crestas: 0 fuera de su radio y "height" en el centro.
static func _cone(x: float, z: float, center: Vector2, radius: float, height: float, sharp: float) -> float:
	var d: float = Vector2(x - center.x, z - center.y).length()
	var t: float = maxf(0.0, 1.0 - d / radius)
	var ridges: float = 1.0 + 0.12 * sin(atan2(z - center.y, x - center.x) * 5.0 + d * 0.11)
	return height * pow(t, sharp) * ridges


## Altura del terreno: valle pedregoso plano bajo el tablero y la cordillera detrás.
static func height_at(x: float, z: float) -> float:
	var radius: float = sqrt(x * x + z * z)
	var amplitude: float = lerpf(0.4, 4.5, smoothstep(14.0, 55.0, radius))
	var wave_a: float = 0.5 + 0.5 * sin(x * 0.11 + 0.7) * cos(z * 0.09 - 0.3)
	var wave_b: float = 0.5 + 0.5 * sin(x * 0.21 - z * 0.17 + 1.6)
	var h: float = TerrainKit.PLATEAU_Y + TerrainKit.board_mask(x, z) * (wave_a * 0.6 + wave_b * 0.4) * amplitude
	h += _cone(x, z, PEAK, PEAK_RADIUS, PEAK_HEIGHT, 1.2)
	for entry in MASSIFS:
		var massif: Vector4 = entry
		h += _cone(x, z, Vector2(massif.x, massif.y), massif.z, massif.w, 1.4)
	return lerpf(h, FAR_Y, SceneryKit.edge_fade(x, z, HALF))


static func _terrain_color(x: float, z: float, y: float, ground: Color) -> Color:
	var n: float = 0.5 + 0.5 * sin(x * 0.27 + z * 0.19) * sin(z * 0.23 - x * 0.15)
	var strata: float = 0.5 + 0.5 * sin(y * 1.1 + n * 1.5)
	var low: Color = ground.darkened(0.05).lerp(Color(0.66, 0.50, 0.36), n * 0.35)
	var high: Color = Color(0.60, 0.42, 0.32).lerp(Color(0.74, 0.62, 0.52), strata)
	var base: Color = low.lerp(high, smoothstep(2.0, 16.0, y))
	return base.lerp(ground, SceneryKit.edge_fade(x, z, HALF))


static func _accept_spot(x: float, z: float) -> bool:
	if Vector2(x - CAMP.x, z - CAMP.y).length() < 9.0:
		return false
	if Vector2(x - TABLETS.x, z - TABLETS.y).length() < 5.0:
		return false
	return true


static func build(root: Node3D, seed_value: int, quality: int, ground: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var density: float = SceneryKit.density(quality)

	SceneryKit.far_ground(root, ground, FAR_Y)
	SceneryKit.terrain(root, HALF, 64, height_at, _terrain_color.bind(ground), "dirt", 0.4)
	SceneryKit.far_mountains(root, rng, 7, Color(0.62, 0.52, 0.50), FAR_Y)

	_add_land(root, rng, density)
	_add_summit(root, rng)

	FxKit.birds(root, rng, 2, Vector3(-8.0, 0.0, -40.0), 20.0, 26.0, Color(0.30, 0.25, 0.20))
	FxKit.clouds(root, rng, 4 if quality <= 0 else 7, 24.0, 46.0, 130.0, Color(0.96, 0.95, 0.98, 0.85))
	FxKit.floaters(root, "Dust", Vector3(2.0, 2.0, -4.0), Vector3(26.0, 2.0, 20.0),
			int(26.0 * density), 0.9, Color(0.86, 0.72, 0.56, 0.32), 0.02, 9.0)


## Peñascos, arbustos secos, el sendero de piedras, el campamento y las tablas de la ley.
static func _add_land(root: Node3D, rng: RandomNumberGenerator, density: float) -> void:
	var kit := MeshKit.new()
	var glow := MeshKit.new()

	var rock_colors: Array[Color] = [Color(0.58, 0.46, 0.38), Color(0.66, 0.54, 0.44), Color(0.50, 0.42, 0.38)]
	for spot in SceneryKit.scatter(rng, int(58.0 * density), 9.0, 62.0, _accept_spot):
		var size: float = rng.randf_range(0.8, 3.2)
		PropKit.rock(kit, rng, Vector3(spot.x, height_at(spot.x, spot.y) - 0.1, spot.y), size,
				rock_colors[rng.randi() % rock_colors.size()])
	for spot in SceneryKit.scatter(rng, int(24.0 * density), 8.0, 45.0, _accept_spot):
		PropKit.bush(kit, rng, Vector3(spot.x, height_at(spot.x, spot.y), spot.y), rng.randf_range(0.9, 1.6),
				Color(0.52, 0.48, 0.28))

	# Sendero de piedras que sube en espiral por la montaña.
	var stone := Color(0.80, 0.72, 0.60)
	var steps: int = 56
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var angle: float = lerpf(PI * 0.15, PI * 4.4, t)
		var radius: float = lerpf(43.0, 4.0, t)
		var x: float = PEAK.x + cos(angle) * radius
		var z: float = PEAK.y + sin(angle) * radius
		kit.box(Vector3(x, height_at(x, z) + 0.1, z), Vector3(1.7, 0.7, 1.7), MeshKit.vary_color(stone, 0.04, rng))

	_add_camp(kit, glow, rng)
	_add_tablets(kit, glow)
	root.add_child(kit.instance(TextureKit.plain(0.95), "Land"))
	root.add_child(glow.instance(TextureKit.glow_vertex(true), "Glow"))


## Tiendas de pastor en círculo alrededor de una fogata.
static func _add_camp(kit: MeshKit, glow: MeshKit, rng: RandomNumberGenerator) -> void:
	var colors: Array[Color] = [Color(0.86, 0.78, 0.62), Color(0.60, 0.42, 0.28), Color(0.78, 0.66, 0.48),
			Color(0.45, 0.36, 0.30)]
	for i in 9:
		var angle: float = TAU * float(i) / 9.0 + rng.randf_range(-0.15, 0.15)
		var radius: float = rng.randf_range(4.2, 6.5)
		var x: float = CAMP.x + cos(angle) * radius
		var z: float = CAMP.y + sin(angle) * radius
		var facing: float = atan2(-cos(angle), -sin(angle))
		PropKit.tent(kit, Vector3(x, height_at(x, z) - 0.05, z), facing, rng.randf_range(1.2, 1.6),
				colors[rng.randi() % colors.size()])
	var fire_y: float = height_at(CAMP.x, CAMP.y)
	kit.cylinder(Vector3(CAMP.x, fire_y - 0.05, CAMP.y), 0.8, 0.7, 0.2, 8, Color(0.34, 0.31, 0.29))
	kit.beam(Vector3(CAMP.x - 0.5, fire_y + 0.25, CAMP.y - 0.2), Vector3(CAMP.x + 0.5, fire_y + 0.3, CAMP.y + 0.2),
			0.14, 0.14, PropKit.DARK_WOOD)
	kit.beam(Vector3(CAMP.x - 0.4, fire_y + 0.3, CAMP.y + 0.3), Vector3(CAMP.x + 0.4, fire_y + 0.25, CAMP.y - 0.3),
			0.14, 0.14, PropKit.DARK_WOOD)
	glow.cone(Vector3(CAMP.x, fire_y + 0.2, CAMP.y), 0.5, 1.1, 6, Color(1.0, 0.58, 0.14, 0.9))
	glow.sphere(Vector3(CAMP.x, fire_y + 0.55, CAMP.y), Vector3(0.22, 0.3, 0.22), Color(1.0, 0.9, 0.5, 0.9), 6, 3)


## Las dos tablas de piedra sobre una roca, con un resplandor dorado.
static func _add_tablets(kit: MeshKit, glow: MeshKit) -> void:
	var y: float = height_at(TABLETS.x, TABLETS.y)
	kit.cylinder(Vector3(TABLETS.x, y - 0.1, TABLETS.y), 1.5, 1.1, 0.8, 7, Color(0.55, 0.47, 0.40))
	var slate := Color(0.88, 0.86, 0.80)
	kit.box(Vector3(TABLETS.x - 0.35, y + 1.35, TABLETS.y), Vector3(0.6, 1.1, 0.14), slate)
	kit.box(Vector3(TABLETS.x + 0.35, y + 1.35, TABLETS.y), Vector3(0.6, 1.1, 0.14), slate.darkened(0.04))
	glow.sphere(Vector3(TABLETS.x, y + 1.5, TABLETS.y), Vector3(1.3, 1.5, 0.6), Color(1.0, 0.88, 0.45, 0.22), 8, 4)


## Nube sobre la cumbre y columna de luz celestial que sube de ella.
static func _add_summit(root: Node3D, rng: RandomNumberGenerator) -> void:
	var cap := MeshKit.new()
	var top := Vector3(PEAK.x, PEAK_HEIGHT * 0.88 + 3.0, PEAK.y)
	for i in 10:
		var angle: float = TAU * float(i) / 10.0 + rng.randf_range(-0.3, 0.3)
		var dist: float = rng.randf_range(4.0, 12.0)
		var puff: float = rng.randf_range(5.0, 9.0)
		cap.sphere(top + Vector3(cos(angle) * dist, rng.randf_range(-2.5, 3.0), sin(angle) * dist),
				Vector3(puff * 1.3, puff * 0.6, puff * 1.1), Color(0.93, 0.93, 0.97, 0.88), 8, 4, 0.1, rng, PI,
				Color(0.55, 0.57, 0.66, 0.88))
	root.add_child(cap.instance(TextureKit.glow_vertex(false), "SummitCloud"))
	FxKit.beam(root, top, 70.0, 2.6, 10.0, Color(1.0, 0.90, 0.55, 0.40), 8)
	FxKit.glow_ball(root, top + Vector3(0.0, 6.0, 0.0), 3.5, Color(1.0, 0.92, 0.55, 0.45))
