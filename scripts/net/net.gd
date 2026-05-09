extends Node
## Autoload. Owns the SteamMultiplayerPeer and session lifecycle, exposes
## signals for peer connect/disconnect/session-end, and provides authority
## helpers (`is_host`, `local_player_id`) that the rest of the multiplayer
## code uses instead of touching the multiplayer API directly.
##
## Phase 1 Tasks 5/6: host_session creates a friends-only Steam lobby and
## binds SteamMultiplayerPeer; join_session joins by lobby_id; leave_session
## tears everything down. Steam invite intake (lobby_invite, join_requested)
## surfaces friend-list interactions to the rest of the app.

signal peer_connected(peer_id: int, steam_id: String)
signal peer_disconnected(peer_id: int)
signal session_ended(reason: String)
signal invite_received(lobby_id: int)

const LOCAL_SENTINEL: String = "local"
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
const LOBBY_MAX_MEMBERS: int = 4

# peer_id (int) -> steam_id (String). Populated by Tasks 5/6.
var _peer_to_steam: Dictionary = {}
var _is_online: bool = false
var _peer: SteamMultiplayerPeer = null
var _lobby_id: int = 0
var _steam_initialized: bool = false

# --- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # tick callbacks even when paused
	# Wire Steam friends-list integration. invite_received fires when a friend
	# sends an in-game invite; join_requested fires when a friend right-clicks
	# "Join Game" in the Steam friends list.
	if Engine.has_singleton("Steam"):
		# GodotSteam API: verify signal names on first editor open
		if Steam.has_signal("lobby_invite"):
			Steam.lobby_invite.connect(_on_steam_lobby_invite)
		if Steam.has_signal("join_requested"):
			Steam.join_requested.connect(_on_steam_join_requested)
	set_process(true)

func _process(_delta: float) -> void:
	# embed_callbacks=false in project settings means we tick Steam manually.
	# Cheap when offline (just an early return inside Steam) — fine to call
	# every frame.
	if _steam_initialized and Engine.has_singleton("Steam"):
		# GodotSteam exposes this as snake_case (verified against the
		# x86_64 binary's symbol table — `run_callbacks` exists,
		# `runCallbacks` does not). Most Matchmaking methods are
		# camelCase (steamInit, joinLobby, setLobbyData) but the
		# callback ticker is the exception.
		Steam.run_callbacks()

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

# --- Session lifecycle (Tasks 5/6) -----------------------------------------

func host_session() -> Error:
	if _is_online:
		return ERR_ALREADY_IN_USE
	if not _ensure_steam_initialized():
		return ERR_UNAVAILABLE
	# GodotSteam API: SteamMultiplayerPeer might be `SteamMultiplayerPeer` or
	# need a different ctor. Verify on first editor open.
	_peer = SteamMultiplayerPeer.new()
	# GodotSteam API: create_lobby vs createLobby
	var err: int = _peer.create_lobby(LOBBY_TYPE_FRIENDS_ONLY, LOBBY_MAX_MEMBERS)
	if err != OK:
		push_error("Net.host_session: create_lobby failed (err=%d)" % err)
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	_is_online = true
	multiplayer.peer_connected.connect(_on_multiplayer_peer_connected)
	multiplayer.peer_disconnected.connect(_on_multiplayer_peer_disconnected)
	# Tag the lobby with a human-readable name on confirmation.
	# GodotSteam API: lobby_created signal name
	if Steam.has_signal("lobby_created"):
		Steam.lobby_created.connect(_on_steam_lobby_created, CONNECT_ONE_SHOT)
	return OK

func join_session(lobby_id: int) -> Error:
	if _is_online:
		return ERR_ALREADY_IN_USE
	if not _ensure_steam_initialized():
		return ERR_UNAVAILABLE
	# GodotSteam API: joinLobby vs join_lobby
	Steam.joinLobby(lobby_id)
	# Subscribe one-shot for the join response.
	if Steam.has_signal("lobby_joined"):
		Steam.lobby_joined.connect(_on_steam_lobby_joined.bind(lobby_id), CONNECT_ONE_SHOT)
	return OK

func leave_session() -> void:
	if not _is_online:
		return
	if _peer != null:
		# GodotSteam API: SteamMultiplayerPeer.close()
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	_peer_to_steam.clear()
	_is_online = false
	_lobby_id = 0
	if multiplayer.peer_connected.is_connected(_on_multiplayer_peer_connected):
		multiplayer.peer_connected.disconnect(_on_multiplayer_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_multiplayer_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_multiplayer_peer_disconnected)
	session_ended.emit("user_left")

# --- Internal helpers ------------------------------------------------------

func _online_local_player_id() -> String:
	# GodotSteam API: getSteamID returns the local user's Steam ID (uint64).
	if Engine.has_singleton("Steam"):
		return str(Steam.getSteamID())
	return LOCAL_SENTINEL

# --- Steam / multiplayer signal handlers -----------------------------------

func _on_multiplayer_peer_connected(peer_id: int) -> void:
	# Look up the steam id for this peer if the SteamMultiplayerPeer exposes it.
	# GodotSteam API: get_steam_id_from_peer_id may vary
	var steam_id: String = ""
	if _peer != null and _peer.has_method("get_steam_id_from_peer_id"):
		steam_id = str(_peer.get_steam_id_from_peer_id(peer_id))
	_peer_to_steam[peer_id] = steam_id
	peer_connected.emit(peer_id, steam_id)

func _on_multiplayer_peer_disconnected(peer_id: int) -> void:
	_peer_to_steam.erase(peer_id)
	peer_disconnected.emit(peer_id)

func _on_steam_lobby_created(connect_status: int, lobby_id: int) -> void:
	# connect_status == 1 typically means success in GodotSteam.
	if connect_status == 1:
		_lobby_id = lobby_id
		# GodotSteam API: setLobbyData
		if Steam.has_method("setLobbyData"):
			Steam.setLobbyData(lobby_id, "name", "Mine Co. session")
	else:
		push_error("Net._on_steam_lobby_created: connect_status=%d" % connect_status)
		session_ended.emit("lobby_create_failed")
		leave_session()

func _on_steam_lobby_joined(lobby_id_from_signal: int, _permissions: int, _locked: bool, response: int, lobby_id_bound: int) -> void:
	# Note: depending on GodotSteam signal signature, the bound arg ordering
	# may differ. We bind lobby_id at connect time as a safety net so we
	# always know which lobby was being targeted.
	if response != 1:
		push_error("Net.join_session: lobby_joined response=%d" % response)
		session_ended.emit("join_failed")
		return
	var lobby_id: int = lobby_id_from_signal if lobby_id_from_signal != 0 else lobby_id_bound
	_peer = SteamMultiplayerPeer.new()
	# GodotSteam API: connect_lobby vs connectLobby
	if not _peer.has_method("connect_lobby"):
		push_error("Net.join_session: SteamMultiplayerPeer missing connect_lobby method")
		_peer = null
		session_ended.emit("join_failed")
		return
	var err: int = _peer.connect_lobby(lobby_id)
	if err != OK:
		push_error("Net.join_session: connect_lobby failed (err=%d)" % err)
		_peer = null
		session_ended.emit("join_failed")
		return
	multiplayer.multiplayer_peer = _peer
	_is_online = true
	_lobby_id = lobby_id
	multiplayer.peer_connected.connect(_on_multiplayer_peer_connected)
	multiplayer.peer_disconnected.connect(_on_multiplayer_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_multiplayer_connected_to_server, CONNECT_ONE_SHOT)
	multiplayer.server_disconnected.connect(_on_multiplayer_server_disconnected, CONNECT_ONE_SHOT)

func _on_multiplayer_connected_to_server() -> void:
	# Snapshot apply lands in Task 13. Nothing to do here yet.
	pass

func _on_multiplayer_server_disconnected() -> void:
	leave_session()
	session_ended.emit("host_disconnected")

func _on_steam_lobby_invite(_inviter: int, lobby_id: int, _game_id: int) -> void:
	# Pure event — we emit our own signal and let the UI (Task 12) decide
	# whether to prompt or auto-join. Auto-joining without UI consent feels
	# hostile, so we never call join_session directly here.
	invite_received.emit(lobby_id)

func _on_steam_join_requested(lobby_id: int, _friend_id: int) -> void:
	# Triggered when a friend right-clicks "Join Game" in the Steam friends
	# list. This is an explicit user action, so we join immediately rather
	# than emitting invite_received and waiting for UI.
	join_session(lobby_id)

# --- Steam initialization helper -------------------------------------------

func _ensure_steam_initialized() -> bool:
	if _steam_initialized:
		return true
	if not Engine.has_singleton("Steam"):
		push_error("Net._ensure_steam_initialized: Steam singleton missing — is GodotSteam loaded?")
		return false
	# GodotSteam API: steamInit returns a Dictionary with status info, or an
	# int, depending on version. Treat anything truthy + non-error as success.
	var result: Variant = Steam.steamInit()
	var ok: bool = false
	if result is Dictionary:
		ok = int(result.get("status", 0)) == 1
	elif result is int:
		ok = result == 0 or result == 1
	else:
		ok = bool(result)
	if not ok:
		# Don't push_error here — callers already convert this to
		# ERR_UNAVAILABLE which they surface in the UI. push_error fires
		# on every offline test run / cold boot before host_session is
		# called, which pollutes logs. Steam-singleton-missing is still
		# logged above because that's a config error, not an expected
		# offline path.
		return false
	_steam_initialized = true
	return true
