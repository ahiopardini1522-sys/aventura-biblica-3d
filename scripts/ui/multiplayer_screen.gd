extends ScreenBase
## Pantalla MULTIJUGADOR. Etapa 1: partida local (1 a 4 jugadores en el mismo dispositivo).
## La partida en línea queda indicada como "próximamente"; su estructura se agregará después.


func _ready() -> void:
	%MinusButton.pressed.connect(_change_count.bind(-1))
	%PlusButton.pressed.connect(_change_count.bind(1))
	%PlayLocalButton.pressed.connect(_on_play_pressed)
	_refresh()
	UiFx.fade_scale_in([%LocalPanel, %OnlinePanel], 0.1, 0.45)


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
