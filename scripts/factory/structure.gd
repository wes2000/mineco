class_name Structure
extends Building
## Base for structural / utility pieces (foundations, walls, roofs, doors,
## windows, lamps, beacons). They register footprints and persist via
## SaveGame, but don't run a tick or carry queues. The exported `kind` lets
## FactoryWorld map an instance back to its catalog id without is-a checks.

@export var kind: StringName = &""

func _ready() -> void:
	# Skip Building._ready's bob/audio wiring — these pieces are inert. We
	# still want to reset the bob origin so any inherited _process work is
	# a no-op rather than mutating position.
	_bob_origin_y = position.y
	_has_bob_origin = false   # disables the per-frame bob lerp
	set_process(false)

func tick(_tick_index: int) -> void:
	pass

# Inert pieces have empty queues; persist save_id only. Subclasses with extra
# state (StorageCrate) override and merge.
func get_save_data() -> Dictionary:
	return {"save_id": save_id}

func apply_save_data(data: Dictionary) -> void:
	if data.has("save_id"):
		save_id = String(data["save_id"])
