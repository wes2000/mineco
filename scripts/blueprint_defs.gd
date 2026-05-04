class_name BlueprintDefs
extends RefCounted
## Static catalog of blueprint unlocks. Each entry is:
##   id (String)            stable key matched by Unlocks.has(id)
##   name (String)          human-readable name shown in toasts / locked text
##   description (String)   short blurb (used by future UIs; the toast is name-only)
##   category (StringName)  rough bucket so future filtering is easy
##
## Most blueprints don't have a consumer wired yet — they sit here as
## reservations for briefs 09+. The four wired today are:
##   iron_pickaxe_blueprint    -> shop pickaxe_iron
##   deepcore_pickaxe_blueprint -> shop pickaxe_deepcore
##   tuned_scanner_blueprint   -> shop scanner_tuned
##   fast_smelter_blueprint    -> shop scanner_fast_sweep (thematic placeholder)

const CAT_BUILD: StringName = &"build"
const CAT_TOOL: StringName = &"tool"
const CAT_FACTORY: StringName = &"factory"
const CAT_WEAPON: StringName = &"weapon"

const ENTRIES: Array = [
	# --- Early ---
	{
		"id": "storage_crate_blueprint",
		"name": "Storage Crate Blueprint",
		"description": "Build deployable storage crates.",
		"category": CAT_BUILD,
	},
	{
		"id": "workbench_blueprint",
		"name": "Workbench Blueprint",
		"description": "Build a workbench for crafting.",
		"category": CAT_BUILD,
	},
	{
		"id": "tuned_scanner_blueprint",
		"name": "Tuned Scanner Blueprint",
		"description": "Unlocks the Tuned Scanner at the shop.",
		"category": CAT_TOOL,
	},
	{
		"id": "iron_pickaxe_blueprint",
		"name": "Iron Pickaxe Blueprint",
		"description": "Unlocks the Iron Pickaxe at the shop.",
		"category": CAT_TOOL,
	},
	# --- Mid ---
	{
		"id": "fast_smelter_blueprint",
		"name": "Fast Smelter Blueprint",
		"description": "A faster smelter — and unlocks the Fast Sweep Scanner.",
		"category": CAT_FACTORY,
	},
	{
		"id": "advanced_belt_blueprint",
		"name": "Advanced Belt Blueprint",
		"description": "Higher-throughput conveyor belts.",
		"category": CAT_FACTORY,
	},
	{
		"id": "reinforced_wall_blueprint",
		"name": "Reinforced Wall Blueprint",
		"description": "Sturdier base walls.",
		"category": CAT_BUILD,
	},
	{
		"id": "crossbow_blueprint",
		"name": "Crossbow Blueprint",
		"description": "Build crossbow turrets.",
		"category": CAT_WEAPON,
	},
	# --- Late ---
	{
		"id": "crusher_blueprint",
		"name": "Crusher Blueprint",
		"description": "Crushes ore for higher yields.",
		"category": CAT_FACTORY,
	},
	{
		"id": "auto_seller_blueprint",
		"name": "Auto-Seller Blueprint",
		"description": "Automatically sells crated goods.",
		"category": CAT_FACTORY,
	},
	{
		"id": "beacon_blueprint",
		"name": "Beacon Blueprint",
		"description": "Aura tower granting nearby buffs.",
		"category": CAT_BUILD,
	},
	{
		"id": "deepcore_pickaxe_blueprint",
		"name": "Deepcore Pickaxe Blueprint",
		"description": "Unlocks the Deepcore Pickaxe at the shop.",
		"category": CAT_TOOL,
	},
]

static func by_id(blueprint_id: String) -> Dictionary:
	for d: Dictionary in ENTRIES:
		if String(d.id) == blueprint_id:
			return d
	return {}

static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for d: Dictionary in ENTRIES:
		out.append(String(d.id))
	return out

static func name_for(blueprint_id: String) -> String:
	var d: Dictionary = by_id(blueprint_id)
	return String(d.get("name", blueprint_id))
