extends SceneTree
## Toma capturas de cada pantalla del juego para revisarlas sin un teléfono.
## La ejecuta GitHub Actions con una pantalla virtual (xvfb) y OpenGL por software:
##   SHOT_DIR=/ruta xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --resolution 1600x720 --script res://tools/capture_screens.gd
## El render por software es lento y no representa el rendimiento de un teléfono.

const SCREENS := ["main_menu", "maps", "multiplayer", "characters", "settings", "board"]
const TIME_LIMIT := 240.0

var _dir: String = ""
var _router: Node
var _state: Node
var _finished: bool = false


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

	_state.select_map("desierto_sinai")
	_state.select_character("david")
	_state.set_player_count(3)

	for key in SCREENS:
		_router.go_to(key)
		await _wait_for(key)
		await create_timer(2.6).timeout
		await _save(key)

	# Vistas extra del tablero: lanzamiento del dado y cámara cercana en ángulo.
	var scene: Node = current_scene
	var dice: Node = scene.get_node_or_null("%Dice")
	var camera: Node = scene.get_node_or_null("%BoardCamera")
	if dice != null:
		dice.roll(5)
		await create_timer(2.4).timeout
		await _save("board_dice")
	if camera != null:
		camera.goal_yaw = 28.0
		camera.goal_pitch = 34.0
		camera.goal_distance = camera.default_distance * 0.62
		await create_timer(1.8).timeout
		await _save("board_angle")
		camera.goal_yaw = 0.0
		camera.goal_pitch = 78.0
		camera.goal_distance = camera.default_distance * 0.78
		await create_timer(1.8).timeout
		await _save("board_top")

	_finished = true
	print("CAPTURAS: listo (%s)" % _dir)
	quit(0)


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
