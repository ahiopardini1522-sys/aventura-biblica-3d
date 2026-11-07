extends SceneTree
## Prueba de humo automática (la ejecuta GitHub Actions con Godot sin pantalla).
##
## Uso:  godot --headless --path . --script res://tools/smoke_test.gd
## Termina con código 0 si todo pasa, 1 si algún control falla y 2 si se agota el tiempo.
##
## Comprueba, con el motor real:
##   - que todos los scripts compilan y todas las escenas se cargan,
##   - que no hay rutas res:// que apunten a archivos inexistentes,
##   - que los datos (mapas, preguntas, versículos) y las reglas del tablero son válidos,
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
	_check(checked > 50, "se revisaron las referencias res:// (%d)" % checked)
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

	var questions: Array = QuestionBank.all_questions()
	_check(questions.size() >= 10, "banco de muestra con 10 preguntas o más (%d)" % questions.size())
	for question in questions:
		if not QuestionBank.is_valid(question):
			_check(false, "pregunta válida: %s" % str(question))
	_check(not QuestionBank.random_question().is_empty(), "se puede sacar una pregunta al azar")

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
