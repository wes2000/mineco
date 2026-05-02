extends Control
## Visible only when BuildController.active is true. Shows 4 tool slots + belt sub-row.

@onready var _slot_labels: Array = [
	$Panel/HBox/Slot1, $Panel/HBox/Slot2, $Panel/HBox/Slot3, $Panel/HBox/Slot4,
]
@onready var _belt_sub: Control = $Panel/BeltSub
@onready var _belt_sub_labels: Array = [
	$Panel/BeltSub/HBox/Sub1, $Panel/BeltSub/HBox/Sub2, $Panel/BeltSub/HBox/Sub3,
]

func _ready() -> void:
	BuildController.active_changed.connect(_on_active_changed)
	BuildController.selection_changed.connect(_on_selection_changed)
	visible = BuildController.active
	_refresh()

func _on_active_changed(is_active: bool) -> void:
	visible = is_active

func _on_selection_changed(_selected_tool: int, _sub: int) -> void:
	_refresh()

func _refresh() -> void:
	for i: int in _slot_labels.size():
		var lbl: Label = _slot_labels[i]
		lbl.modulate = Color.YELLOW if BuildController.current_tool == i else Color.WHITE
	_belt_sub.visible = (BuildController.current_tool == BuildController.Tool.BELT)
	if _belt_sub.visible:
		for i: int in _belt_sub_labels.size():
			var lbl2: Label = _belt_sub_labels[i]
			lbl2.modulate = Color.YELLOW if BuildController.current_belt_sub == i else Color.WHITE
