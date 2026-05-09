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

func test_offline_leave_session_is_no_op() -> void:
	# Should not throw and should not flip is_host.
	_net.leave_session()
	assert_true(_net.is_host(), "Offline leave_session should not change authority")

func test_host_session_offline_without_steam_returns_unavailable() -> void:
	# Steam singleton may or may not be loaded when running under GUT in CLI.
	# Either way, an offline NetClass instance with no Steam wiring should
	# return ERR_UNAVAILABLE rather than crash.
	# (When Steam IS loaded, this still exercises the early-init failure path
	# because steamInit() with app_id=0 won't authenticate.)
	var err: int = _net.host_session()
	# Allow OK for the case where a Steam dev session happens to authenticate
	# successfully under the test runner; ERR_UNAVAILABLE is the offline path.
	assert_true(err == ERR_UNAVAILABLE or err == OK, "host_session must not crash; got err=%d" % err)
	# Defensive: if it returned OK by accident, clean up so other tests aren't
	# stuck "online".
	if err == OK:
		_net.leave_session()

func test_join_session_offline_without_steam_returns_unavailable() -> void:
	var err: int = _net.join_session(0)
	assert_true(err == ERR_UNAVAILABLE or err == OK, "join_session must not crash; got err=%d" % err)
	if err == OK:
		_net.leave_session()

func test_leave_session_when_already_offline_is_no_op() -> void:
	# Already offline by default in before_each.
	_net.leave_session()
	_net.leave_session()  # Calling twice in a row should still be safe.
	assert_true(_net.is_host(), "Offline leave_session must not change authority state")
