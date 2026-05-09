extends CharacterBody3D
## Visible representation of a remote (non-local) player.
##
## MultiplayerSpawner instantiates one of these per non-local peer in the
## session. The MultiplayerSynchronizer in the scene mirrors `position`,
## `rotation.y`, `current_tool`, and `animation_state` from the authoritative
## remote peer. There is no input handling, no camera, no first-person tools —
## the local player has those; remote players are purely visual.
##
## Animation: the placeholder NPC GLB is unrigged. We mirror npc.gd's
## procedural walk-bob to suggest a gait when `animation_state == "walking"`.
## Walk/idle classification is done on the authoritative peer (it knows its
## own velocity) and replicated as a string. Tool-specific visuals and a
## proper rigged player model are deferred — Phase 1 just needs "I can see
## the other player and tell where they are."

@export var steam_id: String = ""
@export var display_name: String = ""

# Replicated state. The MultiplayerSynchronizer mirrors these from the
# authoritative remote peer.
var current_tool: int = 0
var animation_state: String = "idle"  # "idle" or "walking"

# Procedural fake-walk bob, mirroring npc.gd's pattern.
const _WALK_BOB_AMPLITUDE: float = 0.06
const _WALK_TILT_AMPLITUDE: float = 0.08
const _WALK_BOB_HZ: float = 2.4
const _VISUAL_REST_Y: float = 1.4
var _walk_phase: float = 0.0

@onready var _name_label: Label3D = $NameTag
@onready var _visual_root: Node3D = $Visual

func _ready() -> void:
	# Pure visual — no local physics simulation, no input. Position is driven
	# by the MultiplayerSynchronizer from the authoritative remote peer.
	set_physics_process(false)
	_refresh_name_label()

func _process(delta: float) -> void:
	if _visual_root == null:
		return
	if animation_state == "walking":
		_walk_phase += delta * _WALK_BOB_HZ * TAU
		var bob: float = sin(_walk_phase * 2.0) * _WALK_BOB_AMPLITUDE
		var tilt: float = sin(_walk_phase) * _WALK_TILT_AMPLITUDE
		_visual_root.position = Vector3(0.0, _VISUAL_REST_Y + bob, 0.0)
		_visual_root.rotation = Vector3(0.0, 0.0, tilt)
	else:
		_walk_phase = 0.0
		_visual_root.position = _visual_root.position.lerp(Vector3(0.0, _VISUAL_REST_Y, 0.0), 8.0 * delta)
		_visual_root.rotation = _visual_root.rotation.lerp(Vector3.ZERO, 8.0 * delta)

func set_display_name(p_name: String) -> void:
	display_name = p_name
	_refresh_name_label()

func _refresh_name_label() -> void:
	if _name_label != null:
		_name_label.text = display_name if display_name != "" else "Player"
