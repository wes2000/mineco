extends Node
## Autoload. Single source of truth for the player's progression stats.
##
## Other systems (mining, stamina, scanner, vendors, factory, boat, ...)
## resolve their effective values by reading PlayerStats.get_stat(...) and
## multiplying / adding it to their own base. Modifiers are namespaced by a
## source_id (e.g. &"perk_strong_arm", &"shop_pickaxe_iron") so a single
## remove_source() call cleans up everything that source contributed.

# --- Stat name constants ---------------------------------------------------
# Use these instead of bare strings to keep typos out of the call sites.

const MINING_DAMAGE_MULT: StringName       = &"mining_damage_mult"
const MINING_SWING_SPEED_MULT: StringName  = &"mining_swing_speed_mult"
const DIG_RADIUS_MULT: StringName          = &"dig_radius_mult"
const STAMINA_MAX_BONUS: StringName        = &"stamina_max_bonus"
const STAMINA_REGEN_MULT: StringName       = &"stamina_regen_mult"
const SPRINT_SPEED_MULT: StringName        = &"sprint_speed_mult"
const SCANNER_RANGE_MULT: StringName       = &"scanner_range_mult"
const SCANNER_PING_SPEED_MULT: StringName  = &"scanner_ping_speed_mult"
const PICKUP_RADIUS_BONUS: StringName      = &"pickup_radius_bonus"
const SELL_VALUE_MULT: StringName          = &"sell_value_mult"
const CONTRACT_REWARD_MULT: StringName     = &"contract_reward_mult"
const FACTORY_SPEED_MULT: StringName       = &"factory_speed_mult"
const BOAT_SPEED_MULT: StringName          = &"boat_speed_mult"
const HEALTH_MAX_BONUS: StringName         = &"health_max_bonus"
const WEAPON_DAMAGE_MULT: StringName       = &"weapon_damage_mult"
const BUILD_COST_MULT: StringName          = &"build_cost_mult"

# Operations a modifier can apply to a stat.
const OP_ADD: StringName = &"add"
const OP_MUL: StringName = &"mul"

# Default base values per stat. Mults default to 1.0, bonuses to 0.0.
const _BASE: Dictionary = {
	MINING_DAMAGE_MULT: 1.0,
	MINING_SWING_SPEED_MULT: 1.0,
	DIG_RADIUS_MULT: 1.0,
	STAMINA_MAX_BONUS: 0.0,
	STAMINA_REGEN_MULT: 1.0,
	SPRINT_SPEED_MULT: 1.0,
	SCANNER_RANGE_MULT: 1.0,
	SCANNER_PING_SPEED_MULT: 1.0,
	PICKUP_RADIUS_BONUS: 0.0,
	SELL_VALUE_MULT: 1.0,
	CONTRACT_REWARD_MULT: 1.0,
	FACTORY_SPEED_MULT: 1.0,
	BOAT_SPEED_MULT: 1.0,
	HEALTH_MAX_BONUS: 0.0,
	WEAPON_DAMAGE_MULT: 1.0,
	BUILD_COST_MULT: 1.0,
}

# Floor for any computed mult so a stack of nerfs can't reach 0 (which would
# break factory cycles, scanner ranges, etc). Bonuses are unaffected.
const MIN_MULT: float = 0.05

signal stats_changed

# source_id (StringName) → Array of modifier dicts
# Each modifier dict: {stat: StringName, op: StringName, value: float}
var _modifiers: Dictionary = {}

# Cached final stat values, recomputed lazily.
var _cache: Dictionary = {}
var _cache_dirty: bool = true

func _ready() -> void:
	_cache = _BASE.duplicate()

# --- Public API ------------------------------------------------------------

func get_stat(stat_name: StringName) -> float:
	if _cache_dirty:
		_recompute()
	return float(_cache.get(stat_name, _BASE.get(stat_name, 0.0)))

# Add one modifier under source_id. Multiple modifiers can share a source.
func add_modifier(source_id: StringName, stat_name: StringName, op: StringName, value: float) -> void:
	if not _modifiers.has(source_id):
		_modifiers[source_id] = []
	_modifiers[source_id].append({
		"stat": stat_name,
		"op": op,
		"value": value,
	})
	_cache_dirty = true
	stats_changed.emit()

# Remove every modifier registered under source_id.
func remove_source(source_id: StringName) -> void:
	if not _modifiers.has(source_id):
		return
	_modifiers.erase(source_id)
	_cache_dirty = true
	stats_changed.emit()

func has_source(source_id: StringName) -> bool:
	return _modifiers.has(source_id)

# Returns a copy of all final stats — for debug / UI overlays.
func get_all_stats() -> Dictionary:
	if _cache_dirty:
		_recompute()
	return _cache.duplicate()

# Prints final stats and the per-source modifiers feeding them. Useful from
# the admin console while tuning perks / shop items.
func debug_print() -> void:
	if _cache_dirty:
		_recompute()
	print("[PlayerStats] modifier sources:")
	for sid: Variant in _modifiers.keys():
		print("  - %s: %s" % [sid, _modifiers[sid]])
	print("[PlayerStats] final stats:")
	for k: Variant in _cache.keys():
		var base: float = float(_BASE.get(k, 0.0))
		var final: float = float(_cache[k])
		if abs(base - final) > 0.0001:
			print("  %s = %.3f  (base %.3f)" % [k, final, base])
		else:
			print("  %s = %.3f" % [k, final])

# --- Save / load -----------------------------------------------------------

func get_save_data() -> Dictionary:
	# Modifiers are saved as-is — JSON round-trips StringName as plain string,
	# so apply_save_data coerces back. For v1 every source persists; later we
	# can add an `ephemeral` flag to drop temporary buffs from the save.
	var sources: Dictionary = {}
	for sid: Variant in _modifiers.keys():
		var raw: Array = _modifiers[sid]
		var list: Array = []
		for m: Dictionary in raw:
			list.append({
				"stat": String(m.stat),
				"op": String(m.op),
				"value": float(m.value),
			})
		sources[String(sid)] = list
	return {"modifiers": sources}

func apply_save_data(data: Dictionary) -> void:
	_modifiers = {}
	var src: Dictionary = data.get("modifiers", {})
	for sid_str: Variant in src.keys():
		var sid: StringName = StringName(String(sid_str))
		var raw_list: Array = src[sid_str]
		var list: Array = []
		for m: Variant in raw_list:
			if not (m is Dictionary):
				continue
			list.append({
				"stat": StringName(String(m.get("stat", ""))),
				"op": StringName(String(m.get("op", "add"))),
				"value": float(m.get("value", 0.0)),
			})
		_modifiers[sid] = list
	_cache_dirty = true
	stats_changed.emit()

# --- Internal --------------------------------------------------------------

func _recompute() -> void:
	# Adds first, then mults — gives the expected "+5 then x1.2" behavior.
	_cache = _BASE.duplicate()
	for sid: Variant in _modifiers.keys():
		for m: Dictionary in _modifiers[sid]:
			if m.op != OP_ADD:
				continue
			var stat: StringName = m.stat
			_cache[stat] = float(_cache.get(stat, 0.0)) + float(m.value)
	for sid: Variant in _modifiers.keys():
		for m: Dictionary in _modifiers[sid]:
			if m.op != OP_MUL:
				continue
			var stat: StringName = m.stat
			_cache[stat] = float(_cache.get(stat, 0.0)) * float(m.value)
	# Floor only the multiplicative stats so stacked nerfs can't zero them.
	for k: Variant in _cache.keys():
		var base: float = float(_BASE.get(k, 0.0))
		if base >= 1.0 and float(_cache[k]) < MIN_MULT:
			_cache[k] = MIN_MULT
	_cache_dirty = false
