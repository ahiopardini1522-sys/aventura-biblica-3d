class_name ChallengeDeck
extends RefCounted
## Mazo de una partida: reparte los desafíos sin repetir hasta agotar los de cada tipo y
## procura que salgan los cinco tipos (siempre elige entre los menos usados).
## Si el mazo es de un mapa, primero salen los desafíos propios de ese mundo; cuando se
## agotan los de un tipo, siguen los generales y después vuelven a empezar los del mapa.
## Los desafíos de otros mapas no salen nunca.
## Con una semilla fija el reparto es siempre el mismo, útil para las pruebas.

var _rng := RandomNumberGenerator.new()
var _used: Dictionary = {}
var _drawn_by_type: Dictionary = {}
## Cuántos desafíos se han repartido en total.
var drawn: int = 0
## Mapa del mazo ("" = todos los desafíos sin preferencia, como en las primeras etapas).
var map_id: String = ""
## Cuántos de los desafíos repartidos eran propios del mapa.
var drawn_from_map: int = 0


func _init(seed_value: int = 0, for_map_id: String = "") -> void:
	map_id = for_map_id
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
	var candidates: Array[Challenge] = _candidates(type)
	if candidates.is_empty():
		# Se agotaron los de este tipo: vuelven a entrar todos los que le tocan a este mazo.
		for item in _eligible(type):
			_used.erase(item.id)
		candidates = _candidates(type)
	if candidates.is_empty():
		return null
	var chosen: Challenge = candidates[_rng.randi_range(0, candidates.size() - 1)]
	_used[chosen.id] = true
	_drawn_by_type[type] = int(_drawn_by_type[type]) + 1
	drawn += 1
	if not map_id.is_empty() and chosen.map_id == map_id:
		drawn_from_map += 1
	return chosen.shuffled(_rng)


func drawn_of_type(type: String) -> int:
	return int(_drawn_by_type.get(type, 0))


## Los que aún no han salido y le tocan a este mazo, en este orden de preferencia:
## propios del mapa y, si no queda ninguno, generales.
func _candidates(type: String) -> Array[Challenge]:
	if map_id.is_empty():
		return _unused(ChallengeBank.by_type(type))
	var own: Array[Challenge] = _unused(ChallengeBank.by_type_for_map(type, map_id))
	if not own.is_empty():
		return own
	return _unused(ChallengeBank.general_by_type(type))


## Todos los desafíos de un tipo que este mazo puede repartir.
func _eligible(type: String) -> Array[Challenge]:
	if map_id.is_empty():
		return ChallengeBank.by_type(type)
	var result: Array[Challenge] = []
	for item in ChallengeBank.by_type_for_map(type, map_id):
		result.append(item)
	for item in ChallengeBank.general_by_type(type):
		result.append(item)
	return result


func _unused(list: Array[Challenge]) -> Array[Challenge]:
	var result: Array[Challenge] = []
	for item in list:
		if not _used.has(item.id):
			result.append(item)
	return result


func _has_items(type: String) -> bool:
	return Challenge.TYPES.has(type) and not _eligible(type).is_empty()


func _least_used_type() -> String:
	var best: Array[String] = []
	var best_count: int = 1 << 30
	for type in Challenge.TYPES:
		if _eligible(type).is_empty():
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
