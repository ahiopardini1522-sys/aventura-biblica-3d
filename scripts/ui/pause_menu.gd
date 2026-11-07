class_name PauseMenu
extends Control
## Menú de pausa. Al abrirse detiene el juego (get_tree().paused) y al cerrarse lo reanuda.
## Reiniciar y volver al menú piden un segundo toque para evitar errores con el dedo.

signal resumed
signal restart_requested
signal menu_requested

const CONFIRM_TIME := 3.0
const RESTART_TEXT := "REINICIAR PARTIDA"
const MENU_TEXT := "MENÚ PRINCIPAL"

var _armed: Button
var _arm_tween: Tween
var _muted_from: float = -1.0


func _ready() -> void:
	%ResumeButton.pressed.connect(close)
	%SoundButton.pressed.connect(_on_sound_pressed)
	%RestartButton.pressed.connect(_on_restart_pressed)
	%MenuButton.pressed.connect(_on_menu_pressed)
	%Card.add_theme_stylebox_override("panel",
			UiTheme.box(Color(0.05, 0.08, 0.17, 0.96), Color(UiTheme.GOLD, 0.9), 40, 4, 48.0, 36.0, true))
	_refresh_sound_text()


## Abre el menú y pausa el juego. "info" es una línea de estado ("Turno 12 · 4 min").
func open(info: String = "") -> void:
	if visible:
		return
	%InfoLabel.text = info
	_disarm()
	_refresh_sound_text()
	visible = true
	get_tree().paused = true
	%Card.pivot_offset = (%Card as Control).size * 0.5
	%Card.scale = Vector2(0.92, 0.92)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(%Card, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Cierra el menú y reanuda el juego.
func close() -> void:
	if not visible:
		return
	_disarm()
	visible = false
	get_tree().paused = false
	resumed.emit()


func is_open() -> bool:
	return visible


func restart_text() -> String:
	return (%RestartButton as Button).text


func menu_text() -> String:
	return (%MenuButton as Button).text


func sound_text() -> String:
	return (%SoundButton as Button).text


## Pulsar el botón de reiniciar (para las pruebas automáticas).
func press_restart() -> void:
	_on_restart_pressed()


func press_menu() -> void:
	_on_menu_pressed()


func press_sound() -> void:
	_on_sound_pressed()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_restart_pressed() -> void:
	if _armed == %RestartButton:
		_disarm()
		get_tree().paused = false
		visible = false
		restart_requested.emit()
		return
	_arm(%RestartButton)


func _on_menu_pressed() -> void:
	if _armed == %MenuButton:
		_disarm()
		get_tree().paused = false
		visible = false
		menu_requested.emit()
		return
	_arm(%MenuButton)


## Primer toque: el botón pide confirmación durante unos segundos.
func _arm(button: Button) -> void:
	_disarm()
	_armed = button
	button.text = "¿SEGURO? TOCA DE NUEVO"
	_arm_tween = create_tween()
	_arm_tween.tween_interval(CONFIRM_TIME)
	_arm_tween.tween_callback(_disarm)


func _disarm() -> void:
	if _arm_tween != null and _arm_tween.is_valid():
		_arm_tween.kill()
	_armed = null
	%RestartButton.text = RESTART_TEXT
	%MenuButton.text = MENU_TEXT


func _on_sound_pressed() -> void:
	if SettingsManager.master_volume > 0.001:
		_muted_from = SettingsManager.master_volume
		SettingsManager.set_master_volume(0.0, false)
	else:
		SettingsManager.set_master_volume(_muted_from if _muted_from > 0.001 else SettingsManager.DEFAULT_MASTER, false)
	_refresh_sound_text()


func _refresh_sound_text() -> void:
	%SoundButton.text = "SONIDO: ACTIVADO" if SettingsManager.master_volume > 0.001 else "SONIDO: SILENCIADO"
