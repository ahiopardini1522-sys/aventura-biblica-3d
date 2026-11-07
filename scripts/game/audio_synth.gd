class_name AudioSynth
extends RefCounted
## Sonidos sencillos generados por código (clic, confirmación, dado).
## Sirven mientras no haya archivos de audio en assets/audio.

const MIX_RATE := 22050
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


static func _render(duration: float, sampler: Callable) -> AudioStreamWAV:
	var count: int = int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / float(MIX_RATE)
		var sample: float = clampf(float(sampler.call(t)), -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
