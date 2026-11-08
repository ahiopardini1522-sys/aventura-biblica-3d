class_name BoardCamera
extends Camera3D
## Cámara del tablero: gira alrededor del centro arrastrando con un dedo, se acerca y
## se aleja con el gesto de pellizco (o la rueda del ratón) y vuelve a la vista inicial
## con reset_view(). Los movimientos se suavizan para que se sienta fluido en el móvil.
## Durante la partida también sabe enfocar una ficha (focus_on / follow), volver a la vista
## general (release_focus) y sacudirse (shake). Si el jugador la mueve con el dedo, deja de
## hacerlo sola hasta que pulse VISTA, para no pelearse con él.

signal user_moved

const MIN_PITCH := 28.0
const MAX_PITCH := 84.0
const MAX_YAW := 70.0
const ORBIT_SPEED := Vector2(0.14, 0.12) # grados por píxel (giro, inclinación)
const SMOOTHING := 10.0
## Entrada de la escena: la cámara empieza baja, mirando el paisaje hasta el horizonte, y sube a la vista de juego.
const INTRO_YAW := -34.0
const INTRO_PITCH := 17.0
const INTRO_ZOOM := 1.55
const INTRO_HOLD := 0.5
const INTRO_SECONDS := 2.3

var target: Vector3 = Vector3.ZERO
var goal_target: Vector3 = Vector3.ZERO
## Verdadero cuando el jugador movió la cámara a mano: las ayudas automáticas se detienen.
var user_override: bool = false
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
var _home_target: Vector3 = Vector3.ZERO
var _extent: float = 10.0
var _shake_left: float = 0.0
var _shake_total: float = 0.1
var _shake_strength: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO


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
	target = target.lerp(goal_target, k)
	_update_shake(delta)
	_apply()


## Define el punto central y calcula una distancia que deje ver todo el tablero.
func configure(new_target: Vector3, board_extent: float) -> void:
	target = new_target
	goal_target = new_target
	_home_target = new_target
	_extent = board_extent
	user_override = false
	default_distance = clampf(board_extent * 1.55 + 1.0, 10.0, 28.0)
	min_distance = maxf(6.0, board_extent * 0.7)
	max_distance = default_distance * 1.9
	reset_view(false)


## Vuelve a la vista inicial (con animación, o de golpe si "animated" es false).
func reset_view(animated: bool = true) -> void:
	_kill_tween()
	user_override = false
	goal_target = _home_target
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


## Entrada de la escena: la cámara empieza baja, para que se vea el paisaje del mundo (montañas, cielo,
## construcciones), y sube hasta la vista inicial del tablero.
func play_intro() -> void:
	_kill_tween()
	target = _home_target
	goal_target = _home_target
	yaw = INTRO_YAW
	pitch = INTRO_PITCH
	distance = default_distance * INTRO_ZOOM
	goal_yaw = yaw
	goal_pitch = pitch
	goal_distance = distance
	_apply()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "goal_yaw", default_yaw, INTRO_SECONDS).set_delay(INTRO_HOLD) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "goal_pitch", default_pitch, INTRO_SECONDS).set_delay(INTRO_HOLD) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "goal_distance", default_distance, INTRO_SECONDS).set_delay(INTRO_HOLD) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Acerca (factor < 1) o aleja (factor > 1) la cámara.
func zoom_by(factor: float) -> void:
	_kill_tween()
	_mark_user_moved()
	goal_distance = clampf(goal_distance * factor, min_distance, max_distance)


func orbit_by(delta_pixels: Vector2) -> void:
	_kill_tween()
	_mark_user_moved()
	goal_yaw = clampf(goal_yaw - delta_pixels.x * ORBIT_SPEED.x, -MAX_YAW, MAX_YAW)
	goal_pitch = clampf(goal_pitch + delta_pixels.y * ORBIT_SPEED.y, MIN_PITCH, MAX_PITCH)


## Centra la cámara en un punto del tablero (por ejemplo, la ficha que va a moverse) y se acerca un poco.
## No hace nada si el jugador movió la cámara a mano.
func focus_on(point: Vector3, zoom_factor: float = 0.68) -> void:
	if user_override:
		return
	_kill_tween()
	goal_target = _clamp_to_board(point)
	goal_distance = clampf(default_distance * zoom_factor, min_distance, max_distance)


## Sigue un punto que se mueve (la ficha mientras camina) sin cambiar el zoom.
func follow(point: Vector3) -> void:
	if user_override:
		return
	goal_target = _clamp_to_board(point)


## Vuelve a la vista general conservando el giro que tenga la cámara.
func release_focus() -> void:
	if user_override:
		return
	_kill_tween()
	goal_target = _home_target
	goal_distance = default_distance


## Sacude la cámara un momento (la mordida de una serpiente, por ejemplo).
func shake(strength: float = 0.12, duration: float = 0.4) -> void:
	_shake_strength = maxf(strength, 0.0)
	_shake_total = maxf(duration, 0.05)
	_shake_left = _shake_total


func is_shaking() -> bool:
	return _shake_left > 0.0


func _mark_user_moved() -> void:
	if not user_override:
		user_override = true
		user_moved.emit()


func _clamp_to_board(point: Vector3) -> Vector3:
	var half: float = _extent * 0.5
	return Vector3(clampf(point.x, -half, half), _home_target.y, clampf(point.z, -half, half))


func _update_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		_shake_offset = Vector3.ZERO
		return
	_shake_left = maxf(0.0, _shake_left - delta)
	var fade: float = _shake_left / _shake_total
	_shake_offset = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) \
			* (_shake_strength * fade)


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
	target = goal_target
	_apply()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _apply() -> void:
	var yaw_rad: float = deg_to_rad(yaw)
	var pitch_rad: float = deg_to_rad(pitch)
	var offset := Vector3(sin(yaw_rad) * cos(pitch_rad), sin(pitch_rad), cos(yaw_rad) * cos(pitch_rad)) * distance
	transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), target + offset + _shake_offset)
