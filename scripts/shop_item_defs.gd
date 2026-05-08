class_name ShopItemDefs
extends RefCounted
## Static catalog for the gold-shop items. Each item is a Dictionary with:
##   id (String)              stable key, also used to namespace its modifier source
##   name (String)            shown in the UI
##   category (StringName)    CAT_PICKAXE / CAT_SCANNER / CAT_UTILITY
##   price (int)              gold cost
##   requires (Array)         list of item ids the player must own first
##   requires_blueprint (String, optional)
##                            blueprint id that must be unlocked before purchase.
##                            Empty / missing means unconditional.
##   modifiers (Array)        [{stat: String, op: String, value: float}]
##   description (String)     short blurb for the shop row
##
## Pickaxes and scanners are EQUIP-SLOT categories: only one can be active at
## a time, and equipping registers under source &"equip_pickaxe" /
## &"equip_scanner" so the prior item's bonuses come off cleanly.
## Utility items are passive: once owned they're always on, registered under
## &"shop_<id>" and never removed.

const CAT_PICKAXE: StringName = &"pickaxe"
const CAT_SCANNER: StringName = &"scanner"
const CAT_UTILITY: StringName = &"utility"
const CAT_WEAPON: StringName = &"weapon"
const CAT_CROSSHAIR: StringName = &"crosshair"          # shape only
const CAT_CROSSHAIR_COLOR: StringName = &"crosshair_color"  # tint only

# Weapon items are equip-slot too — only one weapon equipped at a time. Their
# `modifiers` arrays stay empty: the Weapon node reads its def from
# WeaponDefs by id instead of going through the PlayerStats mod system.
# Crosshair shape + color are independent equip slots so the player can mix
# any color with any shape; CrosshairHUD reads both.
const EQUIP_CATEGORIES: Array[StringName] = [CAT_PICKAXE, CAT_SCANNER, CAT_WEAPON, CAT_CROSSHAIR, CAT_CROSSHAIR_COLOR]

# Defaults — must exist in ITEMS below. Both are free + auto-granted on
# first spawn (Miner.apply_owned_modifiers) so the player always has a
# functioning crosshair.
const DEFAULT_CROSSHAIR: String = "crosshair_dot_white"
const DEFAULT_CROSSHAIR_COLOR: String = "crosshair_color_white"

const ITEMS: Array = [
	# --- Pickaxes (equip slot) ---
	{
		"id": "pickaxe_copper", "name": "Copper Pickaxe",
		"category": CAT_PICKAXE, "price": 250, "requires": [],
		"icon": "res://assets/icons/shop/pickaxe_copper.svg",
		"modifiers": [{"stat": "mining_damage_mult", "op": "mul", "value": 1.15}],
		"description": "+15% mining damage.",
	},
	{
		"id": "pickaxe_iron", "name": "Iron Pickaxe",
		"category": CAT_PICKAXE, "price": 900, "requires": ["pickaxe_copper"],
		"requires_blueprint": "iron_pickaxe_blueprint",
		"icon": "res://assets/icons/shop/pickaxe_iron.svg",
		"modifiers": [{"stat": "mining_damage_mult", "op": "mul", "value": 1.35}],
		"description": "+35% mining damage.",
	},
	{
		"id": "pickaxe_gold_tipped", "name": "Gold-Tipped Pickaxe",
		"category": CAT_PICKAXE, "price": 2500, "requires": ["pickaxe_iron"],
		"icon": "res://assets/icons/shop/pickaxe_gold_tipped.svg",
		"modifiers": [
			{"stat": "mining_damage_mult", "op": "mul", "value": 1.6},
			{"stat": "stamina_regen_mult", "op": "mul", "value": 1.1},
		],
		"description": "+60% mining damage, +10% stamina regen.",
	},
	{
		"id": "pickaxe_deepcore", "name": "Deepcore Pickaxe",
		"category": CAT_PICKAXE, "price": 8000, "requires": ["pickaxe_gold_tipped"],
		"requires_blueprint": "deepcore_pickaxe_blueprint",
		"requires_rank": 4,
		"icon": "res://assets/icons/shop/pickaxe_deepcore.svg",
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
		"requires_blueprint": "tuned_scanner_blueprint",
		"icon": "res://assets/icons/shop/scanner_tuned.svg",
		"modifiers": [{"stat": "scanner_range_mult", "op": "mul", "value": 1.25}],
		"description": "+25% radar range.",
	},
	{
		"id": "scanner_fast_sweep", "name": "Fast Sweep Scanner",
		"category": CAT_SCANNER, "price": 1200, "requires": ["scanner_tuned"],
		"requires_blueprint": "fast_smelter_blueprint",
		"icon": "res://assets/icons/shop/scanner_fast_sweep.svg",
		"modifiers": [
			{"stat": "scanner_range_mult", "op": "mul", "value": 1.25},
			{"stat": "scanner_ping_speed_mult", "op": "mul", "value": 1.35},
		],
		"description": "+25% range, +35% ping speed.",
	},
	{
		"id": "scanner_material_lock", "name": "Material Lock Scanner",
		"category": CAT_SCANNER, "price": 3500, "requires": ["scanner_fast_sweep"],
		"requires_rank": 3,
		"icon": "res://assets/icons/shop/scanner_material_lock.svg",
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
		"icon": "res://assets/icons/shop/boots_work.svg",
		"modifiers": [{"stat": "sprint_speed_mult", "op": "mul", "value": 1.08}],
		"description": "+8% sprint speed.",
	},
	{
		"id": "survey_pack", "name": "Survey Pack",
		"category": CAT_UTILITY, "price": 1000, "requires": [],
		"icon": "res://assets/icons/shop/survey_pack.svg",
		"modifiers": [{"stat": "pickup_radius_bonus", "op": "add", "value": 2.0}],
		"description": "+2m pickup radius.",
	},
	{
		"id": "boat_rudder_kit", "name": "Boat Rudder Kit",
		"category": CAT_UTILITY, "price": 1500, "requires": [],
		"icon": "res://assets/icons/shop/boat_rudder_kit.svg",
		"modifiers": [{"stat": "boat_speed_mult", "op": "mul", "value": 1.2}],
		"description": "+20% boat top speed.",
	},
	# --- Weapons (equip slot) ---
	# These mirror WeaponDefs by id. No `modifiers` — combat damage is read
	# directly from the WeaponDefs entry by the Weapon node, not the stat
	# system. The shop's equip flow stores the chosen id in
	# Miner.equipped_items["weapon"]; the player reads that on swing.
	{
		"id": "rusty_blade", "name": "Rusty Blade",
		"category": CAT_WEAPON, "price": 400, "requires": [],
		"icon": "res://assets/icons/shop/weapon_rusty_blade.svg",
		"modifiers": [],
		"description": "Cheap melee. Short reach, fast swing.",
	},
	{
		"id": "prospector_hammer", "name": "Prospector Hammer",
		"category": CAT_WEAPON, "price": 1100, "requires": ["rusty_blade"],
		"icon": "res://assets/icons/shop/weapon_prospector_hammer.svg",
		"modifiers": [],
		"description": "Slower melee, much higher damage.",
	},
	{
		"id": "scrap_crossbow", "name": "Scrap Crossbow",
		"category": CAT_WEAPON, "price": 1800, "requires": [],
		"icon": "res://assets/icons/shop/weapon_scrap_crossbow.svg",
		"modifiers": [],
		"description": "Ranged hitscan. Long cooldown.",
	},
	# --- Crosshair shapes (CAT_CROSSHAIR) ---
	# Pure shape entries; tint comes from the separately-equipped color slot.
	# Each entry carries `crosshair_style`. The `_white` suffix in the id is
	# legacy (saves predate the color split) and just means "no built-in tint".
	{
		"id": "crosshair_dot_white", "name": "Dot",
		"category": CAT_CROSSHAIR, "price": 0, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Default. A simple center dot.",
		"crosshair_style": "dot",
	},
	{
		"id": "crosshair_x_white", "name": "Cross",
		"category": CAT_CROSSHAIR, "price": 200, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Two diagonal lines in an X.",
		"crosshair_style": "x",
	},
	{
		"id": "crosshair_t_white", "name": "Tee",
		"category": CAT_CROSSHAIR, "price": 200, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Inverted T crosshair.",
		"crosshair_style": "t",
	},
	{
		"id": "crosshair_o_white", "name": "Ring",
		"category": CAT_CROSSHAIR, "price": 200, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Open circle.",
		"crosshair_style": "o",
	},
	{
		"id": "crosshair_o_dot_white", "name": "Ring + Dot",
		"category": CAT_CROSSHAIR, "price": 250, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Open circle with a center dot.",
		"crosshair_style": "o_dot",
	},
	{
		"id": "crosshair_smiley", "name": "Smiley",
		"category": CAT_CROSSHAIR, "price": 350, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Why so serious. :)",
		"crosshair_style": "smiley",
	},
	{
		"id": "crosshair_plus", "name": "Plus",
		"category": CAT_CROSSHAIR, "price": 250, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Thicker axis-aligned cross.",
		"crosshair_style": "plus",
	},
	{
		"id": "crosshair_heart", "name": "Heart",
		"category": CAT_CROSSHAIR, "price": 300, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Aim with love.",
		"crosshair_style": "heart",
	},
	{
		"id": "crosshair_snowman", "name": "Snowman",
		"category": CAT_CROSSHAIR, "price": 300, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Three stacked circles. Cold-blooded aim.",
		"crosshair_style": "snowman",
	},
	{
		"id": "crosshair_diamond", "name": "Diamond",
		"category": CAT_CROSSHAIR, "price": 250, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Open diamond outline.",
		"crosshair_style": "diamond",
	},
	{
		"id": "crosshair_pulse", "name": "Pulse",
		"category": CAT_CROSSHAIR, "price": 1000, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Animated dot — breathes in and out. Premium tier.",
		"crosshair_style": "pulse",
	},
	# --- Crosshair colors (CAT_CROSSHAIR_COLOR) ---
	# Independent tint slot — any color combines with any shape above.
	{
		"id": "crosshair_color_white", "name": "White",
		"category": CAT_CROSSHAIR_COLOR, "price": 0, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Default. Reads on most surfaces.",
		"crosshair_color": Color(1, 1, 1, 1),
	},
	{
		"id": "crosshair_color_red", "name": "Red",
		"category": CAT_CROSSHAIR_COLOR, "price": 100, "requires": [],
		"icon": "", "modifiers": [],
		"description": "High-contrast red.",
		"crosshair_color": Color(0.95, 0.25, 0.25, 1),
	},
	{
		"id": "crosshair_color_green", "name": "Green",
		"category": CAT_CROSSHAIR_COLOR, "price": 100, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Phosphor green.",
		"crosshair_color": Color(0.35, 0.95, 0.4, 1),
	},
	{
		"id": "crosshair_color_yellow", "name": "Yellow",
		"category": CAT_CROSSHAIR_COLOR, "price": 100, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Highlighter yellow.",
		"crosshair_color": Color(1.0, 0.9, 0.3, 1),
	},
	{
		"id": "crosshair_color_cyan", "name": "Cyan",
		"category": CAT_CROSSHAIR_COLOR, "price": 100, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Cool ocean cyan.",
		"crosshair_color": Color(0.40, 0.85, 0.95, 1),
	},
	{
		"id": "crosshair_color_pink", "name": "Pink",
		"category": CAT_CROSSHAIR_COLOR, "price": 100, "requires": [],
		"icon": "", "modifiers": [],
		"description": "Hot pink.",
		"crosshair_color": Color(1.0, 0.45, 0.75, 1),
	},
]

static var _icon_cache: Dictionary = {}

static func icon_for(item: Dictionary) -> Texture2D:
	var path: String = String(item.get("icon", ""))
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = load(path) as Texture2D
	_icon_cache[path] = tex
	return tex

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
	if cat == CAT_WEAPON: return "Weapons"
	if cat == CAT_CROSSHAIR: return "Crosshairs"
	if cat == CAT_CROSSHAIR_COLOR: return "Colors"
	return String(cat)

# True if the item's prerequisites are all satisfied by `owned_ids` AND the
# blueprint gate (if any) is unlocked. The blueprint check goes through the
# Unlocks autoload so a fresh-launched scene without it (e.g. unit tests)
# still treats absence as "unlocked" rather than crashing.
static func meets_requirements(item: Dictionary, owned_ids: Array) -> bool:
	for req: Variant in item.get("requires", []):
		if not owned_ids.has(String(req)):
			return false
	var bp: String = String(item.get("requires_blueprint", ""))
	if bp != "":
		var loop: SceneTree = Engine.get_main_loop() as SceneTree
		if loop != null:
			var unlocks: Node = loop.root.get_node_or_null("Unlocks")
			if unlocks != null and not bool(unlocks.call("has", bp)):
				return false
	# Optional Mine Co. rank gate. Treated like a soft prerequisite — items
	# without the field load fine on saves predating brief 10.
	var req_rank: int = int(item.get("requires_rank", 0))
	if req_rank > 0:
		var loop2: SceneTree = Engine.get_main_loop() as SceneTree
		if loop2 != null:
			var company: Node = loop2.root.get_node_or_null("CompanyProgress")
			if company != null and int(company.get("rank")) < req_rank:
				return false
	return true

# Convenience: blueprint id this item requires, or "" if none.
static func required_blueprint(item: Dictionary) -> String:
	return String(item.get("requires_blueprint", ""))

# Convenience: rank required for this item, or 0 if none.
static func required_rank(item: Dictionary) -> int:
	return int(item.get("requires_rank", 0))
