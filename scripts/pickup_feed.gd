extends Control
## Bottom-left chat-style pickup feed. Entries stack newest-at-bottom, fade out
## after a short hold time, then free themselves and the rest collapse upward.

const ENTRY_HOLD: float = 1.6
const ENTRY_FADE: float = 0.6
const MAX_ENTRIES: int = 8

const ITEM_COLORS: Dictionary = {
	0: Color(0.85, 0.85, 0.9),    # STONE
	1: Color(1.0, 0.55, 0.4),     # BRICK
	2: Color(0.6, 0.6, 0.6),      # BLOCK
	3: Color(0.85, 0.65, 0.5),    # IRON_ORE
	4: Color(0.9, 0.9, 0.95),     # IRON_INGOT
	5: Color(1, 1, 1),            # IRON_BAR
	6: Color(0.9, 0.78, 0.35),    # GOLD_ORE
	7: Color(1, 0.85, 0.4),       # GOLD_INGOT
	8: Color(1, 0.9, 0.5),        # GOLD_BAR
}

@onready var _vbox: VBoxContainer = $Vbox

func _ready() -> void:
	add_to_group("pickup_feed")

func add_message(material_id: int, amount: int) -> void:
	var name: String = MaterialDefs.DISPLAY_NAME.get(material_id, "?")
	_add_label("+%d %s" % [amount, name], ITEM_COLORS.get(material_id, Color.WHITE))

# Generic system toast — same fade behavior, used for things like 'Game saved'.
func add_text_message(text: String) -> void:
	_add_label(text, Color(0.7, 0.95, 0.7, 1))

func _add_label(text: String, color: Color) -> void:
	while _vbox.get_child_count() >= MAX_ENTRIES:
		var oldest: Node = _vbox.get_child(0)
		oldest.queue_free()
		await get_tree().process_frame
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(lbl)
	var tween: Tween = create_tween()
	tween.tween_interval(ENTRY_HOLD)
	tween.tween_property(lbl, "modulate:a", 0.0, ENTRY_FADE)
	tween.tween_callback(lbl.queue_free)
