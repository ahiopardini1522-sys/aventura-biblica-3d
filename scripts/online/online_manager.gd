extends Node
## Autoload "OnlineManager": la conexión en línea del juego. Guarda la dirección del servidor y la
## identidad anónima del dispositivo, mueve el OnlineClient en cada fotograma y explica en español
## en qué estado está. No se conecta solo al iniciar: la conexión se abre cuando una pantalla la
## pide (fase 4.1: la pantalla Multijugador) y se cierra al salir de ella.

signal status_changed
signal online_count_changed(count: int)

var client: OnlineClient
var server_url: String = ""
var client_id: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	server_url = OnlineConfig.load_server_url()
	client_id = OnlineConfig.load_client_id()
	client = OnlineClient.new()
	client.state_changed.connect(_on_state_changed)
	client.stats_received.connect(_on_stats)
	client.welcomed.connect(_on_welcomed)
	_configure()
	set_process(false)


func _process(delta: float) -> void:
	client.tick(delta)
	if not client.is_busy():
		set_process(false)


func _notification(what: int) -> void:
	if client == null:
		return
	if what == NOTIFICATION_APPLICATION_RESUMED:
		client.check_now()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		client.stop()


# ---------------------------------------------------------------- Órdenes

func is_configured() -> bool:
	return client != null and client.has_server()


## Abre la conexión (o la reintenta si estaba caída).
func connect_to_server() -> void:
	_configure()
	set_process(true)
	client.start()
	status_changed.emit()


## Cierra la conexión de forma ordenada.
func disconnect_from_server() -> void:
	if client == null:
		return
	client.stop()
	status_changed.emit()


## Cambia la dirección del servidor (las pruebas la usan; el juego la lee de data/online.json).
func set_server_url(url: String) -> void:
	server_url = OnlineConfig.normalize_base_url(url)
	_configure()
	status_changed.emit()


# ---------------------------------------------------------------- Estado para la interfaz

## "idle", "busy", "ok", "warn" o "error": la interfaz lo usa para elegir el color.
func status_kind() -> String:
	if not is_configured():
		return "warn"
	match client.state:
		OnlineClient.State.ONLINE:
			return "ok"
		OnlineClient.State.CONNECTING, OnlineClient.State.HANDSHAKE:
			return "busy"
		OnlineClient.State.WAITING:
			return "warn"
		OnlineClient.State.FAILED:
			return "error"
	return "idle"


func status_text() -> String:
	if not is_configured():
		return "Servidor en línea sin configurar."
	match client.state:
		OnlineClient.State.IDLE:
			return "Sin conexión."
		OnlineClient.State.CONNECTING, OnlineClient.State.HANDSHAKE:
			return "Conectando…"
		OnlineClient.State.ONLINE:
			return "Conectado · %s" % online_text(client.online_count)
		OnlineClient.State.WAITING:
			return "Reintentando… (intento %d)" % client.attempt
		OnlineClient.State.FAILED:
			return failure_text(client.fail_code)
	return ""


## Texto con el detalle técnico de la conexión (para la línea pequeña de la pantalla).
func detail_text() -> String:
	if not is_configured():
		return "Cuando el servidor esté publicado, aquí podrás probar la conexión."
	if client.state == OnlineClient.State.ONLINE:
		var parts: Array[String] = []
		if client.resumed:
			parts.append("sesión recuperada")
		if client.ping_ms >= 0:
			parts.append("%d ms" % client.ping_ms)
		return " · ".join(parts)
	return ""


static func online_text(count: int) -> String:
	if count == 1:
		return "1 jugador en línea"
	return "%d jugadores en línea" % count


static func failure_text(code: String) -> String:
	match code:
		OnlineClient.FAIL_NO_SERVER:
			return "Servidor en línea sin configurar."
		OnlineClient.FAIL_BAD_VERSION:
			return "Tu versión del juego no coincide con la del servidor. Actualiza la app."
		OnlineClient.FAIL_REPLACED:
			return "Tu partida se abrió en otro dispositivo, así que se cerró esta conexión."
		OnlineClient.FAIL_UNREACHABLE:
			return "No se pudo conectar. Revisa tu conexión a Internet e inténtalo de nuevo."
		OnlineClient.FAIL_BAD_CLIENT:
			return "No se pudo crear la identidad de este dispositivo."
	return "No se pudo conectar."


# ---------------------------------------------------------------- Internos

func _configure() -> void:
	client.configure(server_url, client_id, _player_name(), _app_version())


func _player_name() -> String:
	var state: Node = get_node_or_null("/root/GameState")
	if state == null:
		return OnlineProtocol.DEFAULT_NAME
	var character: Dictionary = CharacterCatalog.find_character(str(state.get("selected_character_id")))
	return str(character.get("name", OnlineProtocol.DEFAULT_NAME))


func _app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


func _on_state_changed(_new_state: int) -> void:
	status_changed.emit()


func _on_stats(count: int) -> void:
	online_count_changed.emit(count)
	status_changed.emit()


func _on_welcomed(_info: Dictionary) -> void:
	online_count_changed.emit(client.online_count)
