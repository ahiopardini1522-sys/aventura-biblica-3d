extends ScreenBase
## Lista de mapas bíblicos (se llega desde MUNDO BÍBLICO con el botón LISTA): muestra los 7
## mundos con su estado (bloqueado, disponible o completado), qué hay que completar para abrir
## cada uno, sus estadísticas y su insignia. Solo los mapas abiertos se pueden jugar.

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
		button.custom_minimum_size = Vector2(0, 88)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_map_pressed.bind(map_id))
		%MapList.add_child(button)
		_buttons[map_id] = button
		_refresh_button(map_id)
	%PlayMapButton.pressed.connect(_on_play_pressed)

	var start_id: String = GameState.selected_map_id
	if MapCatalog.find_map(start_id).is_empty():
		start_id = MapCatalog.default_map_id()
	_select(start_id)
	UiFx.fade_scale_in([%ListPanel, %DetailPanel], 0.1, 0.45)


func _button_text(map_data: Dictionary) -> String:
	var map_id: String = str(map_data["id"])
	var label: String = "%d. %s" % [int(map_data["order"]), str(map_data["name"])]
	match ProgressManager.status_of(map_id):
		ProgressData.STATUS_COMPLETED:
			return "%s  (completado)" % label
		ProgressData.STATUS_LOCKED:
			return "%s  (bloqueado)" % label
	return label


func _refresh_button(map_id: String) -> void:
	if _buttons.has(map_id):
		(_buttons[map_id] as Button).text = _button_text(MapCatalog.find_map(map_id))


func _on_map_pressed(map_id: String) -> void:
	_select(map_id)
	if GameState.can_select_map(map_id):
		GameState.select_map(map_id)


## Frase que explica qué falta para abrir un mapa bloqueado.
static func requirement_text(map_id: String) -> String:
	var needs: String = MapCatalog.requirement_of(map_id)
	if needs.is_empty():
		return ""
	return "Completa «%s» para abrir este mundo." % MapCatalog.name_of(needs)


func _select(map_id: String) -> void:
	var map_data: Dictionary = MapCatalog.find_map(map_id)
	if map_data.is_empty():
		return
	_selected_id = map_id
	if _buttons.has(map_id):
		(_buttons[map_id] as Button).set_pressed_no_signal(true)

	var status: String = ProgressManager.status_of(map_id)
	var playable: bool = GameState.can_select_map(map_id)
	%MapNameLabel.text = str(map_data["name"])
	%MapRefLabel.text = str(map_data["reference"])
	%MapDescLabel.text = str(map_data["description"])
	match status:
		ProgressData.STATUS_COMPLETED:
			%MapStatusLabel.text = "COMPLETADO"
			%MapStatusLabel.add_theme_color_override("font_color", UiTheme.OK_GREEN)
		ProgressData.STATUS_AVAILABLE:
			%MapStatusLabel.text = "DISPONIBLE"
			%MapStatusLabel.add_theme_color_override("font_color", UiTheme.GOLD)
		_:
			%MapStatusLabel.text = "BLOQUEADO  ·  %s" % requirement_text(map_id)
			%MapStatusLabel.add_theme_color_override("font_color", UiTheme.WARN_RED)

	var board: Dictionary = map_data["board"]
	%MapBoardLabel.text = "Tablero de %d x %d  ·  %d escaleras  ·  %d serpientes  ·  %d desafíos" % [
			int(board["columns"]), int(board["rows"]),
			(board["ladders"] as Array).size(), (board["snakes"] as Array).size(),
			(board["challenge_tiles"] as Array).size()]

	var stats: Dictionary = ProgressManager.region(map_id)
	if int(stats["plays"]) > 0 or int(stats["completions"]) > 0:
		%MapStatsLabel.text = "Partidas: %d  ·  Completado: %d  ·  Aciertos: %d de %d  ·  Estrellas: %d" % [
				int(stats["plays"]), int(stats["completions"]), int(stats["correct"]),
				int(stats["challenges"]), int(stats["stars"])]
	else:
		%MapStatsLabel.text = "Aún no has jugado este mundo."
	var badge: Dictionary = MapCatalog.badge_of(map_id)
	if badge.is_empty():
		%MapBadgeLabel.text = ""
	else:
		var earned: bool = ProgressManager.data.has_badge(str(badge["id"]))
		%MapBadgeLabel.text = "Insignia «%s»: %s  ·  +%d estrellas del viaje" % [
				str(badge["name"]), "ganada" if earned else "pendiente", MapCatalog.reward_stars_of(map_id)]
		%MapBadgeLabel.add_theme_color_override("font_color", UiTheme.GOLD if earned else UiTheme.TEXT_DIM)

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
	%PlayMapButton.text = "JUGAR ESTE MAPA" if playable else "BLOQUEADO"


func _on_play_pressed() -> void:
	if not GameState.can_select_map(_selected_id):
		return
	GameState.select_map(_selected_id)
	SceneRouter.go_to("board")
