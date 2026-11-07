class_name QuestionBank
extends RefCounted
## Banco de preguntas (data/questions/*.json).
## Etapa 1: solo la estructura y un archivo de muestra; ninguna pantalla lo usa todavía.

const SAMPLE_PATH := "res://data/questions/sample_questions.json"

static var _questions: Array = []
static var _loaded: bool = false


static func all_questions() -> Array:
	_ensure_loaded()
	return _questions


## Una pregunta al azar, o {} si el banco está vacío.
static func random_question() -> Dictionary:
	_ensure_loaded()
	if _questions.is_empty():
		return {}
	return _questions[randi() % _questions.size()]


## Comprueba que una pregunta tenga texto, 2 o más opciones y un índice correcto válido.
static func is_valid(question: Dictionary) -> bool:
	if str(question.get("text", "")).is_empty():
		return false
	var options: Variant = question.get("options", [])
	if not (options is Array) or (options as Array).size() < 2:
		return false
	var correct: int = int(question.get("correct", -1))
	return correct >= 0 and correct < (options as Array).size()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_questions = []
	var data: Dictionary = JsonLoader.load_dictionary(SAMPLE_PATH)
	var list: Variant = data.get("questions", [])
	if list is Array:
		for entry in list:
			if entry is Dictionary and is_valid(entry):
				_questions.append(entry)
