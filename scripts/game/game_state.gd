extends Node
## Autoload "GameState": selección actual (mapa, personaje, jugadores) y su guardado.
## Solo se pueden elegir los mapas que el jugador ya tiene abiertos (ver ProgressManager).

signal selection_changed

const PROFILE_PATH := "user://profile.cfg"
const MIN_PLAYERS := 1
const MAX_PLAYERS := 4

var selected_map_id: String = ""
var selected_character_id: String = ""
var player_count: int = 1
## Resumen de la última partida terminada (lo usa la pantalla de victoria).
var last_summary: Dictionary = {}
## Informe de progreso de esa partida (ProgressData.record_match): mapa completado, recompensa,
## insignias y mapas que se abrieron. Vacío si la partida no se anotó.
var last_progress: Dictionary = {}


func _ready() -> void:
	_load()
	ensure_valid_selection()


## Corrige la selección si apunta a algo que ya no existe, que aún no es jugable o que el
## jugador todavía no tiene abierto.
func ensure_valid_selection() -> void:
	if not can_select_map(selected_map_id):
		selected_map_id = MapCatalog.default_map_id()
	if CharacterCatalog.find_character(selected_character_id).is_empty():
		selected_character_id = CharacterCatalog.default_character_id()
	player_count = clampi(player_count, MIN_PLAYERS, MAX_PLAYERS)


## Verdadero si el mapa existe, está hecho y el jugador ya lo desbloqueó.
func can_select_map(id: String) -> bool:
	return MapCatalog.is_playable(id) and ProgressManager.is_unlocked(id)


## Elige el mapa donde se jugará. Un mapa bloqueado no se puede elegir. Devuelve si se eligió.
func select_map(id: String) -> bool:
	if not can_select_map(id):
		return false
	selected_map_id = id
	_changed()
	return true


func select_character(id: String) -> void:
	if CharacterCatalog.find_character(id).is_empty():
		return
	selected_character_id = id
	_changed()


func set_player_count(value: int) -> void:
	player_count = clampi(value, MIN_PLAYERS, MAX_PLAYERS)
	_changed()


## Lista de jugadores de la partida: el jugador 1 usa el personaje elegido y
## los demás reciben los siguientes del catálogo, sin repetir.
func build_roster() -> Array:
	var order: Array[String] = [selected_character_id]
	for id in CharacterCatalog.all_ids():
		if id != selected_character_id:
			order.append(id)
	var roster: Array = []
	for index in player_count:
		var character: Dictionary = CharacterCatalog.find_character(order[index % order.size()])
		roster.append({
			"index": index,
			"character_id": character["id"],
			"name": character["name"],
			"color": character["color"],
		})
	return roster


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "map", selected_map_id)
	cfg.set_value("profile", "character", selected_character_id)
	cfg.set_value("profile", "players", player_count)
	var err: int = cfg.save(PROFILE_PATH)
	if err != OK:
		push_warning("GameState: no se pudo guardar el perfil (error %d)" % err)


func _changed() -> void:
	save()
	selection_changed.emit()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) != OK:
		return
	selected_map_id = str(cfg.get_value("profile", "map", ""))
	selected_character_id = str(cfg.get_value("profile", "character", ""))
	player_count = int(cfg.get_value("profile", "players", 1))
