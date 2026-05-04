class_name IslandEncounterDefs
extends RefCounted
## Static catalog of per-island encounter metadata: how many enemies spawn,
## the per-enemy stat block (HP / damage / move speed), and the gold bounty
## the player earns when ALL enemies on an island are defeated.
##
## Lookups go through `for_island(id)` which falls back to `default_for_tier`
## if a brand-new island appears in IslandVoxelGenerator.CLAIM_ISLANDS without
## an explicit override here. That keeps adding new islands a one-line change.

# Per-tier defaults — used both for islands not listed in OVERRIDES and as the
# baseline that overrides extend. Tier 1 melee should die to ~3 swings of the
# Rusty Blade (10 damage each → 30 HP target).
const TIER_DEFAULTS: Dictionary = {
	1: {
		"enemy_budget": 3,
		"reward_gold": 100,
		"enemy_stats": {"hp": 30, "damage": 6, "speed": 1.8},
	},
	2: {
		"enemy_budget": 4,
		"reward_gold": 250,
		"enemy_stats": {"hp": 45, "damage": 8, "speed": 2.0},
	},
	3: {
		"enemy_budget": 5,
		"reward_gold": 500,
		"enemy_stats": {"hp": 68, "damage": 10, "speed": 2.2},
	},
	4: {
		"enemy_budget": 6,
		"reward_gold": 900,
		"enemy_stats": {"hp": 100, "damage": 13, "speed": 2.3},
	},
	5: {
		"enemy_budget": 7,
		"reward_gold": 1500,
		"enemy_stats": {"hp": 150, "damage": 17, "speed": 2.5},
	},
}

# Per-island overrides keyed by IslandVoxelGenerator island id. Empty by
# default — every shipped island uses the tier baseline. Listed here so the
# spec is discoverable and per-island flavor (e.g. a mini-boss on Diadem
# Keep) is one edit away.
const OVERRIDES: Dictionary = {
	# Examples / placeholders — uncomment + tweak per island as the design grows:
	# "diadem_keep": {"enemy_budget": 8, "reward_gold": 1800},
}

static func default_for_tier(tier: int) -> Dictionary:
	var t: int = clampi(tier, 1, 5)
	# Deep-ish copy so callers can't mutate the constant table.
	var src: Dictionary = TIER_DEFAULTS[t]
	return {
		"enemy_budget": int(src.enemy_budget),
		"reward_gold": int(src.reward_gold),
		"enemy_stats": {
			"hp": int(src.enemy_stats.hp),
			"damage": int(src.enemy_stats.damage),
			"speed": float(src.enemy_stats.speed),
		},
	}

# Returns the merged encounter dict for the given island id. Looks the
# island up in IslandVoxelGenerator.CLAIM_ISLANDS to read its tier, applies
# any per-id OVERRIDES on top, and returns sensible defaults if the id is
# unknown so callers never crash on a missing entry.
static func for_island(island_id: String) -> Dictionary:
	var tier: int = 1
	for isle: Dictionary in IslandVoxelGenerator.CLAIM_ISLANDS:
		if String(isle.id) == island_id:
			tier = int(isle.tier)
			break
	var out: Dictionary = default_for_tier(tier)
	if OVERRIDES.has(island_id):
		var ov: Dictionary = OVERRIDES[island_id]
		for k in ov.keys():
			if k == "enemy_stats" and ov[k] is Dictionary:
				var stats: Dictionary = (out.enemy_stats as Dictionary).duplicate()
				for sk in (ov[k] as Dictionary).keys():
					stats[sk] = ov[k][sk]
				out["enemy_stats"] = stats
			else:
				out[k] = ov[k]
	return out
