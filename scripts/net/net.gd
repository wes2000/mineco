extends Node

# Preload the snapshot module — class_name globals don't always refresh
# on first save in Godot 4.6, and net.gd is an autoload that loads early.
const _NetSnapshot: GDScript = preload("res://scripts/net/snapshot.gd")

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
# Emitted when _is_online flips from false to true (host's lobby_created
# callback or guest's connected_to_server). The pause menu listens so the
# Multiplayer section refreshes the moment we actually go online — without
# this, host_session() returns OK synchronously but the UI stays "offline"
# until lobby_created fires asynchronously, which fools the user into
# clicking Host a second time.
signal session_started()

const LOCAL_SENTINEL: String = "local"
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
const LOBBY_MAX_MEMBERS: int = 4

# peer_id (int) -> steam_id (String). Populated by Tasks 5/6.
var _peer_to_steam: Dictionary = {}
var _is_online: bool = false
var _peer: SteamMultiplayerPeer = null
var _lobby_id: int = 0
var _steam_initialized: bool = false

# peer_id (int) -> RemotePlayer node, the visual stand-in for that peer.
# Owned only on peers that have already received the spawn RPC for this peer.
var _remote_players: Dictionary = {}

# Cached lookup for the spawner. Resolved on first spawn/despawn call.
var _remote_player_spawner: MultiplayerSpawner = null

# Throttle for our local Player's transform broadcast (~20 Hz).
const _TRANSFORM_BROADCAST_HZ: float = 20.0
const _TRANSFORM_BROADCAST_INTERVAL: float = 1.0 / _TRANSFORM_BROADCAST_HZ

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
	# Two-step host setup (verified against GodotSteam binary symbols):
	#   1. Steam.createLobby() asks Steamworks to allocate a lobby.
	#   2. On the lobby_created signal, bind a SteamMultiplayerPeer to the
	#      lobby via peer.host_with_lobby(lobby_id) and register it as the
	#      multiplayer_peer.
	# This is unlike the create_lobby-on-peer pattern in older GodotSteam
	# multiplayer-peer forks; the v4.18+ API splits Steam-side lobby
	# creation from peer binding.
	if not Steam.has_signal("lobby_created"):
		push_error("Net.host_session: Steam.lobby_created signal missing — incompatible GodotSteam version")
		return ERR_UNAVAILABLE
	Steam.lobby_created.connect(_on_steam_lobby_created, CONNECT_ONE_SHOT)
	Steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, LOBBY_MAX_MEMBERS)
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
	# Despawn all RemotePlayer instances locally — peer disconnect signals
	# may not fire for everyone in time.
	for peer_id in _remote_players.keys():
		_local_despawn_remote(peer_id)
	_remote_players.clear()
	_is_online = false
	_lobby_id = 0
	if multiplayer.peer_connected.is_connected(_on_multiplayer_peer_connected):
		multiplayer.peer_connected.disconnect(_on_multiplayer_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_multiplayer_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_multiplayer_peer_disconnected)
	# CONNECT_ONE_SHOT handlers normally clean themselves up after firing,
	# but if leave_session is called before the lobby fully establishes
	# (e.g. user clicks Leave during join handshake), they're still wired.
	# Belt-and-suspenders cleanup so a subsequent join_session doesn't
	# stack duplicate callbacks.
	if multiplayer.connected_to_server.is_connected(_on_multiplayer_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_multiplayer_connected_to_server)
	if multiplayer.server_disconnected.is_connected(_on_multiplayer_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_multiplayer_server_disconnected)
	session_ended.emit("user_left")

# --- Internal helpers ------------------------------------------------------

func _online_local_player_id() -> String:
	# GodotSteam API: getSteamID returns the local user's Steam ID (uint64).
	if Engine.has_singleton("Steam"):
		return str(Steam.getSteamID())
	return LOCAL_SENTINEL

# --- Steam / multiplayer signal handlers -----------------------------------

func _on_multiplayer_peer_connected(peer_id: int) -> void:
	# get_steam_id_for_peer_id is the actual method (NOT _from_) — verified
	# against SteamMultiplayerPeer's exposed method list.
	var steam_id: String = ""
	if _peer != null and _peer.has_method("get_steam_id_for_peer_id"):
		steam_id = str(_peer.get_steam_id_for_peer_id(peer_id))
	_peer_to_steam[peer_id] = steam_id
	peer_connected.emit(peer_id, steam_id)
	if multiplayer.is_server():
		_host_spawn_remote_for(peer_id)
		# Tell the new peer about everyone who was already here so they can
		# render us all.
		for existing_peer_id in _peer_to_steam.keys():
			if existing_peer_id == peer_id:
				continue
			var existing_steam: String = _peer_to_steam[existing_peer_id]
			tell_peer_id_to_spawn.rpc_id(peer_id, existing_peer_id, existing_steam)
		# Late-join: catch the new peer up on the world state we've built up
		# (map fog, ore deposit damage, voxel carves). Phase 1 covers the
		# things that drift visibly during a session.
		_send_world_snapshot(peer_id)

func _on_multiplayer_peer_disconnected(peer_id: int) -> void:
	_peer_to_steam.erase(peer_id)
	peer_disconnected.emit(peer_id)
	if multiplayer.is_server():
		# Tell everyone (including host) to despawn this peer's visual.
		for other_peer in multiplayer.get_peers():
			tell_peer_id_to_despawn.rpc_id(other_peer, peer_id)
		_local_despawn_remote(peer_id)

func _host_spawn_remote_for(peer_id: int) -> void:
	# Host spawns a RemotePlayer-for-peer-N on every peer's tree (other than
	# peer N itself, which has its static Player at /root/Main/Player).
	var spawner: MultiplayerSpawner = _ensure_spawner()
	if spawner == null:
		push_warning("Net._host_spawn_remote_for: no spawner found; skipping")
		return
	var steam_id: String = _peer_to_steam.get(peer_id, "")
	# Tell ALL peers (including host) to spawn this peer's visual, except
	# the peer itself (they have a local Player).
	for other_peer in multiplayer.get_peers():
		if other_peer == peer_id:
			continue
		tell_peer_id_to_spawn.rpc_id(other_peer, peer_id, steam_id)
	# Host always sees every other peer.
	if peer_id != 1:
		_local_spawn_remote(peer_id, steam_id)

@rpc("authority", "call_local", "reliable")
func tell_peer_id_to_spawn(target_peer_id: int, target_steam_id: String) -> void:
	# Receiving peer creates a local RemotePlayer for target_peer_id, unless
	# we ARE target_peer_id (we have our own static Player).
	if target_peer_id == multiplayer.get_unique_id():
		return
	_local_spawn_remote(target_peer_id, target_steam_id)

@rpc("authority", "call_local", "reliable")
func tell_peer_id_to_despawn(target_peer_id: int) -> void:
	_local_despawn_remote(target_peer_id)

func _ensure_spawner() -> MultiplayerSpawner:
	if _remote_player_spawner != null and is_instance_valid(_remote_player_spawner):
		return _remote_player_spawner
	var main: Node = get_tree().current_scene
	if main == null:
		return null
	var s: Node = main.get_node_or_null("RemotePlayerSpawner")
	if s is MultiplayerSpawner:
		_remote_player_spawner = s
	return _remote_player_spawner

func _local_spawn_remote(peer_id: int, steam_id: String) -> void:
	if _remote_players.has(peer_id):
		return  # already spawned (e.g. via spawn-then-late-join)
	var packed: PackedScene = load("res://scenes/remote_player.tscn") as PackedScene
	if packed == null:
		push_error("Net._local_spawn_remote: failed to load remote_player.tscn")
		return
	var inst: Node = packed.instantiate()
	inst.name = "RemotePlayer_%d" % peer_id
	if "steam_id" in inst:
		inst.steam_id = steam_id
	if inst.has_method("set_display_name"):
		inst.set_display_name(_display_name_for(steam_id))
	# Spawn at world origin; first transform RPC will reposition.
	var main: Node = get_tree().current_scene
	if main == null:
		push_error("Net._local_spawn_remote: current_scene is null")
		return
	main.add_child(inst)
	_remote_players[peer_id] = inst

func _local_despawn_remote(peer_id: int) -> void:
	var node: Node = _remote_players.get(peer_id, null)
	if node != null and is_instance_valid(node):
		node.queue_free()
	_remote_players.erase(peer_id)

func _display_name_for(steam_id: String) -> String:
	if Engine.has_singleton("Steam") and steam_id.is_valid_int():
		# GodotSteam API: getFriendPersonaName takes a Steam ID
		return Steam.getFriendPersonaName(int(steam_id))
	return "Player"

func _on_steam_lobby_created(connect_status: int, lobby_id: int) -> void:
	# connect_status == 1 means success in GodotSteam (k_EResultOK).
	if connect_status != 1:
		push_error("Net._on_steam_lobby_created: connect_status=%d" % connect_status)
		session_ended.emit("lobby_create_failed")
		return
	_lobby_id = lobby_id
	if Steam.has_method("setLobbyData"):
		Steam.setLobbyData(lobby_id, "name", "Mine Co. session")
	# Now bind the SteamMultiplayerPeer to the lobby. host_with_lobby is the
	# server-side counterpart of connect_to_lobby — verified against
	# SteamMultiplayerPeer's exposed method list.
	_peer = SteamMultiplayerPeer.new()
	var err: int = _peer.host_with_lobby(lobby_id)
	if err != OK:
		push_error("Net._on_steam_lobby_created: host_with_lobby failed (err=%d)" % err)
		_peer = null
		session_ended.emit("lobby_create_failed")
		return
	multiplayer.multiplayer_peer = _peer
	_is_online = true
	multiplayer.peer_connected.connect(_on_multiplayer_peer_connected)
	multiplayer.peer_disconnected.connect(_on_multiplayer_peer_disconnected)
	# Tell the rest of the app we're online now — the pause menu's
	# Multiplayer section listens and refreshes its status / Host / Leave
	# buttons. Without this, host_session() returns OK synchronously but
	# the UI stays "Single-player" until this callback fires async, which
	# fools users into clicking Host a second time.
	session_started.emit()

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
	# connect_to_lobby is the actual SteamMultiplayerPeer method (verified
	# against the binary's exposed method list — older docs/forks use
	# `connect_lobby`, that name does not exist in v4.18+).
	var err: int = _peer.connect_to_lobby(lobby_id)
	if err != OK:
		push_error("Net.join_session: connect_to_lobby failed (err=%d)" % err)
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
	session_started.emit()

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

# --- Transform broadcast / receive (called from player.gd) -----------------

@rpc("any_peer", "call_remote", "unreliable")
func recv_remote_transform(pos: Vector3, rot_y: float, current_tool: int, animation_state: String) -> void:
	# Sender is the authority for their own transform. Find their visual on
	# our tree and apply.
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	var node: Node = _remote_players.get(sender_peer_id, null)
	if node == null or not is_instance_valid(node):
		return
	# Only assign if these properties exist on the spawned scene.
	if "position" in node:
		node.position = pos
	if "rotation" in node:
		var r: Vector3 = node.rotation
		r.y = rot_y
		node.rotation = r
	if "current_tool" in node:
		node.current_tool = current_tool
	if "animation_state" in node:
		node.animation_state = animation_state

# --- Late-join snapshot (Phase 1 Task 13) ----------------------------------

func _send_world_snapshot(target_peer_id: int) -> void:
	# Host-only path. _NetSnapshot.build reads from MapData / OreDeposits /
	# host miner. The resulting Dictionary is small enough (a few hundred
	# kB worst case for a fully-explored map + many deposits) to send in
	# one reliable RPC.
	var snap: Dictionary = _NetSnapshot.build()
	_recv_world_snapshot.rpc_id(target_peer_id, snap)

@rpc("authority", "call_remote", "reliable")
func _recv_world_snapshot(snap: Dictionary) -> void:
	# Joining peer applies the snapshot to its local world. apply() routes
	# each section to the right subsystem (MapData.apply_save_data,
	# OreDeposit.apply_save_data, Miner.replay_carves).
	_NetSnapshot.apply(snap)
