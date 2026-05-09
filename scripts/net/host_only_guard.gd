class_name HostOnlyGuard
extends RefCounted
## Phase 1 helper: block non-host peers from opening systems whose state
## isn't replicated yet (vendors, contract/claim boards, build mode, etc.).
## Phases 2-3 will remove these guards as those systems gain MP support.

## Returns true if the local peer is a guest. When true, surfaces a small
## toast via the pickup feed so the player knows why the UI didn't open.
##
## Usage:
##     func open() -> void:
##         if HostOnlyGuard.block_if_guest("Vendor"):
##             return
##         # ... existing open logic ...
static func block_if_guest(feature_name: String) -> bool:
	if Net == null:
		return false
	if Net.is_host():
		return false
	_show_toast("%s is host-only in Phase 1" % feature_name)
	return true

static func _show_toast(message: String) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var feed: Node = tree.get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_text_message"):
		feed.call("add_text_message", message)
	else:
		# Fallback: at least log so the player gets a visible engine output.
		push_warning("HostOnlyGuard: " + message)
