class_name ContractBoard
extends Node
## Per-vendor contract state. Holds the vendor's level + XP, the 5 currently-
## available contracts, and the up-to-2 active contracts. Generates contracts
## on demand from a tier pool that widens with vendor level.
##
## A contract is a Dictionary:
##   {
##     "items":            Array of [material_id, count_required] pairs (1-3 entries),
##     "reward_gold":      int    — base 5x sell value, scaled by modifier,
##     "xp":               int    — base equals item sell value, scaled by modifier,
##     "modifier":         String — "" / "rush_order" / "bulk_order" / "refined_goods",
##     "expires_at":       float  — absolute Time.get_unix_time_from_system(); 0 = no expiry,
##     "blueprint_chance": float  — 0.0..1.0 roll on turn-in for a blueprint reward,
##     "required_flags":   Array  — reserved for later gating,
##   }

# Preload the blueprint catalog so contract_board doesn't need its class_name
# resolved through the parser cache (autoload-pattern, per project notes).
const _BlueprintDefs: GDScript = preload("res://scripts/blueprint_defs.gd")

const ACTIVE_MAX: int = 2
const AVAILABLE_MAX: int = 5

# --- Modifier table --------------------------------------------------------
# Roll weights MUST sum to 100. Refined orders only become eligible at vendor
# level >= REFINED_MIN_LEVEL — until then the refined weight is redistributed
# into "none" so total still sums to 100.
const MOD_NONE: String = ""
const MOD_RUSH: String = "rush_order"
const MOD_BULK: String = "bulk_order"
const MOD_REFINED: String = "refined_goods"

const MOD_WEIGHTS: Dictionary = {
	MOD_NONE: 60,
	MOD_RUSH: 18,
	MOD_BULK: 12,
	MOD_REFINED: 10,
}

const REFINED_MIN_LEVEL: int = 3
const RUSH_DURATION_SEC: float = 240.0  # 4 minutes

# Multipliers per modifier. Reward / XP go through these when stamping the
# contract; bulk also multiplies item counts.
const MOD_REWARD_MUL: Dictionary = {
	MOD_NONE: 1.0,
	MOD_RUSH: 2.0,
	MOD_BULK: 1.8,
	MOD_REFINED: 2.5,
}
const MOD_XP_MUL: Dictionary = {
	MOD_NONE: 1.0,
	MOD_RUSH: 1.5,
	MOD_BULK: 1.5,
	MOD_REFINED: 2.0,
}
const MOD_COUNT_MUL: Dictionary = {
	MOD_NONE: 1.0,
	MOD_RUSH: 1.0,
	MOD_BULK: 2.5,
	MOD_REFINED: 1.0,
}
# Chance to drop a blueprint on successful turn-in.
const MOD_BLUEPRINT_CHANCE: Dictionary = {
	MOD_NONE: 0.0,
	MOD_RUSH: 0.20,
	MOD_BULK: 0.05,
	MOD_REFINED: 0.15,
}

# Per-unit sell prices (mirror VendorUI.PRICES). Used to compute reward + XP.
const PRICES: Dictionary = {
	0: 1, 1: 4, 2: 12,    # STONE / BRICK / BLOCK
	3: 3, 4: 10, 5: 30,   # IRON_ORE / IRON_INGOT / IRON_BAR
	6: 10, 7: 30, 8: 90,  # GOLD_ORE / GOLD_INGOT / GOLD_BAR
}

# Material pool by vendor level. Higher level = wider, more T2/T3.
const ALLOWED_BY_LEVEL: Dictionary = {
	1: [0, 3],                    # STONE, IRON_ORE
	2: [0, 3, 6],                 # + GOLD_ORE
	3: [0, 3, 6, 1],              # + BRICK
	4: [0, 3, 6, 1, 4],           # + IRON_INGOT
	5: [0, 3, 6, 1, 4, 7],        # + GOLD_INGOT
	6: [1, 4, 7, 2],              # T2/T3 emphasized; drop raw ores
	7: [4, 7, 2, 5],              # + IRON_BAR
	8: [7, 2, 5, 8],              # + GOLD_BAR
}

signal changed   # fires after any state mutation so UIs can refresh
# Fired at the end of a successful turn_in so meta-progression layers
# (CompanyProgress) can credit lifetime stats + XP without the contract board
# needing to know who's listening.
signal contract_completed(reward_gold: int, xp: int)

var level: int = 1
var xp: int = 0
var available: Array = []
var active: Array = []

func _ready() -> void:
	while available.size() < AVAILABLE_MAX:
		available.append(_generate())
	set_process(true)

func _process(_delta: float) -> void:
	# Tick rush-order expiration. Walk a copy of indices because we may
	# mutate the active list in place. Refilling available is handled here
	# so a vendor who never gets visited doesn't sit on an empty rush slot
	# forever.
	if active.is_empty():
		return
	var now: float = Time.get_unix_time_from_system()
	var expired_any: bool = false
	for i: int in range(active.size() - 1, -1, -1):
		var c: Dictionary = active[i]
		var exp_at: float = float(c.get("expires_at", 0.0))
		if exp_at > 0.0 and now >= exp_at:
			active.remove_at(i)
			expired_any = true
			_show_toast("Rush order expired")
	if expired_any:
		while available.size() < AVAILABLE_MAX:
			available.append(_generate())
		changed.emit()

# XP needed to advance from `level` to `level+1`. Quadratic feel; 50/100/150/...
func xp_to_next() -> int:
	return 50 * level

func activate(idx: int) -> bool:
	if active.size() >= ACTIVE_MAX:
		return false
	if idx < 0 or idx >= available.size():
		return false
	var c: Dictionary = available[idx]
	# Stamp expiration when activated, NOT at generation time. A rush order
	# that's been sitting on the board for 10 minutes shouldn't already be
	# half-burned the moment the player picks it up.
	if String(c.get("modifier", "")) == MOD_RUSH:
		c["expires_at"] = Time.get_unix_time_from_system() + RUSH_DURATION_SEC
	available.remove_at(idx)
	active.append(c)
	while available.size() < AVAILABLE_MAX:
		available.append(_generate())
	changed.emit()
	return true

func can_turn_in(idx: int, miner: Node) -> bool:
	if miner == null or idx < 0 or idx >= active.size():
		return false
	var c: Dictionary = active[idx]
	for entry: Array in c.items:
		if miner.get_material_count(entry[0]) < entry[1]:
			return false
	return true

func turn_in(idx: int, miner: Node) -> bool:
	if not can_turn_in(idx, miner):
		return false
	var c: Dictionary = active[idx]
	for entry: Array in c.items:
		miner.remove_material(entry[0], entry[1])
	# Scale reward by the contract reward multiplier (perks, vendor goodwill).
	var stats: Node = get_node_or_null("/root/PlayerStats")
	var reward_mul: float = 1.0
	if stats != null:
		reward_mul = float(stats.call("get_stat", &"contract_reward_mult"))
	miner.add_gold_currency(int(round(float(c.reward_gold) * reward_mul)))
	# Roll a blueprint drop, if this contract type carries a chance.
	var chance: float = float(c.get("blueprint_chance", 0.0))
	if chance > 0.0 and randf() < chance:
		_award_random_blueprint()
	active.remove_at(idx)
	var awarded_gold: int = int(round(float(c.reward_gold) * reward_mul))
	var awarded_xp: int = int(c.xp)
	_gain_xp(awarded_xp)
	# Generate one fresh available contract to refill the slot freed by turn-in.
	while available.size() < AVAILABLE_MAX:
		available.append(_generate())
	changed.emit()
	# Notify meta-progression after all internal state has settled so any
	# downstream listener sees a consistent board.
	contract_completed.emit(awarded_gold, awarded_xp)
	return true

func get_save_data() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"available": available.duplicate(true),
		"active": active.duplicate(true),
	}

func apply_save_data(data: Dictionary) -> void:
	level = int(data.get("level", 1))
	xp = int(data.get("xp", 0))
	available = []
	for c: Variant in data.get("available", []):
		available.append(_normalize_contract(c))
	active = []
	for c: Variant in data.get("active", []):
		active.append(_normalize_contract(c))
	# Backfill if save came from a state with fewer slots than AVAILABLE_MAX.
	while available.size() < AVAILABLE_MAX:
		available.append(_generate())
	changed.emit()

func _normalize_contract(raw: Variant) -> Dictionary:
	# JSON parse returns Array (untyped) for items, plus int/float numbers.
	# Coerce back to the shape contract_board hands out elsewhere, including
	# the new modifier fields. Old saves without them default cleanly.
	if not (raw is Dictionary):
		return _generate()
	var d: Dictionary = raw
	var items: Array = []
	for entry: Variant in d.get("items", []):
		if entry is Array and entry.size() == 2:
			items.append([int(entry[0]), int(entry[1])])
	var mod: String = String(d.get("modifier", ""))
	# Coerce unknown modifier strings to none so we don't carry junk.
	if not MOD_WEIGHTS.has(mod):
		mod = MOD_NONE
	return {
		"items": items,
		"reward_gold": int(d.get("reward_gold", 0)),
		"xp": int(d.get("xp", 0)),
		"modifier": mod,
		"expires_at": float(d.get("expires_at", 0.0)),
		"blueprint_chance": float(d.get("blueprint_chance", 0.0)),
		"required_flags": d.get("required_flags", []),
	}

func _gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
	# Level-up may have widened the material pool; refresh the available
	# contracts to reflect the new tier.
	if amount > 0:
		available.clear()
		while available.size() < AVAILABLE_MAX:
			available.append(_generate())

func _allowed_materials() -> Array:
	var key: int = clampi(level, 1, 8)
	return ALLOWED_BY_LEVEL[key]

func _amount_for_material(mid: int) -> int:
	var tier: int = MaterialDefs.TIER.get(mid, 1)
	match tier:
		1: return [5, 10, 15, 20, 25].pick_random()
		2: return [3, 6, 9, 12].pick_random()
		3: return [1, 2, 3, 5].pick_random()
	return 5

# Pick a modifier id using the weight table, redistributing refined's slice
# into "none" when the vendor isn't high enough level for it. Always returns
# one of the known ids.
func _pick_modifier() -> String:
	var weights: Dictionary = MOD_WEIGHTS.duplicate()
	if level < REFINED_MIN_LEVEL:
		weights[MOD_NONE] = int(weights[MOD_NONE]) + int(weights[MOD_REFINED])
		weights[MOD_REFINED] = 0
	var total: int = 0
	for v: Variant in weights.values():
		total += int(v)
	if total <= 0:
		return MOD_NONE
	var roll: int = randi() % total
	var acc: int = 0
	for k: Variant in weights.keys():
		acc += int(weights[k])
		if roll < acc:
			return String(k)
	return MOD_NONE

# Refined goods only — pulls from T2/T3 pool regardless of vendor level pool.
func _refined_pool() -> Array:
	var out: Array = []
	for mid: int in MaterialDefs.TIER_2_MATERIALS:
		out.append(mid)
	for mid: int in MaterialDefs.TIER_3_MATERIALS:
		out.append(mid)
	return out

func _generate() -> Dictionary:
	var modifier: String = _pick_modifier()
	var num_items: int = randi_range(1, 3)
	var pool: Array
	if modifier == MOD_REFINED:
		pool = _refined_pool()
	else:
		pool = _allowed_materials()
	var items: Array = []
	var used: Dictionary = {}
	var attempts: int = 0
	while items.size() < num_items and attempts < 12:
		var mid: int = pool.pick_random()
		if used.has(mid):
			attempts += 1
			continue
		used[mid] = true
		var amount: int = _amount_for_material(mid)
		# Bulk multiplies item counts. Round to nearest int, min 1.
		if modifier == MOD_BULK:
			amount = max(1, int(round(float(amount) * float(MOD_COUNT_MUL[MOD_BULK]))))
		items.append([mid, amount])
	var sell_value: int = 0
	for entry: Array in items:
		sell_value += int(entry[1]) * int(PRICES.get(entry[0], 0))
	var reward_mul: float = float(MOD_REWARD_MUL.get(modifier, 1.0))
	var xp_mul: float = float(MOD_XP_MUL.get(modifier, 1.0))
	var bp_chance: float = clampf(float(MOD_BLUEPRINT_CHANCE.get(modifier, 0.0)), 0.0, 1.0)
	# expires_at stamped at activation time, not generation. A rush sitting in
	# the available list shouldn't burn down before the player even picks it.
	return {
		"items": items,
		"reward_gold": int(round(float(sell_value * 5) * reward_mul)),
		"xp": int(round(float(sell_value) * xp_mul)),
		"modifier": modifier,
		"expires_at": 0.0,
		"blueprint_chance": bp_chance,
		"required_flags": [],
	}

# --- Blueprint drop --------------------------------------------------------

func _award_random_blueprint() -> void:
	var unlocks: Node = get_node_or_null("/root/Unlocks")
	if unlocks == null:
		return
	var all_ids: Array[String] = _BlueprintDefs.all_ids()
	var pool: Array[String] = []
	for bp_id: String in all_ids:
		if not bool(unlocks.call("has", bp_id)):
			pool.append(bp_id)
	if pool.is_empty():
		# Nothing left to unlock — silent no-op so rare full-clear states
		# don't break the turn-in flow.
		return
	var chosen: String = pool[randi() % pool.size()]
	if bool(unlocks.call("unlock", chosen)):
		var pretty: String = _BlueprintDefs.name_for(chosen)
		_show_toast("Blueprint unlocked: %s" % pretty)

func _show_toast(text: String) -> void:
	var feed: Node = get_tree().get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_text_message"):
		feed.add_text_message(text)
