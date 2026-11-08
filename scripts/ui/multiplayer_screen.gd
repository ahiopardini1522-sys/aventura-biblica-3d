extends ScreenBase
## Pantalla MULTIJUGADOR: partida local (1 a 4 jugadores en el mismo dispositivo) y, a la derecha,
## el estado de la conexión en línea (fase 4.1: prueba de conexión con el servidor).
## La conexión solo vive mientras esta pantalla está abierta.

const DOT_COLORS := {
	"idle": Color(0.62, 0.66, 0.76),
	"busy": Color(0.55, 0.75, 0.98),
	"ok": UiTheme.OK_GREEN,
	"warn": Color(0.96, 0.77, 0.33),
	"error": UiTheme.WARN_RED,
}


func _ready() -> void:
	%MinusButton.pressed.connect(_change_count.bind(-1))
	%PlusButton.pressed.connect(_change_count.bind(1))
	%PlayLocalButton.pressed.connect(_on_play_pressed)
	%ConnectButton.pressed.connect(_on_connect_pressed)
	OnlineManager.status_changed.connect(_refresh_online)
	_refresh()
	_refresh_online()
	UiFx.fade_scale_in([%LocalPanel, %OnlinePanel], 0.1, 0.45)


func _exit_tree() -> void:
	# La conexión en línea solo se mantiene mientras esta pantalla está abierta.
	if is_instance_valid(OnlineManager):
		OnlineManager.disconnect_from_server()


func _change_count(delta: int) -> void:
	GameState.set_player_count(GameState.player_count + delta)
	_refresh()


func _refresh() -> void:
	var count: int = GameState.player_count
	%CountLabel.text = str(count)
	%MinusButton.disabled = count <= GameState.MIN_PLAYERS
	%PlusButton.disabled = count >= GameState.MAX_PLAYERS

	for child in %PlayerList.get_children():
		%PlayerList.remove_child(child)
		child.queue_free()
	for entry in GameState.build_roster():
		var player: Dictionary = entry
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(44, 44)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel",
				UiTheme.box(player["color"], Color(1, 1, 1, 0.7), 22, 2, 0.0, 0.0, false))
		var label := Label.new()
		label.text = "Jugador %d  ·  %s" % [int(player["index"]) + 1, str(player["name"])]
		row.add_child(dot)
		row.add_child(label)
		%PlayerList.add_child(row)


func _on_play_pressed() -> void:
	GameState.ensure_valid_selection()
	SceneRouter.go_to("board")


# ---------------------------------------------------------------- Partida en línea

func _on_connect_pressed() -> void:
	var client: OnlineClient = OnlineManager.client
	if client.state in [OnlineClient.State.CONNECTING, OnlineClient.State.HANDSHAKE,
			OnlineClient.State.ONLINE, OnlineClient.State.WAITING]:
		OnlineManager.disconnect_from_server()
	else:
		OnlineManager.connect_to_server()
	_refresh_online()


func _refresh_online() -> void:
	var kind: String = OnlineManager.status_kind()
	%StatusLabel.text = OnlineManager.status_text()
	%DetailLabel.text = OnlineManager.detail_text()
	%DetailLabel.visible = not %DetailLabel.text.is_empty()
	var color: Color = DOT_COLORS.get(kind, DOT_COLORS["idle"])
	%StatusDot.add_theme_stylebox_override("panel",
			UiTheme.box(color, Color(1, 1, 1, 0.8), 17, 2, 0.0, 0.0, false))

	var client: OnlineClient = OnlineManager.client
	var button: Button = %ConnectButton
	if not OnlineManager.is_configured():
		button.text = "PROBAR CONEXIÓN"
		button.disabled = true
		return
	button.disabled = false
	match client.state:
		OnlineClient.State.ONLINE:
			button.text = "DESCONECTAR"
		OnlineClient.State.CONNECTING, OnlineClient.State.HANDSHAKE, OnlineClient.State.WAITING:
			button.text = "CANCELAR"
		_:
			button.text = "PROBAR CONEXIÓN"
