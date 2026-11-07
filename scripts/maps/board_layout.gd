class_name BoardLayout
extends RefCounted
## Datos y geometría del tablero, sin nodos: qué casilla va en qué lugar, dónde están
## las escaleras y las serpientes y cómo comprobar que la definición es válida.
## Casillas numeradas desde 1 en zigzag: la fila 0 va de izquierda a derecha,
## la fila 1 de derecha a izquierda, y así sucesivamente.

const TILE_SIZE := 1.0
const TILE_GAP := 0.08
const TILE_HEIGHT := 0.18
const FRAME_MARGIN := 0.4
const FRAME_THICKNESS := 0.3
const PITCH := TILE_SIZE + TILE_GAP

var columns: int = 10
var rows: int = 10
## Cada entrada es (casilla de origen, casilla de destino).
var ladders: Array[Vector2i] = []
var snakes: Array[Vector2i] = []


## Crea el trazado a partir de una entrada de MapCatalog.
static func from_map(map_data: Dictionary) -> BoardLayout:
	var layout := BoardLayout.new()
	var board: Dictionary = map_data.get("board", {})
	layout.columns = maxi(2, int(board.get("columns", 10)))
	layout.rows = maxi(2, int(board.get("rows", 10)))
	layout.ladders = _to_pairs(board.get("ladders", []))
	layout.snakes = _to_pairs(board.get("snakes", []))
	return layout


static func _to_pairs(raw: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if raw is Array:
		for item in raw:
			if item is Array and (item as Array).size() == 2:
				result.append(Vector2i(int(item[0]), int(item[1])))
	return result


func tile_count() -> int:
	return columns * rows


## Columna y fila (fila 0 = la de abajo) de una casilla.
func grid_of(tile: int) -> Vector2i:
	var index: int = clampi(tile, 1, tile_count()) - 1
	var row: int = floori(float(index) / float(columns))
	var col: int = index % columns
	if row % 2 == 1:
		col = columns - 1 - col
	return Vector2i(col, row)


## Centro de la cara superior de la casilla, en coordenadas del tablero.
## El tablero queda centrado en el origen y la fila 0 mira hacia la cámara (+z).
func tile_center(tile: int) -> Vector3:
	var cell: Vector2i = grid_of(tile)
	var x: float = (float(cell.x) - float(columns - 1) * 0.5) * PITCH
	var z: float = (float(rows - 1) * 0.5 - float(cell.y)) * PITCH
	return Vector3(x, TILE_HEIGHT, z)


## Ancho (x) y fondo (z) de la zona de casillas.
func board_size() -> Vector2:
	return Vector2(float(columns) * PITCH - TILE_GAP, float(rows) * PITCH - TILE_GAP)


## Casilla a la que se llega al caer en "tile" (por escalera o serpiente); la misma si no hay.
func jump_target(tile: int) -> int:
	for pair in ladders:
		if pair.x == tile:
			return pair.y
	for pair in snakes:
		if pair.x == tile:
			return pair.y
	return tile


func is_ladder_start(tile: int) -> bool:
	for pair in ladders:
		if pair.x == tile:
			return true
	return false


func is_snake_head(tile: int) -> bool:
	for pair in snakes:
		if pair.x == tile:
			return true
	return false


## Posición dentro de una casilla para que varias fichas quepan juntas.
static func token_offset(slot: int, count: int) -> Vector3:
	var d: float = 0.22
	if count <= 1:
		return Vector3.ZERO
	if count == 2:
		return Vector3(-d if slot == 0 else d, 0.0, 0.0)
	if count == 3:
		match slot:
			0:
				return Vector3(-d, 0.0, d * 0.7)
			1:
				return Vector3(d, 0.0, d * 0.7)
			_:
				return Vector3(0.0, 0.0, -d)
	var x: float = -d if slot % 2 == 0 else d
	var z: float = d if slot < 2 else -d
	return Vector3(x, 0.0, z)


## Comprueba que las escaleras y serpientes sean coherentes. Devuelve la lista de
## problemas encontrados (vacía si todo está bien).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var total: int = tile_count()
	var used: Dictionary = {}
	for pair in ladders:
		problems.append_array(_check_pair("Escalera", pair, total, true, used))
	for pair in snakes:
		problems.append_array(_check_pair("Serpiente", pair, total, false, used))
	return problems


func _check_pair(kind: String, pair: Vector2i, total: int, goes_up: bool,
		used: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var label: String = "%s %d->%d" % [kind, pair.x, pair.y]
	if pair.x < 1 or pair.x > total or pair.y < 1 or pair.y > total:
		problems.append("%s: casilla fuera del tablero (1-%d)" % [label, total])
		return problems
	if goes_up and pair.y <= pair.x:
		problems.append("%s: una escalera debe subir" % label)
	if not goes_up and pair.y >= pair.x:
		problems.append("%s: una serpiente debe bajar" % label)
	if pair.x == 1 or pair.x == total:
		problems.append("%s: la casilla de inicio o de meta no puede ser origen" % label)
	for tile in [pair.x, pair.y]:
		if used.has(tile):
			problems.append("%s: la casilla %d ya la usa otra escalera o serpiente" % [label, tile])
		used[tile] = true
	return problems
