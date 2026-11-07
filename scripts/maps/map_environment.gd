class_name MapEnvironment
extends Node3D
## Entorno 3D de un mapa: cielo, luz del sol, suelo y decoración alrededor del tablero.
## Los colores y los elementos decorativos salen de la sección "theme" de data/maps/maps.json,
## así cada mapa bíblico futuro solo necesita sus propios datos para verse distinto.

const GROUND_Y := -0.4
const PROP_MIN_RADIUS := 11.0
const PROP_MAX_RADIUS := 46.0
# Luz de la escena del tablero. El sol y la luz ambiente se suman sobre las superficies
# horizontales; si la suma pasa de 1.2 aproximadamente, los colores claros se queman.
const SUN_ENERGY := 0.95
const AMBIENT_ENERGY := 0.5
const FOG_DENSITY := 0.003
const GROUND_DARKEN := 0.18

@onready var _world_env: WorldEnvironment = %WorldEnvironment
@onready var _sun: DirectionalLight3D = %Sun
@onready var _ground: MeshInstance3D = %Ground
@onready var _props: Node3D = %Props


func _ready() -> void:
	# El sol queda alto, a la izquierda y delante de la cámara. No es cenital para que
	# las escaleras, las serpientes y las fichas proyecten una sombra visible.
	var sun_in_sky: Vector3 = Vector3(-0.55, 0.62, 0.5).normalized()
	_sun.transform = Transform3D(Basis.looking_at(-sun_in_sky, Vector3.UP), Vector3.ZERO)
	_sun.light_energy = SUN_ENERGY
	_sun.shadow_enabled = SettingsManager.shadows_enabled()
	_ground.position = Vector3(0.0, GROUND_Y, 0.0)


## Aplica los colores del mapa y coloca la decoración. "keep_out" son zonas (x, z, radio)
## donde no se debe poner nada, por ejemplo el área del dado.
func apply_theme(theme_data: Dictionary, seed_value: int, keep_out: Array = []) -> void:
	var sky_top: Color = _color(theme_data, "sky_top", Color(0.25, 0.47, 0.80))
	var sky_horizon: Color = _color(theme_data, "sky_horizon", Color(0.96, 0.85, 0.64))
	var ground: Color = _color(theme_data, "ground", Color(0.80, 0.64, 0.40))
	var ambient: Color = _color(theme_data, "ambient", Color(1.0, 0.94, 0.84))
	var fog: Color = _color(theme_data, "fog", Color(0.95, 0.84, 0.64))
	_world_env.environment = EnvFactory.create(sky_top, sky_horizon, ground, ambient, fog,
			FOG_DENSITY, AMBIENT_ENERGY)
	_sun.light_color = _color(theme_data, "sun", Color(1.0, 0.95, 0.82))
	# El suelo es algo más oscuro que las casillas para que el tablero destaque.
	_ground.material_override = MeshFactory.material(ground.darkened(GROUND_DARKEN), 1.0)
	_build_props(theme_data, ground, seed_value, keep_out)


func prop_count() -> int:
	return _props.get_child_count()


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
