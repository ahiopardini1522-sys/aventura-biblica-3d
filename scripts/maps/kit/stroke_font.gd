class_name StrokeFont
extends RefCounted
## Cifras y signos hechos con trazos gruesos, como geometría plana. Los números del tablero se
## dibujan así y se juntan en la misma malla: cien rótulos de texto serían cien llamadas de
## dibujo (y cien texturas de letras que generar al abrir el mapa) en un móvil de gama media.
##
## Cada glifo mide 0.62 de ancho por 1 de alto, con la "y" hacia arriba. En el tablero "arriba" es
## hacia el fondo (-z), de modo que el texto se lee bien desde la cámara.

const GLYPH_WIDTH := 0.62
## Separación entre el inicio de un glifo y el del siguiente.
const ADVANCE := 0.86

## Cada glifo es una lista de trazos; cada trazo es una lista plana de pares x, y.
const GLYPHS := {
	"0": [[0.31, 1.0, 0.10, 0.90, 0.0, 0.66, 0.0, 0.34, 0.10, 0.10, 0.31, 0.0, 0.52, 0.10, 0.62, 0.34,
			0.62, 0.66, 0.52, 0.90, 0.31, 1.0]],
	"1": [[0.08, 0.76, 0.34, 1.0, 0.34, 0.0], [0.10, 0.0, 0.58, 0.0]],
	"2": [[0.02, 0.78, 0.12, 0.94, 0.31, 1.0, 0.50, 0.94, 0.60, 0.78, 0.58, 0.58, 0.0, 0.0, 0.62, 0.0]],
	"3": [[0.02, 0.86, 0.14, 0.97, 0.32, 1.0, 0.50, 0.95, 0.58, 0.80, 0.54, 0.62, 0.38, 0.52, 0.24, 0.52],
			[0.38, 0.52, 0.56, 0.42, 0.62, 0.26, 0.54, 0.08, 0.34, 0.0, 0.14, 0.03, 0.0, 0.14]],
	"4": [[0.46, 0.0, 0.46, 1.0, 0.0, 0.30, 0.62, 0.30]],
	"5": [[0.56, 1.0, 0.10, 1.0, 0.04, 0.55, 0.22, 0.62, 0.40, 0.60, 0.56, 0.48, 0.62, 0.30, 0.54, 0.10,
			0.34, 0.0, 0.14, 0.02, 0.0, 0.14]],
	"6": [[0.54, 0.94, 0.34, 1.0, 0.14, 0.88, 0.02, 0.62, 0.0, 0.34, 0.08, 0.12, 0.28, 0.0, 0.48, 0.04,
			0.60, 0.22, 0.58, 0.42, 0.44, 0.54, 0.24, 0.54, 0.08, 0.42]],
	"7": [[0.0, 1.0, 0.62, 1.0, 0.24, 0.0]],
	"8": [[0.31, 0.54, 0.12, 0.64, 0.06, 0.80, 0.14, 0.94, 0.31, 1.0, 0.48, 0.94, 0.56, 0.80, 0.50, 0.64,
			0.31, 0.54, 0.08, 0.42, 0.0, 0.24, 0.08, 0.08, 0.31, 0.0, 0.54, 0.08, 0.62, 0.24, 0.54, 0.42,
			0.31, 0.54]],
	"9": [[0.08, 0.06, 0.28, 0.0, 0.48, 0.12, 0.60, 0.38, 0.62, 0.66, 0.54, 0.88, 0.34, 1.0, 0.14, 0.96,
			0.02, 0.78, 0.04, 0.58, 0.18, 0.46, 0.38, 0.46, 0.54, 0.58]],
	"?": [[0.04, 0.78, 0.12, 0.94, 0.31, 1.0, 0.50, 0.94, 0.58, 0.78, 0.54, 0.62, 0.31, 0.46, 0.31, 0.30],
			[0.31, 0.05, 0.31, 0.09]],
}


## Ancho total del texto cuando los glifos miden "height" de alto.
static func text_width(text: String, height: float) -> float:
	if text.is_empty():
		return 0.0
	return (float(text.length() - 1) * ADVANCE + GLYPH_WIDTH) * height


## Agrega el texto como trazos planos que miran hacia arriba, a la altura "center.y", centrado en
## (center.x, center.z). "stroke" es el grosor de la línea. Los caracteres sin glifo se saltan.
static func add_text(kit: MeshKit, text: String, center: Vector3, height: float, stroke: float,
		color: Color) -> void:
	var total: float = text_width(text, height)
	var left: float = center.x - total * 0.5
	var bottom: float = center.z + height * 0.5
	for index in text.length():
		var glyph: String = text.substr(index, 1)
		if not GLYPHS.has(glyph):
			continue
		var origin_x: float = left + float(index) * ADVANCE * height
		var strokes: Array = GLYPHS[glyph]
		for entry in strokes:
			var points: Array = entry
			_add_stroke(kit, points, origin_x, bottom, center.y, height, stroke, color)


## Un trazo: una tira de cuadriláteros planos, uno por tramo, con los extremos prolongados medio
## grosor para que las esquinas queden rellenas.
static func _add_stroke(kit: MeshKit, points: Array, origin_x: float, bottom: float, y: float,
		height: float, stroke: float, color: Color) -> void:
	var count: int = floori(float(points.size()) / 2.0)
	var half: float = stroke * 0.5
	for i in count - 1:
		var a := Vector2(origin_x + float(points[i * 2]) * height, bottom - float(points[i * 2 + 1]) * height)
		var b := Vector2(origin_x + float(points[i * 2 + 2]) * height, bottom - float(points[i * 2 + 3]) * height)
		var along: Vector2 = b - a
		var length: float = along.length()
		if length < 0.0001:
			continue
		var direction: Vector2 = along / length
		var side: Vector2 = Vector2(-direction.y, direction.x) * half
		var start: Vector2 = a - direction * half
		var finish: Vector2 = b + direction * half
		kit.quad(Vector3(start.x - side.x, y, start.y - side.y), Vector3(finish.x - side.x, y, finish.y - side.y),
				Vector3(finish.x + side.x, y, finish.y + side.y), Vector3(start.x + side.x, y, start.y + side.y),
				color, Vector3.UP)
