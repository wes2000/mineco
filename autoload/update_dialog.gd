extends Window
## Modal shown when an update is available. UI is constructed in code so the
## scene tree stays as a single .gd file. Signals communicate with the Updater.

signal update_requested
signal skip_requested

var _versions: Label
var _notes: RichTextLabel
var _progress: ProgressBar
var _status: Label
var _btn_update: Button
var _btn_skip: Button


func _init() -> void:
	title = "Update Available"
	min_size = Vector2i(440, 320)
	size = Vector2i(520, 380)
	transient = false
	exclusive = false
	unresizable = false


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	_versions = Label.new()
	_versions.add_theme_font_size_override("font_size", 18)
	vb.add_child(_versions)

	var notes_header := Label.new()
	notes_header.text = "Release notes:"
	vb.add_child(notes_header)

	_notes = RichTextLabel.new()
	_notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes.scroll_active = true
	_notes.bbcode_enabled = false
	_notes.fit_content = false
	vb.add_child(_notes)

	_progress = ProgressBar.new()
	_progress.visible = false
	_progress.min_value = 0
	_progress.max_value = 100
	vb.add_child(_progress)

	_status = Label.new()
	_status.visible = false
	vb.add_child(_status)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)

	_btn_skip = Button.new()
	_btn_skip.text = "Skip This Version"
	_btn_skip.pressed.connect(func(): skip_requested.emit())
	hb.add_child(_btn_skip)

	_btn_update = Button.new()
	_btn_update.text = "Update Now"
	_btn_update.pressed.connect(func(): update_requested.emit())
	hb.add_child(_btn_update)


func configure(current_version: String, new_version: String, notes: String) -> void:
	if not is_node_ready():
		await ready
	_versions.text = "v%s  →  v%s" % [current_version, new_version]
	_notes.text = notes if notes.strip_edges() != "" else "(no release notes)"


func show_progress() -> void:
	_btn_update.disabled = true
	_btn_skip.disabled = true
	_progress.visible = true
	_status.visible = true
	_status.text = "Downloading…"


func set_progress(downloaded: int, total: int) -> void:
	if total > 0:
		_progress.max_value = total
		_progress.value = downloaded
		_status.text = "Downloading…  %s / %s" % [
			String.humanize_size(downloaded),
			String.humanize_size(total),
		]
	else:
		_progress.value = 0
		_status.text = "Downloading…  %s" % String.humanize_size(downloaded)


func show_error(msg: String) -> void:
	_btn_update.disabled = false
	_btn_skip.disabled = false
	_progress.visible = false
	_status.visible = true
	_status.text = "Error: %s" % msg
