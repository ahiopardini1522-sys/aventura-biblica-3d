class_name MessageBank
extends RefCounted
## Mensajes motivadores cristianos que salen durante la partida (data/messages/messages.json).
## Son frases originales de ánimo; no son citas de la Biblia.

const DATA_PATH := "res://data/messages/messages.json"
const CATEGORIES: Array[String] = [
	"start", "challenge", "correct", "wrong", "ladder", "snake",
	"skip", "last_stretch", "victory",
]

static var _messages: Dictionary = {}
static var _loaded: bool = false


## Todos los mensajes de una categoría.
static func all_in(category: String) -> PackedStringArray:
	_ensure_loaded()
	var result := PackedStringArray()
	var list: Variant = _messages.get(category, [])
	if list is Array:
		for text in list:
			result.append(str(text))
	return result


## Un mensaje de la categoría (al azar si se da un generador, si no el primero).
static func pick(category: String, rng: RandomNumberGenerator = null) -> String:
	var list: PackedStringArray = all_in(category)
	if list.is_empty():
		return ""
	if rng == null:
		return list[0]
	return list[rng.randi_range(0, list.size() - 1)]


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Dictionary = JsonLoader.load_dictionary(DATA_PATH)
	_messages = data.get("messages", {})
