class_name ProgressData
extends RefCounted
## Progreso del jugador en el mundo bíblico, sin nodos ni archivos: qué mapas tiene abiertos,
## cuáles completó, qué insignias ganó y las estadísticas de cada región. Se puede probar con
## partidas simuladas; ProgressManager (autoload) es quien lo guarda en el teléfono.
##
## Reglas:
##   - El primer mapa está abierto desde el principio.
##   - Cada mapa se abre al completar el mapa que pide ("unlock.requires" en maps.json).
##   - Un mapa se completa cuando alguien llega a la meta en una partida terminada.
##   - La primera vez que se completa un mapa da estrellas del viaje y su insignia.

const FORMAT_VERSION := 1

## Insignias de logros generales (además de la insignia de cada mapa, que viene de maps.json).
## "kind": maps = mapas completados, maps_all = todos los mapas, correct = desafíos acertados,
## stars = estrellas ganadas en desafíos y casillas especiales.
const GLOBAL_BADGES: Array = [
	{"id": "viajero", "name": "Viajero", "text": "Completa 3 mundos bíblicos.", "kind": "maps", "goal": 3},
	{"id": "peregrino", "name": "Peregrino", "text": "Completa todos los mundos bíblicos.", "kind": "maps_all", "goal": 0},
	{"id": "sabio", "name": "Sabio", "text": "Acierta 30 desafíos bíblicos.", "kind": "correct", "goal": 30},
	{"id": "coleccionista", "name": "Coleccionista de estrellas", "text": "Gana 60 estrellas.", "kind": "stars", "goal": 60},
]

const STATUS_LOCKED := "locked"
const STATUS_AVAILABLE := "available"
const STATUS_COMPLETED := "completed"

## Mapas abiertos, mapas completados e insignias ganadas (id -> true).
var unlocked: Dictionary = {}
var completed: Dictionary = {}
var badges: Dictionary = {}
## Estadísticas por mapa (id -> diccionario, ver empty_region()).
var regions: Dictionary = {}
## Estrellas del viaje: las que dan los mapas al completarlos por primera vez.
var journey_stars: int = 0


## Progreso de una instalación nueva: solo el primer mapa está abierto.
static func new_game() -> ProgressData:
	var data := ProgressData.new()
	data.refresh_unlocks()
	return data


## Estadísticas vacías de una región.
static func empty_region() -> Dictionary:
	return {
		"plays": 0,
		"completions": 0,
		"best_time": 0.0,
		"best_turns": 0,
		"challenges": 0,
		"correct": 0,
		"stars": 0,
		"best_stars": 0,
		"ladders": 0,
		"snakes": 0,
		"rolls": 0,
		"specials": 0,
	}


# ---------------------------------------------------------------- Consultas

func is_unlocked(map_id: String) -> bool:
	return unlocked.has(map_id)


func is_completed(map_id: String) -> bool:
	return completed.has(map_id)


func has_badge(badge_id: String) -> bool:
	return badges.has(badge_id)


## "locked", "available" o "completed".
func status_of(map_id: String) -> String:
	if completed.has(map_id):
		return STATUS_COMPLETED
	if unlocked.has(map_id):
		return STATUS_AVAILABLE
	return STATUS_LOCKED


## Estadísticas de un mapa (una copia con todos los campos, aunque nunca se haya jugado).
func region(map_id: String) -> Dictionary:
	var result: Dictionary = empty_region()
	var saved: Variant = regions.get(map_id, null)
	if saved is Dictionary:
		for key in result:
			if (saved as Dictionary).has(key):
				result[key] = (saved as Dictionary)[key]
	return result


func map_total() -> int:
	return MapCatalog.playable_maps().size()


func completed_count() -> int:
	var count: int = 0
	for entry in MapCatalog.playable_maps():
		if completed.has(str(entry["id"])):
			count += 1
	return count


func unlocked_count() -> int:
	var count: int = 0
	for entry in MapCatalog.playable_maps():
		if unlocked.has(str(entry["id"])):
			count += 1
	return count


## Avance del viaje de 0.0 a 1.0 (mapas completados entre mapas totales).
func completion_ratio() -> float:
	var total: int = map_total()
	return float(completed_count()) / float(total) if total > 0 else 0.0


func total_correct() -> int:
	var total: int = 0
	for stats in regions.values():
		total += int((stats as Dictionary).get("correct", 0))
	return total


func total_stars_won() -> int:
	var total: int = 0
	for stats in regions.values():
		total += int((stats as Dictionary).get("stars", 0))
	return total


func total_plays() -> int:
	var total: int = 0
	for stats in regions.values():
		total += int((stats as Dictionary).get("plays", 0))
	return total


## Todas las insignias con su estado: primero las de cada mapa (en orden) y luego las generales.
## Cada una: {id, name, text, earned, map} (map vacío en las generales).
func all_badges() -> Array:
	var list: Array = []
	for entry in MapCatalog.playable_maps():
		var badge: Dictionary = MapCatalog.badge_of(str(entry["id"]))
		if badge.is_empty():
			continue
		badge["earned"] = badges.has(str(badge["id"]))
		list.append(badge)
	for entry in GLOBAL_BADGES:
		var info: Dictionary = entry
		list.append({
			"id": str(info["id"]),
			"name": str(info["name"]),
			"text": str(info["text"]),
			"earned": badges.has(str(info["id"])),
			"map": "",
		})
	return list


func badge_counts() -> Vector2i:
	var earned: int = 0
	var list: Array = all_badges()
	for entry in list:
		if bool((entry as Dictionary)["earned"]):
			earned += 1
	return Vector2i(earned, list.size())


# ---------------------------------------------------------------- Cambios

## Abre los mapas cuyo requisito ya está cumplido. Devuelve los que se abrieron ahora.
func refresh_unlocks() -> Array[String]:
	var opened: Array[String] = []
	for map_id in MapCatalog.ids_in_order():
		var needs: String = MapCatalog.requirement_of(map_id)
		if (needs.is_empty() or completed.has(needs)) and not unlocked.has(map_id):
			unlocked[map_id] = true
			opened.append(map_id)
	return opened


## Abre todos los mapas (no guarda nada: sirve para pruebas y para jugar sin avanzar en orden).
func unlock_everything() -> void:
	for map_id in MapCatalog.ids_in_order():
		unlocked[map_id] = true


## Anota que empezó una partida en ese mapa.
func record_start(map_id: String) -> void:
	if MapCatalog.find_map(map_id).is_empty():
		return
	var stats: Dictionary = _region(map_id)
	stats["plays"] = int(stats["plays"]) + 1


## Anota una partida terminada (el resumen de MatchState.summary()) y devuelve el informe:
##   ok, map_id, first_completion, reward_stars, badge ({} si no hay), unlocked_maps (ids),
##   new_badges (lista de {id, name, text}), journey_stars, completed, total
func record_match(map_id: String, summary: Dictionary) -> Dictionary:
	var report: Dictionary = {
		"ok": false,
		"map_id": map_id,
		"first_completion": false,
		"reward_stars": 0,
		"badge": {},
		"unlocked_maps": [],
		"new_badges": [],
		"journey_stars": journey_stars,
		"completed": completed_count(),
		"total": map_total(),
	}
	if MapCatalog.find_map(map_id).is_empty() or not bool(summary.get("finished", false)):
		return report
	report["ok"] = true

	var stats: Dictionary = _region(map_id)
	stats["completions"] = int(stats["completions"]) + 1
	var duration: float = float(summary.get("duration", 0.0))
	if duration > 0.0 and (float(stats["best_time"]) <= 0.0 or duration < float(stats["best_time"])):
		stats["best_time"] = duration
	var turns: int = int(summary.get("turns", 0))
	if turns > 0 and (int(stats["best_turns"]) <= 0 or turns < int(stats["best_turns"])):
		stats["best_turns"] = turns
	stats["challenges"] = int(stats["challenges"]) + int(summary.get("total_challenges", 0))
	stats["correct"] = int(stats["correct"]) + int(summary.get("total_correct", 0))
	var players: Variant = summary.get("players", [])
	if players is Array:
		for entry in players:
			var player: Dictionary = entry
			var player_stats: Dictionary = player.get("stats", {})
			var player_stars: int = int(player.get("stars", 0))
			stats["stars"] = int(stats["stars"]) + player_stars
			stats["best_stars"] = maxi(int(stats["best_stars"]), player_stars)
			stats["ladders"] = int(stats["ladders"]) + int(player_stats.get("ladders", 0))
			stats["snakes"] = int(stats["snakes"]) + int(player_stats.get("snakes", 0))
			stats["rolls"] = int(stats["rolls"]) + int(player_stats.get("rolls", 0))
			stats["specials"] = int(stats["specials"]) + int(player_stats.get("specials", 0))

	var new_badges: Array = []
	if not completed.has(map_id):
		completed[map_id] = true
		report["first_completion"] = true
		var reward: int = MapCatalog.reward_stars_of(map_id)
		journey_stars += reward
		report["reward_stars"] = reward
		var badge: Dictionary = MapCatalog.badge_of(map_id)
		if not badge.is_empty() and not badges.has(str(badge["id"])):
			badges[str(badge["id"])] = true
			report["badge"] = badge
			new_badges.append(badge)
	report["unlocked_maps"] = refresh_unlocks()
	new_badges.append_array(_award_global_badges())
	report["new_badges"] = new_badges
	report["journey_stars"] = journey_stars
	report["completed"] = completed_count()
	return report


func _award_global_badges() -> Array:
	var gained: Array = []
	for entry in GLOBAL_BADGES:
		var info: Dictionary = entry
		var badge_id: String = str(info["id"])
		if badges.has(badge_id) or not _goal_met(info):
			continue
		badges[badge_id] = true
		gained.append({"id": badge_id, "name": str(info["name"]), "text": str(info["text"]), "map": ""})
	return gained


func _goal_met(info: Dictionary) -> bool:
	match str(info["kind"]):
		"maps":
			return completed_count() >= int(info["goal"])
		"maps_all":
			return map_total() > 0 and completed_count() >= map_total()
		"correct":
			return total_correct() >= int(info["goal"])
		"stars":
			return total_stars_won() >= int(info["goal"])
	return false


func _region(map_id: String) -> Dictionary:
	if not regions.has(map_id):
		regions[map_id] = empty_region()
	return regions[map_id]


# ---------------------------------------------------------------- Guardado

## Datos listos para guardar (solo diccionarios, arreglos y números).
func to_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"unlocked": unlocked.keys(),
		"completed": completed.keys(),
		"badges": badges.keys(),
		"regions": regions.duplicate(true),
		"journey_stars": journey_stars,
	}


## Reconstruye el progreso desde lo guardado. Tolera datos incompletos o raros.
static func from_dict(raw: Dictionary) -> ProgressData:
	var data := ProgressData.new()
	_read_ids(raw.get("unlocked", []), data.unlocked)
	_read_ids(raw.get("completed", []), data.completed)
	_read_ids(raw.get("badges", []), data.badges)
	var saved_regions: Variant = raw.get("regions", {})
	if saved_regions is Dictionary:
		for key in saved_regions:
			var saved: Variant = (saved_regions as Dictionary)[key]
			if not (saved is Dictionary):
				continue
			var stats: Dictionary = empty_region()
			for field in stats:
				if (saved as Dictionary).has(field):
					if field == "best_time":
						stats[field] = maxf(0.0, float((saved as Dictionary)[field]))
					else:
						stats[field] = maxi(0, int((saved as Dictionary)[field]))
			data.regions[str(key)] = stats
	data.journey_stars = maxi(0, int(raw.get("journey_stars", 0)))
	# Completar un mapa siempre deja abierto el siguiente, aunque el archivo no lo diga.
	data.refresh_unlocks()
	return data


static func _read_ids(raw: Variant, target: Dictionary) -> void:
	if raw is Array:
		for entry in raw:
			var id: String = str(entry)
			if not id.is_empty():
				target[id] = true
