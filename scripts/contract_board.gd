class_name ContractBoard
extends Node
## Per-vendor contract state. Holds the vendor's level + XP, the 5 currently-
## available contracts, and the up-to-2 active contracts. Generates contracts
## on demand from a tier pool that widens with vendor level.
##
## A contract is a Dictionary:
##   {
##     "items":       Array of [material_id, count_required] pairs (1-3 entries),
##     "reward_gold": int    — 5x the sell value of the items,
##     "xp":          int    — equals the items' base sell value,
##   }

const ACTIVE_MAX: int = 2
const AVAILABLE_MAX: int = 5

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

var level: int = 1
var xp: int = 0
var available: Array = []
var active: Array = []

func _ready() -> void:
	while available.size() < AVAILABLE_MAX:
		available.append(_generate())

# XP needed to advance from `level` to `level+1`. Quadratic feel; 50/100/150/...
func xp_to_next() -> int:
	return 50 * level

func activate(idx: int) -> bool:
	if active.size() >= ACTIVE_MAX:
		return false
	if idx < 0 or idx >= available.size():
		return false
	var c: Dictionary = available[idx]
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
	miner.add_gold_currency(c.reward_gold)
	active.remove_at(idx)
	_gain_xp(c.xp)
	# Generate one fresh available contract to refill the slot freed by turn-in.
	# (Activate already refills, but turn-in doesn't free an available slot —
	# it frees an active one. Generating here keeps the board "always 5 ready"
	# at the next vendor level if we just leveled up.)
	while available.size() < AVAILABLE_MAX:
		available.append(_generate())
	changed.emit()
	return true

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

func _generate() -> Dictionary:
	var num_items: int = randi_range(1, 3)
	var pool: Array = _allowed_materials()
	var items: Array = []
	var used: Dictionary = {}
	var attempts: int = 0
	while items.size() < num_items and attempts < 12:
		var mid: int = pool.pick_random()
		if used.has(mid):
			attempts += 1
			continue
		used[mid] = true
		items.append([mid, _amount_for_material(mid)])
	var sell_value: int = 0
	for entry: Array in items:
		sell_value += int(entry[1]) * int(PRICES.get(entry[0], 0))
	return {
		"items": items,
		"reward_gold": sell_value * 5,
		"xp": sell_value,
	}
