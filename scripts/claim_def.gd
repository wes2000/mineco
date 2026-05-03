class_name ClaimDef
extends RefCounted
## Static catalog for offshore land claims. Single source of truth for per-tier
## expected ore counts, prices, and xp rewards — read by both OreGenerator
## (when scattering deposits on the claim islands) and ClaimVendorBoard /
## ClaimVendorUI (when displaying and selling claims).
##
## Island geography lives in IslandVoxelGenerator.CLAIM_ISLANDS.

# tier (1..5) → {price, xp_reward, expected_ore: {OreDeposit.OreType → count}}
# Counts are the deposits SCATTERED on the island. Each deposit drops ~5–25
# ore on full mine-out depending on size, so a "stone: 12" island yields very
# roughly 60–300 stone over its lifetime — these are upper-bound estimates.
const TIER_TABLE: Dictionary = {
	1: {
		"price": 500,
		"xp_full": 50,
		"label": "Bronze",
		"deposits": {"stone": 12, "iron": 3,  "gold": 0},
	},
	2: {
		"price": 1500,
		"xp_full": 150,
		"label": "Silver",
		"deposits": {"stone": 18, "iron": 6,  "gold": 1},
	},
	3: {
		"price": 4000,
		"xp_full": 350,
		"label": "Gold",
		"deposits": {"stone": 22, "iron": 10, "gold": 3},
	},
	4: {
		"price": 10000,
		"xp_full": 700,
		"label": "Platinum",
		"deposits": {"stone": 28, "iron": 14, "gold": 6},
	},
	5: {
		"price": 25000,
		"xp_full": 1200,
		"label": "Diamond",
		"deposits": {"stone": 36, "iron": 20, "gold": 12},
	},
}

# How much raw ore (avg) one deposit of each kind drops over its full mine-out.
# Used to translate "this island has N gold deposits" into "≈M gold ore" for
# the player-facing summary.
const APPROX_ORE_PER_DEPOSIT: Dictionary = {
	"stone": 14,
	"iron": 11,
	"gold": 8,
}

static func tier(t: int) -> Dictionary:
	return TIER_TABLE.get(clampi(t, 1, 5), TIER_TABLE[1])

static func approx_ore_yield(t: int) -> Dictionary:
	# Returns {material_id → approximate units}. Rounded.
	var info: Dictionary = tier(t)
	var deps: Dictionary = info.deposits
	return {
		MaterialDefs.MaterialId.STONE:    int(round(float(deps.stone) * APPROX_ORE_PER_DEPOSIT.stone)),
		MaterialDefs.MaterialId.IRON_ORE: int(round(float(deps.iron)  * APPROX_ORE_PER_DEPOSIT.iron)),
		MaterialDefs.MaterialId.GOLD_ORE: int(round(float(deps.gold)  * APPROX_ORE_PER_DEPOSIT.gold)),
	}
