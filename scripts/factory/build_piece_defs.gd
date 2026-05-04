class_name BuildPieceDefs
extends RefCounted
## Static catalog of every player-placeable piece in build mode. Used by
## BuildController, FactoryWorld and the bottom HUD to look up display names,
## scenes, footprints, and material costs without scattering data across files.
##
## Each entry:
##   id                 StringName  — same key used by FactoryWorld.KIND_TO_SCENE
##   name               String      — HUD / catalog label
##   category           StringName  — &"factory" / &"structure" / &"utility"
##   scene              String      — res:// path (or "" for the BELT pseudo-tool)
##   icon               String      — res:// icon path (may be "")
##   footprint          Vector2i    — cells in (X, Z); (0, 0) for belt
##   cost               Dictionary  — { MaterialDefs.MaterialId : int }
##   refund_pct         float       — fraction of cost returned on `remove`
##   description        String      — single-line tooltip
##   requires_blueprint String      — Unlocks id; empty = always available
##
## Costs honor PlayerStats.BUILD_COST_MULT — see `effective_cost`.

const _MD: GDScript = preload("res://scripts/factory/material_defs.gd")

const CAT_FACTORY: StringName = &"factory"
const CAT_STRUCTURE: StringName = &"structure"
const CAT_UTILITY: StringName = &"utility"

# Pseudo-id for the belt placement tool (it has no scene; build_controller
# special-cases it). Kept here so the catalog UI can list it in Factory.
const KIND_BELT: StringName = &"belt"

const PIECES: Array = [
	# --- Factory ----------------------------------------------------------
	{
		"id": &"loader",
		"name": "Loader",
		"category": CAT_FACTORY,
		"scene": "res://scenes/factory/loader.tscn",
		"icon": "res://assets/icons/hotbar/build_loader.svg",
		"footprint": Vector2i(2, 2),
		"cost": {},
		"refund_pct": 0.5,
		"description": "Feeds materials onto belts.",
	},
	{
		"id": &"smelter",
		"name": "Smelter",
		"category": CAT_FACTORY,
		"scene": "res://scenes/factory/smelter.tscn",
		"icon": "res://assets/icons/hotbar/build_smelter.svg",
		"footprint": Vector2i(2, 2),
		"cost": {},
		"refund_pct": 0.5,
		"description": "Smelts T1 ore into T2 ingots.",
	},
	{
		"id": &"forge",
		"name": "Forge",
		"category": CAT_FACTORY,
		"scene": "res://scenes/factory/forge.tscn",
		"icon": "res://assets/icons/hotbar/build_forge.svg",
		"footprint": Vector2i(3, 3),
		"cost": {},
		"refund_pct": 0.5,
		"description": "Forges T2 ingots into T3 bars.",
	},
	{
		"id": KIND_BELT,
		"name": "Belt",
		"category": CAT_FACTORY,
		"scene": "",
		"icon": "res://assets/icons/hotbar/build_belt.svg",
		"footprint": Vector2i(0, 0),
		"cost": {},
		"refund_pct": 0.0,
		"description": "Connects machine output to input.",
	},
	{
		"id": &"merger",
		"name": "Merger",
		"category": CAT_FACTORY,
		"scene": "res://scenes/factory/merger.tscn",
		"icon": "res://assets/icons/hotbar/build_merger.svg",
		"footprint": Vector2i(1, 1),
		"cost": {},
		"refund_pct": 0.5,
		"description": "Combines three input belts into one.",
	},
	{
		"id": &"crusher",
		"name": "Crusher",
		"category": CAT_FACTORY,
		"scene": "res://scenes/factory/crusher.tscn",
		"icon": "res://assets/icons/hotbar/build_smelter.svg",
		"footprint": Vector2i(2, 2),
		"cost": {_MD.MaterialId.IRON_INGOT: 4, _MD.MaterialId.STONE: 6},
		"refund_pct": 0.5,
		"description": "Cycles ore back out with a chance for a bonus unit.",
		"requires_blueprint": "crusher_blueprint",
	},
	{
		"id": &"splitter",
		"name": "Splitter",
		"category": CAT_FACTORY,
		"scene": "res://scenes/factory/splitter.tscn",
		"icon": "res://assets/icons/hotbar/build_splitter.svg",
		"footprint": Vector2i(1, 1),
		"cost": {},
		"refund_pct": 0.5,
		"description": "Splits one input belt across three outputs.",
	},
	# --- Structure --------------------------------------------------------
	{
		"id": &"foundation",
		"name": "Foundation",
		"category": CAT_STRUCTURE,
		"scene": "res://scenes/factory/structures/foundation.tscn",
		"icon": "",
		"footprint": Vector2i(1, 1),
		"cost": {_MD.MaterialId.STONE: 6},
		"refund_pct": 0.5,
		"description": "Flat 1x1 platform. Auto-flattens terrain.",
	},
	{
		"id": &"wall",
		"name": "Wall",
		"category": CAT_STRUCTURE,
		"scene": "res://scenes/factory/structures/wall.tscn",
		"icon": "",
		"footprint": Vector2i(1, 1),
		"cost": {_MD.MaterialId.BRICK: 4},
		"refund_pct": 0.5,
		"description": "Simple wall. Visual + collision.",
	},
	{
		"id": &"roof",
		"name": "Roof",
		"category": CAT_STRUCTURE,
		"scene": "res://scenes/factory/structures/roof.tscn",
		"icon": "",
		"footprint": Vector2i(1, 1),
		"cost": {_MD.MaterialId.BRICK: 3, _MD.MaterialId.IRON_BAR: 1},
		"refund_pct": 0.5,
		"description": "Roof piece for covered structures.",
	},
	{
		"id": &"door",
		"name": "Door",
		"category": CAT_STRUCTURE,
		"scene": "res://scenes/factory/structures/door.tscn",
		"icon": "",
		"footprint": Vector2i(1, 1),
		"cost": {_MD.MaterialId.IRON_INGOT: 2, _MD.MaterialId.IRON_BAR: 1},
		"refund_pct": 0.5,
		"description": "Decorative door (no swing yet).",
	},
	{
		"id": &"window",
		"name": "Window",
		"category": CAT_STRUCTURE,
		"scene": "res://scenes/factory/structures/window.tscn",
		"icon": "",
		"footprint": Vector2i(1, 1),
		"cost": {_MD.MaterialId.BRICK: 2, _MD.MaterialId.IRON_INGOT: 1},
		"refund_pct": 0.5,
		"description": "Window pane in a wall.",
	},
	# --- Utility ----------------------------------------------------------
	{
		"id": &"storage_crate",
		"name": "Storage Crate",
		"category": CAT_UTILITY,
		"scene": "res://scenes/factory/structures/storage_crate.tscn",
		"icon": "",
		"footprint": Vector2i(1, 1),
		"cost": {_MD.MaterialId.STONE: 5, _MD.MaterialId.IRON_ORE: 3},
		"refund_pct": 0.5,
		"description": "Holds materials. E to deposit/withdraw.",
	},
	{
		"id": &"workbench",
		"name": "Workbench",
		"category": CAT_UTILITY,
		"scene": "res://scenes/factory/structures/workbench.tscn",
		"icon": "",
		"footprint": Vector2i(1, 1),
		"cost": {_MD.MaterialId.IRON_INGOT: 3, _MD.MaterialId.BLOCK: 2},
		"refund_pct": 0.5,
		"description": "Crafting station. (Coming soon.)",
	},
	{
		"id": &"lamp",
		"name": "Lamp",
		"category": CAT_UTILITY,
		"scene": "res://scenes/factory/structures/lamp.tscn",
		"icon": "",
		"footprint": Vector2i(1, 1),
		"cost": {_MD.MaterialId.IRON_BAR: 1, _MD.MaterialId.GOLD_INGOT: 1},
		"refund_pct": 0.5,
		"description": "Soft area light.",
	},
	{
		"id": &"beacon",
		"name": "Beacon",
		"category": CAT_UTILITY,
		"scene": "res://scenes/factory/structures/beacon.tscn",
		"icon": "",
		"footprint": Vector2i(1, 1),
		"cost": {_MD.MaterialId.GOLD_BAR: 1, _MD.MaterialId.IRON_BAR: 2},
		"refund_pct": 0.5,
		"description": "Tall light pillar visible from afar.",
	},
]

static func all() -> Array:
	return PIECES

static func by_id(piece_id: StringName) -> Dictionary:
	for entry: Dictionary in PIECES:
		if entry.id == piece_id:
			return entry
	return {}

static func by_category(cat: StringName) -> Array:
	var out: Array = []
	for entry: Dictionary in PIECES:
		if entry.category == cat:
			out.append(entry)
	return out

# Returns true if the piece is gated behind a blueprint that the player
# hasn't unlocked yet. Pieces with no requires_blueprint always return false.
static func is_locked(entry: Dictionary) -> bool:
	var bp: String = String(entry.get("requires_blueprint", ""))
	if bp == "":
		return false
	var unlocks: Node = Engine.get_main_loop().root.get_node_or_null("/root/Unlocks") as Node
	if unlocks == null:
		return true
	return not bool(unlocks.call("has", bp))

# Returns the cost dict scaled by PlayerStats.BUILD_COST_MULT, with each entry
# rounded up to at least 1 if the original was > 0. Caller passes the raw cost
# from the def; we never mutate it.
static func effective_cost(raw: Dictionary) -> Dictionary:
	var stats: Node = Engine.get_main_loop().root.get_node_or_null("/root/PlayerStats") as Node
	var mul: float = 1.0
	if stats != null and stats.has_method("get_stat"):
		mul = max(0.05, float(stats.call("get_stat", &"build_cost_mult")))
	var out: Dictionary = {}
	for k: Variant in raw.keys():
		var raw_n: int = int(raw[k])
		if raw_n <= 0:
			continue
		out[int(k)] = max(1, int(ceil(float(raw_n) * mul)))
	return out

static func can_afford(miner: Node, raw_cost: Dictionary) -> bool:
	if miner == null:
		return false
	var eff: Dictionary = effective_cost(raw_cost)
	for mid: Variant in eff.keys():
		if miner.call("get_material_count", int(mid)) < int(eff[mid]):
			return false
	return true

static func charge(miner: Node, raw_cost: Dictionary) -> bool:
	if not can_afford(miner, raw_cost):
		return false
	var eff: Dictionary = effective_cost(raw_cost)
	for mid: Variant in eff.keys():
		miner.call("remove_material", int(mid), int(eff[mid]))
	return true

static func refund(miner: Node, raw_cost: Dictionary, refund_pct: float) -> void:
	if miner == null or refund_pct <= 0.0:
		return
	# Refund is computed off the EFFECTIVE cost (what was charged), so a
	# build-cost reduction perk doesn't unbalance refunds.
	var eff: Dictionary = effective_cost(raw_cost)
	for mid: Variant in eff.keys():
		var qty: int = int(floor(float(int(eff[mid])) * refund_pct))
		if qty > 0:
			miner.call("add_factory_material", int(mid), qty)
