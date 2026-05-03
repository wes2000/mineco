extends Control
## Top-right gold-currency chip. Subscribes to Miner.gold_currency_changed
## via the player_miner group.

@onready var _amount_label: Label = $Chip/Hbox/Amount

func _ready() -> void:
	# Defer one frame so /root/Main/Player/Miner has been added to the
	# 'player_miner' group via miner._ready().
	call_deferred("_subscribe")

func _subscribe() -> void:
	var miner: Node = get_tree().get_first_node_in_group("player_miner")
	if miner == null:
		return
	if miner.has_signal("gold_currency_changed"):
		miner.gold_currency_changed.connect(_on_gold_changed)
		_on_gold_changed(miner.get("gold_currency"))

func _on_gold_changed(amount: int) -> void:
	_amount_label.text = str(amount)
