class_name MapCatalog
extends RefCounted
## Catálogo de mapas bíblicos. Lee data/maps/maps.json.
## Cada mapa trae su tema visual y la definición de su tablero (escaleras y serpientes).

const DATA_PATH := "res://data/maps/maps.json"
const STATUS_AVAILABLE := "available"
const STATUS_COMING_SOON := "coming_soon"

static var _maps: Array = []
static var _loaded: bool = false


static func reload() -> void:
	_loaded = false
	_ensure_loaded()


## Todos los mapas, ordenados por el campo "order".
static func all_maps() -> Array:
	_ensure_loaded()
	return _maps


## Solo los mapas jugables en esta etapa.
static func playable_maps() -> Array:
	_ensure_loaded()
	var result: Array = []
	for entry in _maps:
		if str(entry["status"]) == STATUS_AVAILABLE:
			result.append(entry)
	return result


## Devuelve el mapa con ese id, o {} si no existe.
static func find_map(id: String) -> Dictionary:
	_ensure_loaded()
	for entry in _maps:
		if str(entry["id"]) == id:
			return entry
	return {}


static func is_playable(id: String) -> bool:
	var map_data: Dictionary = find_map(id)
	return not map_data.is_empty() and str(map_data["status"]) == STATUS_AVAILABLE


## Id del primer mapa jugable ("" si no hay ninguno).
static func default_map_id() -> String:
	var playable: Array = playable_maps()
	if playable.is_empty():
		return ""
	return str(playable[0]["id"])


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_maps = []
	var data: Dictionary = JsonLoader.load_dictionary(DATA_PATH)
	var list: Variant = data.get("maps", [])
	if list is Array:
		for entry in list:
			if entry is Dictionary:
				_maps.append(_normalize(entry))
	_maps.sort_custom(_sort_by_order)


static func _sort_by_order(a: Dictionary, b: Dictionary) -> bool:
	return int(a["order"]) < int(b["order"])


## Completa los campos que falten y convierte los colores "#rrggbb" en Color.
static func _normalize(entry: Dictionary) -> Dictionary:
	var theme_in: Dictionary = entry.get("theme", {})
	var theme_out: Dictionary = {}
	for key in theme_in:
		var value: Variant = theme_in[key]
		if value is String and str(value).begins_with("#"):
			theme_out[key] = Color.html(str(value))
		else:
			theme_out[key] = value
	var board_in: Dictionary = entry.get("board", {})
	return {
		"id": str(entry.get("id", "")),
		"order": int(entry.get("order", 999)),
		"name": str(entry.get("name", "Mapa")),
		"reference": str(entry.get("reference", "")),
		"description": str(entry.get("description", "")),
		"status": str(entry.get("status", STATUS_COMING_SOON)),
		"theme": theme_out,
		"board": {
			"columns": int(board_in.get("columns", 10)),
			"rows": int(board_in.get("rows", 10)),
			"ladders": board_in.get("ladders", []),
			"snakes": board_in.get("snakes", []),
			"challenge_tiles": board_in.get("challenge_tiles", []),
		},
	}
