class_name GameFlow
extends Node
## Director de la partida. Une las reglas (MatchState) con todo lo que se ve y se oye:
## el turno, el dado 3D, las fichas que caminan casilla por casilla, las escaleras y las
## serpientes, los desafíos bíblicos con su premio o castigo, los mensajes y la victoria.
##
## Las reglas viven en MatchState/GameRules (y están probadas aparte); este nodo solo las
## cuenta en pantalla, en orden: nada se mueve mientras otra cosa está pasando.

signal turn_started(player_index: int)
signal rolled(player_index: int, value: int)
signal moved(player_index: int, tile: int)
signal jumped(player_index: int, kind: String, from_tile: int, to_tile: int)
signal challenge_shown(player_index: int, item: Challenge)
signal challenge_resolved(player_index: int, correct: bool)
signal special_triggered(player_index: int, result: Dictionary)
signal turn_ended(player_index: int)
signal match_finished(summary: Dictionary)
signal _choice_made
signal _continue_made

enum Phase { IDLE, WAIT_ROLL, ROLLING, MOVING, CHALLENGE, ENDING, FINISHED }

const HOP_TIME := 0.26
const SHIFT_HOP_TIME := 0.2
const LAST_STRETCH_FROM := 90
## Si un tramo del turno tarda más que esto (en segundos de juego) se da por atascado y se reanuda.
const STUCK_SECONDS := 40.0

## Referencias que pone BoardScene antes de llamar a start().
var board: BoardBuilder
var dice: Dice
var camera: BoardCamera
var hud: BoardHud
var panel: ChallengePanel
var fx: Node3D
var tokens: Array[PlayerToken] = []

var state: MatchState
var layout: BoardLayout
var deck: ChallengeDeck
var phase: Phase = Phase.IDLE
## Velocidad de las animaciones (1 = normal). Las pruebas automáticas la suben.
var speed: float = 1.0
## Si no está vacío, los desafíos salen de este tipo (lo usan las pruebas).
var preferred_challenge_type: String = ""

var _rng := RandomNumberGenerator.new()
var _following: PlayerToken
var _shown_tile: Array[int] = []
var _told_last_stretch: Dictionary = {}
var _choice: int = -1
var _continued: bool = false
var _phase_clock: float = 0.0


## Empieza (o reanuda) la partida con el estado indicado. Las fichas ya deben estar en su sitio.
func start(new_state: MatchState) -> void:
	state = new_state
	layout = state.layout
	_rng.randomize()
	deck = ChallengeDeck.new(_rng.randi(), layout.map_id)
	dice.speed = speed
	if not panel.answered.is_connected(_on_panel_answered):
		panel.answered.connect(_on_panel_answered)
		panel.continued.connect(_on_panel_continued)
	_shown_tile.clear()
	_told_last_stretch.clear()
	for entry in state.players:
		var info: Dictionary = entry
		var index: int = int(info["index"])
		_shown_tile.append(int(info["tile"]))
		hud.update_player(index, int(info["tile"]), int(info["stars"]), false)
		tokens[index].set_tile_badge(int(info["tile"]))
	hud.show_toast(MessageBank.pick("start", _rng), UiTheme.GOLD, 3.2)
	_begin_turn(false, true)


func _process(delta: float) -> void:
	if state == null:
		return
	if not state.finished and phase != Phase.IDLE:
		state.elapsed += delta
	if _following != null and is_instance_valid(_following):
		camera.follow(_following.position)
	if phase == Phase.MOVING or phase == Phase.ENDING:
		_phase_clock += delta
		if _phase_clock > STUCK_SECONDS:
			_recover()


# ---------------------------------------------------------------- Consultas

func is_waiting_for_roll() -> bool:
	return phase == Phase.WAIT_ROLL


func is_finished() -> bool:
	return phase == Phase.FINISHED


## Verdadero mientras el jugador del turno tiene un desafío bíblico abierto en el panel.
func is_in_challenge() -> bool:
	return phase == Phase.CHALLENGE


func current_player() -> int:
	return state.current if state != null else -1


func shown_tile(player_index: int) -> int:
	return _shown_tile[player_index] if player_index >= 0 and player_index < _shown_tile.size() else -1


## Dónde se coloca la ficha de un jugador dentro de una casilla.
func token_spot(player_index: int, tile: int) -> Vector3:
	return layout.tile_center(tile) + BoardLayout.token_offset(player_index, state.player_count())


## Coloca a un jugador en una casilla sin animación (para pruebas y para reanudar partidas).
func place_player(player_index: int, tile: int) -> void:
	var info: Dictionary = state.get_player(player_index)
	if info.is_empty():
		return
	var target: int = clampi(tile, 1, layout.last_tile())
	var stats: Dictionary = info["stats"]
	info["tile"] = target
	stats["highest_tile"] = maxi(int(stats["highest_tile"]), target)
	var token: PlayerToken = tokens[player_index]
	token.stop_moving()
	token.position = token_spot(player_index, target)
	token.set_tile_badge(target)
	_shown_tile[player_index] = target
	hud.update_player(player_index, target, int(info["stars"]), false)


# ---------------------------------------------------------------- Turno y tirada

## Lo llama el botón LANZAR DADO: tira por el jugador al que le toca.
func request_roll() -> bool:
	if state == null:
		return false
	return try_roll(state.current)


## Lanza el dado para ese jugador. Devuelve false (y no hace nada) si no es su turno, si el
## dado ya está rodando, si hay algo moviéndose, si el juego está en pausa o si terminó.
## "forced_value" (1 a 6) sirve para las pruebas; con 0 sale un número al azar.
func try_roll(player_index: int, forced_value: int = 0) -> bool:
	if state == null or phase != Phase.WAIT_ROLL:
		return false
	if get_tree().paused or dice.is_rolling or not state.can_roll(player_index):
		return false
	_set_phase(Phase.ROLLING)
	hud.set_roll_enabled(false)
	hud.begin_roll()
	hud.set_hint("Lanzando el dado...")
	var value: int = dice.roll(forced_value)
	if value == 0:
		_set_phase(Phase.WAIT_ROLL)
		hud.set_roll_enabled(true)
		return false
	_resolve_roll(player_index, value)
	return true


func _begin_turn(extra: bool = false, first: bool = false) -> void:
	if state.finished:
		return
	_set_phase(Phase.WAIT_ROLL)
	var player_index: int = state.current
	var info: Dictionary = state.get_player(player_index)
	var player_name: String = str(info["name"])
	for i in tokens.size():
		tokens[i].set_active(i == player_index)
	hud.set_current_player(player_index)
	hud.set_roll_enabled(true)
	if state.player_count() > 1:
		hud.set_hint("%s, toca LANZAR DADO" % player_name)
	else:
		hud.set_hint("Toca LANZAR DADO")
	_stop_following()
	if not first:
		camera.release_focus()
	if extra:
		hud.show_toast("¡Tirada extra para %s!" % player_name, UiTheme.GOLD, 2.0)
	elif state.player_count() > 1:
		hud.show_turn_splash(player_name, info["color"])
	if int(info["tile"]) >= LAST_STRETCH_FROM and not _told_last_stretch.has(player_index):
		_told_last_stretch[player_index] = true
		hud.show_toast(MessageBank.pick("last_stretch", _rng), UiTheme.GOLD, 2.6)
	turn_started.emit(player_index)


func _resolve_roll(player_index: int, value: int) -> void:
	await dice.roll_finished
	var info: Dictionary = state.get_player(player_index)
	var player_name: String = str(info["name"])
	hud.show_die_value(value, "%s sacó %d" % [player_name, value])
	rolled.emit(player_index, value)
	await _wait(0.5)

	_set_phase(Phase.MOVING)
	var result: Dictionary = state.apply_roll(player_index, value)
	if not bool(result.get("ok", false)):
		push_error("GameFlow: se rechazó la tirada (%s)" % str(result.get("reason", "")))
		_begin_turn()
		return
	var token: PlayerToken = tokens[player_index]
	_follow(token)
	camera.focus_on(token.position)
	hud.set_hint("%s avanza..." % player_name)

	if bool(result["blocked"]):
		await _blocked(player_index)
	else:
		for tile in (result["steps"] as Array):
			await _hop(player_index, int(tile), HOP_TIME)
		var jump: Dictionary = result["jump"]
		if not jump.is_empty():
			await _do_jump(player_index, jump)
	if state.finished:
		await _celebrate_goal(player_index)
		return
	if bool(result["challenge"]):
		await _run_challenge(player_index)
		if state.finished:
			await _celebrate_goal(player_index)
			return
	elif not (result["special"] as Dictionary).is_empty():
		await _run_special(player_index)
		if state.finished:
			await _celebrate_goal(player_index)
			return
	await _end_turn(player_index)


func _end_turn(player_index: int) -> void:
	_set_phase(Phase.ENDING)
	_stop_following()
	turn_ended.emit(player_index)
	var info: Dictionary = state.end_turn()
	for skipped in (info["skipped"] as Array):
		var skipped_index: int = int(skipped)
		hud.set_player_note(skipped_index, "")
		hud.show_toast("%s pierde este turno\n%s" % [
				str(state.get_player(skipped_index)["name"]), MessageBank.pick("skip", _rng)],
				UiTheme.WARN_RED, 2.2)
		await _wait(1.6)
	await _wait(0.3)
	_begin_turn(bool(info["extra"]))


# ---------------------------------------------------------------- Movimiento

## La ficha da un salto hasta una casilla; la lista de jugadores y la barra de progreso
## muestran la casilla en la que va cayendo.
func _hop(player_index: int, tile: int, seconds: float) -> void:
	var token: PlayerToken = tokens[player_index]
	var info: Dictionary = state.get_player(player_index)
	var spot: Vector3 = token_spot(player_index, tile)
	SettingsManager.play_step()
	token.set_tile_badge(tile)
	_shown_tile[player_index] = tile
	hud.update_player(player_index, tile, int(info["stars"]))
	var tween: Tween = token.hop_to(spot, seconds / speed)
	await tween.finished
	Effects.dust_puff(fx, spot, Color(0.92, 0.84, 0.70), 4, 0.5)
	moved.emit(player_index, tile)


## La tirada se pasa de la meta y las reglas piden número exacto: la ficha no se mueve.
func _blocked(player_index: int) -> void:
	var token: PlayerToken = tokens[player_index]
	hud.show_toast("Necesitas el número exacto para llegar a la meta", UiTheme.WARN_RED, 2.4)
	SettingsManager.play_wrong()
	await token.shake_head(_anim(0.5)).finished
	await _wait(0.4)


func _do_jump(player_index: int, jump: Dictionary) -> void:
	var kind: String = str(jump["kind"])
	var from_tile: int = int(jump["from"])
	var to_tile: int = int(jump["to"])
	if kind == BoardLayout.KIND_LADDER:
		await _climb(player_index, from_tile, to_tile)
	else:
		await _slide(player_index, from_tile, to_tile)
	jumped.emit(player_index, kind, from_tile, to_tile)


func _climb(player_index: int, from_tile: int, to_tile: int) -> void:
	var token: PlayerToken = tokens[player_index]
	var info: Dictionary = state.get_player(player_index)
	hud.show_toast("¡Escalera! Subes de la casilla %d a la %d\n%s" % [
			from_tile, to_tile, MessageBank.pick("ladder", _rng)], Effects.GREEN, 2.8)
	SettingsManager.play_ladder()
	Effects.ring_pulse(fx, layout.tile_center(from_tile), Effects.GREEN, 1.3, 0.6)
	await _wait(0.35)

	_shown_tile[player_index] = to_tile
	hud.update_player(player_index, to_tile, int(info["stars"]))
	var path: PackedVector3Array = board.ladder_path(from_tile, to_tile)
	var points := PackedVector3Array([token.position])
	points.append_array(path)
	var seconds: float = clampf(path[0].distance_to(path[1]) * 0.24, 0.9, 2.4)
	var tween: Tween = token.travel_path(points, seconds / speed, board.ladder_rungs(from_tile, to_tile), 0.07)
	await tween.finished

	token.set_tile_badge(to_tile)
	var top: Vector3 = layout.tile_center(to_tile)
	Effects.light_pillar(fx, top, Effects.GREEN, 3.0, 0.9)
	Effects.sparkle_burst(fx, top + Vector3(0.0, 0.3, 0.0), Effects.GOLD, 22)
	Effects.floating_text(fx, top + Vector3(0.0, 1.6, 0.0), "¡ARRIBA!", Effects.GREEN)
	await _settle(player_index, to_tile)


func _slide(player_index: int, head_tile: int, tail_tile: int) -> void:
	var token: PlayerToken = tokens[player_index]
	var info: Dictionary = state.get_player(player_index)
	hud.show_toast("¡Serpiente! Bajas de la casilla %d a la %d\n%s" % [
			head_tile, tail_tile, MessageBank.pick("snake", _rng)], Effects.RED, 2.8)
	hud.flash(Effects.RED, 0.22, 0.6)
	SettingsManager.play_snake()
	camera.shake(0.12, 0.5)
	Effects.ring_pulse(fx, layout.tile_center(head_tile), Effects.RED, 1.4, 0.6)
	_bite(board.snake_head_node(head_tile))
	await _wait(0.5)

	_shown_tile[player_index] = tail_tile
	hud.update_player(player_index, tail_tile, int(info["stars"]))
	var path: PackedVector3Array = board.snake_path(head_tile, tail_tile)
	var points := PackedVector3Array([token.position])
	points.append_array(path)
	var length: float = 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	var tween: Tween = token.travel_path(points, clampf(length * 0.3, 1.0, 2.6) / speed)
	await tween.finished

	token.set_tile_badge(tail_tile)
	var bottom: Vector3 = layout.tile_center(tail_tile)
	Effects.dust_puff(fx, bottom, Color(0.85, 0.55, 0.45), 14, 0.9)
	Effects.floating_text(fx, bottom + Vector3(0.0, 1.5, 0.0), "¡Ay!", Effects.RED)
	token.shake_head(_anim(0.5))
	await _settle(player_index, tail_tile)


## Mordisco de la serpiente: la cabeza se lanza hacia delante y vuelve.
func _bite(head: Node3D) -> void:
	if head == null:
		return
	var origin: Vector3 = head.position
	var lunge: Vector3 = origin + head.transform.basis * Vector3(0.0, 0.0, -0.34)
	var tween: Tween = head.create_tween()
	tween.tween_property(head, "position", lunge, 0.12 / speed)
	tween.tween_property(head, "position", origin, 0.3 / speed)


## Baja de la escalera o el cuerpo de la serpiente y se coloca en su sitio de la casilla.
func _settle(player_index: int, tile: int) -> void:
	var token: PlayerToken = tokens[player_index]
	var tween: Tween = token.hop_to(token_spot(player_index, tile), 0.2 / speed, 0.12)
	await tween.finished
	moved.emit(player_index, tile)


# ---------------------------------------------------------------- Desafíos

func _run_challenge(player_index: int) -> void:
	_set_phase(Phase.CHALLENGE)
	var item: Challenge = deck.draw(preferred_challenge_type)
	if item == null:
		return
	var info: Dictionary = state.get_player(player_index)
	var token: PlayerToken = tokens[player_index]
	_stop_following()
	camera.release_focus()
	hud.set_hint("Desafío bíblico: responde en el panel")
	hud.show_toast(MessageBank.pick("challenge", _rng), Effects.BLUE, 1.8)
	Effects.ring_pulse(fx, token.position, Effects.BLUE, 1.5, 0.7)
	Effects.sparkle_burst(fx, token.position + Vector3(0.0, 0.5, 0.0), Effects.BLUE, 14)
	await _wait(0.9)

	_choice = -1
	_continued = false
	panel.present(item, str(info["name"]), info["color"],
			_stake_win(item.difficulty), _stake_lose())
	challenge_shown.emit(player_index, item)
	while _choice < 0:
		await _choice_made

	var correct: bool = item.is_correct(_choice)
	var result: Dictionary = state.apply_challenge_result(player_index, correct, item.difficulty)
	if correct:
		SettingsManager.play_correct()
		hud.flash(Effects.GREEN, 0.18, 0.5)
	else:
		SettingsManager.play_wrong()
		hud.flash(Effects.RED, 0.16, 0.5)
	panel.show_outcome(_outcome_text(result), correct)
	while not _continued:
		await _continue_made
	panel.close()
	if panel.is_open():
		await panel.closed
	await _apply_challenge_result(player_index, result)
	challenge_resolved.emit(player_index, correct)


func _apply_challenge_result(player_index: int, result: Dictionary) -> void:
	var token: PlayerToken = tokens[player_index]
	var info: Dictionary = state.get_player(player_index)
	var correct: bool = bool(result["correct"])
	var move: Dictionary = result["move"]
	var lift := Vector3(0.0, 1.5, 0.0)
	if correct:
		var stars: int = int(result["stars"])
		hud.update_player(player_index, _shown_tile[player_index], int(info["stars"]))
		SettingsManager.play_star()
		Effects.star_shower(fx, token.position + Vector3(0.0, 0.4, 0.0), Effects.GOLD, 8 + stars * 4)
		Effects.floating_text(fx, token.position + lift, "+%s" % _stars_text(stars), Effects.GOLD, 1.0, 1.4, 1.6)
		hud.show_toast(MessageBank.pick("correct", _rng), Effects.GREEN, 2.6)
		token.celebrate(2, _anim(0.6))
		await _wait(0.8)
	else:
		Effects.floating_text(fx, token.position + lift, "¡Casi!", Effects.RED, 1.0, 1.2, 1.4)
		hud.show_toast(MessageBank.pick("wrong", _rng), Effects.RED, 2.6)
		token.shake_head(_anim(0.5))
		if bool(result["skip_next"]):
			hud.set_player_note(player_index, "pierde su próximo turno")
		await _wait(0.8)

	if not move.is_empty() and bool(move["moved"]):
		_follow(token)
		camera.focus_on(token.position)
		var effect_color: Color = Effects.GREEN if correct else Effects.RED
		Effects.ring_pulse(fx, token.position, effect_color, 1.2, 0.5)
		for tile in (move["steps"] as Array):
			await _hop(player_index, int(tile), SHIFT_HOP_TIME)
		Effects.sparkle_burst(fx, token.position + Vector3(0.0, 0.3, 0.0), effect_color, 12)
	elif bool(result["extra_roll"]):
		hud.show_toast("¡Ganaste una tirada extra!", UiTheme.GOLD, 2.0)
		await _wait(0.5)


# ---------------------------------------------------------------- Casillas especiales

## La ficha cayó en una casilla especial (recompensa u obstáculo del mapa): se anuncia, se
## aplica su efecto en las reglas y se cuenta lo que pasó, sin pedir nada al jugador.
func _run_special(player_index: int) -> void:
	var result: Dictionary = state.apply_special(player_index)
	if not bool(result.get("ok", false)):
		return
	var token: PlayerToken = tokens[player_index]
	var info: Dictionary = state.get_player(player_index)
	var good: bool = bool(result["good"])
	var accent: Color = Effects.GREEN if good else Effects.RED
	var lift := Vector3(0.0, 1.5, 0.0)
	_stop_following()
	hud.set_hint("%s: %s" % ["Recompensa" if good else "Obstáculo", str(result["name"])])
	hud.show_toast("%s\n%s" % [str(result["name"]), _special_text(result)],
			UiTheme.GOLD if good else UiTheme.WARN_RED, 2.8)
	if good:
		SettingsManager.play_star()
		hud.flash(Effects.GOLD, 0.16, 0.5)
		Effects.sparkle_burst(fx, token.position + Vector3(0.0, 0.5, 0.0), Effects.GOLD, 16)
	else:
		SettingsManager.play_wrong()
		hud.flash(Effects.RED, 0.14, 0.5)
		token.shake_head(_anim(0.5))
	Effects.ring_pulse(fx, token.position, accent, 1.5, 0.7)
	await _wait(1.1)

	var stars: int = int(result["stars"])
	if stars > 0:
		hud.update_player(player_index, _shown_tile[player_index], int(info["stars"]))
		SettingsManager.play_star()
		Effects.star_shower(fx, token.position + Vector3(0.0, 0.4, 0.0), Effects.GOLD, 8 + stars * 4)
		Effects.floating_text(fx, token.position + lift, "+%s" % _stars_text(stars), Effects.GOLD, 1.0, 1.4, 1.6)
		token.celebrate(2, _anim(0.6))
		await _wait(0.8)
	if bool(result["skip_next"]):
		hud.set_player_note(player_index, "pierde su próximo turno")
	var move: Dictionary = result["move"]
	if not move.is_empty() and bool(move["moved"]):
		_follow(token)
		camera.focus_on(token.position)
		for tile in (move["steps"] as Array):
			await _hop(player_index, int(tile), SHIFT_HOP_TIME)
		Effects.sparkle_burst(fx, token.position + Vector3(0.0, 0.3, 0.0), accent, 12)
	elif bool(result["extra_roll"]):
		await _wait(0.5)
	special_triggered.emit(player_index, result)


## Lo que hace una casilla especial, dicho en una frase corta ("Avanzas 3 casillas").
func _special_text(result: Dictionary) -> String:
	var steps: int = 0
	var move: Dictionary = result["move"]
	if not move.is_empty():
		steps = absi(int(move["delta"]))
	match str(result["kind"]):
		BoardLayout.SPECIAL_ADVANCE:
			return "Avanzas %s" % _tiles_text(steps) if steps > 0 else "Ya estás en la meta"
		BoardLayout.SPECIAL_BACK:
			return "Retrocedes %s" % _tiles_text(steps) if steps > 0 else "Ya estás en el inicio"
		BoardLayout.SPECIAL_EXTRA_ROLL:
			return "¡Tiras otra vez!"
		BoardLayout.SPECIAL_STARS:
			return "+%s" % _stars_text(int(result["stars"]))
		BoardLayout.SPECIAL_SKIP:
			return "Pierdes tu próximo turno"
	return ""


func _on_panel_answered(index: int) -> void:
	_choice = index
	_choice_made.emit()


func _on_panel_continued() -> void:
	_continued = true
	_continue_made.emit()


## "Si aciertas: +2 estrellas y avanzas 2 casillas" según las reglas de la partida.
func _stake_win(difficulty: int) -> String:
	var text: String = "Si aciertas: +%s" % _stars_text(GameRules.stars_for(difficulty))
	match int(state.options["reward_mode"]):
		GameRules.REWARD_ADVANCE:
			text += " y avanzas %s" % _tiles_text(int(state.options["reward_steps"]))
		GameRules.REWARD_EXTRA_ROLL:
			text += " y tiras otra vez"
	return text


func _stake_lose() -> String:
	match int(state.options["penalty_mode"]):
		GameRules.PENALTY_BACK:
			return "Si fallas: retrocedes %s" % _tiles_text(int(state.options["penalty_steps"]))
		GameRules.PENALTY_SKIP_TURN:
			if state.player_count() > 1:
				return "Si fallas: pierdes tu próximo turno"
	return "Si fallas: no pasa nada, ¡sigue intentando!"


## Lo que realmente ocurrió tras responder ("+1 estrella, avanzas 2 casillas").
func _outcome_text(result: Dictionary) -> String:
	var parts: Array[String] = []
	var move: Dictionary = result["move"]
	if bool(result["correct"]):
		parts.append("+%s" % _stars_text(int(result["stars"])))
		if not move.is_empty() and bool(move["moved"]):
			parts.append("avanzas %s" % _tiles_text(int(move["delta"])))
		if bool(result["extra_roll"]):
			parts.append("tiras otra vez")
	else:
		if not move.is_empty() and bool(move["moved"]):
			parts.append("retrocedes %s" % _tiles_text(-int(move["delta"])))
		elif int(state.options["penalty_mode"]) == GameRules.PENALTY_BACK:
			parts.append("ya estás en el inicio")
		if bool(result["skip_next"]):
			parts.append("pierdes tu próximo turno")
		if parts.is_empty():
			parts.append("sin penalización")
	var text: String = ", ".join(parts)
	return text.substr(0, 1).to_upper() + text.substr(1)


static func _stars_text(count: int) -> String:
	return "%d estrella%s" % [count, "" if count == 1 else "s"]


static func _tiles_text(count: int) -> String:
	return "%d casilla%s" % [count, "" if count == 1 else "s"]


# ---------------------------------------------------------------- Victoria

func _celebrate_goal(player_index: int) -> void:
	_set_phase(Phase.FINISHED)
	_stop_following()
	hud.set_roll_enabled(false)
	hud.set_hint("")
	var token: PlayerToken = tokens[player_index]
	for i in tokens.size():
		tokens[i].set_active(i == player_index)
	hud.set_current_player(player_index)
	hud.set_player_note(player_index, "¡Llegó a la meta!")
	var goal: Vector3 = layout.tile_center(layout.last_tile())
	SettingsManager.play_win()
	hud.flash(Effects.GOLD, 0.35, 0.9)
	Effects.light_pillar(fx, goal, Effects.GOLD, 4.0, 1.6)
	Effects.ring_pulse(fx, goal, Effects.GOLD, 2.4, 1.0)
	Effects.star_shower(fx, goal + Vector3(0.0, 0.6, 0.0), Effects.GOLD, 28, 1.6, 0.28)
	Effects.confetti(fx, goal + Vector3(0.0, 5.0, 0.0), Vector3(3.0, 0.2, 3.0), 90, 3.0, false)
	Effects.floating_text(fx, goal + Vector3(0.0, 2.0, 0.0), "¡META!", Effects.GOLD, 1.6, 1.6, 2.2)
	hud.show_toast("¡%s llegó a la meta!" % str(state.get_player(player_index)["name"]), UiTheme.GOLD, 2.6)
	token.celebrate(4, _anim(1.6))
	camera.focus_on(goal, 0.6)
	await _wait(2.8)
	match_finished.emit(state.summary())


# ---------------------------------------------------------------- Ayudas

func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	_phase_clock = 0.0


func _follow(token: PlayerToken) -> void:
	_following = token


func _stop_following() -> void:
	_following = null


## Espera un tiempo de juego (se detiene con la pausa y se acorta con "speed").
func _wait(seconds: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_interval(maxf(seconds / speed, 0.001))
	await tween.finished


## Duración de una animación de la ficha ajustada a la velocidad de la partida: así acaba
## antes de que termine la espera que la acompaña (si no, a velocidad alta el turno seguiría
## mientras la ficha todavía salta o mueve la cabeza).
func _anim(seconds: float) -> float:
	return maxf(seconds / speed, 0.02)


## Último recurso si un tramo del turno se atasca: coloca las fichas donde dicen las reglas
## y pasa al siguiente turno, para que la partida nunca se quede congelada.
func _recover() -> void:
	push_warning("GameFlow: el turno se atascó en la fase %d; se reanuda la partida" % int(phase))
	_stop_following()
	for entry in state.players:
		var info: Dictionary = entry
		var index: int = int(info["index"])
		tokens[index].stop_moving()
		tokens[index].position = token_spot(index, int(info["tile"]))
		tokens[index].set_tile_badge(int(info["tile"]))
		_shown_tile[index] = int(info["tile"])
		hud.update_player(index, int(info["tile"]), int(info["stars"]), false)
	if panel.is_open():
		panel.close()
	camera.release_focus()
	if state.finished:
		_set_phase(Phase.FINISHED)
		match_finished.emit(state.summary())
		return
	if phase == Phase.MOVING:
		state.end_turn()
	_begin_turn()
