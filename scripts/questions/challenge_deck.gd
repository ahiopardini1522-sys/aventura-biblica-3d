class_name ChallengeDeck
extends RefCounted
## Mazo de una partida: reparte los desafíos sin repetir hasta agotar los de cada tipo y
## procura que salgan los cinco tipos (siempre elige entre los menos usados).
## Con una semilla fija el reparto es siempre el mismo, útil para las pruebas.

var _rng := RandomNumberGenerator.new()
var _used: Dictionary = {}
var _drawn_by_type: Dictionary = {}
## Cuántos desafíos se han repartido en total.
var drawn: int = 0


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	for type in Challenge.TYPES:
		_drawn_by_type[type] = 0


## Reparte el siguiente desafío (con las opciones ya mezcladas) o null si el banco está vacío.
## Si "preferred_type" es un tipo válido con desafíos, se usa ese.
func draw(preferred_type: String = "") -> Challenge:
	var type: String = preferred_type if _has_items(preferred_type) else _least_used_type()
	if type.is_empty():
		return null
	var candidates: Array[Challenge] = []
	for item in ChallengeBank.by_type(type):
		if not _used.has(item.id):
			candidates.append(item)
	if candidates.is_empty():
		# Se agotaron los de este tipo: vuelven a entrar todos.
		for item in ChallengeBank.by_type(type):
			_used.erase(item.id)
			candidates.append(item)
	var chosen: Challenge = candidates[_rng.randi_range(0, candidates.size() - 1)]
	_used[chosen.id] = true
	_drawn_by_type[type] = int(_drawn_by_type[type]) + 1
	drawn += 1
	return chosen.shuffled(_rng)


func drawn_of_type(type: String) -> int:
	return int(_drawn_by_type.get(type, 0))


func _has_items(type: String) -> bool:
	return Challenge.TYPES.has(type) and not ChallengeBank.by_type(type).is_empty()


func _least_used_type() -> String:
	var best: Array[String] = []
	var best_count: int = 1 << 30
	for type in Challenge.TYPES:
		if ChallengeBank.by_type(type).is_empty():
			continue
		var count: int = int(_drawn_by_type[type])
		if count < best_count:
			best_count = count
			best.clear()
			best.append(type)
		elif count == best_count:
			best.append(type)
	if best.is_empty():
		return ""
	return best[_rng.randi_range(0, best.size() - 1)]
