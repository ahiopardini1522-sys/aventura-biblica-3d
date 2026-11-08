extends ScreenBase
## MUNDO BÍBLICO: el mapa 3D gigante con los siete mundos conectados por caminos.
##   - Un dedo arrastra el mapa, dos dedos acercan o alejan (los botones + y - también), y un toque
##     elige una región: el icono salta, la cámara vuela hasta ella y el panel de abajo cuenta su
##     estado, qué hay que completar para abrirla, sus estadísticas y su insignia.
##   - Un segundo toque sobre la región elegida (o el botón JUGAR) abre su tablero, si está abierta.
##     Las bloqueadas llevan un candado y dicen qué falta.
##   - Arriba se ve el avance del viaje (mundos completados, estrellas e insignias). Al volver de
##     una partida que abrió un mundo nuevo, el candado salta y se muestra un aviso.

const OVERVIEW_DISTANCE := 124.0
const FOCUS_DISTANCE := 62.0
const ZOOM_STEP := 0.7
const CAMERA_BOUNDS := Rect2(-92.0, -46.0, 190.0, 92.0)
const CAMERA_HOME := Vector3(3.0, 0.0, 10.0)
const INTRO_DELAY := 1.1
const HINT_SECONDS := 9.0
const BANNER_SECONDS := 3.6
## Oleaje y gaviotas de fondo, bajito, mientras se mira el mapa.
const WORLD_SOUND := "sea"
const WORLD_SOUND_DB := -15.0
const HINT_TEXT := "Arrastra para recorrer el mundo  ·  Pellizca para acercar  ·  Toca una región"

@onready var _world: WorldMapBuilder = %World
@onready var _camera: WorldCamera = %Camera

var _selected_id: String = ""
var _built: bool = false
var _intro_pending: bool = false
var _celebrating: bool = false
var _overlay_open: bool = false
var _hint_tween: Tween
var _banner_tween: Tween


func _ready() -> void:
	_style_panels()
	%PlayRegionButton.pressed.connect(_on_play_pressed)
	%ZoomInButton.pressed.connect(_on_zoom_pressed.bind(ZOOM_STEP))
	%ZoomOutButton.pressed.connect(_on_zoom_pressed.bind(1.0 / ZOOM_STEP))
	%ViewButton.pressed.connect(_on_view_pressed)
	%ListButton.pressed.connect(SceneRouter.go_to.bind("maps"))
	%BadgesButton.pressed.connect(open_badges)
	%BadgesCloseButton.pressed.connect(close_badges)
	_camera.tapped.connect(_on_world_tapped)
	_camera.user_moved.connect(_on_user_moved)
	ProgressManager.progress_changed.connect(_on_progress_changed)
	%BadgesPanel.visible = false
	%BannerPanel.visible = false

	_world.build(SettingsManager.quality)
	_camera.configure(CAMERA_BOUNDS, CAMERA_HOME, OVERVIEW_DISTANCE)
	_start_ambience()

	# Un mundo que se abrió en la última partida se muestra primero bloqueado y se abre con una
	# animación; el resto de las regiones muestran su estado real.
	var opened: Array = _pending_unlocks()
	_apply_statuses(opened)

	var start_id: String = GameState.selected_map_id
	if not GameState.can_select_map(start_id):
		start_id = recommended_id()
	if start_id.is_empty() and not _world.region_ids().is_empty():
		start_id = _world.region_ids()[0]
	_select(start_id, false)
	_built = true
	UiFx.fade_scale_in([%Info, %ProgressPanel], 0.12, 0.45)
	_show_hint(HINT_TEXT, HINT_SECONDS)

	if opened.is_empty():
		_intro_pending = true
		_fly_to_selection_later()
	else:
		_celebrate(opened)


func _start_ambience() -> void:
	var player := AmbiencePlayer.new()
	player.name = "Ambience"
	add_child(player)
	player.start(WORLD_SOUND, AmbiencePlayer.FADE_IN, WORLD_SOUND_DB)


# ---------------------------------------------------------------- Consultas (también para las pruebas)

func is_built() -> bool:
	return _built


func world() -> WorldMapBuilder:
	return _world


func camera() -> WorldCamera:
	return _camera


func selected_id() -> String:
	return _selected_id


func is_celebrating() -> bool:
	return _celebrating


func is_badges_open() -> bool:
	return _overlay_open


## Región recomendada: la primera abierta que todavía no se completó ("" si no hay mapas).
func recommended_id() -> String:
	var first_id: String = ""
	for map_id in MapCatalog.ids_in_order():
		if first_id.is_empty():
			first_id = map_id
		if ProgressManager.status_of(map_id) == ProgressData.STATUS_AVAILABLE:
			return map_id
	return first_id


## Región que está bajo el dedo en esa posición de pantalla ("" si no hay ninguna cerca).
func pick_region(screen_position: Vector2) -> String:
	var best_id: String = ""
	var best_distance: float = _pick_radius()
	for map_id in _world.region_ids():
		var point: Vector3 = _world.focus_point(map_id)
		if _camera.is_position_behind(point):
			continue
		var projected: Vector2 = _camera.unproject_position(point)
		var gap: float = projected.distance_to(screen_position)
		if gap < best_distance:
			best_distance = gap
			best_id = map_id
	return best_id


## Posición de pantalla donde se ve la región (para tocarla en las pruebas).
func screen_position_of(map_id: String) -> Vector2:
	return _camera.unproject_position(_world.focus_point(map_id))


func _pick_radius() -> float:
	var per_pixel: float = maxf(_camera.units_per_pixel(), 0.0001)
	return clampf(8.5 / per_pixel, 56.0, 200.0)


# ---------------------------------------------------------------- Estados y selección

func refresh_states() -> void:
	_apply_statuses([])
	if not _selected_id.is_empty():
		_fill_info(_selected_id)


## Muestra el estado de cada región. Las de "held" se muestran bloqueadas (se abrirán después).
func _apply_statuses(held: Array) -> void:
	for map_id in _world.region_ids():
		var status: String = ProgressManager.status_of(map_id)
		if held.has(map_id):
			status = ProgressData.STATUS_LOCKED
		_world.set_status(map_id, status)
	_world.set_next(recommended_id())
	_update_progress_panel()


## Elige una región: aro de selección, salto del icono, vuelo de la cámara y panel de información.
func select_region(map_id: String) -> void:
	_select(map_id, true)


func _select(map_id: String, animate: bool) -> void:
	if MapCatalog.find_map(map_id).is_empty():
		return
	_selected_id = map_id
	_world.set_selected(map_id, animate)
	_fill_info(map_id)
	if animate:
		_intro_pending = false
		_camera.focus_on(_world.focus_point(map_id), FOCUS_DISTANCE)
		SettingsManager.play_click()
		if ProgressManager.status_of(map_id) == ProgressData.STATUS_LOCKED:
			_world.shake_lock(map_id)


func _fill_info(map_id: String) -> void:
	var map_data: Dictionary = MapCatalog.find_map(map_id)
	if map_data.is_empty():
		return
	var status: String = ProgressManager.status_of(map_id)
	%RegionNameLabel.text = str(map_data["name"])
	%RegionRefLabel.text = str(map_data["reference"])
	if status == ProgressData.STATUS_COMPLETED:
		%RegionStatusLabel.text = "COMPLETADO"
		%RegionStatusLabel.add_theme_color_override("font_color", UiTheme.OK_GREEN)
		%RegionDetailLabel.text = str(map_data["description"])
	elif status == ProgressData.STATUS_AVAILABLE:
		%RegionStatusLabel.text = "DISPONIBLE"
		%RegionStatusLabel.add_theme_color_override("font_color", UiTheme.GOLD)
		%RegionDetailLabel.text = str(map_data["description"])
	else:
		%RegionStatusLabel.text = "BLOQUEADO"
		%RegionStatusLabel.add_theme_color_override("font_color", UiTheme.WARN_RED)
		%RegionDetailLabel.text = MapCatalog.requirement_text(map_id)

	var stats: Dictionary = ProgressManager.region(map_id)
	if status == ProgressData.STATUS_LOCKED:
		%RegionStatsLabel.text = ""
	elif int(stats["plays"]) > 0 or int(stats["completions"]) > 0:
		%RegionStatsLabel.text = "Partidas: %d  ·  Completado: %d\nAciertos %d/%d  ·  Estrellas %d" % [
				int(stats["plays"]), int(stats["completions"]), int(stats["correct"]),
				int(stats["challenges"]), int(stats["stars"])]
	else:
		%RegionStatsLabel.text = "Aún no has jugado este mundo."
	%RegionStatsLabel.visible = not %RegionStatsLabel.text.is_empty()

	var badge: Dictionary = MapCatalog.badge_of(map_id)
	if badge.is_empty():
		%RegionBadgeLabel.text = ""
	else:
		var earned: bool = ProgressManager.data.has_badge(str(badge["id"]))
		%RegionBadgeLabel.text = "Insignia «%s»: %s\nPremio: %d estrellas" % [
				str(badge["name"]), "ganada" if earned else "pendiente", MapCatalog.reward_stars_of(map_id)]
		%RegionBadgeLabel.add_theme_color_override("font_color", UiTheme.GOLD if earned else UiTheme.TEXT_DIM)
	%RegionBadgeLabel.visible = not %RegionBadgeLabel.text.is_empty()

	var playable: bool = GameState.can_select_map(map_id)
	%PlayRegionButton.disabled = not playable
	%PlayRegionButton.text = "JUGAR" if playable else "BLOQUEADO"


func _update_progress_panel() -> void:
	var data: ProgressData = ProgressManager.data
	var done: int = data.completed_count()
	var total: int = data.map_total()
	var percent: int = roundi(data.completion_ratio() * 100.0)
	%ProgressLabel.text = "Mundos completados: %d de %d  ·  %d %%" % [done, total, percent]
	(%ProgressBar as ProgressBar).max_value = float(maxi(total, 1))
	(%ProgressBar as ProgressBar).value = float(done)
	var badges: Vector2i = data.badge_counts()
	%JourneyLabel.text = "%d estrellas del viaje  ·  %d de %d insignias" % [data.journey_stars, badges.x, badges.y]


# ---------------------------------------------------------------- Entrada

func _on_world_tapped(screen_position: Vector2) -> void:
	if _overlay_open or _celebrating:
		return
	var map_id: String = pick_region(screen_position)
	if map_id.is_empty():
		return
	if map_id == _selected_id:
		open_selected_region()
	else:
		_select(map_id, true)


## Abre el tablero de la región elegida si está abierta; si está bloqueada, avisa qué falta.
func open_selected_region() -> void:
	if _selected_id.is_empty():
		return
	if not GameState.can_select_map(_selected_id):
		_world.shake_lock(_selected_id)
		SettingsManager.play_wrong()
		_show_hint(MapCatalog.requirement_text(_selected_id), 5.0)
		return
	GameState.select_map(_selected_id)
	SettingsManager.play_confirm()
	SceneRouter.go_to("board")


func _on_play_pressed() -> void:
	open_selected_region()


func _on_zoom_pressed(factor: float) -> void:
	_intro_pending = false
	_camera.zoom_by(factor)


func _on_view_pressed() -> void:
	_intro_pending = false
	_camera.overview()


func _on_user_moved() -> void:
	_intro_pending = false
	_fade_hint()


func _on_progress_changed() -> void:
	if _built and not _celebrating:
		refresh_states()


func _on_back_requested() -> void:
	if _overlay_open:
		close_badges()
		return
	SceneRouter.go_back()


# ---------------------------------------------------------------- Pantalla de insignias

func open_badges() -> void:
	_fill_badges()
	%BadgesPanel.visible = true
	_overlay_open = true
	UiFx.fade_scale_in([%BadgesCard], 0.0, 0.3)


func close_badges() -> void:
	%BadgesPanel.visible = false
	_overlay_open = false


func _fill_badges() -> void:
	for child in %BadgeGrid.get_children():
		%BadgeGrid.remove_child(child)
		child.queue_free()
	var counts: Vector2i = ProgressManager.data.badge_counts()
	%BadgesCountLabel.text = "%d de %d insignias ganadas" % [counts.x, counts.y]
	for entry in ProgressManager.data.all_badges():
		var badge: Dictionary = entry
		%BadgeGrid.add_child(_badge_card(badge))


func _badge_card(badge: Dictionary) -> Control:
	var earned: bool = bool(badge["earned"])
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(540.0, 124.0)
	var fill := Color(0.12, 0.17, 0.30, 0.95) if earned else Color(0.06, 0.08, 0.15, 0.85)
	var edge: Color = UiTheme.GOLD if earned else Color(1.0, 1.0, 1.0, 0.12)
	card.add_theme_stylebox_override("panel", UiTheme.box(fill, edge, 22, 2, 20.0, 12.0, false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var star := StarIcon.new()
	star.configure(UiTheme.GOLD if earned else UiTheme.TEXT_DIM, earned, 58.0)
	row.add_child(star)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = str(badge["name"])
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UiTheme.GOLD_LIGHT if earned else UiTheme.TEXT_DIM)
	texts.add_child(title)
	var detail := Label.new()
	detail.text = str(badge["text"])
	detail.custom_minimum_size = Vector2(380.0, 0.0)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 25)
	detail.add_theme_color_override("font_color", UiTheme.TEXT if earned else UiTheme.TEXT_DIM)
	texts.add_child(detail)
	row.add_child(texts)
	card.add_child(row)
	return card


# ---------------------------------------------------------------- Mundo nuevo abierto

## Mapas que la última partida abrió y que todavía no se celebraron.
func _pending_unlocks() -> Array:
	var report: Dictionary = GameState.last_progress
	if report.is_empty() or bool(report.get("celebrated", false)):
		return []
	var raw: Variant = report.get("unlocked_maps", [])
	var result: Array = []
	if raw is Array:
		for entry in raw:
			var map_id: String = str(entry)
			if GameState.can_select_map(map_id):
				result.append(map_id)
	if not result.is_empty():
		report["celebrated"] = true
	return result


func _celebrate(opened: Array) -> void:
	_celebrating = true
	await get_tree().create_timer(INTRO_DELAY).timeout
	if not is_inside_tree():
		return
	var first_id: String = str(opened[0])
	_select(first_id, true)
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	for entry in opened:
		_world.play_unlock(str(entry))
	var names: PackedStringArray = PackedStringArray()
	for entry in opened:
		names.append(MapCatalog.name_of(str(entry)))
	_show_banner("¡NUEVO MUNDO ABIERTO!" if opened.size() == 1 else "¡NUEVOS MUNDOS ABIERTOS!", " y ".join(names))
	SettingsManager.play_win()
	await get_tree().create_timer(0.9).timeout
	if not is_inside_tree():
		return
	SettingsManager.play_star()
	_celebrating = false
	_apply_statuses([])
	_fill_info(_selected_id)


func _fly_to_selection_later() -> void:
	await get_tree().create_timer(INTRO_DELAY).timeout
	if not is_inside_tree() or not _intro_pending or _selected_id.is_empty():
		return
	_intro_pending = false
	_camera.focus_on(_world.focus_point(_selected_id), FOCUS_DISTANCE)


# ---------------------------------------------------------------- Textos que aparecen y se van

func _show_hint(text: String, seconds: float) -> void:
	var hint := %HintLabel as Label
	hint.text = text
	hint.modulate.a = 1.0
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(seconds)
	_hint_tween.tween_property(hint, "modulate:a", 0.0, 0.8)


func _fade_hint() -> void:
	var hint := %HintLabel as Label
	if hint.modulate.a <= 0.0:
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(1.5)
	_hint_tween.tween_property(hint, "modulate:a", 0.0, 0.8)


## Apaga la pista de arriba enseguida (por ejemplo, cuando sale un aviso grande).
func _dismiss_hint() -> void:
	var hint := %HintLabel as Label
	if hint.modulate.a <= 0.0:
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(hint, "modulate:a", 0.0, 0.25)


func _show_banner(title: String, detail: String) -> void:
	_dismiss_hint()
	%BannerTitle.text = title
	%BannerDetail.text = detail
	var panel := %BannerPanel as Control
	panel.visible = true
	panel.modulate.a = 0.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	_banner_tween.tween_interval(BANNER_SECONDS)
	_banner_tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	_banner_tween.tween_callback(panel.hide)


# ---------------------------------------------------------------- Aspecto

func _style_panels() -> void:
	%ProgressPanel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.GLASS, Color(1, 1, 1, 0.16), 26, 2, 26.0, 14.0))
	%Info.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.GLASS, Color(1, 1, 1, 0.16), 30, 2, 28.0, 22.0))
	%BannerPanel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.10, 0.07, 0.02, 0.9), UiTheme.GOLD, 30, 3, 36.0, 20.0))
	(%ProgressBar as ProgressBar).add_theme_stylebox_override("background",
			UiTheme.box(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 12, 0, 0.0, 0.0, false))
	(%ProgressBar as ProgressBar).add_theme_stylebox_override("fill",
			UiTheme.box(UiTheme.GOLD, Color(0, 0, 0, 0), 12, 0, 0.0, 0.0, false))


func _process(_delta: float) -> void:
	if _built:
		_world.update_label_scale(_camera.distance)
