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

## Casillas especiales. Las de recompensa ayudan y las de obstáculo estorban:
##   advance     avanza "steps" casillas          (recompensa)
##   extra_roll  tira otra vez                    (recompensa)
##   stars       da "stars" estrellas             (recompensa)
##   back        retrocede "steps" casillas       (obstáculo)
##   skip        pierde el próximo turno          (obstáculo; con un solo jugador retrocede 1)
const SPECIAL_ADVANCE := "advance"
const SPECIAL_EXTRA_ROLL := "extra_roll"
const SPECIAL_STARS := "stars"
const SPECIAL_BACK := "back"
const SPECIAL_SKIP := "skip"
const REWARD_KINDS: Array[String] = [SPECIAL_ADVANCE, SPECIAL_EXTRA_ROLL, SPECIAL_STARS]
const OBSTACLE_KINDS: Array[String] = [SPECIAL_BACK, SPECIAL_SKIP]
const MIN_SPECIAL_STEPS := 1
const MAX_SPECIAL_STEPS := 4
const MAX_SPECIAL_STARS := 3

var columns: int = 10
var rows: int = 10
## Cada entrada es (casilla de origen, casilla de destino).
var ladders: Array[Vector2i] = []
var snakes: Array[Vector2i] = []
## Casillas donde se plantea un desafío bíblico (nunca inicio, meta, escaleras ni serpientes).
var challenge_tiles: Array[int] = []
## Id del mapa al que pertenece el trazado (vacío si se creó a mano, por ejemplo en pruebas).
var map_id: String = ""
## Estilo del tablero (cómo se construye en 3D: "garden", "deck", "causeway", ...).
var style: String = ""
## Casillas especiales en el orden del archivo (para validarlas) y por número de casilla.
## Cada una: {tile, kind, name, ref, steps, stars, good}.
var special_list: Array[Dictionary] = []
var specials: Dictionary = {}


## Crea el trazado a partir de una entrada de MapCatalog.
static func from_map(map_data: Dictionary) -> BoardLayout:
	var layout := BoardLayout.new()
	var board: Dictionary = map_data.get("board", {})
	layout.map_id = str(map_data.get("id", ""))
	layout.columns = maxi(2, int(board.get("columns", 10)))
	layout.rows = maxi(2, int(board.get("rows", 10)))
	layout.style = str(board.get("style", ""))
	layout.ladders = _to_pairs(board.get("ladders", []))
	layout.snakes = _to_pairs(board.get("snakes", []))
	var tiles: Variant = board.get("challenge_tiles", [])
	if tiles is Array and not (tiles as Array).is_empty():
		for tile in tiles:
			layout.challenge_tiles.append(int(tile))
	else:
		layout.challenge_tiles = layout.default_challenge_tiles()
	layout._read_specials(board.get("rewards", []), true)
	layout._read_specials(board.get("obstacles", []), false)
	return layout


func _read_specials(raw: Variant, good: bool) -> void:
	if not (raw is Array):
		return
	for entry in raw:
		if not (entry is Dictionary):
			continue
		var info: Dictionary = {
			"tile": int(entry.get("tile", 0)),
			"kind": str(entry.get("kind", "")),
			"name": str(entry.get("name", "")),
			"ref": str(entry.get("ref", "")),
			"steps": int(entry.get("steps", 0)),
			"stars": int(entry.get("stars", 0)),
			"good": good,
		}
		special_list.append(info)
		specials[int(info["tile"])] = info


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


## La casilla especial de esa casilla ({} si es una casilla normal). Es una copia.
func special_at(tile: int) -> Dictionary:
	if specials.has(tile):
		return (specials[tile] as Dictionary).duplicate()
	return {}


func is_special_tile(tile: int) -> bool:
	return specials.has(tile)


## Números de las casillas especiales, de menor a mayor.
func special_tiles() -> Array[int]:
	var result: Array[int] = []
	for tile in specials:
		result.append(int(tile))
	result.sort()
	return result


## Cuántas casillas especiales hay: de recompensa (good = true) o de obstáculo (good = false).
func special_count(good: bool) -> int:
	var count: int = 0
	for info in special_list:
		if bool(info["good"]) == good:
			count += 1
	return count


## Una casilla "tranquila" no es inicio ni meta y no tiene escalera, serpiente, desafío ni
## casilla especial: caer en ella no provoca nada.
func is_quiet(tile: int) -> bool:
	return tile > 1 and tile < last_tile() and jump_kind(tile) == "" \
			and not is_challenge_tile(tile) and not is_special_tile(tile)


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
	problems.append_array(_check_specials(total))
	return problems


func _check_specials(total: int) -> PackedStringArray:
	var problems := PackedStringArray()
	var reserved: Dictionary = reserved_tiles()
	var seen: Dictionary = {}
	for info in special_list:
		var tile: int = int(info["tile"])
		var kind: String = str(info["kind"])
		var label: String = "Casilla especial %d" % tile
		if tile < 1 or tile > total:
			problems.append("%s: fuera del tablero (1-%d)" % [label, total])
		elif reserved.has(tile):
			problems.append("%s: está reservada (inicio, meta, escalera o serpiente)" % label)
		elif is_challenge_tile(tile):
			problems.append("%s: ya es una casilla de desafío" % label)
		if seen.has(tile):
			problems.append("%s: está repetida" % label)
		seen[tile] = true
		if str(info["name"]).strip_edges().is_empty():
			problems.append("%s: no tiene nombre" % label)
		var allowed: Array[String] = REWARD_KINDS if bool(info["good"]) else OBSTACLE_KINDS
		if not allowed.has(kind):
			problems.append("%s: el tipo '%s' no es válido aquí" % [label, kind])
		if kind == SPECIAL_ADVANCE or kind == SPECIAL_BACK:
			var steps: int = int(info["steps"])
			if steps < MIN_SPECIAL_STEPS or steps > MAX_SPECIAL_STEPS:
				problems.append("%s: las casillas deben ser de %d a %d" % [label, MIN_SPECIAL_STEPS, MAX_SPECIAL_STEPS])
		if kind == SPECIAL_STARS:
			var stars: int = int(info["stars"])
			if stars < 1 or stars > MAX_SPECIAL_STARS:
				problems.append("%s: las estrellas deben ser de 1 a %d" % [label, MAX_SPECIAL_STARS])
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
