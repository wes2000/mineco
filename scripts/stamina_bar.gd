extends ProgressBar

@export var stamina_path: NodePath = "/root/Main/Player/Stamina"

func _ready() -> void:
	var stamina: Node = get_node_or_null(stamina_path)
	if stamina == null:
		push_error("StaminaBar: Stamina not found at " + str(stamina_path))
		return
	stamina.stamina_changed.connect(_on_changed)
	min_value = 0.0
	max_value = float(stamina.max_value)
	value = stamina.current

func _on_changed(current: float, max_v: int) -> void:
	max_value = float(max_v)
	value = current
