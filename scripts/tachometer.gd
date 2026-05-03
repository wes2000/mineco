extends Control
## Bottom-right speed readout. Visible only while a Boat in the 'boats' group
## is currently being driven. Reads m/s from boat.current_speed and converts
## to MPH for display.

const MS_TO_MPH: float = 2.23694

@onready var _speed_label: Label = $Chip/Vbox/Speed

var _boat: Node = null

func _ready() -> void:
	visible = false
	set_process(true)

func _process(_delta: float) -> void:
	# Find any active driving boat. Cheap with one boat in the world.
	_boat = null
	for n: Node in get_tree().get_nodes_in_group("boats"):
		if n.get("is_driving"):
			_boat = n
			break
	if _boat == null:
		visible = false
		return
	visible = true
	var mph: float = abs(float(_boat.get("current_speed"))) * MS_TO_MPH
	_speed_label.text = "%d" % roundi(mph)
