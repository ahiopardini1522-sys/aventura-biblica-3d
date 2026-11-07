class_name GameRules
extends RefCounted
## Reglas puras del juego, sin nodos ni animaciones: dónde cae una ficha según el dado,
## qué pasa con las escaleras y las serpientes y qué premio o castigo tiene un desafío.
## Como no dependen de la escena, se pueden probar con miles de partidas simuladas.

const DIE_MIN := 1
const DIE_MAX := 6
const MAX_STARS := 3

## Premio por responder bien (además de las estrellas, que siempre se ganan).
const REWARD_STARS_ONLY := 0
const REWARD_ADVANCE := 1
const REWARD_EXTRA_ROLL := 2

## Castigo por responder mal.
const PENALTY_NONE := 0
const PENALTY_BACK := 1
const PENALTY_SKIP_TURN := 2

const MIN_SHIFT := 1
const MAX_SHIFT := 4


## Opciones de juego por defecto (las mismas que guarda SettingsManager).
static func default_options() -> Dictionary:
	return {
		"challenges": true,
		"reward_mode": REWARD_ADVANCE,
		"reward_steps": 2,
		"penalty_mode": PENALTY_BACK,
		"penalty_steps": 2,
		"exact_finish": false,
	}


## Completa y corrige unas opciones recibidas (por ejemplo, de un archivo guardado).
static func normalize_options(raw: Dictionary) -> Dictionary:
	var options: Dictionary = default_options()
	options["challenges"] = bool(raw.get("challenges", options["challenges"]))
	options["reward_mode"] = clampi(int(raw.get("reward_mode", options["reward_mode"])),
			REWARD_STARS_ONLY, REWARD_EXTRA_ROLL)
	options["reward_steps"] = clampi(int(raw.get("reward_steps", options["reward_steps"])),
			MIN_SHIFT, MAX_SHIFT)
	options["penalty_mode"] = clampi(int(raw.get("penalty_mode", options["penalty_mode"])),
			PENALTY_NONE, PENALTY_SKIP_TURN)
	options["penalty_steps"] = clampi(int(raw.get("penalty_steps", options["penalty_steps"])),
			MIN_SHIFT, MAX_SHIFT)
	options["exact_finish"] = bool(raw.get("exact_finish", options["exact_finish"]))
	return options


## Plan de un movimiento de dado, sin aplicarlo. Devuelve:
##   from, roll       casilla de salida y número del dado
##   blocked          true si hace falta tirada exacta y el dado se pasa de la meta
##   steps            casillas que recorre la ficha, una por una (sin la de salida)
##   landed           casilla donde termina de caminar
##   jump             {} o {kind, from, to} si cae en una escalera o en una serpiente
##   final            casilla donde queda la ficha tras el salto
##   reached_goal     true si la ficha queda en la meta
## Reglas: nunca sale del tablero (se queda en la meta si se pasa) y las escaleras y
## serpientes se aplican siempre, una sola vez.
static func plan_move(layout: BoardLayout, from_tile: int, roll: int,
		exact_finish: bool = false) -> Dictionary:
	var last: int = layout.last_tile()
	var start: int = clampi(from_tile, 1, last)
	var pips: int = clampi(roll, DIE_MIN, DIE_MAX)
	var target: int = start + pips
	var blocked: bool = false
	var landed: int = target
	if target > last:
		if exact_finish:
			blocked = true
			landed = start
		else:
			landed = last
	var steps: Array[int] = []
	for tile in range(start + 1, landed + 1):
		steps.append(tile)
	var jump: Dictionary = {}
	var final_tile: int = landed
	if not blocked:
		var kind: String = layout.jump_kind(landed)
		if kind != "":
			final_tile = layout.jump_target(landed)
			jump = {"kind": kind, "from": landed, "to": final_tile}
	return {
		"from": start,
		"roll": roll,
		"blocked": blocked,
		"steps": steps,
		"landed": landed,
		"jump": jump,
		"final": final_tile,
		"reached_goal": final_tile == last and not blocked,
	}


## Plan de un desplazamiento por premio o castigo (casillas hacia delante o hacia atrás).
## No se sale del tablero y no activa escaleras ni serpientes. Devuelve:
##   from, to, delta, steps (en orden de recorrido), moved, reached_goal
static func plan_shift(layout: BoardLayout, from_tile: int, delta: int) -> Dictionary:
	var last: int = layout.last_tile()
	var start: int = clampi(from_tile, 1, last)
	var target: int = clampi(start + delta, 1, last)
	var steps: Array[int] = []
	if target > start:
		for tile in range(start + 1, target + 1):
			steps.append(tile)
	elif target < start:
		for tile in range(start - 1, target - 1, -1):
			steps.append(tile)
	return {
		"from": start,
		"to": target,
		"delta": target - start,
		"steps": steps,
		"moved": target != start,
		"reached_goal": target == last,
	}


## Estrellas que da un desafío según su dificultad (1 a 3).
static func stars_for(difficulty: int) -> int:
	return clampi(difficulty, 1, MAX_STARS)
