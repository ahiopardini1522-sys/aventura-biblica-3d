class_name BibleReference
extends RefCounted
## Validador de referencias bíblicas como "Génesis 7:12", "Éxodo 14:21-22", "Josué 3" o
## "Mateo 2:1; Lucas 2:4-7". Comprueba que el libro exista y que el capítulo esté dentro
## del número real de capítulos de ese libro (los 66 libros suman 1189 capítulos).
## No guarda ningún texto bíblico: solo sirve para que las referencias del juego sean verificables.

## Libros con su número de capítulos, en el orden de la Biblia protestante.
const BOOKS: Array = [
	["Génesis", 50], ["Éxodo", 40], ["Levítico", 27], ["Números", 36], ["Deuteronomio", 34],
	["Josué", 24], ["Jueces", 21], ["Rut", 4], ["1 Samuel", 31], ["2 Samuel", 24],
	["1 Reyes", 22], ["2 Reyes", 25], ["1 Crónicas", 29], ["2 Crónicas", 36], ["Esdras", 10],
	["Nehemías", 13], ["Ester", 10], ["Job", 42], ["Salmos", 150], ["Proverbios", 31],
	["Eclesiastés", 12], ["Cantares", 8], ["Isaías", 66], ["Jeremías", 52], ["Lamentaciones", 5],
	["Ezequiel", 48], ["Daniel", 12], ["Oseas", 14], ["Joel", 3], ["Amós", 9],
	["Abdías", 1], ["Jonás", 4], ["Miqueas", 7], ["Nahúm", 3], ["Habacuc", 3],
	["Sofonías", 3], ["Hageo", 2], ["Zacarías", 14], ["Malaquías", 4],
	["Mateo", 28], ["Marcos", 16], ["Lucas", 24], ["Juan", 21], ["Hechos", 28],
	["Romanos", 16], ["1 Corintios", 16], ["2 Corintios", 13], ["Gálatas", 6], ["Efesios", 6],
	["Filipenses", 4], ["Colosenses", 4], ["1 Tesalonicenses", 5], ["2 Tesalonicenses", 3],
	["1 Timoteo", 6], ["2 Timoteo", 4], ["Tito", 3], ["Filemón", 1], ["Hebreos", 13],
	["Santiago", 5], ["1 Pedro", 5], ["2 Pedro", 3], ["1 Juan", 5], ["2 Juan", 1],
	["3 Juan", 1], ["Judas", 1], ["Apocalipsis", 22],
]
## Otros nombres admitidos para el mismo libro.
const ALIASES := {
	"salmo": "Salmos",
	"cantar de los cantares": "Cantares",
	"cantares de salomon": "Cantares",
	"apocalipsis de juan": "Apocalipsis",
}
const EXPECTED_BOOKS := 66
const EXPECTED_CHAPTERS := 1189
## El capítulo con más versículos de la Biblia (Salmo 119) tiene 176.
const MAX_VERSE := 176

static var _index: Dictionary = {}


## Suma de capítulos de todos los libros (debe ser 1189).
static func total_chapters() -> int:
	var total: int = 0
	for entry in BOOKS:
		total += int((entry as Array)[1])
	return total


## Capítulos del libro (admite "Salmo" y "Salmos", con o sin tildes). 0 si no existe.
static func chapters_of(book: String) -> int:
	var key: String = _fold(book)
	_ensure_index()
	if _index.has(key):
		return int((_index[key] as Array)[1])
	if ALIASES.has(key):
		return chapters_of(str(ALIASES[key]))
	return 0


## Nombre oficial del libro, o "" si no existe.
static func canonical_name(book: String) -> String:
	var key: String = _fold(book)
	_ensure_index()
	if _index.has(key):
		return str((_index[key] as Array)[0])
	if ALIASES.has(key):
		return str(ALIASES[key])
	return ""


## Analiza una referencia (o varias separadas por ";"). Devuelve:
##   ok        true si todas las partes son válidas
##   problems  descripción de cada error
##   parts     una entrada por parte: {book, chapter, chapter_to, verse, verse_to}
##             (verse = 0 cuando la referencia es de capítulos completos)
static func parse(text: String) -> Dictionary:
	var problems := PackedStringArray()
	var parts: Array = []
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		problems.append("la referencia está vacía")
	else:
		for raw in trimmed.split(";"):
			var part: Dictionary = _parse_part(raw.strip_edges(), problems)
			if not part.is_empty():
				parts.append(part)
	return {"ok": problems.is_empty() and not parts.is_empty(), "problems": problems, "parts": parts}


static func is_valid(text: String) -> bool:
	return bool(parse(text)["ok"])


static func _parse_part(raw: String, problems: PackedStringArray) -> Dictionary:
	var split_at: int = raw.rfind(" ")
	if split_at <= 0:
		problems.append("'%s': falta el libro o el capítulo" % raw)
		return {}
	var book_text: String = raw.substr(0, split_at).strip_edges()
	var numbers: String = raw.substr(split_at + 1).strip_edges()
	var book: String = canonical_name(book_text)
	if book.is_empty():
		problems.append("'%s': el libro '%s' no existe" % [raw, book_text])
		return {}
	var chapter_total: int = chapters_of(book)

	var chapter: int = 0
	var chapter_to: int = 0
	var verse: int = 0
	var verse_to: int = 0
	if numbers.contains(":"):
		var halves: PackedStringArray = numbers.split(":")
		if halves.size() != 2 or not halves[0].is_valid_int():
			problems.append("'%s': formato de capítulo y versículo no válido" % raw)
			return {}
		chapter = int(halves[0])
		chapter_to = chapter
		var verse_text: String = halves[1]
		if verse_text.contains("-"):
			var range_parts: PackedStringArray = verse_text.split("-")
			if range_parts.size() != 2 or not range_parts[0].is_valid_int() \
					or not range_parts[1].is_valid_int():
				problems.append("'%s': rango de versículos no válido" % raw)
				return {}
			verse = int(range_parts[0])
			verse_to = int(range_parts[1])
		elif verse_text.is_valid_int():
			verse = int(verse_text)
			verse_to = verse
		else:
			problems.append("'%s': versículo no válido" % raw)
			return {}
		if verse < 1 or verse_to < verse or verse_to > MAX_VERSE:
			problems.append("'%s': versículos fuera de rango" % raw)
			return {}
	elif numbers.contains("-"):
		var chapter_parts: PackedStringArray = numbers.split("-")
		if chapter_parts.size() != 2 or not chapter_parts[0].is_valid_int() \
				or not chapter_parts[1].is_valid_int():
			problems.append("'%s': rango de capítulos no válido" % raw)
			return {}
		chapter = int(chapter_parts[0])
		chapter_to = int(chapter_parts[1])
	elif numbers.is_valid_int():
		chapter = int(numbers)
		chapter_to = chapter
	else:
		problems.append("'%s': número de capítulo no válido" % raw)
		return {}

	if chapter < 1 or chapter > chapter_total or chapter_to < chapter or chapter_to > chapter_total:
		problems.append("'%s': %s solo tiene %d capítulos" % [raw, book, chapter_total])
		return {}
	return {
		"book": book,
		"chapter": chapter,
		"chapter_to": chapter_to,
		"verse": verse,
		"verse_to": verse_to,
	}


static func _ensure_index() -> void:
	if not _index.is_empty():
		return
	for entry in BOOKS:
		var book: Array = entry
		_index[_fold(str(book[0]))] = book


## Minúsculas y sin tildes, para comparar nombres de libros.
static func _fold(text: String) -> String:
	var result: String = text.strip_edges().to_lower()
	var replacements := {"á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ü": "u"}
	for accented in replacements:
		result = result.replace(str(accented), str(replacements[accented]))
	while result.contains("  "):
		result = result.replace("  ", " ")
	return result
