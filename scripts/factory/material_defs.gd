class_name MaterialDefs
extends RefCounted

enum Material {
	STONE, BRICK, BLOCK,
	IRON_ORE, IRON_INGOT, IRON_BAR,
	GOLD_ORE, GOLD_INGOT, GOLD_BAR,
}

# Tier 1 = mined ore, 2 = smelted, 3 = forged
const TIER: Dictionary = {
	Material.STONE: 1, Material.BRICK: 2, Material.BLOCK: 3,
	Material.IRON_ORE: 1, Material.IRON_INGOT: 2, Material.IRON_BAR: 3,
	Material.GOLD_ORE: 1, Material.GOLD_INGOT: 2, Material.GOLD_BAR: 3,
}

# Loader emit interval (ticks). T1 only.
const LOADER_EMIT_TICKS: Dictionary = {
	Material.STONE: 10,
	Material.IRON_ORE: 20,
	Material.GOLD_ORE: 40,
}

# Smelter cycle (ticks). T1 -> T2.
const SMELTER_TICKS: Dictionary = {
	Material.STONE: 20,
	Material.IRON_ORE: 40,
	Material.GOLD_ORE: 80,
}

# Forge cycle (ticks). T2 -> T3.
const FORGE_TICKS: Dictionary = {
	Material.BRICK: 40,
	Material.IRON_INGOT: 80,
	Material.GOLD_INGOT: 160,
}

# Recipe maps
const SMELT_RECIPE: Dictionary = {
	Material.STONE: Material.BRICK,
	Material.IRON_ORE: Material.IRON_INGOT,
	Material.GOLD_ORE: Material.GOLD_INGOT,
}
const FORGE_RECIPE: Dictionary = {
	Material.BRICK: Material.BLOCK,
	Material.IRON_INGOT: Material.IRON_BAR,
	Material.GOLD_INGOT: Material.GOLD_BAR,
}

# Display names (HUD-facing)
const DISPLAY_NAME: Dictionary = {
	Material.STONE: "Stone", Material.BRICK: "Brick", Material.BLOCK: "Block",
	Material.IRON_ORE: "Iron Ore", Material.IRON_INGOT: "Iron Ingot", Material.IRON_BAR: "Iron Bar",
	Material.GOLD_ORE: "Gold Ore", Material.GOLD_INGOT: "Gold Ingot", Material.GOLD_BAR: "Gold Bar",
}

const TIER_1_MATERIALS: Array[int] = [Material.STONE, Material.IRON_ORE, Material.GOLD_ORE]
const TIER_2_MATERIALS: Array[int] = [Material.BRICK, Material.IRON_INGOT, Material.GOLD_INGOT]
const TIER_3_MATERIALS: Array[int] = [Material.BLOCK, Material.IRON_BAR, Material.GOLD_BAR]
