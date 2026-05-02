extends Node

# Debug toggles + their multipliers. Sliders in the admin panel write to the
# multiplier vars at runtime; the toggles gate whether the multiplier is applied.
var no_stamina: bool = false
var noclip: bool = false   # fly mode + pass through terrain

var fast_speed: bool = false
var speed_multiplier: float = 4.0     # animation playback speed when fast_speed is on

var fast_damage: bool = false
var damage_multiplier: float = 100.0  # shovel damage scale when fast_damage is on

var big_radius: bool = false
var radius_multiplier: float = 5.0    # dirt-carve radius scale when big_radius is on
