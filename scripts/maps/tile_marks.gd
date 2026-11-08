class_name TileMarks
extends RefCounted
## Números y símbolos que se dibujan sobre las casillas del tablero: el número de la casilla, el
## disco dorado con "?" de los desafíos y los iconos de las casillas especiales (recompensas en
## verde, obstáculos en rojo). Todo es geometría plana que se junta en dos mallas para todo el
## tablero: "marks" (discos y figuras, con luz) y "ink" (números, signos y puntos, sin luz para que
## se lean igual de día que de noche).

const INK_DARK := Color(0.16, 0.10, 0.05)
const INK_LIGHT := Color(0.97, 0.94, 0.86)
const GOLD := Color(0.98, 0.80, 0.30)
const GOOD_COLOR := Color(0.26, 0.66, 0.36)
const BAD_COLOR := Color(0.78, 0.22, 0.20)
const WHITE := Color(0.98, 0.97, 0.92)
const NUMBER_HEIGHT := 0.30
const NUMBER_STROKE := 0.05
## Esquina (x, z) de la casilla donde van el disco de desafío o el icono especial.
const CORNER := Vector2(0.25, -0.25)


## El número de la casilla, abajo a la izquierda. El color depende de lo clara que sea la casilla.
static func add_number(ink: MeshKit, tile: int, center: Vector3, tile_color: Color) -> void:
	var color: Color = INK_DARK if tile_color.get_luminance() > 0.42 else INK_LIGHT
	StrokeFont.add_text(ink, str(tile), Vector3(center.x - 0.12, BoardLayout.TILE_HEIGHT + 0.014, center.z + 0.2),
			NUMBER_HEIGHT, NUMBER_STROKE, color)


## Disco dorado con un signo de pregunta: ahí hay un desafío bíblico.
static func add_challenge(marks: MeshKit, ink: MeshKit, center: Vector3) -> void:
	var top: float = BoardLayout.TILE_HEIGHT
	var spot := Vector3(center.x + CORNER.x, top, center.z + CORNER.y)
	marks.disc(spot + Vector3(0.0, 0.008, 0.0), 0.17, GOLD, 14)
	StrokeFont.add_text(ink, "?", spot + Vector3(0.0, 0.02, 0.0), 0.21, 0.04, Color(0.30, 0.14, 0.02))


## Icono de una casilla especial: flecha hacia arriba (avanza), flecha hacia abajo (retrocede),
## estrella, dado (tira otra vez) o pausa (pierde un turno).
static func add_special(marks: MeshKit, ink: MeshKit, kind: String, center: Vector3) -> void:
	var top: float = BoardLayout.TILE_HEIGHT
	var good: bool = BoardLayout.REWARD_KINDS.has(kind)
	var disc_color: Color = GOOD_COLOR if good else BAD_COLOR
	var spot := Vector3(center.x + CORNER.x, top, center.z + CORNER.y)
	marks.place(spot)
	marks.disc(Vector3(0.0, 0.008, 0.0), 0.19, disc_color, 16)
	if kind == BoardLayout.SPECIAL_ADVANCE:
		marks.extrude(_arrow(false), 0.009, 0.02, WHITE)
	elif kind == BoardLayout.SPECIAL_BACK:
		marks.extrude(_arrow(true), 0.009, 0.02, WHITE)
	elif kind == BoardLayout.SPECIAL_STARS:
		marks.extrude(_star_polygon(0.15, 0.065), 0.009, 0.02, Color(1.0, 0.86, 0.28))
	elif kind == BoardLayout.SPECIAL_SKIP:
		marks.box(Vector3(-0.055, 0.0145, 0.0), Vector3(0.065, 0.011, 0.2), WHITE)
		marks.box(Vector3(0.055, 0.0145, 0.0), Vector3(0.065, 0.011, 0.2), WHITE)
	elif kind == BoardLayout.SPECIAL_EXTRA_ROLL:
		marks.extrude(PackedVector2Array([Vector2(-0.1, -0.1), Vector2(0.1, -0.1), Vector2(0.1, 0.1),
				Vector2(-0.1, 0.1)]), 0.009, 0.02, WHITE)
		var pips: Array[Vector2] = [Vector2(-0.058, -0.058), Vector2(0.058, -0.058), Vector2(0.0, 0.0),
				Vector2(-0.058, 0.058), Vector2(0.058, 0.058)]
		for pip in pips:
			ink.disc(spot + Vector3(pip.x, 0.022, pip.y), 0.021, INK_DARK, 6)
	marks.pop()


## Flecha vertical. "down" = hacia la cámara (+z, hacia la salida); si no, hacia el fondo (la meta).
static func _arrow(down: bool) -> PackedVector2Array:
	var dir: float = 1.0 if down else -1.0
	return PackedVector2Array([Vector2(0.0, 0.14 * dir), Vector2(0.11, 0.01 * dir), Vector2(0.045, 0.01 * dir),
			Vector2(0.045, -0.13 * dir), Vector2(-0.045, -0.13 * dir), Vector2(-0.045, 0.01 * dir),
			Vector2(-0.11, 0.01 * dir)])


## Polígono de una estrella de cinco puntas con una punta hacia el fondo del tablero.
static func _star_polygon(outer: float, inner: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var radius: float = outer if i % 2 == 0 else inner
		var angle: float = -PI * 0.5 + TAU * float(i) / 10.0
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points
