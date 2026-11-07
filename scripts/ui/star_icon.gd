class_name StarIcon
extends Control
## Estrella de cinco puntas dibujada por código. No depende de ninguna fuente ni imagen,
## así se ve igual en cualquier móvil. Sirve para las estrellas ganadas y la dificultad.

var color: Color = Color(0.96, 0.77, 0.33):
	set(value):
		color = value
		queue_redraw()
var filled: bool = true:
	set(value):
		filled = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(34.0, 34.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Atajo para configurarla de una vez: color, si va rellena y su tamaño en píxeles.
func configure(new_color: Color, is_filled: bool = true, pixels: float = 34.0) -> StarIcon:
	color = new_color
	filled = is_filled
	custom_minimum_size = Vector2(pixels, pixels)
	queue_redraw()
	return self


## Puntos de la estrella centrada en "center" (alternan punta y valle).
static func outline(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var angle: float = -PI * 0.5 + float(i) * PI / 5.0
		var reach: float = radius if i % 2 == 0 else radius * 0.42
		points.append(center + Vector2(cos(angle), sin(angle)) * reach)
	return points


func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5 - 1.0
	if radius <= 1.0:
		return
	var points: PackedVector2Array = outline(size * 0.5 + Vector2(0.0, radius * 0.06), radius)
	if filled:
		draw_colored_polygon(points, color)
		var edge: PackedVector2Array = points.duplicate()
		edge.append(points[0])
		draw_polyline(edge, color.darkened(0.45), maxf(1.5, radius * 0.1), true)
	else:
		var edge_dim: PackedVector2Array = points.duplicate()
		edge_dim.append(points[0])
		draw_polyline(edge_dim, Color(color, 0.55), maxf(1.5, radius * 0.1), true)
