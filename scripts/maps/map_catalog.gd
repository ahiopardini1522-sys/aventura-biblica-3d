class_name MapCatalog
extends RefCounted
## Catálogo de mapas bíblicos. Lee data/maps/maps.json.
## Cada mapa trae su tema visual, su lugar en el mundo, cómo se desbloquea, su recompensa y la
## definición de su tablero (escaleras, serpientes, desafíos y casillas especiales).

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


## Solo los mapas que ya están hechos (estado "available"). Que se puedan abrir depende además
## del progreso del jugador (ver ProgressData).
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


## Id del primer mapa jugable ("" si no hay ninguno): el que está abierto desde el comienzo.
static func default_map_id() -> String:
	var playable: Array = playable_maps()
	if playable.is_empty():
		return ""
	return str(playable[0]["id"])


## Ids de todos los mapas, en orden.
static func ids_in_order() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for entry in _maps:
		ids.append(str(entry["id"]))
	return ids


## Nombre del mapa ("" si no existe).
static func name_of(id: String) -> String:
	return str(find_map(id).get("name", ""))


## Id del mapa que hay que completar antes de abrir este ("" si está abierto desde el inicio).
static func requirement_of(id: String) -> String:
	var unlock: Dictionary = find_map(id).get("unlock", {})
	return str(unlock.get("requires", ""))


## Ids de los mapas que se abren al completar este.
static func unlocked_by(id: String) -> Array[String]:
	_ensure_loaded()
	var result: Array[String] = []
	for entry in _maps:
		var map_id: String = str(entry["id"])
		if map_id != id and requirement_of(map_id) == id:
			result.append(map_id)
	return result


## Posición del mapa en el mundo bíblico (x hacia el este, y es la z del mundo 3D).
static func world_position(id: String) -> Vector2:
	var world: Dictionary = find_map(id).get("world", {})
	return Vector2(float(world.get("x", 0.0)), float(world.get("z", 0.0)))


## Insignia que se gana al completar el mapa: {id, name, text} o {} si no tiene.
static func badge_of(id: String) -> Dictionary:
	var reward: Dictionary = find_map(id).get("reward", {})
	var badge_id: String = str(reward.get("badge", ""))
	if badge_id.is_empty():
		return {}
	return {
		"id": badge_id,
		"name": str(reward.get("badge_name", badge_id)),
		"text": str(reward.get("badge_text", "")),
		"map": id,
	}


## Estrellas del viaje que da completar el mapa por primera vez.
static func reward_stars_of(id: String) -> int:
	var reward: Dictionary = find_map(id).get("reward", {})
	return maxi(0, int(reward.get("stars", 0)))


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
	var id: String = str(entry.get("id", ""))
	var world_in: Dictionary = entry.get("world", {})
	var unlock_in: Dictionary = entry.get("unlock", {})
	var reward_in: Dictionary = entry.get("reward", {})
	var ambience_in: Dictionary = entry.get("ambience", {})
	var lighting_in: Dictionary = entry.get("lighting", {})
	return {
		"id": id,
		"order": int(entry.get("order", 999)),
		"name": str(entry.get("name", "Mapa")),
		"reference": str(entry.get("reference", "")),
		"description": str(entry.get("description", "")),
		"status": str(entry.get("status", STATUS_COMING_SOON)),
		"style": str(entry.get("style", id)),
		"world": {
			"x": float(world_in.get("x", 0.0)),
			"z": float(world_in.get("z", 0.0)),
			"icon": str(world_in.get("icon", "")),
		},
		"unlock": {"requires": str(unlock_in.get("requires", ""))},
		"reward": {
			"stars": int(reward_in.get("stars", 0)),
			"badge": str(reward_in.get("badge", "")),
			"badge_name": str(reward_in.get("badge_name", "")),
			"badge_text": str(reward_in.get("badge_text", "")),
		},
		"ambience": {"sound": str(ambience_in.get("sound", ""))},
		"lighting": lighting_in.duplicate(true),
		"theme": theme_out,
		"board": {
			"columns": int(board_in.get("columns", 10)),
			"rows": int(board_in.get("rows", 10)),
			"style": str(board_in.get("style", "")),
			"ladders": board_in.get("ladders", []),
			"snakes": board_in.get("snakes", []),
			"challenge_tiles": board_in.get("challenge_tiles", []),
			"rewards": board_in.get("rewards", []),
			"obstacles": board_in.get("obstacles", []),
		},
	}
