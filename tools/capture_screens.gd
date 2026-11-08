extends SceneTree
## Toma capturas de cada pantalla del juego para revisarlas sin un teléfono.
## La ejecuta GitHub Actions con una pantalla virtual (xvfb) y OpenGL por software:
##   SHOT_DIR=/ruta xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --resolution 1600x720 --script res://tools/capture_screens.gd
## El render por software es lento y no representa el rendimiento de un teléfono.
##
## Además de los menús, juega unos turnos de verdad en el tablero (con tiradas forzadas) para
## fotografiar el dado, una escalera, una serpiente, un desafío, la pausa y la victoria.

const SCREENS := ["main_menu", "maps", "multiplayer", "characters", "settings", "board"]
const TIME_LIMIT := 480.0
## Mundos de los que se toman capturas del escenario 3D (vista normal, baja y lateral).
const SCENERY_MAPS := ["eden", "arca_noe", "egipto_exodo", "monte_sinai", "jerusalen", "belen"]

var _dir: String = ""
var _router: Node
var _state: Node
var _finished: bool = false

# Piezas del tablero abierto.
var _flow: Node
var _hud: Node
var _panel: Node
var _camera: Node
var _dice: Node
var _pause: Node


func _initialize() -> void:
	create_timer(TIME_LIMIT).timeout.connect(_on_time_limit)
	_run()


func _on_time_limit() -> void:
	if _finished:
		return
	_finished = true
	print("CAPTURAS: tiempo agotado")
	quit(2)


func _run() -> void:
	await process_frame
	_dir = OS.get_environment("SHOT_DIR")
	if _dir.is_empty():
		_dir = "user://screenshots"
	DirAccess.make_dir_recursive_absolute(_dir)
	_router = root.get_node_or_null("SceneRouter")
	_state = root.get_node_or_null("GameState")
	if _router == null or _state == null:
		print("CAPTURAS: faltan los autoloads")
		quit(1)
		return

	# Las capturas no tocan el progreso real: se abren todos los mundos solo para esta sesión.
	var progress: Node = root.get_node_or_null("ProgressManager")
	if progress != null:
		progress.save_path = "user://progress_capture.cfg"
		progress.unlock_everything_for_session()
	_state.select_map("desierto_sinai")
	_state.select_character("david")
	_state.set_player_count(3)

	for key in SCREENS:
		_router.go_to(key)
		await _wait_for(key)
		await create_timer(2.6).timeout
		await _save(key)
		if key == "settings":
			await _capture_rules_tab()

	await _capture_board()
	await _capture_victory()
	await _capture_scenery(SCENERY_MAPS)

	_finished = true
	print("CAPTURAS: listo (%s)" % _dir)
	quit(0)


func _capture_rules_tab() -> void:
	var tab: Node = current_scene.get_node_or_null("%RulesTab")
	if tab == null:
		print("CAPTURAS: no hay pestaña de reglas")
		return
	tab.pressed.emit()
	await create_timer(1.6).timeout
	await _save("settings_rules")


func _bind_board() -> bool:
	var scene: Node = current_scene
	if scene == null:
		return false
	_flow = scene.get_node_or_null("%Flow")
	_hud = scene.get_node_or_null("%Hud")
	_panel = scene.get_node_or_null("%ChallengePanel")
	_camera = scene.get_node_or_null("%BoardCamera")
	_dice = scene.get_node_or_null("%Dice")
	_pause = scene.get_node_or_null("%PauseMenu")
	return _flow != null and _hud != null and _panel != null and _camera != null and _dice != null and _pause != null


func _capture_board() -> void:
	if not _bind_board():
		print("CAPTURAS: el tablero no tiene todas sus piezas")
		return

	# Vistas de la cámara.
	_camera.goal_yaw = 28.0
	_camera.goal_pitch = 34.0
	_camera.goal_distance = _camera.default_distance * 0.62
	await create_timer(1.8).timeout
	await _save("board_angle")
	_camera.goal_yaw = 0.0
	_camera.goal_pitch = 78.0
	_camera.goal_distance = _camera.default_distance * 0.78
	await create_timer(1.8).timeout
	await _save("board_top")
	_camera.reset_view(false)
	await create_timer(1.0).timeout

	# Turno 1: un 4 desde la casilla 1 cae en la casilla 5, que tiene un desafío.
	_flow.try_roll(0, 4)
	await create_timer(0.7).timeout
	await _save("board_dice")
	await _wait_cond(_challenge_open, 25.0)
	await create_timer(1.5).timeout
	await _save("challenge_question")
	var item: Variant = _panel.challenge
	if item != null:
		_panel.choose(int(item.correct))
	await create_timer(1.0).timeout
	await _save("challenge_answered")
	_panel.continue_pressed()
	await _wait_cond(_ready_for_roll, 25.0)
	await create_timer(0.6).timeout
	await _save("board_next_turn")

	# Turno 2: escalera de la casilla 3 a la 22.
	var second: int = _flow.current_player()
	_flow.place_player(second, 1)
	_flow.try_roll(second, 2)
	await _wait_cond(_toast_starts.bind("¡Escalera"), 20.0)
	await create_timer(1.0).timeout
	await _save("board_ladder")
	await _wait_cond(_ready_for_roll, 25.0)

	# Turno 3: serpiente de la casilla 98 a la 78.
	var third: int = _flow.current_player()
	_flow.place_player(third, 92)
	_flow.try_roll(third, 6)
	await _wait_cond(_toast_starts.bind("¡Serpiente"), 20.0)
	await create_timer(1.1).timeout
	await _save("board_snake")
	await _wait_cond(_ready_for_roll, 25.0)

	# Pausa.
	_hud.pause_pressed.emit()
	await create_timer(0.8).timeout
	await _save("pause")
	_pause.close()
	await create_timer(0.5).timeout


func _capture_victory() -> void:
	if _flow == null or not is_instance_valid(_flow):
		return
	var winner: int = _flow.current_player()
	_flow.place_player(winner, 96)
	_flow.try_roll(winner, 4)
	await create_timer(1.0).timeout
	await _save("board_goal")
	await _wait_for("victory")
	await create_timer(3.2).timeout
	await _save("victory")


## Abre el tablero de cada mundo y fotografía su escenario: vista normal, vista baja (se ve el
## horizonte) y vista lateral.
func _capture_scenery(map_ids: Array) -> void:
	for map_id in map_ids:
		var id: String = str(map_id)
		_state.select_map(id)
		_router.go_to("board")
		await _wait_for("board")
		await create_timer(3.4).timeout
		if not _bind_board():
			print("CAPTURAS: el tablero de '%s' no tiene todas sus piezas" % id)
			continue
		await _save("scenery_%s" % id)
		_camera.goal_yaw = 0.0
		_camera.goal_pitch = 29.0
		_camera.goal_distance = _camera.default_distance * 1.15
		await create_timer(1.8).timeout
		await _save("scenery_%s_low" % id)
		_camera.goal_yaw = -48.0
		_camera.goal_pitch = 36.0
		_camera.goal_distance = _camera.default_distance * 1.25
		await create_timer(1.8).timeout
		await _save("scenery_%s_side" % id)


func _challenge_open() -> bool:
	return _panel != null and _panel.is_open() and not _panel.is_answered()


func _ready_for_roll() -> bool:
	return _flow != null and _flow.is_waiting_for_roll()


func _toast_starts(prefix: String) -> bool:
	return _hud != null and _hud.toast_text().begins_with(prefix)


func _wait_cond(condition: Callable, timeout: float) -> void:
	var waited: float = 0.0
	while waited < timeout:
		if condition.call():
			return
		await create_timer(0.1).timeout
		waited += 0.1
	print("CAPTURAS: una espera terminó sin cumplirse")


func _wait_for(key: String) -> void:
	var waited: float = 0.0
	while waited < 20.0:
		var scene: Node = current_scene
		if scene != null and not _router.is_transitioning and _router.current_key == key \
				and scene.scene_file_path == str(_router.SCENES[key]):
			return
		await create_timer(0.1).timeout
		waited += 0.1
	print("CAPTURAS: la pantalla '%s' no se abrió a tiempo" % key)


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _dir.path_join(shot_name + ".png")
	var err: int = image.save_png(path)
	print("CAPTURAS: %s -> %s (%dx%d, error %d)" % [shot_name, path, image.get_width(), image.get_height(), err])
	print("CAPTURAS:   %s: objetos %d, triángulos %d, llamadas de dibujo %d" % [shot_name,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
