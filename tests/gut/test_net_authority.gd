extends GutTest

const NetClass = preload("res://scripts/net/net.gd")

var _net: Node

func before_each() -> void:
	_net = NetClass.new()
	add_child_autofree(_net)

func test_offline_is_host_returns_true() -> void:
	# When no peer is set, the local instance is treated as the authority.
	assert_true(_net.is_host(), "Offline session should report local as host")

func test_offline_local_player_id_is_local_sentinel() -> void:
	assert_eq(_net.local_player_id(), "local")

func test_offline_steam_id_for_unknown_peer_is_empty() -> void:
	assert_eq(_net.steam_id_for_peer(99), "")

func test_signal_peer_connected_exists() -> void:
	assert_true(_net.has_signal("peer_connected"))

func test_signal_peer_disconnected_exists() -> void:
	assert_true(_net.has_signal("peer_disconnected"))

func test_signal_session_ended_exists() -> void:
	assert_true(_net.has_signal("session_ended"))

func test_signal_invite_received_exists() -> void:
	# Set up by Task 6 wiring; the signal must be defined now so any subsystem
	# can connect to Net.invite_received without depending on Task 6 ordering.
	assert_true(_net.has_signal("invite_received"))

func test_offline_host_session_returns_unavailable() -> void:
	# Stub until Task 5 implements lobby creation.
	assert_eq(_net.host_session(), ERR_UNAVAILABLE)

func test_offline_join_session_returns_unavailable() -> void:
	# Stub until Task 6 implements lobby join.
	assert_eq(_net.join_session(0), ERR_UNAVAILABLE)

func test_offline_leave_session_is_no_op() -> void:
	# Should not throw and should not flip is_host.
	_net.leave_session()
	assert_true(_net.is_host(), "Offline leave_session should not change authority")
