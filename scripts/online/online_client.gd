class_name OnlineClient
extends RefCounted
## Cliente de la conexión en línea: máquina de estados que conecta, saluda al servidor, mantiene
## el latido, reanuda la sesión después de un corte y reintenta con espera creciente.
##
## No usa nodos ni temporizadores: quien lo use (el autoload OnlineManager, o las pruebas) llama a
## tick(delta) cada fotograma. Así las pruebas pueden simular el paso del tiempo sin esperar.
## El transporte (WebSocketTransport en el juego, un doble en las pruebas) se inyecta por fábrica.
##
##   IDLE        sin conexión (no se pidió conectar)
##   CONNECTING  abriendo la conexión
##   HANDSHAKE   conexión abierta, esperando la respuesta ("welcome") al saludo ("hello")
##   ONLINE      conectado y con sesión
##   WAITING     se cortó: esperando para reintentar
##   FAILED      no se reintentará solo (ver fail_code)

signal state_changed(new_state: int)
signal welcomed(info: Dictionary)
signal stats_received(online: int)
signal server_error(code: String, text: String)
## Mensajes del servidor que no son de conexión (salas, turnos...; fases siguientes).
signal message_received(message: Dictionary)
signal connection_lost(will_retry: bool)

enum State { IDLE, CONNECTING, HANDSHAKE, ONLINE, WAITING, FAILED }

const CONNECT_TIMEOUT := 10.0
const HELLO_TIMEOUT := 8.0
const PING_INTERVAL := 20.0
const PONG_TIMEOUT := 10.0
const RESUME_CHECK_TIMEOUT := 4.0
const BACKOFF_BASE := 1.0
const BACKOFF_SLOW_BASE := 5.0
const BACKOFF_MAX := 30.0
const MAX_AUTO_RETRIES := 10
const GRACE_SECONDS := 1.0

const FAIL_NO_SERVER := "no_server"
const FAIL_BAD_CLIENT := "bad_client"
const FAIL_BAD_VERSION := "bad_version"
const FAIL_REPLACED := "replaced"
const FAIL_UNREACHABLE := "unreachable"

var state: int = State.IDLE
var online_count: int = 0
var session: String = ""
var resumed: bool = false
## Reintentos seguidos sin éxito.
var attempt: int = 0
var fail_code: String = ""
var last_close_code: int = -1
var last_error_code: String = ""
## Milisegundos del último latido (-1 si todavía no hubo uno).
var ping_ms: int = -1
## Las pruebas lo desactivan para que las esperas sean exactas.
var jitter_enabled: bool = true

var _transport_factory: Callable
var _transport: OnlineTransport
var _dying: Array = []
var _ws_url: String = ""
var _client_id: String = ""
var _player_name: String = OnlineProtocol.DEFAULT_NAME
var _app_version: String = ""
var _wanted: bool = false
var _now: float = 0.0
var _deadline: float = 0.0
var _next_ping_at: float = 0.0
var _pong_deadline: float = -1.0
var _ping_sent_at: float = -1.0
var _rng := RandomNumberGenerator.new()


func _init(transport_factory: Callable = Callable()) -> void:
	_transport_factory = transport_factory
	_rng.randomize()


## Cambia cómo se crea el transporte (las pruebas ponen uno falso).
func set_transport_factory(factory: Callable) -> void:
	_transport_factory = factory


func configure(base_url: String, client_id: String, player_name: String, app_version: String) -> void:
	_ws_url = OnlineConfig.to_ws_url(base_url)
	_client_id = client_id
	var cleaned: String = OnlineProtocol.clean_name(player_name)
	_player_name = cleaned if not cleaned.is_empty() else OnlineProtocol.DEFAULT_NAME
	_app_version = app_version


func has_server() -> bool:
	return not _ws_url.is_empty()


## Hay algo en marcha: conexión, espera para reintentar o cierre en curso.
func is_busy() -> bool:
	return state in [State.CONNECTING, State.HANDSHAKE, State.ONLINE, State.WAITING] or not _dying.is_empty()


func is_online() -> bool:
	return state == State.ONLINE


# ---------------------------------------------------------------- Órdenes

func start() -> void:
	_wanted = true
	if _ws_url.is_empty():
		_fail(FAIL_NO_SERVER)
		return
	if not OnlineProtocol.is_valid_client_id(_client_id):
		_fail(FAIL_BAD_CLIENT)
		return
	if state in [State.CONNECTING, State.HANDSHAKE, State.ONLINE]:
		return
	attempt = 0
	fail_code = ""
	_connect()


## Termina la conexión de forma ordenada: avisa al servidor para que no guarde la sesión.
func stop() -> void:
	_wanted = false
	if _transport != null and state == State.ONLINE:
		_transport.send_text(OnlineProtocol.bye())
		session = ""
	_drop_transport(true)
	attempt = 0
	_set_state(State.IDLE)


## Pide el número de jugadores conectados (la respuesta llega por stats_received).
func request_stats() -> bool:
	return _send(OnlineProtocol.stats_request())


## Envía un mensaje de juego (fases siguientes). Solo con la conexión lista.
func send_message(message: Dictionary) -> bool:
	if state != State.ONLINE:
		return false
	var text: String = JSON.stringify(message)
	if text.length() > OnlineProtocol.MAX_MESSAGE_CHARS:
		return false
	return _send(text)


## Corta la conexión actual como si se hubiera caído la red, y se reintenta como en un corte real.
## Solo lo usan las pruebas (tools/online_e2e.gd) para comprobar la reanudación de la sesión.
func simulate_network_drop() -> void:
	if _transport == null:
		return
	_lose_connection()


## El teléfono volvió a primer plano: comprueba enseguida si la conexión sigue viva.
func check_now() -> void:
	match state:
		State.ONLINE:
			_send_ping(RESUME_CHECK_TIMEOUT)
		State.WAITING:
			_deadline = _now


# ---------------------------------------------------------------- Avance del tiempo

func tick(delta: float) -> void:
	_now += delta
	_tick_dying()
	var transport: OnlineTransport = _transport
	if transport != null:
		for event in transport.poll():
			if transport != _transport:
				break # la conexión se descartó mientras se atendían los hechos
			_handle_event(event as Dictionary)
	_check_timers()


## Segundos de espera antes del reintento número "attempt" (1, 2, 3...). "unit" (0 a 1) mueve la espera ±20 %.
static func backoff_delay(attempt_number: int, slow: bool, unit: float = 0.5) -> float:
	var base: float = BACKOFF_SLOW_BASE if slow else BACKOFF_BASE
	var wait: float = minf(BACKOFF_MAX, base * pow(2.0, float(maxi(attempt_number, 1) - 1)))
	return wait * (1.0 + 0.2 * (2.0 * clampf(unit, 0.0, 1.0) - 1.0))


static func state_name(value: int) -> String:
	match value:
		State.IDLE:
			return "IDLE"
		State.CONNECTING:
			return "CONNECTING"
		State.HANDSHAKE:
			return "HANDSHAKE"
		State.ONLINE:
			return "ONLINE"
		State.WAITING:
			return "WAITING"
		State.FAILED:
			return "FAILED"
	return "?"


# ---------------------------------------------------------------- Hechos del transporte

func _handle_event(event: Dictionary) -> void:
	match str(event.get("kind", "")):
		OnlineTransport.EVENT_OPEN:
			_on_open()
		OnlineTransport.EVENT_MESSAGE:
			_on_message(str(event.get("text", "")))
		OnlineTransport.EVENT_CLOSE:
			_on_close(int(event.get("code", -1)), str(event.get("reason", "")))


func _on_open() -> void:
	if state != State.CONNECTING:
		return
	_send(OnlineProtocol.hello(_client_id, _player_name, _app_version, session))
	_deadline = _now + HELLO_TIMEOUT
	_set_state(State.HANDSHAKE)


func _on_message(text: String) -> void:
	# Cualquier mensaje prueba que la conexión sigue viva.
	_pong_deadline = -1.0
	if text == OnlineProtocol.PONG:
		_on_pong()
		return
	var message: Dictionary = OnlineProtocol.parse(text)
	if message.is_empty():
		return
	match str(message["t"]):
		"welcome":
			_on_welcome(message)
		"stats":
			online_count = int(message.get("online", online_count))
			stats_received.emit(online_count)
		"pong":
			_on_pong()
		"error":
			last_error_code = str(message.get("code", ""))
			server_error.emit(last_error_code, str(message.get("msg", "")))
		"bye":
			if str(message.get("reason", "")) == "replaced":
				_fail(FAIL_REPLACED)
		_:
			message_received.emit(message)


func _on_pong() -> void:
	if _ping_sent_at >= 0.0:
		ping_ms = int(round((_now - _ping_sent_at) * 1000.0))
		_ping_sent_at = -1.0


func _on_welcome(message: Dictionary) -> void:
	if state != State.HANDSHAKE:
		return
	var token: String = str(message.get("session", ""))
	session = token if OnlineProtocol.is_valid_session(token) else ""
	resumed = bool(message.get("resumed", false))
	online_count = int(message.get("online", 0))
	attempt = 0
	last_error_code = ""
	_next_ping_at = _now + PING_INTERVAL
	_pong_deadline = -1.0
	_ping_sent_at = -1.0
	_set_state(State.ONLINE)
	welcomed.emit(message)


func _on_close(code: int, _reason: String) -> void:
	last_close_code = code
	var was_online: bool = state == State.ONLINE
	_drop_transport(false)
	if not _wanted:
		_set_state(State.IDLE)
		return
	if code == OnlineProtocol.CLOSE_REPLACED:
		_fail(FAIL_REPLACED)
		return
	if code == OnlineProtocol.CLOSE_BAD_VERSION:
		_fail(FAIL_BAD_VERSION)
		return
	var slow: bool = code in [
		OnlineProtocol.CLOSE_RATE_LIMITED,
		OnlineProtocol.CLOSE_TOO_MANY,
		OnlineProtocol.CLOSE_HANDSHAKE_TIMEOUT,
		OnlineProtocol.CLOSE_BAD_MESSAGE,
	]
	_retry_later(slow, was_online)


# ---------------------------------------------------------------- Tiempo y reintentos

func _check_timers() -> void:
	match state:
		State.CONNECTING, State.HANDSHAKE:
			if _now >= _deadline:
				_lose_connection()
		State.WAITING:
			if _now >= _deadline:
				_connect()
		State.ONLINE:
			if _pong_deadline >= 0.0:
				if _now >= _pong_deadline:
					_lose_connection()
			elif _now >= _next_ping_at:
				_send_ping(PONG_TIMEOUT)


func _send_ping(wait: float) -> void:
	if _transport == null:
		return
	_transport.send_text(OnlineProtocol.PING)
	_ping_sent_at = _now
	_pong_deadline = _now + wait
	_next_ping_at = _now + PING_INTERVAL


## La conexión no responde: se descarta y se reintenta.
func _lose_connection() -> void:
	var was_online: bool = state == State.ONLINE
	_drop_transport(false)
	_retry_later(false, was_online)


func _retry_later(slow: bool, announce: bool) -> void:
	attempt += 1
	if attempt > MAX_AUTO_RETRIES:
		if announce:
			connection_lost.emit(false)
		_fail(FAIL_UNREACHABLE)
		return
	var unit: float = _rng.randf() if jitter_enabled else 0.5
	_deadline = _now + backoff_delay(attempt, slow, unit)
	if announce:
		connection_lost.emit(true)
	_set_state(State.WAITING)


func _connect() -> void:
	_drop_transport(false)
	_transport = _make_transport()
	var err: int = _transport.open(_ws_url)
	if err != OK:
		_drop_transport(false)
		_retry_later(false, false)
		return
	_deadline = _now + CONNECT_TIMEOUT
	_ping_sent_at = -1.0
	_pong_deadline = -1.0
	_set_state(State.CONNECTING)


func _make_transport() -> OnlineTransport:
	if _transport_factory.is_valid():
		var made: Variant = _transport_factory.call()
		if made is OnlineTransport:
			return made as OnlineTransport
	return WebSocketTransport.new()


func _fail(code: String) -> void:
	_wanted = false
	fail_code = code
	_drop_transport(false)
	_set_state(State.FAILED)


func _send(text: String) -> bool:
	if _transport == null:
		return false
	return _transport.send_text(text) == OK


## Suelta la conexión actual. Con "graceful" pide un cierre ordenado y le da un segundo de plazo.
func _drop_transport(graceful: bool) -> void:
	if _transport == null:
		return
	var transport: OnlineTransport = _transport
	_transport = null
	if graceful and transport.is_open():
		transport.close(OnlineProtocol.CLOSE_NORMAL, "bye")
		transport.poll()
		_dying.append({"transport": transport, "until": _now + GRACE_SECONDS})
	else:
		transport.close(OnlineProtocol.CLOSE_NORMAL, "")


func _tick_dying() -> void:
	for i in range(_dying.size() - 1, -1, -1):
		var entry: Dictionary = _dying[i]
		var transport: OnlineTransport = entry["transport"]
		var finished: bool = false
		for event in transport.poll():
			if str((event as Dictionary).get("kind", "")) == OnlineTransport.EVENT_CLOSE:
				finished = true
		if finished or _now >= float(entry["until"]):
			_dying.remove_at(i)


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)
