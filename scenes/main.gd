extends Control

@onready var label: Label = $Label

func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "?"))
	label.text = "MiningSim\nv%s" % version
