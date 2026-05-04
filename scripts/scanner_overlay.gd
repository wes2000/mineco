extends Control
## Scanner radar HUD. Visible only while the player has the Scanner tool out.
## Cycles through Stone/Iron/Gold ore targets via R, draws a sweeping radar
## that rotates over PING_INTERVAL, refreshes the nearest target on each
## sweep completion, plays a ping, and shows the distance to the nearest
## node + the current target material name.

const PING_INTERVAL: float = 1.5         # base seconds per radar sweep
const RADAR_RANGE_M: float = 80.0        # base max distance the radar represents
# Effective values are derived from PlayerStats each frame so a perk that
# bumps SCANNER_RANGE_MULT extends the radar without per-instance setup.
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
var _sweep_angle: float = 0.0   # radians, 0 = up, increases CW
var _prev_sweep_angle: float = 0.0

# Last "pinged" position — only updated when the sweep arm crosses the
# CURRENT bearing of the nearest matching node. Until then, the marker
# stays where it was last seen (stale on purpose, classic radar feel).
var _has_known_target: bool = false
var _known_world_pos: Vector3 = Vector3.ZERO
var _known_distance: float = 0.0

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
	_clear_known_target()
	_play_ping()

func hide_scanner() -> void:
	visible = false

func cycle_material() -> void:
	_current_index = (_current_index + 1) % TARGET_MATERIALS.size()
	_apply_material_label()
	# Forget the previous material's last-known target so the marker doesn't
	# linger from the wrong material; it'll re-acquire on the next sweep pass.
	_clear_known_target()
	_play_ping()

func _process(delta: float) -> void:
	if not visible:
		return
	_prev_sweep_angle = _sweep_angle
	# Faster ping = the sweep arm completes its rotation in less time.
	var ping_speed_mul: float = 1.0
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats != null:
		ping_speed_mul = float(stats.call("get_stat", &"scanner_ping_speed_mult"))
	_sweep_angle = fmod(_sweep_angle + delta * ping_speed_mul * (TAU / PING_INTERVAL), TAU)
	_radar.queue_redraw()
	# Each frame, see where the actual nearest matching node IS right now;
	# if the sweep arm just crossed that bearing this frame, "ping" it —
	# refresh the displayed marker to that node's current position.
	var current: Dictionary = _find_current_nearest()
	if not current.is_empty():
		var current_bearing: float = _world_to_radar_bearing(current.pos)
		if not is_nan(current_bearing) and _sweep_crossed(current_bearing):
			_known_world_pos = current.pos
			_known_distance = current.dist
			_has_known_target = true
			_update_distance_label()
	# Once per full revolution, ping (matches the radar sweep cycle).
	if _sweep_angle < _prev_sweep_angle:   # wrapped past 2π → 0
		_play_ping()

func _apply_material_label() -> void:
	var entry: Array = TARGET_MATERIALS[_current_index]
	_material_label.text = entry[1]
	_material_label.add_theme_color_override("font_color", entry[2])

# Returns {"pos": Vector3, "dist": float} for the nearest ore deposit of the
# currently-targeted type, or an empty Dictionary if none exists.
func _find_current_nearest() -> Dictionary:
	if _player == null:
		return {}
	var ore_type: int = TARGET_MATERIALS[_current_index][0]
	var origin: Vector3 = _player.global_position
	var max_range: float = _effective_range()
	var max_range_sq: float = max_range * max_range
	var best_d_sq: float = INF
	var best_pos: Vector3 = Vector3.ZERO
	for n: Node in get_tree().get_nodes_in_group("ore_deposits"):
		if not (n is OreDeposit):
			continue
		var od: OreDeposit = n as OreDeposit
		if od.material != ore_type:
			continue
		var d_sq: float = od.global_position.distance_squared_to(origin)
		if d_sq > max_range_sq:
			continue
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best_pos = od.global_position
	if best_d_sq == INF:
		return {}
	return {"pos": best_pos, "dist": sqrt(best_d_sq)}

func _effective_range() -> float:
	var stats: Node = get_node_or_null("/root/PlayerStats")
	if stats == null:
		return RADAR_RANGE_M
	return RADAR_RANGE_M * float(stats.call("get_stat", &"scanner_range_mult"))

func _clear_known_target() -> void:
	_has_known_target = false
	_known_distance = 0.0
	_distance_label.text = "—"

func _update_distance_label() -> void:
	_distance_label.text = "%.1f m" % _known_distance

# Has the sweep arm just crossed the given bearing this frame? Handles the
# 0 / 2π wrap correctly.
func _sweep_crossed(bearing: float) -> bool:
	var b: float = fposmod(bearing, TAU)
	var prev: float = fposmod(_prev_sweep_angle, TAU)
	var cur: float = fposmod(_sweep_angle, TAU)
	if prev <= cur:
		return prev < b and b <= cur
	# Wrapped past 2π; the swept arc is [prev, 2π) ∪ [0, cur].
	return b > prev or b <= cur

func _play_ping() -> void:
	if _ping == null or _ping.stream == null:
		return
	# Pitch up + randomize so each ping reads as sonar, not 'rock hit'.
	_ping.pitch_scale = randf_range(2.4, 2.7)
	_ping.play()

# Convert a world position to the radar bearing (0 = up = player forward,
# +CW). Returns NAN if the player isn't bound or the position is too close.
func _world_to_radar_bearing(world_pos: Vector3) -> float:
	if _player == null:
		return NAN
	var to_target: Vector3 = world_pos - _player.global_position
	to_target.y = 0
	if to_target.length_squared() < 0.001:
		return NAN
	# Player forward is -Z in local frame; +X is right.
	var local: Vector3 = _player.global_basis.transposed() * to_target
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
	# Target marker — drawn at the LAST KNOWN position (refreshed only when
	# the sweep arm crosses the target's actual current bearing).
	if _has_known_target:
		var ang: float = _world_to_radar_bearing(_known_world_pos)
		if not is_nan(ang):
			var d_norm: float = clamp(_known_distance / _effective_range(), 0.05, 1.0)
			var p: Vector2 = center + Vector2(cos(ang - PI / 2), sin(ang - PI / 2)) * radius * d_norm
			# Pulse the marker subtly with the sweep cycle
			var pulse: float = 4.5 + sin(_sweep_angle * 2.0) * 1.2
			_radar.draw_circle(p, pulse, marker_color)
			_radar.draw_circle(p, pulse * 0.4, Color(0.4, 0.25, 0.0, 1))
			# Edge tick if the target was last known at the radar range edge
			if d_norm >= 0.99:
				var edge_dir: Vector2 = Vector2(cos(ang - PI / 2), sin(ang - PI / 2))
				_radar.draw_line(center + edge_dir * (radius - 6), center + edge_dir * radius, marker_color, 2.0)
