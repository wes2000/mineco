extends Control
## Stub modal for the Workbench piece (brief 05). Just shows a "coming soon"
## message so E-on-workbench gives feedback before the actual crafting system
## ships in a later brief.

@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn

func _ready() -> void:
	visible = false
	add_to_group("workbench_ui")
	_close_btn.pressed.connect(close)

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("machine_interact"):
		close()
		accept_event()
