extends Control

@onready var label: Label = $Label

func _ready() -> void:
	var version := "?"
	var f := FileAccess.open("res://VERSION", FileAccess.READ)
	if f:
		version = f.get_as_text().strip_edges()
		f.close()
	label.text = "MiningSim\nv%s" % version
