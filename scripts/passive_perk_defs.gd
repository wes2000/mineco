class_name PassivePerkDefs
extends RefCounted
## Static catalog for the passive-tree perks. Each perk is a Dictionary with:
##   id (String)                stable key, used to namespace its modifier source
##   name (String)              display label
##   branch (StringName)        BR_MINING / BR_EXPLORATION / BR_AUTOMATION /
##                              BR_COMBAT / BR_ECONOMY / BR_CONSTRUCTION
##   cost (int)                 gold cost per rank (each rank costs the same)
##   requires (Array)           list of perk ids that need at least 1 rank
##   max_rank (int)             how many ranks the perk can reach
##   modifiers_per_rank (Array) list of {stat, op, value} dicts. Applied once
##                              per owned rank, so rank 2 stacks the same
##                              modifier twice (e.g. 1.10 * 1.10 = 1.21).
##   description (String)       short blurb shown under the name
##
## Usage in CONSUMERS — preload via const reference rather than relying on
## class_name resolution, since Godot 4.6's parser cache doesn't always
## refresh when a new class_name shows up:
##     const _PerkDefs: GDScript = preload("res://scripts/passive_perk_defs.gd")

const BR_MINING: StringName       = &"mining"
const BR_EXPLORATION: StringName  = &"exploration"
const BR_AUTOMATION: StringName   = &"automation"
const BR_COMBAT: StringName       = &"combat"
const BR_ECONOMY: StringName      = &"economy"
const BR_CONSTRUCTION: StringName = &"construction"

const BRANCH_ORDER: Array[StringName] = [
	BR_MINING, BR_EXPLORATION, BR_AUTOMATION,
	BR_COMBAT, BR_ECONOMY, BR_CONSTRUCTION,
]

const ITEMS: Array = [
	# --- Mining --------------------------------------------------------------
	{
		"id": "mining_damage_1", "name": "Sharper Edge", "branch": BR_MINING,
		"cost": 250, "requires": [], "max_rank": 3,
		"modifiers_per_rank": [{"stat": "mining_damage_mult", "op": "mul", "value": 1.10}],
		"description": "+10% mining damage per rank.",
	},
	{
		"id": "mining_radius_1", "name": "Wider Bite", "branch": BR_MINING,
		"cost": 350, "requires": [], "max_rank": 2,
		"modifiers_per_rank": [{"stat": "dig_radius_mult", "op": "mul", "value": 1.10}],
		"description": "+10% dig radius per rank.",
	},
	{
		"id": "mining_efficient_1", "name": "Efficient Swing", "branch": BR_MINING,
		"cost": 400, "requires": [], "max_rank": 2,
		"modifiers_per_rank": [{"stat": "stamina_regen_mult", "op": "mul", "value": 1.10}],
		"description": "+10% stamina regen per rank.",
	},
	{
		"id": "mining_damage_2", "name": "Hardened Edge", "branch": BR_MINING,
		"cost": 1500, "requires": ["mining_damage_1"], "max_rank": 2,
		"modifiers_per_rank": [{"stat": "mining_damage_mult", "op": "mul", "value": 1.20}],
		"description": "+20% mining damage per rank.",
	},
	{
		"id": "mining_swing_speed_1", "name": "Fast Hands", "branch": BR_MINING,
		"cost": 5000, "requires": ["mining_damage_1"], "max_rank": 2,
		"modifiers_per_rank": [{"stat": "mining_swing_speed_mult", "op": "mul", "value": 1.15}],
		"description": "+15% swing speed per rank.",
	},

	# --- Exploration --------------------------------------------------------
	{
		"id": "explore_range_1", "name": "Longer Sweep", "branch": BR_EXPLORATION,
		"cost": 300, "requires": [], "max_rank": 3,
		"modifiers_per_rank": [{"stat": "scanner_range_mult", "op": "mul", "value": 1.20}],
		"description": "+20% scanner range per rank.",
	},
	{
		"id": "explore_speed_1", "name": "Fast Radar", "branch": BR_EXPLORATION,
		"cost": 450, "requires": [], "max_rank": 2,
		"modifiers_per_rank": [{"stat": "scanner_ping_speed_mult", "op": "mul", "value": 1.15}],
		"description": "+15% scanner sweep speed per rank.",
	},
	{
		"id": "explore_boat_1", "name": "Boat Handling", "branch": BR_EXPLORATION,
		"cost": 800, "requires": [], "max_rank": 2,
		"modifiers_per_rank": [{"stat": "boat_speed_mult", "op": "mul", "value": 1.15}],
		"description": "+15% boat speed per rank.",
	},
	{
		"id": "explore_pickup_1", "name": "Magnet Belt", "branch": BR_EXPLORATION,
		"cost": 600, "requires": [], "max_rank": 2,
		"modifiers_per_rank": [{"stat": "pickup_radius_bonus", "op": "add", "value": 1.0}],
		"description": "+1m pickup radius per rank.",
	},

	# --- Automation ---------------------------------------------------------
	{
		"id": "auto_factory_1", "name": "Warm Machines", "branch": BR_AUTOMATION,
		"cost": 500, "requires": [], "max_rank": 3,
		"modifiers_per_rank": [{"stat": "factory_speed_mult", "op": "mul", "value": 1.10}],
		"description": "+10% factory speed per rank.",
	},
	{
		"id": "auto_factory_2", "name": "Tuned Pipelines", "branch": BR_AUTOMATION,
		"cost": 2000, "requires": ["auto_factory_1"], "max_rank": 2,
		"modifiers_per_rank": [{"stat": "factory_speed_mult", "op": "mul", "value": 1.15}],
		"description": "+15% factory speed per rank.",
	},

	# --- Combat (stats are wired but not yet consumed in v1) ----------------
	{
		"id": "combat_health_1", "name": "Tough Skin", "branch": BR_COMBAT,
		"cost": 400, "requires": [], "max_rank": 3,
		"modifiers_per_rank": [{"stat": "health_max_bonus", "op": "add", "value": 10.0}],
		"description": "+10 max health per rank. (Combat ships later — inert for now.)",
	},
	{
		"id": "combat_damage_1", "name": "Heavy Hit", "branch": BR_COMBAT,
		"cost": 500, "requires": [], "max_rank": 3,
		"modifiers_per_rank": [{"stat": "weapon_damage_mult", "op": "mul", "value": 1.15}],
		"description": "+15% weapon damage per rank. (Combat ships later — inert for now.)",
	},

	# --- Economy ------------------------------------------------------------
	{
		"id": "econ_sell_1", "name": "Better Deals", "branch": BR_ECONOMY,
		"cost": 350, "requires": [], "max_rank": 3,
		"modifiers_per_rank": [{"stat": "sell_value_mult", "op": "mul", "value": 1.05}],
		"description": "+5% sell value per rank.",
	},
	{
		"id": "econ_contract_1", "name": "Contract Negotiator", "branch": BR_ECONOMY,
		"cost": 500, "requires": [], "max_rank": 3,
		"modifiers_per_rank": [{"stat": "contract_reward_mult", "op": "mul", "value": 1.10}],
		"description": "+10% contract reward per rank.",
	},

	# --- Construction (stat wired but no consumer in v1) --------------------
	{
		"id": "build_cheap_1", "name": "Cheaper Builds", "branch": BR_CONSTRUCTION,
		"cost": 300, "requires": [], "max_rank": 3,
		"modifiers_per_rank": [{"stat": "build_cost_mult", "op": "mul", "value": 0.95}],
		"description": "-5% build cost per rank. (Cost consumer ships later — inert for now.)",
	},
]

static func by_id(perk_id: String) -> Dictionary:
	for d: Dictionary in ITEMS:
		if String(d.id) == perk_id:
			return d
	return {}

static func by_branch(branch: StringName) -> Array:
	var out: Array = []
	for d: Dictionary in ITEMS:
		if StringName(String(d.branch)) == branch:
			out.append(d)
	return out

static func branch_name(branch: StringName) -> String:
	match branch:
		BR_MINING: return "Mining"
		BR_EXPLORATION: return "Exploration"
		BR_AUTOMATION: return "Automation"
		BR_COMBAT: return "Combat"
		BR_ECONOMY: return "Economy"
		BR_CONSTRUCTION: return "Construction"
	return String(branch).capitalize()

static func branch_color(branch: StringName) -> Color:
	match branch:
		BR_MINING: return Color(0.95, 0.65, 0.40, 1)
		BR_EXPLORATION: return Color(0.55, 0.85, 0.95, 1)
		BR_AUTOMATION: return Color(0.85, 0.85, 0.55, 1)
		BR_COMBAT: return Color(0.95, 0.45, 0.45, 1)
		BR_ECONOMY: return Color(0.65, 0.95, 0.65, 1)
		BR_CONSTRUCTION: return Color(0.85, 0.65, 0.95, 1)
	return Color.WHITE

# True if every prerequisite has at least one rank in `owned_ranks`
# (perk_id -> int).
static func meets_requirements(perk: Dictionary, owned_ranks: Dictionary) -> bool:
	for req: Variant in perk.get("requires", []):
		if int(owned_ranks.get(String(req), 0)) <= 0:
			return false
	return true
