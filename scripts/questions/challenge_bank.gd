class_name ChallengeBank
extends RefCounted
## Banco de desafíos bíblicos (data/questions/challenges.json).
## Los desafíos son originales; las referencias son pasajes reales que se pueden comprobar
## en cualquier Biblia. No se guarda ningún texto bíblico textual: el texto de una versión
## (por ejemplo RVR1960) solo se mostraría a través de VerseProvider y con autorización.

const DATA_PATH := "res://data/questions/challenges.json"

static var _items: Array[Challenge] = []
static var _problems: PackedStringArray = PackedStringArray()
static var _loaded: bool = false


static func reload() -> void:
	_loaded = false
	_ensure_loaded()


## Todos los desafíos válidos.
static func all() -> Array[Challenge]:
	_ensure_loaded()
	return _items


## Problemas encontrados al cargar (entradas inválidas o ids repetidos). Vacío si todo está bien.
static func load_problems() -> PackedStringArray:
	_ensure_loaded()
	return _problems


static func by_type(type: String) -> Array[Challenge]:
	_ensure_loaded()
	var result: Array[Challenge] = []
	for item in _items:
		if item.type == type:
			result.append(item)
	return result


## Desafíos propios de un mapa (no incluye los generales). Con un id vacío no devuelve nada.
static func for_map(map_id: String) -> Array[Challenge]:
	_ensure_loaded()
	var result: Array[Challenge] = []
	if map_id.is_empty():
		return result
	for item in _items:
		if item.map_id == map_id:
			result.append(item)
	return result


## Desafíos de un tipo que son propios de un mapa.
static func by_type_for_map(type: String, map_id: String) -> Array[Challenge]:
	var result: Array[Challenge] = []
	for item in for_map(map_id):
		if item.type == type:
			result.append(item)
	return result


## Desafíos generales (los que valen en cualquier mapa) de un tipo.
static func general_by_type(type: String) -> Array[Challenge]:
	_ensure_loaded()
	var result: Array[Challenge] = []
	for item in _items:
		if item.type == type and item.map_id.is_empty():
			result.append(item)
	return result


## Cuántos desafíos propios tiene un mapa de cada tipo.
static func count_for_map(map_id: String) -> Dictionary:
	var counts: Dictionary = {}
	for type in Challenge.TYPES:
		counts[type] = 0
	for item in for_map(map_id):
		counts[item.type] = int(counts[item.type]) + 1
	return counts


## Cuántos desafíos hay de cada tipo.
static func count_by_type() -> Dictionary:
	_ensure_loaded()
	var counts: Dictionary = {}
	for type in Challenge.TYPES:
		counts[type] = 0
	for item in _items:
		counts[item.type] = int(counts[item.type]) + 1
	return counts


static func find(id: String) -> Challenge:
	_ensure_loaded()
	for item in _items:
		if item.id == id:
			return item
	return null


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_items = []
	_problems = PackedStringArray()
	var data: Dictionary = JsonLoader.load_dictionary(DATA_PATH)
	var list: Variant = data.get("challenges", [])
	if not (list is Array):
		_problems.append("challenges.json no tiene la lista 'challenges'")
		return
	var seen: Dictionary = {}
	for entry in list:
		if not (entry is Dictionary):
			_problems.append("hay una entrada que no es un objeto")
			continue
		var item: Challenge = Challenge.from_dict(entry)
		var found: PackedStringArray = item.problems()
		if seen.has(item.id):
			found.append("%s: el id está repetido" % item.id)
		seen[item.id] = true
		if found.is_empty():
			_items.append(item)
		else:
			_problems.append_array(found)
