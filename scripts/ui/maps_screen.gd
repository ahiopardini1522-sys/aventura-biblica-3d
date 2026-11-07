extends ScreenBase
## Pantalla MAPAS: lista los mapas bíblicos del catálogo y muestra el detalle del elegido.
## Solo los mapas con estado "available" se pueden jugar; los demás muestran "PRÓXIMAMENTE".

var _group := ButtonGroup.new()
var _buttons: Dictionary = {}
var _selected_id: String = ""


func _ready() -> void:
	for entry in MapCatalog.all_maps():
		var map_data: Dictionary = entry
		var map_id: String = str(map_data["id"])
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _group
		button.custom_minimum_size = Vector2(0, 100)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = _button_text(map_data)
		button.pressed.connect(_on_map_pressed.bind(map_id))
		%MapList.add_child(button)
		_buttons[map_id] = button
	%PlayMapButton.pressed.connect(_on_play_pressed)

	var start_id: String = GameState.selected_map_id
	if MapCatalog.find_map(start_id).is_empty():
		var all_maps: Array = MapCatalog.all_maps()
		if not all_maps.is_empty():
			start_id = str(all_maps[0]["id"])
	_select(start_id)
	UiFx.fade_scale_in([%ListPanel, %DetailPanel], 0.1, 0.45)


func _button_text(map_data: Dictionary) -> String:
	var map_name: String = str(map_data["name"])
	if str(map_data["status"]) == MapCatalog.STATUS_AVAILABLE:
		return map_name
	return "%s  (próximamente)" % map_name


func _on_map_pressed(map_id: String) -> void:
	_select(map_id)
	if MapCatalog.is_playable(map_id):
		GameState.select_map(map_id)


func _select(map_id: String) -> void:
	var map_data: Dictionary = MapCatalog.find_map(map_id)
	if map_data.is_empty():
		return
	_selected_id = map_id
	if _buttons.has(map_id):
		(_buttons[map_id] as Button).set_pressed_no_signal(true)

	var playable: bool = MapCatalog.is_playable(map_id)
	%MapNameLabel.text = str(map_data["name"])
	%MapRefLabel.text = str(map_data["reference"])
	%MapDescLabel.text = str(map_data["description"])
	%MapStatusLabel.text = "DISPONIBLE" if playable else "PRÓXIMAMENTE"
	%MapStatusLabel.add_theme_color_override("font_color",
			UiTheme.OK_GREEN if playable else UiTheme.TEXT_DIM)

	var board: Dictionary = map_data["board"]
	if playable:
		%MapBoardLabel.text = "Tablero de %d x %d  ·  %d escaleras  ·  %d serpientes" % [
				int(board["columns"]), int(board["rows"]),
				(board["ladders"] as Array).size(), (board["snakes"] as Array).size()]
	else:
		%MapBoardLabel.text = "Tablero en preparación"

	for child in %Swatches.get_children():
		%Swatches.remove_child(child)
		child.queue_free()
	var theme_data: Dictionary = map_data["theme"]
	for key in ["tile_a", "tile_b", "frame", "ground"]:
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(76, 76)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var color: Color = theme_data.get(key, Color.GRAY)
		swatch.add_theme_stylebox_override("panel", UiTheme.box(color, Color(1, 1, 1, 0.55), 18, 2, 0.0, 0.0, false))
		%Swatches.add_child(swatch)

	%PlayMapButton.disabled = not playable
	%PlayMapButton.text = "JUGAR ESTE MAPA" if playable else "PRÓXIMAMENTE"


func _on_play_pressed() -> void:
	if not MapCatalog.is_playable(_selected_id):
		return
	GameState.select_map(_selected_id)
	SceneRouter.go_to("board")
