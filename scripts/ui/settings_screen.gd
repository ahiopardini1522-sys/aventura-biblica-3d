extends ScreenBase
## Pantalla CONFIGURACIÓN: volumen, calidad gráfica y contador de FPS.
## Todo se aplica al instante y se guarda en user://settings.cfg.

const QUALITY_NAMES := ["BAJA", "MEDIA", "ALTA"]

var _quality_group := ButtonGroup.new()
var _quality_buttons: Array[Button] = []


func _ready() -> void:
	_build_quality_buttons()

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


func _build_info_text() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var engine: Dictionary = Engine.get_version_info()
	var adapter: String = RenderingServer.get_video_adapter_name()
	if adapter.is_empty():
		adapter = "sin información de GPU"
	return "Juego v%s  ·  Godot %d.%d.%d  ·  %s" % [
			version, int(engine["major"]), int(engine["minor"]), int(engine["patch"]), adapter]
