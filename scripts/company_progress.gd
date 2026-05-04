extends Node
## Autoload. Tracks lifetime stats for Mine Co. and converts them into Company
## XP / rank. Each rank registers a stat-modifier source on PlayerStats so the
## bonuses stack with shop items / perks but don't replace them.
##
## Loose coupling — this script LISTENS to events from other systems (Miner,
## ContractBoard, ClaimVendorBoard, IslandEncounters, FactoryWorld, Unlocks);
## it never reaches in to mutate them. Sources stay clean.
##
## Save round-trip is owned by SaveGame under data["company"]. Lifetime
## counters MUST NOT double-count after a load — the listeners are emit-driven
## (in-session events only) and the gold-delta listener uses a one-shot
## baseline so the load-time gold_currency_changed emission isn't credited
## as fresh income.

# --- Tunables --------------------------------------------------------------

# XP weights per event type. Tuned so the first rank-up (500 XP) is reachable
# in ~30 minutes of normal play but Mine Co. Director (25k) is a slog.
const XP_PER_GOLD_UNIT: float        = 0.10   # +1 XP per 10 gold earned
const XP_PER_CONTRACT: int           = 25
const XP_PER_CLAIM_CLEARED: int      = 100
const CLAIM_CLEAR_THRESHOLD: float   = 0.60   # release with mined_pct >= 60%
const XP_PER_ENEMY: int              = 5
const XP_PER_FACTORY_ITEM: float     = 0.5
const XP_PER_BLUEPRINT: int          = 50

# Rank thresholds — total cumulative XP needed for that rank.
const RANKS: Array = [
	{"id": 1, "name": "Prospector",       "threshold":     0},
	{"id": 2, "name": "Claim Holder",     "threshold":   500},
	{"id": 3, "name": "Foreman",          "threshold":  1500},
	{"id": 4, "name": "Island Operator",  "threshold":  4000},
	{"id": 5, "name": "Industrialist",    "threshold": 10000},
	{"id": 6, "name": "Mine Co. Director","threshold": 25000},
]

# Per-rank stat modifiers. Applied additively as the player crosses each
# threshold. Each rank gets its own source name &"rank_<N>" on PlayerStats so
# resetting later (prestige) is a clean remove_source per rank.
# Ranks 1 has no rewards (starting rank).
const RANK_REWARDS: Dictionary = {
	2: [  # Claim Holder
		{"stat": &"sell_value_mult", "op": &"mul", "value": 1.05, "label": "+5% sell value"},
	],
	3: [  # Foreman
		{"stat": &"mining_damage_mult", "op": &"mul", "value": 1.05, "label": "+5% mining damage"},
		{"stat": &"factory_speed_mult", "op": &"mul", "value": 1.05, "label": "+5% factory speed"},
	],
	4: [  # Island Operator
		{"stat": &"scanner_range_mult", "op": &"mul", "value": 1.10, "label": "+10% scanner range"},
		{"stat": &"boat_speed_mult",    "op": &"mul", "value": 1.10, "label": "+10% boat speed"},
	],
	5: [  # Industrialist
		{"stat": &"factory_speed_mult", "op": &"mul", "value": 1.10, "label": "+10% factory speed"},
		{"stat": &"sell_value_mult",    "op": &"mul", "value": 1.10, "label": "+10% sell value"},
	],
	6: [  # Mine Co. Director
		{"stat": &"mining_damage_mult", "op": &"mul", "value": 1.15, "label": "+15% mining damage"},
		{"stat": &"sell_value_mult",    "op": &"mul", "value": 1.15, "label": "+15% sell value"},
		{"stat": &"factory_speed_mult", "op": &"mul", "value": 1.20, "label": "+20% factory speed"},
	],
}

# How long after world_ready we wait before binding to per-NPC boards. Mirrors
# SaveGame's auto_load_when_ready coroutine — town spawner is async.
const NPC_BIND_TIMEOUT_SEC: float = 15.0

# --- State -----------------------------------------------------------------

# Lifetime counters (saved).
var lifetime_gold_earned: int = 0
var contracts_completed: int = 0
var claims_cleared: int = 0
var enemies_defeated: int = 0
var factory_items_produced: int = 0
var blueprints_found: int = 0

var company_xp: int = 0
var rank: int = 1

signal xp_changed(new_xp: int)
signal rank_up(new_rank: int, name: String)
signal lifetime_changed

# --- Internal --------------------------------------------------------------

# Gold-delta tracking. Set the moment we first connect to the miner's
# gold_currency_changed signal so a load-time replay of the saved gold isn't
# misread as fresh income.
var _last_gold_seen: int = 0
var _gold_baseline_set: bool = false

# Factory XP throttle: signal can fire many times per tick, so we accumulate
# a fractional XP balance and apply it on a low-frequency timer.
var _factory_xp_pending: float = 0.0
var _factory_apply_accum: float = 0.0
const FACTORY_APPLY_INTERVAL: float = 0.5

var _bound_miner: Node = null
var _bound_contract_board: Node = null
var _bound_claim_board: Node = null
var _bound_island_encounters: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Hook the global Unlocks signal — autoload, always present.
	var unlocks: Node = get_node_or_null("/root/Unlocks")
	if unlocks != null and unlocks.has_signal("unlocked"):
		if not unlocks.is_connected("unlocked", Callable(self, "_on_blueprint_unlocked")):
			unlocks.connect("unlocked", Callable(self, "_on_blueprint_unlocked"))
	# Hook FactoryWorld's per-tick item-emitted re-emission. The autoload
	# defines the signal on _ready, so this is safe at our _ready time.
	var fw: Node = get_node_or_null("/root/FactoryWorld")
	if fw != null and fw.has_signal("factory_item_produced"):
		if not fw.is_connected("factory_item_produced", Callable(self, "_on_factory_item_produced")):
			fw.connect("factory_item_produced", Callable(self, "_on_factory_item_produced"))
	# The Miner / vendor-NPC boards aren't around yet — defer until the world
	# is up. Mirrors SaveGame.auto_load_when_ready.
	call_deferred("_bind_when_ready")
	set_process(true)

func _process(delta: float) -> void:
	# Throttle factory XP application so we don't spam stat-changed signals.
	if _factory_xp_pending > 0.0:
		_factory_apply_accum += delta
		if _factory_apply_accum >= FACTORY_APPLY_INTERVAL:
			_factory_apply_accum = 0.0
			_flush_factory_xp()

# --- Public API ------------------------------------------------------------

func rank_name() -> String:
	return _rank_def(rank).name

func next_rank_name() -> String:
	if rank >= RANKS.size():
		return rank_name()
	return _rank_def(rank + 1).name

# Returns XP needed to reach the NEXT rank. 0 when already maxed.
func xp_to_next_rank() -> int:
	if rank >= RANKS.size():
		return 0
	return max(0, int(_rank_def(rank + 1).threshold) - company_xp)

# XP into the current rank (for progress-bar fills).
func xp_into_current_rank() -> int:
	var base: int = int(_rank_def(rank).threshold)
	return max(0, company_xp - base)

# Span between the current and next thresholds (denominator for the bar).
func xp_span_current_to_next() -> int:
	if rank >= RANKS.size():
		return 0
	var base: int = int(_rank_def(rank).threshold)
	var nxt: int = int(_rank_def(rank + 1).threshold)
	return max(1, nxt - base)

# Re-registers every rank reward source on PlayerStats. Idempotent — used both
# on rank-up and on save-load to put the modifiers back without double-stacking.
func apply_all_rank_modifiers() -> void:
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats == null:
		return
	# Tear down any rank source we might have, regardless of current rank.
	for r_def: Dictionary in RANKS:
		stats.call("remove_source", _rank_source(int(r_def.id)))
	# Re-add for every level <= current rank.
	for r: int in range(1, rank + 1):
		_register_rank_modifiers_on_stats(stats, r)

# Force a recompute of the rank from XP. Used by admin / tests.
func recompute_rank() -> void:
	var new_rank: int = _rank_for_xp(company_xp)
	if new_rank == rank:
		return
	_apply_rank_change(rank, new_rank, false)

# Convenience for an admin "give XP" hook.
func grant_xp(amount: int) -> void:
	if amount <= 0:
		return
	_add_xp(amount)

# --- Event handlers --------------------------------------------------------

func _on_gold_changed(new_amount: int) -> void:
	# First emission after binding becomes the baseline so saved gold restores
	# don't get credited as freshly-earned.
	if not _gold_baseline_set:
		_last_gold_seen = new_amount
		_gold_baseline_set = true
		return
	var delta: int = new_amount - _last_gold_seen
	_last_gold_seen = new_amount
	if delta <= 0:
		return  # purchase / negative delta — don't credit
	lifetime_gold_earned += delta
	lifetime_changed.emit()
	var xp_gain: int = int(floor(float(delta) * XP_PER_GOLD_UNIT))
	if xp_gain > 0:
		_add_xp(xp_gain)

func _on_contract_completed(_reward_gold: int, _xp: int) -> void:
	contracts_completed += 1
	lifetime_changed.emit()
	_add_xp(XP_PER_CONTRACT)

func _on_claim_released(_island_id: String, mined_pct: float) -> void:
	if mined_pct >= CLAIM_CLEAR_THRESHOLD:
		claims_cleared += 1
		lifetime_changed.emit()
		_add_xp(XP_PER_CLAIM_CLEARED)

func _on_enemy_defeated() -> void:
	enemies_defeated += 1
	lifetime_changed.emit()
	_add_xp(XP_PER_ENEMY)

func _on_island_cleared(_island_id: String, _reward_gold: int) -> void:
	# The per-enemy `enemy_defeated` signal already credits XP per kill. The
	# island-cleared event itself doesn't re-grant XP — the lifetime stats
	# we'd want here (islands cleared) are already covered by the existing
	# claims_cleared counter on release. Hook left in place so extending
	# later (e.g. island-clear achievements) is one-line.
	pass

func _on_factory_item_produced(_material_id: int) -> void:
	_factory_xp_pending += XP_PER_FACTORY_ITEM
	# factory_items_produced increments live so the UI counter is accurate
	# even between flushes. XP application is throttled to keep the stat
	# system from churning per item.
	factory_items_produced += 1
	lifetime_changed.emit()

func _on_blueprint_unlocked(_blueprint_id: String) -> void:
	blueprints_found += 1
	lifetime_changed.emit()
	_add_xp(XP_PER_BLUEPRINT)

# --- Internal helpers ------------------------------------------------------

func _flush_factory_xp() -> void:
	var whole: int = int(floor(_factory_xp_pending))
	if whole <= 0:
		return
	_factory_xp_pending -= float(whole)
	_add_xp(whole)

func _add_xp(amount: int) -> void:
	if amount <= 0:
		return
	company_xp += amount
	xp_changed.emit(company_xp)
	var new_rank: int = _rank_for_xp(company_xp)
	if new_rank > rank:
		_apply_rank_change(rank, new_rank, true)

func _apply_rank_change(old_rank: int, new_rank: int, announce: bool) -> void:
	rank = new_rank
	# Register modifiers for every rank we just crossed (in case the player
	# leapt by more than 1 from a single XP grant).
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null:
		for r: int in range(old_rank + 1, new_rank + 1):
			_register_rank_modifiers_on_stats(stats, r)
	if announce:
		var name: String = _rank_def(new_rank).name
		rank_up.emit(new_rank, name)
		_show_toast("Promoted to %s!" % name)

func _register_rank_modifiers_on_stats(stats: Node, r: int) -> void:
	var src: StringName = _rank_source(r)
	# Idempotency: tear down then re-add. add_modifier doesn't dedupe and
	# this path is sometimes hit on load + on rank-up.
	stats.call("remove_source", src)
	var rewards: Array = RANK_REWARDS.get(r, [])
	for m: Dictionary in rewards:
		stats.call("add_modifier", src,
			StringName(String(m.stat)),
			StringName(String(m.op)),
			float(m.value))

static func _rank_source(r: int) -> StringName:
	return StringName("rank_%d" % r)

static func _rank_def(r: int) -> Dictionary:
	var idx: int = clampi(r - 1, 0, RANKS.size() - 1)
	return RANKS[idx]

static func _rank_for_xp(xp: int) -> int:
	var best: int = 1
	for d: Dictionary in RANKS:
		if xp >= int(d.threshold):
			best = int(d.id)
	return best

# Returns the cumulative-XP threshold for rank id.
static func threshold_for_rank(r: int) -> int:
	return int(_rank_def(r).threshold)

# Returns the human-readable label list for rank r's rewards.
static func reward_labels_for_rank(r: int) -> Array:
	var out: Array = []
	for m: Dictionary in RANK_REWARDS.get(r, []):
		out.append(String(m.get("label", "")))
	return out

func _show_toast(text: String) -> void:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	var feed: Node = loop.get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_text_message"):
		feed.call("add_text_message", text)

# --- Late-bind to per-scene event sources ----------------------------------

# Town NPCs / the player aren't around at autoload time. Wait for them, then
# subscribe. Mirrors the loop in SaveGame._auto_load_when_ready.
func _bind_when_ready() -> void:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	# Wait for the player_miner.
	var elapsed: float = 0.0
	while loop.get_first_node_in_group("player_miner") == null and elapsed < NPC_BIND_TIMEOUT_SEC:
		await loop.create_timer(0.25).timeout
		elapsed += 0.25
	_bind_miner(loop.get_first_node_in_group("player_miner"))
	# Wait for vendor NPCs (and the encounter node).
	elapsed = 0.0
	while elapsed < NPC_BIND_TIMEOUT_SEC:
		var have_contract: bool = loop.get_first_node_in_group("contract_vendor_npcs") != null
		var have_claim: bool = loop.get_first_node_in_group("claim_vendor_npcs") != null
		var have_enc: bool = loop.get_first_node_in_group("island_encounters") != null
		if have_contract and have_claim and have_enc:
			break
		await loop.create_timer(0.25).timeout
		elapsed += 0.25
	# Bind whatever's available — partial bindings still work, they just miss
	# events from the absent system.
	var contract_npc: Node = loop.get_first_node_in_group("contract_vendor_npcs")
	if contract_npc != null:
		_bind_contract_board(contract_npc.get("contract_board"))
	var claim_npc: Node = loop.get_first_node_in_group("claim_vendor_npcs")
	if claim_npc != null:
		_bind_claim_board(claim_npc.get("claim_board"))
	_bind_island_encounters(loop.get_first_node_in_group("island_encounters"))

func _bind_miner(miner: Node) -> void:
	if miner == null or miner == _bound_miner:
		return
	_bound_miner = miner
	if miner.has_signal("gold_currency_changed"):
		# Snapshot the live gold as the baseline. From now on, only the DELTA
		# above this baseline counts as new income — perfect for both fresh
		# starts (baseline 0) and post-load binds (baseline = restored gold).
		# If save-load fires apply_save_data later, _gold_baseline_set is
		# flipped back to false there so the next emission re-anchors against
		# the loaded value.
		_last_gold_seen = int(miner.get("gold_currency"))
		_gold_baseline_set = true
		if not miner.gold_currency_changed.is_connected(_on_gold_changed):
			miner.gold_currency_changed.connect(_on_gold_changed)

func _bind_contract_board(board: Node) -> void:
	if board == null or board == _bound_contract_board:
		return
	_bound_contract_board = board
	if board.has_signal("contract_completed"):
		if not board.is_connected("contract_completed", Callable(self, "_on_contract_completed")):
			board.connect("contract_completed", Callable(self, "_on_contract_completed"))

func _bind_claim_board(board: Node) -> void:
	if board == null or board == _bound_claim_board:
		return
	_bound_claim_board = board
	if board.has_signal("claim_released"):
		if not board.is_connected("claim_released", Callable(self, "_on_claim_released")):
			board.connect("claim_released", Callable(self, "_on_claim_released"))

func _bind_island_encounters(node: Node) -> void:
	if node == null or node == _bound_island_encounters:
		return
	_bound_island_encounters = node
	if node.has_signal("enemy_defeated"):
		if not node.is_connected("enemy_defeated", Callable(self, "_on_enemy_defeated")):
			node.connect("enemy_defeated", Callable(self, "_on_enemy_defeated"))
	if node.has_signal("island_cleared"):
		if not node.is_connected("island_cleared", Callable(self, "_on_island_cleared")):
			node.connect("island_cleared", Callable(self, "_on_island_cleared"))

# --- Save / load -----------------------------------------------------------

func get_save_data() -> Dictionary:
	return {
		"lifetime_gold_earned": lifetime_gold_earned,
		"contracts_completed": contracts_completed,
		"claims_cleared": claims_cleared,
		"enemies_defeated": enemies_defeated,
		"factory_items_produced": factory_items_produced,
		"blueprints_found": blueprints_found,
		"company_xp": company_xp,
		"rank": rank,
	}

func apply_save_data(data: Dictionary) -> void:
	lifetime_gold_earned = int(data.get("lifetime_gold_earned", 0))
	contracts_completed = int(data.get("contracts_completed", 0))
	claims_cleared = int(data.get("claims_cleared", 0))
	enemies_defeated = int(data.get("enemies_defeated", 0))
	factory_items_produced = int(data.get("factory_items_produced", 0))
	blueprints_found = int(data.get("blueprints_found", 0))
	company_xp = int(data.get("company_xp", 0))
	rank = clampi(int(data.get("rank", 1)), 1, RANKS.size())
	# Defensive: if the stored rank disagrees with the XP, trust the XP.
	# Avoids a save where rank was bumped externally but XP didn't follow.
	var derived: int = _rank_for_xp(company_xp)
	if derived > rank:
		rank = derived
	# Re-stamp rank modifier sources on PlayerStats so the bonuses are live.
	apply_all_rank_modifiers()
	# Reset the gold baseline so the post-load gold_currency_changed emission
	# from the miner doesn't credit the loaded balance as new income.
	_gold_baseline_set = false
	xp_changed.emit(company_xp)
	lifetime_changed.emit()
