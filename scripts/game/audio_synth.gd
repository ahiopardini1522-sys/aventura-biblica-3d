class_name AudioSynth
extends RefCounted
## Sonidos sencillos generados por código (clic, confirmación, dado, pasos, escalera,
## serpiente, acierto, error, estrella y victoria).
## Sirven mientras no haya archivos de audio en assets/audio.

const MIX_RATE := 22050
const WIN_RATE := 16000
const DICE_HITS: Array = [0.0, 0.07, 0.14, 0.2, 0.26, 0.31, 0.36, 0.41, 0.46, 0.52, 0.6, 0.7, 0.82]

static var _cache: Dictionary = {}
static var _noise: RandomNumberGenerator


static func click() -> AudioStreamWAV:
	if not _cache.has("click"):
		_cache["click"] = _render(0.07, _sample_click)
	return _cache["click"]


static func confirm() -> AudioStreamWAV:
	if not _cache.has("confirm"):
		_cache["confirm"] = _render(0.42, _sample_confirm)
	return _cache["confirm"]


static func dice_roll() -> AudioStreamWAV:
	if not _cache.has("dice_roll"):
		_noise = RandomNumberGenerator.new()
		_noise.seed = 7
		_cache["dice_roll"] = _render(1.0, _sample_dice)
	return _cache["dice_roll"]


## Genera todos los sonidos de una vez (se llama al abrir el tablero, detrás del fundido,
## para que no haya tirones durante la partida).
static func warm_up() -> void:
	click()
	confirm()
	dice_roll()
	step()
	ladder()
	snake()
	correct()
	wrong()
	star()
	win()


static func step() -> AudioStreamWAV:
	if not _cache.has("step"):
		_cache["step"] = _render(0.09, _sample_step)
	return _cache["step"]


static func ladder() -> AudioStreamWAV:
	if not _cache.has("ladder"):
		_cache["ladder"] = _render(0.8, _sample_ladder)
	return _cache["ladder"]


static func snake() -> AudioStreamWAV:
	if not _cache.has("snake"):
		_cache["snake"] = _render(0.95, _sample_snake)
	return _cache["snake"]


static func correct() -> AudioStreamWAV:
	if not _cache.has("correct"):
		_cache["correct"] = _render(0.75, _sample_correct)
	return _cache["correct"]


static func wrong() -> AudioStreamWAV:
	if not _cache.has("wrong"):
		_cache["wrong"] = _render(0.6, _sample_wrong)
	return _cache["wrong"]


static func star() -> AudioStreamWAV:
	if not _cache.has("star"):
		_cache["star"] = _render(0.4, _sample_star)
	return _cache["star"]


static func win() -> AudioStreamWAV:
	if not _cache.has("win"):
		_cache["win"] = _render(2.4, _sample_win, WIN_RATE)
	return _cache["win"]


static func _sample_click(t: float) -> float:
	return sin(TAU * 1500.0 * t) * exp(-t * 60.0) * 0.5


static func _sample_confirm(t: float) -> float:
	var first: float = sin(TAU * 660.0 * t) * exp(-t * 9.0)
	var second: float = 0.0
	if t >= 0.14:
		var t2: float = t - 0.14
		second = sin(TAU * 880.0 * t2) * exp(-t2 * 8.0)
	return (first + second) * 0.35


static func _sample_dice(t: float) -> float:
	var value: float = 0.0
	for hit in DICE_HITS:
		var dt: float = t - float(hit)
		if dt >= 0.0 and dt < 0.05:
			value += (_noise.randf() * 2.0 - 1.0) * exp(-dt * 90.0)
	return value * 0.35


## Una nota suave: seno con un pequeño armónico, ataque corto y caída exponencial.
static func _tone(t: float, start: float, freq: float, length: float, decay: float,
		harmonic: float = 0.0) -> float:
	var dt: float = t - start
	if dt < 0.0 or dt > length:
		return 0.0
	var envelope: float = exp(-dt * decay) * minf(1.0, dt * 300.0)
	var wave: float = sin(TAU * freq * dt)
	if harmonic > 0.0:
		wave += harmonic * sin(TAU * freq * 2.0 * dt)
	return wave * envelope


static func _sample_step(t: float) -> float:
	return _tone(t, 0.0, 540.0, 0.09, 42.0) * 0.4


static func _sample_ladder(t: float) -> float:
	var value: float = 0.0
	value += _tone(t, 0.0, 523.25, 0.4, 7.0, 0.25)
	value += _tone(t, 0.12, 659.25, 0.4, 7.0, 0.25)
	value += _tone(t, 0.24, 783.99, 0.4, 7.0, 0.25)
	value += _tone(t, 0.36, 1046.5, 0.44, 6.0, 0.25)
	return value * 0.26


## Silbido que cae de agudo a grave, con un poco de vibrato.
static func _sample_snake(t: float) -> float:
	var duration: float = 0.95
	var f0: float = 820.0
	var f1: float = 170.0
	var phase: float = TAU * (f0 * t + 0.5 * (f1 - f0) / duration * t * t)
	var wobble: float = 1.0 + 0.12 * sin(TAU * 7.0 * t)
	var envelope: float = exp(-t * 1.6) * minf(1.0, t * 80.0)
	return (sin(phase) + 0.3 * sin(phase * 2.0)) * wobble * envelope * 0.3


static func _sample_correct(t: float) -> float:
	var value: float = 0.0
	value += _tone(t, 0.0, 783.99, 0.5, 6.0, 0.2)
	value += _tone(t, 0.12, 1046.5, 0.5, 6.0, 0.2)
	value += _tone(t, 0.24, 1318.5, 0.5, 5.0, 0.2)
	return value * 0.27


static func _sample_wrong(t: float) -> float:
	var duration: float = 0.6
	var f0: float = 330.0
	var f1: float = 190.0
	var phase: float = TAU * (f0 * t + 0.5 * (f1 - f0) / duration * t * t)
	var first: float = sin(phase) * exp(-t * 5.0)
	return (first + _tone(t, 0.2, 196.0, 0.4, 7.0, 0.3)) * 0.4


static func _sample_star(t: float) -> float:
	return (_tone(t, 0.0, 1760.0, 0.25, 14.0) + _tone(t, 0.07, 2349.0, 0.3, 12.0)) * 0.22


static func _sample_win(t: float) -> float:
	var value: float = 0.0
	value += _tone(t, 0.0, 523.25, 0.55, 5.0, 0.25)
	value += _tone(t, 0.22, 659.25, 0.55, 5.0, 0.25)
	value += _tone(t, 0.44, 783.99, 0.55, 5.0, 0.25)
	value += _tone(t, 0.66, 1046.5, 0.6, 5.0, 0.25)
	for chord in [523.25, 659.25, 783.99, 1046.5]:
		value += _tone(t, 1.0, float(chord), 1.4, 2.2, 0.2) * 0.7
	return value * 0.2


static func _render(duration: float, sampler: Callable, rate: int = MIX_RATE) -> AudioStreamWAV:
	var count: int = int(duration * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / float(rate)
		var sample: float = clampf(float(sampler.call(t)), -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
