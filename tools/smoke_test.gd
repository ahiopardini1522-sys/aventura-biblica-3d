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
##   - que cada botón del menú abre su pantalla y que cada pantalla funciona,
##   - que el tablero se construye (100 casillas, 6 escaleras, 7 serpientes) y el dado muestra
##     el número que saca.
## No puede comprobar el aspecto visual ni el rendimiento en un teléfono real.

const MENU_BUTTONS := {
	"MapsButton": "maps",
	"MultiplayerButton": "multiplayer",
	"CharactersButton": "characters",
	"SettingsButton": "settings",
}
const TIME_LIMIT := 300.0

var _checks: int = 0
var _failures: Array[String] = []
var _finished: bool = false
var _router: Node
var _state: Node
var _settings: Node


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
	_router.go_to("main_menu")
	return await _wait_until(_arrived.bind("main_menu"))


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


# ---------------------------------------------------------------- Tablero

func _test_board_scene() -> void:
	print("-- Tablero 3D")
	_state.select_map("desierto_sinai")
	_state.select_character(CharacterCatalog.all_ids()[0])
	_state.set_player_count(4)
	if not _arrived("main_menu"):
		await _go_to_menu()
	var play := current_scene.get_node_or_null("%PlayButton") as Button
	if play == null:
		_check(false, "el menú tiene el botón JUGAR")
		return
	play.pressed.emit()
	_check(await _wait_until(_arrived.bind("board")), "JUGAR abre el tablero")
	if not _arrived("board"):
		return

	var board := _node("%Board")
	var tokens := _node("%Tokens")
	var camera := _node("%BoardCamera") as Camera3D
	var dice := _node("%Dice")
	var hud := _node("%Hud")
	if board == null or tokens == null or camera == null or dice == null or hud == null:
		return

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

	_check(tokens.get_child_count() == 4, "hay una ficha por jugador (4)")
	var start: Vector3 = board.tile_position(1)
	var positions: Dictionary = {}
	var near_start: bool = true
	for child in tokens.get_children():
		var token := child as Node3D
		positions["%.2f,%.2f" % [token.position.x, token.position.z]] = true
		if Vector2(token.position.x - start.x, token.position.z - start.z).length() > 0.6:
			near_start = false
	_check(near_start, "las fichas están sobre la casilla de inicio")
	_check(positions.size() == 4, "las fichas no se superponen")

	_check(camera.current, "la cámara 3D del tablero está activa")
	_check(await _wait_until(_camera_settled.bind(camera), 8.0), "la cámara termina su animación de entrada")

	camera.orbit_by(Vector2(120.0, -60.0))
	_check(camera.goal_yaw != camera.default_yaw, "arrastrar gira la cámara")
	var before: float = camera.goal_distance
	camera.zoom_by(0.5)
	_check(camera.goal_distance < before, "el zoom acerca la cámara")
	camera.reset_view(false)
	_check(absf(camera.goal_distance - camera.default_distance) < 0.001, "VISTA restablece la cámara")

	for value in range(1, 7):
		var rolled: int = dice.roll(value)
		_check(rolled == value, "el dado acepta el valor %d" % value)
		_check(await _wait_until(_dice_idle.bind(dice), 6.0), "el dado %d termina de rodar" % value)
		_check(dice.up_face() == value, "el dado deja la cara %d hacia arriba" % value)

	var roll_button := hud.get_node_or_null("%RollButton") as Button
	var result_label := hud.get_node_or_null("%ResultLabel") as Label
	if roll_button != null and result_label != null:
		roll_button.pressed.emit()
		_check(roll_button.disabled, "el botón del dado se desactiva mientras rueda")
		_check(await _wait_until(_dice_idle.bind(dice), 6.0), "el lanzamiento desde el panel termina")
		_check(result_label.text.begins_with("Sacaste un"), "el panel muestra el resultado (%s)" % result_label.text)
		_check(not roll_button.disabled, "el botón del dado se activa al terminar")
	else:
		_check(false, "el panel tiene botón y texto de resultado")

	var back := hud.get_node_or_null("%BackButton") as Button
	if back != null:
		back.pressed.emit()
		_check(await _wait_until(_arrived.bind("main_menu")), "MENÚ regresa al menú principal desde el tablero")
	else:
		_check(false, "el panel del tablero tiene botón MENÚ")

	# Con 1 jugador el tablero también debe armarse.
	_state.set_player_count(1)
	if _arrived("main_menu"):
		var play_again := current_scene.get_node_or_null("%PlayButton") as Button
		if play_again != null:
			play_again.pressed.emit()
			if await _wait_until(_arrived.bind("board")):
				var one_token_root := _node("%Tokens")
				_check(one_token_root != null and one_token_root.get_child_count() == 1, "con 1 jugador hay 1 ficha")
	_state.set_player_count(1)
