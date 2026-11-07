class_name UiFx
extends RefCounted
## Efectos de interfaz reutilizables: respuesta al toque, sonido y animaciones de entrada.

const PRESS_SCALE := Vector2(0.96, 0.96)


## Se aplica a todos los botones (lo hace SceneRouter al detectar cada nuevo botón).
static func polish_button(button: BaseButton) -> void:
	if button.has_meta(&"ui_fx"):
		return
	button.set_meta(&"ui_fx", true)
	button.pressed.connect(_on_button_pressed)
	button.button_down.connect(_animate_scale.bind(button, PRESS_SCALE))
	button.button_up.connect(_animate_scale.bind(button, Vector2.ONE))
	button.resized.connect(_update_pivot.bind(button))
	_update_pivot(button)


## Aparece cada elemento con un pequeño retraso escalonado (fundido + leve escala).
## Los elementos quedan invisibles de inmediato y se animan en cuanto el diseño está listo.
static func fade_scale_in(items: Array, step: float = 0.07, duration: float = 0.45) -> void:
	var controls: Array = []
	for item in items:
		var control := item as Control
		if control != null and control.is_inside_tree():
			control.modulate.a = 0.0
			controls.append(control)
	if controls.is_empty():
		return
	var tree: SceneTree = (controls[0] as Control).get_tree()
	await tree.process_frame
	var delay: float = 0.0
	for control in controls:
		if not is_instance_valid(control) or not control.is_inside_tree():
			continue
		control.scale = Vector2(0.94, 0.94)
		control.pivot_offset = control.size * 0.5
		var tween: Tween = control.create_tween()
		tween.set_parallel(true)
		tween.tween_property(control, "modulate:a", 1.0, duration).set_delay(delay)
		tween.tween_property(control, "scale", Vector2.ONE, duration) \
			.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		delay += step


static func _on_button_pressed() -> void:
	SettingsManager.play_click()


static func _update_pivot(button: Control) -> void:
	button.pivot_offset = button.size * 0.5


static func _animate_scale(button: Control, target: Vector2) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	if button.has_meta(&"ui_fx_tween"):
		var previous: Variant = button.get_meta(&"ui_fx_tween")
		if previous is Tween and (previous as Tween).is_valid():
			(previous as Tween).kill()
	var tween: Tween = button.create_tween()
	button.set_meta(&"ui_fx_tween", tween)
	tween.tween_property(button, "scale", target, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
