class_name Challenge
extends RefCounted
## Un desafío bíblico: pregunta, opciones, respuesta correcta, explicación y referencia.
## Hay cinco tipos (ver TYPES). Los datos vienen de data/questions/challenges.json.

const TYPE_MULTIPLE_CHOICE := "multiple_choice"
const TYPE_TRUE_FALSE := "true_false"
const TYPE_CHARACTER := "character"
const TYPE_COMPLETE_VERSE := "complete_verse"
const TYPE_EVENT := "event"

const TYPES: Array[String] = [
	TYPE_MULTIPLE_CHOICE,
	TYPE_TRUE_FALSE,
	TYPE_CHARACTER,
	TYPE_COMPLETE_VERSE,
	TYPE_EVENT,
]
## Título que ve el jugador en el panel de cada tipo.
const TYPE_TITLES := {
	TYPE_MULTIPLE_CHOICE: "PREGUNTA BÍBLICA",
	TYPE_TRUE_FALSE: "VERDADERO O FALSO",
	TYPE_CHARACTER: "¿QUIÉN SOY?",
	TYPE_COMPLETE_VERSE: "COMPLETA LA IDEA DEL VERSÍCULO",
	TYPE_EVENT: "¿QUÉ ACONTECIMIENTO ES?",
}
const BLANK := "____"
const TRUE_FALSE_OPTIONS: Array[String] = ["Verdadero", "Falso"]
const MIN_DIFFICULTY := 1
const MAX_DIFFICULTY := 3
const CHOICE_COUNT := 4

var id: String = ""
var type: String = TYPE_MULTIPLE_CHOICE
var difficulty: int = 1
## Enunciado. En "¿Quién soy?" es opcional (el panel pone uno por defecto).
var prompt: String = ""
## Solo "¿Quién soy?": pistas de la más difícil a la más fácil.
var clues: PackedStringArray = PackedStringArray()
var options: PackedStringArray = PackedStringArray()
## Posición de la respuesta correcta dentro de "options".
var correct: int = 0
var explanation: String = ""
## Referencia bíblica verificable, por ejemplo "Génesis 7:12".
var reference: String = ""
## Solo "completar": id del versículo en data/verses (para mostrar su texto cuando se
## cuente con una versión autorizada).
var verse_id: String = ""


## Crea un desafío a partir de una entrada del JSON. Si es de verdadero o falso,
## "correct" puede ser true/false; en los demás tipos es la posición (0 a 3).
static func from_dict(data: Dictionary) -> Challenge:
	var item := Challenge.new()
	item.id = str(data.get("id", ""))
	item.type = str(data.get("type", ""))
	item.difficulty = int(data.get("difficulty", 1))
	item.prompt = str(data.get("prompt", ""))
	item.explanation = str(data.get("explanation", ""))
	item.reference = str(data.get("reference", ""))
	item.verse_id = str(data.get("verse_id", ""))
	var raw_clues: Variant = data.get("clues", [])
	if raw_clues is Array:
		for clue in raw_clues:
			item.clues.append(str(clue))
	if item.type == TYPE_TRUE_FALSE:
		for text in TRUE_FALSE_OPTIONS:
			item.options.append(text)
		item.correct = 0 if bool(data.get("correct", true)) else 1
	else:
		var raw_options: Variant = data.get("options", [])
		if raw_options is Array:
			for option in raw_options:
				item.options.append(str(option))
		item.correct = int(data.get("correct", -1))
	return item


## Lista de problemas del desafío (vacía si es válido).
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var label: String = id if not id.is_empty() else "(sin id)"
	if id.is_empty():
		found.append("%s: falta el id" % label)
	if not TYPES.has(type):
		found.append("%s: tipo desconocido '%s'" % [label, type])
		return found
	if difficulty < MIN_DIFFICULTY or difficulty > MAX_DIFFICULTY:
		found.append("%s: la dificultad debe ser 1 a 3" % label)
	if type == TYPE_CHARACTER:
		if clues.size() < 2:
			found.append("%s: necesita al menos 2 pistas" % label)
		for clue in clues:
			if clue.strip_edges().is_empty():
				found.append("%s: hay una pista vacía" % label)
	elif prompt.strip_edges().is_empty():
		found.append("%s: falta el enunciado" % label)

	var expected: int = 2 if type == TYPE_TRUE_FALSE else CHOICE_COUNT
	if options.size() != expected:
		found.append("%s: debe tener %d opciones (tiene %d)" % [label, expected, options.size()])
	else:
		var seen: Dictionary = {}
		for option in options:
			var key: String = option.strip_edges().to_lower()
			if key.is_empty():
				found.append("%s: hay una opción vacía" % label)
			if seen.has(key):
				found.append("%s: la opción '%s' está repetida" % [label, option])
			seen[key] = true
		if correct < 0 or correct >= options.size():
			found.append("%s: la respuesta correcta no es una opción válida" % label)

	if explanation.strip_edges().is_empty():
		found.append("%s: falta la explicación" % label)
	if reference.strip_edges().is_empty():
		found.append("%s: falta la referencia bíblica" % label)
	else:
		var parsed: Dictionary = BibleReference.parse(reference)
		if not bool(parsed["ok"]):
			found.append("%s: referencia no válida (%s)" % [label, ", ".join(parsed["problems"])])
	if type == TYPE_COMPLETE_VERSE:
		if prompt.count(BLANK) != 1:
			found.append("%s: el enunciado debe tener un único hueco '%s'" % [label, BLANK])
		if verse_id.is_empty():
			found.append("%s: falta el id del versículo" % label)
	return found


func is_valid() -> bool:
	return problems().is_empty()


func title() -> String:
	return str(TYPE_TITLES.get(type, "DESAFÍO"))


func is_correct(index: int) -> bool:
	return index == correct


func correct_text() -> String:
	if correct >= 0 and correct < options.size():
		return options[correct]
	return ""


## Copia con las opciones mezcladas (la respuesta correcta sigue marcada). En verdadero
## o falso se conserva el orden "Verdadero", "Falso".
func shuffled(rng: RandomNumberGenerator) -> Challenge:
	var copy := Challenge.new()
	copy.id = id
	copy.type = type
	copy.difficulty = difficulty
	copy.prompt = prompt
	copy.clues = clues.duplicate()
	copy.explanation = explanation
	copy.reference = reference
	copy.verse_id = verse_id
	if type == TYPE_TRUE_FALSE:
		copy.options = options.duplicate()
		copy.correct = correct
		return copy
	var order: Array[int] = []
	for i in options.size():
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	for position in order.size():
		copy.options.append(options[order[position]])
		if order[position] == correct:
			copy.correct = position
	return copy
