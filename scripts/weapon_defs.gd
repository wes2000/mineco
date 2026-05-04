class_name WeaponDefs
extends RefCounted
## Static catalog for weapons. Each weapon is a Dictionary with:
##   id (String)            stable key, also used to look up the icon and as
##                          the value stored in Miner.equipped_items["weapon"].
##   name (String)          display label
##   type (StringName)      TYPE_MELEE / TYPE_RANGED
##   damage (int)           base damage per hit (scaled by WEAPON_DAMAGE_MULT)
##   range (float)          forward raycast distance, in meters
##   cooldown (float)       seconds between attacks
##   knockback (float)      reserved for v2 — not yet consumed
##   shop_price (int)       gold cost via the item shop
##   requires (Array)       weapon ids that must be owned before this one is sellable
##   icon (String)          path to the shop / hotbar icon
##   description (String)   short blurb for the shop row
##
## Usage in CONSUMERS — preload via const reference rather than relying on
## class_name resolution, since Godot 4.6's parser cache doesn't always
## refresh when a new class_name shows up:
##     const _WeaponDefs: GDScript = preload("res://scripts/weapon_defs.gd")

const TYPE_MELEE: StringName  = &"melee"
const TYPE_RANGED: StringName = &"ranged"

const ITEMS: Array = [
	{
		"id": "rusty_blade", "name": "Rusty Blade",
		"type": TYPE_MELEE,
		"damage": 12, "range": 2.3, "cooldown": 0.55, "knockback": 3.0,
		"shop_price": 400, "requires": [],
		"icon": "res://assets/icons/shop/weapon_rusty_blade.svg",
		"description": "Cheap melee. Short reach, fast swing.",
	},
	{
		"id": "prospector_hammer", "name": "Prospector Hammer",
		"type": TYPE_MELEE,
		"damage": 22, "range": 2.6, "cooldown": 0.95, "knockback": 6.0,
		"shop_price": 1100, "requires": ["rusty_blade"],
		"icon": "res://assets/icons/shop/weapon_prospector_hammer.svg",
		"description": "Slower melee, much higher damage. Requires Rusty Blade.",
	},
	{
		"id": "scrap_crossbow", "name": "Scrap Crossbow",
		"type": TYPE_RANGED,
		"damage": 18, "range": 28.0, "cooldown": 1.10, "knockback": 2.0,
		"shop_price": 1800, "requires": [],
		"icon": "res://assets/icons/shop/weapon_scrap_crossbow.svg",
		"description": "Ranged hitscan. Long cooldown, no ammo (v1).",
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

static func by_id(weapon_id: String) -> Dictionary:
	for d: Dictionary in ITEMS:
		if String(d.id) == weapon_id:
			return d
	return {}

static func by_type(t: StringName) -> Array:
	var out: Array = []
	for d: Dictionary in ITEMS:
		if d.type == t:
			out.append(d)
	return out

# True if every required weapon id is in `owned_ids`.
static func meets_requirements(item: Dictionary, owned_ids: Array) -> bool:
	for req: Variant in item.get("requires", []):
		if not owned_ids.has(String(req)):
			return false
	return true
