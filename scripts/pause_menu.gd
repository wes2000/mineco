extends Control
## Modal pause menu opened with Esc. 5 tabs: Game / Audio / Video / Hotkeys / Admin.
## Replaces the old AdminPanel (F1) and the side-of-screen KeybindsOverlay.

const TAB_GAME: int = 0
const TAB_AUDIO: int = 1
const TAB_VIDEO: int = 2
const TAB_HOTKEYS: int = 3
const TAB_ADMIN: int = 4

const STANDARD_KEYBINDS: Array = [
	["WASD", "move"],
	["Shift", "sprint (drains stamina)"],
	["Ctrl", "crouch (hold)"],
	["Space", "jump"],
	["LMB", "mine"],
	["E", "interact"],
	["Tab", "inventory (hold)"],
	["M", "map (popup)"],
	["P", "passive tree"],
	["O", "company / rank"],
	["F2", "release mouse (for editor)"],
	["Esc", "menu / close"],
	["B", "build mode"],
]
const BUILD_KEYBINDS: Array = [
	["1 - 6", "select hotbar slot"],
	["G", "open build catalog"],
	["", "  (foundations, walls, roofs,"],
	["", "  storage, workbench, lamp,"],
	["", "  beacon, crusher, ...)"],
	["", "  click an item, then press"],
	["", "  1-6 to bind it to a slot"],
	["LMB", "place / link"],
	["R / wheel", "rotate ghost"],
	["X + LMB", "remove (refunds materials)"],
	["B / Esc", "exit build mode"],
]


@onready var _tabs: TabContainer = $Panel/Vbox/Tabs
@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn

func _ready() -> void:
	visible = false
	add_to_group("pause_menu")
	_close_btn.pressed.connect(close)
	_build_game_tab()
	_build_audio_tab()
	_build_video_tab()
	_build_hotkeys_tab()
	_build_admin_tab()

func toggle() -> void:
	if visible:
		close()
	else:
		open(TAB_GAME)

func open(tab_index: int = TAB_GAME) -> void:
	_tabs.current_tab = tab_index
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_admin_tab()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		accept_event()

# ---- Tab content builders ----------------------------------------------------

func _placeholder_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68, 1))
	lbl.add_theme_font_size_override("font_size", 18)
	return lbl

func _save_game_node() -> Node:
	# Resolved at runtime so the parser doesn't need the SaveGame autoload
	# in its global cache (newly-added autoloads sometimes don't refresh
	# until the editor restarts).
	return get_node_or_null("/root/SaveGame")

func _build_game_tab() -> void:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	var hdr: Label = Label.new()
	hdr.text = "Save & Load"
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85, 1))
	v.add_child(hdr)
	var save_btn: Button = Button.new()
	save_btn.text = "Save Game"
	save_btn.custom_minimum_size = Vector2(220, 36)
	save_btn.pressed.connect(func() -> void:
		var sg: Node = _save_game_node()
		if sg != null:
			sg.call("save_now")
	)
	v.add_child(save_btn)
	var sg_init: Node = _save_game_node()
	var load_btn: Button = Button.new()
	load_btn.text = "Load Game"
	load_btn.custom_minimum_size = Vector2(220, 36)
	load_btn.disabled = sg_init == null or not bool(sg_init.call("has_save"))
	load_btn.pressed.connect(func() -> void:
		var sg: Node = _save_game_node()
		if sg != null and bool(sg.call("has_save")):
			sg.call("load_now")
			close()
	)
	v.add_child(load_btn)
	# Two-click delete: first click arms the button + flips its text; second
	# click within CONFIRM_WINDOW seconds actually deletes. A simple pattern
	# that works without spawning a separate ConfirmationDialog.
	var del_btn: Button = Button.new()
	del_btn.text = "Delete Save"
	del_btn.custom_minimum_size = Vector2(220, 36)
	del_btn.disabled = sg_init == null or not bool(sg_init.call("has_save"))
	var del_state: Dictionary = {"armed": false, "timer": null}
	const CONFIRM_WINDOW: float = 3.0
	var disarm_del: Callable = func() -> void:
		del_state["armed"] = false
		del_btn.text = "Delete Save"
		del_btn.modulate = Color.WHITE
		del_state["timer"] = null
	del_btn.pressed.connect(func() -> void:
		var sg: Node = _save_game_node()
		if sg == null or not bool(sg.call("has_save")):
			return
		if not del_state["armed"]:
			del_state["armed"] = true
			del_btn.text = "Click again to confirm"
			del_btn.modulate = Color(1.0, 0.55, 0.55, 1)
			var timer: SceneTreeTimer = get_tree().create_timer(CONFIRM_WINDOW)
			del_state["timer"] = timer
			timer.timeout.connect(func() -> void:
				if del_state.get("timer") == timer:
					disarm_del.call()
			)
			return
		# Confirmed.
		sg.call("delete_save")
		load_btn.disabled = true
		del_btn.disabled = true
		disarm_del.call()
	)
	v.add_child(del_btn)
	# Passive tree opener — sits below the save controls.
	var sep_pt: HSeparator = HSeparator.new()
	v.add_child(sep_pt)
	var perks_hdr: Label = Label.new()
	perks_hdr.text = "Progression"
	perks_hdr.add_theme_font_size_override("font_size", 14)
	perks_hdr.add_theme_color_override("font_color", Color(0.75, 0.55, 0.95, 1))
	v.add_child(perks_hdr)
	var perks_btn: Button = Button.new()
	perks_btn.text = "Passive Tree  (P)"
	perks_btn.custom_minimum_size = Vector2(220, 36)
	perks_btn.pressed.connect(func() -> void:
		var ui: Node = get_tree().get_first_node_in_group("passive_tree_ui")
		if ui != null and ui.has_method("open"):
			close()
			ui.call("open")
	)
	v.add_child(perks_btn)
	var company_btn: Button = Button.new()
	company_btn.text = "Company  (O)"
	company_btn.custom_minimum_size = Vector2(220, 36)
	company_btn.pressed.connect(func() -> void:
		var co_ui: Node = get_tree().get_first_node_in_group("company_panel_ui")
		if co_ui != null and co_ui.has_method("open"):
			close()
			co_ui.call("open")
	)
	v.add_child(company_btn)
	if sg_init != null and sg_init.has_signal("save_completed"):
		sg_init.connect("save_completed", func() -> void:
			var sg: Node = _save_game_node()
			var has: bool = sg != null and bool(sg.call("has_save"))
			load_btn.disabled = not has
			del_btn.disabled = not has
			disarm_del.call()
		)
	# Unstuck — teleport the player back to spawn (0, 30, 0). Lets you
	# recover after falling through the world or getting wedged inside
	# a built piece. Re-runs SpawnGate's chunk-mesh wait so distant-island
	# saves don't fall through the void on respawn either.
	var sep_unstuck: HSeparator = HSeparator.new()
	v.add_child(sep_unstuck)
	var unstuck_hdr: Label = Label.new()
	unstuck_hdr.text = "Recover"
	unstuck_hdr.add_theme_font_size_override("font_size", 14)
	unstuck_hdr.add_theme_color_override("font_color", Color(0.95, 0.65, 0.55, 1))
	v.add_child(unstuck_hdr)
	var unstuck_btn: Button = Button.new()
	unstuck_btn.text = "Unstuck (Teleport to Spawn)"
	unstuck_btn.custom_minimum_size = Vector2(220, 36)
	unstuck_btn.pressed.connect(func() -> void:
		_teleport_to_spawn()
		close()
	)
	v.add_child(unstuck_btn)
	$Panel/Vbox/Tabs/Game.add_child(v)

# Teleport the player to main-town spawn and re-suspend physics until the
# spawn chunk is meshed (otherwise unstuck-from-a-far-island would just drop
# them into the void waiting for the chunk).
func _teleport_to_spawn() -> void:
	var player: Node3D = get_tree().root.get_node_or_null("Main/Player") as Node3D
	if player == null:
		return
	player.global_position = Vector3(0, 30, 0)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	var gate: Node = get_tree().get_first_node_in_group("spawn_gate")
	if gate != null and gate.has_method("suspend_until_ground"):
		gate.call("suspend_until_ground")

func _build_audio_tab() -> void:
	$Panel/Vbox/Tabs/Audio.add_child(_placeholder_label("Coming soon"))

func _build_video_tab() -> void:
	$Panel/Vbox/Tabs/Video.add_child(_placeholder_label("Coming soon"))

func _build_hotkeys_tab() -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.add_theme_constant_override("separation", 30)
	$Panel/Vbox/Tabs/Hotkeys.add_child(hbox)
	hbox.add_child(_build_keybinds_column("STANDARD", STANDARD_KEYBINDS))
	hbox.add_child(_build_keybinds_column("BUILD MODE", BUILD_KEYBINDS))

func _build_keybinds_column(header_text: String, binds: Array) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	var header: Label = Label.new()
	header.text = header_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
	col.add_child(header)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	for entry: Array in binds:
		var key_lbl: Label = Label.new()
		key_lbl.text = entry[0]
		key_lbl.add_theme_font_size_override("font_size", 14)
		key_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45, 1))
		grid.add_child(key_lbl)
		var desc_lbl: Label = Label.new()
		desc_lbl.text = entry[1]
		desc_lbl.add_theme_font_size_override("font_size", 14)
		desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 1))
		grid.add_child(desc_lbl)
	return col

# ---- Admin tab (replaces old AdminPanel) ------------------------------------

var _admin_no_stamina_btn: CheckButton
var _admin_noclip_btn: CheckButton
var _admin_fast_speed_btn: CheckButton
var _admin_speed_slider: HSlider
var _admin_speed_label: Label
var _admin_fast_damage_btn: CheckButton
var _admin_damage_slider: HSlider
var _admin_damage_label: Label
var _admin_big_radius_btn: CheckButton
var _admin_radius_slider: HSlider
var _admin_radius_label: Label

func _build_admin_tab() -> void:
	var v: VBoxContainer = VBoxContainer.new()
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.add_theme_constant_override("separation", 6)
	$Panel/Vbox/Tabs/Admin.add_child(v)

	_admin_no_stamina_btn = CheckButton.new()
	_admin_no_stamina_btn.text = "No stamina"
	_admin_no_stamina_btn.toggled.connect(func(on: bool) -> void: Admin.no_stamina = on)
	v.add_child(_admin_no_stamina_btn)

	_admin_noclip_btn = CheckButton.new()
	_admin_noclip_btn.text = "Noclip / fly (Space=up, Shift=down)"
	_admin_noclip_btn.toggled.connect(func(on: bool) -> void: Admin.noclip = on)
	v.add_child(_admin_noclip_btn)

	_admin_fast_speed_btn = CheckButton.new()
	_admin_fast_speed_btn.text = "Fast mining speed"
	_admin_fast_speed_btn.toggled.connect(func(on: bool) -> void: Admin.fast_speed = on)
	v.add_child(_admin_fast_speed_btn)
	v.add_child(_make_slider_row("speed"))

	_admin_fast_damage_btn = CheckButton.new()
	_admin_fast_damage_btn.text = "Fast mining damage"
	_admin_fast_damage_btn.toggled.connect(func(on: bool) -> void: Admin.fast_damage = on)
	v.add_child(_admin_fast_damage_btn)
	v.add_child(_make_slider_row("damage"))

	_admin_big_radius_btn = CheckButton.new()
	_admin_big_radius_btn.text = "Big dig radius"
	_admin_big_radius_btn.toggled.connect(func(on: bool) -> void: Admin.big_radius = on)
	v.add_child(_admin_big_radius_btn)
	v.add_child(_make_slider_row("radius"))

	# Give resources row
	var sep: HSeparator = HSeparator.new()
	v.add_child(sep)
	var give_label: Label = Label.new()
	give_label.text = "Give resources (+100):"
	give_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
	v.add_child(give_label)
	# Three rows so the full T1/T2/T3 ladder is reachable from the admin panel.
	var give_rows: Array = [
		["T1 (mined ore)", [
			["Stone",     MaterialDefs.MaterialId.STONE],
			["Iron Ore",  MaterialDefs.MaterialId.IRON_ORE],
			["Gold Ore",  MaterialDefs.MaterialId.GOLD_ORE],
		]],
		["T2 (smelted)", [
			["Brick",       MaterialDefs.MaterialId.BRICK],
			["Iron Ingot",  MaterialDefs.MaterialId.IRON_INGOT],
			["Gold Ingot",  MaterialDefs.MaterialId.GOLD_INGOT],
		]],
		["T3 (forged)", [
			["Block",     MaterialDefs.MaterialId.BLOCK],
			["Iron Bar",  MaterialDefs.MaterialId.IRON_BAR],
			["Gold Bar",  MaterialDefs.MaterialId.GOLD_BAR],
		]],
	]
	for tier_entry: Array in give_rows:
		var tier_lbl: Label = Label.new()
		tier_lbl.text = String(tier_entry[0])
		tier_lbl.add_theme_font_size_override("font_size", 11)
		tier_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))
		v.add_child(tier_lbl)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		for entry: Array in tier_entry[1]:
			var btn: Button = Button.new()
			btn.text = entry[0]
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_give.bind(entry[1]))
			row.add_child(btn)

func _make_slider_row(kind: String) -> HBoxContainer:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var slider: HSlider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl: Label = Label.new()
	lbl.custom_minimum_size = Vector2(60, 0)
	if kind == "speed":
		slider.min_value = 1.0
		slider.max_value = 10.0
		slider.step = 0.5
		slider.value = Admin.speed_multiplier
		_admin_speed_slider = slider
		_admin_speed_label = lbl
		slider.value_changed.connect(func(v: float) -> void:
			Admin.speed_multiplier = v
			_admin_speed_label.text = "x%.1f" % v
		)
		lbl.text = "x%.1f" % Admin.speed_multiplier
	elif kind == "damage":
		slider.min_value = 1.0
		slider.max_value = 300.0
		slider.step = 1.0
		slider.value = Admin.damage_multiplier
		_admin_damage_slider = slider
		_admin_damage_label = lbl
		slider.value_changed.connect(func(v: float) -> void:
			Admin.damage_multiplier = v
			_admin_damage_label.text = "x%d" % int(v)
		)
		lbl.text = "x%d" % int(Admin.damage_multiplier)
	elif kind == "radius":
		slider.min_value = 1.0
		slider.max_value = 20.0
		slider.step = 0.5
		slider.value = Admin.radius_multiplier
		_admin_radius_slider = slider
		_admin_radius_label = lbl
		slider.value_changed.connect(func(v: float) -> void:
			Admin.radius_multiplier = v
			_admin_radius_label.text = "x%.1f" % v
		)
		lbl.text = "x%.1f" % Admin.radius_multiplier
	hbox.add_child(slider)
	hbox.add_child(lbl)
	return hbox

func _refresh_admin_tab() -> void:
	if _admin_no_stamina_btn == null:
		return
	_admin_no_stamina_btn.button_pressed = Admin.no_stamina
	_admin_noclip_btn.button_pressed = Admin.noclip
	_admin_fast_speed_btn.button_pressed = Admin.fast_speed
	_admin_fast_damage_btn.button_pressed = Admin.fast_damage
	_admin_big_radius_btn.button_pressed = Admin.big_radius
	_admin_speed_slider.value = Admin.speed_multiplier
	_admin_damage_slider.value = Admin.damage_multiplier
	_admin_radius_slider.value = Admin.radius_multiplier

func _give(material_id: int) -> void:
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null:
		push_warning("PauseMenu: no player_miner found")
		return
	miner.add_factory_material(material_id, 100)
