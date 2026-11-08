class_name OnlineConfig
extends RefCounted
## Dónde está el servidor en línea y quién es este dispositivo.
##
## La dirección sale de data/online.json (campo "server_url"). La completa solo el flujo de
## despliegue del servidor (.github/workflows/servidor-desplegar.yml) cuando se publica el servidor
## en Cloudflare; mientras esté vacía, el juego muestra "servidor sin configurar".
## Solo se admiten direcciones seguras (https/wss). Se permite http/ws únicamente hacia este mismo
## dispositivo (localhost / 127.0.0.1), para las pruebas automáticas.

const CONFIG_PATH := "res://data/online.json"
const IDENTITY_PATH := "user://online.cfg"


## Lee la dirección del servidor del archivo de configuración. "" si falta, está vacía o no es válida.
static func load_server_url(path: String = CONFIG_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return ""
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	var config: Dictionary = data
	return normalize_base_url(str(config.get("server_url", "")))


## Deja la dirección en su forma canónica (https://servidor o http://127.0.0.1:puerto, sin barra final
## ni "/ws"). Devuelve "" si no es una dirección permitida.
static func normalize_base_url(raw: String) -> String:
	var url: String = raw.strip_edges()
	if url.is_empty():
		return ""
	var lower: String = url.to_lower()
	var secure := true
	if lower.begins_with("https://"):
		url = url.substr(8)
	elif lower.begins_with("wss://"):
		url = url.substr(6)
	elif lower.begins_with("http://"):
		url = url.substr(7)
		secure = false
	elif lower.begins_with("ws://"):
		url = url.substr(5)
		secure = false
	else:
		return ""
	while url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	if url.to_lower().ends_with("/ws"):
		url = url.substr(0, url.length() - 3)
	if url.is_empty() or url.contains("/") or url.contains(" ") or url.contains("?") or url.contains("#") or url.contains("@"):
		return ""
	if not secure and not _is_loopback(url):
		return ""
	return ("https://" if secure else "http://") + url


## Dirección del WebSocket (wss://servidor/ws). "" si la dirección base no es válida.
static func to_ws_url(base_url: String) -> String:
	var base: String = normalize_base_url(base_url)
	if base.is_empty():
		return ""
	if base.begins_with("https://"):
		return "wss://" + base.substr(8) + "/ws"
	return "ws://" + base.substr(7) + "/ws"


## Dirección HTTP de una ruta del servidor (por ejemplo "/health"). "" si la dirección base no es válida.
static func to_http_url(base_url: String, path: String = "/health") -> String:
	var base: String = normalize_base_url(base_url)
	if base.is_empty():
		return ""
	return base + path


## Identificador anónimo de este dispositivo. Se crea la primera vez y se conserva en el teléfono.
static func load_client_id(path: String = IDENTITY_PATH) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		var saved: String = str(cfg.get_value("identity", "client_id", ""))
		if OnlineProtocol.is_valid_client_id(saved):
			return saved
	var created: String = OnlineProtocol.make_client_id()
	cfg.set_value("identity", "client_id", created)
	var err: int = cfg.save(path)
	if err != OK:
		push_warning("OnlineConfig: no se pudo guardar el identificador (error %d)" % err)
	return created


static func _is_loopback(host_and_port: String) -> bool:
	var host: String = host_and_port
	var colon: int = host.rfind(":")
	if colon >= 0 and not host.begins_with("["):
		host = host.substr(0, colon)
	return host == "127.0.0.1" or host == "localhost" or host == "[::1]"
