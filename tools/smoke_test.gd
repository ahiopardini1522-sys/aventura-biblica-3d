extends SceneTree
## Prueba de humo automática (la ejecuta GitHub Actions con Godot sin pantalla).
##
## Uso:  godot --headless --path . --script res://tools/smoke_test.gd
## Termina con código 0 si todo pasa, 1 si algún control falla y 2 si se agota el tiempo.
##
## Comprueba, con el motor real:
##   - que todos los scripts compilan y todas las escenas se cargan,
##   - que no hay rutas res:// que apunten a archivos inexistentes,
##   - que los datos (mapas, desafíos, versículos, mensajes) y las reglas del tablero son válidos,
##   - las reglas del juego: turnos, dado, movimiento, las 6 escaleras, las 7 serpientes,
##     premios, castigos, victoria y cientos de partidas simuladas completas,
##   - que cada desafío bíblico tiene referencias válidas y que los cinco tipos funcionan,
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
	"MapsButton": "maps",
	"MultiplayerButton": "multiplayer",
	"CharactersButton": "characters",
	"SettingsButton": "settings",
}
const TIME_LIMIT := 420.0
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
	_check(_router != null and _state != null and _settings != null, "autoloads cargados (SettingsManager, GameState, SceneRouter)")
	if _router == null or _state == null or _settings == null:
		_finish()
		return

	_test_project_settings()
	_test_scripts_compile()
	_test_scene_loading()
	_test_resource_references()
	_test_data()
	_test_board_layout()
	_test_rules()
	_test_match_state()
	_test_simulated_games()
	_test_bible_references()
	_test_challenge_bank()
	_test_character_roster()
	_test_meshes()
	await _test_menu_and_screens()
	await _test_board_scene()
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
	_check(maps.size() == 6, "el catálogo tiene 6 mapas")
	_check(MapCatalog.playable_maps().size() >= 1, "hay al menos un mapa jugable")
	_check(MapCatalog.is_playable(MapCatalog.default_map_id()), "el mapa por defecto es jugable")
	var ids: Dictionary = {}
	for entry in maps:
		var map_data: Dictionary = entry
		ids[str(map_data["id"])] = true
		var layout: BoardLayout = BoardLayout.from_map(map_data)
		var problems: PackedStringArray = layout.validate()
		_check(problems.is_empty(), "tablero válido: %s %s" % [map_data["id"], str(problems)])
		var theme_data: Dictionary = map_data["theme"]
		for key in ["tile_a", "tile_b", "frame", "ground", "sky_top", "sky_horizon", "ambient", "fog", "sun"]:
			if not (theme_data.get(key) is Color):
				_check(false, "el tema de %s tiene el color '%s'" % [map_data["id"], key])
	_check(ids.size() == maps.size(), "los ids de mapa no se repiten")

	var desert: Dictionary = MapCatalog.find_map("desierto_sinai")
	_check(not desert.is_empty(), "existe el mapa Desierto del Sinaí")
	var board: Dictionary = desert.get("board", {})
	_check((board.get("ladders", []) as Array).size() == 6, "el mapa jugable tiene 6 escaleras")
	_check((board.get("snakes", []) as Array).size() == 7, "el mapa jugable tiene 7 serpientes")

	var verses: Dictionary = JsonLoader.load_dictionary("res://data/verses/verse_references.json")
	var verse_list: Array = verses.get("verses", [])
	_check(verse_list.size() >= 10, "hay referencias bíblicas (%d)" % verse_list.size())
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


func _test_simulated_games() -> void:
	print("-- Partidas simuladas completas")
	var layout: BoardLayout = _desert_layout()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261107
	var games: int = 400
	var completed: int = 0
	var invariants: bool = true
	var longest: int = 0
	var shortest: int = 1 << 30
	var ladder_hits: Dictionary = {}
	var snake_hits: Dictionary = {}
	var challenges_seen: int = 0
	var total_rolls: int = 0
	var winners: Dictionary = {}
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
	_check(completed == games, "las %d partidas simuladas terminan con un ganador (%d)" % [games, completed])
	_check(invariants, "en todas las partidas: casillas dentro del tablero, un solo ganador en la casilla 100 y turnos válidos")
	_check(ladder_hits.size() == 6, "en las simulaciones se usaron las 6 escaleras (%d)" % ladder_hits.size())
	_check(snake_hits.size() == 7, "en las simulaciones se usaron las 7 serpientes (%d)" % snake_hits.size())
	_check(challenges_seen > 500, "en las simulaciones se plantearon desafíos (%d)" % challenges_seen)
	var average_rolls: float = float(total_rolls) / float(games)
	_check(shortest >= 6 and average_rolls >= 20.0 and average_rolls <= 600.0,
			"la duración de las partidas es razonable (media %.0f tiradas, la más corta %d)" % [average_rolls, shortest])
	_check(winners.size() >= 2, "ganan jugadores distintos según la suerte (%s)" % str(winners))
	print("      (la partida más larga tuvo %d tiradas)" % longest)


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
	_check(ChallengeBank.all().size() >= 80, "el banco tiene 80 desafíos o más (%d)" % ChallengeBank.all().size())
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
			_test_screen(key)
			var back := current_scene.find_child("BackButton", true, false) as Button
			_check(back != null, "la pantalla '%s' tiene botón VOLVER" % key)
			if back != null:
				back.pressed.emit()
				_check(await _wait_until(_arrived.bind("main_menu")), "VOLVER regresa al menú desde '%s'" % key)
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
		"maps":
			_test_maps_screen()
		"multiplayer":
			_test_multiplayer_screen()
		"characters":
			_test_characters_screen()
		"settings":
			_test_settings_screen()


func _test_maps_screen() -> void:
	var list := _node("%MapList")
	var play := _node("%PlayMapButton") as Button
	if list == null or play == null:
		return
	var maps: Array = MapCatalog.all_maps()
	_check(list.get_child_count() == maps.size(), "la lista de mapas muestra los %d mapas" % maps.size())
	var playable_index: int = -1
	var locked_index: int = -1
	for i in maps.size():
		if MapCatalog.is_playable(str(maps[i]["id"])):
			playable_index = i
		else:
			locked_index = i
	if locked_index >= 0:
		(list.get_child(locked_index) as Button).pressed.emit()
		_check(play.disabled, "un mapa 'próximamente' no se puede jugar")
		_check(MapCatalog.is_playable(str(_state.selected_map_id)), "elegir un mapa no disponible no cambia la selección")
	if playable_index >= 0:
		(list.get_child(playable_index) as Button).pressed.emit()
		_check(not play.disabled, "el mapa disponible se puede jugar")
		_check(str(_state.selected_map_id) == str(maps[playable_index]["id"]), "el mapa elegido queda guardado")
		_check(not (_node("%MapNameLabel") as Label).text.is_empty(), "se muestra el nombre del mapa")
		_check((_node("%Swatches") as Node).get_child_count() == 4, "se muestran los 4 colores del tablero")


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


func _on_match_finished(summary: Dictionary) -> void:
	_events.append(["match_finished", summary])


func _sample_frame() -> void:
	if _sampling and _sample_token != null:
		_samples.append(_sample_token.position)


## Abre el tablero desde el menú con ese número de jugadores y toma sus piezas.
func _enter_board(player_count: int) -> bool:
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
	_flow.match_finished.connect(_on_match_finished)
	return true


func _player_name(index: int) -> String:
	return str(_flow.state.get_player(index)["name"])


func _token(index: int) -> Node3D:
	return _tokens_root.get_child(index) as Node3D


## Casilla "tranquila": no es inicio ni meta y no tiene escalera, serpiente ni desafío.
func _is_quiet(layout: BoardLayout, tile: int) -> bool:
	return tile > 1 and tile < layout.last_tile() and layout.jump_kind(tile) == "" \
			and not layout.is_challenge_tile(tile)


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


func _test_board_structure() -> void:
	print("-- Tablero: casillas, escaleras, serpientes y fichas")
	var board: Node = _board
	_check(board.tile_count() == 100, "el tablero tiene 100 casillas")
	_check(board.ladder_count() == 6, "el tablero tiene 6 escaleras")
	_check(board.snake_count() == 7, "el tablero tiene 7 serpientes")
	for tile in [1, 2, 11, 50, 100]:
		var tile_node: Node = board.tile_node(tile)
		var number: Label3D = null
		if tile_node != null:
			number = tile_node.get_node_or_null("Number") as Label3D
		_check(number != null and number.text == str(tile), "la casilla %d existe y muestra su número" % tile)
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
		var tile_node: Node = board.tile_node(tile)
		if tile_node != null and tile_node.get_node_or_null("ChallengeMark") != null:
			marked += 1
	_check(challenge_tiles.size() >= 10 and marked == challenge_tiles.size(),
			"las %d casillas de desafío llevan su signo de pregunta" % challenge_tiles.size())
	_check(board.tile_node(2).get_node_or_null("ChallengeMark") == null, "una casilla normal no lleva signo de pregunta")

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
	# Salen desde la recta final para que dure poco, pero con desafíos, escaleras y serpientes de por medio.
	var starts: Array[int] = [90, 84, 78, 72]
	for index in 4:
		_flow.place_player(index, starts[index])
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
	var order_ok: bool = true
	var started: Array = _events_of("turn_started")
	for i in range(1, started.size()):
		if (int((started[i] as Array)[1]) - int((started[i - 1] as Array)[1]) + 4) % 4 != 1:
			order_ok = false
	_check(order_ok, "los turnos siguieron el orden 1, 2, 3, 4 durante toda la partida")
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
