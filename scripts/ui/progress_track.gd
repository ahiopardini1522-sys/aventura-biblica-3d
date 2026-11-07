class_name ProgressTrack
extends Control
## Indicador de progreso de la partida: una barra de la casilla 1 a la meta con una
## marca de color por jugador. Las marcas se deslizan suavemente cuando una ficha avanza,
## y la del jugador en turno se dibuja más grande y con borde dorado.

const GOLD := Color(0.96, 0.77, 0.33)
const BAR_HEIGHT := 16.0
const MARKER_RADIUS := 14.0
const ACTIVE_RADIUS := 19.0
const SIDE_PADDING := 136.0
const TEXT_ZONE := 104.0
const SMOOTHING := 9.0

var total_tiles: int = 100
var active_index: int = -1

var _colors: Array[Color] = []
var _real: Array[float] = []
var _shown: Array[float] = []


func _init() -> void:
	custom_minimum_size = Vector2(0.0, 62.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Prepara la barra para un tablero de "total" casillas y un color por jugador.
func setup(total: int, player_colors: Array) -> void:
	total_tiles = maxi(2, total)
	_colors.clear()
	_real.clear()
	_shown.clear()
	for color in player_colors:
		_colors.append(color as Color)
		_real.append(1.0)
		_shown.append(1.0)
	active_index = -1
	queue_redraw()


## Mueve la marca de un jugador a una casilla (animada, o de golpe si "animated" es false).
func set_tile(index: int, tile: int, animated: bool = true) -> void:
	if index < 0 or index >= _real.size():
		return
	_real[index] = clampf(float(tile), 1.0, float(total_tiles))
	if animated and is_inside_tree():
		set_process(true)
	else:
		_shown[index] = _real[index]
		queue_redraw()


func set_active(index: int) -> void:
	active_index = index
	queue_redraw()


## Casilla que la marca muestra ahora mismo (puede tener decimales mientras se desliza).
func shown_tile(index: int) -> float:
	return _shown[index] if index >= 0 and index < _shown.size() else 0.0


func real_tile(index: int) -> float:
	return _real[index] if index >= 0 and index < _real.size() else 0.0


func is_settled() -> bool:
	for i in _real.size():
		if absf(_real[i] - _shown[i]) > 0.01:
			return false
	return true


func _process(delta: float) -> void:
	var k: float = 1.0 - exp(-SMOOTHING * delta)
	var moving: bool = false
	for i in _real.size():
		var gap: float = _real[i] - _shown[i]
		if absf(gap) < 0.02:
			_shown[i] = _real[i]
		else:
			_shown[i] += gap * k
			moving = true
	queue_redraw()
	if not moving:
		set_process(false)


func _x_of(tile: float) -> float:
	var left: float = SIDE_PADDING
	var right: float = maxf(left + 1.0, size.x - SIDE_PADDING)
	return lerpf(left, right, (tile - 1.0) / float(total_tiles - 1))


func _draw() -> void:
	var center_y: float = size.y * 0.5 + 8.0
	var left: float = _x_of(1.0)
	var right: float = _x_of(float(total_tiles))
	var bar := Rect2(left, center_y - BAR_HEIGHT * 0.5, right - left, BAR_HEIGHT)

	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.03, 0.05, 0.12, 0.82)
	back.border_color = Color(1, 1, 1, 0.28)
	back.set_border_width_all(2)
	back.set_corner_radius_all(int(BAR_HEIGHT * 0.5))
	draw_style_box(back, bar.grow(2.0))

	# Relleno hasta la ficha que va primera.
	var leader: float = 1.0
	for value in _shown:
		leader = maxf(leader, value)
	var fill_width: float = _x_of(leader) - left
	if fill_width > 1.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(GOLD, 0.92)
		fill.set_corner_radius_all(int(BAR_HEIGHT * 0.5))
		draw_style_box(fill, Rect2(left, bar.position.y, fill_width, BAR_HEIGHT))

	# Marcas de cuarto de camino.
	for quarter in [0.25, 0.5, 0.75]:
		var tile: float = 1.0 + float(total_tiles - 1) * float(quarter)
		draw_circle(Vector2(_x_of(tile), center_y), 3.0, Color(1, 1, 1, 0.5))

	# Etiquetas de inicio y meta, a los lados de la barra.
	var font: Font = get_theme_default_font()
	var baseline: float = center_y + 8.0
	draw_string(font, Vector2(0.0, baseline), "INICIO", HORIZONTAL_ALIGNMENT_RIGHT, TEXT_ZONE, 24,
			Color(1, 1, 1, 0.78))
	draw_string(font, Vector2(size.x - TEXT_ZONE + 6.0, baseline), "META", HORIZONTAL_ALIGNMENT_LEFT,
			TEXT_ZONE, 24, Color(1.0, 0.88, 0.54, 0.95))

	# Marcas de los jugadores: primero las demás y por último la del turno, encima.
	for i in _shown.size():
		if i != active_index:
			_draw_marker(i, center_y, false)
	if active_index >= 0 and active_index < _shown.size():
		_draw_marker(active_index, center_y, true)


func _draw_marker(index: int, center_y: float, active: bool) -> void:
	var at := Vector2(_x_of(_shown[index]), center_y)
	var radius: float = ACTIVE_RADIUS if active else MARKER_RADIUS
	draw_circle(at + Vector2(0.0, 3.0), radius, Color(0, 0, 0, 0.35))
	draw_circle(at, radius + 3.0, GOLD if active else Color(1, 1, 1, 0.92))
	draw_circle(at, radius, _colors[index])
	if active:
		var tip := Vector2(at.x, at.y - radius - 6.0)
		draw_colored_polygon(PackedVector2Array([
			tip, tip + Vector2(-9.0, -13.0), tip + Vector2(9.0, -13.0)]), GOLD)
