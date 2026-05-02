# Mining Depth R1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the MVP "click → instantly carve voxels → roll noise for material" with a tool-based loop: a held shovel with swing animation, a stamina bar, surface rocks (1 hit = +1 stone), entity-based underground ore deposits with HP / stage-breaking / scaled visuals, and a distinct ore-hit audio cue.

**Architecture:** Six independent components composed via signals — `Shovel` (view-model + swing animation, owns hit-frame timing), `Stamina` (model + try_consume), `OreDeposit` (StaticBody3D, take_damage → stage transitions → chunk_broken signal), `OreGenerator` (one-shot scatter on world spawn), refactored `Miner` (consumes Shovel's hit-frame, raycasts, routes to deposit or voxel-fallback), and a `StaminaBar` HUD. Voxel carving is preserved as dirt-only traversal (no inventory credit).

**Tech Stack:** Godot 4.6 module build (custom binary; this is the same engine the prior rounds use), GDScript, Voxel Tools 1.6 (`VoxelTerrain`, `VoxelTool.do_sphere`, `VoxelTool.get_voxel_f`).

**Spec:** `docs/superpowers/specs/2026-05-02-mining-depth-r1-design.md`

**Project root:** `C:\Users\whann\Documents\mine-co\` (Windows). All `res://` paths resolve under this root.

**Versioning note:** This project is **NOT** a git repository. Prior plans include `git commit` steps that were never executed; those steps are omitted from this plan. If a repo is later initialized, commit boundaries are obvious from the task structure.

---

## Validation philosophy

Each task ends with an in-editor or runtime visual check via `mcp__godot-ai__project_run` (with `autosave: false`) + `mcp__godot-ai__editor_screenshot source="game"`. Wait at least 8 seconds after `project_run` for chunks to mesh and the player spawn-gate's raycast to fire — the previous round's subagents learned a 5s wait was insufficient on this build. There are no unit tests; this is scene/script wiring with runtime validation.

When the editor is in play mode, MCP file-system operations error with `EDITOR_NOT_READY`. Always `mcp__godot-ai__project_manage op="stop"` before edits, then re-run for verification.

---

## File structure (final state)

```
res://
  scripts/
    shovel.gd                    NEW — Shovel (view-model + swing animation owner)
    stamina.gd                   NEW — Stamina model
    stamina_bar.gd               NEW — HUD bar mirror of Stamina
    ore_deposit.gd               NEW — take_damage / stage / chunk_broken
    ore_generator.gd             NEW — scatter on world spawn
    miner.gd                     MODIFIED — replace dig-on-input with hit-frame consumer
    spawn_gate.gd                MODIFIED — emit world_ready signal
  scenes/
    shovel.tscn                  NEW (uses CC0 GLB + AnimationPlayer)
    ore_deposit.tscn             NEW — base scene
    surface_rock.tscn            NEW — degenerate variant of OreDeposit
    ore_deposits/                NEW directory of 7 .tscn presets
      stone_small.tscn, stone_medium.tscn, stone_large.tscn,
      iron_small.tscn, iron_large.tscn,
      gold_small.tscn, gold_large.tscn
    player.tscn                  MODIFIED — add Stamina, instance Shovel under Camera3D, add OreHitEmitter
    main.tscn                    MODIFIED — StaminaBar in HUD, OreGenerator node
    nature_library.tres          MODIFIED — remove rock_small + rock_medium scatter entries
  assets/
    audio/ore_hit.ogg            NEW — CC0 metal-on-stone clink, ~100-250ms
    models/shovel.glb            NEW — CC0 sourced shovel mesh
  project.godot                  MODIFIED — add named physics layer "mining_targets"
```

---

## Task dependency graph

```
T1 (project plumbing) ─┐
T2 (audio asset)       ├─> T6 (shovel scene needs T3) ─┐
T3 (shovel asset)      │                                │
T4 (Stamina script) ─> T5 (Stamina HUD) ───────────────┤
T7 (OreDeposit base) ─> T8 (presets) ─> T9 (SurfaceRock) ─┤
                                                          ▼
                                                T10 (Miner refactor)
                                                          │
                                                          ▼
                                                T11 (player.tscn wiring)
                                                          │
                                                          ▼
                                                T12 (SpawnGate world_ready)
                                                          │
                                                          ▼
                                                T13 (OreGenerator + main.tscn)
                                                          │
                                                          ▼
                                                T14 (remove decorative rocks)
                                                          │
                                                          ▼
                                                T15 (E2E playtest)
```

Tasks T1, T2, T3, T4, T7 are independent and can be parallelized at the start. T6 needs T3. T5 needs T4. T9 needs T8 needs T7. Everything else is sequential after that.

---

### Task 1: Project plumbing — physics layer

**Files:**
- Modify: `c:/Users/whann/Documents/mine-co/project.godot` (add named physics layer)

**Goal:** Register a `mining_targets` named physics layer so `OreDeposit` collision shapes live there and the player's raycast can branch on layer membership.

- [ ] **Step 1: Read current `project.godot` to find the `[layer_names]` section (or confirm it doesn't exist yet).**

Use `mcp__godot-ai__filesystem_manage op="read_text" params={"path":"res://project.godot"}`.

- [ ] **Step 2: Add the layer name.**

If `[layer_names]` doesn't exist, add it. Add this line within it:

```
3d_physics/layer_2="mining_targets"
```

(Layer 1 is `default`; layer 2 = mining_targets. Index in code is `0b10` = `2`.)

- [ ] **Step 3: Save and reload the project.**

Write the modified file via `mcp__godot-ai__filesystem_manage op="write_text"`. The editor reloads project settings on file save; if a restart is required, do `mcp__godot-ai__editor_manage op="quit"` and the user re-opens — but in practice Godot 4.6 picks up `project.godot` changes live. Verify by reading back with `mcp__godot-ai__project_manage op="settings_get" params={"name":"layer_names/3d_physics/layer_2"}` and confirming the returned value is `"mining_targets"`.

---

### Task 2: Source ore_hit audio asset

**Files (created):**
- `res://assets/audio/ore_hit.ogg`

**Goal:** A CC0 metal-on-stone "clink" / pickaxe-chink, 100-250ms, named `ore_hit.ogg` and importable as `AudioStream`.

- [ ] **Step 1: Search for a CC0 sample.**

Try `WebSearch` for `"pickaxe hit stone CC0 ogg site:freesound.org"` or similar. Acceptable sources: freesound.org (CC0 only — verify license), pixabay.com/sound-effects, opengameart.org. Pick a short, sharp sample.

- [ ] **Step 2: Download the file to `res://assets/audio/ore_hit.ogg`.**

Use `WebFetch` to retrieve the URL, save the file to the absolute path `c:/Users/whann/Documents/mine-co/assets/audio/ore_hit.ogg`. If the source provides .wav, convert/rename to `.ogg` (Godot accepts both, but the spec calls for `.ogg` to match the existing `mine_thump.ogg` convention).

- [ ] **Step 3: Trigger Godot to import the new file.**

`mcp__godot-ai__filesystem_manage op="reimport" params={"paths":["res://assets/audio/ore_hit.ogg"]}`.

- [ ] **Step 4: Verify.**

`mcp__godot-ai__filesystem_manage op="search" params={"name":"ore_hit","type":"AudioStreamOggVorbis"}` — confirm 1 result.

---

### Task 3: Source shovel mesh asset

**Files (created):**
- `res://assets/models/shovel.glb`

**Goal:** A CC0 shovel GLB, low-poly, suitable for first-person view-model (held in lower-right of screen).

- [ ] **Step 1: Search for a CC0 shovel.**

`WebSearch` for `"shovel GLB CC0 low poly"`, prefer Quaternius / Kenney / OpenGameArt. The spec says: if nothing decent in ~10 minutes, fall back to procedural primitives (cylinder handle + box head) authored directly in `shovel.tscn`. The user has stated they will swap the asset later either way.

- [ ] **Step 2: Save to `c:/Users/whann/Documents/mine-co/assets/models/shovel.glb`.**

Create the `assets/models/` directory first if it does not exist. (Use `Bash mkdir -p`.)

- [ ] **Step 3: Reimport via Godot.**

`mcp__godot-ai__filesystem_manage op="reimport" params={"paths":["res://assets/models/shovel.glb"]}`.

- [ ] **Step 4: Verify.**

Confirm the GLB imports as a `PackedScene` with at least one `MeshInstance3D` child by opening it temporarily: `mcp__godot-ai__scene_open params={"path":"res://assets/models/shovel.glb"}`, `mcp__godot-ai__scene_get_hierarchy`, then close without saving. Note total bounding-box dimensions (you'll need them in T6 to scale the view-model).

---

### Task 4: Stamina model script

**Files (created):**
- `res://scripts/stamina.gd`

**Goal:** A standalone `Stamina` Node script with `try_consume(amount)`, regen-with-delay, and `stamina_changed` signal. No coupling to anything else.

- [ ] **Step 1: Create the script.**

`mcp__godot-ai__script_create` with this exact content:

```gdscript
extends Node
class_name Stamina

@export var max_value: int = 100
@export var regen_per_second: float = 30.0
@export var regen_delay_after_swing: float = 0.8
@export var min_resume_threshold: int = 20

var current: float
var _regen_locked_until: float = 0.0
var _empty_lockout: bool = false

signal stamina_changed(current: float, max_value: int)

func _ready() -> void:
	current = float(max_value)
	stamina_changed.emit(current, max_value)

func _process(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _regen_locked_until or current >= float(max_value):
		return
	current = min(float(max_value), current + regen_per_second * delta)
	if _empty_lockout and current >= float(min_resume_threshold):
		_empty_lockout = false
	stamina_changed.emit(current, max_value)

func try_consume(amount: int) -> bool:
	if _empty_lockout: return false
	if current < float(amount):
		_empty_lockout = true
		stamina_changed.emit(current, max_value)
		return false
	current -= float(amount)
	_regen_locked_until = (Time.get_ticks_msec() / 1000.0) + regen_delay_after_swing
	stamina_changed.emit(current, max_value)
	return true
```

- [ ] **Step 2: Symbol verify.**

`mcp__godot-ai__script_manage op="find_symbols" params={"path":"res://scripts/stamina.gd"}` — confirm `class_name=Stamina`, the three declared signals/functions are present, no parse errors. (If parse error, the response surfaces it.)

- [ ] **Step 3: No runtime test in this task.**

Stamina is verified end-to-end by T11 (player wiring) + T15 (E2E playtest).

---

### Task 5: Stamina HUD bar

**Files:**
- Create: `res://scripts/stamina_bar.gd`
- Modify: `res://scenes/main.tscn` (add `StaminaBar` Control under existing `HUD` CanvasLayer)

**Goal:** A `ProgressBar` bottom-center of screen that mirrors the Player's `Stamina` node.

- [ ] **Step 1: Create the script.**

```gdscript
extends ProgressBar

@export var stamina_path: NodePath = "/root/Main/Player/Stamina"

func _ready() -> void:
	var stamina: Node = get_node_or_null(stamina_path)
	if stamina == null:
		push_error("StaminaBar: Stamina not found at " + str(stamina_path))
		return
	stamina.stamina_changed.connect(_on_changed)
	min_value = 0.0
	max_value = float(stamina.max_value)
	value = stamina.current

func _on_changed(current: float, max_v: int) -> void:
	max_value = float(max_v)
	value = current
```

- [ ] **Step 2: Open `scenes/main.tscn`.**

`mcp__godot-ai__scene_open params={"path":"res://scenes/main.tscn"}`.

- [ ] **Step 3: Add a `StaminaBar` ProgressBar node under `HUD`.**

`mcp__godot-ai__node_create` with type `ProgressBar`, parent `HUD`, name `StaminaBar`. Then attach the script via `mcp__godot-ai__script_attach params={"node_path":"HUD/StaminaBar","script_path":"res://scripts/stamina_bar.gd"}`.

Set the layout via `mcp__godot-ai__node_set_property` calls on `HUD/StaminaBar`:

| Property | Value |
|---|---|
| `anchor_left` | 0.5 |
| `anchor_right` | 0.5 |
| `anchor_top` | 1.0 |
| `anchor_bottom` | 1.0 |
| `offset_left` | -150.0 |
| `offset_right` | 150.0 |
| `offset_top` | -50.0 |
| `offset_bottom` | -34.0 |
| `show_percentage` | false |

(Result: 300px wide, 16px tall, centered horizontally, 34px above bottom edge.)

- [ ] **Step 4: Save the scene.**

`mcp__godot-ai__scene_save`.

- [ ] **Step 5: Verify (post-T11 deferred).**

Bar will only render correctly after T11 wires the Stamina node onto the player. Tag this as "verified in T11".

---

### Task 6: Shovel scene + animations

**Files (created):**
- `res://scenes/shovel.tscn`
- `res://scripts/shovel.gd`

**Goal:** A `Shovel` Node3D scene containing the imported GLB mesh + an `AnimationPlayer` with three animations (`idle`, `swing`, `swing_empty`). The `swing` animation includes a call-method track that fires `_emit_hit_frame` at the strike moment.

- [ ] **Step 1: Create `scripts/shovel.gd`.**

```gdscript
extends Node3D
class_name Shovel
# Note: deliberately NOT named "Tool" — `@tool` is a Godot annotation and
# the bare class name invites confusion. When a pickaxe class arrives,
# either share a parent (e.g., MiningTool) or keep them as siblings.

@export var damage: int = 1
@export var stamina_cost: int = 10
@export var swing_duration: float = 0.7

@onready var _anim: AnimationPlayer = $AnimationPlayer
var _swinging: bool = false

signal swing_hit_frame
signal swing_started

func _ready() -> void:
	_anim.animation_finished.connect(_on_animation_finished)

func try_swing(stamina) -> bool:
	if _swinging: return false
	if not stamina.try_consume(stamina_cost):
		_anim.play("swing_empty")
		return false
	_swinging = true
	swing_started.emit()
	_anim.play("swing")
	return true

func _on_animation_finished(_name: String) -> void:
	_swinging = false
	if _anim.current_animation != "idle":
		_anim.play("idle")

# Called by AnimationPlayer call-method track at the strike frame.
func _emit_hit_frame() -> void:
	swing_hit_frame.emit()
```

- [ ] **Step 2: Create the scene.**

`mcp__godot-ai__scene_manage op="create" params={"path":"res://scenes/shovel.tscn","root_type":"Node3D","root_name":"Shovel"}`.

Then add child nodes:
- `Mesh` — instance the GLB. The cleanest path: open `res://assets/models/shovel.glb`, identify the root MeshInstance3D node name, then in `shovel.tscn` use `mcp__godot-ai__node_create` with `type="MeshInstance3D"`, parent root, name `Mesh`. Set its `mesh` property by referencing the `.mesh.tres` extracted from the GLB. (If the GLB ships with a useful mesh-only sub-resource, simpler: instance the whole GLB as a child via `node_create` with type `Node3D` and load it as a PackedScene reference. Pick whichever is cleaner given the actual GLB structure.)
- `AnimationPlayer` — `mcp__godot-ai__node_create type="AnimationPlayer" parent="." name="AnimationPlayer"`.

Attach script: `mcp__godot-ai__script_attach params={"node_path":".","script_path":"res://scripts/shovel.gd"}`.

- [ ] **Step 3: Position and scale the mesh as a view-model.**

The mesh sits in the lower-right of the camera view. Set on the `Mesh` (or wrapping Node3D):

| Property | Value |
|---|---|
| `position` | `Vector3(0.6, -0.5, -0.8)` |
| `scale` | scaled so the shovel head is roughly 0.15-0.2 units across (eyeball based on T3's bounding box reading) |
| `rotation` | `Vector3(0, deg_to_rad(-15), deg_to_rad(20))` (approximate — tune in T15) |

These values are starting points; T15's playtest is where they get nudged.

- [ ] **Step 4: Author the animations.**

Use `mcp__godot-ai__animation_create` (or `animation_manage`) to author three animations on the `AnimationPlayer`:

**`idle`** (length 1.0, loop):
- One track on `Mesh:transform`, holding the rest pose. (Just a single keyframe is fine; no actual movement for v1.)

**`swing`** (length 0.7, no loop):
- `Mesh:rotation` track with keyframes at:
  - t=0.00: rest rotation (whatever T3 rest pose was)
  - t=0.25: wind-up — rotate +30° on X (head goes up-back), +10° on Y
  - t=0.40: strike — rotate -45° on X (head snaps down-forward), -10° on Y, +5° on Z (slight side-swipe)
  - t=0.70: returned to rest
- `Mesh:position` track with subtle accompanying motion (~0.05 unit offset during the swing, snap back at t=0.70).
- **Method call track on `.` (root Shovel node)** firing `_emit_hit_frame` at **t=0.30**. This is the single most important detail in the animation; the hit only registers because of this call.

**`swing_empty`** (length 0.4, no loop):
- `Mesh:rotation` track with a small jiggle (e.g., +5° on X at t=0.10, return at t=0.30).
- **No method call track** — empty swings deal no hit.

If the available animation tools don't expose call-method tracks directly, the implementer adds them by editing the .tscn text directly: an `Animation` resource sub-resource with `tracks/N/type = "method"`, `tracks/N/path = NodePath(".")`, and the keyframe `values = [{ "method": "_emit_hit_frame", "args": [] }]`. Verify the track type by inspecting an existing call-track Animation in the project (or in Godot docs) before committing the structure.

- [ ] **Step 5: Save the scene.**

`mcp__godot-ai__scene_save`.

- [ ] **Step 6: Verify symbols.**

`mcp__godot-ai__script_manage op="find_symbols" params={"path":"res://scripts/shovel.gd"}` — confirm `class_name=Shovel`, signals `swing_hit_frame`, `swing_started` present, methods `try_swing`, `_emit_hit_frame` present.

- [ ] **Step 7: Standalone scene-play sanity check (optional).**

Open `shovel.tscn`, hit play-scene if available, watch for parser/runtime errors. Skip if blocked; full validation happens in T15.

---

### Task 7: OreDeposit base script + scene

**Files (created):**
- `res://scripts/ore_deposit.gd`
- `res://scenes/ore_deposit.tscn`

**Goal:** The reusable `OreDeposit` scene. Subclassed/configured via .tscn variants in T8.

- [ ] **Step 1: Create `scripts/ore_deposit.gd`.**

```gdscript
extends StaticBody3D
class_name OreDeposit

enum Material { STONE, IRON, GOLD }

@export var material: Material = Material.STONE
@export var stage_meshes: Array[Mesh] = []
@export var stage_scales: Array[float] = []   # per-stage MeshInstance3D scale; empty → 1.0
@export var hp_per_stage: int = 30
@export var ore_per_stage: int = 2             # used only when ore_per_stage_array is empty
@export var ore_per_stage_array: Array[int] = []  # per-stage override; matches len(stage_meshes)
@export var size_label: String = "medium"

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _hit_fx: GPUParticles3D = $HitParticles
@onready var _break_fx: GPUParticles3D = $BreakParticles

var _current_stage: int = 0
var _stage_hp_left: int

signal damaged(remaining_hp: int, stage: int)
signal chunk_broken(material: Material, ore_amount: int, stage: int)
signal depleted(material: Material)

func _ready() -> void:
	_stage_hp_left = hp_per_stage
	if stage_meshes.size() > 0:
		_mesh.mesh = stage_meshes[0]
	_mesh.scale = Vector3.ONE * _scale_for_stage(0)

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
```

- [ ] **Step 2: Create `scenes/ore_deposit.tscn`.**

`mcp__godot-ai__scene_manage op="create" params={"path":"res://scenes/ore_deposit.tscn","root_type":"StaticBody3D","root_name":"OreDeposit"}`.

Add children:
- `MeshInstance3D` — name `MeshInstance3D`. Mesh left empty (set per-stage in code at `_ready`).
- `CollisionShape3D` — name `CollisionShape3D`. Shape: a new `SphereShape3D` with `radius = 1.0` (default; presets override).
- `GPUParticles3D` — name `HitParticles`. `one_shot = true`, `emitting = false`, `amount = 8`. Configure a small dust burst:
  - Create a `ParticleProcessMaterial` sub-resource: gravity (0, -2, 0), initial velocity (1.0–2.0), spread 30°, color gray (0.6, 0.6, 0.6).
  - `lifetime = 0.4`.
  - Use a small `BoxMesh` or `QuadMesh` (0.05 units) as `draw_pass_1`.
- `GPUParticles3D` — name `BreakParticles`. Same idea but `amount = 24`, `lifetime = 0.8`, slightly larger box meshes (0.1 units), faster initial velocity (3.0–6.0). Color matches material (override per-preset in T8 — the base scene uses gray).

Set on root `OreDeposit`:
- `collision_layer = 2` (the `mining_targets` layer registered in T1; layer index 2 = bit value 2)
- `collision_mask = 0` (the deposit doesn't need to detect anything; the player's raycast does the detecting)

Attach script: `mcp__godot-ai__script_attach params={"node_path":".","script_path":"res://scripts/ore_deposit.gd"}`.

- [ ] **Step 3: Save.**

`mcp__godot-ai__scene_save`.

- [ ] **Step 4: Verify symbols.**

`mcp__godot-ai__script_manage op="find_symbols" params={"path":"res://scripts/ore_deposit.gd"}` — confirm `class_name=OreDeposit`, all 3 signals + `take_damage` method present.

---

### Task 8: Ore deposit .tscn presets (7 variants)

**Files (created):**
- `res://scenes/ore_deposits/stone_small.tscn`
- `res://scenes/ore_deposits/stone_medium.tscn`
- `res://scenes/ore_deposits/stone_large.tscn`
- `res://scenes/ore_deposits/iron_small.tscn`
- `res://scenes/ore_deposits/iron_large.tscn`
- `res://scenes/ore_deposits/gold_small.tscn`
- `res://scenes/ore_deposits/gold_large.tscn`

**Goal:** Per-material per-size variants of `ore_deposit.tscn`. Each preset bakes in: `material` enum, `hp_per_stage`, `ore_per_stage` (with bonus on final stage so totals match the spec), `stage_meshes` array (same `rock_medium.mesh.tres` repeated at decreasing scales), `MeshInstance3D` material override (gray/iron/gold), `CollisionShape3D` radius matching the stage-0 size, and `BreakParticles` color.

**Reference table** (from spec):

| Preset | Material | Stages | HP/stage | Total HP | Ore distribution | Total | Stage-0 mesh scale | Collision radius |
|---|---|---|---|---|---|---|---|---|
| stone_small | STONE | 2 | 30 | 60 | 2, 3 | 5 | 1.5 | 0.9 |
| stone_medium | STONE | 3 | 30 | 90 | 3, 3, 4 | 10 | 2.5 | 1.5 |
| stone_large | STONE | 4 | 30 | 120 | 3, 4, 4, 4 | 15 | 3.5 | 2.0 |
| iron_small | IRON | 3 | 40 | 120 | 2, 3, 3 | 8 | 1.8 | 1.1 |
| iron_large | IRON | 4 | 40 | 160 | 3, 3, 4, 4 | 14 | 3.0 | 1.8 |
| gold_small | GOLD | 3 | 50 | 150 | 3, 3, 4 | 10 | 1.8 | 1.1 |
| gold_large | GOLD | 4 | 50 | 200 | 5, 5, 5, 5 | 20 | 3.0 | 1.8 |

Stage-N mesh scale = stage-0 scale × `[1.0, 0.75, 0.5, 0.3]` for the appropriate stage count.

Each preset's `stage_meshes` is an `Array[Mesh]` — to vary the visual scale per stage, the simplest approach is to author scaled `ArrayMesh` (or `BoxMesh` etc) sub-resources, but a cleaner approach is to apply the scale via the `MeshInstance3D.scale` at stage transitions in script. **Decision for v1: store the same `Mesh` reference in every slot of `stage_meshes` and apply scaling via `MeshInstance3D.scale` in `ore_deposit.gd`.** This requires a 2-line edit to `ore_deposit.gd` from T7 — fold it in here.

- [ ] **Step 1: (Done in T7 — `stage_scales` and `ore_per_stage_array` are already in `ore_deposit.gd`.)**

Verify by re-reading `scripts/ore_deposit.gd`. If those exports are missing (e.g. T7 was implemented before this plan was updated), add them per T7's script body and re-run `find_symbols`.

- [ ] **Step 2: Pick the per-material override material approach.**

Three simple `StandardMaterial3D` resources, one per ore type. Either:
- (a) Stored as standalone `.tres` files (`res://scenes/ore_deposits/mat_stone.tres`, `mat_iron.tres`, `mat_gold.tres`) and referenced by `MeshInstance3D.material_override` in each preset.
- (b) Sub-resources baked into each preset.

Pick (a) — DRY and easier to retune. Define:

| Material | albedo | metallic | roughness |
|---|---|---|---|
| stone | (0.55, 0.55, 0.55) | 0.0 | 0.85 |
| iron  | (0.45, 0.30, 0.20) | 0.30 | 0.6 |
| gold  | (1.0, 0.78, 0.20) | 0.85 | 0.25 |

- [ ] **Step 3: Author each .tscn preset.**

For each row in the table, create a new scene that **instances** `res://scenes/ore_deposit.tscn` (so they inherit structure and stay in sync if the base changes). Override the exported properties on the root:
- `material` (enum int 0/1/2)
- `hp_per_stage`
- `stage_meshes` — array of N references to `res://assets/nature/rock_medium.mesh.tres`
- `stage_scales` — array of N floats (stage-0 scale × the falloff curve)
- `ore_per_stage` — handle the per-stage variation. Since `ore_per_stage` is an int field, the spec's varying-per-stage distribution doesn't fit a single int. **Resolution:** add a second @export `Array[int] ore_per_stage_array` to `ore_deposit.gd`; when non-empty, it overrides `ore_per_stage` per stage. Update `_break_chunk` to read from the array if set. Bake the per-preset distribution from the table here.

Override on `MeshInstance3D`: `material_override = preload("res://scenes/ore_deposits/mat_<material>.tres")`.

Override on `CollisionShape3D` → `shape` → `radius`: per the table.

Override on `BreakParticles` → ParticleProcessMaterial color: per material (the same colors as the override material's albedo work fine).

This is 7 nearly-identical .tscn files. Authoring via the MCP scene tools one-by-one is fine but slow. Faster: write the first one (`stone_small.tscn`) via MCP, then **read its text contents**, programmatically generate the other 6 by templating, write each to disk, and `reimport`. The implementer chooses whichever is cleaner per their tooling preference.

- [ ] **Step 4: Verify each preset opens cleanly.**

For each: `mcp__godot-ai__scene_open path="res://scenes/ore_deposits/<name>.tscn"`, check `mcp__godot-ai__editor_state` for parse errors, then `mcp__godot-ai__scene_get_hierarchy` to confirm the structure inherited from the base.

---

### Task 9: SurfaceRock scene

**Files (created):**
- `res://scenes/surface_rock.tscn`

**Goal:** A degenerate `OreDeposit` that takes 1 hit, yields 1 stone, 1 stage. Same script, different config.

- [ ] **Step 1: Create as an inherited scene from `ore_deposit.tscn`.**

Same pattern as T8 presets. Override the root's exports:
- `material = STONE`
- `hp_per_stage = 1`
- `ore_per_stage = 1`
- `stage_meshes = [preload("res://assets/nature/rock_small.mesh.tres")]` (smaller mesh)
- `stage_scales = [1.0]`
- `size_label = "surface"`

Override `CollisionShape3D.shape.radius = 0.4` (small).

Override `MeshInstance3D.material_override = preload("res://scenes/ore_deposits/mat_stone.tres")` (same as stone deposits; rock_small.glb already has its own bundled material — pick whichever reads better visually; default to the stone override for consistency).

`BreakParticles.amount = 6` (smaller burst since it's a tiny rock).

- [ ] **Step 2: Save and reimport.**

`mcp__godot-ai__scene_save`.

---

### Task 10: Refactor `miner.gd` — hit-frame consumer

**Files:**
- Modify: `res://scripts/miner.gd` (rewrite — old noise-classifier removed)

**Goal:** `Miner` now waits for the Shovel's `swing_hit_frame` signal, raycasts on receipt, and routes to the deposit-or-voxel branch.

- [ ] **Step 1: Read the current `miner.gd`.**

So you understand which `_terrain` / `_voxel_tool` / `_camera` lookups are reused.

- [ ] **Step 2: Replace the script contents wholesale.**

```gdscript
extends Node3D

@export var reach: float = 4.0
@export var brush_radius: float = 0.8
# Path to the Shovel under the player's Camera3D.
@export var shovel_path: NodePath = "../Camera3D/Shovel"
# Path to the Stamina node on the player.
@export var stamina_path: NodePath = "../Stamina"

@onready var _camera: Camera3D = get_node("../Camera3D")
@onready var _dirt_audio: AudioStreamPlayer3D = $DigEmitter
@onready var _ore_audio: AudioStreamPlayer3D = $OreHitEmitter
@onready var _shovel: Shovel = get_node(shovel_path)
@onready var _stamina: Stamina = get_node(stamina_path)

var _terrain: VoxelTerrain
var _player: CharacterBody3D
var _voxel_tool: VoxelTool

var stone: int = 0
var iron: int = 0
var gold: int = 0

signal inventory_changed(s: int, i: int, g: int)

func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_terrain = get_tree().root.get_node("Main/VoxelTerrain") as VoxelTerrain
	if _terrain != null:
		_voxel_tool = _terrain.get_voxel_tool()
		_voxel_tool.mode = VoxelTool.MODE_REMOVE
	_shovel.swing_hit_frame.connect(_on_hit_frame)

func _process(_delta: float) -> void:
	if Input.is_action_pressed("mine"):
		_shovel.try_swing(_stamina)

func _on_hit_frame() -> void:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var origin: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z
	var end: Vector3 = origin + forward * reach
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	# Hit both default terrain colliders and mining_targets (deposits).
	query.collision_mask = 0b11
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return  # whiff: no audio, no effect
	var collider = hit.collider
	if collider is OreDeposit:
		if not collider.chunk_broken.is_connected(_on_chunk_broken):
			collider.chunk_broken.connect(_on_chunk_broken)
		collider.take_damage(_shovel.damage)
		_ore_audio.play()
	else:
		# Plain voxel terrain — carve dirt for traversal, no inventory credit.
		if _voxel_tool != null:
			_voxel_tool.do_sphere(hit.position, brush_radius)
		_dirt_audio.play()

func _on_chunk_broken(material: int, amount: int, _stage: int) -> void:
	match material:
		OreDeposit.Material.STONE: stone += amount
		OreDeposit.Material.IRON:  iron  += amount
		OreDeposit.Material.GOLD:  gold  += amount
	inventory_changed.emit(stone, iron, gold)
```

- [ ] **Step 3: Delete the now-orphaned `ore_noise.tres` if it's no longer referenced.**

`mcp__godot-ai__filesystem_manage op="search" params={"name":"ore_noise"}` to find references. If `terrain_material.tres` or any shader still references it (the spec mentioned the underground-tint shader uses it), **leave it in place**. If nothing references it, delete it. Note the outcome here for later.

- [ ] **Step 4: Verify symbols.**

`mcp__godot-ai__script_manage op="find_symbols" params={"path":"res://scripts/miner.gd"}` — confirm `_classify`, `_ore_noise`, `gold_threshold`, `iron_threshold`, `ore_noise_seed`, `ore_noise_frequency` are GONE; `_on_hit_frame`, `_on_chunk_broken` are present.

---

### Task 11: Wire components into `player.tscn`

**Files:**
- Modify: `res://scenes/player.tscn`

**Goal:** Add the `Stamina` node, instance `Shovel` under `Camera3D`, add `OreHitEmitter`, ensure `Miner.shovel_path` and `stamina_path` resolve. **The `DigEmitter` already exists from MVP — keep it.**

- [ ] **Step 1: Open the scene.**

`mcp__godot-ai__scene_open path="res://scenes/player.tscn"`.

- [ ] **Step 2: Add `Stamina` Node.**

`mcp__godot-ai__node_create type="Node" parent="." name="Stamina"`. Attach script: `mcp__godot-ai__script_attach node_path="Stamina" script_path="res://scripts/stamina.gd"`.

- [ ] **Step 3: Instance `Shovel` under `Camera3D`.**

The cleanest tool path: edit the `.tscn` text directly to add `[node name="Shovel" parent="Camera3D" instance=ExtResource("...shovel.tscn")]`. Alternatively, `mcp__godot-ai__node_create` with `type="Node3D"` and immediately set its `scene_file_path` property — but instancing via direct text edit is more reliable.

- [ ] **Step 4: Add `OreHitEmitter` AudioStreamPlayer3D under `Miner`.**

`mcp__godot-ai__node_create type="AudioStreamPlayer3D" parent="Miner" name="OreHitEmitter"`. Set properties:
- `stream` — load `res://assets/audio/ore_hit.ogg`
- `volume_db = -16.0` (slightly louder than DigEmitter's -20 since ore-hits should feel rewarding)
- `unit_size = 1.0`
- `max_distance = 10.0`

- [ ] **Step 5: Confirm `Miner.shovel_path` and `stamina_path` exports resolve.**

After saving, `mcp__godot-ai__node_get_properties node_path="Miner"` and verify the `shovel_path` and `stamina_path` exports point to existing nodes. If the Miner script exports default to `"../Camera3D/Shovel"` and `"../Stamina"`, the relative paths should resolve from `Player/Miner` → `Player/Camera3D/Shovel` and `Player/Stamina`. Confirmed.

- [ ] **Step 6: Save.**

`mcp__godot-ai__scene_save`.

- [ ] **Step 7: Smoke test — run scene, verify no errors at startup.**

`mcp__godot-ai__project_run params={"autosave":false}`. Wait 8 seconds. `mcp__godot-ai__logs_read` — should see no parse / null-reference errors. Player should spawn with shovel visible in lower-right of camera. Stamina bar should be visible bottom-center at 100/100. Click LMB once — animation plays, stamina drops to 90, no crash. Stop the game.

---

### Task 12: SpawnGate `world_ready` signal

**Files:**
- Modify: `res://scripts/spawn_gate.gd`

**Goal:** Add a `signal world_ready` that fires once the player has been placed on the prepared terrain. `OreGenerator` (T13) listens for it.

- [ ] **Step 1: Read the current spawn_gate.gd.**

Understand the existing flow: it waits on terrain readiness, raycasts down, places the player.

- [ ] **Step 2: Add the signal declaration and emit.**

Near the top, after `extends Node`:
```gdscript
signal world_ready
```

At the bottom of whatever method completes the player-placement (after the player's transform is set), add:
```gdscript
world_ready.emit()
```

- [ ] **Step 3: Verify symbols.**

`mcp__godot-ai__script_manage op="find_symbols" params={"path":"res://scripts/spawn_gate.gd"}` — confirm signal `world_ready` listed.

---

### Task 13: OreGenerator — script + scene wiring

**Files:**
- Create: `res://scripts/ore_generator.gd`
- Modify: `res://scenes/main.tscn` (add `OreGenerator` Node3D)

**Goal:** A one-shot scatter that runs on `SpawnGate.world_ready` and instances surface rocks + underground deposits across the island.

- [ ] **Step 1: Create the script.**

```gdscript
extends Node3D
class_name OreGenerator

@export var generator_seed: int = 1337
@export var island_radius: float = 145.0
@export var underground_y_band: Vector2 = Vector2(-60.0, -2.0)

@export var surface_grid_step: float = 6.0  # spacing between surface scatter samples
@export var surface_jitter: float = 2.5     # max random offset per sample
@export var stone_deposits: int = 80
@export var iron_deposits: int = 20
@export var gold_deposits: int = 7

@export var stone_small_scn: PackedScene
@export var stone_medium_scn: PackedScene
@export var stone_large_scn: PackedScene
@export var iron_small_scn: PackedScene
@export var iron_large_scn: PackedScene
@export var gold_small_scn: PackedScene
@export var gold_large_scn: PackedScene
@export var surface_rock_scn: PackedScene

@export var voxel_terrain_path: NodePath
@export var island_generator_path: NodePath  # if you want to reuse height function

var _rng: RandomNumberGenerator
var _voxel_tool: VoxelTool

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = generator_seed

func generate() -> void:
	var terrain := get_node(voxel_terrain_path) as VoxelTerrain
	if terrain == null:
		push_error("OreGenerator: VoxelTerrain not found at " + str(voxel_terrain_path))
		return
	_voxel_tool = terrain.get_voxel_tool()
	_scatter_surface_rocks()
	_scatter_underground(stone_deposits, [stone_small_scn, stone_medium_scn, stone_large_scn])
	_scatter_underground(iron_deposits,  [iron_small_scn, iron_large_scn])
	_scatter_underground(gold_deposits,  [gold_small_scn, gold_large_scn])

func _scatter_surface_rocks() -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var grid_min: int = int(-island_radius)
	var grid_max: int = int(island_radius)
	var x: int = grid_min
	while x <= grid_max:
		var z: int = grid_min
		while z <= grid_max:
			var jx: float = _rng.randf_range(-surface_jitter, surface_jitter)
			var jz: float = _rng.randf_range(-surface_jitter, surface_jitter)
			var px: float = float(x) + jx
			var pz: float = float(z) + jz
			if sqrt(px * px + pz * pz) > island_radius:
				z += int(surface_grid_step)
				continue
			# Raycast down from high above to find ground.
			var origin := Vector3(px, 60.0, pz)
			var end := Vector3(px, -10.0, pz)
			var query := PhysicsRayQueryParameters3D.create(origin, end)
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				z += int(surface_grid_step)
				continue
			var landing: Vector3 = hit.position
			# Skip if under water (y < ~0.2 ish).
			if landing.y < 0.2:
				z += int(surface_grid_step)
				continue
			# Skip steep slopes — normal Y component must be reasonably up.
			if hit.normal.y < 0.7:
				z += int(surface_grid_step)
				continue
			var rock := surface_rock_scn.instantiate() as Node3D
			rock.position = landing
			rock.rotation.y = _rng.randf() * TAU
			add_child(rock)
			z += int(surface_grid_step)
		x += int(surface_grid_step)

func _scatter_underground(count: int, prefab_pool: Array[PackedScene]) -> void:
	var attempts: int = 0
	var placed: int = 0
	var max_attempts: int = count * 8
	while placed < count and attempts < max_attempts:
		attempts += 1
		var p: Vector3 = _random_underground_position()
		if not _is_solid_voxel(p):
			continue
		var prefab: PackedScene = prefab_pool.pick_random()
		var deposit := prefab.instantiate() as OreDeposit
		deposit.position = p
		add_child(deposit)
		placed += 1
	if placed < count:
		push_warning("OreGenerator: only placed %d of %d deposits after %d attempts" % [placed, count, attempts])

func _random_underground_position() -> Vector3:
	var theta: float = _rng.randf() * TAU
	var r: float = sqrt(_rng.randf()) * island_radius
	var x: float = cos(theta) * r
	var z: float = sin(theta) * r
	var y: float = _rng.randf_range(underground_y_band.x, underground_y_band.y)
	return Vector3(x, y, z)

func _is_solid_voxel(pos: Vector3) -> bool:
	if _voxel_tool == null: return false
	if not _voxel_tool.is_area_editable(AABB(pos - Vector3.ONE, Vector3.ONE * 2.0)):
		# Chunk not streamed yet — skip this point. (Surface scatter happens after spawn-gate
		# but underground points may still be far from streamed chunks if max_view_distance
		# is smaller than island_radius. island_radius=145 < max_view_distance=256, so we're fine.)
		return false
	return _voxel_tool.get_voxel_f(pos) < 0.0

func _on_world_ready() -> void:
	generate()
```

- [ ] **Step 2: Add `OreGenerator` node to main.tscn.**

`mcp__godot-ai__scene_open path="res://scenes/main.tscn"`. `mcp__godot-ai__node_create type="Node3D" parent="." name="OreGenerator"`. Attach script: `mcp__godot-ai__script_attach node_path="OreGenerator" script_path="res://scripts/ore_generator.gd"`.

- [ ] **Step 3: Set the export references on the OreGenerator node.**

For each `_scn` export, set the corresponding `PackedScene`:
- `stone_small_scn` → `res://scenes/ore_deposits/stone_small.tscn`
- `stone_medium_scn` → `res://scenes/ore_deposits/stone_medium.tscn`
- `stone_large_scn` → `res://scenes/ore_deposits/stone_large.tscn`
- `iron_small_scn` → `res://scenes/ore_deposits/iron_small.tscn`
- `iron_large_scn` → `res://scenes/ore_deposits/iron_large.tscn`
- `gold_small_scn` → `res://scenes/ore_deposits/gold_small.tscn`
- `gold_large_scn` → `res://scenes/ore_deposits/gold_large.tscn`
- `surface_rock_scn` → `res://scenes/surface_rock.tscn`
- `voxel_terrain_path` → `NodePath("../VoxelTerrain")`

Set via `mcp__godot-ai__node_set_property` per export, or by direct .tscn text edit.

- [ ] **Step 4: Wire `SpawnGate.world_ready` → `OreGenerator._on_world_ready`.**

The cleanest way is a connection in main.tscn's `[connection]` block:
```
[connection signal="world_ready" from="SpawnGate" to="OreGenerator" method="_on_world_ready"]
```

Add via `mcp__godot-ai__signal_manage op="connect"` if available, or by direct .tscn text edit.

- [ ] **Step 5: Save.**

`mcp__godot-ai__scene_save`.

---

### Task 14: Remove decorative rocks from `nature_library.tres`

**Files:**
- Modify: `res://scenes/nature_library.tres`

**Goal:** Stop scattering `rock_small` and `rock_medium` via `VoxelInstancer`. The new `OreGenerator` is now solely responsible for rock placement. Tree and grass entries stay.

- [ ] **Step 1: Read the current library.**

`mcp__godot-ai__filesystem_manage op="read_text" params={"path":"res://scenes/nature_library.tres"}`. Identify the entries for `rock_small` and `rock_medium` (likely numbered items 1 and 2 of the 5).

- [ ] **Step 2: Remove those entries.**

Edit the .tres text to delete the rock entries. Care: `VoxelInstanceLibrary` uses numbered IDs — removing items in the middle is fine (they're a sparse map keyed by integer ID); just delete the relevant `[sub_resource]` blocks AND the `items/N` references at the top of the file. **Do not renumber the surviving items** — the IDs are stable references.

- [ ] **Step 3: Reimport.**

`mcp__godot-ai__filesystem_manage op="reimport" params={"paths":["res://scenes/nature_library.tres"]}`.

- [ ] **Step 4: Verify in-editor.**

`mcp__godot-ai__filesystem_manage op="search" params={"name":"rock_small","type":"Mesh"}` — should still find the .mesh.tres (we only removed the library entry, not the asset). Confirm trees and grass still show in the library.

---

### Task 15: End-to-end playtest verification

**Files:** none

**Goal:** Verify the full system against the spec's success criteria. This is the gate before declaring R1 done.

- [ ] **Step 1: Stop any running play, clear logs.**

`mcp__godot-ai__project_manage op="stop"` if playing. `mcp__godot-ai__editor_manage op="logs_clear"` if available.

- [ ] **Step 2: Run the game.**

`mcp__godot-ai__project_run params={"autosave":false}`. Wait 12 seconds (the previous spawn-gate wait is 8s; OreGenerator may add a second or two).

- [ ] **Step 3: Screenshot — confirm shovel + stamina bar visible.**

`mcp__godot-ai__editor_screenshot params={"source":"game"}`. Visual check:
- Shovel mesh in lower-right of view ✓
- Stamina bar bottom-center, full ✓
- Inventory label top-left, all zeros ✓
- Surface rocks visible scattered around the island ✓

- [ ] **Step 4: Mining flow checks.**

The implementer (or a test sequence simulated via input action triggers if available) verifies:
- LMB swing → animation plays. Confirm by screenshot mid-swing.
- Surface rock: aim at one, single LMB → rock disappears (or shrinks), particle burst, +1 stone in inventory, ore-hit clink audio in logs (`mcp__godot-ai__logs_read`).
- Stamina drains 10 per swing. Hold LMB → bar drops to zero. Verify swings stop. Wait ~1s, swings resume.
- Tunnel into dirt: aim at a dirt face, hold LMB → voxel sphere carves out, no inventory change, dirt-thump audio. Confirms the fallback branch.
- Tunnel down to find an underground ore deposit (use creative-mode flight if available, or just dig). Confirm:
  - Distinct visible color (gray for stone, rust for iron, gold-yellow for gold).
  - Multiple hits required to break a single chunk.
  - Per-stage shrink + drop.
  - On final chunk break, deposit despawns.
  - Total ore credited matches preset table.

- [ ] **Step 5: Performance check.**

`mcp__godot-ai__editor_state` while playing — note FPS. Should be solid (60+ on the dev machine; any sub-30 number is a regression to investigate).

- [ ] **Step 6: Stop, capture findings.**

`mcp__godot-ai__project_manage op="stop"`. Write a brief findings note in this plan's task summary at the end of execution: what worked, what needs tuning. Numbers in the spec's tunable defaults table (swing_duration, regen rates, deposit counts, mesh scales) are first-pass guesses — surface the ones that feel wrong.

---

## Post-execution: cleanup punch list

Items the implementer may surface during execution that we deliberately deferred but should be tracked:

1. **Shovel asset swap** — the user has stated they'll source a final shovel mesh later. The placeholder GLB (or procedural primitives) can be swapped without touching shovel.gd or the animations (only the `Mesh.mesh` reference and possibly the rest-pose transform need updating).
2. **`ore_noise.tres` retention** — confirm during T10 step 3 whether anything still references this. If dead code, delete in a follow-up.
3. **Surface rock floating** — if the playtest shows distractingly many "rocks floating after dig" cases, schedule the tween-drop polish.
4. **Animation strike timing** — `swing` animation hit-frame at t=0.30 is a guess. If the visual strike point reads wrong, retune in the AnimationPlayer (no code change).
5. **Deposit visual variety** — if all-gray stone deposits look monotonous, scale the mesh more aggressively across stages or introduce a second mesh variant. Defer to a polish round.
