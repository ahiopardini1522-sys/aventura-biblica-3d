class_name AmbiencePlayer
extends AudioStreamPlayer
## Reproduce en bucle el sonido ambiental de un mundo (jardín, mar, viento...), con entrada suave.
## Va por el bus «Music», así que lo controla el volumen de música de Configuración.
## Se agrega a la escena (add_child) y se llama a start(); al cambiar de escena se apaga solo.
## Aquí no se nombran los autoloads, para que este script también compile en las pruebas.

const BUS := "Music"
const VOLUME_DB := -9.0
const SILENT_DB := -60.0
const FADE_IN := 1.6

## Sonido que está sonando ("" si ninguno).
var kind: String = ""
## Volumen al que llega después de la entrada suave.
var target_db: float = VOLUME_DB

var _fade: Tween


## Empieza el sonido "sound" (uno de AmbienceSynth.KINDS). Uno desconocido lo deja en silencio.
func start(sound: String, fade_seconds: float = FADE_IN, volume_db_target: float = VOLUME_DB) -> void:
	_stop_fade()
	if not AmbienceSynth.has_kind(sound):
		kind = ""
		stop()
		return
	kind = sound
	target_db = volume_db_target
	bus = BUS
	stream = AmbienceSynth.ambience(sound)
	var fade_in: bool = fade_seconds > 0.0 and is_inside_tree()
	volume_db = SILENT_DB if fade_in else target_db
	if not is_inside_tree():
		# Todavía no está en la escena: empezará sola al entrar (sin entrada suave).
		autoplay = true
		return
	play()
	if fade_in:
		_fade = create_tween()
		_fade.tween_property(self, "volume_db", target_db, fade_seconds)


## Lo apaga con una bajada suave (o de golpe si "fade_seconds" es 0).
func fade_out(fade_seconds: float = 0.8) -> void:
	_stop_fade()
	kind = ""
	if not playing:
		return
	if fade_seconds <= 0.0 or not is_inside_tree():
		stop()
		return
	_fade = create_tween()
	_fade.tween_property(self, "volume_db", SILENT_DB, fade_seconds)
	_fade.tween_callback(stop)


func _stop_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
