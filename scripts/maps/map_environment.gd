class_name MapEnvironment
extends Node3D
## Entorno 3D de un mapa: cielo, luz del sol, suelo y decoración alrededor del tablero.
## Los colores y los elementos decorativos salen de la sección "theme" de data/maps/maps.json,
## así cada mapa bíblico futuro solo necesita sus propios datos para verse distinto.

const GROUND_Y := -0.4
const PROP_MIN_RADIUS := 11.0
const PROP_MAX_RADIUS := 46.0
# Luz de la escena del tablero. Con el renderizador de compatibilidad, estas energías hacen
# que las casillas se vean con los colores definidos en maps.json (ganancia cercana a 1.0
# medida sobre las capturas de GitHub Actions). Si se suben mucho, los colores se queman.
const SUN_ENERGY := 0.26
const AMBIENT_ENERGY := 0.28
const FOG_DENSITY := 0.003
const GROUND_DARKEN := 0.18

@onready var _world_env: WorldEnvironment = %WorldEnvironment
@onready var _sun: DirectionalLight3D = %Sun
@onready var _ground: MeshInstance3D = %Ground
@onready var _props: Node3D = %Props

var _scenery: Node3D


func _ready() -> void:
	# El sol queda alto, a la izquierda y delante de la cámara. No es cenital para que
	# las escaleras, las serpientes y las fichas proyecten una sombra visible.
	var sun_in_sky: Vector3 = Vector3(-0.55, 0.62, 0.5).normalized()
	_sun.transform = Transform3D(Basis.looking_at(-sun_in_sky, Vector3.UP), Vector3.ZERO)
	_sun.light_energy = SUN_ENERGY
	_sun.shadow_enabled = SettingsManager.shadows_enabled()
	_ground.position = Vector3(0.0, GROUND_Y, 0.0)


## Aplica un mapa completo: colores, iluminación propia (sección "lighting" del JSON) y el
## escenario 3D de su estilo. Es lo que usa el tablero. "keep_out" son zonas (x, z, radio)
## donde no se debe poner nada, por ejemplo el área del dado.
func apply_map(map_data: Dictionary, seed_value: int, keep_out: Array = []) -> void:
	var theme_data: Dictionary = map_data.get("theme", {})
	var lighting: Dictionary = map_data.get("lighting", {})
	apply_theme(theme_data, seed_value, keep_out, lighting)
	_build_scenery(str(map_data.get("style", "")), theme_data, seed_value)


## Aplica los colores del mapa y coloca la decoración sencilla (sin escenario propio).
func apply_theme(theme_data: Dictionary, seed_value: int, keep_out: Array = [],
		lighting: Dictionary = {}) -> void:
	var sky_top: Color = _color(theme_data, "sky_top", Color(0.25, 0.47, 0.80))
	var sky_horizon: Color = _color(theme_data, "sky_horizon", Color(0.96, 0.85, 0.64))
	var ground: Color = _color(theme_data, "ground", Color(0.80, 0.64, 0.40))
	var ambient: Color = _color(theme_data, "ambient", Color(1.0, 0.94, 0.84))
	var fog: Color = _color(theme_data, "fog", Color(0.95, 0.84, 0.64))
	var sun_energy: float = float(lighting.get("sun_energy", SUN_ENERGY))
	var ambient_energy: float = float(lighting.get("ambient_energy", AMBIENT_ENERGY))
	var fog_density: float = float(lighting.get("fog_density", FOG_DENSITY))
	var environment: Environment = EnvFactory.create(sky_top, sky_horizon, ground, ambient, fog,
			fog_density, ambient_energy)
	_sun.light_energy = sun_energy
	var direction: Variant = lighting.get("sun_dir", null)
	if direction is Array and (direction as Array).size() == 3:
		var parts: Array = direction
		var sun_in_sky := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		if sun_in_sky.length() > 0.01:
			_sun.transform = Transform3D(Basis.looking_at(-sun_in_sky.normalized(), Vector3.UP), Vector3.ZERO)
	# Tono lineal: los colores del tablero salen como están definidos en maps.json.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_world_env.environment = environment
	_sun.light_color = _color(theme_data, "sun", Color(1.0, 0.95, 0.82))
	# El suelo es algo más oscuro que las casillas para que el tablero destaque.
	_ground.material_override = MeshFactory.material(ground.darkened(GROUND_DARKEN), 1.0)
	_build_props(theme_data, ground, seed_value, keep_out)


func prop_count() -> int:
	return _props.get_child_count()


## Cantidad de piezas del escenario 3D del mapa (0 si el mapa usa solo la decoración sencilla).
func scenery_count() -> int:
	return _scenery.get_child_count() if _scenery != null else 0


## Construye el escenario del estilo del mapa y, si lo tiene, oculta el suelo liso antiguo
## (el escenario trae su propio terreno).
func _build_scenery(style: String, theme_data: Dictionary, seed_value: int) -> void:
	if _scenery != null:
		remove_child(_scenery)
		_scenery.queue_free()
		_scenery = null
	_ground.visible = true
	if not SceneryFactory.has_scenery(style):
		return
	_scenery = Node3D.new()
	_scenery.name = "Scenery"
	add_child(_scenery)
	SceneryFactory.build(style, _scenery, seed_value, SettingsManager.quality, theme_data)
	_ground.visible = false


func _build_props(theme_data: Dictionary, ground: Color, seed_value: int, keep_out: Array) -> void:
	for child in _props.get_children():
		_props.remove_child(child)
		child.queue_free()

	var wanted: Array = []
	var raw: Variant = theme_data.get("props", [])
	if raw is Array:
		wanted = raw

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if wanted.has("dune"):
		_scatter(rng, "dune", 7, 30.0, 52.0, keep_out, ground)
	if wanted.has("rock"):
		_scatter(rng, "rock", 14, PROP_MIN_RADIUS, 40.0, keep_out, ground)
	if wanted.has("palm"):
		_scatter(rng, "palm", 10, PROP_MIN_RADIUS, 36.0, keep_out, ground)


## Coloca "count" elementos en un anillo alrededor del tablero, evitando las zonas prohibidas
## y la franja entre el tablero y la cámara para no tapar la vista.
func _scatter(rng: RandomNumberGenerator, kind: String, count: int, min_radius: float,
		max_radius: float, keep_out: Array, ground: Color) -> void:
	var placed: int = 0
	var attempts: int = 0
	while placed < count and attempts < count * 20:
		attempts += 1
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = rng.randf_range(min_radius, max_radius)
		var x: float = cos(angle) * radius
		var z: float = sin(angle) * radius
		if z > 6.0 and absf(x) < 16.0:
			continue
		if _is_blocked(x, z, keep_out):
			continue
		var node: Node3D = _make_prop(kind, rng, ground)
		node.position.x = x
		node.position.z = z
		_props.add_child(node)
		placed += 1


func _make_prop(kind: String, rng: RandomNumberGenerator, ground: Color) -> Node3D:
	match kind:
		"dune":
			var dune: MeshInstance3D = PropFactory.dune(rng, ground)
			dune.position.y = GROUND_Y + 0.2
			return dune
		"rock":
			var rock: MeshInstance3D = PropFactory.rock(rng)
			rock.scale *= rng.randf_range(0.8, 2.0)
			rock.position.y = GROUND_Y + 0.25
			return rock
	var palm: Node3D = PropFactory.palm(rng, rng.randf_range(3.2, 4.4))
	palm.rotation.y = rng.randf_range(0.0, TAU)
	palm.scale = Vector3.ONE * rng.randf_range(1.0, 1.4)
	palm.position.y = GROUND_Y
	return palm


func _is_blocked(x: float, z: float, keep_out: Array) -> bool:
	for zone in keep_out:
		var area: Vector3 = zone
		if Vector2(x - area.x, z - area.y).length() < area.z:
			return true
	return false


func _color(theme_data: Dictionary, key: String, fallback: Color) -> Color:
	var value: Variant = theme_data.get(key, fallback)
	if value is Color:
		return value
	return fallback
