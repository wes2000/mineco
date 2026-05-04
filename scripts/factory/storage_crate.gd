class_name StorageCrate
extends "res://scripts/factory/structure.gd"
## Per-crate inventory chest. Holds counts of every MaterialDefs.MaterialId.
## UI (StorageCrateUI) drives deposit/withdraw — the crate just exposes the
## storage dict and emits a signal so the UI refreshes live.

const _MD: GDScript = preload("res://scripts/factory/material_defs.gd")
const STACK_CAP: int = 9999   # generous; v1 doesn't need stack management

signal storage_changed

# material_id (int) -> count (int). All 9 ids are pre-populated to 0 so the UI
# can render every row without "is the key there" checks.
var storage: Dictionary = {}

func _ready() -> void:
	kind = &"storage_crate"
	for mid: int in [
		_MD.MaterialId.STONE, _MD.MaterialId.BRICK, _MD.MaterialId.BLOCK,
		_MD.MaterialId.IRON_ORE, _MD.MaterialId.IRON_INGOT, _MD.MaterialId.IRON_BAR,
		_MD.MaterialId.GOLD_ORE, _MD.MaterialId.GOLD_INGOT, _MD.MaterialId.GOLD_BAR,
	]:
		if not storage.has(mid):
			storage[mid] = 0
	super._ready()

func get_count(material_id: int) -> int:
	return int(storage.get(material_id, 0))

# Deposits up to `amount` of material_id. Returns how many actually went in.
func deposit(material_id: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var have: int = int(storage.get(material_id, 0))
	var space: int = max(0, STACK_CAP - have)
	var put: int = min(space, amount)
	if put <= 0:
		return 0
	storage[material_id] = have + put
	storage_changed.emit()
	return put

# Withdraws up to `amount` of material_id. Returns how many actually came out.
func withdraw(material_id: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var have: int = int(storage.get(material_id, 0))
	var take: int = min(have, amount)
	if take <= 0:
		return 0
	storage[material_id] = have - take
	storage_changed.emit()
	return take

func get_save_data() -> Dictionary:
	# Stringify keys so JSON round-trips cleanly, like Loader.hopper does.
	var s: Dictionary = {}
	for k: int in storage.keys():
		s[str(k)] = int(storage[k])
	return {"save_id": save_id, "storage": s}

func apply_save_data(data: Dictionary) -> void:
	super.apply_save_data(data)
	var s: Dictionary = data.get("storage", {})
	for k: Variant in s.keys():
		storage[int(String(k))] = int(s[k])
	storage_changed.emit()
