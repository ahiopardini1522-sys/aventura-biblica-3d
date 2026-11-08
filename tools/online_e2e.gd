extends SceneTree
## Prueba de extremo a extremo del cliente en línea contra un servidor REAL (el de `wrangler dev`
## en CI, o el recién desplegado en Cloudflare). A diferencia del smoke_test (que usa un servidor
## falso), aquí el cliente del juego (OnlineClient + WebSocketTransport) habla de verdad por la red.
##
## Uso:  godot --headless --path . --script res://tools/online_e2e.gd -- --url=http://127.0.0.1:8787
## Termina con código 0 si todo pasa, 1 si algo falla, 2 si faltan argumentos o se agota el tiempo.

const TIME_LIMIT := 150.0

var _checks: int = 0
var _failures: Array[String] = []
var _finished: bool = false
var _base_url: String = ""
var _run_id: String = ""


func _initialize() -> void:
	create_timer(TIME_LIMIT).timeout.connect(_on_time_limit)
	_run()


func _on_time_limit() -> void:
	if _finished:
		return
	_finished = true
	print("TIEMPO AGOTADO: la prueba tardó más de %d s (%d controles hechos)." % [int(TIME_LIMIT), _checks])
	quit(2)


func _run() -> void:
	await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--url="):
			_base_url = argument.substr(6)
	_base_url = OnlineConfig.normalize_base_url(_base_url)
	if _base_url.is_empty():
		print("Falta --url=https://servidor (o http://127.0.0.1:puerto).")
		_finished = true
		quit(2)
		return
	_run_id = OnlineProtocol.make_client_id().substr(0, 12)
	print("=== PRUEBA EN LÍNEA (servidor real): %s  ejecución %s ===" % [_base_url, _run_id])
	print("Motor: %s" % Engine.get_version_info()["string"])

	await _test_connect_and_heartbeat()
	await _test_two_clients()
	await _test_resume_after_drop()
	await _test_same_player_elsewhere()
	await _test_graceful_stop()
	await _test_raw_errors()
	await _test_unreachable_server()

	print("")
	print("=== RESULTADO: %d controles, %d fallos ===" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FALLO: %s" % failure)
	_finished = true
	quit(1 if not _failures.is_empty() else 0)


# ---------------------------------------------------------------- Ayudas

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok     %s" % label)
	else:
		_failures.append(label)
		print("  FALLO  %s" % label)


func _player_id(suffix: String) -> String:
	return "e2e-%s-%s" % [_run_id, suffix]


func _new_client(suffix: String, url: String = "") -> OnlineClient:
	var client := OnlineClient.new()
	client.jitter_enabled = false
	client.configure(_base_url if url.is_empty() else url, _player_id(suffix), "Prueba %s" % suffix, "e2e")
	return client


## Hace avanzar los clientes con el tiempo real hasta que se cumpla la condición o se agote el plazo.
func _pump(clients: Array, condition: Callable, timeout: float = 15.0) -> bool:
	var started: int = Time.get_ticks_msec()
	var last: int = started
	while not bool(condition.call()):
		if Time.get_ticks_msec() - started > int(timeout * 1000.0):
			return false
		await process_frame
		var now: int = Time.get_ticks_msec()
		var delta: float = float(now - last) / 1000.0
		last = now
		for client in clients:
			(client as OnlineClient).tick(delta)
	return true


func _is_online(client: OnlineClient) -> bool:
	return client.state == OnlineClient.State.ONLINE


func _has_ping(client: OnlineClient) -> bool:
	return client.ping_ms >= 0


func _online_count_at_least(client: OnlineClient, count: int) -> bool:
	return client.online_count >= count


func _is_failed(client: OnlineClient) -> bool:
	return client.state == OnlineClient.State.FAILED


func _is_waiting(client: OnlineClient) -> bool:
	return client.state == OnlineClient.State.WAITING


func _is_idle(client: OnlineClient) -> bool:
	return client.state == OnlineClient.State.IDLE


func _both_online(first: OnlineClient, second: OnlineClient) -> bool:
	return first.is_online() and second.is_online()


func _never() -> bool:
	return false


# ---------------------------------------------------------------- Escenarios

func _test_connect_and_heartbeat() -> void:
	print("-- Conexión, saludo y latido")
	var client: OnlineClient = _new_client("a")
	client.start()
	_check(await _pump([client], _is_online.bind(client)), "el cliente se conecta y recibe el welcome del servidor")
	_check(OnlineProtocol.is_valid_session(client.session), "el servidor entrega un código de sesión válido")
	_check(not client.resumed and client.online_count >= 1, "primera conexión: sesión nueva y al menos 1 jugador en línea")
	client.check_now()
	_check(await _pump([client], _has_ping.bind(client), 8.0), "el ping de texto recibe su pong (%d ms)" % client.ping_ms)
	_check(client.state == OnlineClient.State.ONLINE, "el latido mantiene la conexión")
	client.stop()
	_check(await _pump([client], _is_idle.bind(client), 3.0), "stop() deja el cliente en reposo")
	await _pump([client], _never, 1.5)


func _test_two_clients() -> void:
	print("-- Dos jugadores a la vez")
	var first: OnlineClient = _new_client("b1")
	var second: OnlineClient = _new_client("b2")
	first.start()
	second.start()
	_check(await _pump([first, second], _both_online.bind(first, second)), "dos dispositivos distintos se conectan a la vez")
	first.request_stats()
	_check(await _pump([first, second], _online_count_at_least.bind(first, 2), 8.0), "stats cuenta al menos 2 jugadores en línea (%d)" % first.online_count)
	_check(first.session != second.session, "cada jugador tiene su propia sesión")
	first.stop()
	second.stop()
	await _pump([first, second], _never, 1.5)


func _test_resume_after_drop() -> void:
	print("-- Corte de red y reanudación de la sesión")
	var client: OnlineClient = _new_client("c")
	client.start()
	_check(await _pump([client], _is_online.bind(client)), "el cliente se conecta")
	var session: String = client.session
	client.simulate_network_drop()
	_check(client.state == OnlineClient.State.WAITING, "al cortarse la conexión pasa a esperar para reintentar")
	_check(await _pump([client], _is_online.bind(client), 15.0), "reconecta solo después de la espera")
	_check(client.resumed and client.session == session, "el servidor reconoce la sesión anterior (reanudada)")
	_check(client.attempt == 0, "el contador de reintentos vuelve a cero")
	client.simulate_network_drop()
	_check(await _pump([client], _is_online.bind(client), 15.0) and client.resumed and client.session == session,
			"se puede reanudar varias veces seguidas")
	client.stop()
	await _pump([client], _never, 1.5)


func _test_same_player_elsewhere() -> void:
	print("-- El mismo jugador desde otro dispositivo")
	var old_device: OnlineClient = _new_client("d")
	old_device.start()
	_check(await _pump([old_device], _is_online.bind(old_device)), "el primer dispositivo se conecta")
	var new_device: OnlineClient = _new_client("d")
	new_device.session = old_device.session
	new_device.start()
	_check(await _pump([old_device, new_device], _is_failed.bind(old_device), 10.0), "el dispositivo anterior recibe el aviso de reemplazo")
	_check(old_device.fail_code == OnlineClient.FAIL_REPLACED, "el motivo es 'replaced' y no reintenta")
	_check(await _pump([old_device, new_device], _is_online.bind(new_device), 10.0), "el dispositivo nuevo queda conectado")
	_check(new_device.resumed, "el dispositivo nuevo reanuda la sesión con el código que tenía")
	new_device.stop()
	await _pump([old_device, new_device], _never, 1.5)


func _test_graceful_stop() -> void:
	print("-- Despedida voluntaria")
	var client: OnlineClient = _new_client("e")
	client.start()
	_check(await _pump([client], _is_online.bind(client)), "el cliente se conecta")
	var old_session: String = client.session
	client.stop()
	await _pump([client], _never, 1.5)
	var again: OnlineClient = _new_client("e")
	again.session = old_session
	again.start()
	_check(await _pump([again], _is_online.bind(again)), "vuelve a conectarse")
	_check(not again.resumed and again.session != old_session, "tras la despedida el servidor ya no guarda la sesión anterior")
	again.stop()
	await _pump([again], _never, 1.5)


func _test_raw_errors() -> void:
	print("-- Errores del protocolo con la conexión real")
	var url: String = OnlineConfig.to_ws_url(_base_url)

	var garbage := WebSocketTransport.new()
	var inbox: Array = []
	_check(garbage.open(url) == OK, "se abre una conexión sin cliente")
	_check(await _raw_wait(garbage, inbox, OnlineTransport.EVENT_OPEN, 10.0), "la conexión se abre")
	garbage.send_text("esto no es json")
	_check(await _raw_wait(garbage, inbox, OnlineTransport.EVENT_CLOSE, 10.0), "el servidor cierra la conexión ante un mensaje inválido")
	var error_code: String = ""
	var close_code: int = -99
	var close_reason: String = ""
	for event in inbox:
		var entry: Dictionary = event
		if str(entry.get("kind", "")) == OnlineTransport.EVENT_MESSAGE:
			var message: Dictionary = OnlineProtocol.parse(str(entry.get("text", "")))
			if str(message.get("t", "")) == "error":
				error_code = str(message.get("code", ""))
		elif str(entry.get("kind", "")) == OnlineTransport.EVENT_CLOSE:
			close_code = int(entry.get("code", -1))
			close_reason = str(entry.get("reason", ""))
	# El servidor manda un aviso de error y cierra con el mismo motivo escrito en el cierre. Godot puede
	# descartar el aviso si el cierre termina en la misma pasada, así que el motivo del cierre vale igual.
	var reported: String = error_code if not error_code.is_empty() else close_reason
	print("   (aviso de error recibido: '%s'; motivo del cierre: '%s')" % [error_code, close_reason])
	_check(reported == "bad_message", "el servidor explica el motivo ('bad_message') en el aviso o en el cierre")
	_check(close_code == OnlineProtocol.CLOSE_BAD_MESSAGE, "el código de cierre llega al juego intacto (%d)" % close_code)

	var fast := WebSocketTransport.new()
	inbox = []
	fast.open(url)
	await _raw_wait(fast, inbox, OnlineTransport.EVENT_OPEN, 10.0)
	fast.send_text(OnlineProtocol.hello(_player_id("f"), "Rápido", "e2e"))
	_check(await _raw_wait(fast, inbox, OnlineTransport.EVENT_MESSAGE, 10.0), "el saludo recibe respuesta")
	for i in 120:
		fast.send_text("{\"t\":\"ping\"}")
	_check(await _raw_wait(fast, inbox, OnlineTransport.EVENT_CLOSE, 10.0), "el servidor corta a quien manda demasiados mensajes")
	close_code = -99
	for event in inbox:
		var entry: Dictionary = event
		if str(entry.get("kind", "")) == OnlineTransport.EVENT_CLOSE:
			close_code = int(entry.get("code", -1))
	_check(close_code == OnlineProtocol.CLOSE_RATE_LIMITED, "el cierre por límite de velocidad llega como 4003 (%d)" % close_code)


func _raw_wait(transport: WebSocketTransport, inbox: Array, kind: String, timeout: float) -> bool:
	var started: int = Time.get_ticks_msec()
	while true:
		for event in inbox:
			if str((event as Dictionary).get("kind", "")) == kind:
				return true
		if Time.get_ticks_msec() - started > int(timeout * 1000.0):
			return false
		await process_frame
		inbox.append_array(transport.poll())
	return false


func _test_unreachable_server() -> void:
	print("-- Servidor que no responde")
	var client: OnlineClient = _new_client("g", "http://127.0.0.1:9")
	client.start()
	_check(await _pump([client], _is_waiting.bind(client), 10.0), "si no hay servidor, pasa a esperar para reintentar")
	_check(client.attempt >= 1, "el fallo de conexión cuenta como un reintento (código de cierre %d)" % client.last_close_code)
	client.stop()
	_check(client.state == OnlineClient.State.IDLE, "stop() cancela los reintentos")
