class_name ShopItemDefs
extends RefCounted
## Static catalog for the gold-shop items. Each item is a Dictionary with:
##   id (String)            stable key, also used to namespace its modifier source
##   name (String)          shown in the UI
##   category (StringName)  CAT_PICKAXE / CAT_SCANNER / CAT_UTILITY
##   price (int)            gold cost
##   requires (Array)       list of item ids the player must own first
##   modifiers (Array)      [{stat: String, op: String, value: float}]
##   description (String)   short blurb for the shop row
##
## Pickaxes and scanners are EQUIP-SLOT categories: only one can be active at
## a time, and equipping registers under source &"equip_pickaxe" /
## &"equip_scanner" so the prior item's bonuses come off cleanly.
## Utility items are passive: once owned they're always on, registered under
## &"shop_<id>" and never removed.

const CAT_PICKAXE: StringName = &"pickaxe"
const CAT_SCANNER: StringName = &"scanner"
const CAT_UTILITY: StringName = &"utility"

const EQUIP_CATEGORIES: Array[StringName] = [CAT_PICKAXE, CAT_SCANNER]

const ITEMS: Array = [
	# --- Pickaxes (equip slot) ---
	{
		"id": "pickaxe_copper", "name": "Copper Pickaxe",
		"category": CAT_PICKAXE, "price": 250, "requires": [],
		"modifiers": [{"stat": "mining_damage_mult", "op": "mul", "value": 1.15}],
		"description": "+15% mining damage.",
	},
	{
		"id": "pickaxe_iron", "name": "Iron Pickaxe",
		"category": CAT_PICKAXE, "price": 900, "requires": ["pickaxe_copper"],
		"modifiers": [{"stat": "mining_damage_mult", "op": "mul", "value": 1.35}],
		"description": "+35% mining damage.",
	},
	{
		"id": "pickaxe_gold_tipped", "name": "Gold-Tipped Pickaxe",
		"category": CAT_PICKAXE, "price": 2500, "requires": ["pickaxe_iron"],
		"modifiers": [
			{"stat": "mining_damage_mult", "op": "mul", "value": 1.6},
			{"stat": "stamina_regen_mult", "op": "mul", "value": 1.1},
		],
		"description": "+60% mining damage, +10% stamina regen.",
	},
	{
		"id": "pickaxe_deepcore", "name": "Deepcore Pickaxe",
		"category": CAT_PICKAXE, "price": 8000, "requires": ["pickaxe_gold_tipped"],
		"modifiers": [
			{"stat": "mining_damage_mult", "op": "mul", "value": 2.0},
			{"stat": "dig_radius_mult", "op": "mul", "value": 1.15},
		],
		"description": "+100% mining damage, +15% dig radius.",
	},
	# --- Scanners (equip slot) ---
	{
		"id": "scanner_tuned", "name": "Tuned Scanner",
		"category": CAT_SCANNER, "price": 500, "requires": [],
		"modifiers": [{"stat": "scanner_range_mult", "op": "mul", "value": 1.25}],
		"description": "+25% radar range.",
	},
	{
		"id": "scanner_fast_sweep", "name": "Fast Sweep Scanner",
		"category": CAT_SCANNER, "price": 1200, "requires": ["scanner_tuned"],
		"modifiers": [
			{"stat": "scanner_range_mult", "op": "mul", "value": 1.25},
			{"stat": "scanner_ping_speed_mult", "op": "mul", "value": 1.35},
		],
		"description": "+25% range, +35% ping speed.",
	},
	{
		"id": "scanner_material_lock", "name": "Material Lock Scanner",
		"category": CAT_SCANNER, "price": 3500, "requires": ["scanner_fast_sweep"],
		"modifiers": [
			{"stat": "scanner_range_mult", "op": "mul", "value": 1.5},
			{"stat": "scanner_ping_speed_mult", "op": "mul", "value": 1.5},
		],
		"description": "+50% range, +50% ping speed.",
	},
	# --- Utility (passive once owned) ---
	{
		"id": "boots_work", "name": "Work Boots",
		"category": CAT_UTILITY, "price": 700, "requires": [],
		"modifiers": [{"stat": "sprint_speed_mult", "op": "mul", "value": 1.08}],
		"description": "+8% sprint speed.",
	},
	{
		"id": "survey_pack", "name": "Survey Pack",
		"category": CAT_UTILITY, "price": 1000, "requires": [],
		"modifiers": [{"stat": "pickup_radius_bonus", "op": "add", "value": 2.0}],
		"description": "+2m pickup radius.",
	},
	{
		"id": "boat_rudder_kit", "name": "Boat Rudder Kit",
		"category": CAT_UTILITY, "price": 1500, "requires": [],
		"modifiers": [{"stat": "boat_speed_mult", "op": "mul", "value": 1.2}],
		"description": "+20% boat top speed.",
	},
]

static func by_id(item_id: String) -> Dictionary:
	for d: Dictionary in ITEMS:
		if String(d.id) == item_id:
			return d
	return {}

static func by_category(cat: StringName) -> Array:
	var out: Array = []
	for d: Dictionary in ITEMS:
		if d.category == cat:
			out.append(d)
	return out

static func is_equip_category(cat: StringName) -> bool:
	return EQUIP_CATEGORIES.has(cat)

static func category_name(cat: StringName) -> String:
	if cat == CAT_PICKAXE: return "Pickaxes"
	if cat == CAT_SCANNER: return "Scanners"
	if cat == CAT_UTILITY: return "Utility"
	return String(cat)

# True if the item's prerequisites are all satisfied by `owned_ids`.
static func meets_requirements(item: Dictionary, owned_ids: Array) -> bool:
	for req: Variant in item.get("requires", []):
		if not owned_ids.has(String(req)):
			return false
	return true
