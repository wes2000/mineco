extends Window
## Modal shown when an update is available. UI + theming are constructed
## in code so the dialog has a consistent blue-on-white look regardless of
## the host OS's window background.

signal update_requested
signal skip_requested

const BG_COLOR        := Color("#1e3a5f")  # deep navy panel
const TEXT_PRIMARY    := Color("#ffffff")
const TEXT_SECONDARY  := Color("#cfe2f3")  # very light blue for secondary
const NOTES_BG        := Color("#152a45")  # darker navy for the notes panel
const BUTTON_NORMAL   := Color("#3a6ea5")
const BUTTON_HOVER    := Color("#5285c0")
const BUTTON_PRESSED  := Color("#2c5683")
const BUTTON_DISABLED := Color("#2a4a6f")
const BUTTON_DISABLED_TEXT := Color("#9eb7d0")
const PROGRESS_TRACK  := Color("#152a45")
const PROGRESS_FILL   := Color("#5da9f0")

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
	# Player.gd captures the mouse at launch, so without this the cursor
	# stays hidden and locked to game center while this dialog is on
	# screen — the user can't actually click Update Now / Skip.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Solid blue panel that fills the Window so the OS-default background
	# never shows through.
	var bg := Panel.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.add_theme_stylebox_override("panel", _flat(BG_COLOR, 0))
	add_child(bg)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	bg.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	_versions = Label.new()
	_versions.add_theme_font_size_override("font_size", 18)
	_versions.add_theme_color_override("font_color", TEXT_PRIMARY)
	vb.add_child(_versions)

	var notes_header := Label.new()
	notes_header.text = "Release notes:"
	notes_header.add_theme_color_override("font_color", TEXT_SECONDARY)
	vb.add_child(notes_header)

	_notes = RichTextLabel.new()
	_notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes.scroll_active = true
	_notes.bbcode_enabled = false
	_notes.fit_content = false
	_notes.add_theme_color_override("default_color", TEXT_PRIMARY)
	_notes.add_theme_stylebox_override("normal", _flat(NOTES_BG, 4))
	_notes.add_theme_stylebox_override("focus", _flat(NOTES_BG, 4))
	vb.add_child(_notes)

	_progress = ProgressBar.new()
	_progress.visible = false
	_progress.min_value = 0
	_progress.max_value = 100
	_progress.add_theme_stylebox_override("background", _flat(PROGRESS_TRACK, 3))
	_progress.add_theme_stylebox_override("fill", _flat(PROGRESS_FILL, 3))
	_progress.add_theme_color_override("font_color", TEXT_PRIMARY)
	vb.add_child(_progress)

	_status = Label.new()
	_status.visible = false
	_status.add_theme_color_override("font_color", TEXT_SECONDARY)
	vb.add_child(_status)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)

	_btn_skip = _make_button("Skip This Version")
	_btn_skip.pressed.connect(func(): skip_requested.emit())
	hb.add_child(_btn_skip)

	_btn_update = _make_button("Update Now")
	_btn_update.pressed.connect(func(): update_requested.emit())
	hb.add_child(_btn_update)


# Hand the mouse back to the game when the dialog goes away. The progress
# branch (Update Now -> download -> game quits) doesn't matter since the
# process is dying anyway.
func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _flat(color: Color, corner: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	if corner > 0:
		sb.set_corner_radius_all(corner)
	return sb


func _make_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_color_override("font_color", TEXT_PRIMARY)
	b.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	b.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
	b.add_theme_color_override("font_disabled_color", BUTTON_DISABLED_TEXT)
	var states := {
		"normal":   BUTTON_NORMAL,
		"hover":    BUTTON_HOVER,
		"pressed":  BUTTON_PRESSED,
		"disabled": BUTTON_DISABLED,
	}
	for state in states:
		var sb := _flat(states[state], 4)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, sb)
	return b


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
