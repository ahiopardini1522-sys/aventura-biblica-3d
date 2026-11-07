extends ScreenBase
## Escena del tablero (Etapa 1): arma el tablero 3D del mapa elegido, coloca las fichas
## en la casilla de inicio, deja el dado listo y conecta la interfaz.
## Todavía no hay turnos ni movimiento de fichas: eso llega en la siguiente etapa.

const TOKEN_SCENE := preload("res://scenes/characters/player_token.tscn")
const TOKEN_SCALE := 0.75

var map_data: Dictionary = {}
var layout: BoardLayout
var roster: Array = []

@onready var _environment: MapEnvironment = %MapEnvironment
@onready var _board: BoardBuilder = %Board
@onready var _tokens: Node3D = %Tokens
@onready var _dice: Dice = %Dice
@onready var _camera: BoardCamera = %BoardCamera
@onready var _hud: BoardHud = %Hud


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
	_environment.apply_theme(theme_data, hash(str(map_data["id"])),
			[Vector3(dice_spot.x, dice_spot.z, 4.0)])

	roster = GameState.build_roster()
	_spawn_tokens()

	_hud.set_map(str(map_data["name"]), str(map_data["reference"]))
	_hud.set_players(roster)
	_hud.back_pressed.connect(_on_back_requested)
	_hud.roll_pressed.connect(_on_roll_pressed)
	_hud.zoom_in_pressed.connect(_camera.zoom_by.bind(0.8))
	_hud.zoom_out_pressed.connect(_camera.zoom_by.bind(1.25))
	_hud.reset_view_pressed.connect(_camera.reset_view)
	_dice.roll_finished.connect(_on_roll_finished)

	var board_size: Vector2 = layout.board_size()
	_camera.configure(Vector3(dice_spot.x * 0.25, 0.0, 0.3), maxf(board_size.x, board_size.y))
	_camera.play_intro()


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


func _on_roll_pressed() -> void:
	if _dice.is_rolling:
		return
	_hud.set_roll_enabled(false)
	_hud.set_result("")
	_dice.roll()


func _on_roll_finished(value: int) -> void:
	_hud.set_result("Sacaste un %d" % value)
	_hud.set_roll_enabled(true)
	SettingsManager.play_confirm()
