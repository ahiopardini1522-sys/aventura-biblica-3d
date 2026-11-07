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

const KIND_LADDER := "ladder"
const KIND_SNAKE := "snake"

var columns: int = 10
var rows: int = 10
## Cada entrada es (casilla de origen, casilla de destino).
var ladders: Array[Vector2i] = []
var snakes: Array[Vector2i] = []
## Casillas donde se plantea un desafío bíblico (nunca inicio, meta, escaleras ni serpientes).
var challenge_tiles: Array[int] = []


## Crea el trazado a partir de una entrada de MapCatalog.
static func from_map(map_data: Dictionary) -> BoardLayout:
	var layout := BoardLayout.new()
	var board: Dictionary = map_data.get("board", {})
	layout.columns = maxi(2, int(board.get("columns", 10)))
	layout.rows = maxi(2, int(board.get("rows", 10)))
	layout.ladders = _to_pairs(board.get("ladders", []))
	layout.snakes = _to_pairs(board.get("snakes", []))
	var tiles: Variant = board.get("challenge_tiles", [])
	if tiles is Array and not (tiles as Array).is_empty():
		for tile in tiles:
			layout.challenge_tiles.append(int(tile))
	else:
		layout.challenge_tiles = layout.default_challenge_tiles()
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


## Número de la casilla de meta (la última).
func last_tile() -> int:
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


## "ladder" si en esa casilla empieza una escalera, "snake" si está la cabeza de una
## serpiente y "" si es una casilla normal.
func jump_kind(tile: int) -> String:
	if is_ladder_start(tile):
		return KIND_LADDER
	if is_snake_head(tile):
		return KIND_SNAKE
	return ""


func is_challenge_tile(tile: int) -> bool:
	return challenge_tiles.has(tile)


## Casillas que no pueden llevar desafío: inicio, meta y los dos extremos de cada
## escalera y de cada serpiente.
func reserved_tiles() -> Dictionary:
	var reserved: Dictionary = {1: true}
	reserved[last_tile()] = true
	for pair in ladders:
		reserved[pair.x] = true
		reserved[pair.y] = true
	for pair in snakes:
		reserved[pair.x] = true
		reserved[pair.y] = true
	return reserved


## Reparto determinista de casillas de desafío para mapas que no las definen: una cada
## cinco casillas aproximadamente, saltando las reservadas.
func default_challenge_tiles() -> Array[int]:
	var reserved: Dictionary = reserved_tiles()
	var result: Array[int] = []
	var tile: int = 5
	while tile < last_tile():
		var candidate: int = tile
		while candidate < last_tile() and reserved.has(candidate):
			candidate += 1
		if candidate < last_tile() and not result.has(candidate):
			result.append(candidate)
		tile = candidate + 5
	return result


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
	problems.append_array(_check_challenge_tiles(total))
	return problems


func _check_challenge_tiles(total: int) -> PackedStringArray:
	var problems := PackedStringArray()
	var reserved: Dictionary = reserved_tiles()
	var seen: Dictionary = {}
	for tile in challenge_tiles:
		if tile < 1 or tile > total:
			problems.append("Desafío en la casilla %d: fuera del tablero (1-%d)" % [tile, total])
		elif reserved.has(tile):
			problems.append("Desafío en la casilla %d: está reservada (inicio, meta, escalera o serpiente)" % tile)
		if seen.has(tile):
			problems.append("Desafío en la casilla %d: está repetido" % tile)
		seen[tile] = true
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
