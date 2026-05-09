extends Node
## Autoload. Owns the SteamMultiplayerPeer and session lifecycle, exposes
## signals for peer connect/disconnect/session-end, and provides authority
## helpers (`is_host`, `local_player_id`) that the rest of the multiplayer
## code uses instead of touching the multiplayer API directly.
##
## Phase 1 Task 4 is the skeleton — `host_session`, `join_session`, and
## `leave_session` are stubs. Real Steam wiring lands in Tasks 5 and 6.

signal peer_connected(peer_id: int, steam_id: String)
signal peer_disconnected(peer_id: int)
signal session_ended(reason: String)
signal invite_received(lobby_id: int)

const LOCAL_SENTINEL: String = "local"

# peer_id (int) -> steam_id (String). Populated by Tasks 5/6.
var _peer_to_steam: Dictionary = {}
var _is_online: bool = false

# --- Public API -------------------------------------------------------------

func is_host() -> bool:
	# Offline = there is no remote authority, so the local instance is the
	# authority. Once a peer is set up by Task 5, defer to multiplayer.
	if not _is_online:
		return true
	return multiplayer.is_server()

func is_online() -> bool:
	return _is_online

func local_player_id() -> String:
	# Phase 1 returns "local" offline. Online lookup is filled in by Task 5
	# when Steam.getSteamID() becomes meaningful.
	if not _is_online:
		return LOCAL_SENTINEL
	return _online_local_player_id()

func steam_id_for_peer(peer_id: int) -> String:
	return _peer_to_steam.get(peer_id, "")

# --- Stubs filled in by Tasks 5 and 6 --------------------------------------

func host_session() -> Error:
	# Implemented in Task 5.
	return ERR_UNAVAILABLE

func join_session(_lobby_id: int) -> Error:
	# Implemented in Task 6.
	return ERR_UNAVAILABLE

func leave_session() -> void:
	# Implemented in Task 5. Offline no-op.
	pass

# --- Internal helpers (private, expanded in Tasks 5/6) ---------------------

func _online_local_player_id() -> String:
	# Replaced in Task 5 with `str(Steam.getSteamID())`. Fall through to
	# the offline sentinel until then.
	return LOCAL_SENTINEL
