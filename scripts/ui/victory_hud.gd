class_name VictoryHud
extends Control
## Interfaz de la pantalla de victoria: nombre del ganador, mensaje, tabla de estadísticas
## de la partida y los botones para jugar otra vez o volver al menú.

signal play_again_pressed
signal menu_pressed
signal world_pressed

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	%PlayAgainButton.pressed.connect(play_again_pressed.emit)
	%MenuButton.pressed.connect(menu_pressed.emit)
	%WorldButton.pressed.connect(world_pressed.emit)
	%StatsPanel.add_theme_stylebox_override("panel",
			UiTheme.box(Color(0.04, 0.06, 0.14, 0.86), Color(UiTheme.GOLD, 0.8), 32, 3, 34.0, 24.0, true))
	%RewardBanner.add_theme_stylebox_override("panel",
			UiTheme.box(Color(0.05, 0.07, 0.16, 0.90), Color(UiTheme.GOLD, 0.95), 30, 3, 30.0, 12.0, true))


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


## Muestra lo que el jugador ganó en el viaje con el informe de ProgressManager.record_match():
## mundo completado, estrellas, insignias nuevas y mapas que se abrieron. Si no hay nada nuevo
## que contar, se queda el mensaje motivador de siempre.
func show_progress(report: Dictionary) -> void:
	var text: Dictionary = progress_text(report)
	var banner := %RewardBanner as Control
	banner.visible = not text.is_empty()
	%MessageLabel.visible = text.is_empty()
	if text.is_empty():
		return
	%RewardTitle.text = str(text["title"])
	%RewardDetail.text = str(text["detail"])


## Textos del informe de progreso ({title, detail}), o {} si no hay nada nuevo que contar.
static func progress_text(report: Dictionary) -> Dictionary:
	if report.is_empty() or not bool(report.get("ok", false)):
		return {}
	var new_badges: Array = report.get("new_badges", [])
	var unlocked: Array = report.get("unlocked_maps", [])
	var first: bool = bool(report.get("first_completion", false))
	if not first and new_badges.is_empty() and unlocked.is_empty():
		return {}
	var map_name: String = MapCatalog.name_of(str(report.get("map_id", "")))
	var title: String = "¡%s completado!" % map_name if first else "¡Nueva insignia!"
	var parts: PackedStringArray = PackedStringArray()
	if first and int(report.get("reward_stars", 0)) > 0:
		parts.append("+%d estrellas del viaje" % int(report["reward_stars"]))
	if not new_badges.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for entry in new_badges:
			names.append("«%s»" % str((entry as Dictionary).get("name", "")))
		parts.append(("Insignia: " if names.size() == 1 else "Insignias: ") + ", ".join(names))
	if not unlocked.is_empty():
		var opened: PackedStringArray = PackedStringArray()
		for id in unlocked:
			opened.append(MapCatalog.name_of(str(id)))
		parts.append(("Se abrió: " if opened.size() == 1 else "Se abrieron: ") + ", ".join(opened))
	parts.append("Viaje: %d de %d mundos" % [int(report.get("completed", 0)), int(report.get("total", 0))])
	return {"title": title, "detail": "  ·  ".join(parts)}


func reward_visible() -> bool:
	return (%RewardBanner as Control).visible


func reward_title() -> String:
	return (%RewardTitle as Label).text


func reward_detail() -> String:
	return (%RewardDetail as Label).text


## Entrada animada de los elementos principales.
func play_intro() -> void:
	var items: Array = [%TitleLabel, %WinnerLabel, %StatsPanel, %PlayAgainButton, %WorldButton, %MenuButton]
	items.insert(2, %RewardBanner if (%RewardBanner as Control).visible else %MessageLabel)
	UiFx.fade_scale_in(items, 0.14, 0.5)


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
