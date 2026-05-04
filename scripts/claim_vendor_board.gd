class_name ClaimVendorBoard
extends Node
## Per-vendor land-claim state. Holds the vendor's level + XP, the list of
## available (i.e. not currently owned) island claims, and the player's
## currently-owned claim (or null). One claim at a time.
##
## All islands themselves come from IslandVoxelGenerator.CLAIM_ISLANDS — this
## board just decides which are visible at the player's current vendor level
## and tracks per-claim mining progress for the owned one.

signal changed   # fires after any state mutation so UIs can refresh

var level: int = 1
var xp: int = 0

# {island_id (String) → mined_so_far {OreType → int}} for the owned claim only.
var owned_id: String = ""
var owned_mined: Dictionary = {}   # OreDeposit.OreType → int

func xp_to_next() -> int:
	# 100 → 250 → 500 → 900 → ∞ (level cap at 5).
	if level >= 5:
		return 99999
	return [100, 250, 500, 900, 99999][clampi(level - 1, 0, 4)]

func has_owned() -> bool:
	return owned_id != ""

# Returns the list of claim-island Dictionaries (from IslandVoxelGenerator)
# the player is allowed to see at the vendor's current level, excluding the
# currently-owned one.
func available() -> Array:
	var out: Array = []
	for isle: Dictionary in IslandVoxelGenerator.CLAIM_ISLANDS:
		if int(isle.tier) > level:
			continue
		if isle.id == owned_id:
			continue
		out.append(isle)
	return out

# Returns the island Dictionary for the currently-owned claim, or {} if none.
func owned_island() -> Dictionary:
	if owned_id == "":
		return {}
	for isle: Dictionary in IslandVoxelGenerator.CLAIM_ISLANDS:
		if isle.id == owned_id:
			return isle
	return {}

func can_buy(island_id: String, miner: Node) -> bool:
	if has_owned() or miner == null:
		return false
	for isle: Dictionary in IslandVoxelGenerator.CLAIM_ISLANDS:
		if isle.id != island_id:
			continue
		if int(isle.tier) > level:
			return false
		var price: int = int(ClaimDef.tier(isle.tier).price)
		return int(miner.get("gold_currency")) >= price
	return false

func buy(island_id: String, miner: Node) -> bool:
	if not can_buy(island_id, miner):
		return false
	for isle: Dictionary in IslandVoxelGenerator.CLAIM_ISLANDS:
		if isle.id != island_id:
			continue
		var price: int = int(ClaimDef.tier(isle.tier).price)
		miner.add_gold_currency(-price)
		owned_id = island_id
		owned_mined = {}
		changed.emit()
		return true
	return false

# Player credits a destroyed deposit toward the owned claim. Caller filters
# by spatial check (deposit must be inside the owned island radius).
func credit_mining(ore_type: int, amount: int) -> void:
	if not has_owned() or amount <= 0:
		return
	owned_mined[ore_type] = int(owned_mined.get(ore_type, 0)) + amount
	changed.emit()

# Returns {OreType → remaining_count_estimate}. Negative values are clamped.
func owned_remaining_estimate() -> Dictionary:
	if not has_owned():
		return {}
	var isle: Dictionary = owned_island()
	var info: Dictionary = ClaimDef.tier(isle.tier)
	var deps: Dictionary = info.deposits
	var per: Dictionary = ClaimDef.APPROX_ORE_PER_DEPOSIT
	var totals: Dictionary = {
		MaterialDefs.MaterialId.STONE:    int(round(float(deps.stone) * per.stone)),
		MaterialDefs.MaterialId.IRON_ORE: int(round(float(deps.iron)  * per.iron)),
		MaterialDefs.MaterialId.GOLD_ORE: int(round(float(deps.gold)  * per.gold)),
	}
	# Map OreType keys (which is what credit_mining stores) to MaterialId for
	# subtraction. OreDeposit.OreType: 0=STONE, 1=IRON, 2=GOLD.
	var ore_to_mat: Dictionary = {
		0: MaterialDefs.MaterialId.STONE,
		1: MaterialDefs.MaterialId.IRON_ORE,
		2: MaterialDefs.MaterialId.GOLD_ORE,
	}
	for ore_type: int in owned_mined.keys():
		var mid: int = int(ore_to_mat.get(ore_type, -1))
		if mid < 0:
			continue
		totals[mid] = max(0, int(totals[mid]) - int(owned_mined[ore_type]))
	return totals

# Computes XP awarded for releasing the currently-owned claim. Equals the
# tier's xp_full × the fraction of estimated ore the player extracted.
func release_xp_preview() -> int:
	if not has_owned():
		return 0
	var isle: Dictionary = owned_island()
	var info: Dictionary = ClaimDef.tier(isle.tier)
	var per: Dictionary = ClaimDef.APPROX_ORE_PER_DEPOSIT
	var deps: Dictionary = info.deposits
	var total_units: float = (
		float(deps.stone) * per.stone +
		float(deps.iron)  * per.iron +
		float(deps.gold)  * per.gold
	)
	if total_units <= 0.0:
		return 0
	var per_ore: Dictionary = {0: per.stone, 1: per.iron, 2: per.gold}
	var mined_units: float = 0.0
	for ore_type: int in owned_mined.keys():
		mined_units += float(owned_mined[ore_type])
	# Cap at 100% so over-generous deposits can't inflate XP past the tier max.
	var pct: float = clampf(mined_units / total_units, 0.0, 1.0)
	return int(round(float(info.xp_full) * pct))

func release() -> int:
	if not has_owned():
		return 0
	var awarded: int = release_xp_preview()
	owned_id = ""
	owned_mined = {}
	_gain_xp(awarded)
	changed.emit()
	return awarded

func get_save_data() -> Dictionary:
	# owned_mined keys are OreType ints; JSON keys must be strings — convert
	# both ways. Same trick the engine already does for inventory dicts.
	var mined_str: Dictionary = {}
	for k: int in owned_mined.keys():
		mined_str[str(k)] = int(owned_mined[k])
	return {
		"level": level,
		"xp": xp,
		"owned_id": owned_id,
		"owned_mined": mined_str,
	}

func apply_save_data(data: Dictionary) -> void:
	level = int(data.get("level", 1))
	xp = int(data.get("xp", 0))
	owned_id = String(data.get("owned_id", ""))
	owned_mined = {}
	for k: Variant in data.get("owned_mined", {}).keys():
		owned_mined[int(String(k))] = int(data["owned_mined"][k])
	changed.emit()

func _gain_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	while level < 5 and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
	# Clamp progress at max level so the bar stays full.
	if level >= 5:
		xp = 0
