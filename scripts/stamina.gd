extends Node
class_name Stamina

@export var max_value: int = 100
@export var regen_per_second: float = 30.0
@export var regen_delay_after_swing: float = 0.8
@export var min_resume_threshold: int = 20

var current: float
var _regen_locked_until: float = 0.0
var _empty_lockout: bool = false
# Cached effective max — base + STAMINA_MAX_BONUS. Recomputed on stats_changed.
var _effective_max: int = 0

signal stamina_changed(current: float, max_value: int)

func _ready() -> void:
	_recompute_effective_max()
	current = float(_effective_max)
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null and stats.has_signal("stats_changed"):
		stats.stats_changed.connect(_on_stats_changed)
	stamina_changed.emit(current, _effective_max)

func _on_stats_changed() -> void:
	var prev_max: int = _effective_max
	_recompute_effective_max()
	# Top up by the bonus delta so granting +50 stamina mid-game actually
	# fills it; clamp the other way if a perk was removed.
	var delta: int = _effective_max - prev_max
	if delta > 0:
		current = min(float(_effective_max), current + float(delta))
	else:
		current = min(current, float(_effective_max))
	stamina_changed.emit(current, _effective_max)

func _recompute_effective_max() -> void:
	var bonus: float = 0.0
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null:
		bonus = float(stats.call("get_stat", &"stamina_max_bonus"))
	_effective_max = max(1, int(round(float(max_value) + bonus)))

func _process(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _regen_locked_until or current >= float(_effective_max):
		return
	var regen: float = regen_per_second
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null:
		regen *= float(stats.call("get_stat", &"stamina_regen_mult"))
	current = min(float(_effective_max), current + regen * delta)
	if _empty_lockout and current >= float(min_resume_threshold):
		_empty_lockout = false
	stamina_changed.emit(current, _effective_max)

func try_consume(amount: int) -> bool:
	if Admin.no_stamina: return true
	if _empty_lockout: return false
	if current < float(amount):
		_empty_lockout = true
		stamina_changed.emit(current, max_value)
		return false
	current -= float(amount)
	_regen_locked_until = (Time.get_ticks_msec() / 1000.0) + regen_delay_after_swing
	stamina_changed.emit(current, max_value)
	return true

# Continuous drain (e.g. sprinting). Returns true if drained, false if depleted
# or in the empty-lockout state. Caller should drop back to walk speed if false.
func try_drain(rate_per_sec: float, delta: float) -> bool:
	if Admin.no_stamina: return true
	if _empty_lockout: return false
	var amount: float = rate_per_sec * delta
	if current <= amount:
		current = 0.0
		_empty_lockout = true
		_regen_locked_until = (Time.get_ticks_msec() / 1000.0) + regen_delay_after_swing
		stamina_changed.emit(current, max_value)
		return false
	current -= amount
	_regen_locked_until = (Time.get_ticks_msec() / 1000.0) + regen_delay_after_swing
	stamina_changed.emit(current, max_value)
	return true
