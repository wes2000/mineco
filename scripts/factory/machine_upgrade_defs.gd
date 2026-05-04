class_name MachineUpgradeDefs
extends RefCounted
## Static catalog of machine upgrade tiers. Mk1 (level 0) is base; entries
## describe what it costs to step UP to the next mark.
##
## UPGRADES[kind] is an array of step costs:
##   index 0 -> cost to upgrade Mk1 -> Mk2
##   index 1 -> cost to upgrade Mk2 -> Mk3
## Each step is { "gold": int, "materials": { MaterialDefs.MaterialId : int } }.
##
## The cycle / capacity benefits live on the Building subclasses themselves
## (apply_upgrade_to_cycle, effective_hopper_cap, processing_buffer_cap) so
## game balance and UI cost copy can move independently.

const _MD: GDScript = preload("res://scripts/factory/material_defs.gd")

const MAX_LEVEL: int = 2   # Mk3

const UPGRADES: Dictionary = {
	&"loader": [
		{ "gold":  500, "materials": { _MD.MaterialId.IRON_INGOT: 5 } },
		{ "gold": 2000, "materials": { _MD.MaterialId.GOLD_INGOT: 3 } },
	],
	&"smelter": [
		{ "gold":  500, "materials": { _MD.MaterialId.IRON_INGOT: 5 } },
		{ "gold": 2000, "materials": { _MD.MaterialId.GOLD_INGOT: 3 } },
	],
	&"forge": [
		{ "gold":  750, "materials": { _MD.MaterialId.IRON_INGOT: 8 } },
		{ "gold": 2500, "materials": { _MD.MaterialId.GOLD_INGOT: 4 } },
	],
	&"crusher": [
		{ "gold":  750, "materials": { _MD.MaterialId.IRON_INGOT: 6 } },
		{ "gold": 2500, "materials": { _MD.MaterialId.GOLD_INGOT: 3 } },
	],
}

# Multiplier on cycle ticks per level. Mk1 = 1.0, Mk2 = 0.75, Mk3 = 0.5.
const CYCLE_DISCOUNT: Array[float] = [1.0, 0.75, 0.5]

# Loader hopper cap by level.
const LOADER_HOPPER_CAP: Array[int] = [999, 1500, 2500]

# Smelter / Forge processing buffer cap by level.
const PROCESSING_BUFFER_CAP: Array[int] = [3, 5, 8]

# Hard floor on cycle ticks so Mk3 + max factory_speed_mult can't collapse to 0.
const MIN_TICKS: int = 2

static func max_level(_kind: StringName) -> int:
	return MAX_LEVEL

static func is_maxed(level: int) -> bool:
	return level >= MAX_LEVEL

static func level_label(level: int) -> String:
	return "Mk%d" % (level + 1)

# Returns the next upgrade step dict ({"gold":..., "materials":{...}}) for the
# given kind/current level, or an empty dict if we're already maxed.
static func next_upgrade_for(kind: StringName, current_level: int) -> Dictionary:
	if not UPGRADES.has(kind):
		return {}
	var arr: Array = UPGRADES[kind]
	if current_level < 0 or current_level >= arr.size():
		return {}
	return arr[current_level]

static func cycle_discount_for(level: int) -> float:
	if level < 0:
		return CYCLE_DISCOUNT[0]
	if level >= CYCLE_DISCOUNT.size():
		return CYCLE_DISCOUNT[CYCLE_DISCOUNT.size() - 1]
	return CYCLE_DISCOUNT[level]

static func loader_hopper_cap_for(level: int) -> int:
	if level < 0:
		return LOADER_HOPPER_CAP[0]
	if level >= LOADER_HOPPER_CAP.size():
		return LOADER_HOPPER_CAP[LOADER_HOPPER_CAP.size() - 1]
	return LOADER_HOPPER_CAP[level]

static func processing_buffer_cap_for(level: int) -> int:
	if level < 0:
		return PROCESSING_BUFFER_CAP[0]
	if level >= PROCESSING_BUFFER_CAP.size():
		return PROCESSING_BUFFER_CAP[PROCESSING_BUFFER_CAP.size() - 1]
	return PROCESSING_BUFFER_CAP[level]
