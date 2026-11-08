class_name WorldCamera
extends Camera3D
## Cámara del mapa mundial. Mira el mundo desde arriba con una inclinación fija y se desliza
## sobre el suelo:
##   un dedo (o ratón con el botón izquierdo)  arrastra el mapa
##   dos dedos                                  pellizco para acercar o alejar (y arrastre)
##   rueda del ratón                            zoom
##   toque corto, sin moverse                   señal "tapped" con la posición en pantalla
## Todos los movimientos se suavizan: la cámara persigue una meta (goal_target / goal_distance).

signal tapped(screen_position: Vector2)
signal user_moved

const MIN_DISTANCE := 20.0
const MAX_DISTANCE := 135.0
const PITCH_DEG := 52.0
const FOV_DEG := 45.0
const TAP_SLOP := 28.0
const SMOOTHING := 9.0
const WHEEL_FACTOR := 0.86

## Zona por la que puede moverse el punto que mira la cámara: Rect2(x, z, ancho, largo).
var bounds: Rect2 = Rect2(-92.0, -46.0, 190.0, 92.0)
var home_target: Vector3 = Vector3(3.0, 0.0, 0.0)
var home_distance: float = 124.0

var target: Vector3 = Vector3.ZERO
var distance: float = 124.0
var goal_target: Vector3 = Vector3.ZERO
var goal_distance: float = 124.0

var _touches: Dictionary = {}
var _touch_start: Vector2 = Vector2.ZERO
var _touch_moved: bool = false
var _touch_multi: bool = false
var _pinch_last: float = 0.0
var _middle_last: Vector2 = Vector2.ZERO

var _mouse_down: bool = false
var _mouse_start: Vector2 = Vector2.ZERO
var _mouse_moved: bool = false


func _init() -> void:
	fov = FOV_DEG
	near = 1.5
	far = 900.0


func _ready() -> void:
	set_process_unhandled_input(true)
	_apply()


## Define la zona de movimiento y la vista general.
func configure(new_bounds: Rect2, new_home_target: Vector3, new_home_distance: float) -> void:
	bounds = new_bounds
	home_target = new_home_target
	home_distance = clampf(new_home_distance, MIN_DISTANCE, MAX_DISTANCE)
	goal_target = _clamp_target(home_target)
	goal_distance = home_distance
	snap()


## Salta de golpe a la meta (sin animación).
func snap() -> void:
	target = goal_target
	distance = goal_distance
	_apply()


## Vuelve a la vista general del mundo.
func overview(animated: bool = true) -> void:
	goal_target = _clamp_target(home_target)
	goal_distance = home_distance
	if not animated:
		snap()


## Vuela hasta mirar "point". La región queda un poco a la derecha del centro para que no la
## tape el panel de información de la izquierda.
func focus_on(point: Vector3, new_distance: float = -1.0, shift: float = 0.2) -> void:
	if new_distance > 0.0:
		goal_distance = clampf(new_distance, MIN_DISTANCE, MAX_DISTANCE)
	var aim := Vector3(point.x - shift * goal_distance, 0.0, point.z)
	goal_target = _clamp_target(aim)


## Acerca (factor < 1) o aleja (factor > 1).
func zoom_by(factor: float) -> void:
	goal_distance = clampf(goal_distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	user_moved.emit()


## Arrastra el mapa lo que se movió el dedo (en píxeles de pantalla).
func pan_by(delta_pixels: Vector2) -> void:
	var step: float = _units_per_pixel(goal_distance)
	var pitch: float = deg_to_rad(PITCH_DEG)
	var moved := Vector3(goal_target.x - delta_pixels.x * step,
			goal_target.y, goal_target.z - delta_pixels.y * step / sin(pitch))
	goal_target = _clamp_target(moved)
	user_moved.emit()


## Cuántas unidades del mundo cubre un píxel de pantalla en el punto que mira la cámara.
func units_per_pixel() -> float:
	return _units_per_pixel(distance)


func is_settled() -> bool:
	return target.distance_to(goal_target) < 0.05 and absf(distance - goal_distance) < 0.05


func _units_per_pixel(at_distance: float) -> float:
	var screen_height: float = 1080.0
	if is_inside_tree():
		screen_height = maxf(1.0, get_viewport().get_visible_rect().size.y)
	return 2.0 * at_distance * tan(deg_to_rad(fov) * 0.5) / screen_height


func _clamp_target(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, bounds.position.x, bounds.end.x), 0.0,
			clampf(point.z, bounds.position.y, bounds.end.y))


func _process(delta: float) -> void:
	if is_settled():
		return
	var k: float = 1.0 - exp(-SMOOTHING * delta)
	target = target.lerp(goal_target, k)
	distance = lerpf(distance, goal_distance, k)
	_apply()


func _apply() -> void:
	var pitch: float = deg_to_rad(PITCH_DEG)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * distance
	transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), target + offset)


# ---------------------------------------------------------------- Entrada

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.canceled:
		_touches.erase(event.index)
		if _touches.is_empty():
			_touch_multi = false
		return
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_touch_start = event.position
			_touch_moved = false
			_touch_multi = false
		else:
			_touch_multi = true
			_start_pinch()
		return
	var had_touch: bool = _touches.has(event.index)
	_touches.erase(event.index)
	if not had_touch:
		return
	if _touches.is_empty():
		var was_tap: bool = not _touch_moved and not _touch_multi
		_touch_multi = false
		_touch_moved = false
		if was_tap:
			tapped.emit(event.position)
	elif _touches.size() == 1:
		_touch_moved = true


func _on_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		_update_pinch()
		return
	if _touch_multi:
		return
	if not _touch_moved:
		var travelled: Vector2 = event.position - _touch_start
		if travelled.length() <= TAP_SLOP:
			return
		_touch_moved = true
		pan_by(travelled)
		return
	pan_by(event.relative)


func _two_touch_points() -> Array[Vector2]:
	var indices: Array = _touches.keys()
	indices.sort()
	var points: Array[Vector2] = []
	for index in indices:
		points.append(_touches[index])
		if points.size() == 2:
			break
	return points


func _start_pinch() -> void:
	var points: Array[Vector2] = _two_touch_points()
	if points.size() < 2:
		return
	_pinch_last = maxf(points[0].distance_to(points[1]), 1.0)
	_middle_last = (points[0] + points[1]) * 0.5


func _update_pinch() -> void:
	var points: Array[Vector2] = _two_touch_points()
	if points.size() < 2:
		return
	var spread: float = maxf(points[0].distance_to(points[1]), 1.0)
	var middle: Vector2 = (points[0] + points[1]) * 0.5
	if _pinch_last > 0.0 and absf(spread - _pinch_last) > 0.5:
		zoom_by(_pinch_last / spread)
	pan_by(middle - _middle_last)
	_pinch_last = spread
	_middle_last = middle


func _on_mouse_button(event: InputEventMouseButton) -> void:
	# Los toques también llegan como ratón emulado: ya se atienden como toques.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		zoom_by(WHEEL_FACTOR)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		zoom_by(1.0 / WHEEL_FACTOR)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_down = true
			_mouse_moved = false
			_mouse_start = event.position
		else:
			var was_tap: bool = _mouse_down and not _mouse_moved
			_mouse_down = false
			_mouse_moved = false
			if was_tap:
				tapped.emit(event.position)


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION or not _mouse_down:
		return
	if not _mouse_moved:
		var travelled: Vector2 = event.position - _mouse_start
		if travelled.length() <= TAP_SLOP:
			return
		_mouse_moved = true
		pan_by(travelled)
		return
	pan_by(event.relative)
