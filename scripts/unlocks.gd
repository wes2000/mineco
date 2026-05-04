extends Node
## Autoload. Central registry for blueprint unlocks. Anything that gates
## content (shop items, build catalog entries, future perks) reads from
## here. Owners drop a blueprint by calling `unlock(id)`; consumers ask
## `has(id)` and listen on the `unlocked` signal to refresh their UI.
##
## State persists via SaveGame's `data["unlocks"]` block. Older saves
## without the block load cleanly with an empty unlock set.

signal unlocked(blueprint_id: String)

var _owned: Dictionary = {}   # String id -> true (used as a set)

func has(blueprint_id: String) -> bool:
	return _owned.has(blueprint_id)

func unlock(blueprint_id: String) -> bool:
	if blueprint_id == "" or _owned.has(blueprint_id):
		return false
	_owned[blueprint_id] = true
	unlocked.emit(blueprint_id)
	return true

func list_owned() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in _owned.keys():
		out.append(String(k))
	return out

func clear_all() -> void:
	# Test/debug helper. Does NOT emit per-id; refresh consumers manually.
	_owned.clear()

# --- Save round-trip --------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"owned": list_owned()}

func apply_save_data(data: Dictionary) -> void:
	_owned.clear()
	for v: Variant in data.get("owned", []):
		_owned[String(v)] = true
	# No per-id signal here — UIs that care should _refresh themselves on
	# load_completed (or just on next open).
