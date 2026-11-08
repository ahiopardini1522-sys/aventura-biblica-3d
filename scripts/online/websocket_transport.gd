class_name WebSocketTransport
extends OnlineTransport
## Transporte real: un WebSocketPeer de Godot. Para direcciones wss:// usa los certificados que
## trae el motor (los mismos en Android y en el escritorio).

var _peer: WebSocketPeer
var _was_open: bool = false
var _finished: bool = false


func open(url: String) -> int:
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = 65536
	_peer.outbound_buffer_size = 65536
	_was_open = false
	_finished = false
	var err: int = _peer.connect_to_url(url)
	if err != OK:
		_peer = null
		_finished = true
	return err


func send_text(text: String) -> int:
	if _peer == null or _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	return _peer.send_text(text)


func close(code: int = 1000, reason: String = "") -> void:
	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.close(code, reason)


func is_open() -> bool:
	return _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func poll() -> Array:
	var events: Array = []
	if _peer == null or _finished:
		return events
	_peer.poll()
	var ready_state: int = _peer.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		events.append({"kind": EVENT_OPEN})
	# Los mensajes se leen antes de avisar del cierre: el servidor suele mandar un error y cerrar enseguida.
	while _peer.get_available_packet_count() > 0:
		var packet: PackedByteArray = _peer.get_packet()
		if _peer.was_string_packet():
			events.append({"kind": EVENT_MESSAGE, "text": packet.get_string_from_utf8()})
	if ready_state == WebSocketPeer.STATE_CLOSED:
		_finished = true
		events.append({
			"kind": EVENT_CLOSE,
			"code": _peer.get_close_code(),
			"reason": _peer.get_close_reason(),
		})
		_peer = null
	return events
