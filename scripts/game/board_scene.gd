extends ScreenBase
## Escena del tablero: arma el tablero 3D del mapa elegido, coloca las fichas, crea la
## partida (MatchState) y le entrega todo a GameFlow, que conduce los turnos.
## También maneja la pausa (botón PAUSAR, tecla Esc y el botón atrás de Android) y el
## paso a la pantalla de victoria.

const TOKEN_SCENE := preload("res://scenes/characters/player_token.tscn")
const TOKEN_SCALE := 0.75

var map_data: Dictionary = {}
var layout: BoardLayout
var roster: Array = []
var match_state: MatchState
var token_nodes: Array[PlayerToken] = []

@onready var _environment: MapEnvironment = %MapEnvironment
@onready var _board: BoardBuilder = %Board
@onready var _tokens: Node3D = %Tokens
@onready var _dice: Dice = %Dice
@onready var _effects: Node3D = %Effects
@onready var _camera: BoardCamera = %BoardCamera
@onready var _flow: GameFlow = %Flow
@onready var _hud: BoardHud = %Hud
@onready var _panel: ChallengePanel = %ChallengePanel
@onready var _pause: PauseMenu = %PauseMenu


func _ready() -> void:
	GameState.ensure_valid_selection()
	map_data = MapCatalog.find_map(GameState.selected_map_id)
	if map_data.is_empty():
		push_error("BoardScene: no hay un mapa jugable seleccionado")
		SceneRouter.go_back()
		return

	layout = BoardLayout.from_map(map_data)
	for problem in layout.validate():
		push_error("BoardScene: %s" % problem)

	var theme_data: Dictionary = map_data["theme"]
	_board.build(layout, theme_data)
	var dice_spot: Vector3 = _board.dice_position()
	_dice.position = dice_spot
	_environment.apply_map(map_data, hash(str(map_data["id"])),
			[Vector3(dice_spot.x, dice_spot.z, 4.0)])
	_start_ambience()

	roster = GameState.build_roster()
	_spawn_tokens()

	_hud.set_map(str(map_data["name"]), str(map_data["reference"]))
	_hud.set_players(roster, layout.tile_count())
	_hud.pause_pressed.connect(_open_pause)
	_hud.roll_pressed.connect(_flow.request_roll)
	_hud.zoom_in_pressed.connect(_camera.zoom_by.bind(0.8))
	_hud.zoom_out_pressed.connect(_camera.zoom_by.bind(1.25))
	_hud.reset_view_pressed.connect(_camera.reset_view)
	_pause.restart_requested.connect(_on_restart_requested)
	_pause.menu_requested.connect(_on_menu_requested)
	_flow.match_finished.connect(_on_match_finished)

	var board_size: Vector2 = layout.board_size()
	_camera.configure(Vector3(dice_spot.x * 0.25, 0.0, 0.3), maxf(board_size.x, board_size.y))
	_camera.play_intro()

	match_state = MatchState.create(layout, roster, SettingsManager.game_options())
	_flow.board = _board
	_flow.dice = _dice
	_flow.camera = _camera
	_flow.hud = _hud
	_flow.panel = _panel
	_flow.fx = _effects
	_flow.tokens = token_nodes
	ProgressManager.record_start(str(map_data["id"]))
	_flow.start(match_state)


## Sonido ambiental del mundo (jardín, mar, viento...), en bucle y por el bus de música.
## Se genera ahora, mientras la pantalla sigue en negro, para que no haya tirones durante la partida.
func _start_ambience() -> void:
	var ambience_data: Dictionary = map_data.get("ambience", {})
	var player := AmbiencePlayer.new()
	player.name = "Ambience"
	add_child(player)
	player.start(str(ambience_data.get("sound", "")))


func _exit_tree() -> void:
	# Por si se sale de la escena con el juego en pausa: la siguiente pantalla no debe heredarla.
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false


## Una ficha por jugador, todas sobre la casilla de inicio.
func _spawn_tokens() -> void:
	var start: Vector3 = layout.tile_center(1)
	for entry in roster:
		var player: Dictionary = entry
		var slot: int = int(player["index"])
		var token := TOKEN_SCENE.instantiate() as PlayerToken
		token.name = "Token_%d" % slot
		_tokens.add_child(token)
		token.setup(player)
		token.scale = Vector3.ONE * TOKEN_SCALE
		token.position = start + BoardLayout.token_offset(slot, roster.size())
		token_nodes.append(token)


func _open_pause() -> void:
	if _pause.is_open() or _flow.is_finished():
		return
	_pause.open("Turno %d  ·  %s" % [match_state.turn_number, _format_duration(match_state.elapsed)])


## El botón atrás de Android y la tecla Esc abren la pausa, o la cierran si ya está abierta.
func _on_back_requested() -> void:
	if _pause.is_open():
		_pause.close()
	else:
		_open_pause()


func _on_restart_requested() -> void:
	SceneRouter.go_to("board")


func _on_menu_requested() -> void:
	SceneRouter.go_back()


## Al terminar la partida se anota en el progreso (estadísticas, mapa completado, recompensa,
## insignias y desbloqueos) y se guarda; la pantalla de victoria muestra el informe.
func _on_match_finished(summary: Dictionary) -> void:
	GameState.last_summary = summary
	GameState.last_progress = ProgressManager.record_match(str(map_data["id"]), summary)
	SceneRouter.go_to("victory")


static func _format_duration(seconds: float) -> String:
	var total: int = int(seconds)
	return "%d:%02d" % [floori(float(total) / 60.0), total % 60]
