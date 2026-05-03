extends Control
## Visible only when BuildController.active is true. Shows 6 tool slots and a
## belt-link status hint when the player is mid-link.

@onready var _slot_labels: Array = [
	$Panel/HBox/Slot1, $Panel/HBox/Slot2, $Panel/HBox/Slot3,
	$Panel/HBox/Slot4, $Panel/HBox/Slot5, $Panel/HBox/Slot6,
]
@onready var _link_hint: Label = $Panel/LinkHint

func _ready() -> void:
	BuildController.active_changed.connect(_on_active_changed)
	BuildController.selection_changed.connect(_on_selection_changed)
	BuildController.link_state_changed.connect(_on_link_state_changed)
	visible = BuildController.active
	_refresh()

func _on_active_changed(is_active: bool) -> void:
	visible = is_active

func _on_selection_changed(_selected_tool: int) -> void:
	_refresh()

func _on_link_state_changed(awaiting_dest: bool) -> void:
	if awaiting_dest:
		_link_hint.text = "Click an INPUT port to finish link (Esc cancels)"
		_link_hint.visible = true
	elif BuildController.current_tool == BuildController.Tool.BELT:
		_link_hint.text = "Click an OUTPUT port to start a belt link"
		_link_hint.visible = true
	else:
		_link_hint.visible = false

func _refresh() -> void:
	for i: int in _slot_labels.size():
		var lbl: Label = _slot_labels[i]
		lbl.modulate = Color.YELLOW if BuildController.current_tool == i else Color.WHITE
	if BuildController.current_tool == BuildController.Tool.BELT:
		_link_hint.text = "Click an OUTPUT port to start a belt link"
		_link_hint.visible = true
	else:
		_link_hint.visible = false
