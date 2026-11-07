extends Node
## Autoload "GameState": selección actual (mapa, personaje, jugadores) y su guardado.
## Las reglas del juego se agregarán en etapas posteriores.

signal selection_changed

const PROFILE_PATH := "user://profile.cfg"
const MIN_PLAYERS := 1
const MAX_PLAYERS := 4

var selected_map_id: String = ""
var selected_character_id: String = ""
var player_count: int = 1


func _ready() -> void:
	_load()
	ensure_valid_selection()


## Corrige la selección si apunta a algo que ya no existe o que aún no es jugable.
func ensure_valid_selection() -> void:
	if not MapCatalog.is_playable(selected_map_id):
		selected_map_id = MapCatalog.default_map_id()
	if CharacterCatalog.find_character(selected_character_id).is_empty():
		selected_character_id = CharacterCatalog.default_character_id()
	player_count = clampi(player_count, MIN_PLAYERS, MAX_PLAYERS)


func select_map(id: String) -> void:
	if not MapCatalog.is_playable(id):
		return
	selected_map_id = id
	_changed()


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
