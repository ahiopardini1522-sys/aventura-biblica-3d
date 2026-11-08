class_name AmbienceSynth
extends RefCounted
## Sonidos ambientales de cada mundo, generados por código (todavía no hay archivos de audio).
##
## Cada uno es un bucle corto (SECONDS) que se repite sin cortes:
##  - el ruido se filtra «en círculo»: el filtro arranca con el estado del final del bucle;
##  - los adornos (pájaros, campanas, olas...) dan la vuelta al llegar al final;
##  - los tonos largos tienen un número entero de ciclos por bucle.
## Los nombres coinciden con el campo "ambience" de data/maps/maps.json:
##   garden (Edén), sea (Arca de Noé), wind (Egipto), desert (Desierto del Sinaí),
##   mountain (Monte Sinaí), city (Jerusalén) y night (Belén).

const KINDS: Array[String] = ["garden", "sea", "wind", "desert", "mountain", "city", "night"]
const FALLBACK := "wind"
const RATE := 11025
const SECONDS := 5.0
## Muestras que se «calientan» antes de filtrar (la memoria de un filtro simple es mucho menor).
const WARM := 2048
## Varianza del ruido uniforme entre -1 y 1.
const WHITE_VARIANCE := 1.0 / 3.0
## Volumen medio (RMS) de cada sonido, de 0 a 1.
const LEVELS: Dictionary = {
	"garden": 0.12, "sea": 0.14, "wind": 0.13, "desert": 0.10, "mountain": 0.12, "city": 0.11, "night": 0.10,
}

static var _cache: Dictionary = {}


static func has_kind(kind: String) -> bool:
	return KINDS.has(kind)


## Cantidad de muestras de cada bucle.
static func frames() -> int:
	return int(SECONDS * float(RATE))


## Sonido en bucle del mundo "kind" (se genera una vez y se guarda). Un nombre desconocido da el viento.
static func ambience(kind: String) -> AudioStreamWAV:
	var key: String = kind if KINDS.has(kind) else FALLBACK
	if not _cache.has(key):
		_cache[key] = _build(key)
	return _cache[key]


static func _build(kind: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4243 + KINDS.find(kind) * 101
	var mix: PackedFloat32Array
	if kind == "garden":
		mix = _garden(rng)
	elif kind == "sea":
		mix = _sea(rng)
	elif kind == "desert":
		mix = _desert(rng)
	elif kind == "mountain":
		mix = _mountain(rng)
	elif kind == "city":
		mix = _city(rng)
	elif kind == "night":
		mix = _night(rng)
	else:
		mix = _wind(rng)
	return _to_stream(mix, float(LEVELS.get(kind, 0.12)))


# ---------------------------------------------------------------- Los siete ambientes

## Edén: arroyo, brisa suave y pájaros.
static func _garden(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var mix: PackedFloat32Array = _silence()
	mix = _add(mix, _band(_white(rng), 450.0, 2800.0), _envelope(6.0, 0.0, 1, 0.55), 1.0)
	mix = _add(mix, _smooth(_white(rng), 240.0), _envelope(1.0, -PI * 0.5, 2, 0.2), 0.8)
	for k in 9:
		var start: float = (float(k) + rng.randf_range(0.15, 0.85)) * SECONDS / 9.0
		var base: float = rng.randf_range(2500.0, 4100.0)
		var rising: bool = rng.randf() < 0.5
		var ratio: float = 1.22 if rising else 0.8
		var notes: int = rng.randi_range(2, 4)
		for j in notes:
			var f0: float = base * (1.0 + 0.06 * float(j))
			mix = _note(mix, start + float(j) * 0.14, f0, f0 * ratio, 0.11, 1.5, 0.15, 0.0)
	return mix


## Arca de Noé: oleaje, espuma y dos gaviotas.
static func _sea(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var mix: PackedFloat32Array = _silence()
	mix = _add(mix, _smooth(_white(rng), 140.0), _envelope(2.0, 0.0, 1, 0.6), 0.9)
	mix = _add(mix, _band(_white(rng), 120.0, 1400.0), _envelope(2.0, -PI * 0.5, 2, 0.1), 1.5)
	mix = _add(mix, _band(_white(rng), 1500.0, 5000.0), _envelope(2.0, -PI * 0.5 + 0.9, 3, 0.02), 0.55)
	mix = _note(mix, 1.1, 2500.0, 1700.0, 0.5, 0.9, 0.3, 2.0)
	mix = _note(mix, 3.6, 2300.0, 1500.0, 0.42, 0.8, 0.3, 2.0)
	return mix


## Egipto: ráfagas de viento y un silbido lejano.
static func _wind(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var mix: PackedFloat32Array = _silence()
	mix = _add(mix, _smooth(_white(rng), 300.0), _envelope(1.0, 0.0, 2, 0.25), 1.2)
	mix = _add(mix, _band(_white(rng), 380.0, 1600.0), _envelope(2.0, 1.7, 2, 0.12), 1.0)
	mix = _add(mix, _band(_white(rng), 1800.0, 4800.0), _envelope(3.0, 0.6, 3, 0.05), 0.45)
	mix = _note(mix, 1.4, 880.0, 1180.0, 1.9, 0.16, 0.0, 1.5)
	return mix


## Desierto del Sinaí: viento seco, arena y un halcón.
static func _desert(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var mix: PackedFloat32Array = _silence()
	mix = _add(mix, _smooth(_white(rng), 220.0), _envelope(1.0, 0.0, 1, 0.35), 1.0)
	mix = _add(mix, _band(_white(rng), 2600.0, 5000.0), _envelope(2.0, 0.4, 3, 0.08), 0.3)
	mix = _note(mix, 2.2, 2700.0, 1900.0, 0.55, 0.9, 0.35, 3.0)
	mix = _note(mix, 2.8, 2500.0, 1800.0, 0.4, 0.7, 0.35, 3.0)
	return mix


## Monte Sinaí: acordes celestiales que respiran, viento alto y un trueno lejano.
static func _mountain(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var mix: PackedFloat32Array = _silence()
	mix = _add(mix, _smooth(_white(rng), 520.0), _envelope(1.0, 0.0, 2, 0.3), 0.9)
	mix = _add(mix, _smooth(_white(rng), 190.0), _bump(1.2, 2.6, 0.0), 1.6)
	# Frecuencias = ciclos / SECONDS: 110, 165, 220, 330, 440 y 660 Hz, con parejas desafinadas
	# unas décimas de hertz para que el sonido brille y se mueva despacio.
	mix = _tone(mix, 550, 0.55, 1.0, 0.0)
	mix = _tone(mix, 551, 0.45, 1.0, 1.6)
	mix = _tone(mix, 825, 0.5, 2.0, 0.7)
	mix = _tone(mix, 1100, 0.45, 1.0, 2.4)
	mix = _tone(mix, 1103, 0.35, 2.0, 0.2)
	mix = _tone(mix, 1650, 0.3, 3.0, 1.1)
	mix = _tone(mix, 2200, 0.22, 2.0, 3.0)
	mix = _tone(mix, 3300, 0.12, 3.0, 0.5)
	return mix


## Jerusalén: murmullo de la ciudad, campanas y un shofar lejano.
static func _city(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var mix: PackedFloat32Array = _silence()
	mix = _add(mix, _band(_white(rng), 250.0, 1100.0), _envelope(5.0, 0.3, 1, 0.45), 1.0)
	mix = _add(mix, _band(_white(rng), 600.0, 2200.0), _envelope(7.0, 2.0, 1, 0.35), 0.45)
	mix = _bell(mix, 0.9, 784.0, 2.0, 0.55)
	mix = _bell(mix, 3.4, 587.3, 2.0, 0.5)
	mix = _note(mix, 1.9, 262.0, 294.0, 1.3, 0.8, 0.55, 0.0)
	mix = _note(mix, 1.9, 786.0, 882.0, 1.3, 0.25, 0.0, 0.0)
	return mix


## Belén: noche en calma, grillos y campanitas de estrellas.
static func _night(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var mix: PackedFloat32Array = _silence()
	mix = _add(mix, _smooth(_white(rng), 170.0), _envelope(1.0, 0.9, 1, 0.4), 0.8)
	# Dos grillos: cada canto son tres golpecitos; su volumen sube y baja varias veces por vuelta.
	for g in 25:
		var presence: float = 0.25 + 0.75 * (0.5 + 0.5 * sin(TAU * 2.0 * float(g) / 25.0))
		for p in 3:
			mix = _note(mix, float(g) * 0.2 + 0.012 + float(p) * 0.045, 4300.0, 4300.0, 0.03,
					0.5 * presence, 0.0, 0.0)
	for g in 22:
		var presence: float = 0.25 + 0.75 * (0.5 + 0.5 * sin(TAU * 3.0 * float(g) / 22.0 + 1.0))
		for p in 3:
			mix = _note(mix, float(g) * SECONDS / 22.0 + 0.07 + float(p) * 0.05, 4800.0, 4800.0, 0.03,
					0.4 * presence, 0.0, 0.0)
	mix = _bell(mix, 0.6, 1568.0, 1.8, 0.35)
	mix = _bell(mix, 2.3, 1318.5, 1.8, 0.33)
	mix = _bell(mix, 3.7, 1046.5, 1.8, 0.3)
	return mix


# ---------------------------------------------------------------- Ruido y filtros

static func _silence() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames())
	return out


## Ruido blanco (uniforme entre -1 y 1).
static func _white(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n: int = frames()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randf() * 2.0 - 1.0
	return out


static func _coefficient(cutoff: float) -> float:
	return 1.0 - exp(-TAU * cutoff / float(RATE))


## Filtro de un polo que cierra el círculo: antes de empezar se calienta con el final del bucle,
## así que la última muestra y la primera encajan sin salto.
static func _filter(input: PackedFloat32Array, coef: float, gain: float) -> PackedFloat32Array:
	var n: int = input.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var y: float = 0.0
	for i in range(n - WARM, n):
		y += coef * (input[i] - y)
	for i in n:
		y += coef * (input[i] - y)
		out[i] = y * gain
	return out


## Ruido blanco suavizado (paso bajo), con volumen medio 1.
static func _smooth(input: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var coef: float = _coefficient(cutoff)
	return _filter(input, coef, 1.0 / sqrt(WHITE_VARIANCE * coef / (2.0 - coef)))


## Ruido blanco entre dos frecuencias (diferencia de dos pasos bajos), con volumen medio 1.
static func _band(input: PackedFloat32Array, low_cut: float, high_cut: float) -> PackedFloat32Array:
	var c_high: float = _coefficient(high_cut)
	var c_low: float = _coefficient(low_cut)
	var variance: float = WHITE_VARIANCE * (c_high / (2.0 - c_high) + c_low / (2.0 - c_low)
			- 2.0 * c_high * c_low / (1.0 - (1.0 - c_high) * (1.0 - c_low)))
	var gain: float = 1.0 / sqrt(maxf(variance, 0.000001))
	var high: PackedFloat32Array = _filter(input, c_high, 1.0)
	var low: PackedFloat32Array = _filter(input, c_low, 1.0)
	for i in high.size():
		high[i] = (high[i] - low[i]) * gain
	return high


# ---------------------------------------------------------------- Envolventes

## Sube y baja "cycles" veces por bucle (un número entero, para que cierre bien), de "floor_level" a 1.
## power: 1 suave, 2 picuda (olas, ráfagas), 3 muy picuda.
static func _envelope(cycles: float, phase: float, power: int, floor_level: float) -> PackedFloat32Array:
	var n: int = frames()
	var out := PackedFloat32Array()
	out.resize(n)
	var speed: float = TAU * cycles / float(n)
	for i in n:
		var v: float = 0.5 + 0.5 * sin(speed * float(i) + phase)
		if power >= 2:
			v *= v
		if power >= 3:
			v *= v
		out[i] = floor_level + (1.0 - floor_level) * v
	return out


## Una sola «colina» suave que empieza en start_s y dura length_s (da la vuelta al final del bucle).
static func _bump(start_s: float, length_s: float, floor_level: float) -> PackedFloat32Array:
	var n: int = frames()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = floor_level
	var first: int = int(start_s * float(RATE))
	var count: int = int(length_s * float(RATE))
	for j in count:
		var w: float = sin(PI * float(j) / float(count))
		out[(first + j) % n] = floor_level + (1.0 - floor_level) * w * w
	return out


# ---------------------------------------------------------------- Mezcla y sonidos sueltos

## Suma a "mix" una capa de ruido por su envolvente (puede ir vacía) y su ganancia.
static func _add(mix: PackedFloat32Array, layer: PackedFloat32Array, envelope: PackedFloat32Array,
		gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = mix
	var n: int = out.size()
	if envelope.size() == n:
		for i in n:
			out[i] += layer[i] * envelope[i] * gain
	else:
		for i in n:
			out[i] += layer[i] * gain
	return out


## Un tono largo con "cycles" ciclos por bucle (frecuencia = cycles / SECONDS) que «respira».
static func _tone(mix: PackedFloat32Array, cycles: int, gain: float, breath_cycles: float,
		breath_phase: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = mix
	var n: int = out.size()
	var carrier: float = TAU * float(cycles) / float(n)
	var breath: float = TAU * breath_cycles / float(n)
	for i in n:
		var amp: float = 0.6 + 0.4 * sin(breath * float(i) + breath_phase)
		out[i] += sin(carrier * float(i)) * amp * gain
	return out


## Una nota con barrido de frecuencia, un armónico y vibrato (pájaros, gaviotas, grillos, shofar).
## Empieza en start_s y da la vuelta al llegar al final del bucle.
static func _note(mix: PackedFloat32Array, start_s: float, f0: float, f1: float, length_s: float,
		gain: float, overtone: float, wobble: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = mix
	var n: int = out.size()
	var count: int = int(length_s * float(RATE))
	var first: int = int(start_s * float(RATE))
	var slope: float = (f1 - f0) / length_s
	for j in count:
		var dt: float = float(j) / float(RATE)
		var env: float = sin(PI * float(j) / float(count))
		env *= env
		var phase: float = TAU * (f0 * dt + 0.5 * slope * dt * dt)
		if wobble > 0.0:
			phase += wobble * sin(TAU * 6.0 * dt)
		var v: float = sin(phase)
		if overtone > 0.0:
			v += overtone * sin(phase * 2.0)
		out[(first + j) % n] += v * env * gain
	return out


## Una campana: cuatro parciales que se apagan cada vez más rápido (el mismo decaimiento, elevado).
static func _bell(mix: PackedFloat32Array, start_s: float, freq: float, length_s: float,
		gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = mix
	var n: int = out.size()
	var count: int = int(length_s * float(RATE))
	var first: int = int(start_s * float(RATE))
	for j in count:
		var dt: float = float(j) / float(RATE)
		var d1: float = exp(-dt * 2.2)
		var d2: float = d1 * d1
		var d3: float = d2 * d1
		var v: float = sin(TAU * freq * dt) * d1
		v += 0.5 * sin(TAU * freq * 2.01 * dt) * d2
		v += 0.3 * sin(TAU * freq * 2.76 * dt) * d3
		v += 0.15 * sin(TAU * freq * 5.4 * dt) * d2 * d2
		out[(first + j) % n] += v * minf(1.0, dt * 400.0) * gain
	return out


## Lleva la mezcla al volumen medio "target_rms", la limita y la guarda como bucle de 16 bits.
static func _to_stream(mix: PackedFloat32Array, target_rms: float) -> AudioStreamWAV:
	var n: int = mix.size()
	var energy: float = 0.0
	for i in n:
		energy += mix[i] * mix[i]
	var gain: float = target_rms / maxf(sqrt(energy / float(n)), 0.000001)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v: float = clampf(mix[i] * gain, -0.95, 0.95)
		data.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav
