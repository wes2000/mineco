extends Node
class_name Health
## Generic health component. Drop on any node that should be damageable.
## Read effective max via max_value (base_max + HEALTH_MAX_BONUS for the player;
## non-player owners can simply ignore the player-stats path — the bonus only
## applies if `apply_player_health_bonus` is true).
##
## Owners interested in damage feedback should connect to:
##   damaged(amount, source_pos, current, max)
##   health_changed(current, max)
##   died(source_pos)

@export var base_max: int = 50
@export var current: float = -1.0   # -1 sentinel — _ready fills from max_value()
## When true, max_value() reads PlayerStats.HEALTH_MAX_BONUS and adds it to base_max.
## Set on the player's Health node so the "Tough Skin" perk lights up.
@export var apply_player_health_bonus: bool = false
## When true, the next take_damage call still computes & emits damage signals
## even if current is already 0. Default false (dead = no further damage).
@export var allow_overkill_signals: bool = false

signal damaged(amount: float, source_pos: Vector3, current: float, max_v: int)
signal health_changed(current: float, max_v: int)
signal died(source_pos: Vector3)

var _is_dead: bool = false

func _ready() -> void:
	if current < 0.0:
		current = float(max_value())
	# Re-emit on stat changes so the player health bar refills the delta when
	# Tough Skin is taken mid-game.
	if apply_player_health_bonus:
		var stats: Node = get_node_or_null("/root/PlayerStats")
		if stats != null and stats.has_signal("stats_changed"):
			stats.stats_changed.connect(_on_player_stats_changed)
	# Defer one frame so listeners hooked in their own _ready see the value.
	call_deferred("_emit_initial")

func _emit_initial() -> void:
	health_changed.emit(current, max_value())

func max_value() -> int:
	var bonus: float = 0.0
	if apply_player_health_bonus:
		var stats: Node = get_node_or_null("/root/PlayerStats")
		if stats != null:
			bonus = float(stats.call("get_stat", &"health_max_bonus"))
	return max(1, int(round(float(base_max) + bonus)))

func is_dead() -> bool:
	return _is_dead

func take_damage(amount: float, source_pos: Vector3 = Vector3.ZERO, _tags: Dictionary = {}) -> void:
	if amount <= 0.0:
		return
	if _is_dead and not allow_overkill_signals:
		return
	current = max(0.0, current - amount)
	var mv: int = max_value()
	damaged.emit(amount, source_pos, current, mv)
	health_changed.emit(current, mv)
	if current <= 0.0 and not _is_dead:
		_is_dead = true
		died.emit(source_pos)

func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	var mv: int = max_value()
	current = min(float(mv), current + amount)
	health_changed.emit(current, mv)

# Restore to full and clear the dead flag — used after respawn and by training
# dummies that pop back up after a delay.
func revive_full() -> void:
	_is_dead = false
	current = float(max_value())
	health_changed.emit(current, max_value())

func get_save_data() -> Dictionary:
	return {
		"current": current,
		"base_max": base_max,
		"is_dead": _is_dead,
	}

func apply_save_data(data: Dictionary) -> void:
	base_max = int(data.get("base_max", base_max))
	current = float(data.get("current", base_max))
	_is_dead = bool(data.get("is_dead", false))
	health_changed.emit(current, max_value())

func _on_player_stats_changed() -> void:
	# Top up by the bonus delta so taking Tough Skin mid-game actually fills.
	var mv: int = max_value()
	if current > float(mv):
		current = float(mv)
	health_changed.emit(current, mv)
