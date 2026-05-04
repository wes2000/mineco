extends Node
## Autoload. Tracks owned ranks for the passive-tree perks defined in
## scripts/passive_perk_defs.gd. Spending gold here registers a modifier
## source on PlayerStats per perk so the bonuses immediately affect gameplay
## via existing stat consumers (mining, scanner, factory, sell, ...).
##
## Persisted via SaveGame under the "passive_tree" key. Existing saves
## without that block load fine — apply_save_data() with the default {}
## leaves every rank at 0 and the player keeps full base stats.

# Preload the catalog by const reference so the parser doesn't need
# PassivePerkDefs in its global class_name cache.
const _PerkDefs: GDScript = preload("res://scripts/passive_perk_defs.gd")

signal changed

# perk_id (String) -> int rank
var _ranks: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# --- Public API -----------------------------------------------------------

func current_rank(perk_id: String) -> int:
	return int(_ranks.get(perk_id, 0))

# Total gold spent across every owned rank — for HUD readouts later.
func total_spent() -> int:
	var total: int = 0
	for pid: Variant in _ranks.keys():
		var perk: Dictionary = _PerkDefs.by_id(String(pid))
		if perk.is_empty():
			continue
		total += int(perk.cost) * int(_ranks[pid])
	return total

# True when player can buy the next rank: perk exists, more ranks available,
# prerequisites met, and miner has the gold.
func can_buy(perk_id: String, miner: Node) -> bool:
	var perk: Dictionary = _PerkDefs.by_id(perk_id)
	if perk.is_empty():
		return false
	var rank: int = current_rank(perk_id)
	if rank >= int(perk.max_rank):
		return false
	if not _PerkDefs.meets_requirements(perk, _ranks):
		return false
	if miner == null:
		return false
	if int(miner.get("gold_currency")) < int(perk.cost):
		return false
	return true

func buy(perk_id: String, miner: Node) -> bool:
	if not can_buy(perk_id, miner):
		return false
	var perk: Dictionary = _PerkDefs.by_id(perk_id)
	# Subtract gold via the miner's API so its gold_currency_changed signal
	# fires and HUD widgets update.
	if miner.has_method("add_gold_currency"):
		miner.call("add_gold_currency", -int(perk.cost))
	else:
		miner.set("gold_currency", int(miner.get("gold_currency")) - int(perk.cost))
	_ranks[perk_id] = current_rank(perk_id) + 1
	apply_all_modifiers()
	changed.emit()
	return true

# Re-registers every owned perk's modifier source on PlayerStats. Cheap and
# idempotent — remove_source for an unknown source is a no-op. Called from
# buy(), apply_save_data(), and after the autoload is reachable so a
# fresh-loaded game still pushes its perks onto PlayerStats.
func apply_all_modifiers() -> void:
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats == null:
		return
	# Tear down every perk we know about so a removed/cleared rank doesn't
	# leave a stale source behind. We iterate the catalog (not _ranks) so
	# resetting a rank to 0 cleans up too.
	for perk: Dictionary in _PerkDefs.ITEMS:
		stats.call("remove_source", _source_id_for(String(perk.id)))
	# Add a single source per owned perk, with its modifiers stacked once
	# per rank.
	for pid: Variant in _ranks.keys():
		var rank: int = int(_ranks[pid])
		if rank <= 0:
			continue
		var perk: Dictionary = _PerkDefs.by_id(String(pid))
		if perk.is_empty():
			continue
		var src: StringName = _source_id_for(String(pid))
		for _r: int in rank:
			for m: Dictionary in perk.modifiers_per_rank:
				stats.call("add_modifier", src,
					StringName(String(m.stat)),
					StringName(String(m.op)),
					float(m.value))

# Admin / debug — wipes every rank and refunds nothing. Useful from the
# console while tuning. Not bound to a UI button.
func reset_all() -> void:
	_ranks.clear()
	apply_all_modifiers()
	changed.emit()

# --- Save / load ----------------------------------------------------------

func get_save_data() -> Dictionary:
	# Write the dictionary as String->int so JSON round-trips cleanly.
	var out: Dictionary = {}
	for pid: Variant in _ranks.keys():
		out[String(pid)] = int(_ranks[pid])
	return {"ranks": out}

func apply_save_data(data: Dictionary) -> void:
	_ranks.clear()
	var raw: Dictionary = data.get("ranks", {})
	for pid: Variant in raw.keys():
		var r: int = int(raw[pid])
		if r > 0:
			_ranks[String(pid)] = r
	apply_all_modifiers()
	changed.emit()

# --- Internal -------------------------------------------------------------

func _source_id_for(perk_id: String) -> StringName:
	return StringName("perk_" + perk_id)
