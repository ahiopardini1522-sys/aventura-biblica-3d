extends ScreenBase
## Pantalla CONFIGURACIÓN: volumen, calidad gráfica, contador de FPS y reglas del juego
## (desafíos, premio por acertar, penalización por fallar y tirada exacta en la meta).
## Todo se aplica al instante y se guarda en user://settings.cfg.

const QUALITY_NAMES := ["BAJA", "MEDIA", "ALTA"]
const REWARD_NAMES := ["SOLO ESTRELLAS", "AVANZAR", "TIRADA EXTRA"]
const PENALTY_NAMES := ["NINGUNA", "RETROCEDER", "PERDER TURNO"]

var _quality_group := ButtonGroup.new()
var _quality_buttons: Array[Button] = []
var _tab_group := ButtonGroup.new()
var _reward_group := ButtonGroup.new()
var _reward_buttons: Array[Button] = []
var _penalty_group := ButtonGroup.new()
var _penalty_buttons: Array[Button] = []
var _reward_steps_label: Label
var _reward_minus: Button
var _reward_plus: Button
var _penalty_steps_label: Label
var _penalty_minus: Button
var _penalty_plus: Button


func _ready() -> void:
	_build_quality_buttons()
	_build_rules()
	_build_tabs()

	%MasterSlider.value_changed.connect(_on_slider_changed.bind("master"))
	%MusicSlider.value_changed.connect(_on_slider_changed.bind("music"))
	%SfxSlider.value_changed.connect(_on_slider_changed.bind("sfx"))
	%MasterSlider.drag_ended.connect(_on_drag_ended)
	%MusicSlider.drag_ended.connect(_on_drag_ended)
	%SfxSlider.drag_ended.connect(_on_drag_ended)

	%TestSoundButton.pressed.connect(SettingsManager.play_confirm)
	%FpsButton.toggled.connect(_on_fps_toggled)
	%ResetButton.pressed.connect(_on_reset_pressed)

	%InfoLabel.text = _build_info_text()
	_refresh()
	_refresh_rules()
	UiFx.fade_scale_in([%AudioPanel, %VideoPanel], 0.1, 0.45)


func _exit_tree() -> void:
	SettingsManager.save()


func _build_quality_buttons() -> void:
	for level in QUALITY_NAMES.size():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _quality_group
		button.text = QUALITY_NAMES[level]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 100)
		button.pressed.connect(_on_quality_pressed.bind(level))
		%QualityRow.add_child(button)
		_quality_buttons.append(button)


# ---------------------------------------------------------------- Pestañas y reglas del juego

func _build_tabs() -> void:
	%GeneralTab.button_group = _tab_group
	%RulesTab.button_group = _tab_group
	%GeneralTab.pressed.connect(_show_tab.bind(0))
	%RulesTab.pressed.connect(_show_tab.bind(1))


func _show_tab(index: int) -> void:
	%Content.visible = index == 0
	%RulesContent.visible = index == 1
	if index == 1:
		_refresh_rules()
		UiFx.fade_scale_in([%RewardPanel, %PenaltyPanel], 0.1, 0.4)
	else:
		UiFx.fade_scale_in([%AudioPanel, %VideoPanel], 0.1, 0.4)


func _build_rules() -> void:
	_build_choice_row(%RewardRow, REWARD_NAMES, _reward_group, _reward_buttons, _on_reward_mode_pressed)
	_build_choice_row(%PenaltyRow, PENALTY_NAMES, _penalty_group, _penalty_buttons, _on_penalty_mode_pressed)
	var reward_parts: Array = _build_stepper(%RewardStepper, "Casillas que avanzas",
			_on_reward_steps.bind(-1), _on_reward_steps.bind(1))
	_reward_steps_label = reward_parts[0]
	_reward_minus = reward_parts[1]
	_reward_plus = reward_parts[2]
	var penalty_parts: Array = _build_stepper(%PenaltyStepper, "Casillas que retrocedes",
			_on_penalty_steps.bind(-1), _on_penalty_steps.bind(1))
	_penalty_steps_label = penalty_parts[0]
	_penalty_minus = penalty_parts[1]
	_penalty_plus = penalty_parts[2]
	%ChallengesToggle.toggled.connect(_on_challenges_toggled)
	%ExactToggle.toggled.connect(_on_exact_toggled)
	%RulesResetButton.pressed.connect(_on_rules_reset_pressed)


func _build_choice_row(row: HBoxContainer, names: Array, group: ButtonGroup,
		buttons: Array[Button], callback: Callable) -> void:
	for index in names.size():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = str(names[index])
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 112)
		button.pressed.connect(callback.bind(index))
		row.add_child(button)
		buttons.append(button)


## Un contador con "-" y "+": devuelve [etiqueta del valor, botón menos, botón más].
func _build_stepper(row: HBoxContainer, caption: String, on_minus: Callable, on_plus: Callable) -> Array:
	var name_label := Label.new()
	name_label.text = caption
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)
	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(96, 96)
	minus.add_theme_font_size_override("font_size", 52)
	minus.pressed.connect(on_minus)
	row.add_child(minus)
	var value := Label.new()
	value.theme_type_variation = &"ValueLabel"
	value.custom_minimum_size = Vector2(72, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(96, 96)
	plus.add_theme_font_size_override("font_size", 52)
	plus.pressed.connect(on_plus)
	row.add_child(plus)
	return [value, minus, plus]


func _refresh_rules() -> void:
	%ChallengesToggle.set_pressed_no_signal(SettingsManager.challenges_enabled)
	%ChallengesToggle.text = "DESAFÍOS: ACTIVADOS" if SettingsManager.challenges_enabled else "DESAFÍOS: DESACTIVADOS"
	%ExactToggle.set_pressed_no_signal(SettingsManager.exact_finish)
	%ExactToggle.text = "TIRADA EXACTA EN LA META: SÍ" if SettingsManager.exact_finish else "TIRADA EXACTA EN LA META: NO"
	for index in _reward_buttons.size():
		_reward_buttons[index].set_pressed_no_signal(index == SettingsManager.reward_mode)
		_reward_buttons[index].disabled = not SettingsManager.challenges_enabled
	for index in _penalty_buttons.size():
		_penalty_buttons[index].set_pressed_no_signal(index == SettingsManager.penalty_mode)
		_penalty_buttons[index].disabled = not SettingsManager.challenges_enabled
	_reward_steps_label.text = str(SettingsManager.reward_steps)
	_penalty_steps_label.text = str(SettingsManager.penalty_steps)
	var reward_steps_on: bool = SettingsManager.challenges_enabled \
			and SettingsManager.reward_mode == GameRules.REWARD_ADVANCE
	var penalty_steps_on: bool = SettingsManager.challenges_enabled \
			and SettingsManager.penalty_mode == GameRules.PENALTY_BACK
	_reward_minus.disabled = not reward_steps_on or SettingsManager.reward_steps <= GameRules.MIN_SHIFT
	_reward_plus.disabled = not reward_steps_on or SettingsManager.reward_steps >= GameRules.MAX_SHIFT
	_penalty_minus.disabled = not penalty_steps_on or SettingsManager.penalty_steps <= GameRules.MIN_SHIFT
	_penalty_plus.disabled = not penalty_steps_on or SettingsManager.penalty_steps >= GameRules.MAX_SHIFT


func _on_challenges_toggled(enabled: bool) -> void:
	SettingsManager.set_challenges_enabled(enabled)
	_refresh_rules()


func _on_exact_toggled(enabled: bool) -> void:
	SettingsManager.set_exact_finish(enabled)
	_refresh_rules()


func _on_reward_mode_pressed(mode: int) -> void:
	SettingsManager.set_reward_mode(mode)
	_refresh_rules()


func _on_penalty_mode_pressed(mode: int) -> void:
	SettingsManager.set_penalty_mode(mode)
	_refresh_rules()


func _on_reward_steps(direction: int) -> void:
	SettingsManager.set_reward_steps(SettingsManager.reward_steps + direction)
	_refresh_rules()


func _on_penalty_steps(direction: int) -> void:
	SettingsManager.set_penalty_steps(SettingsManager.penalty_steps + direction)
	_refresh_rules()


func _on_rules_reset_pressed() -> void:
	SettingsManager.reset_game_rules()
	SettingsManager.save()
	_refresh_rules()


# ---------------------------------------------------------------- Valores generales

## Lee los valores guardados y los muestra sin volver a dispararlos como cambios.
func _refresh() -> void:
	%MasterSlider.set_value_no_signal(SettingsManager.master_volume)
	%MusicSlider.set_value_no_signal(SettingsManager.music_volume)
	%SfxSlider.set_value_no_signal(SettingsManager.sfx_volume)
	_refresh_value_labels()
	for level in _quality_buttons.size():
		_quality_buttons[level].set_pressed_no_signal(level == SettingsManager.quality)
	%FpsButton.set_pressed_no_signal(SettingsManager.show_fps)
	_refresh_fps_text()


func _refresh_value_labels() -> void:
	%MasterValue.text = _percent(SettingsManager.master_volume)
	%MusicValue.text = _percent(SettingsManager.music_volume)
	%SfxValue.text = _percent(SettingsManager.sfx_volume)


func _refresh_fps_text() -> void:
	%FpsButton.text = "ACTIVADO" if SettingsManager.show_fps else "DESACTIVADO"


func _percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


func _on_slider_changed(value: float, which: String) -> void:
	# No se guarda en cada movimiento: se guarda al soltar el deslizador.
	match which:
		"master":
			SettingsManager.set_master_volume(value, false)
		"music":
			SettingsManager.set_music_volume(value, false)
		"sfx":
			SettingsManager.set_sfx_volume(value, false)
	_refresh_value_labels()


func _on_drag_ended(_value_changed: bool) -> void:
	SettingsManager.save()


func _on_quality_pressed(level: int) -> void:
	SettingsManager.set_quality(level)


func _on_fps_toggled(enabled: bool) -> void:
	SettingsManager.set_show_fps(enabled)
	_refresh_fps_text()


func _on_reset_pressed() -> void:
	SettingsManager.reset_to_defaults()
	_refresh()
	_refresh_rules()


func _build_info_text() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.3.0"))
	var engine: Dictionary = Engine.get_version_info()
	var adapter: String = RenderingServer.get_video_adapter_name()
	if adapter.is_empty():
		adapter = "sin información de GPU"
	return "Juego v%s  ·  Godot %d.%d.%d  ·  %s" % [
			version, int(engine["major"]), int(engine["minor"]), int(engine["patch"]), adapter]
