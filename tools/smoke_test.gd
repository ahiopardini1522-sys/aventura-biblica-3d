extends SceneTree
## Prueba de humo automática (la ejecuta GitHub Actions con Godot sin pantalla).
##
## Uso:  godot --headless --path . --script res://tools/smoke_test.gd
## Termina con código 0 si todo pasa, 1 si algún control falla y 2 si se agota el tiempo.
##
## Comprueba, con el motor real:
##   - que todos los scripts compilan y todas las escenas se cargan,
##   - que no hay rutas res:// que apunten a archivos inexistentes,
##   - que los datos (los 7 mapas, desafíos, versículos, mensajes) y las reglas de cada tablero
##     son válidos,
##   - las reglas del juego: turnos, dado, movimiento, escaleras, serpientes, casillas
##     especiales, premios, castigos, victoria y cientos de partidas simuladas completas en
##     cada uno de los 7 tableros,
##   - el progreso: desbloqueo de mapas en orden, recompensas, insignias, estadísticas y guardado,
##   - que cada desafío bíblico tiene referencias válidas, que los cinco tipos funcionan y que
##     cada mapa tiene sus propios desafíos,
##   - el mapa mundial: relieve plano bajo las plataformas, caminos, iconos 3D, cámara táctil
##     (arrastre, pellizco, rueda), toques de verdad sobre cada mundo, estados bloqueado/abierto/
##     completado, celebración al abrir un mundo, insignias y apertura de cada tablero,
##   - que cada botón del menú abre su pantalla y que cada pantalla funciona (incluidas las
##     reglas del juego en Configuración),
##   - la partida REAL dentro de la escena del tablero, con el motor de verdad: turnos y bloqueo
##     fuera de turno, dado 3D, movimiento casilla por casilla, las 13 escaleras y serpientes con
##     su animación, los cinco tipos de desafío con premios y castigos, pausa (botón, Esc y atrás
##     de Android), victoria con estadísticas, jugar otra vez y una partida completa jugada por
##     un robot.
## No puede comprobar el aspecto visual (eso lo hacen las capturas) ni el rendimiento en un
## teléfono real.

const MENU_BUTTONS := {
	"MapsButton": "world",
	"MultiplayerButton": "multiplayer",
	"CharactersButton": "characters",
	"SettingsButton": "settings",
}
const TEST_PROGRESS_PATH := "user://progress_test.cfg"
## Orden de los mundos bíblicos (cada uno se abre al completar el anterior).
const MAP_ORDER: Array[String] = ["eden", "arca_noe", "egipto_exodo", "desierto_sinai", "monte_sinai", "jerusalen", "belen"]
const TIME_LIMIT := 480.0
## Velocidad de las animaciones del juego durante las pruebas (1 = la normal).
const GAME_SPEED := 10.0
const JUMP_SPEED := 4.0
const BOT_SPEED := 12.0

var _checks: int = 0
var _failures: Array[String] = []
var _finished: bool = false
var _router: Node
var _state: Node
var _settings: Node
var _progress: Node

# Piezas del tablero que está abierto (las toma _bind_board).
# OJO: se declaran sin tipo de clase a propósito. Este script se compila ANTES de que existan los
# autoloads (--script), y las clases del juego que usan SettingsManager no compilarían si el script
# las nombrara de forma estática (tipos, "as Clase" o enumeraciones). Se las llama dinámicamente.
var _board: Node
var _tokens_root: Node
var _camera: Node
var _dice: Node
var _hud: Node
var _flow: Node
var _panel: Node
var _pause: Node
var _effects_root: Node
var _events: Array = []
var _samples: Array[Vector3] = []
var _sample_token: Node3D
var _sampling: bool = false
## Solo se toman muestras mientras la interfaz ya muestra _sample_tile para el jugador _sample_player,
## es decir, durante la subida o la bajada y no durante los pasos que llevan hasta la base.
var _sample_player: int = -1
var _sample_tile: int = 0


func _initialize() -> void:
	create_timer(TIME_LIMIT).timeout.connect(_on_time_limit)
	_run()


func _on_time_limit() -> void:
	if _finished:
		return
	_finished = true
	print("")
	print("TIEMPO AGOTADO: la prueba tardó más de %d s (%d controles hechos)." % [int(TIME_LIMIT), _checks])
	quit(2)


func _run() -> void:
	await process_frame
	Engine.max_fps = 0
	print("=== PRUEBA DE HUMO: Aventura Bíblica 3D ===")
	print("Motor: %s" % Engine.get_version_info()["string"])
	_router = root.get_node_or_null("SceneRouter")
	_state = root.get_node_or_null("GameState")
	_settings = root.get_node_or_null("SettingsManager")
	_progress = root.get_node_or_null("ProgressManager")
	_check(_router != null and _state != null and _settings != null and _progress != null,
			"autoloads cargados (SettingsManager, ProgressManager, GameState, SceneRouter)")
	if _router == null or _state == null or _settings == null or _progress == null:
		_finish()
		return
	# Las pruebas no tocan el progreso real: guardan en otro archivo y empiezan de cero.
	_progress.save_path = TEST_PROGRESS_PATH
	_progress.reset(false)

	_test_project_settings()
	_test_scripts_compile()
	_test_scene_loading()
	_test_resource_references()
	_test_data()
	_test_board_layout()
	_test_rules()
	_test_match_state()
	_test_special_tiles()
	_test_simulated_games()
	_test_progress()
	_test_bible_references()
	_test_challenge_bank()
	_test_character_roster()
	_test_meshes()
	_test_kits()
	_test_stroke_font_and_marks()
	_test_scenery()
	_test_board_styles()
	_test_world_logic()
	_test_world_camera()
	_test_online_protocol()
	_test_online_config()
	_test_online_client()
	await _test_ambience()
	await _test_menu_and_screens()
	await _test_board_scene()
	await _test_every_board()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROGRESS_PATH))
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("")
	print("=== RESULTADO: %d controles, %d fallos ===" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FALLO: %s" % failure)
	quit(1 if not _failures.is_empty() else 0)


# ---------------------------------------------------------------- Ayudas

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok     %s" % label)
	else:
		_failures.append(label)
		print("  FALLO  %s" % label)


func _scan(path: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	for file_name in DirAccess.get_files_at(path):
		if file_name.get_extension() == extension:
			found.append(path.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(path):
		if dir_name.begins_with("."):
			continue
		found.append_array(_scan(path.path_join(dir_name), extension))
	return found


func _wait_until(condition: Callable, timeout: float = 8.0) -> bool:
	var waited: float = 0.0
	while waited < timeout:
		if condition.call():
			return true
		await create_timer(0.05).timeout
		waited += 0.05
	return bool(condition.call())


func _arrived(key: String) -> bool:
	var scene: Node = current_scene
	if scene == null or _router.is_transitioning or _router.current_key != key:
		return false
	return scene.scene_file_path == str(_router.SCENES[key])


func _dice_idle(dice: Node) -> bool:
	return not dice.is_rolling


func _camera_settled(camera: Node) -> bool:
	return absf(camera.distance - camera.default_distance) < 0.3


## Busca un nodo (por ruta o %NombreUnico) en la escena actual y registra un fallo si falta.
func _node(path: String) -> Node:
	var scene: Node = current_scene
	var found: Node = null
	if scene != null:
		found = scene.get_node_or_null(path)
	_check(found != null, "existe el nodo %s" % path)
	return found


func _go_to_menu() -> bool:
	await _wait_until(_idle_router, 10.0)
	_router.go_to("main_menu")
	return await _wait_until(_arrived.bind("main_menu"), 15.0)


# ---------------------------------------------------------------- Pruebas estáticas

func _test_project_settings() -> void:
	print("-- Configuración del proyecto")
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_check(ResourceLoader.exists(main_scene), "la escena principal existe (%s)" % main_scene)
	_check(int(ProjectSettings.get_setting("display/window/handheld/orientation", -1)) == 4,
			"orientación horizontal con sensor")
	_check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "gl_compatibility",
			"renderizador de compatibilidad (OpenGL)")
	_check(bool(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false)),
			"compresión ETC2/ASTC activada (necesaria para Android)")
	_check(FileAccess.file_exists("res://icon.svg"), "existe el icono del juego")

	var cfg := ConfigFile.new()
	var err: int = cfg.load("res://export_presets.cfg")
	_check(err == OK, "export_presets.cfg se puede leer")
	if err == OK:
		_check(str(cfg.get_value("preset.0", "platform", "")) == "Android", "el preset de exportación es Android")
		_check(bool(cfg.get_value("preset.0.options", "architectures/arm64-v8a", false)), "se exporta arm64-v8a")
		_check(not bool(cfg.get_value("preset.0.options", "gradle_build/use_gradle_build", true)),
				"exportación APK directa (sin Gradle)")
		var package_name: String = str(cfg.get_value("preset.0.options", "package/unique_name", ""))
		var regex := RegEx.new()
		regex.compile("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$")
		_check(regex.search(package_name) != null, "nombre de paquete válido (%s)" % package_name)
		_check(str(cfg.get_value("preset.0", "include_filter", "")).contains("*.json"),
				"la exportación incluye los archivos .json de data/")
		_check(bool(cfg.get_value("preset.0.options", "permissions/internet", false)),
				"el APK declara el permiso de Internet (necesario para jugar en línea)")
		_check(str(cfg.get_value("preset.0", "exclude_filter", "")).contains("server/*"),
				"la carpeta del servidor (server/) no viaja en el APK")
		_check(str(cfg.get_value("preset.0.options", "version/name", "")) == str(ProjectSettings.get_setting("application/config/version", "")),
				"la versión del APK coincide con la del proyecto")
	_check(ProjectSettings.has_setting("autoload/OnlineManager"), "OnlineManager está registrado como autoload")


func _test_scripts_compile() -> void:
	print("-- Scripts: compilación")
	var paths: Array[String] = _scan("res://scripts", "gd")
	_check(paths.size() >= 25, "se encontraron los scripts del juego (%d)" % paths.size())
	for path in paths:
		var script := load(path) as GDScript
		_check(script != null and script.can_instantiate(), "compila %s" % path)


func _test_scene_loading() -> void:
	print("-- Escenas: carga e instancia")
	var paths: Array[String] = _scan("res://scenes", "tscn")
	_check(paths.size() >= 12, "se encontraron las escenas del juego (%d)" % paths.size())
	for path in paths:
		var packed := load(path) as PackedScene
		var ok: bool = false
		if packed != null:
			var instance: Node = packed.instantiate()
			ok = instance != null
			if instance != null:
				instance.free()
		_check(ok, "carga e instancia %s" % path)
	for key in _router.SCENES:
		var scene_path: String = str(_router.SCENES[key])
		_check(ResourceLoader.exists(scene_path), "ruta del router '%s' existe (%s)" % [key, scene_path])


func _test_resource_references() -> void:
	print("-- Rutas res:// referenciadas")
	var regex := RegEx.new()
	regex.compile("res://[A-Za-z0-9_\\-./]+")
	var checked: int = 0
	var missing: Array[String] = []
	for extension in ["gd", "tscn", "tres", "godot", "cfg", "json"]:
		for path in _scan("res://", extension):
			var text: String = FileAccess.get_file_as_string(path)
			for result in regex.search_all(text):
				var reference: String = result.get_string().rstrip(".")
				checked += 1
				if not (FileAccess.file_exists(reference) or DirAccess.dir_exists_absolute(reference)):
					missing.append("%s -> %s" % [path, reference])
	_check(checked >= 25, "se revisaron las referencias res:// (%d)" % checked)
	_check(missing.is_empty(), "no hay referencias a archivos inexistentes %s" % str(missing))


func _test_data() -> void:
	print("-- Datos (mapas, preguntas, versículos)")
	var maps: Array = MapCatalog.all_maps()
	_check(maps.size() == 7, "el catálogo tiene 7 mapas (%d)" % maps.size())
	_check(MapCatalog.ids_in_order() == MAP_ORDER, "los mapas están en el orden del viaje %s" % str(MapCatalog.ids_in_order()))
	_check(MapCatalog.playable_maps().size() == 7, "los 7 mapas están hechos y son jugables")
	_check(MapCatalog.is_playable(MapCatalog.default_map_id()) and MapCatalog.default_map_id() == "eden",
			"el primer mapa (Jardín del Edén) es el que está abierto desde el inicio")
	var ids: Dictionary = {}
	var styles: Dictionary = {}
	var board_styles: Dictionary = {}
	var positions: Dictionary = {}
	var layouts: Dictionary = {}
	var badges: Dictionary = {}
	for entry in maps:
		var map_data: Dictionary = entry
		var map_id: String = str(map_data["id"])
		ids[map_id] = true
		var layout: BoardLayout = BoardLayout.from_map(map_data)
		var problems: PackedStringArray = layout.validate()
		_check(problems.is_empty(), "tablero válido: %s %s" % [map_id, str(problems)])
		_check(layout.tile_count() == 100 and layout.map_id == map_id,
				"%s: tablero de 100 casillas (inicio, meta y recorrido en zigzag)" % map_id)
		_check(layout.ladders.size() == 6 and layout.snakes.size() == 7,
				"%s: 6 escaleras y 7 serpientes (%d y %d)" % [map_id, layout.ladders.size(), layout.snakes.size()])
		_check(layout.challenge_tiles.size() == 20, "%s: 20 casillas de desafío bíblico (%d)" % [map_id, layout.challenge_tiles.size()])
		_check(layout.special_count(true) == 4 and layout.special_count(false) == 4,
				"%s: 4 recompensas y 4 obstáculos (%d y %d)" % [map_id, layout.special_count(true), layout.special_count(false)])
		var theme_data: Dictionary = map_data["theme"]
		for key in ["tile_a", "tile_b", "frame", "ground", "sky_top", "sky_horizon", "ambient", "fog", "sun"]:
			if not (theme_data.get(key) is Color):
				_check(false, "el tema de %s tiene el color '%s'" % [map_id, key])
		# Identidad propia: estilo de escenario y de tablero, lugar en el mapa mundial, recompensa y sonido.
		var style: String = str(map_data["style"])
		var board_style: String = str(map_data["board"]["style"])
		_check(not style.is_empty() and not board_style.is_empty() and layout.style == board_style,
				"%s: tiene estilo de escenario (%s) y de tablero (%s)" % [map_id, style, board_style])
		styles[style] = true
		board_styles[board_style] = true
		var world_spot: Vector2 = MapCatalog.world_position(map_id)
		positions["%.0f,%.0f" % [world_spot.x, world_spot.y]] = true
		_check(not str(map_data["world"]["icon"]).is_empty(), "%s: tiene icono 3D en el mapa mundial (%s)" % [map_id, map_data["world"]["icon"]])
		var badge: Dictionary = MapCatalog.badge_of(map_id)
		_check(not badge.is_empty() and not str(badge["name"]).is_empty() and not str(badge["text"]).is_empty()
				and MapCatalog.reward_stars_of(map_id) > 0, "%s: da una insignia y estrellas del viaje al completarse" % map_id)
		badges[str(badge.get("id", ""))] = true
		_check(not str(map_data["ambience"]["sound"]).is_empty(), "%s: tiene sonido ambiente (%s)" % [map_id, map_data["ambience"]["sound"]])
		var lighting: Dictionary = map_data["lighting"]
		var sun_dir: Variant = lighting.get("sun_dir", [])
		_check(float(lighting.get("sun_energy", 0.0)) >= 0.1 and float(lighting.get("sun_energy", 9.0)) <= 0.6
				and float(lighting.get("ambient_energy", 0.0)) >= 0.1 and float(lighting.get("ambient_energy", 9.0)) <= 0.6
				and float(lighting.get("fog_density", 0.0)) >= 0.0005 and float(lighting.get("fog_density", 9.0)) <= 0.02
				and sun_dir is Array and (sun_dir as Array).size() == 3,
				"%s: tiene su propia iluminación (sol, ambiente, niebla y dirección)" % map_id)
		layouts["%s|%s" % [str(layout.ladders), str(layout.snakes)]] = true
	_check(ids.size() == maps.size(), "los ids de mapa no se repiten")
	_check(styles.size() == 7 and board_styles.size() == 7, "cada mapa tiene su propio estilo de escenario y de tablero (no es el mismo tablero con otros colores)")
	_check(positions.size() == 7, "cada mapa tiene su propio lugar en el mapa mundial")
	_check(layouts.size() == 7, "cada mapa tiene sus propias escaleras y serpientes")
	_check(badges.size() == 7, "cada mapa tiene su propia insignia")

	# Desbloqueo progresivo: el primero libre y cada uno pide completar el anterior.
	_check(MapCatalog.requirement_of(MAP_ORDER[0]).is_empty(), "el primer mapa no pide nada para abrirse")
	for i in range(1, MAP_ORDER.size()):
		_check(MapCatalog.requirement_of(MAP_ORDER[i]) == MAP_ORDER[i - 1],
				"%s se abre al completar %s" % [MAP_ORDER[i], MAP_ORDER[i - 1]])
		_check(str(MapCatalog.unlocked_by(MAP_ORDER[i - 1])) == str([MAP_ORDER[i]]),
				"completar %s abre solo %s" % [MAP_ORDER[i - 1], MAP_ORDER[i]])
	_check(MapCatalog.unlocked_by(MAP_ORDER[MAP_ORDER.size() - 1]).is_empty(), "el último mapa no abre ninguno más")

	var desert: Dictionary = MapCatalog.find_map("desierto_sinai")
	_check(not desert.is_empty(), "se conserva el Desierto del Sinaí de la etapa anterior")
	var board: Dictionary = desert.get("board", {})
	_check((board.get("ladders", []) as Array).size() == 6, "el Desierto del Sinaí conserva sus 6 escaleras")
	_check((board.get("snakes", []) as Array).size() == 7, "el Desierto del Sinaí conserva sus 7 serpientes")

	var verses: Dictionary = JsonLoader.load_dictionary("res://data/verses/verse_references.json")
	var verse_list: Array = verses.get("verses", [])
	_check(verse_list.size() >= 40, "hay referencias bíblicas (%d)" % verse_list.size())
	var verse_ids: Dictionary = {}
	for verse in verse_list:
		var entry: Dictionary = verse
		var verse_id: String = str(entry.get("id", ""))
		var verse_map: String = str(entry.get("map", ""))
		var good: bool = not verse_id.is_empty() and not verse_ids.has(verse_id) \
				and not str(entry.get("reference", "")).is_empty() \
				and (verse_map == "general" or ids.has(verse_map))
		verse_ids[verse_id] = true
		if not good:
			_check(false, "referencia bíblica válida: %s" % verse_id)
	_check(true, "referencias bíblicas revisadas")


func _test_board_layout() -> void:
	print("-- Trazado del tablero")
	var desert: Dictionary = MapCatalog.find_map("desierto_sinai")
	var layout: BoardLayout = BoardLayout.from_map(desert)
	_check(layout.tile_count() == 100, "100 casillas")
	_check(layout.grid_of(1) == Vector2i(0, 0), "la casilla 1 está abajo a la izquierda")
	_check(layout.grid_of(10) == Vector2i(9, 0), "la casilla 10 cierra la primera fila")
	_check(layout.grid_of(11) == Vector2i(9, 1), "la fila 2 empieza a la derecha (zigzag)")
	_check(layout.grid_of(20) == Vector2i(0, 1), "la casilla 20 cierra la fila 2")
	_check(layout.grid_of(100) == Vector2i(0, 9), "la meta (100) queda arriba a la izquierda")

	var contiguous: bool = true
	var distinct: Dictionary = {}
	for tile in range(1, 101):
		var center: Vector3 = layout.tile_center(tile)
		distinct["%.2f,%.2f" % [center.x, center.z]] = true
		if tile < 100:
			var step: float = center.distance_to(layout.tile_center(tile + 1))
			if absf(step - BoardLayout.PITCH) > 0.001:
				contiguous = false
	_check(contiguous, "cada casilla está pegada a la siguiente (recorrido continuo)")
	_check(distinct.size() == 100, "las 100 casillas tienen posiciones distintas")
	_check(layout.tile_center(1).x < 0.0 and layout.tile_center(1).z > 0.0,
			"el inicio mira hacia la cámara (x < 0, z > 0)")

	_check(layout.jump_target(3) == 22, "la casilla 3 sube por la escalera a la 22")
	_check(layout.jump_target(98) == 78, "la casilla 98 baja por la serpiente a la 78")
	_check(layout.jump_target(5) == 5, "una casilla normal no salta")
	_check(layout.validate().is_empty(), "el trazado del mapa jugable es válido")

	var broken := BoardLayout.new()
	broken.ladders.append(Vector2i(10, 5))
	broken.snakes.append(Vector2i(20, 30))
	broken.snakes.append(Vector2i(40, 200))
	_check(broken.validate().size() >= 3, "la validación detecta escaleras/serpientes mal definidas")

	# Casillas especiales (recompensas y obstáculos) del Desierto del Sinaí.
	_check(str(layout.special_tiles()) == "[17, 29, 43, 52, 66, 74, 83, 89]",
			"el desierto tiene sus 8 casillas especiales %s" % str(layout.special_tiles()))
	_check(layout.special_at(17)["kind"] == BoardLayout.SPECIAL_ADVANCE and int(layout.special_at(17)["steps"]) == 2 and bool(layout.special_at(17)["good"]),
			"la casilla 17 es una recompensa que avanza 2 casillas")
	_check(layout.special_at(66)["kind"] == BoardLayout.SPECIAL_EXTRA_ROLL and layout.special_at(83)["kind"] == BoardLayout.SPECIAL_STARS,
			"hay recompensas de tirada extra (66) y de estrellas (83)")
	_check(layout.special_at(52)["kind"] == BoardLayout.SPECIAL_BACK and not bool(layout.special_at(52)["good"])
			and layout.special_at(74)["kind"] == BoardLayout.SPECIAL_SKIP,
			"hay obstáculos que retroceden (52) y que hacen perder el turno (74)")
	_check(layout.special_at(2).is_empty() and not layout.is_special_tile(2) and layout.is_special_tile(43), "una casilla normal no es especial")
	_check(layout.is_quiet(2) and layout.is_quiet(4) and not layout.is_quiet(5) and not layout.is_quiet(17)
			and not layout.is_quiet(3) and not layout.is_quiet(1) and not layout.is_quiet(100),
			"una casilla tranquila no tiene desafío, escalera, serpiente ni casilla especial")
	var bad_cases: Array = [
		["en el inicio", 1, BoardLayout.SPECIAL_ADVANCE, true, 2, 0, "Prueba"],
		["fuera del tablero", 101, BoardLayout.SPECIAL_ADVANCE, true, 2, 0, "Prueba"],
		["sobre una escalera", 3, BoardLayout.SPECIAL_ADVANCE, true, 2, 0, "Prueba"],
		["sobre un desafío", 5, BoardLayout.SPECIAL_ADVANCE, true, 2, 0, "Prueba"],
		["tipo de obstáculo en una recompensa", 20, BoardLayout.SPECIAL_BACK, true, 2, 0, "Prueba"],
		["tipo de recompensa en un obstáculo", 20, BoardLayout.SPECIAL_STARS, false, 0, 2, "Prueba"],
		["avanzar 0 casillas", 20, BoardLayout.SPECIAL_ADVANCE, true, 0, 0, "Prueba"],
		["retroceder 9 casillas", 20, BoardLayout.SPECIAL_BACK, false, 9, 0, "Prueba"],
		["0 estrellas", 20, BoardLayout.SPECIAL_STARS, true, 0, 0, "Prueba"],
		["sin nombre", 20, BoardLayout.SPECIAL_ADVANCE, true, 2, 0, ""],
	]
	for bad in bad_cases:
		var probe: BoardLayout = _desert_layout()
		probe.special_list.clear()
		probe.specials.clear()
		var info: Dictionary = {"tile": int(bad[1]), "kind": str(bad[2]), "name": str(bad[6]), "ref": "",
				"steps": int(bad[4]), "stars": int(bad[5]), "good": bool(bad[3])}
		probe.special_list.append(info)
		probe.specials[int(bad[1])] = info
		_check(not probe.validate().is_empty(), "la validación detecta una casilla especial %s" % str(bad[0]))
	var repeated: BoardLayout = _desert_layout()
	repeated.special_list.append(repeated.special_list[0].duplicate())
	_check(not repeated.validate().is_empty(), "la validación detecta una casilla especial repetida")

	for count in range(1, 5):
		var seen: Dictionary = {}
		for slot in count:
			var offset: Vector3 = BoardLayout.token_offset(slot, count)
			seen["%.2f,%.2f" % [offset.x, offset.z]] = true
			_check(absf(offset.x) <= 0.3 and absf(offset.z) <= 0.3, "ficha %d de %d cabe en la casilla" % [slot + 1, count])
		_check(seen.size() == count, "%d fichas ocupan posiciones distintas" % count)


func _test_character_roster() -> void:
	print("-- Personajes y jugadores")
	var characters: Array = CharacterCatalog.all_characters()
	_check(characters.size() >= 4, "hay al menos 4 personajes para 4 jugadores")
	var unique: Dictionary = {}
	for entry in characters:
		var character: Dictionary = entry
		unique[str(character["id"])] = true
		_check(character["color"] is Color and not str(character["name"]).is_empty(), "personaje completo: %s" % character["id"])
	_check(unique.size() == characters.size(), "los ids de personaje no se repiten")

	_state.select_character(CharacterCatalog.all_ids()[0])
	for count in range(1, 5):
		_state.set_player_count(count)
		var roster: Array = _state.build_roster()
		var used: Dictionary = {}
		for entry in roster:
			used[str(entry["character_id"])] = true
		_check(roster.size() == count and used.size() == count, "lista de %d jugador(es) sin personajes repetidos" % count)
		_check(str(roster[0]["character_id"]) == str(_state.selected_character_id), "el jugador 1 usa el personaje elegido")
	_state.set_player_count(99)
	_check(_state.player_count == 4, "el número de jugadores se limita a 4")
	_state.set_player_count(0)
	_check(_state.player_count == 1, "el número de jugadores no baja de 1")


func _test_meshes() -> void:
	print("-- Mallas 3D (orientación de las caras)")
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in 12:
		points.append(Vector3(float(i) * 0.3, 0.2 + sin(float(i)) * 0.1, cos(float(i) * 0.7) * 0.3))
		radii.append(0.12)
		colors.append(Color.WHITE)
	var tube: ArrayMesh = MeshFactory.tube(points, radii, colors, 8)
	_check(_winding_ratio(tube) > 0.999, "el tubo de las serpientes tiene las caras hacia afuera")

	var terrain: ArrayMesh = LandscapeBuilder.terrain_mesh()
	_check(terrain.get_surface_count() == 1, "el terreno tiene una superficie")
	_check(_winding_ratio(terrain) > 0.999, "el terreno tiene las caras hacia arriba")

	var left := PackedVector3Array([Vector3(-1, 0, 0), Vector3(-1, 0, 2), Vector3(-1, 0, 4)])
	var right := PackedVector3Array([Vector3(1, 0, 0), Vector3(1, 0, 2), Vector3(1, 0, 4)])
	_check(_winding_ratio(MeshFactory.ribbon(left, right)) > 0.999, "la cinta del río tiene las caras hacia arriba")
	_check(is_finite(LandscapeBuilder.height_at(3.0, -7.0)), "la altura del terreno es un número válido")


## Fracción de triángulos cuyo orden de vértices (horario = cara frontal en Godot)
## coincide con las normales guardadas en la malla.
func _winding_ratio(mesh: ArrayMesh) -> float:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i in verts.size():
			indices.append(i)
	var good: int = 0
	var total: int = 0
	for t in range(0, indices.size() - 2, 3):
		var a: Vector3 = verts[indices[t]]
		var b: Vector3 = verts[indices[t + 1]]
		var c: Vector3 = verts[indices[t + 2]]
		var front: Vector3 = (c - a).cross(b - a)
		if front.length_squared() < 0.000000001:
			continue
		var stored: Vector3 = norms[indices[t]] + norms[indices[t + 1]] + norms[indices[t + 2]]
		total += 1
		if front.dot(stored) > 0.0:
			good += 1
	return float(good) / float(maxi(total, 1))


# ---------------------------------------------------------------- Herramientas 3D de los escenarios

## Fracción de triángulos cuya normal guardada apunta lejos de "center" (piezas convexas).
func _outward_ratio(mesh: ArrayMesh, center: Vector3) -> float:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var good: int = 0
	var total: int = 0
	for t in range(0, verts.size() - 2, 3):
		var centroid: Vector3 = (verts[t] + verts[t + 1] + verts[t + 2]) / 3.0
		total += 1
		if norms[t].dot(centroid - center) > 0.0:
			good += 1
	return float(good) / float(maxi(total, 1))


## Triángulos de todas las mallas de un nodo (y sus hijos).
func _triangles_of(node: Node) -> int:
	var total: int = 0
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				total += int(float(verts.size()) / 3.0)
	for child in node.get_children():
		total += _triangles_of(child)
	return total


func _count_nodes(node: Node, type_name: String) -> int:
	var total: int = 0
	if node.is_class(type_name):
		total += 1
	for child in node.get_children():
		total += _count_nodes(child, type_name)
	return total


func _piece_ok(label: String, kit: MeshKit, center: Vector3, minimum: float = 0.999) -> void:
	_check(kit.triangle_count() > 0, "%s: tiene triángulos (%d)" % [label, kit.triangle_count()])
	if kit.triangle_count() == 0:
		return
	var mesh: ArrayMesh = kit.commit()
	_check(_winding_ratio(mesh) > 0.999, "%s: el orden de los vértices coincide con las normales" % label)
	_check(_outward_ratio(mesh, center) >= minimum, "%s: las caras miran hacia afuera" % label)


func _test_kits() -> void:
	print("-- Herramientas 3D (mallas, texturas, terreno, agua, efectos)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var white := Color.WHITE

	var kit := MeshKit.new()
	kit.box(Vector3(1.0, 2.0, 3.0), Vector3(2.0, 1.0, 4.0), white)
	_check(kit.triangle_count() == 12, "una caja tiene 12 triángulos")
	_piece_ok("caja", kit, Vector3(1.0, 2.0, 3.0))

	kit = MeshKit.new()
	kit.cylinder(Vector3.ZERO, 1.0, 0.7, 2.0, 8, white, true, true)
	_piece_ok("cilindro", kit, Vector3(0.0, 1.0, 0.0))
	kit = MeshKit.new()
	kit.cone(Vector3.ZERO, 1.0, 2.0, 7, white)
	_piece_ok("cono", kit, Vector3(0.0, 0.6, 0.0))
	kit = MeshKit.new()
	kit.pyramid(Vector3.ZERO, 1.5, 3.0, white)
	_piece_ok("pirámide", kit, Vector3(0.0, 1.0, 0.0))
	_check(kit.triangle_count() == 4, "una pirámide tiene 4 caras")
	kit = MeshKit.new()
	kit.frustum(Vector3.ZERO, 1.0, 0.5, 3.0, white)
	_piece_ok("tronco de pirámide", kit, Vector3(0.0, 1.5, 0.0))
	kit = MeshKit.new()
	kit.sphere(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.7, 1.2), white, 8, 5, 0.2, rng)
	_piece_ok("esfera irregular", kit, Vector3(0.0, 1.0, 0.0), 0.98)
	kit = MeshKit.new()
	kit.dome(Vector3.ZERO, 1.5, white)
	_piece_ok("cúpula", kit, Vector3(0.0, 0.3, 0.0))
	kit = MeshKit.new()
	kit.gable(Vector3.ZERO, Vector3(4.0, 1.5, 3.0), white)
	_piece_ok("techo a dos aguas", kit, Vector3(0.0, 0.5, 0.0))
	kit = MeshKit.new()
	kit.beam(Vector3.ZERO, Vector3(3.0, 1.0, 2.0), 0.2, 0.1, white)
	_piece_ok("viga", kit, Vector3(1.5, 0.5, 1.0))

	# Dos polígonos (uno en cada sentido) dan prismas con las caras hacia afuera.
	var square_ccw := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var square_cw := PackedVector2Array([Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)])
	kit = MeshKit.new()
	kit.extrude(square_ccw, 0.0, 2.0, white)
	_piece_ok("prisma (sentido antihorario)", kit, Vector3(0.0, 1.0, 0.0))
	kit = MeshKit.new()
	kit.extrude(square_cw, 0.0, 2.0, white)
	_piece_ok("prisma (sentido horario)", kit, Vector3(0.0, 1.0, 0.0))

	# Colocar, girar, escalar y reflejar no deja caras al revés.
	kit = MeshKit.new()
	kit.place(Vector3(10.0, 0.0, 0.0), PI * 0.5, Vector3(1.0, 2.0, 0.5))
	kit.box(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 1.0, 1.0), white)
	kit.pop()
	_piece_ok("caja girada y escalada", kit, Vector3(10.0, 2.0, 0.0))
	kit = MeshKit.new()
	kit.place(Vector3(0.0, 0.0, 0.0), 0.0, Vector3(-1.0, 1.0, 1.0))
	kit.box(Vector3(3.0, 1.0, 0.0), Vector3(1.0, 1.0, 1.0), white)
	kit.pop()
	_piece_ok("caja reflejada", kit, Vector3(-3.0, 1.0, 0.0))
	_check(kit.xf == Transform3D.IDENTITY, "pop() devuelve la colocación anterior")

	# Tubo recto con los extremos abiertos: las caras miran lejos del eje.
	var tube_points := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	var tube_radii := PackedFloat32Array([0.2, 0.2, 0.15, 0.1])
	kit = MeshKit.new()
	kit.tube(tube_points, tube_radii, white, 6)
	var tube_mesh: ArrayMesh = kit.commit()
	_check(kit.triangle_count() == 3 * 6 * 2, "un tubo de 4 puntos y 6 lados tiene 36 triángulos")
	_check(_winding_ratio(tube_mesh) > 0.999, "el tubo del escenario tiene el orden de vértices correcto")
	var tube_arrays: Array = tube_mesh.surface_get_arrays(0)
	var tube_verts: PackedVector3Array = tube_arrays[Mesh.ARRAY_VERTEX]
	var tube_norms: PackedVector3Array = tube_arrays[Mesh.ARRAY_NORMAL]
	var tube_out: int = 0
	for t in range(0, tube_verts.size() - 2, 3):
		var centroid: Vector3 = (tube_verts[t] + tube_verts[t + 1] + tube_verts[t + 2]) / 3.0
		if tube_norms[t].dot(Vector3(0.0, centroid.y, centroid.z)) > 0.0:
			tube_out += 1
	_check(tube_out == kit.triangle_count(), "el tubo del escenario mira hacia afuera")

	# La estrella se ve por los dos lados.
	kit = MeshKit.new()
	kit.star(Vector3.ZERO, 1.0, 0.45, white)
	_check(kit.triangle_count() == 20, "una estrella plana tiene 20 triángulos (dos lados)")
	var star_mesh: ArrayMesh = kit.commit()
	var star_arrays: Array = star_mesh.surface_get_arrays(0)
	var star_norms: PackedVector3Array = star_arrays[Mesh.ARRAY_NORMAL]
	var plus_z: int = 0
	var minus_z: int = 0
	for n in star_norms:
		if n.z > 0.9:
			plus_z += 1
		elif n.z < -0.9:
			minus_z += 1
	_check(plus_z == minus_z and plus_z > 0, "la estrella tiene el mismo número de caras hacia cada lado")

	# Coordenadas de textura y colores guardados.
	kit = MeshKit.new()
	kit.uv_scale = 0.5
	kit.box(Vector3.ZERO, Vector3(2.0, 2.0, 2.0), Color(0.2, 0.4, 0.6))
	var box_arrays: Array = kit.commit().surface_get_arrays(0)
	var box_uvs: PackedVector2Array = box_arrays[Mesh.ARRAY_TEX_UV]
	var box_colors: PackedColorArray = box_arrays[Mesh.ARRAY_COLOR]
	_check(box_uvs.size() == 36 and box_colors.size() == 36, "la malla guarda UVs y colores por vértice")
	_check(box_colors[0].is_equal_approx(Color(0.2, 0.4, 0.6)), "el color por vértice es el pedido")

	# Una malla vacía no rompe nada.
	var empty := MeshKit.new()
	_check(empty.is_empty() and empty.commit().get_surface_count() == 0, "una malla vacía no tiene superficies")

	# Piezas decorativas: todas producen geometría razonable.
	var props: Dictionary = {}
	kit = MeshKit.new()
	PropKit.tree_round(kit, rng, Vector3.ZERO, 1.0, Color(0.3, 0.6, 0.3))
	props["árbol"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.tree_fruit(kit, rng, Vector3.ZERO, 1.0, Color(0.3, 0.6, 0.3), Color(0.9, 0.2, 0.2))
	props["frutal"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.cypress(kit, rng, Vector3.ZERO, 1.0)
	props["ciprés"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.olive(kit, rng, Vector3.ZERO, 1.0)
	props["olivo"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.palm(kit, rng, Vector3.ZERO, 1.0)
	props["palmera"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.papyrus(kit, rng, Vector3.ZERO, 1.0)
	props["papiro"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.rock(kit, rng, Vector3.ZERO, 1.0, Color(0.5, 0.5, 0.5))
	props["roca"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.house_gable(kit, rng, Vector3.ZERO, 0.3, 2.0, 2.0, 1.6, Color(0.9, 0.85, 0.7), Color(0.6, 0.3, 0.2))
	props["casa con tejado"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.house_flat(kit, rng, Vector3.ZERO, 0.3, 2.0, 2.0, 1.6, Color(0.9, 0.85, 0.7))
	props["casa de techo plano"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.tower(kit, Vector3.ZERO, 1.0, 4.0, Color(0.8, 0.75, 0.65), Color(0.6, 0.3, 0.2))
	props["torre"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.wall_run(kit, Vector3(0, 0, 0), Vector3(6, 0, 2), 2.0, 0.6, Color(0.8, 0.75, 0.65))
	props["muro"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.column(kit, Vector3.ZERO, 0.3, 3.0, Color(0.9, 0.88, 0.8))
	props["columna"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.obelisk(kit, Vector3.ZERO, 0.5, 4.0, Color(0.9, 0.8, 0.6), Color(0.95, 0.8, 0.3))
	props["obelisco"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.tent(kit, Vector3.ZERO, 0.0, 1.5, Color(0.5, 0.35, 0.25))
	props["tienda"] = kit.triangle_count()
	kit = MeshKit.new()
	PropKit.barrel(kit, Vector3.ZERO, 0.3, 0.7, Color(0.5, 0.35, 0.2))
	PropKit.crate(kit, Vector3.ZERO, 0.5, Color(0.5, 0.35, 0.2))
	PropKit.hay_bale(kit, Vector3.ZERO, 0.0, Color(0.85, 0.75, 0.4))
	PropKit.torch(kit, Vector3.ZERO)
	PropKit.lantern_post(kit, Vector3.ZERO, 1.5)
	PropKit.gateway(kit, Vector3.ZERO, 3.0, 3.0, 0.5, Color(0.8, 0.75, 0.65), Color(0.9, 0.8, 0.5))
	PropKit.flower(kit, Vector3.ZERO, Color.RED)
	PropKit.bush(kit, rng, Vector3.ZERO, 1.0, Color(0.2, 0.5, 0.2))
	props["objetos pequeños"] = kit.triangle_count()
	for prop_name in props:
		var count: int = int(props[prop_name])
		_check(count > 0 and count < 400, "pieza decorativa '%s' tiene una cantidad razonable de triángulos (%d)" % [prop_name, count])

	# Animales del escenario: cada uno es una pieza razonable y con el orden de vértices correcto.
	for animal in ["elefante", "jirafa", "leon", "cebra", "oveja", "burro", "buey", "paloma"]:
		kit = MeshKit.new()
		AnimalKit.make(kit, rng, str(animal), Vector3.ZERO, 0.0, 1.0)
		var animal_triangles: int = kit.triangle_count()
		_check(animal_triangles > 60 and animal_triangles < 500,
				"animal '%s' tiene una cantidad razonable de triángulos (%d)" % [str(animal), animal_triangles])
		_check(_winding_ratio(kit.commit()) > 0.999, "animal '%s' tiene el orden de vértices correcto" % str(animal))
	kit = MeshKit.new()
	AnimalKit.make(kit, rng, "especie_inventada", Vector3.ZERO, 0.0, 1.0)
	_check(kit.is_empty(), "un animal desconocido no agrega nada")
	kit = MeshKit.new()
	AnimalKit.make(kit, rng, "jirafa", Vector3(5.0, 0.0, 5.0), 1.0, 1.0)
	_check(kit.xf == Transform3D.IDENTITY, "colocar un animal deja el MeshKit como estaba")

	# Texturas y materiales.
	for kind in TextureKit.kinds():
		var texture: ImageTexture = TextureKit.texture(kind)
		_check(texture != null and texture.get_width() == TextureKit.SIZE and texture.get_height() == TextureKit.SIZE,
				"textura '%s' de %d x %d" % [kind, TextureKit.SIZE, TextureKit.SIZE])
		var image: Image = texture.get_image()
		var total: float = 0.0
		for y in range(0, TextureKit.SIZE, 3):
			for x in range(0, TextureKit.SIZE, 3):
				total += image.get_pixel(x, y).r
		var average: float = total / float(22 * 22)
		_check(average > 0.55 and average < 1.0, "la textura '%s' no es ni muy oscura ni quemada (%.2f)" % [kind, average])
	_check(TextureKit.texture("grass") == TextureKit.texture("grass"), "las texturas se guardan en caché")
	_check(TextureKit.material("stone") == TextureKit.material("stone"), "los materiales se guardan en caché")
	_check(TextureKit.material("planks").albedo_texture != null and TextureKit.material("planks").vertex_color_use_as_albedo,
			"el material con textura usa también el color por vértice")
	_check(TextureKit.glow_vertex(true).blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "el material de luz es aditivo")
	_check(TextureKit.soft_dot().get_width() == 32, "el punto suave de las partículas es de 32 píxeles")

	# Terreno.
	_check(is_zero_approx(TerrainKit.board_mask(TerrainKit.PLATEAU_CENTER_X, 0.0)), "bajo el tablero el terreno es plano")
	_check(TerrainKit.board_mask(60.0, 0.0) > 0.999, "lejos del tablero el relieve actúa completo")
	var mid: float = TerrainKit.board_mask(TerrainKit.PLATEAU_CENTER_X + TerrainKit.PLATEAU_HALF_X + 4.0, 0.0)
	_check(mid > 0.0 and mid < 1.0, "entre medias la subida es gradual (%.2f)" % mid)
	var height_fn := func(x: float, z: float) -> float: return sin(x) * 0.3 + z * 0.02
	var color_fn := func(_x: float, _z: float, _y: float) -> Color: return Color(0.4, 0.6, 0.3)
	var grid: ArrayMesh = TerrainKit.build(10.0, 8, height_fn, color_fn, 0.3)
	_check(grid.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 8 * 8 * 2 * 3, "el terreno de 8 x 8 tiene 128 triángulos")
	_check(_winding_ratio(grid) > 0.999, "el terreno tiene las caras hacia arriba")
	var grid_norms: PackedVector3Array = grid.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var all_up: bool = true
	for n in grid_norms:
		if n.y <= 0.0:
			all_up = false
	_check(all_up, "todas las normales del terreno miran hacia arriba")

	# Agua.
	var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 3), Vector3(0, 0, 6), Vector3(-1, 0, 9)])
	var ribbon: ArrayMesh = WaterKit.ribbon(path, 2.0)
	_check(_winding_ratio(ribbon) > 0.999, "la cinta del río del escenario mira hacia arriba")
	var ribbon_norms: PackedVector3Array = ribbon.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var ribbon_up: bool = ribbon_norms.size() > 0
	for n in ribbon_norms:
		if n.y <= 0.0:
			ribbon_up = false
	_check(ribbon_up, "las normales de la cinta miran hacia arriba")
	var sheet: ArrayMesh = WaterKit.sheet(Vector3(0, 5, 0), Vector3(4, 5, 0), Vector3(0, 0, 2), Vector3(4, 0, 2), 3, 2)
	_check(sheet.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 3 * 2 * 2 * 3, "la lámina de 3 x 2 tiene 12 triángulos")
	_check(WaterKit.WATER_SHADER.contains("shader_type spatial") and WaterKit.FALL_SHADER.contains("shader_type spatial"),
			"los shaders de agua están definidos")
	var water: ShaderMaterial = WaterKit.water_material(Color(0.1, 0.4, 0.6, 0.9), Color(0.4, 0.8, 0.8, 0.8))
	_check(water.shader != null and water.shader.code.length() > 100, "el material del agua tiene su shader")
	_check(water == WaterKit.water_material(Color(0.1, 0.4, 0.6, 0.9), Color(0.4, 0.8, 0.8, 0.8)),
			"el material del agua se guarda en caché")

	# Efectos.
	var holder := Node3D.new()
	var floaters: CPUParticles3D = FxKit.floaters(holder, "Prueba", Vector3.ZERO, Vector3.ONE, 20, 0.2, Color.WHITE)
	_check(floaters.amount == 20 and floaters.get_parent() == holder, "las partículas flotantes se crean y se agregan")
	FxKit.clouds(holder, rng, 4, 30.0, 40.0, 100.0)
	_check(_count_nodes(holder, "MeshInstance3D") == 4, "se crean las 4 nubes pedidas")
	FxKit.birds(holder, rng, 3, Vector3.ZERO, 10.0, 8.0, Color.WHITE)
	_check(holder.get_children().size() == 1 + 4 + 3, "se crean las 3 aves pedidas")
	var stars: MeshInstance3D = FxKit.star_dome(holder, rng, 50)
	_check(_triangles_of(stars) == 50 * 4, "50 estrellas tienen 200 triángulos")
	var beam: MeshInstance3D = FxKit.beam(holder, Vector3.ZERO, 10.0, 1.0, 0.4, Color(1, 1, 0.8, 0.5))
	_check(_triangles_of(beam) > 0, "el haz de luz tiene geometría")
	holder.free()


## Las cifras de trazos y las marcas de las casillas: geometría plana, hacia arriba y dentro de la casilla.
func _test_stroke_font_and_marks() -> void:
	print("-- Números de trazos y marcas de casillas")
	for glyph in "0123456789?":
		var one := MeshKit.new()
		StrokeFont.add_text(one, glyph, Vector3.ZERO, 0.3, 0.05, Color.BLACK)
		_check(one.triangle_count() >= 4, "el glifo '%s' tiene trazos (%d triángulos)" % [glyph, one.triangle_count()])
	_check(is_equal_approx(StrokeFont.text_width("100", 1.0), 2.0 * StrokeFont.ADVANCE + StrokeFont.GLYPH_WIDTH),
			"el ancho de '100' suma tres glifos")
	_check(StrokeFont.text_width("", 1.0) == 0.0, "un texto vacío no mide nada")
	var center := Vector3(1.0, 0.2, 3.0)
	var kit := MeshKit.new()
	StrokeFont.add_text(kit, "100", center, 0.3, 0.05, Color.BLACK)
	StrokeFont.add_text(kit, "x", center, 0.3, 0.05, Color.BLACK)
	var arrays: Array = kit.commit().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var half_width: float = StrokeFont.text_width("100", 0.3) * 0.5 + 0.05
	var inside: bool = true
	var facing_up: bool = true
	for i in verts.size():
		if absf(verts[i].x - center.x) > half_width or absf(verts[i].z - center.z) > 0.15 + 0.05 or not is_equal_approx(verts[i].y, 0.2):
			inside = false
		if normals[i].y < 0.99:
			facing_up = false
	_check(verts.size() > 0 and inside, "el número queda dentro de su caja y a una sola altura")
	_check(facing_up, "los trazos miran hacia arriba")
	_check(StrokeFont.GLYPHS.size() == 11, "hay glifos para 0-9 y '?'")

	var tile_center := Vector3(2.0, BoardLayout.TILE_HEIGHT, -1.0)
	var marks := MeshKit.new()
	var ink := MeshKit.new()
	TileMarks.add_number(ink, 37, tile_center, Color(0.9, 0.9, 0.8))
	_check(ink.triangle_count() > 20, "el número 37 tiene geometría")
	for kind in ["advance", "extra_roll", "stars", "back", "skip"]:
		var icon_marks := MeshKit.new()
		var icon_ink := MeshKit.new()
		TileMarks.add_special(icon_marks, icon_ink, str(kind), tile_center)
		_check(icon_marks.triangle_count() > 20, "el icono '%s' tiene figuras (%d triángulos)" % [str(kind), icon_marks.triangle_count()])
	TileMarks.add_challenge(marks, ink, tile_center)
	_check(marks.triangle_count() == 14, "el disco de desafío tiene 14 triángulos")
	var bright := MeshKit.new()
	TileMarks.add_number(bright, 8, tile_center, Color(0.1, 0.1, 0.1))
	var dark_ink := MeshKit.new()
	TileMarks.add_number(dark_ink, 8, tile_center, Color(0.95, 0.95, 0.9))
	var light_color: Color = (bright.commit().surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray)[0]
	var dark_color: Color = (dark_ink.commit().surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray)[0]
	_check(light_color.get_luminance() > 0.6 and dark_color.get_luminance() < 0.2,
			"el número es claro sobre casillas oscuras y oscuro sobre casillas claras")
	var night_ink := MeshKit.new()
	TileMarks.add_number(night_ink, 8, tile_center, Color(0.95, 0.95, 0.9), true)
	var night_color: Color = (night_ink.commit().surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray)[0]
	_check(night_color.get_luminance() > 0.6, "en un tablero de noche el número va en claro aunque la casilla sea clara")


## Cada mapa construye su propio tablero: casillas, borde, puertas, escaleras y serpientes del
## estilo, con pocas mallas, y todo lo que el motor necesita (anclas, marcas, caminos).
func _test_board_styles() -> void:
	print("-- Tableros propios de cada mapa")
	_check(BoardStyle.normalize("nada") == "sand" and BoardStyle.normalize("city") == "city",
			"un estilo desconocido usa el del desierto")
	_check(BoardStyle.is_night("village") and not BoardStyle.is_night("garden") and not BoardStyle.is_night("sand"),
			"solo el tablero de Belén es de noche")
	var surface_triangles: Dictionary = {}
	var landmark_triangles: Dictionary = {}
	var ids: Array[String] = MapCatalog.ids_in_order()
	_check(ids.size() == 7, "hay 7 mapas con tablero propio")
	for id in ids:
		var map_data: Dictionary = MapCatalog.find_map(id)
		var layout: BoardLayout = BoardLayout.from_map(map_data)
		var label: String = str(map_data.get("name", id))
		var builder := BoardBuilder.new()
		builder.build(layout, map_data.get("theme", {}))
		_check(builder.board_style() == BoardStyle.normalize(layout.style), "%s: usa el estilo '%s'" % [label, layout.style])
		_check(builder.tile_count() == 100 and builder.ladder_count() == 6 and builder.snake_count() == 7,
				"%s: 100 casillas, 6 escaleras y 7 serpientes" % label)
		for piece_name in ["TileSurface", "TileMarks", "TileInk", "FrameDecor", "StartMarker/Body", "GoalMarker/Body"]:
			_check(builder.get_node_or_null(str(piece_name)) != null, "%s: tiene '%s'" % [label, str(piece_name)])
		var surface := builder.get_node_or_null("TileSurface") as MeshInstance3D
		var triangles: int = _triangles_of(surface) if surface != null else 0
		surface_triangles[triangles] = true
		_check(triangles >= 100 * 8, "%s: superficie con geometría (%d triángulos)" % [label, triangles])
		var meshes: int = _count_nodes(builder, "MeshInstance3D")
		_check(meshes <= 40, "%s: pocas llamadas de dibujo en el tablero (%d mallas)" % [label, meshes])
		_check(_count_nodes(builder, "Label3D") == 2, "%s: solo hay dos rótulos de texto (INICIO y META)" % label)
		_check(_triangles_of(builder) <= 70000, "%s: el tablero cabe en el presupuesto de triángulos (%d)" % [label, _triangles_of(builder)])
		var landmarks: int = _triangles_of(builder.get_node_or_null("StartMarker")) + _triangles_of(builder.get_node_or_null("GoalMarker"))
		landmark_triangles[landmarks] = true
		var all_marked: bool = true
		for tile in layout.challenge_tiles:
			if not builder.has_challenge_mark(tile):
				all_marked = false
		_check(all_marked, "%s: todas las casillas de desafío tienen su marca" % label)
		var specials_marked: bool = true
		for tile in layout.special_tiles():
			if not builder.has_special_mark(tile):
				specials_marked = false
		_check(specials_marked and layout.special_tiles().size() == 8, "%s: las 8 casillas especiales tienen su icono" % label)
		var anchors_ok: bool = true
		for tile in [1, 37, 100]:
			var anchor: Node3D = builder.tile_node(tile)
			if anchor == null or anchor.position.distance_to(builder.tile_position(tile)) > 0.001:
				anchors_ok = false
		_check(anchors_ok, "%s: las anclas están sobre sus casillas" % label)
		var head: Node3D = builder.snake_head_node(layout.snakes[0].x)
		_check(head != null and head.get_node_or_null("HeadMesh") != null, "%s: la cabeza de la serpiente es una malla" % label)
		var ladder_body: Node = builder.get_node_or_null("Ladders/Ladder_%03d_%03d/Body" % [layout.ladders[0].x, layout.ladders[0].y])
		_check(ladder_body != null, "%s: cada escalera es una malla" % label)
		_check(builder.snake_path(layout.snakes[0].x, layout.snakes[0].y).size() > 10, "%s: las serpientes tienen camino" % label)
		builder.free()
	_check(surface_triangles.size() >= 6, "las superficies de los tableros son distintas entre sí (%d variantes)" % surface_triangles.size())
	_check(landmark_triangles.size() >= 6, "las puertas de salida y meta son distintas entre sí (%d variantes)" % landmark_triangles.size())


func _test_scenery() -> void:
	print("-- Escenarios 3D")
	_check(SceneryFactory.has_scenery("eden") and not SceneryFactory.has_scenery("desierto"),
			"el desierto conserva su decoración original")
	_test_scenery_eden()
	_test_scenery_style("arca", "arca_noe", "Arca de Noé", ["Sea", "Ark", "Animals", "Ararat", "Rainbow"])
	_test_scenery_style("egipto", "egipto_exodo", "Egipto", ["Terrain", "WaterWall", "SeaVolume", "Monuments", "Flames", "Seabed"])
	_test_scenery_style("sinai", "monte_sinai", "Monte Sinaí", ["Terrain", "Land", "Glow", "SummitCloud", "Beam"])
	_test_scenery_style("jerusalen", "jerusalen", "Jerusalén", ["Terrain", "City", "Trim", "Nature"])
	_test_scenery_style("belen", "belen", "Belén", ["Terrain", "Village", "VillageGlow", "Stable", "StableGlow", "BethlehemStar", "Nature"])
	_test_scenery_city_and_night()


## Construye el escenario de un estilo con los datos reales de su mapa y revisa sus piezas, su
## presupuesto de triángulos y que la calidad baja use menos geometría que la alta.
func _test_scenery_style(style: String, map_id: String, label: String, required_nodes: Array) -> void:
	var map_data: Dictionary = MapCatalog.find_map(map_id)
	var theme_data: Dictionary = map_data.get("theme", {})
	_check(SceneryFactory.has_scenery(style), "%s: el estilo '%s' tiene escenario propio" % [label, style])
	_check(str(map_data.get("style", "")) == style, "%s: el mapa '%s' usa el estilo '%s'" % [label, map_id, style])
	var scenery := Node3D.new()
	SceneryFactory.build(style, scenery, 12345, 1, theme_data)
	_scenery_report(label, scenery, 90000)
	for piece_name in required_nodes:
		_check(scenery.get_node_or_null(str(piece_name)) != null, "%s: tiene '%s'" % [label, str(piece_name)])
	scenery.free()
	var low_root := Node3D.new()
	SceneryFactory.build(style, low_root, 12345, 0, theme_data)
	var low_triangles: int = _triangles_of(low_root)
	low_root.free()
	var high_root := Node3D.new()
	SceneryFactory.build(style, high_root, 12345, 2, theme_data)
	var high_triangles: int = _triangles_of(high_root)
	high_root.free()
	_check(low_triangles < high_triangles, "%s: la calidad baja usa menos triángulos que la alta (%d < %d)" % [label, low_triangles, high_triangles])
	# El mismo escenario con la misma semilla sale idéntico (para que el mapa no cambie de una partida a otra).
	var again := Node3D.new()
	SceneryFactory.build(style, again, 12345, 1, theme_data)
	var first := Node3D.new()
	SceneryFactory.build(style, first, 12345, 1, theme_data)
	_check(_triangles_of(again) == _triangles_of(first), "%s: con la misma semilla el escenario es idéntico" % label)
	again.free()
	first.free()


## Detalles propios de Jerusalén y Belén: suelo bajo el tablero, calles libres y luces del establo.
func _test_scenery_city_and_night() -> void:
	_check(is_equal_approx(SceneryJerusalen.height_at(TerrainKit.PLATEAU_CENTER_X, 0.0), TerrainKit.PLATEAU_Y),
			"Jerusalén: el suelo bajo el tablero está a la altura esperada")
	_check(SceneryJerusalen.height_at(SceneryJerusalen.OLIVES.x, SceneryJerusalen.OLIVES.y) > 8.0,
			"Jerusalén: el monte de los Olivos es alto")
	_check(is_equal_approx(SceneryBelen.height_at(TerrainKit.PLATEAU_CENTER_X, 0.0), TerrainKit.PLATEAU_Y),
			"Belén: el suelo bajo el tablero está a la altura esperada")
	_check(SceneryBelen.height_at(0.0, -46.0) < 2.0, "Belén: el establo está sobre terreno casi plano")
	var map_data: Dictionary = MapCatalog.find_map("belen")
	var theme_data: Dictionary = map_data.get("theme", {})
	var lit := Node3D.new()
	SceneryFactory.build("belen", lit, 12345, 1, theme_data)
	_check(_count_nodes(lit, "OmniLight3D") == 2, "Belén: la fogata y el establo tienen luz cálida (calidad media)")
	lit.free()
	var dark := Node3D.new()
	SceneryFactory.build("belen", dark, 12345, 0, theme_data)
	_check(_count_nodes(dark, "OmniLight3D") == 0, "Belén: la calidad baja no usa luces dinámicas")
	dark.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spots: Array[Vector2] = SceneryKit.scatter_rect(rng, 30, Rect2(Vector2(-40.0, -80.0), Vector2(80.0, 50.0)), 6.0)
	_check(spots.size() > 10, "scatter_rect reparte puntos (%d)" % spots.size())
	var spaced: bool = true
	var clear: bool = true
	for i in spots.size():
		if SceneryKit.is_clear_zone(spots[i].x, spots[i].y):
			clear = false
		for j in range(i + 1, spots.size()):
			if spots[i].distance_to(spots[j]) < 6.0 - 0.001:
				spaced = false
	_check(spaced, "scatter_rect separa los puntos al menos lo pedido")
	_check(clear, "scatter_rect no pone nada en la zona del tablero")


func _scenery_report(label: String, scenery: Node3D, max_triangles: int) -> void:
	var triangles: int = _triangles_of(scenery)
	var meshes: int = _count_nodes(scenery, "MeshInstance3D")
	print("  %s: %d mallas, %d triángulos, %d sistemas de partículas" % [label, meshes, triangles,
			_count_nodes(scenery, "CPUParticles3D")])
	_check(meshes >= 6, "%s: tiene mallas suficientes (%d)" % [label, meshes])
	_check(triangles > 8000 and triangles <= max_triangles, "%s: triángulos dentro del presupuesto (%d de %d)" % [label, triangles, max_triangles])
	_check(_count_nodes(scenery, "MeshInstance3D") <= 48, "%s: pocas llamadas de dibujo (%d mallas)" % [label, meshes])
	var all_off: bool = true
	var stack: Array[Node] = [scenery]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			all_off = false
		for child in node.get_children():
			stack.append(child)
	_check(all_off, "%s: el escenario no proyecta sombras (solo el tablero)" % label)


func _test_scenery_eden() -> void:
	_check(is_equal_approx(SceneryEden.height_at(TerrainKit.PLATEAU_CENTER_X, 0.0), TerrainKit.PLATEAU_Y),
			"Edén: el suelo bajo el tablero está a la altura esperada")
	_check(SceneryEden.height_at(SceneryEden.river_x(20.0), 20.0) < SceneryEden.WATER_Y - 0.3, "Edén: el cauce del río queda bajo el agua")
	_check(SceneryEden.height_at(-23.0, -29.0) > 8.0, "Edén: la cima del acantilado de la cascada es alta")
	_check(SceneryEden.height_at(40.0, -50.0) > -0.3, "Edén: hay colinas lejos del tablero")
	var lowest: float = 0.0
	var highest: float = 0.0
	for gx in range(-9, 10):
		for gz in range(-9, 10):
			var h: float = SceneryEden.height_at(float(gx) * 10.0, float(gz) * 10.0)
			lowest = minf(lowest, h)
			highest = maxf(highest, h)
	_check(lowest > -2.0 and highest < 13.0, "Edén: las alturas están entre %.1f y %.1f" % [lowest, highest])
	var eden := Node3D.new()
	SceneryEden.build(eden, 12345, 1, Color(0.37, 0.63, 0.29))
	_scenery_report("Edén", eden, 90000)
	_check(eden.get_node_or_null("Terrain") != null and eden.get_node_or_null("River") != null, "Edén: tiene terreno y río")
	_check(eden.get_node_or_null("Waterfall") != null, "Edén: tiene cascada")
	_check(_count_nodes(eden, "CPUParticles3D") >= 2, "Edén: tiene polen y niebla de cascada")
	eden.free()
	var low_root := Node3D.new()
	SceneryEden.build(low_root, 12345, 0, Color(0.37, 0.63, 0.29))
	var low_triangles: int = _triangles_of(low_root)
	low_root.free()
	var high_root := Node3D.new()
	SceneryEden.build(high_root, 12345, 2, Color(0.37, 0.63, 0.29))
	var high_triangles: int = _triangles_of(high_root)
	high_root.free()
	_check(low_triangles < high_triangles, "Edén: la calidad baja usa menos triángulos que la alta (%d < %d)" % [low_triangles, high_triangles])


# ---------------------------------------------------------------- Reglas del juego

func _desert_layout() -> BoardLayout:
	return BoardLayout.from_map(MapCatalog.find_map("desierto_sinai"))


func _roster(count: int) -> Array:
	var roster: Array = []
	for i in count:
		roster.append({
			"index": i,
			"character_id": "jugador_%d" % i,
			"name": "Jugador %d" % (i + 1),
			"color": Color.WHITE,
		})
	return roster


func _test_rules() -> void:
	print("-- Reglas: dado, movimiento, escaleras y serpientes")
	var layout: BoardLayout = _desert_layout()
	_check(layout.last_tile() == 100, "la meta es la casilla 100")
	_check(layout.challenge_tiles.size() >= 15 and layout.validate().is_empty(),
			"hay casillas de desafío válidas (%d)" % layout.challenge_tiles.size())
	_check(layout.default_challenge_tiles().size() >= 10,
			"un mapa sin casillas de desafío recibe un reparto por defecto")

	var normal: Dictionary = GameRules.plan_move(layout, 10, 4)
	_check(str(normal["steps"]) == "[11, 12, 13, 14]" and int(normal["final"]) == 14
			and (normal["jump"] as Dictionary).is_empty() and not bool(normal["reached_goal"]),
			"un movimiento normal recorre las casillas una por una (10 + 4 = 14)")
	var passing: Dictionary = GameRules.plan_move(layout, 2, 4)
	_check(int(passing["final"]) == 6 and (passing["jump"] as Dictionary).is_empty(),
			"pasar por encima de una escalera no la activa (solo cuenta caer en ella)")

	var ladder_cases: int = 0
	var ladders_ok: bool = true
	for pair in layout.ladders:
		for from_tile in range(maxi(1, pair.x - 6), pair.x):
			var plan: Dictionary = GameRules.plan_move(layout, from_tile, pair.x - from_tile)
			var jump: Dictionary = plan["jump"]
			ladder_cases += 1
			if jump.is_empty() or str(jump["kind"]) != "ladder" or int(jump["from"]) != pair.x \
					or int(jump["to"]) != pair.y or int(plan["landed"]) != pair.x \
					or int(plan["final"]) != pair.y or int(plan["final"]) <= int(plan["landed"]):
				ladders_ok = false
	_check(ladders_ok and ladder_cases >= 30,
			"las 6 escaleras suben a su casilla superior desde cada tirada posible (%d casos)" % ladder_cases)

	var snake_cases: int = 0
	var snakes_ok: bool = true
	for pair in layout.snakes:
		for from_tile in range(maxi(1, pair.x - 6), pair.x):
			var plan: Dictionary = GameRules.plan_move(layout, from_tile, pair.x - from_tile)
			var jump: Dictionary = plan["jump"]
			snake_cases += 1
			if jump.is_empty() or str(jump["kind"]) != "snake" or int(jump["from"]) != pair.x \
					or int(jump["to"]) != pair.y or int(plan["landed"]) != pair.x \
					or int(plan["final"]) != pair.y or int(plan["final"]) >= int(plan["landed"]):
				snakes_ok = false
	_check(snakes_ok and snake_cases >= 36,
			"las 7 serpientes bajan a su casilla inferior desde cada tirada posible (%d casos)" % snake_cases)

	var win: Dictionary = GameRules.plan_move(layout, 97, 3)
	_check(bool(win["reached_goal"]) and int(win["final"]) == 100, "caer justo en la meta gana la partida")
	var over: Dictionary = GameRules.plan_move(layout, 99, 6)
	_check(bool(over["reached_goal"]) and int(over["final"]) == 100 and (over["steps"] as Array).size() == 1,
			"pasarse de la meta deja la ficha en la meta, nunca fuera del tablero")
	var blocked: Dictionary = GameRules.plan_move(layout, 99, 6, true)
	_check(bool(blocked["blocked"]) and int(blocked["final"]) == 99 and not bool(blocked["reached_goal"])
			and (blocked["steps"] as Array).is_empty(),
			"con tirada exacta, pasarse de la meta deja la ficha donde estaba")
	var exact: Dictionary = GameRules.plan_move(layout, 99, 1, true)
	_check(bool(exact["reached_goal"]) and not bool(exact["blocked"]), "con tirada exacta, el número justo gana")

	var inside: bool = true
	var contiguous: bool = true
	for tile in range(1, 101):
		for roll in range(1, 7):
			for exact_mode in [false, true]:
				var plan: Dictionary = GameRules.plan_move(layout, tile, roll, bool(exact_mode))
				var final_tile: int = int(plan["final"])
				var landed: int = int(plan["landed"])
				if final_tile < 1 or final_tile > 100 or landed < 1 or landed > 100:
					inside = false
				var walked: Array = plan["steps"]
				for i in walked.size():
					if int(walked[i]) != tile + 1 + i:
						contiguous = false
				if walked.size() > 6:
					contiguous = false
	_check(inside, "ninguna tirada desde ninguna casilla saca la ficha del tablero (1200 casos)")
	_check(contiguous, "el recorrido de cada tirada es continuo y de 6 casillas como máximo")

	var back: Dictionary = GameRules.plan_shift(layout, 3, -5)
	_check(int(back["to"]) == 1 and str(back["steps"]) == "[2, 1]", "retroceder nunca baja de la casilla 1")
	var ahead: Dictionary = GameRules.plan_shift(layout, 98, 5)
	_check(int(ahead["to"]) == 100 and bool(ahead["reached_goal"]), "avanzar por premio se detiene en la meta")
	var no_chain: Dictionary = GameRules.plan_shift(layout, 96, 2)
	_check(int(no_chain["to"]) == 98, "un premio que cae en una serpiente no la activa")
	_check(GameRules.stars_for(0) == 1 and GameRules.stars_for(2) == 2 and GameRules.stars_for(9) == 3,
			"las estrellas del desafío van de 1 a 3")
	var normalized: Dictionary = GameRules.normalize_options({"reward_steps": 99, "penalty_mode": -4})
	_check(int(normalized["reward_steps"]) == GameRules.MAX_SHIFT and int(normalized["penalty_mode"]) == 0,
			"las opciones de juego se corrigen si vienen fuera de rango")

	var advance_effect: Dictionary = GameRules.special_effect({"kind": "advance", "steps": 3, "name": "Prueba", "good": true}, 2)
	_check(str(advance_effect["kind"]) == "advance" and int(advance_effect["steps"]) == 3 and not bool(advance_effect["converted"]),
			"una casilla especial de avanzar avanza lo indicado")
	var skip_effect: Dictionary = GameRules.special_effect({"kind": "skip", "name": "Prueba", "good": false}, 3)
	_check(str(skip_effect["kind"]) == "skip" and not bool(skip_effect["converted"]), "con varios jugadores perder el turno se mantiene")
	var solo_effect: Dictionary = GameRules.special_effect({"kind": "skip", "name": "Prueba", "good": false}, 1)
	_check(str(solo_effect["kind"]) == "back" and int(solo_effect["steps"]) == 1 and bool(solo_effect["converted"]),
			"con un solo jugador perder el turno se convierte en retroceder 1 casilla")
	var clamped: Dictionary = GameRules.special_effect({"kind": "back", "steps": 99, "stars": 99, "name": "Prueba"}, 2)
	_check(int(clamped["steps"]) == BoardLayout.MAX_SPECIAL_STEPS and int(clamped["stars"]) == BoardLayout.MAX_SPECIAL_STARS,
			"los valores de una casilla especial se limitan a lo permitido")


func _test_match_state() -> void:
	print("-- Partida: turnos, premios, castigos y victoria")
	var layout: BoardLayout = _desert_layout()

	for count in range(1, 5):
		var state: MatchState = MatchState.create(layout, _roster(count), {"challenges": false})
		var order_ok: bool = state.player_count() == count and state.current == 0
		var rejects_intruders: bool = true
		for turn in count * 3:
			if state.current != turn % count:
				order_ok = false
			if count > 1:
				var intruder: int = (state.current + 1) % count
				if state.can_roll(intruder) or bool(state.apply_roll(intruder, 3)["ok"]):
					rejects_intruders = false
			if not state.can_roll(state.current) or not bool(state.apply_roll(state.current, 1)["ok"]):
				order_ok = false
			state.end_turn()
		_check(order_ok, "con %d jugador(es) los turnos se alternan en orden" % count)
		_check(rejects_intruders, "con %d jugador(es) no se puede tirar fuera de turno" % count)

	var first: MatchState = MatchState.create(layout, _roster(2), {"challenges": false})
	first.apply_roll(0, 1)
	_check(int(first.get_player(0)["tile"]) == 2 and int(first.get_player(1)["tile"]) == 1,
			"cada jugador tiene su propia casilla")

	var challenge_state: MatchState = MatchState.create(layout, _roster(2), {})
	challenge_state.players[0]["tile"] = 2
	var on_challenge: Dictionary = challenge_state.apply_roll(0, 3)
	_check(int(on_challenge["final"]) == 5 and bool(on_challenge["challenge"]),
			"caer en una casilla de desafío (la 5) lo plantea")
	var off_challenge: MatchState = MatchState.create(layout, _roster(2), {"challenges": false})
	off_challenge.players[0]["tile"] = 2
	_check(not bool(off_challenge.apply_roll(0, 3)["challenge"]), "con los desafíos desactivados no se plantea ninguno")
	var on_ladder: MatchState = MatchState.create(layout, _roster(2), {})
	_check(not bool(on_ladder.apply_roll(0, 2)["challenge"]) and int(on_ladder.get_player(0)["tile"]) == 22,
			"una escalera no plantea desafío")

	var reward: MatchState = MatchState.create(layout, _roster(2), {"reward_mode": GameRules.REWARD_ADVANCE, "reward_steps": 3})
	reward.players[0]["tile"] = 10
	var good: Dictionary = reward.apply_challenge_result(0, true, 2)
	_check(bool(good["correct"]) and int(good["stars"]) == 2 and int(reward.get_player(0)["tile"]) == 13
			and int(reward.get_player(0)["stars"]) == 2, "acertar da estrellas y avanza las casillas de premio")
	var extra: MatchState = MatchState.create(layout, _roster(3), {"reward_mode": GameRules.REWARD_EXTRA_ROLL})
	extra.apply_challenge_result(0, true, 1)
	var repeat: Dictionary = extra.end_turn()
	_check(bool(repeat["extra"]) and int(repeat["next"]) == 0 and extra.current == 0,
			"el premio de tirada extra repite el turno del mismo jugador")
	_check(int(extra.end_turn()["next"]) == 1, "después de la tirada extra el turno sigue su orden")
	var stars_only: MatchState = MatchState.create(layout, _roster(2), {"reward_mode": GameRules.REWARD_STARS_ONLY})
	stars_only.players[0]["tile"] = 20
	stars_only.apply_challenge_result(0, true, 3)
	_check(int(stars_only.get_player(0)["tile"]) == 20 and int(stars_only.get_player(0)["stars"]) == 3,
			"el premio de solo estrellas no mueve la ficha")

	var penalty: MatchState = MatchState.create(layout, _roster(2), {"penalty_mode": GameRules.PENALTY_BACK, "penalty_steps": 3})
	penalty.players[0]["tile"] = 20
	var bad: Dictionary = penalty.apply_challenge_result(0, false, 3)
	_check(not bool(bad["correct"]) and int(bad["stars"]) == 0 and int(penalty.get_player(0)["tile"]) == 17,
			"fallar retrocede las casillas configuradas y no da estrellas")
	var near_start: MatchState = MatchState.create(layout, _roster(2), {"penalty_mode": GameRules.PENALTY_BACK, "penalty_steps": 4})
	near_start.players[0]["tile"] = 3
	near_start.apply_challenge_result(0, false, 1)
	_check(int(near_start.get_player(0)["tile"]) == 1, "el castigo nunca manda la ficha antes de la casilla 1")
	var none_state: MatchState = MatchState.create(layout, _roster(2), {"penalty_mode": GameRules.PENALTY_NONE})
	none_state.players[0]["tile"] = 30
	none_state.apply_challenge_result(0, false, 1)
	_check(int(none_state.get_player(0)["tile"]) == 30 and not bool(none_state.get_player(0)["skip_next"]),
			"con castigo desactivado fallar no cambia nada")

	var skip: MatchState = MatchState.create(layout, _roster(3), {"penalty_mode": GameRules.PENALTY_SKIP_TURN})
	skip.apply_challenge_result(0, false, 1)
	var sequence: Array[int] = []
	for turn_index in 3:
		var step: Dictionary = skip.end_turn()
		sequence.append(int(step["next"]))
		if turn_index == 2:
			_check(str(step["skipped"]) == "[0]", "el jugador castigado aparece como turno perdido")
	_check(str(sequence) == "[1, 2, 1]", "perder el turno salta al jugador castigado una sola vez (%s)" % str(sequence))
	var solo_skip: MatchState = MatchState.create(layout, _roster(1), {"penalty_mode": GameRules.PENALTY_SKIP_TURN})
	solo_skip.apply_challenge_result(0, false, 1)
	_check(not bool(solo_skip.get_player(0)["skip_next"]), "con un solo jugador perder el turno no se marca")

	var win: MatchState = MatchState.create(layout, _roster(3), {"challenges": false})
	win.players[0]["tile"] = 97
	var finishing: Dictionary = win.apply_roll(0, 3)
	_check(win.finished and win.winner == 0 and bool(finishing["reached_goal"]), "el primero que llega a la meta gana")
	_check(not bool(win.apply_roll(1, 2)["ok"]), "después de la victoria nadie más puede tirar")
	_check(bool(win.end_turn()["finished"]) and win.current == 0, "después de la victoria el turno no avanza")
	var summary: Dictionary = win.summary()
	_check(str(summary["winner_name"]) == "Jugador 1" and int(summary["winner"]) == 0 and bool(summary["finished"]),
			"el resumen indica quién ganó")
	_check((summary["players"] as Array).size() == 3 and int((summary["players"] as Array)[0]["rank"]) == 1
			and bool((summary["players"] as Array)[0]["winner"]), "el resumen ordena a los jugadores con el ganador primero")
	var reward_win: MatchState = MatchState.create(layout, _roster(2), {"reward_mode": GameRules.REWARD_ADVANCE, "reward_steps": 4})
	reward_win.players[0]["tile"] = 97
	var bonus_win: Dictionary = reward_win.apply_challenge_result(0, true, 1)
	_check(reward_win.finished and bool(bonus_win["reached_goal"]), "llegar a la meta con un premio también gana")

	var tied: MatchState = MatchState.create(layout, _roster(3), {})
	tied.players[0]["tile"] = 40
	tied.players[1]["tile"] = 60
	tied.players[2]["tile"] = 60
	tied.players[2]["stars"] = 5
	_check(str(tied.ranking()) == "[2, 1, 0]", "sin ganador, el orden sale por casilla y luego por estrellas")

	var exact_state: MatchState = MatchState.create(layout, _roster(2), {"exact_finish": true, "challenges": false})
	exact_state.players[0]["tile"] = 98
	var overshoot: Dictionary = exact_state.apply_roll(0, 5)
	_check(bool(overshoot["blocked"]) and int(exact_state.get_player(0)["tile"]) == 98 and not exact_state.finished,
			"con tirada exacta la ficha espera el número justo")


## Casillas especiales: solo actúan al caer en ellas y cada tipo hace lo que dice, en los 7 mapas.
func _test_special_tiles() -> void:
	print("-- Casillas especiales: recompensas y obstáculos")
	var desert: BoardLayout = _desert_layout()
	var landing: MatchState = MatchState.create(desert, _roster(2), {"challenges": false})
	landing.players[0]["tile"] = 16
	var on_special: Dictionary = landing.apply_roll(0, 1)
	_check(int(on_special["final"]) == 17 and str((on_special["special"] as Dictionary)["kind"]) == "advance" and not bool(on_special["challenge"]),
			"caer en la casilla 17 activa su recompensa")
	var passing: MatchState = MatchState.create(desert, _roster(2), {"challenges": false})
	passing.players[0]["tile"] = 14
	_check((passing.apply_roll(0, 4)["special"] as Dictionary).is_empty(), "pasar por encima de una casilla especial no la activa")
	var plain: MatchState = MatchState.create(desert, _roster(2), {"challenges": false})
	_check((plain.apply_roll(0, 1)["special"] as Dictionary).is_empty(), "una casilla normal no activa nada")
	var nothing: MatchState = MatchState.create(desert, _roster(2), {})
	_check(not bool(nothing.apply_special(0)["ok"]), "sin casilla especial en la casilla actual no pasa nada")
	nothing.players[0]["tile"] = 17
	_check(not bool(nothing.apply_special(1)["ok"]), "solo el jugador que tiene el turno recibe el efecto")
	_check(bool(nothing.apply_special(0)["ok"]), "el jugador en turno sí recibe el efecto")

	var no_chain: bool = true
	var kinds_seen: Dictionary = {}
	var failures: Array[String] = []
	var effects_checked: int = 0
	for map_id in MAP_ORDER:
		var layout: BoardLayout = BoardLayout.from_map(MapCatalog.find_map(map_id))
		# Las escaleras y las serpientes no activan casillas especiales (no hay cadenas).
		for pair in layout.ladders:
			var ladder_state: MatchState = MatchState.create(layout, _roster(2), {"challenges": false})
			ladder_state.players[0]["tile"] = pair.x - 1
			var ladder_plan: Dictionary = ladder_state.apply_roll(0, 1)
			if (ladder_plan["jump"] as Dictionary).is_empty() or not (ladder_plan["special"] as Dictionary).is_empty():
				no_chain = false
		for pair in layout.snakes:
			var snake_state: MatchState = MatchState.create(layout, _roster(2), {"challenges": false})
			snake_state.players[0]["tile"] = pair.x - 1
			var snake_plan: Dictionary = snake_state.apply_roll(0, 1)
			if (snake_plan["jump"] as Dictionary).is_empty() or not (snake_plan["special"] as Dictionary).is_empty():
				no_chain = false
		for tile in layout.special_tiles():
			var special: Dictionary = layout.special_at(tile)
			kinds_seen[str(special["kind"])] = true
			for count in [1, 2]:
				var state: MatchState = MatchState.create(layout, _roster(count), {"challenges": false})
				state.players[0]["tile"] = tile
				var result: Dictionary = state.apply_special(0)
				var info: Dictionary = state.get_player(0)
				var stats: Dictionary = info["stats"]
				var effect: Dictionary = GameRules.special_effect(special, count)
				var label: String = "%s casilla %d (%d jugador/es)" % [map_id, tile, count]
				var ok: bool = bool(result["ok"]) and str(result["kind"]) == str(effect["kind"]) \
						and int(stats["specials"]) == 1 and bool(result["good"]) == bool(special["good"]) \
						and int(stats["special_rewards" if bool(special["good"]) else "special_obstacles"]) == 1
				match str(effect["kind"]):
					"advance":
						ok = ok and int(info["tile"]) == tile + int(special["steps"]) and not bool(result["extra_roll"])
					"back":
						ok = ok and int(info["tile"]) == maxi(1, tile - int(effect["steps"]))
					"stars":
						ok = ok and int(info["stars"]) == int(special["stars"]) and int(stats["special_stars"]) == int(special["stars"]) \
								and int(info["tile"]) == tile
					"extra_roll":
						var again: Dictionary = state.end_turn()
						ok = ok and bool(result["extra_roll"]) and bool(again["extra"]) and state.current == 0 and int(info["tile"]) == tile
					"skip":
						ok = ok and bool(info["skip_next"]) and bool(result["skip_next"]) and int(info["tile"]) == tile
					_:
						ok = false
				if not ok:
					failures.append(label)
				effects_checked += 1
	_check(failures.is_empty(), "cada casilla especial de los 7 mapas hace lo que dice (%d comprobaciones) %s" % [effects_checked, str(failures.slice(0, 3))])
	_check(no_chain, "caer por una escalera o una serpiente no activa casillas especiales")
	_check(kinds_seen.size() == 5, "los mapas usan los 5 tipos de casilla especial (%s)" % str(kinds_seen.keys()))

	var solo: MatchState = MatchState.create(desert, _roster(1), {"challenges": false})
	solo.players[0]["tile"] = 74
	var solo_result: Dictionary = solo.apply_special(0)
	_check(str(solo_result["kind"]) == "back" and bool(solo_result["converted"]) and int(solo.get_player(0)["tile"]) == 73
			and not bool(solo.get_player(0)["skip_next"]), "con un solo jugador la casilla de perder turno retrocede 1 casilla")
	var skipper: MatchState = MatchState.create(desert, _roster(3), {"challenges": false})
	skipper.players[0]["tile"] = 74
	skipper.apply_special(0)
	var order: Array[int] = []
	for _turn in 3:
		order.append(int(skipper.end_turn()["next"]))
	_check(str(order) == "[1, 2, 1]", "la casilla de perder turno salta al jugador una sola vez (%s)" % str(order))


func _test_simulated_games() -> void:
	print("-- Partidas simuladas completas en los 7 tableros")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261107
	var games: int = 120
	var winners: Dictionary = {}
	var longest: int = 0
	for map_id in MAP_ORDER:
		var layout: BoardLayout = BoardLayout.from_map(MapCatalog.find_map(map_id))
		var completed: int = 0
		var invariants: bool = true
		var shortest: int = 1 << 30
		var ladder_hits: Dictionary = {}
		var snake_hits: Dictionary = {}
		var special_hits: Dictionary = {}
		var special_kinds: Dictionary = {}
		var challenges_seen: int = 0
		var total_rolls: int = 0
		for _game in games:
			var count: int = rng.randi_range(1, 4)
			var options: Dictionary = {
				"challenges": rng.randf() < 0.85,
				"reward_mode": rng.randi_range(0, 2),
				"reward_steps": rng.randi_range(1, 4),
				"penalty_mode": rng.randi_range(0, 2),
				"penalty_steps": rng.randi_range(1, 4),
				"exact_finish": rng.randf() < 0.3,
			}
			var state: MatchState = MatchState.create(layout, _roster(count), options)
			var guard: int = 0
			var rolls: int = 0
			while not state.finished and guard < 5000:
				guard += 1
				var who: int = state.current
				var plan: Dictionary = state.apply_roll(who, rng.randi_range(1, 6))
				rolls += 1
				if not bool(plan["ok"]):
					invariants = false
					break
				var jump: Dictionary = plan["jump"]
				if not jump.is_empty():
					if str(jump["kind"]) == "ladder":
						ladder_hits[int(jump["from"])] = true
					else:
						snake_hits[int(jump["from"])] = true
				if bool(plan["challenge"]) and not state.finished:
					challenges_seen += 1
					var answered: Dictionary = state.apply_challenge_result(who, rng.randf() < 0.6, rng.randi_range(1, 3))
					if not bool(answered["ok"]):
						invariants = false
				elif not (plan["special"] as Dictionary).is_empty() and not state.finished:
					var special: Dictionary = plan["special"]
					var applied: Dictionary = state.apply_special(who)
					if not bool(applied["ok"]):
						invariants = false
					else:
						special_hits[int(special["tile"])] = true
						special_kinds[str(special["kind"])] = true
				for info in state.players:
					var tile: int = int(info["tile"])
					if tile < 1 or tile > 100:
						invariants = false
				if not state.finished:
					state.end_turn()
			total_rolls += rolls
			if state.finished:
				completed += 1
				longest = maxi(longest, rolls)
				shortest = mini(shortest, rolls)
				winners[state.winner] = int(winners.get(state.winner, 0)) + 1
				var champion: Dictionary = state.get_player(state.winner)
				if int(champion["tile"]) != 100:
					invariants = false
				var finished_players: int = 0
				for info in state.players:
					if bool(info["finished"]):
						finished_players += 1
				if finished_players != 1:
					invariants = false
		_check(completed == games, "%s: las %d partidas simuladas terminan con un ganador (%d)" % [map_id, games, completed])
		_check(invariants, "%s: casillas dentro del tablero, un solo ganador en la casilla 100 y turnos válidos" % map_id)
		_check(ladder_hits.size() == layout.ladders.size() and snake_hits.size() == layout.snakes.size(),
				"%s: se usaron sus %d escaleras y sus %d serpientes (%d y %d)" % [map_id, layout.ladders.size(), layout.snakes.size(), ladder_hits.size(), snake_hits.size()])
		_check(special_hits.size() >= 7 and special_kinds.size() >= _kind_count(layout) - 1,
				"%s: se activaron sus casillas especiales (%d de 8, %d tipos)" % [map_id, special_hits.size(), special_kinds.size()])
		_check(challenges_seen > 60, "%s: se plantearon desafíos (%d)" % [map_id, challenges_seen])
		var average_rolls: float = float(total_rolls) / float(games)
		_check(shortest >= 6 and average_rolls >= 20.0 and average_rolls <= 600.0,
				"%s: la duración de las partidas es razonable (media %.0f tiradas, la más corta %d)" % [map_id, average_rolls, shortest])
	_check(winners.size() >= 2, "ganan jugadores distintos según la suerte (%s)" % str(winners))
	print("      (la partida más larga tuvo %d tiradas)" % longest)


## Cuántos tipos distintos de casilla especial tiene un tablero.
func _kind_count(layout: BoardLayout) -> int:
	var kinds: Dictionary = {}
	for info in layout.special_list:
		kinds[str(info["kind"])] = true
	return kinds.size()


func _fake_summary(duration: float, turns: int, correct: int, stars_first: int, stars_second: int) -> Dictionary:
	return {
		"finished": true, "winner": 0, "winner_name": "Jugador 1", "turns": turns, "duration": duration,
		"total_rolls": turns * 2, "total_challenges": correct + 2, "total_correct": correct,
		"players": [
			{"index": 0, "name": "Jugador 1", "tile": 100, "stars": stars_first, "rank": 1, "winner": true,
				"stats": {"rolls": turns, "ladders": 2, "snakes": 1, "specials": 3}},
			{"index": 1, "name": "Jugador 2", "tile": 60, "stars": stars_second, "rank": 2, "winner": false,
				"stats": {"rolls": turns, "ladders": 1, "snakes": 2, "specials": 1}},
		],
		"options": {},
	}


## Progreso: mapas bloqueados y abiertos, recompensas, insignias, estadísticas y guardado.
func _test_progress() -> void:
	print("-- Progreso: desbloqueo, recompensas, insignias, estadísticas y guardado")
	var data: ProgressData = ProgressData.new_game()
	_check(data.is_unlocked("eden") and data.status_of("eden") == "available", "el primer mapa está disponible desde el comienzo")
	var locked_ok: bool = true
	for i in range(1, MAP_ORDER.size()):
		if data.is_unlocked(MAP_ORDER[i]) or data.status_of(MAP_ORDER[i]) != "locked":
			locked_ok = false
	_check(locked_ok and data.unlocked_count() == 1 and data.completed_count() == 0 and data.map_total() == 7,
			"los otros 6 mapas empiezan bloqueados")
	_check(data.completion_ratio() == 0.0 and data.badge_counts() == Vector2i(0, 11) and data.all_badges().size() == 11,
			"empieza sin avance y con 11 insignias por ganar (7 de mapa y 4 generales)")
	data.record_start("eden")
	data.record_start("mapa_que_no_existe")
	_check(int(data.region("eden")["plays"]) == 1 and not data.regions.has("mapa_que_no_existe"), "se cuentan las partidas empezadas de un mapa que existe")
	var unfinished: Dictionary = data.record_match("eden", {"finished": false})
	_check(not bool(unfinished["ok"]) and not data.is_completed("eden"), "una partida sin terminar no completa el mapa")
	_check(not bool(data.record_match("mapa_que_no_existe", _fake_summary(100.0, 10, 1, 1, 1))["ok"]), "un mapa que no existe no se anota")

	var journey: int = 0
	var chain_ok: bool = true
	var chain_notes: Array[String] = []
	for i in MAP_ORDER.size():
		var map_id: String = MAP_ORDER[i]
		var report: Dictionary = data.record_match(map_id, _fake_summary(300.0 - float(i), 30 + i, 6, 9, 4))
		journey += MapCatalog.reward_stars_of(map_id)
		var expected_unlocks: Array = [MAP_ORDER[i + 1]] if i + 1 < MAP_ORDER.size() else []
		var badge: Dictionary = report["badge"]
		if not bool(report["ok"]) or not bool(report["first_completion"]) or int(report["reward_stars"]) != MapCatalog.reward_stars_of(map_id) \
				or str(badge.get("id", "")) != str(MapCatalog.badge_of(map_id)["id"]) or str(report["unlocked_maps"]) != str(expected_unlocks) \
				or int(report["journey_stars"]) != journey or int(report["completed"]) != i + 1 or int(report["total"]) != 7:
			chain_ok = false
			chain_notes.append(map_id)
		if data.status_of(map_id) != "completed" or not data.has_badge(str(badge.get("id", ""))):
			chain_ok = false
		if i + 2 < MAP_ORDER.size() and data.is_unlocked(MAP_ORDER[i + 2]):
			chain_ok = false
			chain_notes.append("%s abrió dos mapas" % map_id)
		if i == 1:
			_check(not data.has_badge("viajero"), "con 2 mapas completados aún no se gana la insignia Viajero")
		if i == 2:
			_check(data.has_badge("viajero") and report["new_badges"].size() == 2, "al completar el tercer mapa se gana Viajero junto con la insignia del mapa")
		if i == 3:
			_check(not data.has_badge("sabio") and not data.has_badge("coleccionista"), "con 24 aciertos y 52 estrellas aún no se ganan Sabio ni Coleccionista")
		if i == 4:
			_check(data.has_badge("sabio") and data.has_badge("coleccionista"), "con 30 aciertos y 65 estrellas se ganan Sabio y Coleccionista")
	_check(chain_ok, "los 7 mapas se completan en orden: cada uno da su recompensa, su insignia y abre el siguiente %s" % str(chain_notes))
	_check(data.has_badge("peregrino") and data.completed_count() == 7 and data.completion_ratio() == 1.0 and data.journey_stars == journey,
			"al completar los 7 mundos se gana la insignia Peregrino (estrellas del viaje: %d)" % data.journey_stars)
	_check(data.badge_counts() == Vector2i(11, 11), "se ganan las 11 insignias")
	var eden_stats: Dictionary = data.region("eden")
	_check(int(eden_stats["plays"]) == 1 and int(eden_stats["completions"]) == 1 and float(eden_stats["best_time"]) == 300.0 \
			and int(eden_stats["best_turns"]) == 30 and int(eden_stats["correct"]) == 6 and int(eden_stats["challenges"]) == 8 \
			and int(eden_stats["stars"]) == 13 and int(eden_stats["best_stars"]) == 9 and int(eden_stats["ladders"]) == 3 \
			and int(eden_stats["snakes"]) == 3 and int(eden_stats["specials"]) == 4, "las estadísticas de la región suman la partida %s" % str(eden_stats))
	var again: Dictionary = data.record_match("eden", _fake_summary(200.0, 25, 3, 2, 1))
	_check(bool(again["ok"]) and not bool(again["first_completion"]) and int(again["reward_stars"]) == 0 and (again["badge"] as Dictionary).is_empty()
			and (again["unlocked_maps"] as Array).is_empty() and data.journey_stars == journey, "repetir un mapa no repite la recompensa")
	var better: Dictionary = data.region("eden")
	_check(int(better["completions"]) == 2 and float(better["best_time"]) == 200.0 and int(better["best_turns"]) == 25 and int(better["best_stars"]) == 9,
			"se guarda el mejor tiempo y los mejores turnos de la región")
	data.record_match("eden", _fake_summary(900.0, 90, 0, 0, 0))
	_check(float(data.region("eden")["best_time"]) == 200.0 and int(data.region("eden")["best_turns"]) == 25, "una partida peor no cambia los récords")

	var copy: ProgressData = ProgressData.from_dict(data.to_dict())
	_check(copy.unlocked == data.unlocked and copy.completed == data.completed and copy.badges == data.badges
			and copy.journey_stars == data.journey_stars and copy.regions == data.regions, "el progreso se guarda y se vuelve a leer igual")
	var damaged: ProgressData = ProgressData.from_dict({"unlocked": "mal", "completed": [5, ""], "badges": 7, "regions": {"eden": 3, "arca_noe": {"plays": -4, "best_time": -1.0}}, "journey_stars": -9})
	_check(damaged.journey_stars == 0 and damaged.is_unlocked("eden") and int(damaged.region("arca_noe")["plays"]) == 0 and float(damaged.region("arca_noe")["best_time"]) == 0.0,
			"un archivo dañado no rompe el progreso")
	_check(ProgressData.from_dict({"completed": ["eden"]}).is_unlocked("arca_noe"), "completar un mapa deja abierto el siguiente aunque el archivo no lo diga")
	var everything: ProgressData = ProgressData.new_game()
	everything.unlock_everything()
	_check(everything.unlocked_count() == 7 and everything.completed_count() == 0, "abrir todos los mapas no los marca como completados")

	# El gestor guarda en un archivo de prueba y recupera el progreso al "reiniciar".
	_progress.reset(false)
	_check(_state.can_select_map("eden") and not _state.can_select_map("arca_noe") and not _state.can_select_map("belen"),
			"el jugador solo puede elegir el mapa que tiene abierto")
	_check(not _state.select_map("arca_noe") and str(_state.selected_map_id) == "eden", "elegir un mapa bloqueado no cambia la selección")
	_state.selected_map_id = "belen"
	_state.ensure_valid_selection()
	_check(str(_state.selected_map_id) == "eden", "si la selección apunta a un mapa bloqueado vuelve al primero")
	_progress.record_start("eden")
	var manager_report: Dictionary = _progress.record_match("eden", _fake_summary(250.0, 28, 5, 6, 3))
	_check(bool(manager_report["ok"]) and bool(manager_report["first_completion"]) and _progress.is_completed("eden") and _progress.is_unlocked("arca_noe"),
			"el gestor anota el mapa completado y abre el siguiente")
	_check(FileAccess.file_exists(TEST_PROGRESS_PATH), "el progreso se guarda en un archivo del teléfono")
	_check(_state.select_map("arca_noe") and str(_state.selected_map_id) == "arca_noe", "al completar un mapa se puede elegir el siguiente")
	_progress.unlock_everything_for_session()
	_check(_progress.is_unlocked("belen"), "se pueden abrir todos los mapas solo en esta sesión")
	_progress.load_progress()
	_check(_progress.is_completed("eden") and _progress.is_unlocked("arca_noe") and not _progress.is_unlocked("belen")
			and int(_progress.region("eden")["plays"]) == 1 and int(_progress.region("eden")["completions"]) == 1,
			"al volver a abrir el juego el progreso sigue ahí y los mapas abiertos de prueba no se guardaron")
	var broken_file := FileAccess.open(TEST_PROGRESS_PATH, FileAccess.WRITE)
	if broken_file != null:
		broken_file.store_string("esto no es un archivo de progreso ][")
		broken_file.close()
	_progress.load_progress()
	_check(_progress.is_unlocked("eden") and not _progress.is_completed("eden"), "un archivo de progreso dañado empieza una partida nueva sin fallar")
	_progress.reset(false)
	_state.selected_map_id = "eden"

# ---------------------------------------------------------------- Referencias y desafíos

func _test_bible_references() -> void:
	print("-- Referencias bíblicas")
	_check(BibleReference.BOOKS.size() == 66, "la lista tiene los 66 libros")
	_check(BibleReference.total_chapters() == 1189, "los libros suman 1189 capítulos (%d)" % BibleReference.total_chapters())
	_check(BibleReference.chapters_of("Salmos") == 150 and BibleReference.chapters_of("Salmo") == 150,
			"Salmos tiene 150 capítulos (también como 'Salmo')")
	_check(BibleReference.chapters_of("Genesis") == 50, "los libros se reconocen sin tildes")
	_check(BibleReference.chapters_of("Judas") == 1 and BibleReference.chapters_of("Apocalipsis") == 22,
			"Judas tiene 1 capítulo y Apocalipsis 22")
	for good in ["Génesis 7:12", "Éxodo 14:21-22", "Éxodo 19-20", "Josué 3", "1 Samuel 17:48-50",
			"Salmo 23:1", "Salmos 119:176", "Mateo 2:1; Lucas 2:4-7", "2 Samuel 5; 1 Reyes 6", "Judas 1:25"]:
		_check(BibleReference.is_valid(good), "referencia válida: %s" % good)
	for bad in ["", "Génesis", "Génesis 51:1", "Foo 1:1", "Juan 3:0", "Salmos 151", "Judas 2",
			"Mateo 5:9-3", "Juan 3:16-", "Éxodo 20-19", "Juan x:1", "Lucas 2:4; Pedro 3:1"]:
		_check(not BibleReference.is_valid(bad), "referencia inválida detectada: '%s'" % bad)
	var parsed: Dictionary = BibleReference.parse("Mateo 2:1; Lucas 2:4-7")
	_check((parsed["parts"] as Array).size() == 2 and str((parsed["parts"] as Array)[1]["book"]) == "Lucas"
			and int((parsed["parts"] as Array)[1]["verse_to"]) == 7, "una referencia con dos partes se separa bien")
	for entry in MapCatalog.all_maps():
		var map_data: Dictionary = entry
		_check(BibleReference.is_valid(str(map_data["reference"])), "la referencia del mapa '%s' es válida (%s)" % [map_data["id"], map_data["reference"]])


func _test_challenge_bank() -> void:
	print("-- Desafíos bíblicos")
	var problems: PackedStringArray = ChallengeBank.load_problems()
	_check(problems.is_empty(), "todos los desafíos del banco son válidos %s" % str(problems))
	var counts: Dictionary = ChallengeBank.count_by_type()
	_check(ChallengeBank.all().size() >= 240, "el banco tiene 240 desafíos o más (%d)" % ChallengeBank.all().size())
	for type in Challenge.TYPES:
		_check(int(counts[type]) >= 10, "hay 10 o más desafíos de tipo %s (%d)" % [type, counts[type]])

	var prompts: Dictionary = {}
	var difficulties: Dictionary = {}
	var clean: bool = true
	for item in ChallengeBank.all():
		var key: String = item.prompt if item.type != Challenge.TYPE_CHARACTER else "|".join(item.clues)
		if prompts.has(key):
			clean = false
		prompts[key] = true
		difficulties[item.difficulty] = true
		if item.prompt.length() > 220 or item.explanation.length() > 220:
			clean = false
		for option in item.options:
			if option.length() > 60:
				clean = false
		if item.type == Challenge.TYPE_CHARACTER:
			var folded_clues: String = " " + _letters_only(" ".join(item.clues)) + " "
			var answer: String = " " + _letters_only(item.correct_text()) + " "
			if folded_clues.contains(answer):
				clean = false
		if item.type == Challenge.TYPE_COMPLETE_VERSE:
			var from_verse: Dictionary = BibleReference.parse(VerseProvider.reference_of(item.verse_id))
			var from_item: Dictionary = BibleReference.parse(item.reference)
			if not bool(from_verse["ok"]) or not bool(from_item["ok"]) \
					or str((from_verse["parts"] as Array)[0]["book"]) != str((from_item["parts"] as Array)[0]["book"]) \
					or int((from_verse["parts"] as Array)[0]["chapter"]) != int((from_item["parts"] as Array)[0]["chapter"]) \
					or int((from_verse["parts"] as Array)[0]["verse"]) != int((from_item["parts"] as Array)[0]["verse"]):
				clean = false
	_check(clean, "no hay enunciados repetidos, textos demasiado largos, pistas que revelen el personaje ni versículos mal enlazados")
	_check(difficulties.size() == 3, "hay desafíos de las tres dificultades")

	var tf_correct: Dictionary = {}
	for item in ChallengeBank.by_type(Challenge.TYPE_TRUE_FALSE):
		tf_correct[item.correct] = int(tf_correct.get(item.correct, 0)) + 1
		if item.options.size() != 2 or item.options[0] != "Verdadero" or item.options[1] != "Falso":
			tf_correct["mal"] = 1
	_check(tf_correct.size() == 2 and int(tf_correct[0]) >= 6 and int(tf_correct[1]) >= 6,
			"verdadero o falso tiene afirmaciones verdaderas y falsas (%s)" % str(tf_correct))

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var shuffle_ok: bool = true
	for item in ChallengeBank.all():
		for _round in 5:
			var mixed: Challenge = item.shuffled(rng)
			if mixed.correct_text() != item.correct_text() or mixed.options.size() != item.options.size():
				shuffle_ok = false
			var sorted_a: Array = Array(item.options)
			var sorted_b: Array = Array(mixed.options)
			sorted_a.sort()
			sorted_b.sort()
			if sorted_a != sorted_b:
				shuffle_ok = false
			if item.type == Challenge.TYPE_TRUE_FALSE and mixed.correct != item.correct:
				shuffle_ok = false
	_check(shuffle_ok, "mezclar las opciones conserva cuál es la respuesta correcta")

	# Cada mapa tiene sus propios desafíos bíblicos (20: 4 de cada tipo) además de los generales.
	var general_total: int = 0
	for type in Challenge.TYPES:
		general_total += ChallengeBank.general_by_type(type).size()
	_check(general_total >= 100, "se conservan los desafíos generales de la etapa anterior (%d)" % general_total)
	for map_id in MAP_ORDER:
		var own: Array[Challenge] = ChallengeBank.for_map(map_id)
		var per_type: Dictionary = ChallengeBank.count_for_map(map_id)
		var even: bool = true
		for type in Challenge.TYPES:
			if int(per_type[type]) != 4:
				even = false
		_check(own.size() == 20 and even, "%s: tiene 20 desafíos propios, 4 de cada tipo %s" % [map_id, str(per_type)])
		var tagged: bool = true
		var verses_ok: bool = true
		for item in own:
			if item.map_id != map_id or not item.problems().is_empty():
				tagged = false
			if item.type == Challenge.TYPE_COMPLETE_VERSE:
				var verse_entry: Dictionary = VerseProvider.references().get(item.verse_id, {})
				if str(verse_entry.get("map", "")) != map_id:
					verses_ok = false
		_check(tagged and verses_ok, "%s: sus desafíos son válidos, llevan la etiqueta del mapa y sus versículos están enlazados" % map_id)
	_check(ChallengeBank.for_map("").is_empty() and ChallengeBank.for_map("mapa_que_no_existe").is_empty(), "un mapa sin desafíos propios no devuelve ninguno")
	var general_item: Challenge = Challenge.from_dict({"id": "x", "type": "true_false", "map": "general", "correct": true})
	var mapped_item: Challenge = Challenge.from_dict({"id": "y", "type": "true_false", "map": "belen", "correct": true})
	var ghost_item: Challenge = Challenge.from_dict({"id": "z", "type": "true_false", "map": "no_existe", "prompt": "p",
			"explanation": "e", "reference": "Juan 3:16", "correct": true})
	_check(general_item.map_id == "" and mapped_item.map_id == "belen" and mapped_item.shuffled(rng).map_id == "belen",
			"la etiqueta 'general' vale para todos los mapas y la de un mapa se conserva al mezclar")
	_check(" ".join(ghost_item.problems()).contains("no existe"), "un desafío de un mapa que no existe se detecta")

	var deck_a := ChallengeDeck.new(4242)
	var deck_b := ChallengeDeck.new(4242)
	var same_sequence: bool = true
	var all_types_per_block: bool = true
	var block: Dictionary = {}
	var seen_in_type: Dictionary = {}
	var repeats: bool = false
	for n in 60:
		var drawn_a: Challenge = deck_a.draw()
		var drawn_b: Challenge = deck_b.draw()
		if drawn_a == null or drawn_b == null or drawn_a.id != drawn_b.id:
			same_sequence = false
			continue
		block[drawn_a.type] = true
		if (n + 1) % 5 == 0:
			if block.size() != 5:
				all_types_per_block = false
			block.clear()
		if seen_in_type.has(drawn_a.id):
			repeats = true
		seen_in_type[drawn_a.id] = true
	_check(same_sequence, "con la misma semilla el mazo reparte los mismos desafíos")
	_check(all_types_per_block, "cada 5 desafíos salen los cinco tipos")
	_check(not repeats, "el mazo no repite desafíos mientras quedan sin salir (60 sacados)")
	var forced: Challenge = ChallengeDeck.new(7).draw(Challenge.TYPE_EVENT)
	_check(forced != null and forced.type == Challenge.TYPE_EVENT, "se puede pedir un tipo concreto de desafío")
	for map_id in MAP_ORDER:
		var map_deck := ChallengeDeck.new(2026, map_id)
		var first_ids: Dictionary = {}
		var own_first: bool = true
		var foreign: bool = false
		for n in 100:
			var drawn: Challenge = map_deck.draw()
			if drawn == null:
				foreign = true
				continue
			if n < 20:
				first_ids[drawn.id] = true
				if drawn.map_id != map_id:
					own_first = false
			if not drawn.map_id.is_empty() and drawn.map_id != map_id:
				foreign = true
		_check(first_ids.size() == 20 and own_first, "%s: los primeros 20 desafíos de una partida son los propios del mapa, sin repetir" % map_id)
		_check(not foreign, "%s: el mazo nunca saca desafíos de otro mapa (100 sacados)" % map_id)
	var typed_map_deck := ChallengeDeck.new(5, "belen")
	var typed_pick: Challenge = typed_map_deck.draw(Challenge.TYPE_COMPLETE_VERSE)
	_check(typed_pick != null and typed_pick.type == Challenge.TYPE_COMPLETE_VERSE and typed_pick.map_id == "belen",
			"se puede pedir un tipo concreto dentro de un mapa y sale uno de ese mapa")

	# El texto bíblico solo aparece si hay una versión autorizada; hoy no la hay.
	_check(VerseProvider.active_translation().is_empty(), "ninguna versión con derechos está activa (RVR1960 requiere autorización)")
	_check(VerseProvider.text_of("sal_23_1").is_empty() and VerseProvider.attribution().is_empty(),
			"sin autorización el juego no muestra texto bíblico")
	var rvr: Dictionary = {}
	for entry in VerseProvider.translations():
		if str((entry as Dictionary).get("id", "")) == "rvr1960":
			rvr = entry
	_check(not rvr.is_empty() and str(rvr["status"]) == "requires_authorization" and not bool(rvr["enabled"]),
			"RVR1960 está preparada en la estructura pero desactivada")
	VerseProvider.use_test_translation({"sal_23_1": "texto de prueba"})
	_check(VerseProvider.text_of("sal_23_1") == "texto de prueba" and not VerseProvider.attribution().is_empty(),
			"la estructura muestra el texto cuando una versión está activa (versión falsa de prueba)")
	VerseProvider.clear_test_translation()
	_check(VerseProvider.text_of("sal_23_1").is_empty(), "al quitar la versión de prueba vuelve a no haber texto")

	for category in MessageBank.CATEGORIES:
		var messages: PackedStringArray = MessageBank.all_in(category)
		var short_enough: bool = true
		for text in messages:
			if text.strip_edges().is_empty() or text.length() > 80:
				short_enough = false
		_check(messages.size() >= 2 and short_enough, "mensajes motivadores de '%s' (%d)" % [category, messages.size()])
	var verse_ok: bool = true
	for entry in VerseProvider.references().values():
		var verse: Dictionary = entry
		if not BibleReference.is_valid(str(verse.get("reference", ""))) or not str(verse.get("text", "")).is_empty():
			verse_ok = false
	_check(verse_ok, "las referencias de versículos son válidas y no incluyen texto con derechos")


## Minúsculas con solo letras y espacios, para buscar palabras completas.
func _letters_only(text: String) -> String:
	var result: String = ""
	for i in text.length():
		var c: String = text.substr(i, 1).to_lower()
		result += c if (c.unicode_at(0) > 96 and c.unicode_at(0) < 123) or "áéíóúüñ".contains(c) else " "
	while result.contains("  "):
		result = result.replace("  ", " ")
	return result.strip_edges()


# ---------------------------------------------------------------- Menú y pantallas

func _test_menu_and_screens() -> void:
	print("-- Menú principal y pantallas")
	_check(await _go_to_menu(), "el menú principal se abre")
	var menu: Node = current_scene
	if menu == null:
		return
	_check(menu.get_node_or_null("%TitleBlock") != null, "el menú muestra el bloque del título")
	for button_name in ["PlayButton", "MapsButton", "MultiplayerButton", "CharactersButton", "SettingsButton"]:
		var button := menu.get_node_or_null("%" + button_name) as Button
		_check(button != null and not button.text.is_empty() and not button.disabled, "botón %s existe y está activo" % button_name)

	for button_name in MENU_BUTTONS:
		var key: String = MENU_BUTTONS[button_name]
		var button := current_scene.get_node_or_null("%" + button_name) as Button
		if button == null:
			continue
		button.pressed.emit()
		var arrived: bool = await _wait_until(_arrived.bind(key))
		_check(arrived, "%s abre la pantalla '%s'" % [button_name, key])
		if arrived:
			await _test_screen(key)
			var back := current_scene.find_child("BackButton", true, false) as Button
			_check(back != null, "la pantalla '%s' tiene botón VOLVER" % key)
			if back != null:
				back.pressed.emit()
				_check(await _wait_until(_arrived.bind("main_menu")), "VOLVER regresa al menú desde '%s'" % key)
				if key == "multiplayer":
					_online_after_leaving_screen()
		if current_scene == null or not _arrived("main_menu"):
			_check(await _go_to_menu(), "regreso al menú para seguir probando")

	# Botón "atrás" de Android (y tecla Esc) desde una pantalla secundaria.
	var settings_button := current_scene.get_node_or_null("%SettingsButton") as Button
	if settings_button != null:
		settings_button.pressed.emit()
		if await _wait_until(_arrived.bind("settings")):
			root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
			_check(await _wait_until(_arrived.bind("main_menu")), "el botón atrás de Android vuelve al menú")
	var characters_button := current_scene.get_node_or_null("%CharactersButton") as Button
	if characters_button != null:
		characters_button.pressed.emit()
		if await _wait_until(_arrived.bind("characters")):
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.physical_keycode = KEY_ESCAPE
			escape.pressed = true
			Input.parse_input_event(escape)
			_check(await _wait_until(_arrived.bind("main_menu")), "la tecla Esc vuelve al menú")
	if not _arrived("main_menu"):
		await _go_to_menu()


func _test_screen(key: String) -> void:
	match key:
		"world":
			await _test_world_screen()
		"maps":
			await _test_maps_screen()
		"multiplayer":
			await _test_multiplayer_screen()
		"characters":
			_test_characters_screen()
		"settings":
			_test_settings_screen()


# ---------------------------------------------------------------- Conexión en línea (fase 4.1)

const FakeTransport := preload("res://tools/fake_online_transport.gd")
const ONLINE_TEST_ID := "prueba-0123456789abcdef"
const ONLINE_TEST_SESSION := "0123456789abcdef0123456789abcdef"
const ONLINE_TEST_URL := "https://juego.example"

var _fakes: Array = []
var _fake_open_result: int = OK
var _online_events: Array = []
var _online_restore_url: String = ""


func _make_fake() -> OnlineTransport:
	var fake: OnlineTransport = FakeTransport.new()
	fake.set("open_result", _fake_open_result)
	_fakes.append(fake)
	return fake


func _last_fake() -> Object:
	return _fakes[_fakes.size() - 1]


func _on_online_welcomed(_info: Dictionary) -> void:
	_online_events.append("welcomed")


func _on_online_stats(count: int) -> void:
	_online_events.append("stats:%d" % count)


func _on_online_message(message: Dictionary) -> void:
	_online_events.append("message:%s" % str(message.get("t", "")))


func _on_online_lost(will_retry: bool) -> void:
	_online_events.append("lost:%s" % str(will_retry))


func _on_online_error(code: String, _text: String) -> void:
	_online_events.append("error:%s" % code)


func _new_online_client(url: String = ONLINE_TEST_URL) -> OnlineClient:
	_fakes.clear()
	_fake_open_result = OK
	_online_events.clear()
	var client := OnlineClient.new(_make_fake)
	client.jitter_enabled = false
	client.configure(url, ONLINE_TEST_ID, "Noé", "0.4.0-alfa.1")
	client.welcomed.connect(_on_online_welcomed)
	client.stats_received.connect(_on_online_stats)
	client.message_received.connect(_on_online_message)
	client.connection_lost.connect(_on_online_lost)
	client.server_error.connect(_on_online_error)
	return client


func _online_welcome(online: int, resumed: bool) -> Dictionary:
	return {
		"t": "welcome", "v": OnlineProtocol.VERSION, "session": ONLINE_TEST_SESSION, "resumed": resumed,
		"server": "prueba", "now": 1, "online": online, "you": {"client": ONLINE_TEST_ID, "name": "Noé"},
	}


## Lleva un cliente nuevo hasta ONLINE con el servidor falso.
func _online_connect(client: OnlineClient, online: int = 3, resumed: bool = false) -> void:
	client.start()
	var fake: Object = _last_fake()
	fake.server_accepts()
	client.tick(0.05)
	fake.server_sends_json(_online_welcome(online, resumed))
	client.tick(0.05)


func _online_state(client: OnlineClient) -> String:
	return OnlineClient.state_name(client.state)


func _test_online_protocol() -> void:
	print("-- Conexión en línea: protocolo")
	var hello: Dictionary = OnlineProtocol.parse(OnlineProtocol.hello(ONLINE_TEST_ID, "  Noé  ", "0.4.0-alfa.1"))
	_check(str(hello.get("t", "")) == "hello" and int(hello.get("v", 0)) == OnlineProtocol.VERSION,
			"el saludo lleva su tipo y la versión del protocolo")
	_check(str(hello.get("client", "")) == ONLINE_TEST_ID and str(hello.get("name", "")) == "Noé"
			and str(hello.get("app", "")) == "0.4.0-alfa.1",
			"el saludo lleva el identificador, el nombre limpio y la versión de la app")
	_check(not hello.has("resume"), "sin sesión previa, el saludo no pide reanudar")
	var resume: Dictionary = OnlineProtocol.parse(OnlineProtocol.hello(ONLINE_TEST_ID, "Noé", "x", ONLINE_TEST_SESSION))
	_check(str(resume.get("resume", "")) == ONLINE_TEST_SESSION, "con una sesión válida, el saludo pide reanudarla")
	var bad_resume: Dictionary = OnlineProtocol.parse(OnlineProtocol.hello(ONLINE_TEST_ID, "Noé", "x", "no-valida"))
	_check(not bad_resume.has("resume"), "una sesión mal formada no se envía")
	_check(str(OnlineProtocol.parse(OnlineProtocol.bye()).get("t", "")) == "bye", "mensaje de despedida (bye)")
	_check(str(OnlineProtocol.parse(OnlineProtocol.stats_request()).get("t", "")) == "stats", "mensaje de estadísticas (stats)")

	_check(not OnlineProtocol.parse("{\"t\":\"welcome\",\"online\":2}").is_empty(), "se lee un mensaje válido")
	for bad in ["", "hola", "{", "[]", "null", "7", "\"t\"", "{}", "{\"t\":1}", "{\"t\":\"\"}",
			"{\"t\":\"%s\"}" % "x".repeat(33), "[{\"t\":\"a\"}]"]:
		_check(OnlineProtocol.parse(bad).is_empty(), "se ignora el mensaje inválido: %s" % bad.left(20))

	var cleaning := {
		"  Ana   María ": "Ana María",
		"A\u0001b\u0007c": "Abc",
		"Zero\u200bWidth": "ZeroWidth",
		"\u202eatrás": "atrás",
		"": "",
		"   ": "",
	}
	for raw in cleaning:
		_check(OnlineProtocol.clean_name(str(raw)) == str(cleaning[raw]), "limpia el nombre '%s'" % str(raw).strip_edges())
	_check(OnlineProtocol.clean_name("x".repeat(50)).length() == OnlineProtocol.NAME_MAX_CHARS, "el nombre se recorta a 20 caracteres")

	_check(OnlineProtocol.is_valid_client_id("abcdefghijklmnop") and not OnlineProtocol.is_valid_client_id("corto")
			and not OnlineProtocol.is_valid_client_id("con espacios y mas!!") and not OnlineProtocol.is_valid_client_id("a".repeat(65)),
			"validación del identificador de dispositivo")
	_check(OnlineProtocol.is_valid_session(ONLINE_TEST_SESSION) and not OnlineProtocol.is_valid_session("ABCDEF")
			and not OnlineProtocol.is_valid_session(ONLINE_TEST_SESSION.to_upper()),
			"validación del código de sesión")
	var first_id: String = OnlineProtocol.make_client_id()
	_check(OnlineProtocol.is_valid_client_id(first_id) and first_id != OnlineProtocol.make_client_id(),
			"los identificadores de dispositivo generados son válidos y distintos")
	_test_online_protocol_matches_server()


## El juego y el servidor tienen que usar los mismos números: se leen de server/src/protocol.js.
func _test_online_protocol_matches_server() -> void:
	var path := "res://server/src/protocol.js"
	_check(FileAccess.file_exists(path), "existe el protocolo del servidor (server/src/protocol.js)")
	if not FileAccess.file_exists(path):
		return
	var source: String = FileAccess.get_file_as_string(path)
	var expected := {
		"PROTOCOL_VERSION = ": OnlineProtocol.VERSION,
		"REPLACED: ": OnlineProtocol.CLOSE_REPLACED,
		"BAD_VERSION: ": OnlineProtocol.CLOSE_BAD_VERSION,
		"BAD_MESSAGE: ": OnlineProtocol.CLOSE_BAD_MESSAGE,
		"RATE_LIMITED: ": OnlineProtocol.CLOSE_RATE_LIMITED,
		"TOO_MANY: ": OnlineProtocol.CLOSE_TOO_MANY,
		"HANDSHAKE_TIMEOUT: ": OnlineProtocol.CLOSE_HANDSHAKE_TIMEOUT,
		"NAME_MAX_CHARS: ": OnlineProtocol.NAME_MAX_CHARS,
		"MAX_MESSAGE_CHARS: ": OnlineProtocol.MAX_MESSAGE_CHARS,
	}
	for key in expected:
		var regex := RegEx.new()
		regex.compile(String(key) + "(\\d+)")
		var found: RegExMatch = regex.search(source)
		_check(found != null and int(found.get_string(1)) == int(expected[key]),
				"el juego y el servidor coinciden en %s%d" % [String(key), int(expected[key])])


func _test_online_config() -> void:
	print("-- Conexión en línea: configuración")
	var cases := {
		"https://a.b.workers.dev": "https://a.b.workers.dev",
		"https://a.b.workers.dev/": "https://a.b.workers.dev",
		"wss://a.b.workers.dev/ws": "https://a.b.workers.dev",
		"  https://a.b.workers.dev/ws/  ": "https://a.b.workers.dev",
		"http://127.0.0.1:8787": "http://127.0.0.1:8787",
		"ws://localhost:8787/ws": "http://localhost:8787",
		"http://evil.example": "",
		"ws://evil.example/ws": "",
		"ftp://a.dev": "",
		"a.b.workers.dev": "",
		"": "",
		"   ": "",
		"https://": "",
		"https://a b.dev": "",
		"https://a.dev/otra/ruta": "",
		"https://usuario@a.dev": "",
		"https://a.dev?x=1": "",
	}
	for raw in cases:
		_check(OnlineConfig.normalize_base_url(str(raw)) == str(cases[raw]), "dirección '%s' -> '%s'" % [str(raw).strip_edges(), str(cases[raw])])
	_check(OnlineConfig.to_ws_url("https://a.dev") == "wss://a.dev/ws", "https se convierte en wss://.../ws")
	_check(OnlineConfig.to_ws_url("http://127.0.0.1:8787") == "ws://127.0.0.1:8787/ws", "http local se convierte en ws://.../ws")
	_check(OnlineConfig.to_ws_url("http://evil.example").is_empty() and OnlineConfig.to_ws_url("").is_empty(),
			"una dirección no permitida no genera WebSocket")
	_check(OnlineConfig.to_http_url("https://a.dev", "/health") == "https://a.dev/health", "dirección de /health")

	var shipped: String = OnlineConfig.CONFIG_PATH
	_check(FileAccess.file_exists(shipped), "existe data/online.json")
	var parsed := JSON.new()
	_check(parsed.parse(FileAccess.get_file_as_string(shipped)) == OK and typeof(parsed.data) == TYPE_DICTIONARY
			and (parsed.data as Dictionary).has("server_url"), "data/online.json es un JSON con el campo server_url")
	var shipped_url: String = OnlineConfig.load_server_url()
	_check(shipped_url.is_empty() or shipped_url.begins_with("https://"), "la dirección del servidor del juego está vacía o es https")

	var temp := "user://online_config_test.json"
	_write_text(temp, "{\"server_url\": \"https://x.workers.dev/ws\"}")
	_check(OnlineConfig.load_server_url(temp) == "https://x.workers.dev", "lee y normaliza la dirección del archivo")
	_write_text(temp, "no es json")
	_check(OnlineConfig.load_server_url(temp).is_empty(), "un archivo dañado da una dirección vacía")
	_write_text(temp, "[1, 2]")
	_check(OnlineConfig.load_server_url(temp).is_empty(), "un archivo que no es un objeto da una dirección vacía")
	_write_text(temp, "{\"server_url\": \"http://malo.example\"}")
	_check(OnlineConfig.load_server_url(temp).is_empty(), "una dirección insegura se rechaza")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	_check(OnlineConfig.load_server_url(temp).is_empty(), "sin archivo, la dirección está vacía")

	var identity := "user://online_identity_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(identity))
	var created: String = OnlineConfig.load_client_id(identity)
	_check(OnlineProtocol.is_valid_client_id(created), "se crea un identificador de dispositivo válido")
	_check(OnlineConfig.load_client_id(identity) == created, "el identificador se conserva entre sesiones")
	var cfg := ConfigFile.new()
	cfg.set_value("identity", "client_id", "dañado!")
	cfg.save(identity)
	var repaired: String = OnlineConfig.load_client_id(identity)
	_check(OnlineProtocol.is_valid_client_id(repaired) and repaired != "dañado!", "un identificador dañado se vuelve a crear")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(identity))


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _test_online_client() -> void:
	print("-- Conexión en línea: cliente (con servidor falso)")
	_online_client_without_server()
	_online_client_happy_path()
	_online_client_heartbeat_and_resume()
	_online_client_backoff()
	_online_client_close_codes()
	_online_client_stop()
	_online_client_timeouts()
	_online_client_misc()


func _online_client_without_server() -> void:
	var client: OnlineClient = _new_online_client("")
	client.start()
	_check(not client.has_server() and client.state == OnlineClient.State.FAILED and client.fail_code == OnlineClient.FAIL_NO_SERVER
			and _fakes.is_empty(), "sin dirección de servidor no se intenta conectar (FAILED no_server)")
	client = _new_online_client("http://evil.example")
	client.start()
	_check(client.state == OnlineClient.State.FAILED and _fakes.is_empty(), "una dirección insegura no se usa")
	client = _new_online_client()
	client.configure(ONLINE_TEST_URL, "corto", "Noé", "x")
	client.start()
	_check(client.state == OnlineClient.State.FAILED and client.fail_code == OnlineClient.FAIL_BAD_CLIENT,
			"un identificador de dispositivo inválido no se usa")


func _online_client_happy_path() -> void:
	var client: OnlineClient = _new_online_client()
	_check(client.state == OnlineClient.State.IDLE and not client.is_busy(), "el cliente nuevo está en reposo")
	client.start()
	_check(client.state == OnlineClient.State.CONNECTING and _fakes.size() == 1 and client.is_busy(), "start() empieza a conectar")
	var fake: Object = _last_fake()
	_check(str(fake.url) == "wss://juego.example/ws", "se conecta a wss://servidor/ws (%s)" % str(fake.url))
	fake.server_accepts()
	client.tick(0.05)
	_check(client.state == OnlineClient.State.HANDSHAKE, "con la conexión abierta se espera el welcome")
	var sent: Array = fake.sent_json()
	_check(sent.size() == 1 and str((sent[0] as Dictionary).get("t", "")) == "hello", "lo primero que se envía es el hello")
	var hello: Dictionary = sent[0]
	_check(str(hello.get("client", "")) == ONLINE_TEST_ID and str(hello.get("name", "")) == "Noé"
			and int(hello.get("v", 0)) == OnlineProtocol.VERSION and not hello.has("resume"),
			"el hello lleva identificador, nombre y versión; sin sesión previa no pide reanudar")
	fake.server_sends_json(_online_welcome(3, false))
	client.tick(0.05)
	_check(client.state == OnlineClient.State.ONLINE and client.is_online(), "tras el welcome el cliente está ONLINE")
	_check(client.session == ONLINE_TEST_SESSION and not client.resumed and client.online_count == 3 and client.attempt == 0,
			"guarda la sesión y el número de jugadores en línea")
	_check(_online_events.has("welcomed"), "avisa con la señal welcomed")
	_check(client.request_stats() and fake.sent_json().size() == 2 and str((fake.sent_json()[1] as Dictionary).get("t", "")) == "stats",
			"request_stats() envía el pedido de estadísticas")
	fake.server_sends_json({"t": "stats", "online": 5})
	client.tick(0.05)
	_check(client.online_count == 5 and _online_events.has("stats:5"), "las estadísticas actualizan el número de jugadores")
	fake.server_sends_json({"t": "sala_actualizada", "jugadores": 2})
	fake.server_sends("esto no es json")
	fake.server_sends_json({"sin_tipo": true})
	fake.server_sends_json({"t": "error", "code": "unknown_type", "msg": "no existe"})
	client.tick(0.05)
	_check(_online_events.has("message:sala_actualizada"), "los mensajes de juego se pasan a message_received")
	_check(_online_events.has("error:unknown_type") and client.last_error_code == "unknown_type", "los errores del servidor se avisan")
	_check(client.state == OnlineClient.State.ONLINE, "los mensajes inválidos o desconocidos no cortan la conexión")
	_check(client.send_message({"t": "sala_unirse", "codigo": "ABCD"}) and fake.sent_json().size() == 3, "send_message() envía un mensaje de juego")
	_check(not client.send_message({"t": "grande", "relleno": "x".repeat(5000)}), "un mensaje demasiado grande no se envía")
	client.stop()


func _online_client_heartbeat_and_resume() -> void:
	var client: OnlineClient = _new_online_client()
	_online_connect(client)
	var fake: Object = _last_fake()
	client.tick(OnlineClient.PING_INTERVAL - 1.0)
	_check(fake.sent_ping_count() == 0, "todavía no toca el latido")
	client.tick(1.1)
	_check(fake.sent_ping_count() == 1, "cada 20 s se envía un ping")
	client.tick(0.1)
	fake.server_sends("pong")
	client.tick(0.1)
	_check(client.state == OnlineClient.State.ONLINE and client.ping_ms >= 0, "el pong mantiene la conexión y mide la demora (%d ms)" % client.ping_ms)
	client.tick(OnlineClient.PING_INTERVAL + 0.5)
	_check(fake.sent_ping_count() == 2, "el latido se repite")
	client.tick(OnlineClient.PONG_TIMEOUT - 1.0)
	_check(client.state == OnlineClient.State.ONLINE, "mientras no pase el plazo del pong sigue conectado")
	client.tick(1.5)
	_check(client.state == OnlineClient.State.WAITING and client.attempt == 1, "sin pong a tiempo se da por perdida la conexión (WAITING)")
	_check(_online_events.has("lost:true"), "avisa que se perdió la conexión y que va a reintentar")
	_check((fake.closed_by_client as Array).size() == 1, "se descarta la conexión muerta")
	client.tick(OnlineClient.BACKOFF_BASE - 0.1)
	_check(client.state == OnlineClient.State.WAITING, "espera 1 s antes del primer reintento")
	client.tick(0.2)
	_check(client.state == OnlineClient.State.CONNECTING and _fakes.size() == 2, "reintenta con una conexión nueva")
	var second: Object = _last_fake()
	second.server_accepts()
	client.tick(0.05)
	var hello: Dictionary = (second.sent_json() as Array)[0]
	_check(str(hello.get("resume", "")) == ONLINE_TEST_SESSION, "al reconectar pide reanudar la misma sesión")
	second.server_sends_json(_online_welcome(4, true))
	client.tick(0.05)
	_check(client.state == OnlineClient.State.ONLINE and client.resumed and client.attempt == 0 and client.online_count == 4,
			"sesión reanudada: vuelve a ONLINE y se reinicia el contador de reintentos")
	client.stop()


func _online_client_backoff() -> void:
	var delays: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0, 30.0, 30.0]
	for i in delays.size():
		_check(is_equal_approx(OnlineClient.backoff_delay(i + 1, false), delays[i]), "espera del reintento %d = %s s" % [i + 1, str(delays[i])])
	_check(is_equal_approx(OnlineClient.backoff_delay(1, true), 5.0) and is_equal_approx(OnlineClient.backoff_delay(2, true), 10.0)
			and is_equal_approx(OnlineClient.backoff_delay(9, true), 30.0), "los errores de límite esperan más (5, 10, 20, 30 s)")
	_check(is_equal_approx(OnlineClient.backoff_delay(3, false, 0.0), 3.2) and is_equal_approx(OnlineClient.backoff_delay(3, false, 1.0), 4.8),
			"la variación al azar es de ±20 %")

	var client: OnlineClient = _new_online_client()
	client.start()
	for failure in range(1, 4):
		_last_fake().connection_fails()
		client.tick(0.05)
		var expected: float = OnlineClient.backoff_delay(failure, false)
		_check(client.state == OnlineClient.State.WAITING and client.attempt == failure, "fallo %d: espera %s s" % [failure, str(expected)])
		client.tick(expected - 0.3)
		var still_waiting: bool = client.state == OnlineClient.State.WAITING
		client.tick(0.4)
		_check(still_waiting and client.state == OnlineClient.State.CONNECTING, "fallo %d: reintenta justo después de la espera" % failure)
	_check(not _online_events.has("lost:true"), "si nunca estuvo conectado no avisa 'conexión perdida'")
	# Sigue fallando hasta agotar los reintentos automáticos.
	var guard: int = 0
	while client.state != OnlineClient.State.FAILED and guard < 30:
		_last_fake().connection_fails()
		client.tick(0.05)
		client.tick(OnlineClient.BACKOFF_MAX + 1.0)
		guard += 1
	_check(client.state == OnlineClient.State.FAILED and client.fail_code == OnlineClient.FAIL_UNREACHABLE, "tras %d reintentos se rinde (FAILED unreachable)" % OnlineClient.MAX_AUTO_RETRIES)
	var made: int = _fakes.size()
	client.tick(120.0)
	_check(_fakes.size() == made and not client.is_busy(), "ya no reintenta solo")
	client.start()
	_check(client.state == OnlineClient.State.CONNECTING and client.attempt == 0 and client.fail_code.is_empty(), "start() de nuevo reinicia los reintentos")
	_fake_open_result = ERR_CANT_CONNECT
	client = _new_online_client()
	_fake_open_result = ERR_CANT_CONNECT
	client.start()
	_check(client.state == OnlineClient.State.WAITING and client.attempt == 1, "si ni siquiera se puede empezar a conectar, se reintenta después")
	_fake_open_result = OK


func _online_client_close_codes() -> void:
	var client: OnlineClient = _new_online_client()
	_online_connect(client)
	_last_fake().server_closes(OnlineProtocol.CLOSE_BAD_VERSION, "bad_version")
	client.tick(0.05)
	var made: int = _fakes.size()
	client.tick(60.0)
	_check(client.state == OnlineClient.State.FAILED and client.fail_code == OnlineClient.FAIL_BAD_VERSION and _fakes.size() == made,
			"cierre 4001: versión distinta, no reintenta")

	client = _new_online_client()
	_online_connect(client)
	_last_fake().server_closes(OnlineProtocol.CLOSE_REPLACED, "replaced")
	client.tick(0.05)
	_check(client.state == OnlineClient.State.FAILED and client.fail_code == OnlineClient.FAIL_REPLACED, "cierre 4000: se abrió en otro lugar, no reintenta")

	client = _new_online_client()
	_online_connect(client)
	_last_fake().server_sends_json({"t": "bye", "reason": "replaced"})
	client.tick(0.05)
	_check(client.state == OnlineClient.State.FAILED and client.fail_code == OnlineClient.FAIL_REPLACED, "el aviso 'bye replaced' también detiene los reintentos")

	client = _new_online_client()
	_online_connect(client)
	_last_fake().server_closes(OnlineProtocol.CLOSE_RATE_LIMITED, "rate_limited")
	client.tick(0.05)
	_check(client.state == OnlineClient.State.WAITING and _online_events.has("lost:true"), "cierre 4003: reintenta")
	client.tick(OnlineClient.BACKOFF_SLOW_BASE - 0.3)
	var slow_waiting: bool = client.state == OnlineClient.State.WAITING
	client.tick(0.4)
	_check(slow_waiting and client.state == OnlineClient.State.CONNECTING, "cierre 4003: espera 5 s (más que un corte normal)")

	client = _new_online_client()
	_online_connect(client)
	_last_fake().server_closes(1006, "")
	client.tick(0.05)
	client.tick(OnlineClient.BACKOFF_BASE + 0.1)
	_check(client.state == OnlineClient.State.CONNECTING and client.last_close_code == 1006, "un corte de red (1006) reintenta a los 1,0 s")

	client = _new_online_client()
	_online_connect(client)
	_last_fake().server_closes(OnlineProtocol.CLOSE_TOO_MANY, "too_many_connections")
	client.tick(0.05)
	_check(client.state == OnlineClient.State.WAITING and client.attempt == 1, "cierre 4004 (servidor lleno): espera y reintenta")


func _online_client_stop() -> void:
	var client: OnlineClient = _new_online_client()
	_online_connect(client)
	var fake: Object = _last_fake()
	client.stop()
	var sent: Array = fake.sent_json()
	_check(str((sent[sent.size() - 1] as Dictionary).get("t", "")) == "bye", "stop() envía la despedida (bye)")
	_check((fake.closed_by_client as Array).size() == 1 and int((fake.closed_by_client[0] as Dictionary).get("code", 0)) == 1000,
			"stop() cierra con el código normal 1000")
	_check(client.state == OnlineClient.State.IDLE and client.session.is_empty(), "tras stop() queda en reposo y sin sesión")
	client.tick(0.5)
	var made: int = _fakes.size()
	client.tick(120.0)
	_check(_fakes.size() == made and not client.is_busy(), "tras stop() no reintenta ni queda nada pendiente")
	_online_connect(client)
	var again: Dictionary = (_last_fake().sent_json() as Array)[0]
	_check(not again.has("resume"), "después de una despedida voluntaria no se intenta reanudar la sesión")

	client = _new_online_client()
	client.start()
	_last_fake().connection_fails()
	client.tick(0.05)
	client.stop()
	made = _fakes.size()
	client.tick(120.0)
	_check(client.state == OnlineClient.State.IDLE and _fakes.size() == made, "stop() durante la espera cancela el reintento")


func _online_client_timeouts() -> void:
	var client: OnlineClient = _new_online_client()
	client.start()
	client.tick(OnlineClient.CONNECT_TIMEOUT - 0.5)
	_check(client.state == OnlineClient.State.CONNECTING, "mientras no pase el plazo sigue conectando")
	client.tick(1.0)
	_check(client.state == OnlineClient.State.WAITING and client.attempt == 1, "si la conexión no abre a tiempo, se reintenta")

	client = _new_online_client()
	client.start()
	_last_fake().server_accepts()
	client.tick(0.05)
	client.tick(OnlineClient.HELLO_TIMEOUT + 0.5)
	_check(client.state == OnlineClient.State.WAITING and client.attempt == 1, "si el servidor no responde al saludo, se reintenta")


func _online_client_misc() -> void:
	var client: OnlineClient = _new_online_client()
	_online_connect(client)
	var fake: Object = _last_fake()
	client.check_now()
	_check(fake.sent_ping_count() == 1, "al volver de segundo plano se comprueba la conexión enseguida")
	client.tick(OnlineClient.RESUME_CHECK_TIMEOUT - 0.5)
	_check(client.state == OnlineClient.State.ONLINE, "la comprobación espera hasta 4 s")
	client.tick(1.0)
	_check(client.state == OnlineClient.State.WAITING, "sin respuesta a la comprobación se reconecta")
	client.check_now()
	client.tick(0.0)
	_check(client.state == OnlineClient.State.CONNECTING, "volver a primer plano durante la espera reconecta sin esperar")
	client.stop()

	client = _new_online_client()
	client.start()
	var early: Object = _last_fake()
	early.server_accepts()
	client.tick(0.05)
	var welcome: Dictionary = _online_welcome(2, false)
	welcome["session"] = "inventada"
	early.server_sends_json(welcome)
	client.tick(0.05)
	_check(client.state == OnlineClient.State.ONLINE and client.session.is_empty(), "un código de sesión mal formado se descarta")
	client.stop()

	client = _new_online_client()
	_check(not client.send_message({"t": "x"}) and not client.request_stats(), "sin conexión no se envía nada")
	client.start()
	_last_fake().server_accepts()
	client.tick(0.05)
	_last_fake().server_sends_json({"t": "stats", "online": 9})
	client.tick(0.05)
	_check(not client.is_online(), "el servidor no puede saltarse el saludo para dejar al cliente ONLINE")
	client.stop()


func _online_manager_and_screen() -> void:
	var manager: Node = root.get_node_or_null("OnlineManager")
	_check(manager != null, "el autoload OnlineManager existe")
	var panel := _node("%OnlinePanel")
	var dot := _node("%StatusDot") as Panel
	var label := _node("%StatusLabel") as Label
	var detail := _node("%DetailLabel") as Label
	var button := _node("%ConnectButton") as Button
	_check(_node("%OnlineTitle") != null and _node("%OnlineText") != null, "el panel en línea tiene título y explicación")
	if manager == null or panel == null or dot == null or label == null or detail == null or button == null:
		return
	var shipped_url: String = str(manager.server_url)
	var client: OnlineClient = manager.client

	manager.set_server_url("")
	await process_frame
	_check(not manager.is_configured() and label.text.contains("sin configurar") and button.disabled,
			"sin servidor configurado el panel avisa y el botón está desactivado")
	_check(manager.status_kind() == "warn" and manager.detail_text().length() > 0, "sin servidor: aviso amarillo con explicación")

	manager.set_server_url(ONLINE_TEST_URL)
	_fakes.clear()
	_fake_open_result = OK
	client.set_transport_factory(_make_fake)
	client.jitter_enabled = false
	await process_frame
	_check(manager.is_configured() and not button.disabled and button.text == "PROBAR CONEXIÓN" and label.text == "Sin conexión.",
			"con servidor configurado el botón PROBAR CONEXIÓN está activo")
	button.pressed.emit()
	_check(client.state == OnlineClient.State.CONNECTING and label.text == "Conectando…" and button.text == "CANCELAR",
			"al probar la conexión el panel muestra 'Conectando…' y el botón pasa a CANCELAR")
	_check(_fakes.size() == 1, "pulsar el botón abre una conexión")
	var fake: Object = _last_fake()
	fake.server_accepts()
	await process_frame
	await process_frame
	_check(client.state == OnlineClient.State.HANDSHAKE, "OnlineManager hace avanzar al cliente en cada fotograma")
	fake.server_sends_json(_online_welcome(7, false))
	await process_frame
	await process_frame
	_check(client.state == OnlineClient.State.ONLINE, "el cliente llega a ONLINE dentro del juego")
	_check(label.text == "Conectado · 7 jugadores en línea" and button.text == "DESCONECTAR", "el panel muestra 'Conectado' con el número de jugadores")
	var style := dot.get_theme_stylebox("panel") as StyleBoxFlat
	_check(style != null and style.bg_color.is_equal_approx(UiTheme.OK_GREEN), "el punto de estado se pone verde")
	fake.server_sends_json({"t": "stats", "online": 1})
	await process_frame
	await process_frame
	_check(label.text == "Conectado · 1 jugador en línea", "el panel se actualiza con las estadísticas (singular)")

	fake.server_closes(1006, "")
	await process_frame
	await process_frame
	_check(client.state == OnlineClient.State.WAITING and label.text.contains("Reintentando") and button.text == "CANCELAR",
			"si se corta la conexión el panel avisa que reintenta")
	style = dot.get_theme_stylebox("panel") as StyleBoxFlat
	_check(style != null and style.bg_color.is_equal_approx(Color(0.96, 0.77, 0.33)), "el punto de estado se pone amarillo")
	button.pressed.emit()
	_check(client.state == OnlineClient.State.IDLE and label.text == "Sin conexión." and button.text == "PROBAR CONEXIÓN",
			"CANCELAR detiene los reintentos")

	client.jitter_enabled = false
	button.pressed.emit()
	var guard: int = 0
	while client.state != OnlineClient.State.FAILED and guard < 40:
		if client.state == OnlineClient.State.CONNECTING:
			_last_fake().connection_fails()
		client.tick(OnlineClient.BACKOFF_MAX + 1.0)
		guard += 1
	_check(client.state == OnlineClient.State.FAILED and label.text.contains("No se pudo conectar"), "si el servidor no responde, el panel explica el problema")
	style = dot.get_theme_stylebox("panel") as StyleBoxFlat
	_check(style != null and style.bg_color.is_equal_approx(UiTheme.WARN_RED), "el punto de estado se pone rojo")
	_check(not button.disabled and button.text == "PROBAR CONEXIÓN", "después del error se puede volver a probar")

	# Se deja conectado para comprobar que al salir de la pantalla la conexión se cierra.
	button.pressed.emit()
	var again: Object = _last_fake()
	again.server_accepts()
	await process_frame
	await process_frame
	again.server_sends_json(_online_welcome(2, false))
	await process_frame
	await process_frame
	_check(client.state == OnlineClient.State.ONLINE, "se puede volver a conectar después de un error")
	_online_restore_url = shipped_url


## Se comprueba después de pulsar VOLVER en Multijugador: la conexión en línea se cierra sola.
func _online_after_leaving_screen() -> void:
	var manager: Node = root.get_node_or_null("OnlineManager")
	if manager == null:
		return
	var client: OnlineClient = manager.client
	_check(client.state == OnlineClient.State.IDLE and not client.is_online(), "al salir de Multijugador se cierra la conexión en línea")
	if not _fakes.is_empty():
		var sent: Array = _last_fake().sent_json()
		_check(not sent.is_empty() and str((sent[sent.size() - 1] as Dictionary).get("t", "")) == "bye",
				"al salir de Multijugador se avisa al servidor con bye")
	client.set_transport_factory(Callable())
	client.jitter_enabled = true
	manager.set_server_url(_online_restore_url)
	_fakes.clear()


# ---------------------------------------------------------------- Sonidos ambientales

## Cada mundo tiene su sonido en bucle: se generan por código, no están vacíos, no se pasan de volumen,
## cierran el bucle sin salto, suenan distinto entre sí y los reproduce un nodo que va por el bus de música.
func _test_ambience() -> void:
	print("-- Sonidos ambientales de los mundos")
	var kinds: Array[String] = AmbienceSynth.KINDS
	_check(kinds.size() == 7, "hay un sonido ambiental para cada uno de los 7 mundos (%d)" % kinds.size())
	_check(AmbienceSynth.has_kind("sea") and not AmbienceSynth.has_kind("") and not AmbienceSynth.has_kind("lluvia"),
			"solo se aceptan los nombres de sonido conocidos")
	var frames: int = AmbienceSynth.frames()
	_check(frames == int(AmbienceSynth.SECONDS * float(AmbienceSynth.RATE)) and frames > 40000,
			"cada bucle dura %.1f segundos (%d muestras)" % [AmbienceSynth.SECONDS, frames])

	var hashes: Dictionary = {}
	var total_ms: int = 0
	for kind in kinds:
		var started: int = Time.get_ticks_msec()
		var stream: AudioStreamWAV = AmbienceSynth.ambience(kind)
		var elapsed: int = Time.get_ticks_msec() - started
		total_ms += elapsed
		if stream == null:
			_check(false, "el sonido '%s' se genera" % kind)
			continue
		_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo
				and stream.mix_rate == AmbienceSynth.RATE and stream.data.size() == frames * 2,
				"sonido '%s': audio de 16 bits, mono, %d Hz (%d ms)" % [kind, stream.mix_rate, elapsed])
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == frames,
				"sonido '%s': se repite en bucle de principio a fin" % kind)
		var data: PackedByteArray = stream.data
		var first: int = data.decode_s16(0)
		var previous: int = first
		var peak: int = absi(first)
		var energy: float = float(first * first)
		var diff_energy: float = 0.0
		var window: int = 2756
		var window_energy: float = float(first * first)
		var quietest: float = INF
		var loudest: float = 0.0
		for i in range(1, frames):
			var value: int = data.decode_s16(i * 2)
			peak = maxi(peak, absi(value))
			energy += float(value * value)
			diff_energy += float((value - previous) * (value - previous))
			previous = value
			window_energy += float(value * value)
			if (i + 1) % window == 0:
				quietest = minf(quietest, window_energy)
				loudest = maxf(loudest, window_energy)
				window_energy = 0.0
		var rms: float = sqrt(energy / float(frames)) / 32767.0
		var diff_rms: float = sqrt(diff_energy / float(frames - 1))
		var seam: int = absi(first - previous)
		_check(rms > 0.05 and rms < 0.2, "sonido '%s': volumen medio %.3f (ni mudo ni fuerte)" % [kind, rms])
		_check(peak > 3000 and peak <= 31200, "sonido '%s': el pico (%d de 32767) no se recorta" % [kind, peak])
		_check(float(seam) <= 5.0 * diff_rms + 100.0,
				"sonido '%s': el final del bucle encaja con el principio (salto %d, normal %.0f)" % [kind, seam, diff_rms])
		var movement: float = sqrt(loudest / maxf(quietest, 1.0))
		_check(movement > 1.05, "sonido '%s': tiene movimiento, no es un zumbido plano (x%.2f)" % [kind, movement])
		hashes[hash(data)] = kind
	_check(hashes.size() == kinds.size(), "los 7 sonidos son distintos entre sí (%d)" % hashes.size())
	_check(total_ms < 20000, "los 7 sonidos se generan en %d ms" % total_ms)
	print("  (generar los 7 sonidos tardó %d ms en esta máquina)" % total_ms)
	_check(AmbienceSynth.ambience("sea") == AmbienceSynth.ambience("sea"), "cada sonido se genera una sola vez")
	_check(AmbienceSynth.ambience("no-existe") == AmbienceSynth.ambience(AmbienceSynth.FALLBACK),
			"un nombre desconocido da el sonido del viento")

	# Cada mundo del catálogo pide un sonido que existe, y los 7 son distintos.
	var used: Dictionary = {}
	var catalog_ok: bool = true
	for map_id in MapCatalog.ids_in_order():
		var sound: String = str(MapCatalog.find_map(map_id)["ambience"]["sound"])
		used[sound] = true
		if not AmbienceSynth.has_kind(sound):
			catalog_ok = false
	_check(catalog_ok and used.size() == 7, "los 7 mundos del catálogo piden 7 sonidos que existen (%d)" % used.size())

	# El reproductor: bucle por el bus de música, entrada suave y silencio con un nombre desconocido.
	var player := AmbiencePlayer.new()
	player.name = "AmbienceTest"
	root.add_child(player)
	player.start("garden", 0.0)
	_check(player.playing and player.kind == "garden" and str(player.bus) == "Music"
			and player.stream == AmbienceSynth.ambience("garden"),
			"el reproductor toca el sonido pedido por el bus de música")
	_check(is_equal_approx(player.volume_db, AmbiencePlayer.VOLUME_DB),
			"sin entrada suave suena al volumen final (%.1f dB)" % player.volume_db)
	player.start("sea", 0.5, -20.0)
	_check(player.playing and player.kind == "sea" and player.volume_db <= AmbiencePlayer.SILENT_DB + 1.0,
			"con entrada suave empieza casi en silencio (%.1f dB)" % player.volume_db)
	await create_timer(0.8).timeout
	_check(is_equal_approx(player.volume_db, -20.0), "la entrada suave llega al volumen pedido (%.1f dB)" % player.volume_db)
	player.start("lluvia")
	_check(not player.playing and player.kind.is_empty(), "un sonido desconocido deja el reproductor en silencio")
	player.start("night", 0.0)
	player.fade_out(0.0)
	_check(not player.playing and player.kind.is_empty(), "fade_out(0) lo apaga de golpe")
	player.queue_free()
	await create_timer(0.05).timeout


# ---------------------------------------------------------------- Mapa mundial

## Mundo bíblico: disposición, relieve, caminos e iconos 3D (sin abrir la pantalla).
func _test_world_logic() -> void:
	print("-- Mundo bíblico: relieve, caminos e iconos 3D")
	WorldMapBuilder.prepare_layout()
	var ids: Array[String] = MapCatalog.ids_in_order()
	_check(WorldMapBuilder.road_count() == 6, "hay 6 caminos que unen los 7 mundos (%d)" % WorldMapBuilder.road_count())

	var scale_ok: bool = true
	var land_ok: bool = true
	var min_gap: float = 1000000.0
	for i in ids.size():
		var spot: Vector2 = WorldMapBuilder.region_spot(ids[i])
		if spot.distance_to(MapCatalog.world_position(ids[i]) * WorldMapBuilder.WORLD_SCALE) > 0.001:
			scale_ok = false
		if WorldMapBuilder.land_mask(spot.x, spot.y) < 0.95:
			land_ok = false
		for j in range(i + 1, ids.size()):
			min_gap = minf(min_gap, spot.distance_to(WorldMapBuilder.region_spot(ids[j])))
	_check(scale_ok, "las regiones están donde dice el catálogo (por la escala del mundo)")
	_check(land_ok, "las 7 regiones están sobre tierra firme")
	_check(min_gap > 28.0, "las regiones están bien separadas (mínimo %.1f)" % min_gap)

	# El suelo bajo cada plataforma es plano y ningún triángulo del terreno la tapa.
	var flat_ok: bool = true
	var covered_ok: bool = true
	var highest_near: float = -1000.0
	var cell: float = WorldMapBuilder.HALF * 2.0 / float(WorldMapBuilder.CELLS)
	var reach: float = WorldMapBuilder.PAD_RADIUS + cell * 1.45
	for id in ids:
		var spot: Vector2 = WorldMapBuilder.region_spot(id)
		if absf(WorldMapBuilder.height_at(spot.x, spot.y) - WorldMapBuilder.GROUND_Y) > 0.001:
			flat_ok = false
		for step in 12:
			var angle: float = TAU * float(step) / 12.0
			var around: Vector2 = spot + Vector2(cos(angle), sin(angle)) * (WorldMapBuilder.PAD_RADIUS + 1.0)
			if absf(WorldMapBuilder.height_at(around.x, around.y) - WorldMapBuilder.GROUND_Y) > 0.001:
				flat_ok = false
		for gx in range(floori((spot.x - reach) / cell), ceili((spot.x + reach) / cell) + 1):
			for gz in range(floori((spot.y - reach) / cell), ceili((spot.y + reach) / cell) + 1):
				var vertex := Vector2(float(gx) * cell, float(gz) * cell)
				if vertex.distance_to(spot) <= reach:
					highest_near = maxf(highest_near, WorldMapBuilder.height_at(vertex.x, vertex.y))
	if highest_near >= WorldMapBuilder.PAD_Y - 0.1:
		covered_ok = false
	_check(flat_ok, "el suelo bajo cada plataforma es plano")
	_check(covered_ok, "el terreno que toca cada plataforma queda por debajo de ella (máx. %.2f)" % highest_near)

	# Caminos: nacen y mueren en el borde de las plataformas y van por suelo plano.
	var chain_ok: bool = true
	var ends_ok: bool = true
	var flat_roads: bool = true
	for index in WorldMapBuilder.road_count():
		var path: PackedVector2Array = WorldMapBuilder.road_points(index)
		if WorldMapBuilder.road_from(index) != ids[index] or WorldMapBuilder.road_to(index) != ids[index + 1]:
			chain_ok = false
		if path.size() < 10:
			ends_ok = false
			continue
		var from_spot: Vector2 = WorldMapBuilder.region_spot(WorldMapBuilder.road_from(index))
		var to_spot: Vector2 = WorldMapBuilder.region_spot(WorldMapBuilder.road_to(index))
		var edge: float = WorldMapBuilder.PAD_RADIUS - 0.4
		if absf(path[0].distance_to(from_spot) - edge) > 0.05 or absf(path[path.size() - 1].distance_to(to_spot) - edge) > 0.05:
			ends_ok = false
		for point in path:
			if absf(WorldMapBuilder.height_at(point.x, point.y) - WorldMapBuilder.GROUND_Y) > 0.01:
				flat_roads = false
	_check(chain_ok, "los caminos unen los mundos en el orden en que se abren")
	_check(ends_ok, "cada camino va de borde a borde de dos plataformas")
	_check(flat_roads, "los caminos van por suelo plano")

	# Relieve: montañas con cumbres altas y mar alrededor.
	var peak: float = -100.0
	for gx in range(-120, 121, 6):
		for gz in range(-60, 61, 6):
			peak = maxf(peak, WorldMapBuilder.height_at(float(gx), float(gz)))
	_check(peak > 10.0 and peak < 26.0, "hay montañas altas (cumbre %.1f)" % peak)
	_check(WorldMapBuilder.height_at(0.0, 140.0) < WorldMapBuilder.SEA_Y - 1.0
			and WorldMapBuilder.height_at(-140.0, 0.0) < WorldMapBuilder.SEA_Y - 1.0
			and WorldMapBuilder.height_at(140.0, -10.0) < WorldMapBuilder.SEA_Y - 1.0, "el continente está rodeado de mar")

	var color_ok: bool = true
	for id in ids:
		var spot: Vector2 = WorldMapBuilder.region_spot(id)
		var theme_data: Dictionary = MapCatalog.find_map(id)["theme"]
		var ground: Color = theme_data["ground"]
		var found: Color = WorldMapBuilder.color_at(spot.x, spot.y, 0.0)
		if absf(found.r - ground.r) + absf(found.g - ground.g) + absf(found.b - ground.b) > 0.6 or found.a < 0.999:
			color_ok = false
	_check(color_ok, "el terreno junto a cada región toma el color de su mundo")
	var snow: Color = WorldMapBuilder.color_at(0.0, 0.0, 15.0)
	var beach: Color = WorldMapBuilder.color_at(0.0, 0.0, WorldMapBuilder.SEA_Y - 0.1)
	_check(snow.get_luminance() > 0.7 and beach.r > beach.b, "las cumbres tienen nieve y la costa arena")

	# Iconos 3D: uno distinto para cada región.
	var icon_names: Dictionary = {}
	for id in ids:
		var world_data: Dictionary = MapCatalog.find_map(id)["world"]
		icon_names[str(world_data["icon"])] = true
	_check(icon_names.size() == 7, "cada mundo tiene un icono 3D distinto (%d)" % icon_names.size())
	var shapes: Dictionary = {}
	for icon in WorldIcons.ICONS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var model := MeshKit.new()
		var glow := MeshKit.new()
		var height: float = WorldIcons.add_icon(model, glow, icon, rng)
		_check(icon_names.has(icon), "el icono '%s' lo usa un mundo del catálogo" % icon)
		_check(model.triangle_count() >= 30 and height > 3.0 and height < 14.0,
				"icono '%s': %d triángulos y %.1f de alto" % [icon, model.triangle_count(), height])
		shapes[model.triangle_count()] = true
		var mesh: ArrayMesh = model.commit()
		_check(_winding_ratio(mesh) > 0.999, "icono '%s': el orden de los vértices coincide con las normales" % icon)
		var box: AABB = mesh.get_aabb()
		# Las rocas van medio hundidas en el suelo (hasta ≈1.6 bajo la plataforma, donde no se ven).
		_check(box.position.y > -1.7 and box.end.y < height + 1.5 and absf(box.position.x) < 10.0 and absf(box.end.x) < 10.0
				and absf(box.position.z) < 10.0 and absf(box.end.z) < 10.0,
				"icono '%s': cabe en la plataforma (%s)" % [icon, str(box)])
		var decor := MeshKit.new()
		var decor_glow := MeshKit.new()
		WorldIcons.add_decor(decor, decor_glow, icon, rng, 1.0)
		var decor_box: AABB = decor.commit().get_aabb()
		_check(decor.triangle_count() >= 40 and absf(decor_box.position.x) < 11.0 and absf(decor_box.end.x) < 11.0
				and absf(decor_box.position.z) < 11.0 and absf(decor_box.end.z) < 11.0,
				"icono '%s': decorado de %d triángulos dentro de la plataforma" % [icon, decor.triangle_count()])
		var sparse := MeshKit.new()
		WorldIcons.add_decor(sparse, MeshKit.new(), icon, rng, 0.55)
		_check(sparse.triangle_count() > 0 and sparse.triangle_count() <= decor.triangle_count() + 400,
				"icono '%s': con calidad baja el decorado sigue ahí (%d triángulos)" % [icon, sparse.triangle_count()])
	_check(shapes.size() >= 6, "los iconos son distintos entre sí (%d formas)" % shapes.size())
	var unknown := MeshKit.new()
	_check(WorldIcons.add_icon(unknown, MeshKit.new(), "nada", RandomNumberGenerator.new()) == 4.0 and unknown.is_empty(),
			"un icono desconocido no agrega nada")

	# Figuras de estado.
	var lock := MeshKit.new()
	WorldIcons.add_padlock(lock)
	var lock_box: AABB = lock.commit().get_aabb()
	_check(lock.triangle_count() >= 100 and lock_box.size.y > 1.8 and lock_box.size.y < 3.2,
			"el candado tiene forma (%d triángulos, %.1f de alto)" % [lock.triangle_count(), lock_box.size.y])
	var ring := MeshKit.new()
	WorldIcons.add_ring(ring, 7.7, 0.2, Color.WHITE, 32)
	var ring_box: AABB = ring.commit().get_aabb()
	_check(ring.triangle_count() >= 128 and absf(ring_box.size.x - 15.4) < 0.9 and ring_box.size.y < 0.8,
			"el aro de luz es plano y mide lo que debe (%.1f de ancho)" % ring_box.size.x)
	var star := MeshKit.new()
	WorldIcons.add_star(star, 1.5)
	_check(star.triangle_count() >= 10, "la estrella de región completada tiene forma (%d triángulos)" % star.triangle_count())
	var arrow := MeshKit.new()
	WorldIcons.add_arrow(arrow)
	var arrow_box: AABB = arrow.commit().get_aabb()
	_check(arrow.triangle_count() >= 10 and absf(arrow_box.position.y) < 0.01 and arrow_box.size.y > 3.0,
			"la flecha apunta hacia abajo con la punta en el origen")

	# El mundo completo se construye en cada calidad y cabe en el presupuesto del teléfono.
	var totals: Dictionary = {}
	for quality in [0, 1, 2]:
		var built := WorldMapBuilder.new()
		root.add_child(built)
		built.build(int(quality))
		totals[int(quality)] = _triangles_of(built)
		var meshes: int = _count_nodes(built, "MeshInstance3D")
		var labels: int = _count_nodes(built, "Label3D")
		_check(built.region_ids().size() == 7 and labels == 7,
				"calidad %d: se construyen las 7 regiones con su nombre (%d rótulos)" % [int(quality), labels])
		_check(meshes > 60 and meshes < 170,
				"calidad %d: %d objetos de malla (cada uno es una orden de dibujo)" % [int(quality), meshes])
		var sun := built.get_node_or_null("Sun") as DirectionalLight3D
		_check(built.get_node_or_null("WorldEnvironment") != null and sun != null and not sun.shadow_enabled,
				"calidad %d: el mundo tiene su propia luz y no usa sombras (más fluido en el teléfono)" % int(quality))
		root.remove_child(built)
		built.free()
	_check(int(totals[0]) > 20000 and int(totals[2]) < 110000 and int(totals[0]) <= int(totals[1]) and int(totals[1]) <= int(totals[2]),
			"los triángulos del mundo suben con la calidad: %d, %d, %d" % [int(totals[0]), int(totals[1]), int(totals[2])])


func _wheel_event(up: bool, emulated: bool = false) -> InputEventMouseButton:
	return _mouse_button_event(MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(900.0, 500.0), emulated)


func _mouse_button_event(button: int, pressed: bool, at: Vector2, emulated: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button as MouseButton
	event.pressed = pressed
	event.position = at
	event.global_position = at
	if emulated:
		event.device = InputEvent.DEVICE_ID_EMULATION
	return event


func _mouse_move_event(at: Vector2, relative: Vector2, emulated: bool = false) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	if emulated:
		event.device = InputEvent.DEVICE_ID_EMULATION
	return event


func _touch_event(index: int, pressed: bool, at: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = at
	return event


func _drag_event(index: int, at: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	event.relative = relative
	return event


## La cámara del mapa mundial con gestos sintéticos: ratón, rueda, toques, pellizco y límites.
func _test_world_camera() -> void:
	print("-- Cámara del mundo bíblico: gestos táctiles")
	var camera := WorldCamera.new()
	var bounds := Rect2(-92.0, -46.0, 190.0, 92.0)
	camera.configure(bounds, Vector3(3.0, 0.0, 0.0), 124.0)
	var taps: Array = []
	var moves: Array = []
	camera.tapped.connect(func(p: Vector2) -> void: taps.append(p))
	camera.user_moved.connect(func() -> void: moves.append(1))
	_check(is_equal_approx(camera.distance, 124.0) and camera.is_settled(), "la cámara empieza en la vista general")
	var looking: float = (-camera.transform.basis.z).dot((camera.target - camera.transform.origin).normalized())
	_check(looking > 0.999 and camera.transform.origin.y > 50.0 and camera.transform.origin.z > camera.target.z,
			"la cámara mira el mapa desde arriba y desde el sur (%.4f)" % looking)

	# Rueda del ratón.
	var start_distance: float = camera.goal_distance
	camera._unhandled_input(_wheel_event(true))
	_check(camera.goal_distance < start_distance - 5.0, "la rueda hacia arriba acerca la cámara")
	camera._unhandled_input(_wheel_event(false))
	_check(absf(camera.goal_distance - start_distance) < 0.01, "la rueda hacia abajo la aleja otra vez")
	for i in 40:
		camera._unhandled_input(_wheel_event(true))
	_check(is_equal_approx(camera.goal_distance, WorldCamera.MIN_DISTANCE), "el zoom no pasa de la distancia mínima")
	for i in 60:
		camera._unhandled_input(_wheel_event(false))
	_check(is_equal_approx(camera.goal_distance, WorldCamera.MAX_DISTANCE), "el zoom no pasa de la distancia máxima")
	_check(moves.size() >= 100, "cada zoom avisa que el jugador movió la cámara")
	camera.overview(false)
	var unit: float = camera.units_per_pixel()
	_check(unit > 0.05 and unit < 0.2, "la cámara sabe cuánto mundo cubre un píxel (%.4f)" % unit)

	# Arrastre con el ratón.
	var before: Vector3 = camera.goal_target
	camera._unhandled_input(_mouse_button_event(MOUSE_BUTTON_LEFT, true, Vector2(900.0, 500.0)))
	camera._unhandled_input(_mouse_move_event(Vector2(1020.0, 500.0), Vector2(120.0, 0.0)))
	camera._unhandled_input(_mouse_move_event(Vector2(1020.0, 600.0), Vector2(0.0, 100.0)))
	camera._unhandled_input(_mouse_button_event(MOUSE_BUTTON_LEFT, false, Vector2(1020.0, 600.0)))
	var moved: Vector3 = camera.goal_target - before
	_check(absf(moved.x + 120.0 * unit) < 0.05, "arrastrar a la derecha mueve el mapa a la derecha (%.2f)" % moved.x)
	_check(absf(moved.z + 100.0 * unit / sin(deg_to_rad(WorldCamera.PITCH_DEG))) < 0.05,
			"arrastrar hacia abajo mueve el mapa hacia abajo (%.2f)" % moved.z)
	_check(taps.is_empty(), "arrastrar no cuenta como un toque")

	# Toque corto: con el ratón y con pequeños temblores del dedo.
	before = camera.goal_target
	camera._unhandled_input(_mouse_button_event(MOUSE_BUTTON_LEFT, true, Vector2(700.0, 400.0)))
	camera._unhandled_input(_mouse_button_event(MOUSE_BUTTON_LEFT, false, Vector2(700.0, 400.0)))
	_check(taps.size() == 1 and taps[0] == Vector2(700.0, 400.0), "un clic sin mover avisa el toque con su posición")
	camera._unhandled_input(_mouse_button_event(MOUSE_BUTTON_LEFT, true, Vector2(700.0, 400.0)))
	camera._unhandled_input(_mouse_move_event(Vector2(712.0, 406.0), Vector2(12.0, 6.0)))
	camera._unhandled_input(_mouse_button_event(MOUSE_BUTTON_LEFT, false, Vector2(712.0, 406.0)))
	_check(taps.size() == 2 and camera.goal_target.is_equal_approx(before), "un temblor pequeño sigue siendo un toque y no mueve el mapa")

	# El ratón emulado por los toques se ignora (los toques ya se atienden como toques).
	var zoom_before: float = camera.goal_distance
	camera._unhandled_input(_mouse_button_event(MOUSE_BUTTON_LEFT, true, Vector2(500.0, 500.0), true))
	camera._unhandled_input(_mouse_button_event(MOUSE_BUTTON_LEFT, false, Vector2(500.0, 500.0), true))
	camera._unhandled_input(_wheel_event(true, true))
	_check(taps.size() == 2 and is_equal_approx(camera.goal_distance, zoom_before), "los eventos de ratón emulados por toques se ignoran")

	# Un dedo: toque y arrastre.
	camera._unhandled_input(_touch_event(0, true, Vector2(500.0, 300.0)))
	camera._unhandled_input(_touch_event(0, false, Vector2(500.0, 300.0)))
	_check(taps.size() == 3 and taps[2] == Vector2(500.0, 300.0), "un toque corto con el dedo avisa su posición")
	before = camera.goal_target
	camera._unhandled_input(_touch_event(0, true, Vector2(500.0, 300.0)))
	camera._unhandled_input(_drag_event(0, Vector2(650.0, 300.0), Vector2(150.0, 0.0)))
	camera._unhandled_input(_drag_event(0, Vector2(700.0, 300.0), Vector2(50.0, 0.0)))
	camera._unhandled_input(_touch_event(0, false, Vector2(700.0, 300.0)))
	_check(absf((camera.goal_target.x - before.x) + 200.0 * unit) < 0.05 and taps.size() == 3,
			"un dedo arrastra el mapa y no cuenta como toque (%.2f)" % (camera.goal_target.x - before.x))

	# Dos dedos: pellizco para acercar y para alejar.
	camera.overview(false)
	var pinch_start: float = camera.goal_distance
	camera._unhandled_input(_touch_event(0, true, Vector2(600.0, 500.0)))
	camera._unhandled_input(_touch_event(1, true, Vector2(800.0, 500.0)))
	camera._unhandled_input(_drag_event(1, Vector2(1000.0, 500.0), Vector2(200.0, 0.0)))
	_check(absf(camera.goal_distance - pinch_start * 0.5) < 0.5, "separar los dedos acerca la cámara (%.1f)" % camera.goal_distance)
	camera._unhandled_input(_drag_event(1, Vector2(800.0, 500.0), Vector2(-200.0, 0.0)))
	_check(absf(camera.goal_distance - pinch_start) < 0.5, "juntar los dedos aleja la cámara (%.1f)" % camera.goal_distance)
	camera._unhandled_input(_touch_event(1, false, Vector2(800.0, 500.0)))
	camera._unhandled_input(_touch_event(0, false, Vector2(600.0, 500.0)))
	_check(taps.size() == 3, "un pellizco no cuenta como toque")
	camera._unhandled_input(_touch_event(0, true, Vector2(300.0, 300.0)))
	camera._unhandled_input(_touch_event(0, false, Vector2(300.0, 300.0)))
	_check(taps.size() == 4, "después del pellizco los toques vuelven a funcionar")

	# Límites del mapa.
	camera.pan_by(Vector2(-100000.0, -100000.0))
	_check(is_equal_approx(camera.goal_target.x, bounds.end.x) and is_equal_approx(camera.goal_target.z, bounds.end.y),
			"no se puede arrastrar más allá del borde este y sur")
	camera.pan_by(Vector2(100000.0, 100000.0))
	_check(is_equal_approx(camera.goal_target.x, bounds.position.x) and is_equal_approx(camera.goal_target.z, bounds.position.y),
			"no se puede arrastrar más allá del borde oeste y norte")

	# Vuelo hasta una región: la región queda un poco a la derecha del centro.
	camera.overview(false)
	camera.focus_on(Vector3(30.0, 4.0, 10.0), 50.0)
	_check(is_equal_approx(camera.goal_distance, 50.0) and absf(camera.goal_target.x - 20.0) < 0.001
			and absf(camera.goal_target.z - 10.0) < 0.001, "focus_on apunta al lado izquierdo de la región")
	_check(not camera.is_settled(), "la cámara todavía no llegó")
	var last_gap: float = camera.target.distance_to(camera.goal_target)
	var smooth: bool = true
	for i in 12:
		camera._process(0.05)
		var gap: float = camera.target.distance_to(camera.goal_target)
		if gap > last_gap + 0.0001:
			smooth = false
		last_gap = gap
	_check(smooth and last_gap < 25.0, "la cámara se acerca a la meta sin pasarse")
	for i in 60:
		camera._process(0.05)
	_check(camera.is_settled(), "la cámara termina de llegar con el tiempo")
	camera.overview(true)
	camera.snap()
	_check(camera.target.is_equal_approx(Vector3(3.0, 0.0, 0.0)) and is_equal_approx(camera.distance, 124.0), "VISTA vuelve a la vista general")
	camera.free()


## La pantalla MUNDO BÍBLICO con el motor real: regiones, estados, toques de verdad, desbloqueos,
## insignias y apertura de tableros. Termina en la pantalla del mundo.
func _test_world_screen() -> void:
	print("-- Mundo bíblico: la pantalla (regiones, estados, toques, desbloqueos, insignias y tableros)")
	var original_size: Vector2i = root.size
	if original_size.x < 1280 or original_size.y < 720:
		root.size = Vector2i(1920, 1080)
	_progress.reset(false)
	_state.last_progress = {}
	_state.selected_map_id = "eden"
	if await _open_world():
		await _world_first_day()
		await _world_taps_and_gestures()
		await _world_progress_and_boards()
		await _world_celebration()
		await _world_badges()
		await _world_list_and_back()
	_progress.reset(false)
	_state.last_progress = {}
	_state.selected_map_id = "eden"
	if root.size != original_size:
		root.size = original_size
	if not _arrived("world"):
		await _open_world()


## Abre (o vuelve a abrir) el mapa mundial y espera a que termine de construirse.
func _open_world() -> bool:
	await _wait_until(_idle_router, 10.0)
	_router.go_to("world")
	if not await _wait_until(_arrived.bind("world"), 15.0):
		_check(false, "el mundo bíblico se abre")
		return false
	if not await _wait_until(_world_ready, 15.0):
		_check(false, "el mundo bíblico termina de construirse")
		return false
	return true


func _world_ready() -> bool:
	var scene: Node = current_scene
	if scene == null or not _arrived("world"):
		return false
	return bool(scene.is_built())


func _world_camera() -> WorldCamera:
	var scene: Node = current_scene
	if scene == null or not _arrived("world"):
		return null
	var found: WorldCamera = scene.camera()
	return found


func _world_flown() -> bool:
	var cam: WorldCamera = _world_camera()
	return cam != null and cam.goal_distance < cam.home_distance - 20.0 and cam.is_settled()


func _world_selected(map_id: String) -> bool:
	var scene: Node = current_scene
	return scene != null and _arrived("world") and str(scene.selected_id()) == map_id


func _world_celebrated() -> bool:
	var scene: Node = current_scene
	return scene != null and _arrived("world") and not bool(scene.is_celebrating())


func _world_banner_visible() -> bool:
	var scene: Node = current_scene
	if scene == null:
		return false
	var banner := scene.get_node_or_null("%BannerPanel") as Control
	return banner != null and banner.visible


## Un toque corto con el dedo, entregado a la ventana como lo haría el sistema (pasa por los
## paneles de la interfaz y llega a la cámara solo si nada los detiene).
func _push_tap(at: Vector2) -> void:
	root.push_input(_touch_event(0, true, at), true)
	root.push_input(_touch_event(0, false, at), true)


## Verdadero si un panel o botón de la interfaz tapa ese punto de la pantalla.
func _covered_by_ui(point: Vector2) -> bool:
	var scene: Node = current_scene
	if scene == null:
		return false
	for path in ["%Info", "%Tools", "%ProgressPanel"]:
		var control := scene.get_node_or_null(path) as Control
		if control != null and control.visible and control.get_global_rect().has_point(point):
			return true
	var back := scene.find_child("BackButton", true, false) as Control
	return back != null and back.get_global_rect().has_point(point)


func _texts_under(node: Node) -> PackedStringArray:
	var found := PackedStringArray()
	if node is Label:
		found.append((node as Label).text)
	for child in node.get_children():
		found.append_array(_texts_under(child))
	return found


## Primer día: solo el primer mundo está abierto; el panel, el avance y la cámara lo reflejan.
func _world_first_day() -> void:
	var screen: Node = current_scene
	var world: WorldMapBuilder = screen.world()
	var camera: WorldCamera = screen.camera()
	_check(world != null and camera != null, "la pantalla tiene el mapa 3D y su cámara")
	if world == null or camera == null:
		return
	var view: Rect2 = root.get_visible_rect()
	_check(view.size.x >= 1280.0 and view.size.y >= 720.0, "la prueba tiene una pantalla de tamaño real (%s)" % str(view.size))

	_check(world.region_ids() == MAP_ORDER, "el mapa muestra los 7 mundos en el orden del viaje")
	var names_ok: bool = true
	var status_ok: bool = true
	var lights_ok: bool = true
	var roads_closed: bool = true
	for id in MAP_ORDER:
		var first: bool = id == "eden"
		var label: Label3D = world.label_of(id)
		if label == null or label.text != MapCatalog.name_of(id):
			names_ok = false
		var wanted: String = "available" if first else "locked"
		if world.status_of(id) != wanted or world.is_lock_visible(id) == first:
			status_ok = false
		if world.is_halo_visible(id) != first or world.is_star_visible(id):
			lights_ok = false
		if not first and world.is_road_open(id):
			roads_closed = false
	_check(names_ok, "cada mundo lleva su nombre flotando sobre el icono")
	_check(status_ok, "el Edén aparece abierto y los otros 6 mundos, con candado")
	_check(lights_ok, "solo el mundo abierto tiene aro de luz y ninguno tiene estrella todavía")
	_check(roads_closed, "los caminos que llevan a mundos cerrados están apagados")
	_check(world.is_arrow_visible() and world.next_id == "eden", "la flecha dorada señala el próximo mundo")
	var world_sound: Node = screen.get_node_or_null("Ambience")
	_check(world_sound != null and str(world_sound.get("kind")) == "sea" and bool(world_sound.get("playing")),
			"el mapa mundial suena: oleaje de fondo")
	_check(str(screen.selected_id()) == "eden" and world.is_selector_visible("eden") and not world.is_selector_visible("arca_noe"),
			"el Edén está elegido al empezar")
	var triangles: int = _triangles_of(world)
	var meshes: int = _count_nodes(world, "MeshInstance3D")
	_check(triangles > 20000 and triangles < 110000, "el mundo 3D tiene %d triángulos (tope para el teléfono: 110 mil)" % triangles)
	_check(meshes < 170, "el mundo 3D usa %d objetos de malla (cada uno es una orden de dibujo)" % meshes)

	# Panel de información y avance del viaje.
	var name_label := _node("%RegionNameLabel") as Label
	var ref_label := _node("%RegionRefLabel") as Label
	var status_label := _node("%RegionStatusLabel") as Label
	var detail_label := _node("%RegionDetailLabel") as Label
	var stats_label := _node("%RegionStatsLabel") as Label
	var badge_label := _node("%RegionBadgeLabel") as Label
	var play := _node("%PlayRegionButton") as Button
	var progress_label := _node("%ProgressLabel") as Label
	var bar := _node("%ProgressBar") as ProgressBar
	var journey := _node("%JourneyLabel") as Label
	if name_label == null or ref_label == null or status_label == null or detail_label == null or stats_label == null \
			or badge_label == null or play == null or progress_label == null or bar == null or journey == null:
		return
	_check(name_label.text == "Jardín del Edén" and ref_label.text == "Génesis 2:8-17" and status_label.text == "DISPONIBLE"
			and not detail_label.text.is_empty(), "el panel cuenta el mundo elegido (%s · %s)" % [name_label.text, status_label.text])
	_check(not play.disabled and play.text == "JUGAR", "JUGAR está activo en el primer mundo")
	_check(stats_label.text.contains("Aún no has jugado") and badge_label.text.contains("pendiente")
			and badge_label.text.contains("Premio: %d" % MapCatalog.reward_stars_of("eden")),
			"el panel muestra que falta jugar y la insignia pendiente con su premio")
	_check(progress_label.text.contains("0 de 7") and bar.value == 0.0 and bar.max_value == 7.0,
			"el avance del viaje empieza en 0 de 7 (%s)" % progress_label.text)
	_check(journey.text.contains("0 estrellas") and journey.text.contains("0 de 11 insignias"),
			"las estrellas y las insignias del viaje empiezan en cero (%s)" % journey.text)

	# La cámara vuela sola hasta el mundo elegido.
	_check(await _wait_until(_world_flown, 10.0), "la cámara vuela sola hasta el mundo elegido")
	_check(str(screen.pick_region(screen.screen_position_of("eden"))) == "eden", "el Edén queda a la vista y se puede tocar")

	# Vista general: los 7 mundos a la vista, separados y sin paneles encima.
	camera.overview(false)
	var inside_ok: bool = true
	var free_ok: bool = true
	var picks_ok: bool = true
	var points: Array[Vector2] = []
	for id in MAP_ORDER:
		var at: Vector2 = screen.screen_position_of(id)
		points.append(at)
		if not view.grow(-24.0).has_point(at):
			inside_ok = false
		if _covered_by_ui(at):
			free_ok = false
		if str(screen.pick_region(at)) != id:
			picks_ok = false
	var closest: float = 1000000.0
	for i in points.size():
		for j in range(i + 1, points.size()):
			closest = minf(closest, points[i].distance_to(points[j]))
	_check(inside_ok, "en la vista general se ven los 7 mundos dentro de la pantalla")
	_check(free_ok, "en la vista general ningún panel ni botón tapa un mundo")
	_check(picks_ok, "tocar el icono de cada mundo elige ese mundo")
	_check(closest > 160.0, "los mundos se ven bien separados (%.0f px entre los más cercanos)" % closest)
	_check(str(screen.pick_region(Vector2(-500.0, -500.0))) == "", "tocar fuera del mapa no elige ningún mundo")


## Toques, arrastre, pellizco, rueda y botones de zoom, entregados como lo hace el sistema.
func _world_taps_and_gestures() -> void:
	var screen: Node = current_scene
	var world: WorldMapBuilder = screen.world()
	var camera: WorldCamera = screen.camera()
	if world == null or camera == null:
		return
	var view: Rect2 = root.get_visible_rect()
	var name_label := _node("%RegionNameLabel") as Label
	var status_label := _node("%RegionStatusLabel") as Label
	var detail_label := _node("%RegionDetailLabel") as Label
	var stats_label := _node("%RegionStatsLabel") as Label
	var play := _node("%PlayRegionButton") as Button
	var hint := _node("%HintLabel") as Label
	if name_label == null or status_label == null or detail_label == null or stats_label == null or play == null or hint == null:
		return

	# Un toque sobre un mundo cerrado lo elige y explica qué falta; otro toque no abre el tablero.
	camera.overview(false)
	_push_tap(screen.screen_position_of("arca_noe"))
	_check(await _wait_until(_world_selected.bind("arca_noe"), 3.0), "tocar el Arca de Noé (cerrada) la elige")
	_check(world.is_selector_visible("arca_noe") and not world.is_selector_visible("eden"), "el aro de selección pasa al Arca de Noé")
	_check(name_label.text == "Arca de Noé" and status_label.text == "BLOQUEADO"
			and detail_label.text == MapCatalog.requirement_text("arca_noe") and detail_label.text.contains("Jardín del Edén"),
			"un mundo cerrado dice qué hay que completar (%s)" % detail_label.text)
	_check(play.disabled and play.text == "BLOQUEADO" and stats_label.text.is_empty() and not stats_label.visible,
			"un mundo cerrado no se puede jugar ni muestra estadísticas")
	_check(await _wait_until(_world_flown, 8.0), "la cámara vuela hasta el mundo tocado")
	_push_tap(screen.screen_position_of("arca_noe"))
	await create_timer(0.4).timeout
	_check(_arrived("world") and str(_state.selected_map_id) == "eden", "otro toque sobre un mundo cerrado no abre su tablero")
	_check(hint.text == MapCatalog.requirement_text("arca_noe"), "el aviso repite qué hay que completar (%s)" % hint.text)

	# Tocar el vacío no cambia nada; arrastrar mueve el mapa sin elegir ni abrir nada.
	var chosen: String = str(screen.selected_id())
	_push_tap(Vector2(view.size.x * 0.5, 150.0))
	_check(str(screen.selected_id()) == chosen and _arrived("world"), "tocar el mapa vacío no cambia la selección")
	camera.overview(false)
	var start_target: Vector3 = camera.goal_target
	root.push_input(_touch_event(0, true, Vector2(700.0, 450.0)), true)
	root.push_input(_drag_event(0, Vector2(850.0, 450.0), Vector2(150.0, 0.0)), true)
	root.push_input(_drag_event(0, Vector2(1000.0, 450.0), Vector2(150.0, 0.0)), true)
	root.push_input(_touch_event(0, false, Vector2(1000.0, 450.0)), true)
	_check(camera.goal_target.x < start_target.x - 20.0 and str(screen.selected_id()) == chosen,
			"un dedo que arrastra recorre el mapa (%.1f) sin elegir nada" % (camera.goal_target.x - start_target.x))
	camera.overview(false)
	var pinch_start: float = camera.goal_distance
	root.push_input(_touch_event(0, true, Vector2(800.0, 450.0)), true)
	root.push_input(_touch_event(1, true, Vector2(1000.0, 450.0)), true)
	root.push_input(_drag_event(1, Vector2(1200.0, 450.0), Vector2(200.0, 0.0)), true)
	root.push_input(_touch_event(1, false, Vector2(1200.0, 450.0)), true)
	root.push_input(_touch_event(0, false, Vector2(800.0, 450.0)), true)
	_check(camera.goal_distance < pinch_start * 0.6 and str(screen.selected_id()) == chosen,
			"separar dos dedos acerca la cámara (%.0f → %.0f)" % [pinch_start, camera.goal_distance])
	camera.overview(false)
	root.push_input(_wheel_event(true), true)
	_check(camera.goal_distance < camera.home_distance - 5.0, "la rueda del ratón también acerca la cámara")

	# Botones de zoom y vista general.
	var zoom_in := _node("%ZoomInButton") as Button
	var zoom_out := _node("%ZoomOutButton") as Button
	var view_button := _node("%ViewButton") as Button
	if zoom_in == null or zoom_out == null or view_button == null:
		return
	camera.overview(false)
	zoom_in.pressed.emit()
	_check(absf(camera.goal_distance - camera.home_distance * 0.7) < 0.1, "el botón + acerca la cámara")
	zoom_out.pressed.emit()
	_check(absf(camera.goal_distance - camera.home_distance) < 0.1, "el botón - la aleja")
	for i in 3:
		zoom_in.pressed.emit()
	camera.goal_target = Vector3(40.0, 0.0, -20.0)
	view_button.pressed.emit()
	_check(absf(camera.goal_distance - camera.home_distance) < 0.01 and camera.goal_target.is_equal_approx(camera.home_target),
			"VISTA vuelve a la vista general")

	# Cada mundo se elige tocándolo, y el panel muestra sus datos del catálogo.
	var selected_ok: bool = true
	var info_ok: bool = true
	var ref_label := _node("%RegionRefLabel") as Label
	for id in MAP_ORDER:
		camera.overview(false)
		_push_tap(screen.screen_position_of(id))
		var locked: bool = id != "eden"
		if str(screen.selected_id()) != id or not world.is_selector_visible(id):
			selected_ok = false
		if name_label.text != MapCatalog.name_of(id) or ref_label.text != str(MapCatalog.find_map(id)["reference"]) \
				or (status_label.text == "BLOQUEADO") != locked or play.disabled != locked:
			info_ok = false
	_check(selected_ok, "tocar cada uno de los 7 mundos lo elige")
	_check(info_ok, "el panel muestra el nombre, la referencia y el estado de cada mundo")
	screen.select_region("eden")


## Completar el Edén con el mapa abierto, y abrir tableros tocando la región y con JUGAR.
func _world_progress_and_boards() -> void:
	var screen: Node = current_scene
	var world: WorldMapBuilder = screen.world()
	var camera: WorldCamera = screen.camera()
	if world == null or camera == null:
		return
	var name_label := _node("%RegionNameLabel") as Label
	var status_label := _node("%RegionStatusLabel") as Label
	var stats_label := _node("%RegionStatsLabel") as Label
	var badge_label := _node("%RegionBadgeLabel") as Label
	var play := _node("%PlayRegionButton") as Button
	var progress_label := _node("%ProgressLabel") as Label
	var bar := _node("%ProgressBar") as ProgressBar
	var journey := _node("%JourneyLabel") as Label
	if name_label == null or status_label == null or stats_label == null or badge_label == null or play == null \
			or progress_label == null or bar == null or journey == null:
		return

	# Los estados se actualizan solos cuando cambia el progreso.
	var report: Dictionary = _progress.record_match("eden", _fake_summary(240.0, 27, 5, 6, 2))
	var opened: Array = report.get("unlocked_maps", [])
	_check(bool(report.get("ok", false)) and opened == ["arca_noe"], "completar el Edén abre el Arca de Noé (%s)" % str(opened))
	_check(world.status_of("eden") == "completed" and world.is_star_visible("eden") and not world.is_halo_visible("eden"),
			"el Edén completado muestra su estrella y ya no su aro")
	_check(world.status_of("arca_noe") == "available" and not world.is_lock_visible("arca_noe") and world.is_halo_visible("arca_noe"),
			"el Arca de Noé pierde el candado y se ilumina")
	_check(world.is_road_open("arca_noe") and not world.is_road_open("egipto_exodo"), "el camino hacia el Arca se enciende y el siguiente sigue apagado")
	_check(world.next_id == "arca_noe" and world.is_arrow_visible(), "la flecha dorada pasa al Arca de Noé")
	var counts: Vector2i = _progress.data.badge_counts()
	_check(progress_label.text.contains("1 de 7") and bar.value == 1.0, "el avance del viaje sube a 1 de 7 (%s)" % progress_label.text)
	_check(journey.text.contains("%d estrellas del viaje" % int(report["journey_stars"])) and journey.text.contains("%d de %d insignias" % [counts.x, counts.y])
			and counts.x >= 1, "las estrellas y las insignias del viaje se actualizan (%s)" % journey.text)
	_check(status_label.text == "COMPLETADO" and stats_label.text.contains("Completado: 1") and badge_label.text.contains("ganada"),
			"el panel del Edén muestra completado, sus estadísticas y la insignia ganada")

	# Primer toque elige el Arca (ya abierta); el segundo abre su tablero.
	camera.overview(false)
	_push_tap(screen.screen_position_of("arca_noe"))
	_check(await _wait_until(_world_selected.bind("arca_noe"), 3.0), "tocar el Arca de Noé (abierta) la elige")
	_check(status_label.text == "DISPONIBLE" and not play.disabled and play.text == "JUGAR", "el Arca abierta se puede jugar")
	_check(_arrived("world") and str(_state.selected_map_id) == "eden", "un solo toque no abre el tablero")
	await _wait_until(_world_flown, 8.0)
	_push_tap(screen.screen_position_of("arca_noe"))
	_check(await _wait_until(_arrived.bind("board"), 25.0), "un segundo toque sobre el Arca de Noé abre su tablero")
	_check(str(_state.selected_map_id) == "arca_noe", "el tablero abierto es el del mundo tocado")

	# Al volver del tablero, el mundo jugado queda elegido; JUGAR abre el tablero de otro mundo.
	if not await _open_world():
		return
	screen = current_scene
	_check(await _wait_until(_world_selected.bind("arca_noe"), 3.0), "al volver, el último mundo jugado queda elegido")
	screen.select_region("eden")
	play = _node("%PlayRegionButton") as Button
	play.pressed.emit()
	_check(await _wait_until(_arrived.bind("board"), 25.0) and str(_state.selected_map_id) == "eden",
			"el botón JUGAR abre el tablero del mundo elegido")
	if not await _open_world():
		return
	screen = current_scene

	# JUGAR en un mundo cerrado no abre nada.
	screen.select_region("egipto_exodo")
	play = _node("%PlayRegionButton") as Button
	_check(play.disabled, "JUGAR está desactivado en un mundo cerrado")
	play.pressed.emit()
	await create_timer(0.4).timeout
	_check(_arrived("world") and str(_state.selected_map_id) == "eden", "ni siquiera forzando el botón se abre un mundo cerrado")


## Al volver de una partida que abrió un mundo nuevo, el candado salta y se muestra un aviso (una vez).
func _world_celebration() -> void:
	_progress.reset(false)
	var report: Dictionary = _progress.record_match("eden", _fake_summary(240.0, 27, 5, 6, 2))
	_state.last_progress = report
	_state.selected_map_id = "eden"
	if not await _open_world():
		return
	var screen: Node = current_scene
	var world: WorldMapBuilder = screen.world()
	if world == null:
		return
	_check(bool(screen.is_celebrating()), "al volver de una partida que abrió un mundo, el mapa lo celebra")
	_check(world.status_of("arca_noe") == "locked" and world.is_lock_visible("arca_noe") and world.status_of("eden") == "completed",
			"el mundo nuevo se muestra primero con su candado")
	var chosen: String = str(screen.selected_id())
	_push_tap(screen.screen_position_of("jerusalen"))
	_check(str(screen.selected_id()) == chosen, "durante la celebración los toques no cambian la selección")
	_check(await _wait_until(_world_selected.bind("arca_noe"), 6.0), "la cámara va al mundo nuevo")
	_check(await _wait_until(_world_banner_visible, 8.0), "aparece el aviso de mundo nuevo")
	var title := _node("%BannerTitle") as Label
	var detail := _node("%BannerDetail") as Label
	if title != null and detail != null:
		_check(title.text == "¡NUEVO MUNDO ABIERTO!" and detail.text == "Arca de Noé", "el aviso dice cuál mundo se abrió (%s)" % detail.text)
	_check(await _wait_until(_world_celebrated, 10.0), "la celebración termina")
	_check(world.status_of("arca_noe") == "available" and not world.is_lock_visible("arca_noe") and world.is_road_open("arca_noe"),
			"al terminar, el candado desapareció y el camino está encendido")
	_check(bool(_state.last_progress.get("celebrated", false)), "la celebración queda anotada para no repetirse")
	if await _open_world():
		var again: Node = current_scene
		_check(not bool(again.is_celebrating()), "al volver a abrir el mapa no se repite la celebración")


## Pantalla de insignias: se abre, lista las 11, bloquea el mapa de atrás y se cierra de tres formas.
func _world_badges() -> void:
	var screen: Node = current_scene
	var button := _node("%BadgesButton") as Button
	var panel := _node("%BadgesPanel") as Control
	var grid := _node("%BadgeGrid")
	var count_label := _node("%BadgesCountLabel") as Label
	var close_button := _node("%BadgesCloseButton") as Button
	if screen == null or button == null or panel == null or grid == null or count_label == null or close_button == null:
		return
	_check(not panel.visible and not bool(screen.is_badges_open()), "las insignias empiezan cerradas")
	button.pressed.emit()
	_check(bool(screen.is_badges_open()) and panel.visible, "INSIGNIAS abre la pantalla de insignias")
	var badges: Array = _progress.data.all_badges()
	var counts: Vector2i = _progress.data.badge_counts()
	_check(grid.get_child_count() == 11 and badges.size() == 11, "se muestran las 11 insignias (%d)" % grid.get_child_count())
	_check(count_label.text == "%d de %d insignias ganadas" % [counts.x, counts.y] and counts.x >= 1,
			"el contador de insignias coincide con el progreso (%s)" % count_label.text)
	var texts: PackedStringArray = _texts_under(grid)
	var names_ok: bool = true
	for entry in badges:
		var badge: Dictionary = entry
		if not texts.has(str(badge["name"])) or not texts.has(str(badge["text"])):
			names_ok = false
	_check(names_ok, "cada tarjeta muestra el nombre y la condición de su insignia")
	var chosen: String = str(screen.selected_id())
	_push_tap(screen.screen_position_of(chosen))
	await create_timer(0.4).timeout
	_check(_arrived("world") and str(screen.selected_id()) == chosen, "con las insignias abiertas, el mapa de atrás no recibe toques")
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await create_timer(0.4).timeout
	_check(not bool(screen.is_badges_open()) and not panel.visible and _arrived("world"), "el botón atrás de Android cierra las insignias sin salir del mapa")
	button.pressed.emit()
	close_button.pressed.emit()
	_check(not bool(screen.is_badges_open()) and not panel.visible, "CERRAR cierra las insignias")


## LISTA abre la lista de mapas (con su propia prueba) y VOLVER regresa al mapa mundial.
func _world_list_and_back() -> void:
	var list_button := _node("%ListButton") as Button
	if list_button == null:
		return
	# La lista de mapas se arma al abrirse: se parte de una partida nueva, como en el primer día.
	_progress.reset(false)
	list_button.pressed.emit()
	if not await _wait_until(_arrived.bind("maps"), 15.0):
		_check(false, "LISTA abre la lista de mapas")
		return
	await _test_maps_screen()
	var back := current_scene.find_child("BackButton", true, false) as Button
	_check(back != null, "la lista de mapas tiene botón VOLVER")
	if back != null:
		back.pressed.emit()
		_check(await _wait_until(_arrived.bind("world"), 15.0), "VOLVER en la lista de mapas regresa al mapa mundial")


func _test_maps_screen() -> void:
	var list := _node("%MapList")
	var play := _node("%PlayMapButton") as Button
	var status := _node("%MapStatusLabel") as Label
	if list == null or play == null or status == null:
		return
	_progress.reset(false)
	_state.selected_map_id = "eden"
	var maps: Array = MapCatalog.all_maps()
	_check(list.get_child_count() == maps.size(), "la lista de mapas muestra los %d mapas" % maps.size())
	var buttons: Array = list.get_children()
	_check((buttons[0] as Button).text.contains("1. Jardín del Edén") and not (buttons[0] as Button).text.contains("bloqueado"),
			"el primer mapa aparece abierto (%s)" % (buttons[0] as Button).text)
	var locked_marked: bool = true
	for i in range(1, buttons.size()):
		if not (buttons[i] as Button).text.contains("(bloqueado)"):
			locked_marked = false
	_check(locked_marked, "los otros 6 mapas aparecen bloqueados")
	(buttons[1] as Button).pressed.emit()
	_check(play.disabled and status.text.begins_with("BLOQUEADO") and status.text.contains("Jardín del Edén"),
			"un mapa bloqueado explica qué hay que completar (%s)" % status.text)
	_check(str(_state.selected_map_id) == "eden", "elegir un mapa bloqueado no cambia la selección")
	(buttons[0] as Button).pressed.emit()
	_check(not play.disabled and str(_state.selected_map_id) == "eden", "el primer mapa se puede jugar y queda elegido")
	_check(not (_node("%MapNameLabel") as Label).text.is_empty(), "se muestra el nombre del mapa")
	_check((_node("%Swatches") as Node).get_child_count() == 4, "se muestran los 4 colores del tablero")
	_check((_node("%MapBadgeLabel") as Label).text.contains("pendiente"), "se muestra la insignia pendiente del mapa")

	# Al completar un mapa se abre el siguiente (la lista se reconstruye al volver a abrirla).
	_progress.record_match("eden", _fake_summary(240.0, 27, 5, 6, 2))
	_router.go_to("maps")
	if not await _wait_until(_arrived.bind("maps"), 10.0):
		_check(false, "la lista de mapas se vuelve a abrir")
		return
	list = _node("%MapList")
	play = _node("%PlayMapButton") as Button
	if list == null or play == null:
		return
	buttons = list.get_children()
	_check((buttons[0] as Button).text.contains("(completado)") and not (buttons[1] as Button).text.contains("(bloqueado)")
			and (buttons[2] as Button).text.contains("(bloqueado)"), "el primer mapa aparece completado y el segundo se abre")
	(buttons[1] as Button).pressed.emit()
	_check(not play.disabled and str(_state.selected_map_id) == "arca_noe", "el segundo mapa ya se puede elegir")
	(buttons[0] as Button).pressed.emit()
	_check((_node("%MapBadgeLabel") as Label).text.contains("ganada") and (_node("%MapStatsLabel") as Label).text.contains("Completado: 1"),
			"el mapa completado muestra su insignia ganada y sus estadísticas")
	_progress.reset(false)
	_state.selected_map_id = "eden"


func _test_multiplayer_screen() -> void:
	var plus := _node("%PlusButton") as Button
	var minus := _node("%MinusButton") as Button
	var count_label := _node("%CountLabel") as Label
	var player_list := _node("%PlayerList")
	var play := _node("%PlayLocalButton") as Button
	if plus == null or minus == null or count_label == null or player_list == null or play == null:
		return
	_state.set_player_count(1)
	minus.pressed.emit()
	_check(int(_state.player_count) == 1, "no se puede bajar de 1 jugador")
	for expected in [2, 3, 4]:
		plus.pressed.emit()
		_check(int(_state.player_count) == expected and count_label.text == str(expected),
				"el botón + sube a %d jugadores" % expected)
	_check(plus.disabled, "el botón + se desactiva en 4 jugadores")
	plus.pressed.emit()
	_check(int(_state.player_count) == 4, "no se puede pasar de 4 jugadores")
	minus.pressed.emit()
	_check(int(_state.player_count) == 3 and player_list.get_child_count() == 3, "el botón - baja a 3 y la lista se actualiza")
	_check(not play.text.is_empty() and not play.disabled, "el botón JUGAR de la partida local está activo")
	await _online_manager_and_screen()


func _test_characters_screen() -> void:
	var list := _node("%CharacterList")
	var play := _node("%PlayButton") as Button
	var name_label := _node("%NameLabel") as Label
	if list == null or play == null or name_label == null:
		return
	var characters: Array = CharacterCatalog.all_characters()
	_check(list.get_child_count() == characters.size(), "la lista muestra los %d personajes" % characters.size())
	for i in characters.size():
		(list.get_child(i) as Button).pressed.emit()
		_check(str(_state.selected_character_id) == str(characters[i]["id"]) and name_label.text == str(characters[i]["name"]),
				"elegir a %s lo guarda y muestra su nombre" % characters[i]["name"])
	_check(not play.disabled, "el botón JUGAR de la pantalla de personajes está activo")
	(list.get_child(0) as Button).pressed.emit()


func _test_settings_screen() -> void:
	var master := _node("%MasterSlider") as HSlider
	var music := _node("%MusicSlider") as HSlider
	var sfx := _node("%SfxSlider") as HSlider
	var master_label := _node("%MasterValue") as Label
	var quality_row := _node("%QualityRow")
	var fps := _node("%FpsButton") as Button
	var reset := _node("%ResetButton") as Button
	var test_sound := _node("%TestSoundButton") as Button
	if master == null or music == null or sfx == null or master_label == null or quality_row == null \
			or fps == null or reset == null or test_sound == null:
		return
	master.value = 0.35
	music.value = 0.2
	sfx.value = 0.6
	_check(absf(float(_settings.master_volume) - 0.35) < 0.001, "el volumen general cambia")
	_check(absf(float(_settings.music_volume) - 0.2) < 0.001, "el volumen de música cambia")
	_check(absf(float(_settings.sfx_volume) - 0.6) < 0.001, "el volumen de efectos cambia")
	_check(master_label.text == "35%", "el porcentaje del volumen se actualiza")
	_check(quality_row.get_child_count() == 3, "hay 3 niveles de calidad")
	for level in [0, 2, 1]:
		(quality_row.get_child(level) as Button).pressed.emit()
		_check(int(_settings.quality) == level, "la calidad %d se aplica" % level)
	fps.button_pressed = true
	_check(bool(_settings.show_fps), "se activa el contador de FPS")
	fps.button_pressed = false
	_check(not bool(_settings.show_fps), "se desactiva el contador de FPS")
	test_sound.pressed.emit()
	_check(true, "PROBAR SONIDO se ejecuta sin errores")
	_settings.save()
	var saved := ConfigFile.new()
	_check(saved.load("user://settings.cfg") == OK and absf(float(saved.get_value("audio", "master", -1.0)) - 0.35) < 0.001,
			"los ajustes se guardan en user://settings.cfg")
	reset.pressed.emit()
	_check(absf(float(_settings.master_volume) - 0.8) < 0.001 and int(_settings.quality) == 1, "RESTABLECER vuelve a los valores iniciales")
	_test_rules_tab()


# ---------------------------------------------------------------- Ayudas del tablero

func _idle_router() -> bool:
	return not _router.is_transitioning


func _events_of(kind: String) -> Array:
	var found: Array = []
	for entry in _events:
		var event: Array = entry
		if str(event[0]) == kind:
			found.append(event)
	return found


func _has_event(kind: String, count: int = 1) -> bool:
	return _events_of(kind).size() >= count


func _on_turn_started(player_index: int) -> void:
	_events.append(["turn_started", player_index])


func _on_rolled(player_index: int, value: int) -> void:
	_events.append(["rolled", player_index, value])


func _on_moved(player_index: int, tile: int) -> void:
	_events.append(["moved", player_index, tile])


func _on_jumped(player_index: int, kind: String, from_tile: int, to_tile: int) -> void:
	_events.append(["jumped", player_index, kind, from_tile, to_tile])


func _on_challenge_shown(player_index: int, item: Challenge) -> void:
	_events.append(["challenge_shown", player_index, item])


func _on_challenge_resolved(player_index: int, correct: bool) -> void:
	_events.append(["challenge_resolved", player_index, correct])


func _on_turn_ended(player_index: int) -> void:
	_events.append(["turn_ended", player_index])


func _on_special_triggered(player_index: int, result: Dictionary) -> void:
	_events.append(["special", player_index, result])


func _on_match_finished(summary: Dictionary) -> void:
	_events.append(["match_finished", summary])


func _sample_frame() -> void:
	if _sampling and _sample_token != null and int(_flow.shown_tile(_sample_player)) == _sample_tile:
		_samples.append(_sample_token.position)


## Abre el tablero desde el menú con ese número de jugadores y toma sus piezas.
func _enter_board(player_count: int) -> bool:
	# El tablero de pruebas es el del Desierto del Sinaí (4.º mapa): se abren todos solo en esta sesión.
	_progress.unlock_everything_for_session()
	_state.select_map("desierto_sinai")
	_state.select_character(CharacterCatalog.all_ids()[0])
	_state.set_player_count(player_count)
	if not _arrived("main_menu"):
		if not await _go_to_menu():
			_check(false, "se puede volver al menú para abrir el tablero")
			return false
	var play := current_scene.get_node_or_null("%PlayButton") as Button
	if play == null:
		_check(false, "el menú tiene el botón JUGAR")
		return false
	play.pressed.emit()
	var arrived: bool = await _wait_until(_arrived.bind("board"), 15.0)
	_check(arrived, "JUGAR abre el tablero con %d jugador(es)" % player_count)
	if not arrived:
		return false
	return _bind_board()


## Toma las piezas del tablero que está abierto, acelera la partida y se suscribe a sus avisos.
func _bind_board() -> bool:
	var scene: Node = current_scene
	if scene == null or scene.scene_file_path != str(_router.SCENES["board"]):
		_check(false, "hay un tablero abierto")
		return false
	_board = scene.get_node_or_null("%Board")
	_tokens_root = scene.get_node_or_null("%Tokens")
	_camera = scene.get_node_or_null("%BoardCamera")
	_dice = scene.get_node_or_null("%Dice")
	_hud = scene.get_node_or_null("%Hud")
	_flow = scene.get_node_or_null("%Flow")
	_panel = scene.get_node_or_null("%ChallengePanel")
	_pause = scene.get_node_or_null("%PauseMenu")
	_effects_root = scene.get_node_or_null("%Effects")
	var ok: bool = _board != null and _tokens_root != null and _camera != null and _dice != null \
			and _hud != null and _flow != null and _panel != null and _pause != null and _effects_root != null
	_check(ok, "el tablero tiene casillas, fichas, cámara, dado, interfaz, director, panel de desafíos, pausa y efectos")
	if not ok:
		return false
	_flow.speed = GAME_SPEED
	_dice.speed = GAME_SPEED
	_events.clear()
	_flow.turn_started.connect(_on_turn_started)
	_flow.rolled.connect(_on_rolled)
	_flow.moved.connect(_on_moved)
	_flow.jumped.connect(_on_jumped)
	_flow.challenge_shown.connect(_on_challenge_shown)
	_flow.challenge_resolved.connect(_on_challenge_resolved)
	_flow.turn_ended.connect(_on_turn_ended)
	_flow.special_triggered.connect(_on_special_triggered)
	_flow.match_finished.connect(_on_match_finished)
	return true


func _player_name(index: int) -> String:
	return str(_flow.state.get_player(index)["name"])


func _token(index: int) -> Node3D:
	return _tokens_root.get_child(index) as Node3D


## Casilla "tranquila": no es inicio ni meta y no tiene escalera, serpiente, desafío ni casilla especial.
func _is_quiet(layout: BoardLayout, tile: int) -> bool:
	return layout.is_quiet(tile)


## Una casilla de salida tal que "salida + tirada" sea tranquila, buscando desde "from_tile".
func _quiet_start(layout: BoardLayout, roll: int, from_tile: int) -> int:
	var tile: int = maxi(from_tile, 1)
	while tile < layout.last_tile() - 8:
		if _is_quiet(layout, tile + roll):
			return tile
		tile += 1
	return 2


## Hace lo que haría el jugador: responde los desafíos que salgan y toca CONTINUAR, hasta que
## la partida espere la siguiente tirada (o termine). answer_mode: 0 acierta, 1 falla, 2 al azar.
func _drive_until_ready(timeout: float = 40.0, answer_mode: int = 0) -> bool:
	var waited: float = 0.0
	while waited < timeout:
		if _panel.is_open():
			if not _panel.is_answered():
				var pick: int = _panel.challenge.correct
				if answer_mode == 1:
					pick = (_panel.challenge.correct + 1) % maxi(_panel.option_count(), 1)
				elif answer_mode == 2:
					pick = randi_range(0, maxi(_panel.option_count(), 1) - 1)
				_panel.choose(pick)
			elif _panel.continue_visible():
				_panel.continue_pressed()
		elif _flow.is_waiting_for_roll() or _flow.is_finished():
			return true
		await create_timer(0.03).timeout
		waited += 0.03
	return false


## Cada ficha, cada fila de la lista y cada insignia deben mostrar la casilla que dicen las reglas.
func _sync_problems() -> Array[String]:
	var problems: Array[String] = []
	for entry in _flow.state.players:
		var info: Dictionary = entry
		var index: int = int(info["index"])
		var tile: int = int(info["tile"])
		var token: Node3D = _token(index)
		var spot: Vector3 = _flow.token_spot(index, tile)
		if token.position.distance_to(spot) > 0.05:
			problems.append("la ficha %d está en %s y debía estar en %s (casilla %d)" % [index, str(token.position), str(spot), tile])
		if _hud.row_tile(index) != tile:
			problems.append("la lista muestra la casilla %d para el jugador %d (reglas: %d)" % [_hud.row_tile(index), index, tile])
		if _flow.shown_tile(index) != tile:
			problems.append("el director muestra la casilla %d para el jugador %d (reglas: %d)" % [_flow.shown_tile(index), index, tile])
		if token.badge_text() != str(tile):
			problems.append("la insignia del jugador %d dice %s (reglas: %d)" % [index, token.badge_text(), tile])
	return problems


func _check_synced(label: String) -> void:
	var problems: Array[String] = _sync_problems()
	_check(problems.is_empty(), label if problems.is_empty() else "%s: %s" % [label, "; ".join(problems)])


## Dónde cae un punto respecto a una línea quebrada: x = avance (0 a 1), y = distancia a la línea.
func _along_polyline(points: PackedVector3Array, point: Vector3) -> Vector2:
	var lengths := PackedFloat32Array([0.0])
	var total: float = 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
		lengths.append(total)
	var best_distance: float = INF
	var best_fraction: float = 0.0
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var ab: Vector3 = points[i] - a
		var t: float = clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
		var distance: float = point.distance_to(a + ab * t)
		if distance < best_distance:
			best_distance = distance
			best_fraction = (lengths[i - 1] + ab.length() * t) / maxf(total, 0.000001)
	return Vector2(best_fraction, best_distance)


func _press_escape() -> void:
	for pressed in [true, false]:
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.physical_keycode = KEY_ESCAPE
		escape.pressed = bool(pressed)
		Input.parse_input_event(escape)


func _pause_is(open: bool) -> bool:
	return _pause != null and _pause.is_open() == open and paused == open


# ---------------------------------------------------------------- Tablero y partida real

func _test_board_scene() -> void:
	print("-- Tablero 3D")
	_settings.reset_game_rules()
	if not await _enter_board(4):
		return
	_test_board_structure()
	_test_hud_basics()
	await _test_camera_and_dice()
	await _test_effects()
	await _test_turn_and_dice_lock()
	await _test_movement()
	await _test_jumps()
	await _test_challenges()
	await _test_rewards_and_penalties()
	await _test_exact_finish()
	await _test_pause()
	await _test_victory_and_replay()
	await _test_full_match_with_bot()
	await _test_player_counts()
	await _go_to_menu()


## Abre los 7 tableros en la escena real, uno tras otro (como al tocar JUGAR en el mapa mundial), y en cada
## uno comprueba que se arma completo, que suena como su mundo, que cabe en el presupuesto del teléfono y que el
## primer turno funciona: dado, ficha, lista de jugadores y cambio de turno.
func _test_every_board() -> void:
	print("-- Los 7 tableros en la escena real")
	_settings.reset_game_rules()
	_progress.unlock_everything_for_session()
	for map_id in MAP_ORDER:
		var data: Dictionary = MapCatalog.find_map(map_id)
		var title: String = str(data["name"])
		_state.select_map(map_id)
		_state.select_character(CharacterCatalog.all_ids()[0])
		_state.set_player_count(2)
		_router.go_to("board")
		if not await _wait_until(_arrived.bind("board"), 20.0):
			_check(false, "%s: se abre el tablero" % title)
			continue
		if not _bind_board():
			continue
		var layout: BoardLayout = _flow.layout
		var board_data: Dictionary = data["board"]
		_check(str(_state.selected_map_id) == map_id and layout.tile_count() == 100 and _board.tile_count() == 100
				and _board.ladder_count() == (board_data["ladders"] as Array).size()
				and _board.snake_count() == (board_data["snakes"] as Array).size(),
				"%s: tablero de 100 casillas con sus %d escaleras y sus %d serpientes" % [title,
						_board.ladder_count(), _board.snake_count()])
		var marks_ok: bool = true
		for tile in layout.challenge_tiles:
			if not _board.has_challenge_mark(tile):
				marks_ok = false
		for tile in layout.special_tiles():
			if not _board.has_special_mark(tile):
				marks_ok = false
		_check(marks_ok and layout.challenge_tiles.size() >= 10 and layout.special_tiles().size() >= 6,
				"%s: %d desafíos y %d casillas especiales, todos marcados" % [title,
						layout.challenge_tiles.size(), layout.special_tiles().size()])
		var map_line := _hud.get_node_or_null("%MapLine") as Label
		_check(map_line != null and map_line.text.contains(title) and map_line.text.contains(str(data["reference"])),
				"%s: la interfaz dice el mundo y su referencia bíblica" % title)
		var sound: Node = current_scene.get_node_or_null("Ambience")
		var wanted_sound: String = str(data["ambience"]["sound"])
		_check(sound != null and str(sound.get("kind")) == wanted_sound and bool(sound.get("playing")),
				"%s: suena su ambiente ('%s')" % [title, wanted_sound])
		var triangles: int = _triangles_of(current_scene)
		var meshes: int = _count_nodes(current_scene, "MeshInstance3D")
		print("  %s: %d mallas y %d triángulos en total" % [title, meshes, triangles])
		_check(triangles < 120000 and meshes < 300,
				"%s: cabe en el presupuesto del teléfono (%d triángulos, %d mallas)" % [title, triangles, meshes])

		var roll_button := _hud.get_node_or_null("%RollButton") as Button
		if roll_button == null:
			_check(false, "%s: hay botón LANZAR DADO" % title)
			continue
		_events.clear()
		roll_button.pressed.emit()
		var rolled: bool = await _wait_until(_has_event.bind("rolled"), 10.0)
		var ready: bool = await _drive_until_ready()
		var tile_after: int = int(_flow.state.get_player(0)["tile"])
		_check(rolled and ready and tile_after > 1 and _flow.current_player() == 1,
				"%s: el primer turno funciona (casilla %d, ahora le toca al jugador 2)" % [title, tile_after])
		_check_synced("%s: fichas, lista e insignias coinciden con las reglas" % title)
	_progress.reset(false)
	await _go_to_menu()


func _test_board_structure() -> void:
	print("-- Tablero: casillas, escaleras, serpientes y fichas")
	var board: Node = _board
	_check(board.tile_count() == 100, "el tablero tiene 100 casillas")
	_check(board.ladder_count() == 6, "el tablero tiene 6 escaleras")
	_check(board.snake_count() == 7, "el tablero tiene 7 serpientes")
	for tile in [1, 2, 11, 50, 100]:
		var tile_node: Node = board.tile_node(tile)
		_check(tile_node is Node3D and int(tile_node.get_meta(&"tile", 0)) == tile,
				"la casilla %d existe y tiene su ancla" % tile)
	var tile_surface := board.get_node_or_null("TileSurface") as MeshInstance3D
	var tile_ink := board.get_node_or_null("TileInk") as MeshInstance3D
	_check(tile_surface != null and _triangles_of(tile_surface) >= 100 * 8,
			"las 100 casillas son una sola malla con geometría propia del estilo")
	_check(tile_ink != null and _triangles_of(tile_ink) >= 100 * 12,
			"los 100 números se dibujan como una sola malla de trazos")
	var board_sound: Node = current_scene.get_node_or_null("Ambience")
	var wanted_sound: String = str(MapCatalog.find_map("desierto_sinai")["ambience"]["sound"])
	_check(board_sound != null and str(board_sound.get("kind")) == wanted_sound and bool(board_sound.get("playing"))
			and str(board_sound.get("bus")) == "Music",
			"el tablero suena como su mundo ('%s') por el bus de música" % wanted_sound)
	_check(board.get_node_or_null("StartMarker") != null, "hay un punto de inicio")
	_check(board.get_node_or_null("GoalMarker") != null, "hay una meta")
	_check(board.get_node_or_null("DiceArea") != null, "hay una zona para el dado")
	_check(board.get_node_or_null("Ladders/Ladder_003_022") != null, "existe la escalera 3 -> 22")
	_check(board.get_node_or_null("Snakes/Snake_098_078") != null, "existe la serpiente 98 -> 78")
	var snake_body := board.get_node_or_null("Snakes/Snake_098_078/Body") as MeshInstance3D
	_check(snake_body != null and _winding_ratio(snake_body.mesh as ArrayMesh) > 0.999,
			"la serpiente del tablero tiene las caras hacia afuera")

	var challenge_tiles: Array[int] = _flow.layout.challenge_tiles
	var marked: int = 0
	for tile in challenge_tiles:
		if board.has_challenge_mark(tile):
			marked += 1
	_check(challenge_tiles.size() >= 10 and marked == challenge_tiles.size(),
			"las %d casillas de desafío llevan su signo de pregunta" % challenge_tiles.size())
	_check(not board.has_challenge_mark(2), "una casilla normal no lleva signo de pregunta")
	var special_marked: int = 0
	for tile in _flow.layout.special_tiles():
		if board.has_special_mark(tile):
			special_marked += 1
	_check(special_marked == _flow.layout.special_tiles().size() and special_marked > 0,
			"las %d casillas especiales llevan su icono" % special_marked)

	_check(_tokens_root.get_child_count() == 4, "hay una ficha por jugador (4)")
	var start: Vector3 = board.tile_position(1)
	var positions: Dictionary = {}
	var near_start: bool = true
	for child in _tokens_root.get_children():
		var token := child as Node3D
		positions["%.2f,%.2f" % [token.position.x, token.position.z]] = true
		if Vector2(token.position.x - start.x, token.position.z - start.z).length() > 0.6:
			near_start = false
	_check(near_start, "las fichas están sobre la casilla de inicio")
	_check(positions.size() == 4, "las fichas no se superponen")
	var colors: Dictionary = {}
	for entry in _flow.state.players:
		var info: Dictionary = entry
		colors[(info["color"] as Color).to_html(false)] = true
	_check(colors.size() == 4, "cada jugador tiene su propio color de ficha")
	_check_synced("al empezar, fichas, lista e insignias muestran la casilla 1")


func _test_hud_basics() -> void:
	print("-- Interfaz del tablero")
	var roll_button := _hud.get_node_or_null("%RollButton") as Button
	var pause_button := _hud.get_node_or_null("%PauseButton") as Button
	_check(roll_button != null and roll_button.text == "LANZAR DADO", "hay un botón LANZAR DADO")
	_check(pause_button != null and pause_button.text == "PAUSAR", "hay un botón PAUSAR")
	_check(_hud.row_count() == 4, "la lista muestra a los 4 jugadores con su posición")
	_check(_hud.progress() != null and _hud.progress().visible, "hay un indicador de progreso")
	_check(_hud.turn_text() == "Turno de %s" % _player_name(0), "el panel dice de quién es el turno (%s)" % _hud.turn_text())
	_check(_hud.die_text() == "?", "el recuadro del dado espera la primera tirada")
	for index in 4:
		_check(_hud.row_tile_text(index) == "Casilla 1", "el jugador %d aparece en la casilla 1" % (index + 1))
	_check(_hud.is_roll_enabled() and roll_button != null and not roll_button.disabled, "LANZAR DADO está activo al empezar")
	_check(_flow.is_waiting_for_roll() and _flow.current_player() == 0, "la partida espera la tirada del jugador 1")
	_check(not _panel.is_open(), "el panel de desafíos está cerrado")
	_check(not _pause.is_open() and not paused, "el juego no empieza en pausa")


func _test_camera_and_dice() -> void:
	print("-- Cámara y dado 3D")
	_check(_camera.current, "la cámara 3D del tablero está activa")
	_check(await _wait_until(_camera_settled.bind(_camera), 8.0), "la cámara termina su animación de entrada")
	_camera.orbit_by(Vector2(120.0, -60.0))
	_check(_camera.goal_yaw != _camera.default_yaw, "arrastrar gira la cámara")
	_check(_camera.user_override, "mover la cámara a mano evita que el juego la mueva sola")
	var before: float = _camera.goal_distance
	_camera.zoom_by(0.5)
	_check(_camera.goal_distance < before, "el zoom acerca la cámara")
	_camera.reset_view(false)
	_check(absf(_camera.goal_distance - _camera.default_distance) < 0.001, "VISTA restablece la cámara")
	_check(not _camera.user_override, "VISTA devuelve la cámara al juego")

	# La entrada de la escena empieza baja, para que se vea el paisaje. Si el juego o el jugador mueven la
	# cámara a mitad de camino (por ejemplo, al lanzar el dado enseguida), no puede quedarse en esa vista baja.
	_camera.play_intro()
	_check(_camera.is_intro_running(), "la entrada de la escena está en marcha")
	_check(absf(_camera.pitch - BoardCamera.INTRO_PITCH) < 0.001 and _camera.pitch < _camera.default_pitch - 30.0,
			"la entrada empieza con la cámara baja (%.0f°), mirando el paisaje" % _camera.pitch)
	_check(_camera.distance > _camera.default_distance * 1.4, "la entrada empieza con la cámara alejada")
	_check(_camera.fov > BoardCamera.DEFAULT_FOV + 5.0, "la entrada empieza con el ángulo ancho (%.0f°)" % _camera.fov)
	_camera.focus_on(Vector3.ZERO)
	_check(not _camera.is_intro_running(), "enfocar una ficha detiene la entrada")
	_check(absf(_camera.goal_pitch - _camera.default_pitch) < 0.001 and absf(_camera.goal_yaw - _camera.default_yaw) < 0.001
			and absf(_camera.goal_fov - BoardCamera.DEFAULT_FOV) < 0.001,
			"al interrumpir la entrada, la cámara va a la inclinación, el giro y el ángulo de juego")
	_camera.reset_view(false)
	_camera.play_intro()
	_camera.orbit_by(Vector2.ZERO)
	_check(not _camera.is_intro_running() and absf(_camera.goal_pitch - _camera.default_pitch) < 0.001,
			"un gesto del jugador durante la entrada tampoco deja la cámara baja")
	_camera.reset_view(false)
	_check(not _camera.is_intro_running() and absf(_camera.distance - _camera.default_distance) < 0.001
			and absf(_camera.fov - BoardCamera.DEFAULT_FOV) < 0.001,
			"VISTA después de la entrada deja la cámara y el ángulo en la vista de juego")
	# El jugador puede bajar la cámara casi hasta el horizonte para ver el paisaje, y no más.
	_camera.orbit_by(Vector2(0.0, -2000.0))
	_check(absf(_camera.goal_pitch - BoardCamera.MIN_PITCH) < 0.001 and BoardCamera.MIN_PITCH <= 15.0,
			"arrastrar hacia abajo baja la cámara hasta el límite (%.0f°)" % _camera.goal_pitch)
	_camera.orbit_by(Vector2(0.0, 4000.0))
	_check(absf(_camera.goal_pitch - BoardCamera.MAX_PITCH) < 0.001, "arrastrar hacia arriba sube la cámara hasta el límite (%.0f°)" % _camera.goal_pitch)
	_camera.reset_view(false)

	_dice.speed = 20.0
	for value in range(1, 7):
		var rolled: int = _dice.roll(value)
		_check(rolled == value, "el dado acepta el valor %d" % value)
		_check(await _wait_until(_dice_idle.bind(_dice), 6.0), "el dado %d termina de rodar" % value)
		_check(_dice.up_face() == value, "el dado deja la cara %d hacia arriba" % value)
	var first: int = _dice.roll(2)
	var second: int = _dice.roll(5)
	_check(first == 2 and second == 0, "mientras rueda, el dado ignora un segundo lanzamiento")
	_check(await _wait_until(_dice_idle.bind(_dice), 6.0), "el dado vuelve a quedar libre")
	_check(_dice.up_face() == 2, "el segundo lanzamiento ignorado no cambió el resultado")
	var seen: Dictionary = {}
	var in_range: bool = true
	var faces_match: bool = true
	for _i in 18:
		var random_value: int = _dice.roll()
		if random_value < 1 or random_value > 6:
			in_range = false
		seen[random_value] = true
		await _wait_until(_dice_idle.bind(_dice), 6.0)
		if _dice.up_face() != random_value:
			faces_match = false
	_check(in_range, "los lanzamientos al azar dan siempre del 1 al 6")
	_check(faces_match, "el dado siempre muestra el número que anunció")
	_check(seen.size() >= 3, "los lanzamientos al azar varían (%d números distintos en 18)" % seen.size())
	_dice.speed = GAME_SPEED


func _test_effects() -> void:
	print("-- Efectos visuales")
	var parent := Node3D.new()
	parent.name = "EffectsProbe"
	_effects_root.add_child(parent)
	var made: Array[Node] = []
	made.append(Effects.sparkle_burst(parent, Vector3.ZERO, Effects.GOLD, 6, 2.0, 0.2))
	made.append(Effects.star_shower(parent, Vector3.ZERO, Effects.GOLD, 6, 0.2))
	made.append(Effects.dust_puff(parent, Vector3.ZERO, Color.WHITE, 4, 0.2))
	made.append(Effects.ring_pulse(parent, Vector3.ZERO, Effects.GREEN, 1.0, 0.2))
	made.append(Effects.light_pillar(parent, Vector3.ZERO, Effects.GREEN, 2.0, 0.3))
	made.append(Effects.floating_text(parent, Vector3(0.0, 1.0, 0.0), "+2", Effects.GOLD, 1.0, 1.0, 0.3))
	made.append(Effects.confetti(parent, Vector3(0.0, 3.0, 0.0), Vector3(1.0, 0.1, 1.0), 10, 0.2, false))
	var created: int = 0
	var ids: Array[int] = []
	for node in made:
		if node != null and node.is_inside_tree():
			created += 1
			ids.append(node.get_instance_id())
	_check(created == 7, "los 7 efectos (chispas, estrellas, polvo, aro, columna de luz, texto y confeti) se crean")
	_check(Effects.sparkle_burst(null, Vector3.ZERO, Effects.GOLD) == null, "un efecto sin dónde mostrarse no falla")
	_check(Effects.star_mesh(0.2).get_surface_count() == 1, "la estrella 3D tiene su malla")
	var gone: bool = await _wait_until(_effects_gone.bind(ids), 4.0)
	_check(gone, "los efectos se borran solos al terminar")
	parent.queue_free()


func _effects_gone(ids: Array[int]) -> bool:
	for id in ids:
		if instance_from_id(id) != null:
			return false
	return true


func _test_turn_and_dice_lock() -> void:
	print("-- Turnos y bloqueo del dado")
	for index in 4:
		_check(_token(index).is_active() == (index == 0), "solo la ficha del jugador en turno está marcada (jugador %d)" % (index + 1))
	_check(_hud.row_is_highlighted(0) and not _hud.row_is_highlighted(1), "la lista resalta al jugador en turno")
	_check(_hud.hint_text() == "%s, toca LANZAR DADO" % _player_name(0), "la ayuda nombra al jugador en turno (%s)" % _hud.hint_text())
	for other in [1, 2, 3, -1, 4, 9]:
		_check(not _flow.try_roll(int(other)), "el jugador %d no puede tirar fuera de su turno" % int(other))
	_check(_flow.is_waiting_for_roll() and not _dice.is_rolling and _events_of("rolled").is_empty(),
			"los intentos fuera de turno no mueven el dado ni la partida")

	var roll_button := _hud.get_node_or_null("%RollButton") as Button
	if roll_button == null:
		return
	roll_button.pressed.emit()
	_check(_dice.is_rolling, "LANZAR DADO hace rodar el dado 3D")
	_check(roll_button.disabled and not _hud.is_roll_enabled(), "el botón se bloquea mientras el dado rueda")
	_check(_hud.die_text() == "?", "mientras rueda el recuadro muestra una interrogación")
	_check(not _flow.is_waiting_for_roll(), "la partida deja de esperar tirada")
	_check(not _flow.try_roll(0), "no se puede tirar otra vez mientras rueda")
	_check(not _flow.request_roll(), "tocar de nuevo el botón tampoco lanza otra vez")
	roll_button.pressed.emit()
	_check(_dice.roll(3) == 0, "el dado ignora un nuevo lanzamiento mientras rueda")
	_check(await _wait_until(_has_event.bind("rolled"), 10.0), "el dado termina y se anuncia la tirada")
	var rolled_event: Array = _events_of("rolled")[0]
	var value: int = int(rolled_event[2])
	_check(int(rolled_event[1]) == 0 and value >= 1 and value <= 6, "la tirada es del jugador 1 y vale del 1 al 6 (%d)" % value)
	_check(_dice.up_face() == value, "el dado 3D muestra el mismo número que se anunció")
	_check(_hud.die_text() == str(value), "el número obtenido se muestra en la interfaz (%s)" % _hud.die_text())
	_check(_hud.result_text().contains(str(value)) and _hud.result_text().contains(_player_name(0)),
			"el mensaje dice quién sacó qué (%s)" % _hud.result_text())
	_check(await _drive_until_ready(), "el turno termina y la partida vuelve a esperar")
	_check(_events_of("rolled").size() == 1, "el doble toque lanzó el dado una sola vez")
	_check(_events_of("turn_ended").size() == 1, "se avisó del fin del turno")
	_check(_flow.current_player() == 1, "el turno pasa al jugador 2")
	_check(_hud.turn_text() == "Turno de %s" % _player_name(1), "el panel ahora dice: %s" % _hud.turn_text())
	_check(_hud.row_is_highlighted(1) and not _hud.row_is_highlighted(0), "la lista resalta al nuevo jugador")
	_check(_token(1).is_active() and not _token(0).is_active(), "la marca de turno pasó a la ficha del jugador 2")
	_check(_hud.is_roll_enabled() and not roll_button.disabled, "LANZAR DADO se activa para el siguiente jugador")
	_check(_hud.is_splash_visible(), "se anuncia el turno en grande")
	_check(int(_flow.state.get_player(0)["tile"]) > 1, "la ficha del jugador 1 salió de la casilla 1")
	for index in range(1, 4):
		_check(int(_flow.state.get_player(index)["tile"]) == 1, "la ficha del jugador %d no se movió" % (index + 1))
	_check_synced("tras el primer turno, fichas, lista e insignias coinciden con las reglas")
	_check(not _flow.try_roll(0), "el jugador 1 ya no puede tirar")


func _token_inside_board(token: Node3D) -> bool:
	var size: Vector2 = _flow.layout.board_size()
	return absf(token.position.x) <= size.x * 0.5 + 0.1 and absf(token.position.z) <= size.y * 0.5 + 0.1


## Un turno tranquilo (sin escaleras, serpientes ni desafíos) del jugador que tiene el turno.
func _quiet_turn() -> bool:
	var player: int = _flow.current_player()
	var roll: int = 1 + (player % 3)
	var start_tile: int = _quiet_start(_flow.layout, roll, 12 + player * 11)
	_flow.place_player(player, start_tile)
	if not _flow.try_roll(player, roll):
		return false
	return await _drive_until_ready()


func _restore_rules() -> void:
	_flow.state.options = GameRules.default_options()
	_flow.preferred_challenge_type = ""


func _test_movement() -> void:
	print("-- Movimiento de las fichas")
	var layout: BoardLayout = _flow.layout
	for value in range(1, 7):
		var player: int = _flow.current_player()
		var start_tile: int = _quiet_start(layout, value, 10 + value * 9)
		var final_tile: int = start_tile + value
		_flow.place_player(player, start_tile)
		_events.clear()
		var accepted: bool = _flow.try_roll(player, value)
		_check(accepted, "el jugador %d tira un %d desde la casilla %d" % [player + 1, value, start_tile])
		_check(await _drive_until_ready(), "el movimiento del %d termina y pasa el turno" % value)
		var hops: Array[int] = []
		for entry in _events_of("moved"):
			hops.append(int((entry as Array)[2]))
		var expected: Array[int] = []
		for tile in range(start_tile + 1, final_tile + 1):
			expected.append(tile)
		_check(hops == expected, "con un %d la ficha avanza una casilla por vez %s" % [value, str(hops)])
		_check(int(_flow.state.get_player(player)["tile"]) == final_tile, "con un %d queda en la casilla %d" % [value, final_tile])
		_check(_hud.row_tile_text(player) == "Casilla %d" % final_tile,
				"la lista muestra la casilla actual (%s)" % _hud.row_tile_text(player))
		_check(_token(player).badge_text() == str(final_tile), "el número flotante sobre la ficha muestra la casilla %d" % final_tile)
		_check(_token_inside_board(_token(player)), "la ficha sigue dentro del tablero")
		_check_synced("con un %d, ficha, lista e insignia coinciden con las reglas" % value)
		_check(_events_of("turn_ended").size() == 1 and _events_of("rolled").size() == 1, "con un %d hubo un solo turno y una sola tirada" % value)

	# Nunca se sale del tablero.
	var any_outside: bool = false
	for tile in range(1, layout.last_tile() + 1):
		for slot in 4:
			var spot: Vector3 = _flow.token_spot(slot, tile)
			var size: Vector2 = layout.board_size()
			if absf(spot.x) > size.x * 0.5 + 0.1 or absf(spot.z) > size.y * 0.5 + 0.1:
				any_outside = true
	_check(not any_outside, "ninguna casilla coloca una ficha fuera del tablero")
	var player_now: int = _flow.current_player()
	_flow.place_player(player_now, -5)
	_check(int(_flow.state.get_player(player_now)["tile"]) == 1, "una casilla menor que 1 se corrige a la casilla 1")
	_flow.place_player(player_now, 250)
	_check(int(_flow.state.get_player(player_now)["tile"]) == layout.last_tile(), "una casilla mayor que 100 se corrige a la meta")
	_flow.place_player(player_now, 1)

	# Orden de turnos: 12 turnos seguidos dan tres vueltas completas, siempre en el mismo orden.
	var order: Array[int] = []
	_events.clear()
	for _turn in 12:
		var expected_player: int = _flow.current_player()
		order.append(expected_player)
		_check(await _quiet_turn(), "el turno del jugador %d se juega completo" % (expected_player + 1))
	var rotation_ok: bool = true
	for i in range(1, order.size()):
		if order[i] != (order[i - 1] + 1) % 4:
			rotation_ok = false
	_check(rotation_ok, "los turnos se alternan solos en orden 1, 2, 3, 4 (%s)" % str(order))
	var started: Array = _events_of("turn_started")
	_check(started.size() == 12, "se avisó del comienzo de cada turno (%d)" % started.size())
	_check_synced("tras 12 turnos, fichas, lista e insignias coinciden con las reglas")


# ---------------------------------------------------------------- Escaleras y serpientes

func _test_jumps() -> void:
	print("-- Las 6 escaleras y las 7 serpientes en la partida real")
	var layout: BoardLayout = _flow.layout
	var jumps: Array = []
	for pair in layout.ladders:
		jumps.append([pair.x, pair.y, BoardLayout.KIND_LADDER])
	for pair in layout.snakes:
		jumps.append([pair.x, pair.y, BoardLayout.KIND_SNAKE])
	_check(jumps.size() == 13, "el mapa tiene 6 escaleras y 7 serpientes (%d saltos)" % jumps.size())
	process_frame.connect(_sample_frame)
	_flow.speed = JUMP_SPEED
	var case_number: int = 0
	for entry in jumps:
		var jump: Array = entry
		await _jump_case(int(jump[0]), int(jump[1]), str(jump[2]), 1 + (case_number % 6))
		case_number += 1
	_flow.speed = GAME_SPEED
	process_frame.disconnect(_sample_frame)
	_sampling = false


func _jump_case(from_tile: int, to_tile: int, kind: String, wanted_roll: int) -> void:
	var is_ladder: bool = kind == BoardLayout.KIND_LADDER
	var word: String = "escalera" if is_ladder else "serpiente"
	var label: String = "%s %d -> %d" % [word, from_tile, to_tile]
	var roll: int = mini(wanted_roll, from_tile - 1)
	var start_tile: int = from_tile - roll
	var player: int = _flow.current_player()
	var info: Dictionary = _flow.state.get_player(player)
	var stats: Dictionary = info["stats"]
	var counter: String = "ladders" if is_ladder else "snakes"
	var count_before: int = int(stats[counter])
	_flow.place_player(player, start_tile)
	_events.clear()
	_samples.clear()
	_sample_token = _token(player)
	_sample_player = player
	_sample_tile = to_tile
	_sampling = true
	var accepted: bool = _flow.try_roll(player, roll)
	var ready: bool = await _drive_until_ready()
	_sampling = false
	_check(accepted and ready, "%s: con un %d desde la casilla %d se cae en la base y el turno termina" % [label, roll, start_tile])

	var jumped: Array = _events_of("jumped")
	var jump_ok: bool = jumped.size() == 1
	if jump_ok:
		var event: Array = jumped[0]
		jump_ok = int(event[1]) == player and str(event[2]) == kind and int(event[3]) == from_tile and int(event[4]) == to_tile
	_check(jump_ok, "%s: se avisa del salto con su tipo, su origen y su destino" % label)
	_check(int(info["tile"]) == to_tile, "%s: la ficha termina en la casilla %d" % [label, to_tile])
	_check_synced("%s: ficha, lista e insignia terminan en la casilla %d" % [label, to_tile])
	_check(int(stats[counter]) == count_before + 1, "%s: las estadísticas cuentan el salto" % label)

	var hop_tiles: Array[int] = []
	for entry in _events_of("moved"):
		hop_tiles.append(int((entry as Array)[2]))
	var expected_hops: Array[int] = []
	for tile in range(start_tile + 1, from_tile + 1):
		expected_hops.append(tile)
	expected_hops.append(to_tile)
	_check(hop_tiles == expected_hops, "%s: camina hasta la base y %s hasta la casilla %d %s" % [
			label, "sube" if is_ladder else "baja", to_tile, str(hop_tiles)])

	var polyline: PackedVector3Array = _board.ladder_path(from_tile, to_tile) if is_ladder \
			else _board.snake_path(from_tile, to_tile)
	var middle: int = 0
	var worst_gap: float = 0.0
	for sample in _samples:
		var along: Vector2 = _along_polyline(polyline, sample)
		if along.x > 0.2 and along.x < 0.8:
			middle += 1
			worst_gap = maxf(worst_gap, along.y)
	_check(middle >= 2, "%s: la animación recorre el camino y no se teletransporta (%d cuadros intermedios)" % [label, middle])
	_check(worst_gap < 0.8, "%s: la ficha %s siguiendo %s (se separó %.2f)" % [
			label, "sube" if is_ladder else "baja", "la escalera" if is_ladder else "el cuerpo de la serpiente", worst_gap])
	_check(_token_inside_board(_token(player)), "%s: la ficha termina dentro del tablero" % label)


# ---------------------------------------------------------------- Desafíos

func _test_challenges() -> void:
	print("-- Desafíos bíblicos en la partida real")
	var case_number: int = 0
	for type in Challenge.TYPES:
		for answer_right in [true, false]:
			await _challenge_case(str(type), bool(answer_right), case_number)
			case_number += 1
	_restore_rules()


func _challenge_case(type: String, answer_right: bool, case_number: int) -> void:
	var layout: BoardLayout = _flow.layout
	var tiles: Array[int] = layout.challenge_tiles
	var target: int = tiles[(case_number * 3 + 2) % tiles.size()]
	var roll: int = mini(3, target - 1)
	var player: int = _flow.current_player()
	var info: Dictionary = _flow.state.get_player(player)
	var stats: Dictionary = info["stats"]
	var label: String = "%s, %s" % [str(Challenge.TYPE_TITLES.get(type, type)), "acierta" if answer_right else "falla"]
	var stars_before: int = int(info["stars"])
	var challenges_before: int = int(stats["challenges"])
	_flow.preferred_challenge_type = type
	_flow.place_player(player, target - roll)
	_events.clear()
	var accepted: bool = _flow.try_roll(player, roll)
	var shown: bool = await _wait_until(_has_event.bind("challenge_shown"), 15.0)
	_check(accepted and shown, "[%s] al caer en la casilla %d sale un desafío" % [label, target])
	if not shown:
		await _drive_until_ready()
		return
	var item: Challenge = (_events_of("challenge_shown")[0] as Array)[2] as Challenge
	_check(item != null and item.type == type, "[%s] el desafío es del tipo pedido" % label)
	_check(_panel.is_open() and not _panel.is_answered(), "[%s] el panel se abre y espera la respuesta" % label)
	_check(_flow.is_in_challenge() and not _hud.is_roll_enabled(), "[%s] mientras responde no se puede tirar" % label)
	_check(not _flow.try_roll(player) and not _flow.try_roll((player + 1) % 4), "[%s] nadie puede tirar durante el desafío" % label)
	var expected_options: int = 2 if type == Challenge.TYPE_TRUE_FALSE else 4
	_check(_panel.option_count() == expected_options and item.options.size() == expected_options,
			"[%s] el panel muestra %d opciones" % [label, expected_options])
	_check(not _panel.prompt_text().is_empty(), "[%s] se muestra la pregunta" % label)
	_check(_panel.clue_count() == (3 if type == Challenge.TYPE_CHARACTER else 0), "[%s] las pistas solo salen al adivinar personajes" % label)
	var note := _panel.get_node_or_null("%NoteLabel") as Control
	_check(note != null and note.visible == (type == Challenge.TYPE_COMPLETE_VERSE),
			"[%s] la nota sobre el versículo solo sale al completar versículos" % label)
	var win_label := _panel.get_node_or_null("%WinLabel") as Label
	var lose_label := _panel.get_node_or_null("%LoseLabel") as Label
	_check(win_label != null and win_label.text.begins_with("Si aciertas: +") and win_label.text.contains("avanzas 2 casillas"),
			"[%s] el panel anuncia el premio (%s)" % [label, win_label.text if win_label != null else ""])
	_check(lose_label != null and lose_label.text == "Si fallas: retrocedes 2 casillas",
			"[%s] el panel anuncia el castigo (%s)" % [label, lose_label.text if lose_label != null else ""])

	var pick: int = item.correct if answer_right else (item.correct + 1) % item.options.size()
	_check(_panel.choose(pick), "[%s] se toca una opción" % label)
	_check(not _panel.choose(item.correct), "[%s] una segunda respuesta se ignora" % label)
	_check(_panel.feedback_visible() and _panel.continue_visible(), "[%s] aparece la corrección y el botón CONTINUAR" % label)
	_check(_panel.result_text() == ("¡CORRECTO!" if answer_right else "NO ERA ESA"), "[%s] dice si acertó (%s)" % [label, _panel.result_text()])
	_check(_panel.answer_text() == "Respuesta correcta: %s" % item.correct_text(), "[%s] muestra la respuesta correcta" % label)
	_check(not item.explanation.is_empty() and _panel.explanation_text() == item.explanation, "[%s] muestra la explicación" % label)
	_check(_panel.reference_text().begins_with("Referencia: ") and _panel.reference_text().contains(item.reference),
			"[%s] muestra la referencia bíblica (%s)" % [label, item.reference])
	if answer_right:
		_check(_panel.outcome_text().contains("estrella"), "[%s] el panel anuncia lo ganado (%s)" % [label, _panel.outcome_text()])
	else:
		_check(_panel.outcome_text().begins_with("Retrocedes"), "[%s] el panel anuncia lo perdido (%s)" % [label, _panel.outcome_text()])
	var stars_gain: int = GameRules.stars_for(item.difficulty) if answer_right else 0
	_check(int(info["stars"]) == stars_before + stars_gain, "[%s] las estrellas ganadas son %d" % [label, stars_gain])
	_check(int(stats["challenges"]) == challenges_before + 1, "[%s] las estadísticas cuentan el desafío" % label)

	_check(await _drive_until_ready(), "[%s] tras CONTINUAR el turno termina" % label)
	var resolved: Array = _events_of("challenge_resolved")
	_check(resolved.size() == 1 and bool((resolved[0] as Array)[2]) == answer_right, "[%s] se avisa del resultado" % label)
	var plan: Dictionary = GameRules.plan_shift(layout, target, 2 if answer_right else -2)
	_check(int(info["tile"]) == int(plan["to"]), "[%s] la ficha %s y queda en la casilla %d" % [
			label, "avanza 2" if answer_right else "retrocede 2", int(plan["to"])])
	var expected_hops: Array[int] = []
	for tile in range(target - roll + 1, target + 1):
		expected_hops.append(tile)
	expected_hops.append_array(plan["steps"])
	var hop_tiles: Array[int] = []
	for entry in _events_of("moved"):
		hop_tiles.append(int((entry as Array)[2]))
	_check(hop_tiles == expected_hops, "[%s] camina casilla por casilla, también el premio o el castigo %s" % [label, str(hop_tiles)])
	_check(not _panel.is_open(), "[%s] el panel se cierra" % label)
	_check(_hud.row_stars(player) == int(info["stars"]), "[%s] la lista muestra las estrellas" % label)
	_check(_hud.is_toast_visible() and not _hud.toast_text().is_empty(), "[%s] se muestra un mensaje de ánimo (%s)" % [label, _hud.toast_text()])
	_check_synced("[%s] ficha, lista e insignia coinciden con las reglas" % label)


## Juega un turno que cae en una casilla de desafío y devuelve lo que pasó.
func _play_challenge_turn(type: String, target: int, answer_right: bool) -> Dictionary:
	var player: int = _flow.current_player()
	var info: Dictionary = _flow.state.get_player(player)
	var report: Dictionary = {"ok": false, "player": player, "target": target, "stars_before": int(info["stars"])}
	var roll: int = mini(3, target - 1)
	_flow.preferred_challenge_type = type
	_flow.place_player(player, target - roll)
	_events.clear()
	if not _flow.try_roll(player, roll):
		return report
	if not await _wait_until(_has_event.bind("challenge_shown"), 15.0):
		await _drive_until_ready()
		return report
	var item: Challenge = (_events_of("challenge_shown")[0] as Array)[2] as Challenge
	report["item"] = item
	report["win_text"] = (_panel.get_node("%WinLabel") as Label).text
	report["lose_text"] = (_panel.get_node("%LoseLabel") as Label).text
	var pick: int = item.correct if answer_right else (item.correct + 1) % item.options.size()
	_panel.choose(pick)
	report["outcome"] = _panel.outcome_text()
	report["ready"] = await _drive_until_ready()
	report["final_tile"] = int(info["tile"])
	report["stars_after"] = int(info["stars"])
	report["ok"] = bool(report["ready"])
	return report


func _test_rewards_and_penalties() -> void:
	print("-- Premios y castigos configurables")
	var layout: BoardLayout = _flow.layout
	var target: int = 41
	_check(layout.is_challenge_tile(target), "la casilla %d es de desafío" % target)

	# Solo estrellas, sin castigo.
	_flow.state.options["reward_mode"] = GameRules.REWARD_STARS_ONLY
	_flow.state.options["penalty_mode"] = GameRules.PENALTY_NONE
	var report: Dictionary = await _play_challenge_turn(Challenge.TYPE_MULTIPLE_CHOICE, target, true)
	_check(bool(report["ok"]) and int(report["final_tile"]) == target and int(report["stars_after"]) > int(report["stars_before"]),
			"solo estrellas: acertar da estrellas y la ficha se queda en la casilla %d" % target)
	_check(str(report["win_text"]).begins_with("Si aciertas: +") and not str(report["win_text"]).contains("avanzas"),
			"solo estrellas: el panel no promete avanzar (%s)" % str(report["win_text"]))
	_check(str(report["lose_text"]) == "Si fallas: no pasa nada, ¡sigue intentando!", "sin castigo: el panel lo dice (%s)" % str(report["lose_text"]))
	report = await _play_challenge_turn(Challenge.TYPE_TRUE_FALSE, target, false)
	_check(bool(report["ok"]) and int(report["final_tile"]) == target and int(report["stars_after"]) == int(report["stars_before"]),
			"sin castigo: fallar no mueve la ficha ni quita estrellas")
	_check(str(report["outcome"]) == "Sin penalización", "sin castigo: el panel lo anuncia (%s)" % str(report["outcome"]))

	# Avanzar y retroceder 3 casillas.
	_flow.state.options["reward_mode"] = GameRules.REWARD_ADVANCE
	_flow.state.options["reward_steps"] = 3
	_flow.state.options["penalty_mode"] = GameRules.PENALTY_BACK
	_flow.state.options["penalty_steps"] = 3
	report = await _play_challenge_turn(Challenge.TYPE_EVENT, target, true)
	_check(bool(report["ok"]) and int(report["final_tile"]) == target + 3, "avanzar 3: acertar lleva la ficha a la casilla %d" % (target + 3))
	_check(str(report["win_text"]).contains("avanzas 3 casillas"), "avanzar 3: el panel lo anuncia (%s)" % str(report["win_text"]))
	report = await _play_challenge_turn(Challenge.TYPE_CHARACTER, target, false)
	_check(bool(report["ok"]) and int(report["final_tile"]) == target - 3, "retroceder 3: fallar lleva la ficha a la casilla %d" % (target - 3))
	_check(str(report["lose_text"]) == "Si fallas: retrocedes 3 casillas", "retroceder 3: el panel lo anuncia (%s)" % str(report["lose_text"]))

	# Tirada extra al acertar.
	_flow.state.options["reward_mode"] = GameRules.REWARD_EXTRA_ROLL
	var extra_player: int = _flow.current_player()
	var extra_stats: Dictionary = _flow.state.get_player(extra_player)["stats"]
	var extras_before: int = int(extra_stats["extra_rolls"])
	report = await _play_challenge_turn(Challenge.TYPE_COMPLETE_VERSE, target, true)
	_check(bool(report["ok"]) and str(report["win_text"]).contains("tiras otra vez"), "tirada extra: el panel lo anuncia (%s)" % str(report["win_text"]))
	_check(_flow.current_player() == extra_player, "tirada extra: el mismo jugador vuelve a tirar")
	_check(int(extra_stats["extra_rolls"]) == extras_before + 1, "tirada extra: las estadísticas la cuentan")
	_check(_hud.toast_text().contains("Tirada extra"), "tirada extra: se anuncia en pantalla (%s)" % _hud.toast_text())
	_check(await _quiet_turn(), "tirada extra: se juega la tirada extra")
	_check(_flow.current_player() == (extra_player + 1) % 4, "tirada extra: después sigue el siguiente jugador")

	# Perder el próximo turno al fallar (4 jugadores).
	_flow.state.options["penalty_mode"] = GameRules.PENALTY_SKIP_TURN
	var skipper: int = _flow.current_player()
	var skipper_stats: Dictionary = _flow.state.get_player(skipper)["stats"]
	var skips_before: int = int(skipper_stats["skipped_turns"])
	report = await _play_challenge_turn(Challenge.TYPE_MULTIPLE_CHOICE, target, false)
	_check(bool(report["ok"]) and str(report["lose_text"]) == "Si fallas: pierdes tu próximo turno",
			"perder turno: el panel lo anuncia (%s)" % str(report["lose_text"]))
	_check(int(report["final_tile"]) == target, "perder turno: la ficha no retrocede")
	_check(bool(_flow.state.get_player(skipper)["skip_next"]), "perder turno: queda marcado")
	_check(_hud.row_tile_text(skipper).contains("pierde su próximo turno"), "perder turno: la lista lo avisa (%s)" % _hud.row_tile_text(skipper))
	var order: Array[int] = []
	for _turn in 3:
		order.append(_flow.current_player())
		_check(await _quiet_turn(), "perder turno: juegan los demás")
	_check(order == [(skipper + 1) % 4, (skipper + 2) % 4, (skipper + 3) % 4], "perder turno: juegan los otros tres en orden %s" % str(order))
	_check(_flow.current_player() == (skipper + 1) % 4, "perder turno: el jugador %d se salta su turno" % (skipper + 1))
	_check(int(skipper_stats["skipped_turns"]) == skips_before + 1, "perder turno: las estadísticas lo cuentan")
	_check(not _hud.row_tile_text(skipper).contains("pierde"), "perder turno: el aviso desaparece")
	_check(not bool(_flow.state.get_player(skipper)["skip_next"]), "perder turno: la marca se borra")
	_check_synced("tras perder un turno, fichas, lista e insignias coinciden con las reglas")

	# Desafíos desactivados: caer en una casilla de desafío no abre el panel.
	_restore_rules()
	_flow.state.options["challenges"] = false
	var quiet_player: int = _flow.current_player()
	_flow.place_player(quiet_player, target - 3)
	_events.clear()
	_check(_flow.try_roll(quiet_player, 3), "sin desafíos: se tira normalmente")
	_check(await _drive_until_ready(), "sin desafíos: el turno termina sin abrir el panel")
	_check(_events_of("challenge_shown").is_empty() and int(_flow.state.get_player(quiet_player)["tile"]) == target,
			"sin desafíos: la ficha queda en la casilla de desafío %d" % target)
	_restore_rules()


# ---------------------------------------------------------------- Meta exacta

func _test_exact_finish() -> void:
	print("-- Tirada exacta en la meta")
	var layout: BoardLayout = _flow.layout
	_flow.state.options["exact_finish"] = true
	var player: int = _flow.current_player()
	var info: Dictionary = _flow.state.get_player(player)
	var stats: Dictionary = info["stats"]
	var blocked_before: int = int(stats["blocked"])
	_flow.place_player(player, layout.last_tile() - 3)
	_events.clear()
	_check(_flow.try_roll(player, 6), "con tirada exacta, un 6 desde la casilla %d se intenta" % (layout.last_tile() - 3))
	_check(await _drive_until_ready(), "el turno termina aunque la tirada se pase de la meta")
	_check(int(info["tile"]) == layout.last_tile() - 3 and not _flow.state.finished, "la ficha no se mueve ni gana si se pasa de la meta")
	_check(_events_of("moved").is_empty(), "la ficha no da ningún salto")
	_check(int(stats["blocked"]) == blocked_before + 1, "las estadísticas cuentan la tirada bloqueada")
	_check_synced("tras la tirada bloqueada, ficha, lista e insignia siguen en su casilla")
	_check(_flow.current_player() == (player + 1) % 4, "tras la tirada bloqueada pasa el turno")
	_flow.place_player(player, 1)
	_restore_rules()


# ---------------------------------------------------------------- Pausa

func _restarted(old_scene_id: int) -> bool:
	return _arrived("board") and current_scene.get_instance_id() != old_scene_id


func _test_pause() -> void:
	print("-- Pausa")
	var pause_button := _hud.get_node_or_null("%PauseButton") as Button
	var resume_button := _pause.get_node_or_null("%ResumeButton") as Button
	_check(pause_button != null and resume_button != null, "existen los botones PAUSAR y CONTINUAR")
	if pause_button == null or resume_button == null:
		return
	_check(not paused and not _pause.is_open(), "el juego corre antes de pausar")
	var elapsed_before: float = _flow.state.elapsed
	pause_button.pressed.emit()
	_check(_pause_is(true), "PAUSAR abre el menú y detiene el juego")
	_check(not _flow.try_roll(_flow.current_player()), "en pausa no se puede lanzar el dado")
	await create_timer(0.4).timeout
	_check(absf(_flow.state.elapsed - elapsed_before) < 0.0001, "el reloj de la partida se detiene en pausa")
	_check(_pause.restart_text() == "REINICIAR PARTIDA" and _pause.menu_text() == "MENÚ PRINCIPAL",
			"el menú ofrece reiniciar y volver al menú principal")
	var sound_before: String = _pause.sound_text()
	var volume_before: float = _settings.master_volume
	_pause.press_sound()
	_check(_pause.sound_text() != sound_before, "el botón de sonido cambia de estado (%s)" % _pause.sound_text())
	_pause.press_sound()
	_check(_pause.sound_text() == sound_before and absf(_settings.master_volume - volume_before) < 0.001,
			"silenciar y volver a activar deja el volumen como estaba")
	resume_button.pressed.emit()
	_check(_pause_is(false), "CONTINUAR cierra el menú y reanuda el juego")

	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(_pause_is(true), "el botón atrás de Android abre la pausa")
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(_pause_is(false), "el botón atrás de Android la cierra")
	_press_escape()
	_check(await _wait_until(_pause_is.bind(true), 3.0), "la tecla Esc abre la pausa")
	_press_escape()
	_check(await _wait_until(_pause_is.bind(false), 3.0), "la tecla Esc la cierra")

	# Pausar con el dado en el aire: nada avanza hasta reanudar.
	var player: int = _flow.current_player()
	var start_tile: int = _quiet_start(_flow.layout, 2, 20)
	_flow.place_player(player, start_tile)
	_events.clear()
	_check(_flow.try_roll(player, 2), "se lanza el dado")
	pause_button.pressed.emit()
	_check(_pause_is(true), "se puede pausar con el dado en el aire")
	await create_timer(0.5).timeout
	_check(_dice.is_rolling and _events_of("rolled").is_empty(), "en pausa el dado se queda en el aire")
	_check(int(_flow.state.get_player(player)["tile"]) == start_tile, "en pausa la partida no avanza")
	resume_button.pressed.emit()
	_check(await _drive_until_ready(), "al reanudar la jugada continúa hasta el final del turno")
	_check(int(_flow.state.get_player(player)["tile"]) == start_tile + 2, "la ficha llega a su casilla tras reanudar")
	_check_synced("tras la pausa, fichas, lista e insignias coinciden con las reglas")

	# REINICIAR pide un segundo toque y empieza una partida nueva.
	var old_scene_id: int = current_scene.get_instance_id()
	pause_button.pressed.emit()
	_pause.press_restart()
	_check(_pause.restart_text() != "REINICIAR PARTIDA", "REINICIAR pide confirmar con un segundo toque (%s)" % _pause.restart_text())
	_check(current_scene.get_instance_id() == old_scene_id and _pause.is_open(), "un solo toque no reinicia la partida")
	_pause.press_restart()
	_check(await _wait_until(_restarted.bind(old_scene_id), 15.0), "el segundo toque reinicia la partida")
	_check(not paused, "la pausa no se arrastra a la partida nueva")
	if not _bind_board():
		return
	_check(_flow.state.turn_number == 1 and _flow.current_player() == 0 and not _flow.state.finished, "la partida nueva empieza desde el primer turno")
	_check_synced("la partida nueva empieza con todas las fichas en la casilla 1")
	for index in 4:
		_check(int(_flow.state.get_player(index)["tile"]) == 1 and int(_flow.state.get_player(index)["stars"]) == 0,
				"el jugador %d empieza en la casilla 1 y sin estrellas" % (index + 1))

	# MENÚ PRINCIPAL también pide confirmación.
	var menu_pause := _hud.get_node_or_null("%PauseButton") as Button
	if menu_pause == null:
		return
	menu_pause.pressed.emit()
	_pause.press_menu()
	_check(_pause.menu_text() != "MENÚ PRINCIPAL" and _pause.is_open(), "MENÚ PRINCIPAL pide confirmar con un segundo toque")
	_pause.press_menu()
	_check(await _wait_until(_arrived.bind("main_menu"), 15.0), "el segundo toque vuelve al menú principal")
	_check(not paused, "la pausa no se arrastra al menú")


# ---------------------------------------------------------------- Victoria

func _test_victory_and_replay() -> void:
	print("-- Victoria, estadísticas y jugar otra vez")
	if not _arrived("board"):
		if not await _enter_board(4):
			return
	var layout: BoardLayout = _flow.layout
	var winner: int = _flow.current_player()
	var names: Array[String] = []
	for index in 4:
		names.append(_player_name(index))
	# Los demás quedan en otros lugares para comprobar el orden del podio.
	var spots: Array[int] = [30, 55, 20, 70]
	var expected_order: Array[int] = [winner]
	var others: Array[int] = []
	for index in 4:
		if index != winner:
			_flow.place_player(index, spots[index])
			others.append(index)
	others.sort_custom(_by_spot_desc.bind(spots))
	expected_order.append_array(others)
	_flow.place_player(winner, layout.last_tile() - 3)
	_events.clear()
	_check(_flow.try_roll(winner, 6), "el jugador %d tira un 6 desde la casilla %d (más de lo que falta)" % [winner + 1, layout.last_tile() - 3])
	_check(await _wait_until(_has_event.bind("match_finished"), 30.0), "al llegar a la meta se avisa de que la partida terminó")
	_check(_flow.is_finished() and _flow.state.finished and _flow.state.winner == winner, "el primero en llegar a la meta gana")
	_check(int(_flow.state.get_player(winner)["tile"]) == layout.last_tile(), "con una tirada de más la ficha se detiene en la meta, sin salirse del tablero")
	_check(not _flow.try_roll(winner) and not _flow.try_roll((winner + 1) % 4), "con la partida terminada nadie puede tirar")
	_check(not _hud.is_roll_enabled(), "LANZAR DADO queda bloqueado al terminar")
	_check(await _wait_until(_arrived.bind("victory"), 20.0), "se abre la pantalla de victoria 3D")
	if not _arrived("victory"):
		return

	var scene: Node = current_scene
	var hud: Node = scene.get_node_or_null("%Hud")
	_check(hud != null, "la pantalla de victoria tiene su interfaz")
	if hud == null:
		return
	var summary: Dictionary = _state.last_summary
	_check(bool(summary.get("finished", false)) and int(summary.get("winner", -1)) == winner and str(summary.get("winner_name", "")) == names[winner],
			"el resumen de la partida nombra al ganador (%s)" % str(summary.get("winner_name", "")))
	var progress_report: Dictionary = _state.last_progress
	_check(bool(progress_report.get("ok", false)) and str(progress_report.get("map_id", "")) == "desierto_sinai"
			and bool(progress_report.get("first_completion", false)) and int(progress_report.get("reward_stars", 0)) == 25,
			"la victoria completa el mapa por primera vez y da +25 estrellas del viaje")
	_check(_progress.is_completed("desierto_sinai") and int(_progress.region("desierto_sinai")["completions"]) == 1
			and int(_progress.region("desierto_sinai")["plays"]) >= 1, "el progreso anota la partida del Desierto del Sinaí")
	_check(hud.reward_visible() and hud.reward_title() == "¡Desierto del Sinaí completado!"
			and hud.reward_detail().contains("+25 estrellas del viaje") and hud.reward_detail().contains("Peregrino del Desierto")
			and hud.reward_detail().contains("de 7 mundos"),
			"la pantalla de victoria muestra el mapa completado, la recompensa y la insignia (%s)" % hud.reward_detail())
	var world_button := hud.get_node_or_null("%WorldButton") as Button
	_check(world_button != null and world_button.text == "MUNDO BÍBLICO", "la victoria tiene el botón MUNDO BÍBLICO")
	_check(hud.progress_text({}).is_empty() and hud.progress_text({"ok": true, "first_completion": false, "new_badges": [], "unlocked_maps": []}).is_empty(),
			"si no hay nada nuevo no se muestra recompensa")
	var sample_text: Dictionary = hud.progress_text({"ok": true, "map_id": "eden", "first_completion": true, "reward_stars": 10,
			"new_badges": [{"name": "Guardián del Huerto"}], "unlocked_maps": ["arca_noe"], "completed": 1, "total": 7})
	_check(str(sample_text.get("title", "")) == "¡Jardín del Edén completado!" and str(sample_text.get("detail", "")).contains("«Guardián del Huerto»")
			and str(sample_text.get("detail", "")).contains("Se abrió: Arca de Noé") and str(sample_text.get("detail", "")).contains("Viaje: 1 de 7 mundos"),
			"el texto de recompensa dice mapa, estrellas, insignia y mapa que se abre")
	_check(hud.winner_text().contains(names[winner]), "la pantalla muestra el nombre del ganador (%s)" % hud.winner_text())
	_check(hud.row_count() == 4, "la tabla muestra las estadísticas de los 4 jugadores")
	_check(hud.summary_text().begins_with("Turnos:") and hud.summary_text().contains("Duración:") and hud.summary_text().contains("Desafíos:"),
			"se muestran turnos, duración, tiradas y desafíos")
	var ranked: Array = summary.get("players", [])
	var actual_order: Array[int] = []
	for entry in ranked:
		actual_order.append(int((entry as Dictionary)["index"]))
	_check(actual_order == expected_order, "el podio ordena a los jugadores: ganador y luego por avance %s" % str(actual_order))
	_check(ranked.size() == 4 and bool((ranked[0] as Dictionary)["winner"]) and int((ranked[0] as Dictionary)["rank"]) == 1,
			"el ganador figura primero")
	_check(int(summary.get("total_rolls", 0)) >= 1 and int(summary.get("turns", 0)) >= 1, "las estadísticas cuentan tiradas y turnos")
	_check(scene.tokens.size() == 4, "el podio 3D tiene una ficha por jugador")
	_check(scene.get_node_or_null("%Stage") != null and (scene.get_node("%Stage") as Node).get_node_or_null("Trophy") != null,
			"el podio 3D tiene una copa para el ganador")
	_check(await _wait_until(_fireworks_started.bind(scene), 4.0), "hay fuegos artificiales")
	var again := hud.get_node_or_null("%PlayAgainButton") as Button
	var menu_button := hud.get_node_or_null("%MenuButton") as Button
	_check(again != null and again.text == "JUGAR OTRA VEZ" and menu_button != null, "hay botones para jugar otra vez y para volver al menú")
	if again == null:
		return
	again.pressed.emit()
	_check(await _wait_until(_arrived.bind("board"), 15.0), "JUGAR OTRA VEZ abre un tablero nuevo")
	if not _bind_board():
		return
	_check(_flow.state.turn_number == 1 and not _flow.state.finished and _flow.state.player_count() == 4,
			"la nueva partida empieza desde cero con los mismos 4 jugadores")
	_check_synced("en la nueva partida todos están en la casilla 1")
	_check(_flow.is_waiting_for_roll() and _hud.is_roll_enabled(), "la nueva partida espera la primera tirada")


func _by_spot_desc(a: int, b: int, spots: Array[int]) -> bool:
	return spots[a] > spots[b]


func _fireworks_started(scene: Node) -> bool:
	return int(scene.fireworks_launched()) >= 1


# ---------------------------------------------------------------- Partida completa con un robot

func _test_full_match_with_bot() -> void:
	print("-- Partida completa jugada por un robot (respuestas al azar)")
	if not _arrived("board"):
		if not await _enter_board(4):
			return
	_flow.speed = BOT_SPEED
	_dice.speed = BOT_SPEED
	# Partida entera de 4 jugadores desde la casilla 1 hasta la meta, con todos los desafíos,
	# escaleras y serpientes que se crucen por el camino (las respuestas se eligen al azar).
	for index in 4:
		_check(int(_flow.state.get_player(index)["tile"]) == 1, "el jugador %d sale de la casilla 1" % (index + 1))
	_events.clear()
	var problems: Array[String] = []
	var turns: int = 0
	var stuck: bool = false
	while not _flow.is_finished() and turns < 400:
		problems.append_array(_sync_problems())
		for index in 4:
			if not _token_inside_board(_token(index)):
				problems.append("la ficha %d se salió del tablero" % index)
		var player: int = _flow.current_player()
		if not _flow.request_roll():
			problems.append("no se pudo lanzar el dado en el turno %d del jugador %d" % [turns + 1, player + 1])
			break
		turns += 1
		if not await _drive_until_ready(40.0, 2):
			stuck = true
			problems.append("el turno %d (jugador %d) se atascó" % [turns, player + 1])
			break
	_check(not stuck and _flow.is_finished() and _flow.state.finished, "la partida termina sola con un ganador tras %d turnos" % turns)
	_check(problems.is_empty(), "durante toda la partida las fichas, la lista y las reglas coinciden %s" % str(problems.slice(0, 3)))
	var winner: int = _flow.state.winner
	_check(winner >= 0 and winner < 4 and int(_flow.state.get_player(winner)["tile"]) == _flow.layout.last_tile(), "el ganador está en la meta")
	# El orden es 1, 2, 3, 4, salvo lo que mandan las casillas especiales: una tirada extra repite
	# al mismo jugador y perder el turno salta al jugador castigado una sola vez.
	var order_ok: bool = true
	var skipping: Dictionary = {}
	var extra_owed: bool = false
	var previous_player: int = -1
	var specials_played: int = 0
	for entry in _events:
		var event: Array = entry
		var kind: String = str(event[0])
		if kind == "special":
			specials_played += 1
			var special_result: Dictionary = event[2]
			if bool(special_result["extra_roll"]):
				extra_owed = true
			if bool(special_result["skip_next"]):
				skipping[int(event[1])] = true
		elif kind == "turn_started":
			var player_now: int = int(event[1])
			if previous_player >= 0:
				var expected_next: int = previous_player
				if not extra_owed:
					expected_next = (previous_player + 1) % 4
					while skipping.has(expected_next):
						skipping.erase(expected_next)
						expected_next = (expected_next + 1) % 4
				if player_now != expected_next:
					order_ok = false
			extra_owed = false
			previous_player = player_now
	_check(order_ok, "los turnos siguieron el orden 1, 2, 3, 4 durante toda la partida (con %d casillas especiales)" % specials_played)
	var summary: Dictionary = _flow.state.summary()
	_check(int(summary["total_rolls"]) == _events_of("rolled").size(), "las estadísticas cuentan las tiradas (%d)" % int(summary["total_rolls"]))
	_check(int(summary["total_challenges"]) == _events_of("challenge_shown").size() \
			and _events_of("challenge_resolved").size() == _events_of("challenge_shown").size()
			and int(summary["total_correct"]) <= int(summary["total_challenges"]),
			"las estadísticas cuentan los desafíos (%d, %d correctos)" % [int(summary["total_challenges"]), int(summary["total_correct"])])
	_check(await _wait_until(_arrived.bind("victory"), 20.0), "la partida completa termina en la pantalla de victoria")
	if _arrived("victory"):
		var victory_hud: Node = current_scene.get_node_or_null("%Hud")
		var menu_button: Button = null
		if victory_hud != null:
			menu_button = victory_hud.get_node_or_null("%MenuButton") as Button
		_check(menu_button != null, "la pantalla de victoria tiene el botón MENÚ")
		if menu_button != null:
			menu_button.pressed.emit()
			_check(await _wait_until(_arrived.bind("main_menu"), 15.0), "el botón MENÚ de la victoria vuelve al menú principal")


# ---------------------------------------------------------------- 1, 2 y 3 jugadores

func _test_player_counts() -> void:
	print("-- Partidas de 1, 2 y 3 jugadores")
	for count in [1, 2, 3]:
		var players: int = int(count)
		if not await _enter_board(players):
			continue
		_check(_tokens_root.get_child_count() == players and _hud.row_count() == players and _flow.state.player_count() == players,
				"con %d jugador(es) hay %d ficha(s) y %d fila(s) en la lista" % [players, players, players])
		var spots: Dictionary = {}
		for child in _tokens_root.get_children():
			spots["%.2f,%.2f" % [(child as Node3D).position.x, (child as Node3D).position.z]] = true
		_check(spots.size() == players, "con %d jugador(es) las fichas no se superponen" % players)
		var expected_hint: String = "Toca LANZAR DADO" if players == 1 else "%s, toca LANZAR DADO" % _player_name(0)
		_check(_hud.hint_text() == expected_hint, "la ayuda dice: %s" % _hud.hint_text())
		if players == 1:
			_check(not _hud.is_splash_visible(), "con un solo jugador no hay aviso de turno")
		var order: Array[int] = []
		var expected_order: Array[int] = []
		for turn in players * 2 + 1:
			order.append(_flow.current_player())
			expected_order.append(turn % players)
			_check(await _quiet_turn(), "turno %d de la partida de %d jugador(es)" % [turn + 1, players])
		_check(order == expected_order, "con %d jugador(es) los turnos se alternan %s" % [players, str(order)])
		_check_synced("con %d jugador(es), fichas, lista e insignias coinciden con las reglas" % players)
		if players == 1:
			await _solo_rules_and_victory()
		else:
			await _go_to_menu()


func _solo_rules_and_victory() -> void:
	# Perder el turno no tiene sentido con un solo jugador: no pasa nada.
	_flow.state.options["penalty_mode"] = GameRules.PENALTY_SKIP_TURN
	var report: Dictionary = await _play_challenge_turn(Challenge.TYPE_TRUE_FALSE, 41, false)
	_check(bool(report["ok"]) and str(report["lose_text"]) == "Si fallas: no pasa nada, ¡sigue intentando!",
			"con un jugador, perder el turno no se anuncia (%s)" % str(report.get("lose_text", "")))
	_check(not bool(_flow.state.get_player(0)["skip_next"]) and _flow.current_player() == 0 and _flow.is_waiting_for_roll(),
			"con un jugador, fallar no le quita el turno")
	_restore_rules()
	var layout: BoardLayout = _flow.layout
	_flow.place_player(0, layout.last_tile() - 4)
	_events.clear()
	_check(_flow.try_roll(0, 4), "el jugador solitario tira un 4 desde la casilla %d" % (layout.last_tile() - 4))
	_check(await _wait_until(_arrived.bind("victory"), 30.0), "al llegar a la meta se abre la victoria")
	if not _arrived("victory"):
		return
	var hud: Node = current_scene.get_node_or_null("%Hud")
	_check(hud != null and hud.winner_text().contains("llegó a la meta") and hud.row_count() == 1,
			"la victoria de un solo jugador lo felicita por llegar a la meta (%s)" % (hud.winner_text() if hud != null else ""))
	var world_button: Button = null
	if hud != null:
		world_button = hud.get_node_or_null("%WorldButton") as Button
	if world_button != null:
		world_button.pressed.emit()
		_check(await _wait_until(_arrived.bind("world"), 15.0), "el botón MUNDO BÍBLICO de la victoria abre el mundo bíblico")
	await _go_to_menu()


# ---------------------------------------------------------------- Reglas del juego (ajustes)

func _test_rules_tab() -> void:
	print("-- Ajustes: pestaña REGLAS DEL JUEGO")
	var tab_general := _node("%GeneralTab") as Button
	var tab_rules := _node("%RulesTab") as Button
	var content := _node("%Content") as Control
	var rules_content := _node("%RulesContent") as Control
	var challenges := _node("%ChallengesToggle") as Button
	var reward_row := _node("%RewardRow")
	var reward_stepper := _node("%RewardStepper")
	var penalty_row := _node("%PenaltyRow")
	var penalty_stepper := _node("%PenaltyStepper")
	var exact := _node("%ExactToggle") as Button
	var rules_reset := _node("%RulesResetButton") as Button
	if tab_general == null or tab_rules == null or content == null or rules_content == null or challenges == null \
			or reward_row == null or reward_stepper == null or penalty_row == null or penalty_stepper == null \
			or exact == null or rules_reset == null:
		return
	_settings.reset_game_rules()
	tab_rules.pressed.emit()
	_check(rules_content.visible and not content.visible, "la pestaña REGLAS DEL JUEGO muestra las reglas")
	_check(reward_row.get_child_count() == 3 and penalty_row.get_child_count() == 3, "hay 3 tipos de premio y 3 de castigo")
	var options: Dictionary = _settings.game_options()
	_check(bool(options["challenges"]) and int(options["reward_mode"]) == GameRules.REWARD_ADVANCE \
			and int(options["penalty_mode"]) == GameRules.PENALTY_BACK and not bool(options["exact_finish"]),
			"las reglas empiezan con los valores iniciales")
	for mode in [0, 1, 2]:
		(reward_row.get_child(mode) as Button).pressed.emit()
		_check(int(_settings.game_options()["reward_mode"]) == mode, "el premio %d se aplica a las opciones de la partida" % mode)
		(penalty_row.get_child(mode) as Button).pressed.emit()
		_check(int(_settings.game_options()["penalty_mode"]) == mode, "el castigo %d se aplica a las opciones de la partida" % mode)
	(reward_row.get_child(1) as Button).pressed.emit()
	(penalty_row.get_child(1) as Button).pressed.emit()
	var reward_plus := reward_stepper.get_child(3) as Button
	var reward_minus := reward_stepper.get_child(1) as Button
	var penalty_plus := penalty_stepper.get_child(3) as Button
	var penalty_minus := penalty_stepper.get_child(1) as Button
	for _i in 4:
		reward_plus.pressed.emit()
		penalty_minus.pressed.emit()
	_check(int(_settings.game_options()["reward_steps"]) == GameRules.MAX_SHIFT, "el premio no pasa de %d casillas" % GameRules.MAX_SHIFT)
	_check(int(_settings.game_options()["penalty_steps"]) == GameRules.MIN_SHIFT, "el castigo no baja de %d casilla" % GameRules.MIN_SHIFT)
	_check(reward_plus.disabled and penalty_minus.disabled, "los botones + y - se desactivan en sus límites")
	for _i in 4:
		reward_minus.pressed.emit()
		penalty_plus.pressed.emit()
	_check(int(_settings.game_options()["reward_steps"]) == GameRules.MIN_SHIFT and int(_settings.game_options()["penalty_steps"]) == GameRules.MAX_SHIFT,
			"las casillas del premio y del castigo se pueden cambiar")
	exact.button_pressed = true
	_check(bool(_settings.game_options()["exact_finish"]), "se activa la tirada exacta en la meta")
	challenges.button_pressed = false
	_check(not bool(_settings.game_options()["challenges"]), "se pueden desactivar los desafíos")
	_check((reward_row.get_child(0) as Button).disabled and (penalty_row.get_child(0) as Button).disabled,
			"sin desafíos, los premios y castigos se desactivan en pantalla")
	_settings.save()
	var saved := ConfigFile.new()
	_check(saved.load("user://settings.cfg") == OK and int(saved.get_value("game", "penalty_steps", -1)) == GameRules.MAX_SHIFT \
			and bool(saved.get_value("game", "exact_finish", false)) and not bool(saved.get_value("game", "challenges", true)),
			"las reglas se guardan en user://settings.cfg")
	rules_reset.pressed.emit()
	var defaults: Dictionary = GameRules.default_options()
	var after: Dictionary = _settings.game_options()
	_check(bool(after["challenges"]) == bool(defaults["challenges"]) and int(after["reward_mode"]) == int(defaults["reward_mode"]) \
			and int(after["reward_steps"]) == int(defaults["reward_steps"]) and int(after["penalty_mode"]) == int(defaults["penalty_mode"]) \
			and int(after["penalty_steps"]) == int(defaults["penalty_steps"]) and bool(after["exact_finish"]) == bool(defaults["exact_finish"]),
			"RESTABLECER REGLAS vuelve a los valores iniciales")
	tab_general.pressed.emit()
	_check(content.visible and not rules_content.visible, "la pestaña GENERAL vuelve a mostrar el sonido y los gráficos")
