extends Node
## Autoload. Owns the chat history buffer and RPC handlers. Send chat with
## Chat.send(text); subscribe to `new_message` to update UI.

const MAX_LINES: int = 6

signal new_message(line: Dictionary)

var _buffer: Array = []  # most recent at end

# --- Public API ------------------------------------------------------------

func get_recent_lines() -> Array:
	return _buffer.duplicate()

func send(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed == "":
		return
	if Net == null or not Net.is_online():
		# Offline: just append locally so single-player /commands or
		# debug echoes still produce a visible line.
		_append_local(Net.local_player_id() if Net != null else "you", trimmed, _now())
		return
	# Online: route through host so author/timestamp are authoritative.
	_request_chat_rpc.rpc_id(1, Net.local_player_id(), trimmed)

# --- RPC -------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _request_chat_rpc(author: String, text: String) -> void:
	# Host-only handler. Stamp the timestamp here so all peers agree on
	# when each line was said, then broadcast.
	if not multiplayer.is_server():
		return
	var ts: int = _now()
	_broadcast_chat_rpc.rpc(author, text, ts)
	# host_self call: the rpc above hits remotes; we still need to apply
	# locally because call_local on _request_chat_rpc only fires the
	# request handler, not the broadcast handler.
	_broadcast_chat_rpc(author, text, ts)

@rpc("authority", "call_remote", "reliable")
func _broadcast_chat_rpc(author: String, text: String, ts: int) -> void:
	_append_local(author, text, ts)

# --- Internals -------------------------------------------------------------

func _append_local(author: String, text: String, ts: int) -> void:
	var line: Dictionary = {"author": author, "text": text, "ts": ts}
	_buffer.append(line)
	while _buffer.size() > MAX_LINES:
		_buffer.pop_front()
	new_message.emit(line)

func _now() -> int:
	return int(Time.get_unix_time_from_system())
