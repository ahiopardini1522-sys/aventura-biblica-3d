extends Node
## Autoload "SettingsManager": ajustes del jugador (volumen, calidad, FPS).
## Se guardan en user://settings.cfg y se aplican al iniciar.

signal settings_changed

enum Quality { LOW, MEDIUM, HIGH }

const SETTINGS_PATH := "user://settings.cfg"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const DEFAULT_MASTER := 0.8
const DEFAULT_MUSIC := 0.8
const DEFAULT_SFX := 0.9

var master_volume: float = DEFAULT_MASTER
var music_volume: float = DEFAULT_MUSIC
var sfx_volume: float = DEFAULT_SFX
var quality: int = Quality.MEDIUM
var show_fps: bool = false

var _fps_layer: CanvasLayer
var _fps_label: Label
var _fps_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_SFX)
	_load()
	_build_fps_overlay()
	apply_all()


func _process(delta: float) -> void:
	if not show_fps:
		return
	_fps_accum += delta
	if _fps_accum >= 0.5:
		_fps_accum = 0.0
		_fps_label.text = "%d FPS" % int(Engine.get_frames_per_second())


# ---------------------------------------------------------------- Cambios

func set_master_volume(value: float, save_now: bool = true) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume("Master", master_volume)
	_changed(save_now)


func set_music_volume(value: float, save_now: bool = true) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volume(BUS_MUSIC, music_volume)
	_changed(save_now)


func set_sfx_volume(value: float, save_now: bool = true) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volume(BUS_SFX, sfx_volume)
	_changed(save_now)


func set_quality(value: int) -> void:
	quality = clampi(value, Quality.LOW, Quality.HIGH)
	_apply_quality()
	_changed(true)


func set_show_fps(value: bool) -> void:
	show_fps = value
	_apply_fps()
	_changed(true)


func reset_to_defaults() -> void:
	master_volume = DEFAULT_MASTER
	music_volume = DEFAULT_MUSIC
	sfx_volume = DEFAULT_SFX
	quality = Quality.MEDIUM
	show_fps = false
	apply_all()
	_changed(true)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "show_fps", show_fps)
	var err: int = cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("SettingsManager: no se pudo guardar los ajustes (error %d)" % err)


func apply_all() -> void:
	_apply_volume("Master", master_volume)
	_apply_volume(BUS_MUSIC, music_volume)
	_apply_volume(BUS_SFX, sfx_volume)
	_apply_quality()
	_apply_fps()


## True si las sombras deben estar activas con la calidad actual.
func shadows_enabled() -> bool:
	return quality != Quality.LOW


# ---------------------------------------------------------------- Sonido

func play_click() -> void:
	_play(AudioSynth.click(), -4.0)


func play_confirm() -> void:
	_play(AudioSynth.confirm(), -3.0)


func play_dice() -> void:
	_play(AudioSynth.dice_roll(), -2.0)


func _play(stream: AudioStream, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_SFX
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


# ---------------------------------------------------------------- Interno

func _changed(save_now: bool) -> void:
	if save_now:
		save()
	settings_changed.emit()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


func _apply_volume(bus_name: String, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))


func _apply_quality() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	match quality:
		Quality.LOW:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
		Quality.MEDIUM:
			viewport.msaa_3d = Viewport.MSAA_2X
		_:
			viewport.msaa_3d = Viewport.MSAA_4X
	get_tree().call_group("sun_light", "set", "shadow_enabled", shadows_enabled())


func _apply_fps() -> void:
	if _fps_layer != null:
		_fps_layer.visible = show_fps


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", DEFAULT_MASTER)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", DEFAULT_MUSIC)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", DEFAULT_SFX)), 0.0, 1.0)
	quality = clampi(int(cfg.get_value("video", "quality", Quality.MEDIUM)), Quality.LOW, Quality.HIGH)
	show_fps = bool(cfg.get_value("video", "show_fps", false))


func _build_fps_overlay() -> void:
	_fps_layer = CanvasLayer.new()
	_fps_layer.layer = 99
	_fps_label = Label.new()
	_fps_label.position = Vector2(24, 12)
	_fps_label.add_theme_font_size_override("font_size", 28)
	_fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_fps_label.add_theme_constant_override("outline_size", 6)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_layer.add_child(_fps_label)
	add_child(_fps_layer)
