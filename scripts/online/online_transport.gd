class_name OnlineTransport
extends RefCounted
## Conexión de texto con el servidor. WebSocketTransport es la real; las pruebas usan un doble
## (tools/fake_online_transport.gd). No usa señales: poll() devuelve lo que pasó desde la última vez,
## así el orden de los hechos es siempre el mismo y no hay referencias circulares.
##
## Cada hecho es un diccionario:
##   {"kind": "open"}                                  la conexión quedó abierta
##   {"kind": "message", "text": "..."}                llegó un mensaje de texto
##   {"kind": "close", "code": 1006, "reason": "..."}  se cerró (code -1 si nunca llegó a abrirse)

const EVENT_OPEN := "open"
const EVENT_MESSAGE := "message"
const EVENT_CLOSE := "close"


## Empieza a conectar. Devuelve OK si la conexión está en marcha o un código de error si ni siquiera pudo empezar.
func open(_url: String) -> int:
	return ERR_UNAVAILABLE


## Envía un mensaje de texto. Devuelve OK o un código de error.
func send_text(_text: String) -> int:
	return ERR_UNAVAILABLE


## Pide cerrar la conexión (el cierre real se confirma con un hecho "close" en poll()).
func close(_code: int = 1000, _reason: String = "") -> void:
	pass


## Avanza la conexión y devuelve los hechos nuevos, en orden.
func poll() -> Array:
	return []


func is_open() -> bool:
	return false
