class_name MaterialDefs
extends RefCounted

enum MaterialId {
	STONE, BRICK, BLOCK,
	IRON_ORE, IRON_INGOT, IRON_BAR,
	GOLD_ORE, GOLD_INGOT, GOLD_BAR,
}

# Tier 1 = mined ore, 2 = smelted, 3 = forged
const TIER: Dictionary = {
	MaterialId.STONE: 1, MaterialId.BRICK: 2, MaterialId.BLOCK: 3,
	MaterialId.IRON_ORE: 1, MaterialId.IRON_INGOT: 2, MaterialId.IRON_BAR: 3,
	MaterialId.GOLD_ORE: 1, MaterialId.GOLD_INGOT: 2, MaterialId.GOLD_BAR: 3,
}

# Loader emit interval (ticks). T1 only.
const LOADER_EMIT_TICKS: Dictionary = {
	MaterialId.STONE: 10,
	MaterialId.IRON_ORE: 20,
	MaterialId.GOLD_ORE: 40,
}

# Smelter cycle (ticks). T1 -> T2.
const SMELTER_TICKS: Dictionary = {
	MaterialId.STONE: 20,
	MaterialId.IRON_ORE: 40,
	MaterialId.GOLD_ORE: 80,
}

# Forge cycle (ticks). T2 -> T3.
const FORGE_TICKS: Dictionary = {
	MaterialId.BRICK: 40,
	MaterialId.IRON_INGOT: 80,
	MaterialId.GOLD_INGOT: 160,
}

# Crusher cycle (ticks). T1 -> same T1 with a bonus chance.
const CRUSHER_TICKS: Dictionary = {
	MaterialId.STONE: 20,
	MaterialId.IRON_ORE: 40,
	MaterialId.GOLD_ORE: 80,
}

# Recipe ratio: smelter and forge both consume this many input items per output.
# Iron example: 3 iron ore -> 1 iron ingot (smelter), 3 iron ingots -> 1 iron bar (forge).
const RECIPE_INPUT_PER_OUTPUT: int = 3

# Recipe maps
const SMELT_RECIPE: Dictionary = {
	MaterialId.STONE: MaterialId.BRICK,
	MaterialId.IRON_ORE: MaterialId.IRON_INGOT,
	MaterialId.GOLD_ORE: MaterialId.GOLD_INGOT,
}
const FORGE_RECIPE: Dictionary = {
	MaterialId.BRICK: MaterialId.BLOCK,
	MaterialId.IRON_INGOT: MaterialId.IRON_BAR,
	MaterialId.GOLD_INGOT: MaterialId.GOLD_BAR,
}

# Display names (HUD-facing)
const DISPLAY_NAME: Dictionary = {
	MaterialId.STONE: "Stone", MaterialId.BRICK: "Brick", MaterialId.BLOCK: "Block",
	MaterialId.IRON_ORE: "Iron Ore", MaterialId.IRON_INGOT: "Iron Ingot", MaterialId.IRON_BAR: "Iron Bar",
	MaterialId.GOLD_ORE: "Gold Ore", MaterialId.GOLD_INGOT: "Gold Ingot", MaterialId.GOLD_BAR: "Gold Bar",
}

const TIER_1_MATERIALS: Array[int] = [MaterialId.STONE, MaterialId.IRON_ORE, MaterialId.GOLD_ORE]
const TIER_2_MATERIALS: Array[int] = [MaterialId.BRICK, MaterialId.IRON_INGOT, MaterialId.GOLD_INGOT]
const TIER_3_MATERIALS: Array[int] = [MaterialId.BLOCK, MaterialId.IRON_BAR, MaterialId.GOLD_BAR]

# Returns a copy of `items` (each entry is [material_id, count]) sorted in
# rarity order: tier 1 first, then tier 2, then tier 3, breaking ties by
# material id so stone-line / iron-line / gold-line stay in the same order.
static func sort_items_by_rarity(items: Array) -> Array:
	var out: Array = items.duplicate()
	out.sort_custom(func(a: Array, b: Array) -> bool:
		var ta: int = TIER.get(a[0], 0)
		var tb: int = TIER.get(b[0], 0)
		if ta != tb:
			return ta < tb
		return int(a[0]) < int(b[0])
	)
	return out
