extends Control
## Bottom-left chat overlay. Renders the last MAX_LINES messages and provides
## an Enter-to-toggle input field that sends through the Chat autoload.

@onready var _history: VBoxContainer = $VBox/History
@onready var _input: LineEdit = $VBox/Input

func _ready() -> void:
	add_to_group("chat_overlay")
	_input.text_submitted.connect(_on_input_submitted)
	if Chat != null:
		Chat.new_message.connect(_on_new_message)
	_redraw_history()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("chat_open") and not _input.visible:
		_open_input()
		accept_event()
		return
	if event.is_action_pressed("ui_cancel") and _input.visible:
		_close_input(false)
		accept_event()

func _open_input() -> void:
	_input.text = ""
	_input.visible = true
	_input.grab_focus()
	# Release the mouse so the player can type without rotating the camera.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_input(submitted: bool) -> void:
	_input.visible = false
	_input.release_focus()
	# Restore mouse capture only if not in a menu state.
	var pause: Node = get_tree().get_first_node_in_group("pause_menu")
	if pause == null or not pause.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_input_submitted(text: String) -> void:
	if Chat != null:
		Chat.send(text)
	_close_input(true)

func _on_new_message(_line: Dictionary) -> void:
	_redraw_history()

func _redraw_history() -> void:
	for c in _history.get_children():
		c.queue_free()
	if Chat == null:
		return
	for line in Chat.get_recent_lines():
		var lbl: Label = Label.new()
		var author: String = String(line.get("author", "?"))
		var text: String = String(line.get("text", ""))
		# Truncate long Steam IDs (numeric > 8 digits) so they don't dominate.
		var disp_author: String = author
		if author.is_valid_int() and author.length() > 8:
			disp_author = "User" + author.right(4)
		lbl.text = "[%s] %s" % [disp_author, text]
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96, 1))
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		lbl.add_theme_constant_override("outline_size", 4)
		_history.add_child(lbl)
