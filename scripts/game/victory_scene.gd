extends ScreenBase
## Pantalla de victoria 3D: un podio con las fichas de los jugadores en el orden en que
## terminaron, la del ganador saltando de alegría bajo una copa dorada que gira, confeti y
## fuegos artificiales, y a la derecha las estadísticas de la partida con los botones para
## jugar otra vez o volver al menú.

const TOKEN_SCENE := preload("res://scenes/characters/player_token.tscn")
const STEP_WIDTH := 1.5
const STEP_PITCH := 1.72
const STEP_HEIGHTS: Array[float] = [1.7, 1.15, 0.8, 0.45]
const STEP_COLORS: Array[Color] = [
	Color(1.0, 0.80, 0.28),
	Color(0.78, 0.80, 0.86),
	Color(0.80, 0.52, 0.30),
	Color(0.55, 0.60, 0.68),
]
const TOKEN_SCALE := 1.5
const CAMERA_DISTANCE := 10.6
const CAMERA_HEIGHT := 3.5
const LOOK_AT := Vector3(3.6, 2.35, 0.0)
const FIREWORK_COLORS: Array[Color] = [
	Color(1.0, 0.84, 0.40),
	Color(1.0, 0.45, 0.40),
	Color(0.50, 0.80, 1.0),
	Color(0.60, 0.95, 0.55),
	Color(0.85, 0.60, 1.0),
]

var summary: Dictionary = {}
var tokens: Array[PlayerToken] = []

var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _fireworks_tween: Tween
var _fireworks_count: int = 0
var _winner_spot: Vector3 = Vector3.ZERO

@onready var _environment: MapEnvironment = %MapEnvironment
@onready var _stage: Node3D = %Stage
@onready var _effects: Node3D = %Effects
@onready var _camera: Camera3D = %Camera
@onready var _hud: VictoryHud = %Hud


func _ready() -> void:
	_rng.randomize()
	GameState.ensure_valid_selection()
	summary = GameState.last_summary
	if summary.is_empty():
		summary = _fallback_summary()
	var map_data: Dictionary = MapCatalog.find_map(GameState.selected_map_id)
	if not map_data.is_empty():
		_environment.apply_theme(map_data["theme"], hash(str(map_data["id"])),
				[Vector3(0.0, 0.0, 9.0)])

	_build_podium()
	_hud.show_summary(summary)
	_hud.play_again_pressed.connect(_on_play_again)
	_hud.menu_pressed.connect(_on_menu)
	_hud.play_intro()
	_update_camera()
	_start_celebration()


func _process(delta: float) -> void:
	_time += delta
	_update_camera()


func _exit_tree() -> void:
	if _fireworks_tween != null and _fireworks_tween.is_valid():
		_fireworks_tween.kill()


## Lugar del ganador en el podio (para las pruebas automáticas).
func winner_spot() -> Vector3:
	return _winner_spot


func fireworks_launched() -> int:
	return _fireworks_count


func _on_play_again() -> void:
	SceneRouter.go_to("board")


func _on_menu() -> void:
	SceneRouter.go_back()


# ---------------------------------------------------------------- Podio

func _build_podium() -> void:
	var ranked: Array = summary.get("players", [])
	var count: int = mini(ranked.size(), STEP_HEIGHTS.size())
	# Posición de cada puesto: 1.º al centro, 2.º a la izquierda, 3.º a la derecha, 4.º más a la izquierda.
	var slots: Array[float] = [0.0, -STEP_PITCH, STEP_PITCH, -STEP_PITCH * 2.0]
	var low: float = 0.0
	var high: float = 0.0
	for rank in count:
		low = minf(low, slots[rank])
		high = maxf(high, slots[rank])
	var shift: float = -(low + high) * 0.5

	_stage.position = Vector3(shift, -0.3, 0.0)
	for rank in count:
		var entry: Dictionary = ranked[rank]
		_build_step(rank, slots[rank], entry)
	_winner_spot = Vector3(slots[0] + shift, STEP_HEIGHTS[0] - 0.3, 0.0)
	if count > 0:
		_build_trophy(Vector3(slots[0], STEP_HEIGHTS[0] + 3.2, 0.0))


func _build_step(rank: int, x: float, entry: Dictionary) -> void:
	var height: float = STEP_HEIGHTS[rank]
	var step_color: Color = STEP_COLORS[rank]
	var step_mesh := BoxMesh.new()
	step_mesh.size = Vector3(STEP_WIDTH, height, STEP_WIDTH)
	var step := MeshInstance3D.new()
	step.name = "Step_%d" % (rank + 1)
	step.mesh = step_mesh
	step.material_override = MeshFactory.material(step_color, 0.55, 0.15)
	step.position = Vector3(x, height * 0.5, 0.0)
	_stage.add_child(step)

	var numeral := Label3D.new()
	numeral.text = str(rank + 1)
	numeral.font_size = 128
	numeral.pixel_size = 0.0075
	numeral.shaded = false
	numeral.modulate = Color(0.20, 0.12, 0.04)
	numeral.outline_size = 0
	numeral.position = Vector3(x, height * 0.5, STEP_WIDTH * 0.5 + 0.02)
	_stage.add_child(numeral)

	var color: Color = entry["color"]
	var token := TOKEN_SCENE.instantiate() as PlayerToken
	token.name = "Token_%d" % int(entry["index"])
	_stage.add_child(token)
	token.setup(entry)
	token.set_initial_visible(false)
	token.scale = Vector3.ONE * TOKEN_SCALE
	token.position = Vector3(x, height, 0.0)
	token.rotation.y = 0.0
	tokens.append(token)
	if rank == 0:
		_celebrate_loop(token)

	var name_label := Label3D.new()
	name_label.text = str(entry["name"])
	name_label.font_size = 80
	name_label.pixel_size = 0.0062
	name_label.outline_size = 18
	name_label.outline_modulate = Color(0.08, 0.05, 0.02, 0.95)
	name_label.modulate = color.lightened(0.4)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.shaded = false
	name_label.no_depth_test = true
	name_label.position = Vector3(x, height + 2.0, 0.0)
	_stage.add_child(name_label)


func _celebrate_loop(token: PlayerToken) -> void:
	if not is_instance_valid(token) or not token.is_inside_tree():
		return
	var tween: Tween = token.celebrate(2, 1.1)
	tween.finished.connect(_celebrate_loop.bind(token))


## Copa dorada que gira y flota sobre el ganador.
func _build_trophy(at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Trophy"
	root.position = at
	_stage.add_child(root)

	var gold: StandardMaterial3D = MeshFactory.material(Color(1.0, 0.80, 0.28), 0.3, 0.3)
	gold.emission_enabled = true
	gold.emission = Color(0.95, 0.62, 0.10)
	gold.emission_energy_multiplier = 0.4

	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = 0.52
	cup_mesh.bottom_radius = 0.2
	cup_mesh.height = 0.78
	cup_mesh.radial_segments = 20
	cup_mesh.rings = 1
	root.add_child(_part(cup_mesh, gold, Vector3(0.0, 0.5, 0.0)))

	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.09
	stem_mesh.bottom_radius = 0.12
	stem_mesh.height = 0.38
	stem_mesh.radial_segments = 12
	stem_mesh.rings = 1
	root.add_child(_part(stem_mesh, gold, Vector3(0.0, -0.08, 0.0)))

	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.34
	base_mesh.bottom_radius = 0.42
	base_mesh.height = 0.16
	base_mesh.radial_segments = 20
	base_mesh.rings = 1
	root.add_child(_part(base_mesh, gold, Vector3(0.0, -0.33, 0.0)))

	var handle_mesh := TorusMesh.new()
	handle_mesh.inner_radius = 0.13
	handle_mesh.outer_radius = 0.2
	handle_mesh.rings = 16
	handle_mesh.ring_segments = 8
	for side in [-1.0, 1.0]:
		var handle := _part(handle_mesh, gold, Vector3(float(side) * 0.6, 0.55, 0.0))
		handle.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		root.add_child(handle)

	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 1.0
	halo_mesh.height = 2.0
	halo_mesh.radial_segments = 16
	halo_mesh.rings = 8
	var halo := _part(halo_mesh, MeshFactory.glow_material(Color(1.0, 0.86, 0.45, 0.2)), Vector3(0.0, 0.4, 0.0))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)

	var spin: Tween = root.create_tween().set_loops()
	spin.tween_property(root, "rotation:y", TAU, 7.0).from(0.0)
	var bob: Tween = root.create_tween().set_loops()
	bob.tween_property(root, "position:y", at.y + 0.18, 1.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(root, "position:y", at.y, 1.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _part(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance


# ---------------------------------------------------------------- Fiesta y cámara

func _start_celebration() -> void:
	var center_x: float = _winner_spot.x
	Effects.confetti(_effects, Vector3(center_x + 2.0, 7.5, 0.0), Vector3(8.0, 0.2, 3.5), 150, 4.0, true)
	Effects.light_pillar(_effects, _winner_spot, Effects.GOLD, 7.0, 2.4)
	Effects.star_shower(_effects, _winner_spot + Vector3(0.0, 0.6, 0.0), Effects.GOLD, 24, 1.6, 0.28)
	_fireworks_tween = create_tween().set_loops()
	_fireworks_tween.tween_callback(_launch_fireworks)
	_fireworks_tween.tween_interval(0.9)


func _launch_fireworks() -> void:
	_fireworks_count += 1
	var color: Color = FIREWORK_COLORS[_rng.randi_range(0, FIREWORK_COLORS.size() - 1)]
	var at := Vector3(_winner_spot.x + _rng.randf_range(-6.0, 6.0), _rng.randf_range(3.5, 6.5),
			_rng.randf_range(-2.0, 1.0))
	Effects.sparkle_burst(_effects, at, color, 34, 4.6, 1.3, 0.16)
	if _fireworks_count % 3 == 0:
		Effects.star_shower(_effects, _winner_spot + Vector3(0.0, 0.6, 0.0), Effects.GOLD, 14, 1.4, 0.24)
		SettingsManager.play_star()


## La cámara mira al podio desde delante y se balancea despacio de un lado a otro.
func _update_camera() -> void:
	var sway: float = sin(_time * 0.45) * deg_to_rad(8.0)
	var pivot := Vector3(_winner_spot.x, 0.0, 0.0)
	var offset := Vector3(sin(sway) * CAMERA_DISTANCE, CAMERA_HEIGHT, cos(sway) * CAMERA_DISTANCE)
	_camera.position = pivot + offset
	_camera.look_at(pivot + LOOK_AT, Vector3.UP)


## Resumen mínimo por si se abre esta pantalla sin una partida terminada.
func _fallback_summary() -> Dictionary:
	var roster: Array = GameState.build_roster()
	var list: Array = []
	for entry in roster:
		var info: Dictionary = entry
		var rank: int = list.size() + 1
		list.append({
			"index": int(info["index"]),
			"name": str(info["name"]),
			"color": info["color"],
			"character_id": str(info["character_id"]),
			"tile": 100 if rank == 1 else 1,
			"stars": 0,
			"rank": rank,
			"winner": rank == 1,
			"stats": MatchState._new_stats(),
		})
	var first: Dictionary = list[0] if not list.is_empty() else {}
	return {
		"finished": true,
		"winner": int(first.get("index", 0)),
		"winner_name": str(first.get("name", "")),
		"winner_color": first.get("color", Color.WHITE),
		"winner_character": str(first.get("character_id", "")),
		"turns": 0,
		"duration": 0.0,
		"total_rolls": 0,
		"total_challenges": 0,
		"total_correct": 0,
		"players": list,
		"options": GameRules.default_options(),
	}
