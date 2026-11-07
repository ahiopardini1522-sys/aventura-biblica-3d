class_name ScreenBase
extends Node
## Base de las pantallas de menú: maneja el botón "atrás" de Android (y la tecla Esc).
## Por defecto vuelve al menú principal; el menú principal lo reemplaza para salir del juego.


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_requested()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_requested()


func _on_back_requested() -> void:
	SceneRouter.go_back()
