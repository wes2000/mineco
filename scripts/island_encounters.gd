extends Node
## Owns per-island enemy spawning + clear-state tracking. Listens to
## SpawnGate.world_ready, then spawns the enemy budget for each claim
## island at deterministic positions (RNG seeded from the island id).
## When all enemies on an island are defeated, the player gets a one-time
## gold bounty + pickup-feed toast. Per-island state round-trips through
## SaveGame.
##
## Note: this is a plain Node added to main.tscn (not an autoload). It
## reaches state via groups + the player_miner / pickup_feed lookups, and
## SaveGame already handles the "find via group / has_method" pattern for
## non-autoload owners — see _save_owner / _save_owner_apply below.

const _IslandGen: GDScript = preload("res://scripts/island_voxel_generator.gd")
const _EncDefs: GDScript = preload("res://scripts/island_encounter_defs.gd")
const ENEMY_SCN: PackedScene = preload("res://scenes/enemy.tscn")

# Mixed into the per-island RNG seed so changing this constant lets us
# reroll all encounter layouts without touching island ids.
const SEED_SALT: int = 0x51A1D5
# Surface height in the deterministic island generator below which we don't
# spawn (i.e. underwater or sub-1m beach — would clip into the water plane).
const MIN_SPAWN_SURFACE_Y: float = 1.0
# Y nudge above the sampled surface so enemies don't start half-buried while
# the chunk under them finishes meshing.
const SPAWN_Y_BUMP: float = 1.2

@export var spawn_gate_path: NodePath
@export var voxel_terrain_path: NodePath
@export var spawn_delay_after_world_ready: float = 0.5

var _island_generator: IslandVoxelGenerator = null
# Per-island state. Keyed by island id → {enemies_spawned, enemies_killed,
# cleared, reward_claimed}. `cleared` true means we already granted the
# bounty and won't re-spawn on load.
var _state: Dictionary = {}
# Map of live enemy → island id, so we can decrement counts on `tree_exited`
# in case an enemy is freed without the standard `enemy_killed` signal.
var _live_enemies: Dictionary = {}
# Pending state from SaveGame.apply_state — applied once the spawn happens
# (so we can skip already-cleared islands).
var _pending_save: Dictionary = {}
var _has_spawned: bool = false

func _ready() -> void:
	add_to_group("island_encounters")
	if voxel_terrain_path != NodePath(""):
		var t: VoxelTerrain = get_node_or_null(voxel_terrain_path) as VoxelTerrain
		if t != null:
			_island_generator = t.generator as IslandVoxelGenerator
	# Hook spawn gate. If the gate is missing (test scene, etc.) we fall back
	# to a small timer so the system still self-bootstraps.
	var gate: Node = get_node_or_null(spawn_gate_path) if spawn_gate_path != NodePath("") else null
	if gate != null and gate.has_signal("world_ready"):
		gate.world_ready.connect(_on_world_ready)
	else:
		get_tree().create_timer(2.0).timeout.connect(_on_world_ready)

func _on_world_ready() -> void:
	if _has_spawned:
		return
	# Defer slightly so the OreGenerator's per-island scatter (also hooked
	# to world_ready) finishes printing first — keeps the log readable.
	get_tree().create_timer(spawn_delay_after_world_ready).timeout.connect(_spawn_all)

func _spawn_all() -> void:
	if _has_spawned:
		return
	_has_spawned = true
	if _island_generator == null:
		push_warning("IslandEncounters: no IslandVoxelGenerator — skipping spawn")
		return
	var total: int = 0
	for isle: Dictionary in IslandVoxelGenerator.CLAIM_ISLANDS:
		var id: String = String(isle.id)
		# Initialize state from save (if present) or clean defaults.
		var s: Dictionary = _initial_state_for(id)
		_state[id] = s
		# If the save says we already cleared this island, don't respawn.
		if bool(s.cleared):
			continue
		var enc: Dictionary = _EncDefs.for_island(id)
		var budget: int = int(enc.enemy_budget)
		var stats: Dictionary = enc.enemy_stats
		var placed: int = _spawn_for_island(isle, budget, stats)
		s["enemies_spawned"] = placed
		# An island with budget > 0 but zero placeable surface (very unlikely
		# given the size of the islands) is treated as already-cleared so the
		# player doesn't get stuck waiting for a phantom kill.
		if placed == 0 and budget > 0:
			s["cleared"] = true
		total += placed
		print("IslandEncounters: %s (T%d) — spawned %d enemies (budget %d)" % [
			isle.name, isle.tier, placed, budget
		])
	print("IslandEncounters: total %d enemies spawned across %d islands" % [
		total, IslandVoxelGenerator.CLAIM_ISLANDS.size()
	])

func _spawn_for_island(isle: Dictionary, budget: int, stats: Dictionary) -> int:
	if budget <= 0:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = (String(isle.id).hash()) ^ SEED_SALT
	var max_r: float = IslandVoxelGenerator.island_max_radius(isle) * 0.85
	var placed: int = 0
	var attempts: int = 0
	var cap: int = budget * 24   # generous — most points succeed
	var island_id: String = String(isle.id)
	while placed < budget and attempts < cap:
		attempts += 1
		var theta: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * max_r
		var x: float = float(isle.center.x) + cos(theta) * r
		var z: float = float(isle.center.y) + sin(theta) * r
		if not IslandVoxelGenerator.point_inside_island(isle, x, z):
			continue
		var sy: float = _island_generator._height(x, z)
		if sy < MIN_SPAWN_SURFACE_Y:
			continue
		_spawn_one(island_id, Vector3(x, sy + SPAWN_Y_BUMP, z), stats)
		placed += 1
	return placed

func _spawn_one(island_id: String, pos: Vector3, stats: Dictionary) -> void:
	var enemy: Node3D = ENEMY_SCN.instantiate() as Node3D
	enemy.position = pos
	# Configure via method so the enemy applies the stats before _ready runs
	# its Health initialization.
	if enemy.has_method("configure"):
		enemy.call("configure", {
			"hp": int(stats.get("hp", 30)),
			"damage": int(stats.get("damage", 6)),
			"speed": float(stats.get("speed", 1.8)),
			"island_id": island_id,
		})
	add_child(enemy)
	# Connect signals after add_child so the enemy is in the scene tree.
	if enemy.has_signal("enemy_killed"):
		enemy.connect("enemy_killed", Callable(self, "_on_enemy_killed"))
	enemy.tree_exited.connect(Callable(self, "_on_enemy_freed").bind(enemy))
	_live_enemies[enemy] = island_id

func _on_enemy_killed(island_id: String) -> void:
	if not _state.has(island_id):
		return
	var s: Dictionary = _state[island_id]
	s["enemies_killed"] = int(s.get("enemies_killed", 0)) + 1
	if int(s.enemies_killed) >= int(s.get("enemies_spawned", 0)) and not bool(s.get("cleared", false)):
		_mark_cleared(island_id, s)
	_state[island_id] = s

func _on_enemy_freed(enemy: Node) -> void:
	# Safety net: if an enemy is freed without firing enemy_killed (e.g. scene
	# reload / queue_free during shutdown), drop our reference. We don't count
	# this as a kill — only the explicit signal does.
	if _live_enemies.has(enemy):
		_live_enemies.erase(enemy)

func _mark_cleared(island_id: String, s: Dictionary) -> void:
	s["cleared"] = true
	if bool(s.get("reward_claimed", false)):
		return
	var enc: Dictionary = _EncDefs.for_island(island_id)
	var gold: int = int(enc.reward_gold)
	# Find the island display name for the toast.
	var name: String = island_id
	for isle: Dictionary in IslandVoxelGenerator.CLAIM_ISLANDS:
		if String(isle.id) == island_id:
			name = String(isle.name)
			break
	# Grant the bounty to the miner.
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner != null and miner.has_method("add_gold_currency"):
		miner.call("add_gold_currency", gold)
	# Pickup-feed toast.
	var feed: Node = get_tree().get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_text_message"):
		feed.call("add_text_message", "%s cleared — +%d g" % [name, gold])
	s["reward_claimed"] = true
	print("IslandEncounters: %s cleared, +%d gold" % [name, gold])

# --- Save / load ------------------------------------------------------------

func get_save_data() -> Dictionary:
	# Round-trip the per-island state. Leaving out ints/bools that match the
	# default would shrink the save but obscures intent — full state is fine.
	var out: Dictionary = {}
	for id in _state.keys():
		var s: Dictionary = _state[id]
		out[id] = {
			"enemies_spawned": int(s.get("enemies_spawned", 0)),
			"enemies_killed": int(s.get("enemies_killed", 0)),
			"cleared": bool(s.get("cleared", false)),
			"reward_claimed": bool(s.get("reward_claimed", false)),
		}
	return out

func apply_save_data(data: Dictionary) -> void:
	# If we haven't spawned yet, stash the data — _spawn_all reads it via
	# _initial_state_for(). If we have spawned, we still want the cleared
	# flag to take effect (free any live enemies on cleared islands so the
	# player doesn't fight spawn-on-load re-rolls of an already-cleared isle).
	_pending_save = data.duplicate(true)
	if _has_spawned:
		_apply_save_post_spawn(data)

func _initial_state_for(id: String) -> Dictionary:
	if _pending_save.has(id):
		var saved: Dictionary = _pending_save[id]
		return {
			"enemies_spawned": int(saved.get("enemies_spawned", 0)),
			"enemies_killed": int(saved.get("enemies_killed", 0)),
			"cleared": bool(saved.get("cleared", false)),
			"reward_claimed": bool(saved.get("reward_claimed", false)),
		}
	return {
		"enemies_spawned": 0,
		"enemies_killed": 0,
		"cleared": false,
		"reward_claimed": false,
	}

func _apply_save_post_spawn(data: Dictionary) -> void:
	# Edge case: SaveGame.apply_state ran AFTER we spawned (e.g. a manual load
	# mid-game). For each island the save says is cleared, free its live
	# enemies so the world matches the save.
	for id_v in data.keys():
		var id: String = String(id_v)
		var saved: Dictionary = data[id_v]
		if not bool(saved.get("cleared", false)):
			continue
		_state[id] = {
			"enemies_spawned": int(saved.get("enemies_spawned", 0)),
			"enemies_killed": int(saved.get("enemies_killed", 0)),
			"cleared": true,
			"reward_claimed": bool(saved.get("reward_claimed", true)),
		}
		var to_free: Array = []
		for n in _live_enemies.keys():
			if String(_live_enemies[n]) == id:
				to_free.append(n)
		for n in to_free:
			_live_enemies.erase(n)
			if is_instance_valid(n):
				(n as Node).queue_free()
