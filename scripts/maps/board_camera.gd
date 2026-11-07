class_name BoardCamera
extends Camera3D
## Cámara del tablero: gira alrededor del centro arrastrando con un dedo, se acerca y
## se aleja con el gesto de pellizco (o la rueda del ratón) y vuelve a la vista inicial
## con reset_view(). Los movimientos se suavizan para que se sienta fluido en el móvil.

const MIN_PITCH := 28.0
const MAX_PITCH := 84.0
const MAX_YAW := 70.0
const ORBIT_SPEED := Vector2(0.14, 0.12) # grados por píxel (giro, inclinación)
const SMOOTHING := 10.0

var target: Vector3 = Vector3.ZERO
var default_yaw: float = 0.0
var default_pitch: float = 56.0
var default_distance: float = 17.0
var min_distance: float = 8.0
var max_distance: float = 32.0

# Valores actuales y metas (en grados y unidades de mundo).
var yaw: float = 0.0
var pitch: float = 56.0
var distance: float = 17.0
var goal_yaw: float = 0.0
var goal_pitch: float = 56.0
var goal_distance: float = 17.0

var _touches: Dictionary = {}
var _pinch_last: float = 0.0
var _tween: Tween


func _ready() -> void:
	current = true
	fov = 45.0
	far = 400.0
	_snap_to_goal()


func _process(delta: float) -> void:
	var k: float = 1.0 - exp(-SMOOTHING * delta)
	yaw = lerpf(yaw, goal_yaw, k)
	pitch = lerpf(pitch, goal_pitch, k)
	distance = lerpf(distance, goal_distance, k)
	_apply()


## Define el punto central y calcula una distancia que deje ver todo el tablero.
func configure(new_target: Vector3, board_extent: float) -> void:
	target = new_target
	default_distance = clampf(board_extent * 1.55 + 1.0, 10.0, 28.0)
	min_distance = maxf(6.0, board_extent * 0.7)
	max_distance = default_distance * 1.9
	reset_view(false)


## Vuelve a la vista inicial (con animación, o de golpe si "animated" es false).
func reset_view(animated: bool = true) -> void:
	_kill_tween()
	if not animated:
		goal_yaw = default_yaw
		goal_pitch = default_pitch
		goal_distance = default_distance
		_snap_to_goal()
		return
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "goal_yaw", default_yaw, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "goal_pitch", default_pitch, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "goal_distance", default_distance, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Entrada de la escena: la cámara baja desde arriba y se coloca en la vista inicial.
func play_intro() -> void:
	_kill_tween()
	yaw = -32.0
	pitch = 78.0
	distance = default_distance * 1.7
	goal_yaw = yaw
	goal_pitch = pitch
	goal_distance = distance
	_apply()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "goal_yaw", default_yaw, 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "goal_pitch", default_pitch, 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "goal_distance", default_distance, 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Acerca (factor < 1) o aleja (factor > 1) la cámara.
func zoom_by(factor: float) -> void:
	_kill_tween()
	goal_distance = clampf(goal_distance * factor, min_distance, max_distance)


func orbit_by(delta_pixels: Vector2) -> void:
	_kill_tween()
	goal_yaw = clampf(goal_yaw - delta_pixels.x * ORBIT_SPEED.x, -MAX_YAW, MAX_YAW)
	goal_pitch = clampf(goal_pitch + delta_pixels.y * ORBIT_SPEED.y, MIN_PITCH, MAX_PITCH)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		_pinch_last = _pinch_distance()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[drag.index] = drag.position
		if _touches.size() >= 2:
			var current_distance: float = _pinch_distance()
			if _pinch_last > 1.0 and current_distance > 1.0:
				zoom_by(_pinch_last / current_distance)
			_pinch_last = current_distance
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		# Un dedo (o el botón izquierdo del ratón) gira la vista; con dos dedos solo hay zoom.
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and _touches.size() < 2:
			orbit_by(motion.relative)
	elif event is InputEventMouseButton:
		var wheel := event as InputEventMouseButton
		if wheel.pressed and wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(0.9)
		elif wheel.pressed and wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.1)


func _pinch_distance() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


func _snap_to_goal() -> void:
	yaw = goal_yaw
	pitch = goal_pitch
	distance = goal_distance
	_apply()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _apply() -> void:
	var yaw_rad: float = deg_to_rad(yaw)
	var pitch_rad: float = deg_to_rad(pitch)
	var offset := Vector3(sin(yaw_rad) * cos(pitch_rad), sin(pitch_rad), cos(yaw_rad) * cos(pitch_rad)) * distance
	transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), target + offset)
