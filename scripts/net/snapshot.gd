class_name NetSnapshot
extends RefCounted
## Late-join state catch-up for Mine Co. multiplayer.
##
## When a peer joins a session that's already in progress, the host calls
## `build()` to collect a snapshot of replicable world state and pushes it
## to the joining peer, who calls `apply()` to bring their local world into
## sync.
##
## Phase 1 covers the three things that drift visibly during a session:
##   - Map exploration mask (so the team's shared minimap is correct on join)
##   - OreDeposit stage/hp (so partially-mined deposits show their current
##     mesh + scale)
##   - Voxel carves the host has made (so dug tunnels appear under the
##     joining peer; voxels are deterministic from the seed otherwise)
##
## Out of scope for Phase 1: vendor stock, contract assignments, claims,
## boats, factory placements, enemies — all of those are host-only-locked
## for guests until Phases 2 and 3 unlock them, so there's nothing the
## guest needs to render.

# --- Build (host) ----------------------------------------------------------

static func build() -> Dictionary:
	return {
		"map_explored_b64": _build_map_explored(),
		"map_explored_count": _build_map_explored_count(),
		"deposit_state": _build_deposit_state(),
		"voxel_carves": _build_voxel_carves(),
	}

static func _build_map_explored() -> String:
	if MapData == null:
		return ""
	# Read the private _explored array via get(); it's a PackedByteArray.
	var bytes: PackedByteArray = MapData.get("_explored")
	if bytes == null:
		return ""
	return Marshalls.raw_to_base64(bytes)

static func _build_map_explored_count() -> int:
	if MapData == null:
		return 0
	return int(MapData.get("_explored_cell_count"))

static func _build_deposit_state() -> Array:
	# Each entry: {id, stage, hp}. Skip deposits with empty ids (debug spawns).
	var out: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return out
	for n: Node in tree.get_nodes_in_group("ore_deposits"):
		if not (n is OreDeposit):
			continue
		var dep: OreDeposit = n
		if dep.deposit_id == "":
			continue
		out.append({
			"id": String(dep.deposit_id),
			"stage": int(dep._current_stage),
			"hp": int(dep._stage_hp_left),
		})
	return out

static func _build_voxel_carves() -> Array:
	# Pull from host's local Miner. Each entry is {pos: [x, y, z], radius}.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	var miner: Node = tree.get_first_node_in_group("player_miner")
	if miner == null:
		return []
	var carves: Variant = miner.get("_carves")
	if not (carves is Array):
		return []
	# Duplicate so we don't share the live array reference.
	return (carves as Array).duplicate(true)

# --- Apply (joining peer) --------------------------------------------------

static func apply(snap: Dictionary) -> void:
	_apply_map_explored(snap)
	_apply_deposit_state(snap)
	_apply_voxel_carves(snap)

static func _apply_map_explored(snap: Dictionary) -> void:
	if MapData == null:
		return
	var b64: String = String(snap.get("map_explored_b64", ""))
	if b64 == "":
		return
	var bytes: PackedByteArray = Marshalls.base64_to_raw(b64)
	# Compose a save_data-shaped dict and reuse MapData.apply_save_data — that
	# path already handles texture refresh + map_updated emission and is the
	# canonical "apply explored mask" entry point. We don't have the colored
	# image bytes from the host (they may be different on each peer), so we
	# leave that out; cells will color themselves locally next time the
	# player walks past or via _apply_remote_explored_diff_rpc.
	MapData.apply_save_data({
		"grid_size": MapData.GRID_SIZE,
		"explored_b64": b64,
		"explored_cell_count": int(snap.get("map_explored_count", 0)),
		# image_b64 omitted — apply_save_data tolerates absence and just
		# leaves the local image alone.
	})

static func _apply_deposit_state(snap: Dictionary) -> void:
	var entries: Variant = snap.get("deposit_state", [])
	if not (entries is Array):
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	# Build an id -> deposit lookup once; deposit_state usually has many
	# entries on a long-running host.
	var by_id: Dictionary = {}
	for n: Node in tree.get_nodes_in_group("ore_deposits"):
		if n is OreDeposit and (n as OreDeposit).deposit_id != "":
			by_id[(n as OreDeposit).deposit_id] = n
	for e in entries:
		if not (e is Dictionary):
			continue
		var id: String = String(e.get("id", ""))
		if id == "":
			continue
		var dep: OreDeposit = by_id.get(id) as OreDeposit
		if dep == null:
			continue
		dep.apply_save_data({"stage": int(e.get("stage", 0)), "hp": int(e.get("hp", 0))})

static func _apply_voxel_carves(snap: Dictionary) -> void:
	var carves: Variant = snap.get("voxel_carves", [])
	if not (carves is Array):
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var miner: Node = tree.get_first_node_in_group("player_miner")
	if miner == null or not miner.has_method("replay_carves"):
		return
	# Pre-stuff the carve log on the joining peer's miner. replay_carves
	# already iterates _carves and calls VoxelTool.do_sphere — this reuses
	# the SaveGame load path, which is the canonical "apply a carve list".
	# Note: this REPLACES the joining peer's local _carves — appropriate on
	# late-join because the joining peer hasn't carved anything yet.
	miner.set("_carves", (carves as Array).duplicate(true))
	miner.call("replay_carves")
