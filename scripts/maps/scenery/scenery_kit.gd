class_name SceneryKit
extends RefCounted
## Ayudas comunes de los escenarios: zonas que deben quedar libres alrededor del tablero,
## reparto aleatorio de elementos, terreno con material y suelo lejano.

## Cuánta vegetación y decoración se pone según la calidad gráfica (0 baja, 1 media, 2 alta).
static func density(quality: int) -> float:
	if quality <= 0:
		return 0.55
	if quality == 1:
		return 1.0
	return 1.3


## Verdadero si (x, z) cae sobre el tablero, su marco, la zona del dado o la franja delante del
## tablero (la que mira hacia la cámara). Ahí no se pone nada que estorbe la vista.
static func is_clear_zone(x: float, z: float, margin: float = 1.5) -> bool:
	var dx: float = absf(x - TerrainKit.PLATEAU_CENTER_X) - (TerrainKit.PLATEAU_HALF_X + margin)
	var dz: float = absf(z) - (TerrainKit.PLATEAU_HALF_Z + margin)
	if dx < 0.0 and dz < 0.0:
		return true
	if z > 5.0 and absf(x - TerrainKit.PLATEAU_CENTER_X) < 16.0:
		return true
	return false


## Puntos (x, z) al azar en un anillo alrededor del tablero. "accept(x, z) -> bool" puede
## rechazar sitios (ríos, edificios...). Si no se encuentran todos, se devuelven los que haya.
static func scatter(rng: RandomNumberGenerator, count: int, min_radius: float, max_radius: float,
		accept: Callable = Callable()) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var attempts: int = 0
	while points.size() < count and attempts < count * 40:
		attempts += 1
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = rng.randf_range(min_radius, max_radius)
		var x: float = cos(angle) * radius
		var z: float = sin(angle) * radius
		if is_clear_zone(x, z):
			continue
		if accept.is_valid() and not bool(accept.call(x, z)):
			continue
		points.append(Vector2(x, z))
	return points


## Puntos (x, z) al azar dentro de un rectángulo, separados al menos "min_gap" entre sí y fuera
## de la zona libre del tablero. "accept(x, z) -> bool" puede rechazar sitios.
static func scatter_rect(rng: RandomNumberGenerator, count: int, area: Rect2, min_gap: float,
		accept: Callable = Callable()) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var attempts: int = 0
	while points.size() < count and attempts < count * 60:
		attempts += 1
		var x: float = rng.randf_range(area.position.x, area.end.x)
		var z: float = rng.randf_range(area.position.y, area.end.y)
		if is_clear_zone(x, z):
			continue
		if accept.is_valid() and not bool(accept.call(x, z)):
			continue
		var crowded: bool = false
		for other in points:
			if Vector2(x - other.x, z - other.y).length() < min_gap:
				crowded = true
				break
		if crowded:
			continue
		points.append(Vector2(x, z))
	return points


## Terreno con textura, listo para agregar a la escena.
static func terrain(root: Node3D, half: float, cells: int, height_fn: Callable, color_fn: Callable,
		texture_kind: String, uv_scale: float = 0.3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Terrain"
	node.mesh = TerrainKit.build(half, cells, height_fn, color_fn, uv_scale)
	node.material_override = TextureKit.material(texture_kind, 1.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	return node


## Disco enorme a la altura del borde del terreno: hace que el terreno no termine en el vacío.
static func far_ground(root: Node3D, color: Color, y: float, radius: float = 320.0) -> MeshInstance3D:
	var kit := MeshKit.new()
	kit.disc(Vector3(0.0, y, 0.0), radius, color, 32)
	var node: MeshInstance3D = kit.instance(TextureKit.plain(1.0), "FarGround")
	root.add_child(node)
	return node


## Montañas lejanas azuladas en el horizonte.
static func far_mountains(root: Node3D, rng: RandomNumberGenerator, count: int, color: Color,
		y: float, min_radius: float = 150.0, max_radius: float = 210.0, height_scale: float = 1.0) -> MeshInstance3D:
	var kit := MeshKit.new()
	for i in count:
		var angle: float = TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(count)
		var distance: float = rng.randf_range(min_radius, max_radius)
		var radius: float = rng.randf_range(28.0, 46.0)
		var height: float = rng.randf_range(24.0, 42.0) * height_scale
		var tint: Color = MeshKit.vary_color(color, 0.03, rng)
		kit.cylinder(Vector3(cos(angle) * distance, y, sin(angle) * distance), radius, 0.0, height, 7, tint)
	var node: MeshInstance3D = kit.instance(TextureKit.plain(1.0), "FarMountains")
	root.add_child(node)
	return node


## Mezcla de un color con otro según t (0 a 1), por comodidad en las funciones de color.
static func mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))


## Cuánto se acerca (x, z) al borde del terreno: 0 en el centro, 1 en el borde.
static func edge_fade(x: float, z: float, half: float, width: float = 28.0) -> float:
	return smoothstep(half - width, half - 2.0, maxf(absf(x), absf(z)))
