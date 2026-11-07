class_name BoardHud
extends Control
## Interfaz táctil sobre el tablero: turno actual, número del dado, posición y estrellas de
## cada jugador, indicador de progreso, mensajes, LANZAR DADO y PAUSAR.
## Solo emite señales y muestra lo que se le indica; quien decide qué pasa es GameFlow.

signal pause_pressed
signal roll_pressed
signal zoom_in_pressed
signal zoom_out_pressed
signal reset_view_pressed

const ROW_HEIGHT := 92.0
## Ancho máximo del texto de un aviso; si es más largo se parte en líneas.
const TOAST_MAX_TEXT_WIDTH := 980.0
## Distancia entre el borde superior de la pantalla y el aviso.
const TOAST_TOP := 236.0

var _rows: Dictionary = {}
var _roster: Array = []
var _current: int = -1
var _toast_tween: Tween
var _toast_source: String = ""
var _flash_tween: Tween
var _die_tween: Tween
var _splash_tween: Tween
var _pulse_tween: Tween
var _roll_enabled: bool = false

@onready var _progress: ProgressTrack = %Progress


func _ready() -> void:
	%PauseButton.pressed.connect(pause_pressed.emit)
	%RollButton.pressed.connect(roll_pressed.emit)
	%ZoomInButton.pressed.connect(zoom_in_pressed.emit)
	%ZoomOutButton.pressed.connect(zoom_out_pressed.emit)
	%ResetViewButton.pressed.connect(reset_view_pressed.emit)
	%ResultLabel.text = ""
	%TurnPanel.add_theme_stylebox_override("panel",
			UiTheme.box(UiTheme.GLASS, Color(1, 1, 1, 0.2), 34, 3, 28.0, 8.0, true))
	%TurnDot.add_theme_stylebox_override("panel", _circle_style(Color.WHITE))
	%ToastLabel.text = ""
	%HintLabel.text = ""
	_style_die(UiTheme.GOLD)
	_set_die_text("?")


# ---------------------------------------------------------------- Mapa y jugadores

## Nombre y referencia bíblica del mapa que se está jugando.
func set_map(map_name: String, reference: String) -> void:
	%MapLine.text = "%s  ·  %s" % [map_name, reference]


## Muestra la lista de jugadores (entradas de GameState.build_roster()) y prepara la barra
## de progreso para un tablero de "total_tiles" casillas.
func set_players(roster: Array, total_tiles: int = 100) -> void:
	_roster = roster
	_rows.clear()
	for child in %PlayersList.get_children():
		%PlayersList.remove_child(child)
		child.queue_free()
	var colors: Array = []
	for entry in roster:
		var player: Dictionary = entry
		colors.append(player["color"])
		var row: Dictionary = _make_row(player)
		_rows[int(player["index"])] = row
		%PlayersList.add_child(row["panel"])
	_progress.setup(total_tiles, colors)
	_current = -1


## Actualiza la casilla y las estrellas de un jugador (lista y barra de progreso).
func update_player(index: int, tile: int, stars: int, animated: bool = true) -> void:
	if not _rows.has(index):
		return
	var row: Dictionary = _rows[index]
	var tile_changed: bool = int(row["tile"]) != tile
	var stars_changed: bool = int(row["stars"]) != stars
	row["tile"] = tile
	row["stars"] = stars
	_refresh_row_text(row)
	(row["stars_label"] as Label).text = str(stars)
	_progress.set_tile(index, tile, animated)
	if animated and tile_changed:
		_pulse(row["tile_label"] as Control)
	if animated and stars_changed:
		_pulse(row["stars_box"] as Control, 1.3)


## Nota corta bajo el nombre de un jugador ("Pierde su turno", "¡Llegó a la meta!"...).
func set_player_note(index: int, note: String) -> void:
	if not _rows.has(index):
		return
	var row: Dictionary = _rows[index]
	row["note"] = note
	_refresh_row_text(row)


## Marca de quién es el turno: banner superior, fila resaltada y marca grande en la barra.
func set_current_player(index: int) -> void:
	_current = index
	for key in _rows.keys():
		var row: Dictionary = _rows[key]
		(row["panel"] as PanelContainer).add_theme_stylebox_override("panel",
				_row_style(int(key) == index, row["color"]))
	_progress.set_active(index)
	if not _rows.has(index):
		return
	var row_now: Dictionary = _rows[index]
	var color: Color = row_now["color"]
	%TurnLabel.text = "Turno de %s" % str(row_now["name"])
	%TurnDot.add_theme_stylebox_override("panel", _circle_style(color))
	%TurnPanel.add_theme_stylebox_override("panel",
			UiTheme.box(UiTheme.GLASS, Color(color.lightened(0.2), 0.95), 34, 4, 28.0, 8.0, true))
	_style_die(color)
	_pulse(%TurnLabel as Control, 1.12)


func current_player() -> int:
	return _current


# ---------------------------------------------------------------- Dado y botón de lanzar

## Habilita o bloquea LANZAR DADO. Mientras está habilitado palpita suavemente.
func set_roll_enabled(enabled: bool) -> void:
	_roll_enabled = enabled
	%RollButton.disabled = not enabled
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	%RollButton.modulate = Color.WHITE
	if enabled and is_inside_tree():
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(%RollButton, "modulate", Color(1.14, 1.08, 0.9), 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse_tween.tween_property(%RollButton, "modulate", Color.WHITE, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func is_roll_enabled() -> bool:
	return _roll_enabled


## El dado empezó a rodar: la ficha del número muestra una interrogación.
func begin_roll() -> void:
	_set_die_text("?")
	%ResultLabel.text = ""


## Muestra el número que salió, grande, en el recuadro del dado.
func show_die_value(value: int, caption: String = "") -> void:
	_set_die_text(str(value))
	%ResultLabel.text = caption
	_pop(%DieBadge as Control)


func die_text() -> String:
	return (%DieLabel as Label).text


func result_text() -> String:
	return (%ResultLabel as Label).text


## Texto de ayuda junto al botón de lanzar ("Toca LANZAR DADO", "Moviendo a Ana..."...).
func set_hint(text: String) -> void:
	%HintLabel.text = text


func hint_text() -> String:
	return (%HintLabel as Label).text


# ---------------------------------------------------------------- Mensajes y efectos

## Mensaje flotante en la parte alta del tablero (motivador, resultado de una casilla...).
func show_toast(text: String, accent: Color = UiTheme.GOLD, seconds: float = 2.8) -> void:
	if text.is_empty():
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_source = text
	var label := %ToastLabel as Label
	# El texto se parte en líneas aquí mismo: una etiqueta con ajuste automático no tiene ancho
	# propio dentro del panel y se encogía hasta mostrar una letra por renglón.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text = _wrap_lines(text, label.get_theme_font("font"),
			label.get_theme_font_size("font_size"), TOAST_MAX_TEXT_WIDTH)
	%Toast.add_theme_stylebox_override("panel",
			UiTheme.box(Color(0.04, 0.06, 0.14, 0.9), Color(accent, 0.95), 30, 4, 36.0, 18.0, true))
	# Se centra arriba con el tamaño exacto del texto.
	var panel_size: Vector2 = (%Toast as Control).get_combined_minimum_size()
	(%Toast as Control).offset_left = -panel_size.x * 0.5
	(%Toast as Control).offset_right = panel_size.x * 0.5
	(%Toast as Control).offset_top = TOAST_TOP
	(%Toast as Control).offset_bottom = TOAST_TOP + panel_size.y
	%Toast.visible = true
	%Toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(%Toast, "modulate:a", 1.0, 0.22)
	_toast_tween.tween_interval(maxf(seconds, 0.2))
	_toast_tween.tween_property(%Toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(_hide_toast)


func hide_toast() -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_hide_toast()


func toast_text() -> String:
	return _toast_source if (%Toast as Control).visible else ""


func is_toast_visible() -> bool:
	return (%Toast as Control).visible


## Destello de color sobre toda la pantalla (verde al acertar, rojo al fallar, dorado al ganar).
func flash(color: Color, alpha: float = 0.3, seconds: float = 0.5) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	%Flash.color = Color(color, alpha)
	_flash_tween = create_tween()
	_flash_tween.tween_property(%Flash, "color:a", 0.0, maxf(seconds, 0.05)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Anuncio grande y breve del turno ("TURNO DE ANA"), con el color del jugador.
func show_turn_splash(player_name: String, color: Color) -> void:
	if _splash_tween != null and _splash_tween.is_valid():
		_splash_tween.kill()
	var label := %Splash as Label
	label.text = "TURNO DE %s" % player_name.to_upper()
	label.add_theme_color_override("font_color", color.lightened(0.35))
	label.visible = true
	label.modulate.a = 0.0
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.7, 0.7)
	_splash_tween = create_tween()
	_splash_tween.set_parallel(true)
	_splash_tween.tween_property(label, "modulate:a", 1.0, 0.18)
	_splash_tween.tween_property(label, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_splash_tween.chain().tween_interval(0.55)
	_splash_tween.chain().tween_property(label, "modulate:a", 0.0, 0.3)
	_splash_tween.chain().tween_callback(_hide_splash)


func is_splash_visible() -> bool:
	return (%Splash as Control).visible


# ---------------------------------------------------------------- Consultas (pruebas)

func row_count() -> int:
	return _rows.size()


func row_tile(index: int) -> int:
	return int((_rows[index] as Dictionary)["tile"]) if _rows.has(index) else -1


func row_stars(index: int) -> int:
	return int((_rows[index] as Dictionary)["stars"]) if _rows.has(index) else -1


func row_tile_text(index: int) -> String:
	return ((_rows[index] as Dictionary)["tile_label"] as Label).text if _rows.has(index) else ""


func row_is_highlighted(index: int) -> bool:
	return _rows.has(index) and index == _current


func turn_text() -> String:
	return (%TurnLabel as Label).text


func progress() -> ProgressTrack:
	return _progress


# ---------------------------------------------------------------- Interno

func _make_row(player: Dictionary) -> Dictionary:
	var color: Color = player["color"]
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	panel.add_theme_stylebox_override("panel", _row_style(false, color))

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 14)
	panel.add_child(line)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(44.0, 44.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", _circle_style(color))
	line.add_child(dot)

	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	line.add_child(texts)

	var name_label := Label.new()
	name_label.text = "%d. %s" % [int(player["index"]) + 1, str(player["name"])]
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(name_label)

	var tile_label := Label.new()
	tile_label.theme_type_variation = &"DimLabel"
	tile_label.add_theme_font_size_override("font_size", 24)
	tile_label.clip_text = true
	tile_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(tile_label)

	var stars_box := HBoxContainer.new()
	stars_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stars_box.add_theme_constant_override("separation", 6)
	stars_box.add_child(StarIcon.new().configure(UiTheme.GOLD, true, 30.0))
	var stars_label := Label.new()
	stars_label.text = "0"
	stars_label.add_theme_font_size_override("font_size", 32)
	stars_label.add_theme_color_override("font_color", UiTheme.GOLD_LIGHT)
	stars_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars_box.add_child(stars_label)
	line.add_child(stars_box)

	var row: Dictionary = {
		"panel": panel,
		"name": str(player["name"]),
		"color": color,
		"tile": 1,
		"stars": 0,
		"note": "",
		"tile_label": tile_label,
		"stars_label": stars_label,
		"stars_box": stars_box,
	}
	_refresh_row_text(row)
	return row


func _refresh_row_text(row: Dictionary) -> void:
	var text: String = "Casilla %d" % int(row["tile"])
	var note: String = str(row["note"])
	if not note.is_empty():
		text += "  ·  " + note
	(row["tile_label"] as Label).text = text


func _row_style(active: bool, color: Color) -> StyleBoxFlat:
	if active:
		return UiTheme.box(Color(color.darkened(0.55), 0.62), Color(UiTheme.GOLD, 0.98), 24, 4, 16.0, 8.0, false)
	return UiTheme.box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.14), 24, 2, 16.0, 8.0, false)


func _circle_style(color: Color) -> StyleBoxFlat:
	return UiTheme.box(color, Color(1, 1, 1, 0.92), 30, 3, 0.0, 0.0, false)


func _style_die(color: Color) -> void:
	%DieBadge.add_theme_stylebox_override("panel",
			UiTheme.box(color.lightened(0.12), Color(1, 1, 1, 0.95), 30, 5, 0.0, 0.0, true))
	var dark_text: bool = color.lightened(0.12).get_luminance() > 0.42
	%DieLabel.add_theme_color_override("font_color", UiTheme.INK if dark_text else Color.WHITE)


func _set_die_text(text: String) -> void:
	%DieLabel.text = text


func _pop(control: Control) -> void:
	if _die_tween != null and _die_tween.is_valid():
		_die_tween.kill()
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(0.55, 0.55)
	_die_tween = create_tween()
	_die_tween.tween_property(control, "scale", Vector2.ONE, 0.38) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pulse(control: Control, amount: float = 1.18) -> void:
	if control == null or not control.is_inside_tree():
		return
	control.pivot_offset = control.size * 0.5
	var tween: Tween = control.create_tween()
	tween.tween_property(control, "scale", Vector2(amount, amount), 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_toast() -> void:
	%Toast.visible = false
	%Toast.modulate.a = 0.0


## Parte el texto en líneas de como máximo max_width píxeles, respetando los saltos que ya trae.
static func _wrap_lines(text: String, font: Font, font_size: int, max_width: float) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for paragraph in text.split("\n"):
		var line: String = ""
		for word in paragraph.split(" ", false):
			var candidate: String = word if line.is_empty() else line + " " + word
			if line.is_empty() or font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= max_width:
				line = candidate
			else:
				lines.append(line)
				line = word
		lines.append(line)
	return "\n".join(lines)


func _hide_splash() -> void:
	%Splash.visible = false
	%Splash.modulate.a = 0.0
