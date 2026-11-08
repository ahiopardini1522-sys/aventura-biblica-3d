class_name OnlineProtocol
extends RefCounted
## Protocolo de la conexión en línea (versión 1). Repite lo que define server/src/protocol.js:
## el juego y el servidor tienen que coincidir. Todo viaja como texto por WebSocket:
##   - el texto "ping": el servidor contesta "pong" (latido barato);
##   - objetos JSON con el campo "t" (tipo): hello, welcome, stats, error, bye...

const VERSION := 1
const PING := "ping"
const PONG := "pong"

## Códigos con los que el servidor cierra la conexión (4000 a 4999 son de la aplicación).
const CLOSE_NORMAL := 1000
const CLOSE_REPLACED := 4000          ## el mismo jugador se conectó desde otro lugar
const CLOSE_BAD_VERSION := 4001       ## el servidor y el juego usan versiones distintas del protocolo
const CLOSE_BAD_MESSAGE := 4002
const CLOSE_RATE_LIMITED := 4003
const CLOSE_TOO_MANY := 4004
const CLOSE_HANDSHAKE_TIMEOUT := 4005

const NAME_MAX_CHARS := 20
const MAX_MESSAGE_CHARS := 4096
const DEFAULT_NAME := "Jugador"


static func hello(client_id: String, player_name: String, app_version: String, resume: String = "") -> String:
	var message: Dictionary = {
		"t": "hello",
		"v": VERSION,
		"client": client_id,
		"name": clean_name(player_name),
		"app": app_version,
	}
	if is_valid_session(resume):
		message["resume"] = resume
	return JSON.stringify(message)


static func bye() -> String:
	return JSON.stringify({"t": "bye"})


static func stats_request() -> String:
	return JSON.stringify({"t": "stats"})


## Convierte un texto en mensaje. Devuelve {} si no es un objeto JSON con un tipo "t" de texto.
static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var message: Dictionary = data
	var kind: Variant = message.get("t", null)
	if typeof(kind) != TYPE_STRING:
		return {}
	var kind_text: String = kind
	if kind_text.is_empty() or kind_text.length() > 32:
		return {}
	return message


static func is_valid_client_id(value: String) -> bool:
	return _matches("^[A-Za-z0-9_-]{16,64}$", value)


static func is_valid_session(value: String) -> bool:
	return _matches("^[a-f0-9]{32}$", value)


## Identificador anónimo y permanente de este dispositivo (24 caracteres hexadecimales al azar).
static func make_client_id() -> String:
	return Crypto.new().generate_random_bytes(12).hex_encode()


## Quita caracteres de control, invisibles y espacios repetidos; recorta al largo máximo.
static func clean_name(raw: String) -> String:
	var kept := ""
	for i in raw.length():
		var code: int = raw.unicode_at(i)
		if code < 32 or (code >= 127 and code <= 159):
			continue
		if (code >= 0x200B and code <= 0x200F) or (code >= 0x2028 and code <= 0x202F):
			continue
		if (code >= 0x2060 and code <= 0x206F) or code == 0xFEFF:
			continue
		kept += raw.substr(i, 1)
	var words: PackedStringArray = kept.split(" ", false)
	var joined: String = " ".join(words)
	if joined.length() > NAME_MAX_CHARS:
		joined = joined.substr(0, NAME_MAX_CHARS).strip_edges()
	return joined


static func _matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return false
	return regex.search(value) != null
