class_name VictoryHud
extends Control
## Interfaz de la pantalla de victoria: nombre del ganador, mensaje, tabla de estadísticas
## de la partida y los botones para jugar otra vez o volver al menú.

signal play_again_pressed
signal menu_pressed

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	%PlayAgainButton.pressed.connect(play_again_pressed.emit)
	%MenuButton.pressed.connect(menu_pressed.emit)
	%StatsPanel.add_theme_stylebox_override("panel",
			UiTheme.box(Color(0.04, 0.06, 0.14, 0.86), Color(UiTheme.GOLD, 0.8), 32, 3, 34.0, 24.0, true))


## Rellena la pantalla con el resumen de MatchState.summary().
func show_summary(summary: Dictionary) -> void:
	var players: Array = summary.get("players", [])
	var winner_name: String = str(summary.get("winner_name", ""))
	if players.size() <= 1:
		%WinnerLabel.text = "¡%s llegó a la meta!" % winner_name
	else:
		%WinnerLabel.text = "¡%s ganó la partida!" % winner_name
	%MessageLabel.text = MessageBank.pick("victory", _rng)
	_build_table(players)
	%SummaryLabel.text = "Turnos: %d  ·  Duración: %s  ·  Tiradas: %d\nDesafíos: %d  ·  Respuestas correctas: %d" % [
			int(summary.get("turns", 0)), format_duration(float(summary.get("duration", 0.0))),
			int(summary.get("total_rolls", 0)), int(summary.get("total_challenges", 0)),
			int(summary.get("total_correct", 0))]


## Entrada animada de los elementos principales.
func play_intro() -> void:
	UiFx.fade_scale_in([%TitleLabel, %WinnerLabel, %MessageLabel, %StatsPanel,
			%PlayAgainButton, %MenuButton], 0.14, 0.5)


func winner_text() -> String:
	return (%WinnerLabel as Label).text


func summary_text() -> String:
	return (%SummaryLabel as Label).text


func row_count() -> int:
	return maxi(0, floori(float((%Table as GridContainer).get_child_count()) / 4.0) - 1)


static func format_duration(seconds: float) -> String:
	var total: int = int(seconds)
	return "%d:%02d" % [floori(float(total) / 60.0), total % 60]


func _build_table(players: Array) -> void:
	var table := %Table as GridContainer
	for child in table.get_children():
		table.remove_child(child)
		child.queue_free()
	for title in ["JUGADOR", "CASILLA", "ESTRELLAS", "ACIERTOS"]:
		var header := Label.new()
		header.text = title
		header.theme_type_variation = &"DimLabel"
		header.add_theme_font_size_override("font_size", 24)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if title == "JUGADOR" else HORIZONTAL_ALIGNMENT_CENTER
		if title == "JUGADOR":
			header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		table.add_child(header)
	for entry in players:
		_add_row(table, entry)


func _add_row(table: GridContainer, entry: Dictionary) -> void:
	var stats: Dictionary = entry["stats"]
	var color: Color = entry["color"]
	var is_winner: bool = bool(entry["winner"])

	var who := HBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_constant_override("separation", 14)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(40.0, 40.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel",
			UiTheme.box(color, UiTheme.GOLD if is_winner else Color(1, 1, 1, 0.85), 30, 4 if is_winner else 3, 0.0, 0.0, false))
	who.add_child(dot)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = "%d.  %s" % [int(entry["rank"]), str(entry["name"])]
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.add_theme_color_override("font_color", UiTheme.GOLD_LIGHT if is_winner else UiTheme.TEXT)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(name_label)
	var detail := Label.new()
	detail.theme_type_variation = &"DimLabel"
	detail.add_theme_font_size_override("font_size", 22)
	detail.text = "Mejor tirada %d  ·  Escaleras %d  ·  Serpientes %d" % [
			int(stats["best_roll"]), int(stats["ladders"]), int(stats["snakes"])]
	detail.clip_text = true
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(detail)
	who.add_child(texts)
	table.add_child(who)

	table.add_child(_value_label(str(int(entry["tile"]))))

	var stars_cell := HBoxContainer.new()
	stars_cell.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_cell.add_theme_constant_override("separation", 6)
	stars_cell.add_child(StarIcon.new().configure(UiTheme.GOLD, true, 30.0))
	stars_cell.add_child(_value_label(str(int(entry["stars"]))))
	table.add_child(stars_cell)

	table.add_child(_value_label("%d/%d" % [int(stats["correct"]), int(stats["challenges"])]))


func _value_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 34)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label
