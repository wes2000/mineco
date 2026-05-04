extends StaticBody3D
class_name OreDeposit

enum OreType { STONE, IRON, GOLD }

@export var material: OreType = OreType.STONE
@export var stage_meshes: Array[Mesh] = []
@export var stage_scales: Array[float] = []
@export var hp_per_stage: int = 30
@export var ore_per_stage: int = 2
@export var ore_per_stage_array: Array[int] = []
@export var size_label: String = "medium"

# Distance past which the deposit mesh is culled. Kept well inside the
# voxel terrain's max_view_distance AND inside the distance the mesher can
# reliably keep up with at sailing speed — far enough past visibility_range
# means terrain at that range has been queued for ages but might still not
# be meshed yet, leading to floating deposits over un-meshed islands.
const VISIBILITY_RANGE_END: float = 192.0
const VISIBILITY_FADE_MARGIN: float = 24.0

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _hit_fx: GPUParticles3D = $HitParticles
@onready var _break_fx: GPUParticles3D = $BreakParticles

var _current_stage: int = 0
var _stage_hp_left: int

# Stable id assigned by OreGenerator from the deterministic spawn position.
# Used by SaveGame to restore mid-mining state and remove fully-depleted
# deposits after the OreGenerator's regenerated set is in the scene.
var deposit_id: String = ""

signal damaged(remaining_hp: int, stage: int)
signal chunk_broken(material: OreType, ore_amount: int, stage: int)
signal depleted(material: OreType)

func _ready() -> void:
	_stage_hp_left = hp_per_stage
	if stage_meshes.size() > 0:
		_mesh.mesh = stage_meshes[0]
	_mesh.scale = Vector3.ONE * _scale_for_stage(0)
	_mesh.visibility_range_end = VISIBILITY_RANGE_END
	_mesh.visibility_range_end_margin = VISIBILITY_FADE_MARGIN
	add_to_group("ore_deposits")

func take_damage(amount: int) -> void:
	_stage_hp_left -= amount
	_hit_fx.restart()
	damaged.emit(_stage_hp_left, _current_stage)
	if _stage_hp_left <= 0:
		_break_chunk()

func _break_chunk() -> void:
	_current_stage += 1
	_break_fx.restart()
	chunk_broken.emit(material, _ore_for_stage(_current_stage - 1), _current_stage - 1)
	if _current_stage >= stage_meshes.size():
		depleted.emit(material)
		queue_free()
	else:
		_mesh.mesh = stage_meshes[_current_stage]
		_mesh.scale = Vector3.ONE * _scale_for_stage(_current_stage)
		_stage_hp_left = hp_per_stage
		# Visual drop: nudge Y down a hair so the deposit appears to settle.
		position.y -= 0.05

func _scale_for_stage(s: int) -> float:
	if s < stage_scales.size():
		return stage_scales[s]
	return 1.0

func _ore_for_stage(s: int) -> int:
	if s < ore_per_stage_array.size():
		return ore_per_stage_array[s]
	return ore_per_stage

# --- Save / load -----------------------------------------------------------

func get_save_data() -> Dictionary:
	# Saved per non-depleted deposit. Depleted deposits are tracked by their
	# absence from the saved dict.
	return {"stage": _current_stage, "hp": _stage_hp_left}

func apply_save_data(data: Dictionary) -> void:
	_current_stage = int(data.get("stage", 0))
	_stage_hp_left = int(data.get("hp", hp_per_stage))
	if _current_stage >= stage_meshes.size():
		queue_free()
		return
	if stage_meshes.size() > 0:
		_mesh.mesh = stage_meshes[_current_stage]
	_mesh.scale = Vector3.ONE * _scale_for_stage(_current_stage)
