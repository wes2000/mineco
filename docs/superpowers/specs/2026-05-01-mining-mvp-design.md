# Mine Co. — Mining MVP

**Date:** 2026-05-01
**Project:** Mine Co. (Godot 4.6 module build with Voxel Tools 1.6, Forward+, D3D12)
**Status:** Approved by user, ready for implementation

## Goal

Add the core mining loop to the existing walkable island: click to carve voxel terrain, classify what was mined into one of three materials (stone/iron/gold) via 3D noise, increment a per-material counter, show counters in a HUD. Materials are NOT visible on the surface — players discover ore by digging.

This is the first round that actually uses the voxel SDF terrain for what we built it for. Everything before this has been "walking around a pretty island"; this round adds a verb.

## Non-goals (this round)

- **Persistence** — terrain edits + inventory reset on game restart. Adding `VoxelStreamSQLite` is a separate round.
- **Visible ore deposits** — surface looks identical regardless of what's underneath. Visual hints come in a polish round.
- **Per-material sounds** — one generic dig thump for all materials.
- **Tools / pickaxe upgrades / durability**
- **Inventory limits / storage / crafting / resource sinks**
- **Different brush shapes or sizes** — single fixed sphere brush.
- **Particle / dust effect on dig**
- **Visual brush cursor / aim indicator** — center-of-screen aim is enough for FPS.
- **Reach upgrades, tier gating, depth-based progression**

## Architecture overview

Three independent components composed via signals:

1. **`Miner`** — Node3D under Player. Handles raycast aim, dig action, classification via 3D noise, inventory state. Emits `inventory_changed(stone, iron, gold)` signal on each dig.
2. **`InventoryHUD`** — Label in a CanvasLayer in main.tscn. Subscribes to Miner's signal, formats and displays the counts.
3. **Audio** — `AudioStreamPlayer3D` child of Miner, plays a CC0 dig thump on every successful dig.

No shared state, no autoload. Miner is the source of truth for inventory; HUD just observes it.

## Project structure changes

```
res://
  scripts/
    miner.gd                  — NEW: raycast + dig + classify + inventory
    inventory_hud.gd          — NEW: subscribes to Miner.inventory_changed
  scenes/
    main.tscn                 — modified: add CanvasLayer + Label child for HUD
    player.tscn               — modified: add Miner Node3D + DigEmitter children
  assets/audio/
    mine_thump.ogg            — NEW: short CC0 dig thud (~150ms)
  project.godot               — modified: add `mine` input action (left mouse button)
```

Two new scripts, two scene modifications, one new audio file, one input map entry. No new shaders, no addons, no autoloads.

## Component: `Miner` script

`scripts/miner.gd`:

```gdscript
extends Node

@export var reach: float = 4.0
@export var brush_radius: float = 0.8
@export var dig_cooldown: float = 0.25
@export var ore_noise_seed: int = 42
@export var ore_noise_frequency: float = 0.05
# Thresholds map noise [-1, 1] to material. Stats (uniform simplex):
# > 0.8 ≈ 10% gold; > 0.3 ≈ 35% (so iron is ~25%); else stone (~65%).
@export var gold_threshold: float = 0.8
@export var iron_threshold: float = 0.3

@onready var _camera: Camera3D = get_node("../Camera3D")
@onready var _audio: AudioStreamPlayer3D = $DigEmitter

var _terrain: VoxelTerrain
var _player: CharacterBody3D
var _voxel_tool: VoxelTool
var _ore_noise: FastNoiseLite
var _cooldown_left: float = 0.0

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
	_ore_noise = FastNoiseLite.new()
	_ore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ore_noise.seed = ore_noise_seed
	_ore_noise.frequency = ore_noise_frequency
	# NOTE: do NOT emit inventory_changed in _ready. Scene-tree _ready order between
	# /Player/Miner and /HUD/InventoryLabel is non-deterministic — HUD reads initial
	# state directly from miner properties in its own _ready instead.

func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	if Input.is_action_pressed("mine") and _cooldown_left <= 0.0 and _voxel_tool != null:
		_try_dig()

func _try_dig() -> void:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var origin: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z
	var end: Vector3 = origin + forward * reach
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return

	var pos: Vector3 = hit.position
	_voxel_tool.do_sphere(pos, brush_radius)

	var material: String = _classify(pos)
	match material:
		"stone": stone += 1
		"iron": iron += 1
		"gold": gold += 1
	inventory_changed.emit(stone, iron, gold)
	_audio.play()
	_cooldown_left = dig_cooldown

func _classify(pos: Vector3) -> String:
	if pos.y > 0.0:
		return "stone"
	var n: float = _ore_noise.get_noise_3d(pos.x, pos.y, pos.z)
	if n > gold_threshold:
		return "gold"
	elif n > iron_threshold:
		return "iron"
	else:
		return "stone"
```

Notes:
- **Camera + terrain references are looked up at `_ready`**. Camera is the sibling Camera3D under the Player. Terrain is at the absolute scene path `/root/Main/VoxelTerrain` — hardcoded path is fine for an MVP; if main.tscn restructures, this script needs updating.
- **VoxelTool mode**: `MODE_REMOVE` is the carve operation. Set per-call (cheap; Voxel Tools doesn't recommend caching the tool across frames).
- **Raycast excludes player** so we don't dig at the player's own collider when looking down at our feet.
- **3D noise**: simplex noise sampled at the dig position. Same position → same noise value, so veins are stable. Frequency 0.05 → ~20m wavelength.
- **Surface dirt → stone**: simplifies the classification. If the user wants surface to yield nothing, change the early-return to `return ""` and skip increments for empty.
- **Initial signal emit** on `_ready()` lets the HUD show "0 / 0 / 0" without needing its own initialization logic.

## Component: `InventoryHUD` script

`scripts/inventory_hud.gd`:

```gdscript
extends Label

@export var miner_path: NodePath = "/root/Main/Player/Miner"

func _ready() -> void:
	var miner: Node = get_node_or_null(miner_path)
	if miner == null:
		push_error("InventoryHUD: Miner not found at " + str(miner_path))
		return
	miner.inventory_changed.connect(_on_changed)
	# Read initial state directly — sidesteps _ready ordering between Miner and HUD.
	_on_changed(miner.stone, miner.iron, miner.gold)

func _on_changed(s: int, i: int, g: int) -> void:
	text = "Stone: %d   Iron: %d   Gold: %d" % [s, i, g]
```

Attached to a `Label` node inside a `CanvasLayer` in main.tscn:

```
[node name="HUD" type="CanvasLayer" parent="."]

[node name="InventoryLabel" type="Label" parent="HUD"]
offset_left = 20.0
offset_top = 20.0
offset_right = 400.0
offset_bottom = 60.0
text = "Stone: 0   Iron: 0   Gold: 0"
script = ExtResource("inventory_hud_script")
```

The `text = "..."` initial value is a fallback for if signal connection misfires; Miner's `_ready` emits an immediate update once the connection is live.

If readability is poor over varied terrain, the implementer adds a semi-transparent dark `StyleBoxFlat` background via `theme_override_styles/normal`. Out of scope for v1 unless visibly broken.

## Component: Audio

Single file `assets/audio/mine_thump.ogg`. CC0 short (~100-200ms) dig/pickaxe-thud sound. Sourced manually via WebSearch / Pixabay / OpenGameArt / gamesounds.xyz, same workflow as the R4 audio files.

`DigEmitter` is an `AudioStreamPlayer3D` child of the Miner node:

```
[node name="DigEmitter" type="AudioStreamPlayer3D" parent="Miner"]
stream = ExtResource("mine_thump")
unit_size = 1.0
max_distance = 10.0
volume_db = -6.0
```

Tight near-field (1m unit_size, 10m cutoff) — same pattern as R4's StepEmitter. Loud at the player, doesn't carry across the map.

## Component: Input action

Add `mine` action to `project.godot` `[input]` section. Minimal form (Godot's parser fills in defaults for unspecified fields):

```
mine={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"device":-1,"button_index":1,"pressed":false,"script":null)
]
}
```

`button_index = 1` is left mouse button. After editing project.godot, the user must do **Project → Reload Current Project** (same as v1 input map setup) for the new action to register.

## Behavior boundaries

- **Reach 4m** — raycast distance from camera. Beyond this, player must walk closer.
- **Brush 0.8m radius** — sphere of ~2 m³ carved per click.
- **Cooldown 0.25s** when held → ~4 digs/sec smoothly.
- **Dig anywhere** — surface or underground; surface dirt yields stone (simplification).
- **Voxel bounds** are y=[-100, 100]. Player can dig a 100m shaft straight down before hitting the bounds floor.
- **Material rates per dig**: noise threshold > 0.5 → gold (~5% of underground volume), > 0.1 → iron (~25%), else stone (~70%). Tunable via thresholds.

## Risks and open questions

1. **VoxelTool API names verified**. `mode` is the property; `MODE_REMOVE` is the constant; `do_sphere(pos, radius)` is the method. Voxel Tools 1.6 docs confirmed during spec review.

2. **Raycast hits the player's own collider** if not excluded. Mitigation in the script: `query.exclude = [_player.get_rid()]`.

3. **Camera-relative raycast**: uses `-camera.global_transform.basis.z` for forward direction. Standard for FPS — the player's first-person camera Z-axis points "out the back of head" so we negate it.

4. **HUD readability** against bright/varied backgrounds. Not addressed in v1 design; tunable as styling in playtest.

5. **Initial signal emit at `_ready()`** ensures HUD starts at "0 / 0 / 0". If `_ready` order is wrong (HUD's `_ready` runs before Miner's), the initial emit might fire before HUD has subscribed. **Mitigation:** Miner emits AGAIN on `_process` first frame... actually that's fragile. Simpler: HUD reads initial values directly from miner properties on `_ready`:
   ```gdscript
   _on_changed(miner.stone, miner.iron, miner.gold)
   ```
   after connecting. Update HUD script accordingly during implementation.

6. **Noise classification at sphere centers vs sphere volume**. The script classifies at the raycast hit position (the sphere center). The actual carved sphere may straddle a boundary in noise space — the player removes some "stone" voxels and some "iron" voxels but only gets +1 of one type. Acceptable simplification; future polish could integrate noise across the sphere.

7. **`get_voxel_tool()` returning null** if terrain isn't fully ready. Mitigation: the dig action checks `_terrain != null` and the `_try_dig` early-returns on no raycast hit. If `get_voxel_tool()` returns null specifically, an error log on dig would be helpful but not blocking.

8. **Mining the same chunk faster than meshing can keep up**. `do_sphere` schedules the carve for the next frame's mesh rebuild. Multiple digs in 0.25s spans several frames so chunks have time to update. No issue at 4 Hz dig rate.

9. **Foliage instances after carving** — `VoxelInstancer` scatters foliage based on the terrain surface state when the chunk was first streamed. After digging, the underlying surface changes but pre-existing instances do NOT retroactively delete or re-place. Visual quirk: floating grass/rocks/trees over carved holes until that chunk re-streams (which happens when the player walks far enough away and back). Acceptable for MVP — addressed in a later round (force chunk re-stream on edit or filter instances against the new SDF).

## Out of scope (deferred)

- Persistence — terrain edits + inventory survive game restart (`VoxelStreamSQLite` + saved inventory JSON)
- Visible ore deposits on surface
- Per-material dig sounds
- Visual brush cursor / aim crosshair
- Pickaxe / tool tier system
- Inventory caps, storage chests, crafting recipes
- Resource sinks (anything that USES collected materials)
- Cube / cylinder brush shapes
- Mining-particle dust effect
- HUD polish: icons per material, animated counters, fade-in
- Mining-rate upgrades
- Day/night cycle, weather, etc. (other systems)

## Success criteria

- Walk up to terrain, hold left-click, hear thumps and watch a hole grow.
- HUD top-left shows three counters incrementing.
- After 30+ digs underground, mix of stone (~70%), iron (~25%), gold (~5%).
- Frame rate stays solid during continuous mining.
- Restart game: world refills (no persistence), counters back to zero, no errors.
