extends Panel

@onready var _no_stamina_btn: CheckButton = $VBox/NoStamina
@onready var _noclip_btn: CheckButton = $VBox/Noclip

@onready var _fast_speed_btn: CheckButton = $VBox/FastSpeed
@onready var _speed_slider: HSlider = $VBox/SpeedRow/SpeedSlider
@onready var _speed_label: Label = $VBox/SpeedRow/SpeedLabel

@onready var _fast_damage_btn: CheckButton = $VBox/FastDamage
@onready var _damage_slider: HSlider = $VBox/DamageRow/DamageSlider
@onready var _damage_label: Label = $VBox/DamageRow/DamageLabel

@onready var _big_radius_btn: CheckButton = $VBox/BigRadius
@onready var _radius_slider: HSlider = $VBox/RadiusRow/RadiusSlider
@onready var _radius_label: Label = $VBox/RadiusRow/RadiusLabel

@onready var _give_stone_btn: Button = $VBox/GiveRow/GiveStone
@onready var _give_iron_btn: Button = $VBox/GiveRow/GiveIron
@onready var _give_gold_btn: Button = $VBox/GiveRow/GiveGold

func _ready() -> void:
	visible = false

	_no_stamina_btn.button_pressed = Admin.no_stamina
	_no_stamina_btn.toggled.connect(func(on): Admin.no_stamina = on)

	_noclip_btn.button_pressed = Admin.noclip
	_noclip_btn.toggled.connect(func(on): Admin.noclip = on)

	_fast_speed_btn.button_pressed = Admin.fast_speed
	_fast_speed_btn.toggled.connect(func(on): Admin.fast_speed = on)
	_speed_slider.value = Admin.speed_multiplier
	_speed_slider.value_changed.connect(_on_speed_changed)
	_update_speed_label()

	_fast_damage_btn.button_pressed = Admin.fast_damage
	_fast_damage_btn.toggled.connect(func(on): Admin.fast_damage = on)
	_damage_slider.value = Admin.damage_multiplier
	_damage_slider.value_changed.connect(_on_damage_changed)
	_update_damage_label()

	_big_radius_btn.button_pressed = Admin.big_radius
	_big_radius_btn.toggled.connect(func(on): Admin.big_radius = on)
	_radius_slider.value = Admin.radius_multiplier
	_radius_slider.value_changed.connect(_on_radius_changed)
	_update_radius_label()

	_give_stone_btn.pressed.connect(_give.bind(MaterialDefs.MaterialId.STONE))
	_give_iron_btn.pressed.connect(_give.bind(MaterialDefs.MaterialId.IRON_ORE))
	_give_gold_btn.pressed.connect(_give.bind(MaterialDefs.MaterialId.GOLD_ORE))

func _give(material_id: int) -> void:
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null:
		push_warning("AdminPanel: no player_miner found")
		return
	miner.add_factory_material(material_id, 100)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("admin_toggle"):
		visible = not visible
		if visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _on_speed_changed(v: float) -> void:
	Admin.speed_multiplier = v
	_update_speed_label()

func _on_damage_changed(v: float) -> void:
	Admin.damage_multiplier = v
	_update_damage_label()

func _on_radius_changed(v: float) -> void:
	Admin.radius_multiplier = v
	_update_radius_label()

func _update_speed_label() -> void:
	_speed_label.text = "x%.1f" % Admin.speed_multiplier

func _update_damage_label() -> void:
	_damage_label.text = "x%d" % int(Admin.damage_multiplier)

func _update_radius_label() -> void:
	_radius_label.text = "x%.1f" % Admin.radius_multiplier
