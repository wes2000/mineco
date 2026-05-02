# Mine Co. — Mining Depth R1: Shovel, Stamina, Ore Deposits

**Date:** 2026-05-02
**Project:** Mine Co. (Godot 4.6 module build with Voxel Tools 1.6, Forward+, D3D12)
**Status:** Approved by user, ready for implementation planning
**Builds on:** `2026-05-01-mining-mvp-design.md` (the existing instant-dig classifier)

## Goal

Replace the MVP "click to instantly carve voxels and roll a noise function for what you got" with a tool-based mining loop:

- A visible shovel held in the camera with a real swing animation.
- A stamina bar that prevents holding LMB indefinitely.
- Surface rocks that take one swing for +1 stone (grass and dirt give nothing — the dirt-tunneling action is preserved as traversal-only).
- Underground ore as **discrete entity deposits** — visible boulders that take many shovel hits, break in stages, and yield 5–20 ore total over their lifetime.
- A distinct audio cue when hitting an ore deposit vs. plain dirt.
- A damage-and-HP model so future tool tiers (pickaxe, etc.) just bump `tool.damage` and every deposit takes proportionally fewer swings.

This round adds **depth and weight** to the verb. After this, mining feels like a deliberate activity rather than a noise-roll.

## Non-goals (this round)

- **Persistence** — mined deposits respawn on game restart. (Same constraint as the MVP round.)
- **Pickaxe / tool tier system.** Only the shovel exists. `Tool.damage` is the only knob.
- **Tier-locking** (e.g., "gold requires X tool to register damage"). Shovel can hit anything; gold just takes far more swings.
- **Physical chunk pickups** as `RigidBody3D`s. Ore credit is instant on chunk-break, with a particle flourish.
- **Sprint stamina interaction.** No sprint exists yet.
- **Empty-stamina audio cue.** Visible bar drain reads clearly enough.
- **Variant ore-hit audio samples.** Single CC0 file; layer variants later if it sounds repetitive.
- **Floating-rock land-on-dig polish.** Surface rocks remain `StaticBody3D` and visually float if you carve the dirt out from under them. Mining them removes them.
- **Authored cracked stage meshes.** Stage transitions are scale-and-jiggle on a single mesh.
- **View-model bob, head-bob coupling.**
- **Visual brush cursor / aim crosshair.** (Same as MVP — center-of-screen aim is enough.)

## Architecture overview

Six independent components composed via signals + node references. Each has one clear job and can be reasoned about without holding the others in your head.

1. **`Tool` (Shovel)** — held weapon view-model under the camera. Owns the swing animation, the per-swing damage value, and emits `swing_started` / `swing_hit_frame` signals. Replaces the MVP's "input → instant dig" model.
2. **`Miner`** *(refactored)* — listens to `swing_hit_frame`, raycasts at the moment of impact, looks up what was hit (ore deposit, surface rock, plain voxel terrain), routes the hit. No more direct voxel carving on input. Still owns the inventory counters and `inventory_changed` signal.
3. **`Stamina`** — pure model node on the player. Tracks current/max, exposes `try_consume(amount) -> bool`, emits `stamina_changed`. Tool asks Stamina before swinging; Stamina handles regen + post-swing delay internally.
4. **`OreDeposit`** — `StaticBody3D` placed by the OreGenerator. Owns: material type (stone/iron/gold), HP, current break-stage, total-yield. Receives `take_damage(amount)`. Manages stage transitions, mesh swaps, particle bursts, ore credit emission.
5. **`SurfaceRock`** — degenerate `OreDeposit` config: 1 HP, 1 stage, 1 stone, no transitions. Same hit pipeline.
6. **`OreGenerator`** — runs once after the player's spawn-gate completes. Scatters surface rocks across the island, seeds underground deposits via random sampling within the island radius and a y-band [−60, −2]. Replaces the rock entries in `nature_library.tres`.

Plus three small additions: a `StaminaBar` HUD node, an `OreHitEmitter` audio player on Miner, and a `mining_targets` physics layer.

### Data flow on a single swing

```
Input.mine pressed
  -> Tool.try_swing(stamina)
    -> Stamina.try_consume(10) -> false? -> abort, play "swing_empty"
    -> AnimationPlayer.play("swing")
       (~0.30s into the animation, an anim track call-method fires)
    -> Tool.swing_hit_frame.emit()
      -> Miner._on_hit_frame()
        -> raycast from camera, mining_targets layer first, then default
        -> hit OreDeposit?  -> deposit.take_damage(tool.damage)
                                -> maybe stage transition, maybe credit ore
        -> hit raw voxel?   -> _voxel_tool.do_sphere(hit_pos, brush_radius)
                                -> no inventory credit; play dirt-thump
        -> hit nothing?     -> no audio, no effect (whiff)
```

Voxel carving is preserved as a fallback so you can still tunnel through dirt to reach deposits — you just don't get anything for the dirt.

## Project structure changes

```
res://
  scripts/
    shovel.gd                      NEW: Tool (held shovel, swing animation owner)
    stamina.gd                     NEW: Stamina model
    stamina_bar.gd                 NEW: HUD bar mirror of Stamina
    ore_deposit.gd                 NEW: take_damage / stage / chunk_broken
    ore_generator.gd               NEW: scatter on world spawn
    miner.gd                       MODIFIED: replace dig-on-input with hit-frame consumer
    spawn_gate.gd                  MODIFIED: emit world_ready signal
  scenes/
    shovel.tscn                    NEW (uses CC0 GLB)
    ore_deposit.tscn               NEW (base scene)
    surface_rock.tscn              NEW (degenerate variant)
    ore_deposits/                  NEW directory of 7 .tscn presets
      stone_small.tscn, stone_medium.tscn, stone_large.tscn,
      iron_small.tscn, iron_large.tscn,
      gold_small.tscn, gold_large.tscn
    player.tscn                    MODIFIED: add Stamina, Shovel under Camera3D, OreHitEmitter
    main.tscn                      MODIFIED: add StaminaBar to HUD, add OreGenerator node
    nature_library.tres            MODIFIED: remove rock_small + rock_medium scatter entries
  assets/
    audio/ore_hit.ogg              NEW: CC0 metal-on-stone clink, ~100-250ms
    models/shovel.glb              NEW: CC0 sourced shovel mesh
  project.godot                    MODIFIED: add named physics layer "mining_targets"
```

## Component: `Tool` (Shovel)

**Scene:** `scenes/shovel.tscn`, instanced under `Player/Camera3D`.

```
Shovel (Node3D)
├── Mesh (MeshInstance3D — CC0 GLB)
└── AnimationPlayer
    └── animations: "idle", "swing", "swing_empty"
```

**Script:** `scripts/shovel.gd`

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

func try_swing(stamina) -> bool:
    if _swinging: return false
    if not stamina.try_consume(stamina_cost):
        _anim.play("swing_empty")
        return false
    _swinging = true
    swing_started.emit()
    _anim.play("swing")
    return true

func _on_swing_animation_finished(_name: String) -> void:
    _swinging = false
    _anim.play("idle")

# Called by AnimationPlayer call-method track at the strike frame.
func _emit_hit_frame() -> void:
    swing_hit_frame.emit()
```

**Animations** authored in the AnimationPlayer:

- `idle` — shovel rests in lower-right of view. Static for v1; subtle bob can come later.
- `swing` — 0.7s total: wind-up over ~0.25s (back-up), strike over ~0.15s (snap down-forward; **call-method `_emit_hit_frame` fires at t=0.30s**), recovery over ~0.30s (return to idle).
- `swing_empty` — 0.4s: shovel jiggles up slightly then drops. No `_emit_hit_frame` call. Plays the "tired" feel without a hit.

**Why hit-frame, not raycast-on-input:** the player's hit registers when the shovel head visually lands, not when the button is pressed. Standard for weighty melee animations. The animation track owns the timing; the script just listens.

**View-model rendering:** the shovel mesh sits at roughly `Transform3D(0.6, -0.5, -0.8)` from camera origin, scale ~0.4, placed lower-right of view. Rendered on a separate `VisualLayer` mask so the camera's near-plane doesn't clip it. Standard FPS view-model setup; the camera's cull mask and the shovel's `layers` get tuned during implementation.

**CC0 model sourcing:** Quaternius / Kenney / OpenGameArt search for a permissively licensed shovel GLB. If nothing decent surfaces in ~10 minutes, fall back to procedural primitives (cylinder handle + box head). User has stated they will swap the asset later. Either way the rest of the system works unchanged.

## Component: `Stamina`

**Script:** `scripts/stamina.gd`, attached to a `Stamina` Node child of Player.

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

### Behavior

- 100/100 at spawn.
- Each successful swing costs 10 → instantly visible drop.
- Regen pauses for 0.8s after every swing, then refills at 30/sec → ~3.3s for empty→full.
- When `try_consume` fails for any reason (zero stamina, or under cost), `_empty_lockout` flips on. Bar regens but `try_consume` keeps refusing until `current >= min_resume_threshold` (20). Prevents one-swing-per-regen-tick stuttering near zero.
- Stamina has zero coupling to anything else. Future systems (sprint, power-attacks) call `try_consume(N)` with their own cost.

### Stamina HUD

`scenes/main.tscn`:

```
HUD (CanvasLayer)
├── InventoryLabel  [existing]
└── StaminaBar (Control)
    └── ProgressBar (centered horizontally near bottom)
```

`scripts/stamina_bar.gd` connects to Player's `Stamina` node, mirrors `current/max_value` to `ProgressBar.value`. Bottom-center, ~300px wide, ~16px tall, yellow fill, dark background. Standard `ProgressBar` styling.

### Wiring

Tool's `try_swing(stamina)` is called from Miner's `_process`:

```gdscript
if Input.is_action_pressed("mine"):
    _tool.try_swing(_stamina)
```

## Component: `OreDeposit` and `SurfaceRock`

This is the core of the new mining loop. Everything you swing at goes through here.

**Scene:** `scenes/ore_deposit.tscn`

```
OreDeposit (StaticBody3D, collision_layer = mining_targets)
├── CollisionShape3D (sphere, radius scales with deposit size)
├── MeshInstance3D
├── HitParticles (GPUParticles3D, one_shot, dust burst)
└── BreakParticles (GPUParticles3D, one_shot, larger chunk burst)
```

**Script:** `scripts/ore_deposit.gd`

```gdscript
extends StaticBody3D
class_name OreDeposit

enum Material { STONE, IRON, GOLD }

@export var material: Material = Material.STONE
@export var stage_meshes: Array[Mesh] = []   # index = stage; size = stage count
@export var hp_per_stage: int = 30
@export var ore_per_stage: int = 2
@export var size_label: String = "medium"    # informational only

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
    _mesh.mesh = stage_meshes[0]

func take_damage(amount: int) -> void:
    _stage_hp_left -= amount
    _hit_fx.restart()
    damaged.emit(_stage_hp_left, _current_stage)
    if _stage_hp_left <= 0:
        _break_chunk()

func _break_chunk() -> void:
    _current_stage += 1
    _break_fx.restart()
    chunk_broken.emit(material, ore_per_stage, _current_stage - 1)
    if _current_stage >= stage_meshes.size():
        depleted.emit(material)
        queue_free()
    else:
        _mesh.mesh = stage_meshes[_current_stage]
        _stage_hp_left = hp_per_stage
```

### Stage mesh authoring

For v1, "stage meshes" are *the same boulder mesh at progressively smaller scales*. A 4-stage stone large becomes the same mesh at scale 1.0, 0.75, 0.5, 0.3. Each break also nudges Y down a tiny random amount so the deposit visibly drops as it shrinks. Far easier than authoring distinct cracked variants and reads correctly enough — the player sees the deposit shrink in chunks at each break.

If we later author fractured variants (Blender Cell Fracture or hand-modeled), we swap the mesh array contents. No script change.

### Material visual differentiation

- **Stone:** existing `rock_medium.glb` (re-purposed, scaled up 1.5–3×), default gray PBR.
- **Iron:** same mesh, reddish-brown / rust-tinted PBR override material.
- **Gold:** same mesh, golden-yellow PBR override with high metallic + low roughness.

One mesh, three material overrides. Trivial to swap in custom geometry per material later.

### Tres presets

Each entry in `scenes/ore_deposits/` is a `PackedScene` that pre-bakes the right material override, hp_per_stage, ore_per_stage, stage_meshes (correctly scaled), and collision radius:

| Preset | Stages | HP/stage | Total HP | Ore/stage | Total ore |
|---|---|---|---|---|---|
| stone_small | 2 | 30 | 60 | 2.5* | 5 |
| stone_medium | 3 | 30 | 90 | 3.3* | 10 |
| stone_large | 4 | 30 | 120 | 3.75* | 15 |
| iron_small | 3 | 40 | 120 | 2.7* | 8 |
| iron_large | 4 | 40 | 160 | 3.5* | 14 |
| gold_small | 3 | 50 | 150 | 3.3* | 10 |
| gold_large | 4 | 50 | 200 | 5 | 20 |

*Since `ore_per_stage` is an int but the totals require fractional averages, the .tres presets store integer ore-per-stage and a small remainder bonus on the final stage so totals match (e.g., stone_medium = 3, 3, 4 → 10). The implementer picks the exact distribution per preset; the design just fixes the total.

### SurfaceRock

`scenes/surface_rock.tscn` uses the same `OreDeposit` script with:

- `material = STONE`
- `hp_per_stage = 1`
- `ore_per_stage = 1`
- `stage_meshes = [single mesh]` (one stage)

One swing → one break → +1 stone → free deposit. No code branching. The "1-hit surface rock" and "200-HP gold deposit" share the exact same `take_damage → _break_chunk → depleted` path.

### Miner consumes the signals

In `scripts/miner.gd`, refactored on-hit-frame handler:

```gdscript
func _on_hit_frame() -> void:
    var hit := _raycast_at_camera_forward()
    if hit.is_empty():
        return
    var collider = hit.collider
    if collider is OreDeposit:
        if not collider.chunk_broken.is_connected(_on_chunk_broken):
            collider.chunk_broken.connect(_on_chunk_broken)
        collider.take_damage(_tool.damage)
        _ore_hit_audio.play()
    else:
        # Plain voxel terrain
        _voxel_tool.do_sphere(hit.position, brush_radius)
        _dirt_hit_audio.play()

func _on_chunk_broken(material: int, amount: int, _stage: int) -> void:
    match material:
        OreDeposit.Material.STONE: stone += amount
        OreDeposit.Material.IRON:  iron  += amount
        OreDeposit.Material.GOLD:  gold  += amount
    inventory_changed.emit(stone, iron, gold)
```

### Why this design

- One script handles every minable thing. Surface rocks ARE ore deposits, just degenerate ones.
- `Tool.damage` is the only knob to upgrade later — replace shovel with pickaxe at `damage=5`, every deposit takes 1/5 the swings. The HP table never changes.
- All visual state (current mesh, particles) lives on the deposit. Miner doesn't care; it just calls `take_damage`.

## Component: `OreGenerator`

`scripts/ore_generator.gd`, attached to a new `OreGenerator` Node3D in `main.tscn`.

Runs **once**, after the existing `SpawnGate` finishes placing the player on the readied terrain.

```gdscript
extends Node3D
class_name OreGenerator

@export var seed: int = 1337
@export var island_radius: float = 145.0
@export var underground_y_band: Vector2 = Vector2(-60.0, -2.0)

@export var surface_rocks_per_100m2: float = 0.6
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

var _rng: RandomNumberGenerator
var _voxel_tool: VoxelTool

func _ready() -> void:
    _rng = RandomNumberGenerator.new()
    _rng.seed = seed

func generate() -> void:
    var terrain := get_node(voxel_terrain_path) as VoxelTerrain
    _voxel_tool = terrain.get_voxel_tool()
    _scatter_surface_rocks()
    _scatter_underground(stone_deposits, [stone_small_scn, stone_medium_scn, stone_large_scn])
    _scatter_underground(iron_deposits,  [iron_small_scn, iron_large_scn])
    _scatter_underground(gold_deposits,  [gold_small_scn, gold_large_scn])

func _scatter_surface_rocks() -> void:
    # Sample a square grid over the island, jitter, raycast down to find surface,
    # confirm ground is solid (not water), instance surface_rock_scn there.
    ...

func _scatter_underground(count: int, prefab_pool: Array[PackedScene]) -> void:
    var attempts: int = 0
    var placed: int = 0
    while placed < count and attempts < count * 8:
        attempts += 1
        var p := _random_underground_position()
        if not _is_solid_voxel(p): continue
        var prefab: PackedScene = prefab_pool.pick_random()
        var deposit := prefab.instantiate() as OreDeposit
        deposit.position = p
        add_child(deposit)
        placed += 1

func _random_underground_position() -> Vector3:
    var theta: float = _rng.randf() * TAU
    var r: float = sqrt(_rng.randf()) * island_radius
    var x: float = cos(theta) * r
    var z: float = sin(theta) * r
    var y: float = _rng.randf_range(underground_y_band.x, underground_y_band.y)
    return Vector3(x, y, z)

func _is_solid_voxel(pos: Vector3) -> bool:
    return _voxel_tool.get_voxel_f(pos) < 0.0   # SDF negative = solid
```

Surface scatter uses a downward raycast at each grid sample to find the ground; ignores points over water and points where slope is too steep. Underground scatter uses the voxel SDF to confirm the position is inside solid rock so deposits never spawn in air pockets.

### Decorative rock removal

`nature_library.tres` currently scatters `rock_small` and `rock_medium` via `VoxelInstancer`. Their entries are removed from the library — the GLB asset files stay (we still use the meshes inside `OreDeposit` scenes). Tree and grass entries are untouched. The new `OreGenerator` is now solely responsible for rock placement.

### Floating-rock mitigation

A surface rock's transform is fixed at world-gen. If the player digs out the dirt under one, it appears to float on its `StaticBody3D` collider. v1 acceptable behavior:

- The rock stays put (it is `StaticBody3D`); it never falls. Visually it floats; mining it removes it.
- Optional polish (deferred): one-shot tween drop when the supporting voxels go SDF-positive. Skip until playtest demands it.

## Audio: distinguishing ore-hit from dirt-dig

Two `AudioStreamPlayer3D` nodes on Miner:

- `DigEmitter` — *(existing)* — plays `mine_thump.ogg` when raycast hits raw voxel terrain (dirt-tunnel mining, no inventory credit).
- `OreHitEmitter` — **new** — plays `ore_hit.ogg` (CC0: sharp metal-on-stone "clink" / pickaxe-chink, 100–250ms) when raycast hits any `OreDeposit` (surface rock or underground).

Sourced via the same workflow as `mine_thump.ogg`; the project has the precedent in the R4 ambient audio spec.

If a single ore-hit sample sounds repetitive under sustained mining, it's a 5-line change to load 3 variants and `pick_random()`. Defer until playtest says it's needed.

Empty-stamina swings: no separate sound for v1.

## Project plumbing changes

### Physics layer

`project.godot`: add a named physics layer `mining_targets` (e.g., layer index 2). Every `OreDeposit` scene sets `collision_layer` to include that layer. Player's raycast probes both `default` and `mining_targets`. Lets the script's `is OreDeposit` test confirm hits cheaply rather than per-frame mask juggling.

### Input map

`mine` action stays bound to LMB (already exists from MVP). No changes.

### `SpawnGate`

`scripts/spawn_gate.gd` adds:

```gdscript
signal world_ready
```

emitted once the player has been placed on the prepared terrain. `OreGenerator._ready` connects to it and calls `generate()` on receipt.

### `miner.gd` cleanup

- Remove the inline noise-classification (`_classify`, `ore_noise_seed`, `gold_threshold`, `iron_threshold`, the FastNoiseLite instance).
- Replace input-handling block: instead of "input → cooldown check → do_sphere → classify → increment → emit → audio", install a `swing_hit_frame` listener on the Tool and route hits as shown in the OreDeposit section.
- Inventory counters and the `inventory_changed` signal stay (they are the API the HUD already listens to).
- The `ore_noise.tres` resource and the terrain-shader sampling stay — they still tint the underground voxel walls so dug-out areas hint at "this region is ore-rich" even though those colors no longer drive inventory. Cheap visual signal at zero ongoing cost. Reviewable if it conflicts with the new entity-deposit visuals during playtest.

## Behavior boundaries and tunable defaults

| Knob | Default | Notes |
|---|---|---|
| `Tool.damage` | 1 | Shovel only; pickaxe later changes this |
| `Tool.stamina_cost` | 10 | Per-swing flat |
| `Tool.swing_duration` | 0.7s | Animation length; hit-frame at t=0.30s |
| `Stamina.max_value` | 100 | |
| `Stamina.regen_per_second` | 30 | Empty → full in ~3.3s |
| `Stamina.regen_delay_after_swing` | 0.8s | Forces a real pause |
| `Stamina.min_resume_threshold` | 20 | Anti-stutter when near-empty |
| `Miner.brush_radius` | 0.8 | Voxel carve radius (dirt only — unchanged from MVP) |
| `OreGenerator.island_radius` | 145.0 | Scatter limit |
| `OreGenerator.underground_y_band` | (-60, -2) | Where deposits live |
| `OreGenerator.stone_deposits` | 80 | |
| `OreGenerator.iron_deposits` | 20 | |
| `OreGenerator.gold_deposits` | 7 | |
| `surface_rocks_per_100m2` | 0.6 | Tune to match prior decorative density |

### Mining-time intuition

- Small stone deposit: 60 swings × 0.7s/swing + stamina pauses ≈ ~45s for 5 stone.
- Large gold deposit: 200 swings ≈ ~3 minutes of focused mining for 20 gold. A real milestone.
- Surface rock: 1 swing → +1 stone. Plentiful.

These numbers are intentional — the shovel is the **starter** tool, deliberately inefficient long-term.

## Risks and open questions

1. **Camera near-plane clipping the view-model.** Default Godot camera near=0.05 is generous, but a shovel held at z=-0.8 from camera origin can clip the wall when standing close. Mitigations during implementation: separate visual layer for the view-model with the camera's main pass excluding it and a second small pass rendering it on top, or simply tune transform/scale so it sits within near-plane comfortably. Standard FPS problem; pick whichever is cleanest in Godot 4.6.

2. **AnimationPlayer call-method track ordering.** The `_emit_hit_frame` track must fire AT the correct keyframe time, not at animation start or end. AnimationPlayer call-tracks fire in scheduled order but if `swing_empty` is started during a partial `swing` (rapid LMB taps that fail stamina), an old call-track might still fire late. Mitigation: `_swinging` guard in `try_swing` blocks new swings until `animation_finished` clears it.

3. **`get_voxel_tool()` returning null** if terrain isn't fully ready. Already a known issue from MVP; same mitigation: Miner's `_voxel_tool != null` check before using it. OreGenerator runs after `SpawnGate.world_ready`, by which time the terrain *is* ready and `get_voxel_tool()` should return non-null. Defensive null check still warranted.

4. **Underground deposit visibility.** Deposits are placed inside solid voxel rock. The player can't see them until they dig nearby. By design: discovery IS the gameplay. But the underlying rock around a deposit needs to be carve-able with the dirt-fallback (no inventory credit) so the player can reveal and reach the deposit. Verified by the `if collider is OreDeposit ... else _voxel_tool.do_sphere(...)` branch — anything that isn't a deposit is treated as carveable terrain.

5. **Deposit sitting partly inside an air pocket.** Voxel SDF check (`get_voxel_f < 0`) is taken at the deposit's center. The deposit mesh radius might extend into a nearby cavity or above the SDF surface for a deposit placed near `y = -2`. Likely visually fine — the deposit is just embedded in rock with a tiny exposed face — and once the player tunnels in they fully see it. If playtest shows weird half-buried deposits at the y-band edge, narrow the y-band or rerun the SDF check at offset points around the deposit center.

6. **OreGenerator running before all terrain chunks are streamed.** The `bounds = AABB(-208, -112, -208, 416, 224, 416)` voxel terrain is huge but `SpawnGate` only verifies the chunk under the player. Underground deposits placed where chunks haven't streamed yet may report `get_voxel_f` as the default value (probably air/solid depending on backend). Mitigation: use `_voxel_tool.is_area_editable(AABB)` before placement, OR rely on `IslandVoxelGenerator._height` evaluation in script to decide solidity (since it's deterministic from world position). Pick during implementation; the latter is cheaper.

7. **VoxelInstancer entries removed from `nature_library.tres`** — confirm nothing else in the project references those entries by ID. Grep before deleting. Tree/grass entries are renumbered if necessary.

8. **Performance: 100+ static deposits + collision shapes.** Each deposit is a `StaticBody3D` with one `CollisionShape3D` (sphere). Godot handles thousands of static colliders comfortably. Particles are `GPUParticles3D` with `one_shot=true` and `emitting=false` until `restart()` — they idle near-free. Should not impact frame rate.

9. **Per-deposit signal connection in Miner.** Miner connects to `chunk_broken` lazily on first hit (`if not is_connected(...)`). When the deposit is `queue_free`'d on `depleted`, the connection dies with it — no leak. Miner also doesn't need to connect to `damaged` or `depleted` signals; only `chunk_broken` matters for inventory.

## Out of scope (deferred)

- Persistence (mined deposits + inventory survive game restart)
- Pickaxe / tool tier system; tier-locking by ore type
- Physical chunk pickups (`RigidBody3D`-based)
- Sprint stamina interaction
- Empty-stamina audio cue
- Variant ore-hit audio samples
- Floating-rock land-on-dig polish
- Authored cracked-stage meshes (Cell Fracture etc.)
- View-model bob, head-bob coupling
- Visual brush cursor / aim crosshair
- Multiple tool slots / switching tools (only the shovel exists this round)
- HUD polish: ore-type icons, animated counters, stamina bar styling beyond defaults

## Success criteria

- Player spawns with a visible shovel held in lower-right of view.
- LMB swings the shovel; the animation reads as a real wind-up + strike + recovery.
- Stamina bar visible bottom-center, drains 10 per swing, regens after 0.8s pause.
- Holding LMB drains stamina to 0; swings stop until bar refills to 20%.
- Surface rocks scatter the island; one swing pops a rock, +1 stone, distinct ore-hit audio.
- Tunneling into dirt with the shovel still works; no ore credited; dirt-thump audio.
- Underground deposits visibly distinct (gray boulders, rust-iron, gold-yellow).
- Multi-hit deposits visibly shrink in stages; each break credits the right amount of ore; small particle burst per hit, larger burst per chunk-break.
- A small stone deposit yields exactly 5 stone over ~60 swings. A large gold deposit yields exactly 20 gold over ~200 swings.
- Frame rate stays solid with 100+ deposits in the world.
- No crashes on game restart; world re-rolls deposits at new positions (since seed default is fixed, positions repeat — stable for testing).
