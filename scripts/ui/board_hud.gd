class_name BoardHud
extends Control
## Interfaz táctil sobre el tablero: volver al menú, controles de la vista,
## lista de jugadores y el botón para lanzar el dado.
## Solo emite señales; quien decide qué hacer con ellas es la escena del tablero.

signal back_pressed
signal roll_pressed
signal zoom_in_pressed
signal zoom_out_pressed
signal reset_view_pressed


func _ready() -> void:
	%BackButton.pressed.connect(back_pressed.emit)
	%RollButton.pressed.connect(roll_pressed.emit)
	%ZoomInButton.pressed.connect(zoom_in_pressed.emit)
	%ZoomOutButton.pressed.connect(zoom_out_pressed.emit)
	%ResetViewButton.pressed.connect(reset_view_pressed.emit)
	%ResultLabel.text = ""


## Nombre y referencia bíblica del mapa que se está jugando.
func set_map(map_name: String, reference: String) -> void:
	%MapTitleLabel.text = map_name
	%MapRefLabel.text = reference


## Muestra la lista de jugadores (entradas de GameState.build_roster()).
func set_players(roster: Array) -> void:
	for child in %PlayersList.get_children():
		%PlayersList.remove_child(child)
		child.queue_free()
	for entry in roster:
		var player: Dictionary = entry
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(36, 36)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel",
				UiTheme.box(player["color"], Color(1, 1, 1, 0.75), 18, 2, 0.0, 0.0, false))
		var label := Label.new()
		label.text = "%d. %s" % [int(player["index"]) + 1, str(player["name"])]
		label.add_theme_font_size_override("font_size", 32)
		row.add_child(dot)
		row.add_child(label)
		%PlayersList.add_child(row)


## Texto grande junto al botón del dado (por ejemplo, el resultado del lanzamiento).
func set_result(text: String) -> void:
	%ResultLabel.text = text


func set_roll_enabled(enabled: bool) -> void:
	%RollButton.disabled = not enabled
