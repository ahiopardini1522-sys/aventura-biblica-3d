class_name VerseProvider
extends RefCounted
## Acceso a los versículos del juego. Hoy solo hay referencias (libro, capítulo, versículo):
## el texto de una versión con derechos de autor, como Reina-Valera 1960 (RVR1960), no se
## incluye hasta contar con la autorización de quien la publica.
##
## Para activar una versión autorizada más adelante:
##   1. Crear data/verses/<archivo>.json con {"verses": {"<verse_id>": "<texto>"}}.
##   2. En data/verses/translations.json poner en esa versión "status": "authorized"
##      y "enabled": true.
## Mientras tanto text_of() devuelve "" y el juego muestra solo la referencia.

const REFERENCES_PATH := "res://data/verses/verse_references.json"
const TRANSLATIONS_PATH := "res://data/verses/translations.json"
const VERSES_DIR := "res://data/verses/"
const STATUS_AUTHORIZED := "authorized"

static var _references: Dictionary = {}
static var _translations: Array = []
static var _texts: Dictionary = {}
static var _loaded: bool = false
## Versión de prueba en memoria (nunca se guarda ni se incluye en el juego).
static var _test_translation: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_texts.clear()
	_ensure_loaded()


## Todas las entradas de data/verses/verse_references.json, por id.
static func references() -> Dictionary:
	_ensure_loaded()
	return _references


static func has_reference(verse_id: String) -> bool:
	_ensure_loaded()
	return _references.has(verse_id)


## Referencia legible ("Salmos 23:1") de un versículo, o "" si no existe.
static func reference_of(verse_id: String) -> String:
	_ensure_loaded()
	if not _references.has(verse_id):
		return ""
	return str((_references[verse_id] as Dictionary).get("reference", ""))


## Versiones previstas (autorizadas o no), tal como están en translations.json.
static func translations() -> Array:
	_ensure_loaded()
	return _translations


## Versión cuyo texto puede mostrarse, o {} si todavía no hay ninguna autorizada.
static func active_translation() -> Dictionary:
	_ensure_loaded()
	if not _test_translation.is_empty():
		return _test_translation
	for entry in _translations:
		var translation: Dictionary = entry
		if bool(translation.get("enabled", false)) \
				and str(translation.get("status", "")) == STATUS_AUTHORIZED:
			return translation
	return {}


## Texto del versículo en la versión activa, o "" si no hay versión autorizada o falta el texto.
static func text_of(verse_id: String) -> String:
	var translation: Dictionary = active_translation()
	if translation.is_empty():
		return ""
	if not _test_translation.is_empty():
		return str((_test_translation.get("texts", {}) as Dictionary).get(verse_id, ""))
	var key: String = str(translation.get("id", ""))
	if not _texts.has(key):
		var file_name: String = str(translation.get("text_file", ""))
		var verses: Dictionary = {}
		if not file_name.is_empty() and FileAccess.file_exists(VERSES_DIR + file_name):
			var data: Dictionary = JsonLoader.load_dictionary(VERSES_DIR + file_name)
			verses = data.get("verses", {})
		_texts[key] = verses
	return str((_texts[key] as Dictionary).get(verse_id, ""))


## Nota de atribución que debe acompañar al texto (vacía si no hay versión activa).
static func attribution() -> String:
	var translation: Dictionary = active_translation()
	if translation.is_empty():
		return ""
	return "%s · %s" % [str(translation.get("name", "")), str(translation.get("publisher", ""))]


## Solo para pruebas automáticas: activa una versión falsa en memoria.
static func use_test_translation(texts: Dictionary) -> void:
	_test_translation = {
		"id": "prueba",
		"name": "Versión de prueba",
		"publisher": "solo pruebas",
		"texts": texts,
	}


static func clear_test_translation() -> void:
	_test_translation = {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_references = {}
	_translations = []
	var refs: Dictionary = JsonLoader.load_dictionary(REFERENCES_PATH)
	var verse_list: Variant = refs.get("verses", [])
	if verse_list is Array:
		for entry in verse_list:
			if entry is Dictionary:
				_references[str((entry as Dictionary).get("id", ""))] = entry
	var info: Dictionary = JsonLoader.load_dictionary(TRANSLATIONS_PATH)
	var translation_list: Variant = info.get("translations", [])
	if translation_list is Array:
		for entry in translation_list:
			if entry is Dictionary:
				_translations.append(entry)
