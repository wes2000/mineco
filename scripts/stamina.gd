extends Node
class_name Stamina

@export var max_value: int = 100
@export var regen_per_second: float = 30.0
@export var regen_delay_after_swing: float = 0.8
@export var min_resume_threshold: int = 20

var current: float
var _regen_locked_until: float = 0.0
var _empty_lockout: bool = false

signal stamina_changed(current: float, max_value: int)

func _ready() -> void:
	current = float(max_value)
	stamina_changed.emit(current, max_value)

func _process(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _regen_locked_until or current >= float(max_value):
		return
	current = min(float(max_value), current + regen_per_second * delta)
	if _empty_lockout and current >= float(min_resume_threshold):
		_empty_lockout = false
	stamina_changed.emit(current, max_value)

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
