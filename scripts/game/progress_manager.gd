extends Node
## Autoload "ProgressManager": guarda y consulta el progreso del jugador en el mundo bíblico
## (mapas abiertos, mapas completados, insignias y estadísticas por región).
## Se guarda en user://progress.cfg cada vez que cambia. La lógica vive en ProgressData.

signal progress_changed

const SAVE_PATH := "user://progress.cfg"

## Dónde se guarda. Las pruebas automáticas lo cambian para no tocar el progreso real.
var save_path: String = SAVE_PATH
var data: ProgressData


func _ready() -> void:
	load_progress()


## Lee el progreso guardado (o empieza uno nuevo si no hay nada o el archivo está dañado).
func load_progress() -> void:
	data = ProgressData.new_game()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	var raw: Variant = cfg.get_value("progress", "data", {})
	if raw is Dictionary:
		data = ProgressData.from_dict(raw)
	progress_changed.emit()


func save() -> bool:
	_ensure()
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "data", data.to_dict())
	var err: int = cfg.save(save_path)
	if err != OK:
		push_warning("ProgressManager: no se pudo guardar el progreso (error %d)" % err)
		return false
	return true


## Borra todo el progreso y empieza de nuevo (con "save_now" también lo guarda).
func reset(save_now: bool = true) -> void:
	data = ProgressData.new_game()
	if save_now:
		save()
	progress_changed.emit()


func is_unlocked(map_id: String) -> bool:
	_ensure()
	return data.is_unlocked(map_id)


func is_completed(map_id: String) -> bool:
	_ensure()
	return data.is_completed(map_id)


func status_of(map_id: String) -> String:
	_ensure()
	return data.status_of(map_id)


func region(map_id: String) -> Dictionary:
	_ensure()
	return data.region(map_id)


## Anota que empezó una partida en el mapa.
func record_start(map_id: String) -> void:
	_ensure()
	data.record_start(map_id)
	save()
	progress_changed.emit()


## Anota una partida terminada, guarda y devuelve el informe de ProgressData.record_match().
func record_match(map_id: String, summary: Dictionary) -> Dictionary:
	_ensure()
	var report: Dictionary = data.record_match(map_id, summary)
	if bool(report["ok"]):
		save()
		progress_changed.emit()
	return report


## Abre todos los mapas solo en esta sesión (no se guarda).
func unlock_everything_for_session() -> void:
	_ensure()
	data.unlock_everything()
	progress_changed.emit()


func _ensure() -> void:
	if data == null:
		load_progress()
