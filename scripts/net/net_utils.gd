class_name NetUtils
extends RefCounted
## Stateless helpers wrapping the canonical request → host RPC pattern.
## Gameplay code calls these instead of touching `multiplayer.*` directly,
## which keeps the network layer swappable later if we ever leave Steam.
##
## === RPC argument convention ===
## All RPC methods in Mine Co. multiplayer take a single `args: Array`
## parameter and unpack inside. This keeps the helper API uniform — every
## call site looks like `NetUtils.request_to_host(self, "_my_rpc", [arg1, arg2, arg3])`.
## Trade-off: less type-checking at call sites; gain: one helper signature
## covers every game-state RPC without per-method overloads or metaprogramming.
## The receiver always declares the RPC method as:
##     @rpc("any_peer", "call_local", "reliable")
##     func _my_rpc(args: Array) -> void:
##         var x = args[0]; var y = args[1]
##         ...
## When we call the local-host branch we use `target.callv(method_name, [args])`
## — note the wrapping array: `callv` expects an Array of positional arguments,
## and our single positional argument *is itself an Array*.

## Routes a request from any peer to the host. If the local peer IS the host,
## calls the method synchronously. Otherwise, RPCs to peer 1 (the host).
##
## The receiver script must own `method_name` and have annotated it
## @rpc("any_peer", "call_local"[, "reliable"]).
static func request_to_host(target: Node, method_name: String, args: Array) -> void:
	if Net.is_host():
		target.callv(method_name, [args])
	else:
		target.rpc_id(1, method_name, args)

## Host broadcasts state to all peers (host included via local call).
## Errors out if called from a non-host.
static func broadcast(target: Node, method_name: String, args: Array) -> void:
	if not Net.is_host():
		push_error("NetUtils.broadcast called from non-host")
		return
	target.rpc(method_name, args)
	target.callv(method_name, [args])

## Host sends to one specific peer. Errors out if called from non-host.
## If `peer_id` is the host's own id (1), this falls through to a local call.
static func tell_peer(target: Node, peer_id: int, method_name: String, args: Array) -> void:
	if not Net.is_host():
		push_error("NetUtils.tell_peer called from non-host")
		return
	if peer_id == 1:
		target.callv(method_name, [args])
	else:
		target.rpc_id(peer_id, method_name, args)
