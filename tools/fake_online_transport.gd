extends OnlineTransport
## Doble de prueba del transporte en línea: no abre ninguna conexión. La prueba hace de servidor
## con server_accepts(), server_sends(), server_closes()... y mira lo que el cliente envió en "sent".
## Se usa desde tools/smoke_test.gd (no viaja en el APK: tools/* está excluido de la exportación).

var url: String = ""
## Lo que devolverá open() (las pruebas ponen un error para simular que ni empieza a conectar).
var open_result: int = OK
## Textos que envió el cliente, en orden.
var sent: Array[String] = []
## Cierres pedidos por el cliente: {"code": int, "reason": String}.
var closed_by_client: Array = []

var _events: Array = []
var _open: bool = false


func open(p_url: String) -> int:
	url = p_url
	return open_result


func send_text(text: String) -> int:
	if not _open:
		return ERR_UNCONFIGURED
	sent.append(text)
	return OK


func close(code: int = 1000, reason: String = "") -> void:
	closed_by_client.append({"code": code, "reason": reason})
	if _open:
		_open = false
		_events.append({"kind": EVENT_CLOSE, "code": code, "reason": reason})


func poll() -> Array:
	var out: Array = _events
	_events = []
	return out


func is_open() -> bool:
	return _open


# ---------------------------------------------------------------- Lo que hace "el servidor"

func server_accepts() -> void:
	_open = true
	_events.append({"kind": EVENT_OPEN})


func server_sends(text: String) -> void:
	_events.append({"kind": EVENT_MESSAGE, "text": text})


func server_sends_json(message: Dictionary) -> void:
	server_sends(JSON.stringify(message))


func server_closes(code: int, reason: String = "") -> void:
	_open = false
	_events.append({"kind": EVENT_CLOSE, "code": code, "reason": reason})


## La conexión no llegó a abrirse (sin Internet, servidor caído...).
func connection_fails() -> void:
	server_closes(-1, "")


# ---------------------------------------------------------------- Lo que envió el cliente

## Mensajes JSON enviados por el cliente (sin contar los "ping" de texto).
func sent_json() -> Array:
	var out: Array = []
	for text in sent:
		var json := JSON.new()
		if json.parse(text) == OK and typeof(json.data) == TYPE_DICTIONARY:
			out.append(json.data)
	return out


func sent_ping_count() -> int:
	return sent.count(OnlineProtocol.PING)
