extends Control
## Scanner radar HUD. Visible only while the player has the Scanner tool out.
## Cycles through Stone/Iron/Gold ore targets via R, draws a sweeping radar
## that rotates over PING_INTERVAL, refreshes the nearest target on each
## sweep completion, plays a ping, and shows the distance to the nearest
## node + the current target material name.

const PING_INTERVAL: float = 1.5         # seconds per radar sweep
const RADAR_RANGE_M: float = 80.0        # max distance the radar represents
const TARGET_MATERIALS: Array = [
	[OreDeposit.OreType.STONE, "Stone Ore",  Color(0.85, 0.85, 0.9)],
	[OreDeposit.OreType.IRON,  "Iron Ore",   Color(0.85, 0.65, 0.5)],
	[OreDeposit.OreType.GOLD,  "Gold Ore",   Color(1, 0.85, 0.4)],
]

@onready var _radar: Control = $Panel/Vbox/Radar
@onready var _distance_label: Label = $Panel/Vbox/Distance
@onready var _material_label: Label = $Panel/Vbox/MaterialName
@onready var _ping: AudioStreamPlayer = $Ping

var _current_index: int = 0
var _player: Node3D = null
var _sweep_angle: float = 0.0   # radians, 0 = pointing right; sweeps clockwise
var _last_refresh: float = 0.0

# Cached nearest-target state, refreshed on each sweep completion
var _has_target: bool = false
var _target_world_pos: Vector3 = Vector3.ZERO
var _target_distance: float = 0.0

func _ready() -> void:
	add_to_group("scanner_overlay")
	visible = false
	_radar.draw.connect(_draw_radar)
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_material_label()

func bind_player(p: Node3D) -> void:
	_player = p

func show_scanner() -> void:
	visible = true
	_refresh_target()
	_play_ping()
	_last_refresh = Time.get_ticks_msec() / 1000.0

func hide_scanner() -> void:
	visible = false

func cycle_material() -> void:
	_current_index = (_current_index + 1) % TARGET_MATERIALS.size()
	_apply_material_label()
	_refresh_target()
	_play_ping()
	_last_refresh = Time.get_ticks_msec() / 1000.0

func _process(delta: float) -> void:
	if not visible:
		return
	# Continuous radar sweep — one full rotation per PING_INTERVAL.
	_sweep_angle = fmod(_sweep_angle + delta * (TAU / PING_INTERVAL), TAU)
	_radar.queue_redraw()
	# Refresh target + ping each time the sweep completes a rotation.
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_refresh >= PING_INTERVAL:
		_refresh_target()
		_play_ping()
		_last_refresh = now

func _apply_material_label() -> void:
	var entry: Array = TARGET_MATERIALS[_current_index]
	_material_label.text = entry[1]
	_material_label.add_theme_color_override("font_color", entry[2])

func _refresh_target() -> void:
	_has_target = false
	if _player == null:
		return
	var ore_type: int = TARGET_MATERIALS[_current_index][0]
	var origin: Vector3 = _player.global_position
	var best_d_sq: float = INF
	var best_pos: Vector3 = Vector3.ZERO
	for n: Node in get_tree().get_nodes_in_group("ore_deposits"):
		if not (n is OreDeposit):
			continue
		var od: OreDeposit = n as OreDeposit
		if od.material != ore_type:
			continue
		var d_sq: float = od.global_position.distance_squared_to(origin)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best_pos = od.global_position
	if best_d_sq < INF:
		_has_target = true
		_target_world_pos = best_pos
		_target_distance = sqrt(best_d_sq)
		_distance_label.text = "%.1f m" % _target_distance
	else:
		_distance_label.text = "no signal"

func _play_ping() -> void:
	if _ping == null or _ping.stream == null:
		return
	# Pitch up + slightly randomize so each ping feels like sonar, not "rock hit".
	_ping.pitch_scale = randf_range(2.4, 2.7)
	_ping.play()

# Returns the angle (in radians, 0 = up = forward, +CW) from the player to the
# target in the player's horizontal frame. Returns NAN if no target.
func _target_angle_relative_to_player() -> float:
	if not _has_target or _player == null:
		return NAN
	var to_target: Vector3 = _target_world_pos - _player.global_position
	to_target.y = 0
	if to_target.length_squared() < 0.001:
		return NAN
	# Player's forward is -Z in local frame; project target onto local XZ.
	var local: Vector3 = _player.global_basis.transposed() * to_target
	# In local frame: -Z is forward, +X is right. Convert to a 2D angle where
	# 0 = up (forward) and +ve = clockwise from above (which matches +X = right).
	return atan2(local.x, -local.z)

func _draw_radar() -> void:
	var center: Vector2 = _radar.size * 0.5
	var radius: float = min(_radar.size.x, _radar.size.y) * 0.5 - 4.0
	var grid_color: Color = Color(0.20, 0.50, 0.30, 0.45)
	var ring_color: Color = Color(0.30, 0.85, 0.45, 0.85)
	var sweep_color: Color = Color(0.55, 1.0, 0.65, 0.60)
	var marker_color: Color = Color(1.0, 1.0, 0.40, 1)
	# Concentric rings
	_radar.draw_arc(center, radius, 0, TAU, 64, ring_color, 1.5)
	_radar.draw_arc(center, radius * 0.66, 0, TAU, 48, grid_color, 1.0)
	_radar.draw_arc(center, radius * 0.33, 0, TAU, 32, grid_color, 1.0)
	# Cross
	_radar.draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), grid_color, 1.0)
	_radar.draw_line(center - Vector2(0, radius), center + Vector2(0, radius), grid_color, 1.0)
	# Forward indicator at the top
	_radar.draw_line(center, center + Vector2(0, -radius), Color(0.75, 1.0, 0.75, 0.8), 1.2)
	# Sweep arm (rotates over time). Draw multiple slices for a fading trail.
	for i: int in 6:
		var a: float = _sweep_angle - i * 0.10
		var fade: float = sweep_color.a * (1.0 - float(i) / 6.0) * 0.7
		var col: Color = Color(sweep_color.r, sweep_color.g, sweep_color.b, fade)
		var end: Vector2 = center + Vector2(cos(a - PI / 2), sin(a - PI / 2)) * radius
		_radar.draw_line(center, end, col, 1.5 if i == 0 else 1.0)
	# Target marker
	if _has_target:
		var ang: float = _target_angle_relative_to_player()
		if not is_nan(ang):
			var d_norm: float = clamp(_target_distance / RADAR_RANGE_M, 0.05, 1.0)
			var p: Vector2 = center + Vector2(cos(ang - PI / 2), sin(ang - PI / 2)) * radius * d_norm
			# Pulse the marker subtly with the sweep cycle
			var pulse: float = 4.5 + sin(_sweep_angle * 2.0) * 1.2
			_radar.draw_circle(p, pulse, marker_color)
			_radar.draw_circle(p, pulse * 0.4, Color(0.4, 0.25, 0.0, 1))
			# Edge tick if the target is at the radar range edge (off-radar)
			if d_norm >= 0.99:
				var edge_dir: Vector2 = Vector2(cos(ang - PI / 2), sin(ang - PI / 2))
				_radar.draw_line(center + edge_dir * (radius - 6), center + edge_dir * radius, marker_color, 2.0)
