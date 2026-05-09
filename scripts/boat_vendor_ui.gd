extends Control
## Modal "buy a boat" window. One item, one button. Disables the Buy button
## once the player owns the boat or can't afford it.

const BOAT_PRICE: int = 2000

@onready var _close_btn: Button = $Panel/Vbox/HeaderRow/CloseBtn
@onready var _buy_btn: Button = $Panel/Vbox/ButtonRow/BuyBtn
@onready var _status: Label = $Panel/Vbox/Status

var _miner: Node = null

func _ready() -> void:
	add_to_group("boat_vendor_ui")
	visible = false
	_close_btn.pressed.connect(close)
	_buy_btn.pressed.connect(_on_buy)

func open() -> void:
	if HostOnlyGuard.block_if_guest("Boat Vendor"):
		return
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_miner = get_tree().get_first_node_in_group("player_miner")
	if _miner != null:
		if not _miner.gold_currency_changed.is_connected(_on_gold_changed):
			_miner.gold_currency_changed.connect(_on_gold_changed)
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _miner != null and _miner.gold_currency_changed.is_connected(_on_gold_changed):
		_miner.gold_currency_changed.disconnect(_on_gold_changed)
	_miner = null

func _on_gold_changed(_amount: int) -> void:
	_refresh()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("machine_interact"):
		close()
		accept_event()

func _refresh() -> void:
	if _miner == null:
		return
	var owned: bool = _miner.get("has_boat")
	var gold: int = _miner.get("gold_currency")
	if owned:
		_buy_btn.disabled = true
		_buy_btn.text = "Boat purchased ✓"
		_status.text = "Your boat is tied up at the dock."
	elif gold < BOAT_PRICE:
		_buy_btn.disabled = true
		_buy_btn.text = "Buy boat (%dg)" % BOAT_PRICE
		_status.text = "You need %d more gold." % (BOAT_PRICE - gold)
	else:
		_buy_btn.disabled = false
		_buy_btn.text = "Buy boat (%dg)" % BOAT_PRICE
		_status.text = "Press E on the boat to climb in."

func _on_buy() -> void:
	if _miner == null:
		return
	if _miner.get("has_boat"):
		return
	var gold: int = _miner.get("gold_currency")
	if gold < BOAT_PRICE:
		return
	_miner.add_gold_currency(-BOAT_PRICE)
	_miner.set("has_boat", true)
	_refresh()
