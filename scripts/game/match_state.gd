class_name MatchState
extends RefCounted
## Estado de una partida: jugadores, de quién es el turno, casillas, estrellas, estadísticas
## y ganador. Aplica las reglas de GameRules y no sabe nada de escenas ni animaciones,
## así que se puede probar con partidas simuladas completas.

var layout: BoardLayout
var options: Dictionary = {}
## Un diccionario por jugador: index, name, color, character_id, tile, stars,
## skip_next, finished y stats.
var players: Array = []
var current: int = 0
var turn_number: int = 1
var winner: int = -1
var finished: bool = false
## Segundos de juego efectivo (lo va sumando quien conduce la partida).
var elapsed: float = 0.0
var extra_roll_pending: bool = false


## Crea la partida con los jugadores de GameState.build_roster() (o una lista equivalente).
static func create(new_layout: BoardLayout, roster: Array, new_options: Dictionary = {}) -> MatchState:
	var state := MatchState.new()
	state.layout = new_layout
	state.options = GameRules.normalize_options(new_options)
	for entry in roster:
		var info: Dictionary = entry
		state.players.append({
			"index": state.players.size(),
			"name": str(info.get("name", "Jugador")),
			"color": info.get("color", Color.WHITE),
			"character_id": str(info.get("character_id", "")),
			"tile": 1,
			"stars": 0,
			"skip_next": false,
			"finished": false,
			"stats": _new_stats(),
		})
	return state


static func _new_stats() -> Dictionary:
	return {
		"rolls": 0,
		"best_roll": 0,
		"steps": 0,
		"blocked": 0,
		"ladders": 0,
		"snakes": 0,
		"tiles_climbed": 0,
		"tiles_slid": 0,
		"challenges": 0,
		"correct": 0,
		"wrong": 0,
		"bonus_tiles": 0,
		"penalty_tiles": 0,
		"extra_rolls": 0,
		"skipped_turns": 0,
		"highest_tile": 1,
		"specials": 0,
		"special_rewards": 0,
		"special_obstacles": 0,
		"special_stars": 0,
	}


func player_count() -> int:
	return players.size()


func get_player(index: int) -> Dictionary:
	if index < 0 or index >= players.size():
		return {}
	return players[index]


func current_player() -> Dictionary:
	return get_player(current)


## True si ese jugador puede tirar el dado ahora: es su turno y la partida sigue.
func can_roll(player_index: int) -> bool:
	return not finished and player_index == current \
			and player_index >= 0 and player_index < players.size()


## Aplica una tirada del jugador indicado. Si no es su turno devuelve {"ok": false, ...}.
## Si no, devuelve el plan de GameRules.plan_move() más:
##   ok, player, challenge (true si ahora toca un desafío)
func apply_roll(player_index: int, roll: int) -> Dictionary:
	if finished:
		return {"ok": false, "reason": "la partida ya terminó"}
	if not can_roll(player_index):
		return {"ok": false, "reason": "no es el turno de ese jugador"}
	var info: Dictionary = players[player_index]
	var stats: Dictionary = info["stats"]
	var plan: Dictionary = GameRules.plan_move(layout, int(info["tile"]), roll,
			bool(options["exact_finish"]))

	stats["rolls"] = int(stats["rolls"]) + 1
	stats["best_roll"] = maxi(int(stats["best_roll"]), clampi(roll, GameRules.DIE_MIN, GameRules.DIE_MAX))
	if bool(plan["blocked"]):
		stats["blocked"] = int(stats["blocked"]) + 1
	else:
		stats["steps"] = int(stats["steps"]) + (plan["steps"] as Array).size()
		var jump: Dictionary = plan["jump"]
		if not jump.is_empty():
			var gap: int = absi(int(jump["to"]) - int(jump["from"]))
			if str(jump["kind"]) == BoardLayout.KIND_LADDER:
				stats["ladders"] = int(stats["ladders"]) + 1
				stats["tiles_climbed"] = int(stats["tiles_climbed"]) + gap
			else:
				stats["snakes"] = int(stats["snakes"]) + 1
				stats["tiles_slid"] = int(stats["tiles_slid"]) + gap
	_set_tile(info, int(plan["final"]))
	if bool(plan["reached_goal"]):
		_finish(player_index)

	plan["ok"] = true
	plan["player"] = player_index
	plan["challenge"] = bool(options["challenges"]) and not finished \
			and not bool(plan["blocked"]) and (plan["jump"] as Dictionary).is_empty() \
			and layout.is_challenge_tile(int(plan["final"]))
	# Una casilla especial solo actúa si la ficha camina hasta ella: caer por una escalera o una
	# serpiente, o llegar a ella por un premio o castigo, no la activa (no hay cadenas).
	plan["special"] = {}
	if not finished and not bool(plan["blocked"]) and (plan["jump"] as Dictionary).is_empty():
		plan["special"] = layout.special_at(int(plan["final"]))
	return plan


## Aplica la casilla especial en la que está parado el jugador del turno. Devuelve:
##   ok, player, kind, name, ref, good, converted, stars, move (plan_shift o {}),
##   extra_roll, skip_next, reached_goal
func apply_special(player_index: int) -> Dictionary:
	if finished or not can_roll(player_index):
		return {"ok": false, "reason": "no es el turno de ese jugador"}
	var info: Dictionary = players[player_index]
	var special: Dictionary = layout.special_at(int(info["tile"]))
	if special.is_empty():
		return {"ok": false, "reason": "no hay casilla especial en esa casilla"}
	var effect: Dictionary = GameRules.special_effect(special, players.size())
	var stats: Dictionary = info["stats"]
	var kind: String = str(effect["kind"])
	var result: Dictionary = {
		"ok": true,
		"player": player_index,
		"kind": kind,
		"name": str(effect["name"]),
		"ref": str(effect["ref"]),
		"good": bool(effect["good"]),
		"converted": bool(effect["converted"]),
		"stars": 0,
		"move": {},
		"extra_roll": false,
		"skip_next": false,
		"reached_goal": false,
	}
	stats["specials"] = int(stats["specials"]) + 1
	if bool(effect["good"]):
		stats["special_rewards"] = int(stats["special_rewards"]) + 1
	else:
		stats["special_obstacles"] = int(stats["special_obstacles"]) + 1
	match kind:
		BoardLayout.SPECIAL_ADVANCE:
			result["move"] = _shift(info, int(effect["steps"]))
		BoardLayout.SPECIAL_BACK:
			result["move"] = _shift(info, -int(effect["steps"]))
		BoardLayout.SPECIAL_EXTRA_ROLL:
			extra_roll_pending = true
			result["extra_roll"] = true
		BoardLayout.SPECIAL_STARS:
			var gained: int = int(effect["stars"])
			info["stars"] = int(info["stars"]) + gained
			stats["special_stars"] = int(stats["special_stars"]) + gained
			result["stars"] = gained
		BoardLayout.SPECIAL_SKIP:
			if players.size() > 1:
				info["skip_next"] = true
				result["skip_next"] = true
	var move: Dictionary = result["move"]
	if not move.is_empty() and bool(move["reached_goal"]):
		result["reached_goal"] = true
		_finish(player_index)
	return result


## Aplica el resultado de un desafío del jugador en turno: estrellas y premio si acertó,
## castigo si falló. Devuelve:
##   ok, correct, stars, move (plan_shift o {}), extra_roll, skip_next, reached_goal
func apply_challenge_result(player_index: int, correct: bool, difficulty: int) -> Dictionary:
	if finished or not can_roll(player_index):
		return {"ok": false, "reason": "no es el turno de ese jugador"}
	var info: Dictionary = players[player_index]
	var stats: Dictionary = info["stats"]
	var result: Dictionary = {
		"ok": true,
		"player": player_index,
		"correct": correct,
		"stars": 0,
		"move": {},
		"extra_roll": false,
		"skip_next": false,
		"reached_goal": false,
	}
	stats["challenges"] = int(stats["challenges"]) + 1
	if correct:
		var stars: int = GameRules.stars_for(difficulty)
		result["stars"] = stars
		info["stars"] = int(info["stars"]) + stars
		stats["correct"] = int(stats["correct"]) + 1
		match int(options["reward_mode"]):
			GameRules.REWARD_ADVANCE:
				result["move"] = _shift(info, int(options["reward_steps"]))
			GameRules.REWARD_EXTRA_ROLL:
				extra_roll_pending = true
				result["extra_roll"] = true
	else:
		stats["wrong"] = int(stats["wrong"]) + 1
		match int(options["penalty_mode"]):
			GameRules.PENALTY_BACK:
				result["move"] = _shift(info, -int(options["penalty_steps"]))
			GameRules.PENALTY_SKIP_TURN:
				# Con un solo jugador perder el turno no cambia nada, así que no se marca.
				if players.size() > 1:
					info["skip_next"] = true
					result["skip_next"] = true
	var move: Dictionary = result["move"]
	if not move.is_empty() and bool(move["reached_goal"]):
		result["reached_goal"] = true
		_finish(player_index)
	return result


## Pasa el turno. Devuelve:
##   next      jugador que tira ahora
##   extra     true si el mismo jugador repite (premio de tirada extra)
##   skipped   jugadores que pierden su turno por un castigo
##   finished  true si la partida ya terminó (el turno no cambia)
func end_turn() -> Dictionary:
	var result: Dictionary = {"next": current, "extra": false, "skipped": [], "finished": finished}
	if finished:
		return result
	if extra_roll_pending:
		extra_roll_pending = false
		var again: Dictionary = players[current]
		var again_stats: Dictionary = again["stats"]
		again_stats["extra_rolls"] = int(again_stats["extra_rolls"]) + 1
		turn_number += 1
		result["extra"] = true
		return result
	var count: int = players.size()
	var next_index: int = current
	var skipped: Array = []
	for _attempt in count:
		next_index = (next_index + 1) % count
		var candidate: Dictionary = players[next_index]
		if bool(candidate["skip_next"]):
			candidate["skip_next"] = false
			var candidate_stats: Dictionary = candidate["stats"]
			candidate_stats["skipped_turns"] = int(candidate_stats["skipped_turns"]) + 1
			skipped.append(next_index)
			continue
		break
	current = next_index
	turn_number += 1
	result["next"] = current
	result["skipped"] = skipped
	return result


## Jugadores ordenados de mejor a peor: primero el ganador y después por casilla y estrellas.
func ranking() -> Array[int]:
	var order: Array[int] = []
	for i in players.size():
		order.append(i)
	order.sort_custom(_ranks_before)
	return order


## Resumen para la pantalla de victoria y las estadísticas.
func summary() -> Dictionary:
	var order: Array[int] = ranking()
	var list: Array = []
	var total_rolls: int = 0
	var total_challenges: int = 0
	var total_correct: int = 0
	for rank in order.size():
		var info: Dictionary = players[order[rank]]
		var stats: Dictionary = info["stats"]
		total_rolls += int(stats["rolls"])
		total_challenges += int(stats["challenges"])
		total_correct += int(stats["correct"])
		list.append({
			"index": int(info["index"]),
			"name": str(info["name"]),
			"color": info["color"],
			"character_id": str(info["character_id"]),
			"tile": int(info["tile"]),
			"stars": int(info["stars"]),
			"rank": rank + 1,
			"winner": int(info["index"]) == winner,
			"stats": stats.duplicate(),
		})
	var winner_info: Dictionary = get_player(winner)
	return {
		"finished": finished,
		"winner": winner,
		"winner_name": str(winner_info.get("name", "")),
		"winner_color": winner_info.get("color", Color.WHITE),
		"winner_character": str(winner_info.get("character_id", "")),
		"turns": turn_number,
		"duration": elapsed,
		"total_rolls": total_rolls,
		"total_challenges": total_challenges,
		"total_correct": total_correct,
		"players": list,
		"options": options.duplicate(),
	}


func _ranks_before(a: int, b: int) -> bool:
	if a == winner and b != winner:
		return true
	if b == winner and a != winner:
		return false
	var info_a: Dictionary = players[a]
	var info_b: Dictionary = players[b]
	if int(info_a["tile"]) != int(info_b["tile"]):
		return int(info_a["tile"]) > int(info_b["tile"])
	if int(info_a["stars"]) != int(info_b["stars"]):
		return int(info_a["stars"]) > int(info_b["stars"])
	return a < b


func _shift(info: Dictionary, delta: int) -> Dictionary:
	var stats: Dictionary = info["stats"]
	var move: Dictionary = GameRules.plan_shift(layout, int(info["tile"]), delta)
	if bool(move["moved"]):
		_set_tile(info, int(move["to"]))
		if int(move["delta"]) > 0:
			stats["bonus_tiles"] = int(stats["bonus_tiles"]) + int(move["delta"])
		else:
			stats["penalty_tiles"] = int(stats["penalty_tiles"]) - int(move["delta"])
	return move


func _set_tile(info: Dictionary, tile: int) -> void:
	info["tile"] = tile
	var stats: Dictionary = info["stats"]
	stats["highest_tile"] = maxi(int(stats["highest_tile"]), tile)


func _finish(player_index: int) -> void:
	finished = true
	winner = player_index
	var info: Dictionary = players[player_index]
	info["finished"] = true
