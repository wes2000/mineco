# Belt-Driven Smelting v1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first automation system in Mine Co. — three placeable buildings (Loader / Smelter / Forge) connected by belts (Straight / 90° Corner / T-junction), driven by a deterministic 10 Hz simulation, with full build-mode UX and recipe UI.

**Architecture:** Discrete cell-occupancy belt simulation with smooth visual interpolation (the "Hybrid C" approach — items logically own one Vector3i cell at a time, visually lerp between cell centers). Two new autoloads: `FactoryWorld` (owns cell registry + 10 Hz tick) and `BuildController` (owns build mode + ghost preview). Buildings share a state-machine base class.

**Tech Stack:** Godot 4.6 (Forward+), GDScript (typed, signals, `class_name`), Voxel Tools 1.6 module, Jolt physics, godot-ai MCP for in-editor verification.

**Spec:** [docs/superpowers/specs/2026-05-02-belt-smelting-v1-design.md](../specs/2026-05-02-belt-smelting-v1-design.md)

---

## How verification works in this plan

This project has no automated test framework (matching its existing `mining-mvp` and `mining-depth-r1` pattern). Each task includes a **manual verification step** — usually one of:

- **Editor check (godot-ai MCP)**: open the scene/script in Godot via MCP, read node properties or run the editor
- **Runtime check (godot-ai MCP)**: launch the project via `mcp__godot-ai__project_run`, observe `mcp__godot-ai__logs_read` output, take a screenshot via `mcp__godot-ai__editor_screenshot`
- **Static check**: parse the file, verify no syntax errors via `mcp__godot-ai__script_manage` (op: read)

If a subagent cannot verify a task because Godot isn't running or MCP isn't reachable, it should report the verification gap and continue rather than block.

## Parallelism map

Tasks marked **[P:group-N]** can run in parallel within their group. Tasks not marked must run sequentially.

```
Task 0 (git init) — sequential, prerequisite
Task 1 (material_defs.gd) — sequential
Task 2 (factory_world.gd skeleton) — sequential
Task 3 (autoload registration) — sequential
─────── parallel group A ───────
Task 4 [P:A] item.gd + 9 item scenes
Task 5 [P:A] item_pool.gd
Task 6 [P:A] belt_graph.gd
─────── sequential ───────
Task 7 belt_cell.gd + 3 belt scenes
Task 8 wire belts into FactoryWorld tick
Task 9 building.gd base class
─────── parallel group B ───────
Task 10 [P:B] loader.gd + scene
Task 11 [P:B] smelter.gd + scene
Task 12 [P:B] forge.gd + scene
─────── parallel group C1 ───────
Task 13 [P:C1] build_controller.gd + ghost_overlay
Task 17 [P:C1] machine_ui.gd + scene
Task 18 [P:C1] extend inventory_hud.gd
─────── sequential ───────
Task 14 build_hotbar scene (depends on Task 13's BuildController API)
Task 15 register input actions in project.godot
Task 16 wire BuildController ↔ FactoryWorld
Task 16.1 belt auto-orientation + neighbour-change re-orientation
─────── parallel group D ───────
Task 19 [P:D] procedural animations
Task 20 [P:D] audio stubs
Task 21 [P:D] forge overflow tracking
Task 22 [P:D] belt removal item-drop
─────── sequential ───────
Task 23 final integration tests (manual + soak)
```

---

## Task 0: Initialize git repository

**Files:**
- Create: `.git/` (via `git init`)
- Modify: `.gitignore` (already exists per earlier `ls`)

- [ ] **Step 1**: Verify the project is not yet a git repo

Run: `git -C "C:/Users/whann/Documents/mine-co" status`
Expected: `fatal: not a git repository`

- [ ] **Step 2**: Initialize repo

Run: `git -C "C:/Users/whann/Documents/mine-co" init`
Expected: `Initialized empty Git repository in ...`

- [ ] **Step 3**: Verify `.gitignore` excludes Godot artifacts

Read `.gitignore`. If it doesn't already exclude `.godot/` and `*.import`, add those lines. Existing content is 46 bytes — likely already fine but confirm.

- [ ] **Step 4**: Initial commit of current project state

```bash
git -C "C:/Users/whann/Documents/mine-co" add -A
git -C "C:/Users/whann/Documents/mine-co" commit -m "chore: initialize repo before belt-smelting work"
```

---

## Task 1: Material definitions (pure data)

**Files:**
- Create: `scripts/factory/material_defs.gd`

This is the single source of truth for all material taxonomy and timings. Pure static data — no nodes, no signals.

- [ ] **Step 1**: Create the directory

```bash
mkdir -p "C:/Users/whann/Documents/mine-co/scripts/factory"
```

- [ ] **Step 2**: Write `material_defs.gd`

```gdscript
class_name MaterialDefs
extends RefCounted

enum Material {
    STONE, BRICK, BLOCK,
    IRON_ORE, IRON_INGOT, IRON_BAR,
    GOLD_ORE, GOLD_INGOT, GOLD_BAR,
}

# Tier 1 = mined ore, 2 = smelted, 3 = forged
const TIER: Dictionary = {
    Material.STONE: 1, Material.BRICK: 2, Material.BLOCK: 3,
    Material.IRON_ORE: 1, Material.IRON_INGOT: 2, Material.IRON_BAR: 3,
    Material.GOLD_ORE: 1, Material.GOLD_INGOT: 2, Material.GOLD_BAR: 3,
}

# Loader emit interval (ticks). T1 only.
const LOADER_EMIT_TICKS: Dictionary = {
    Material.STONE: 10,
    Material.IRON_ORE: 20,
    Material.GOLD_ORE: 40,
}

# Smelter cycle (ticks). T1 -> T2.
const SMELTER_TICKS: Dictionary = {
    Material.STONE: 20,
    Material.IRON_ORE: 40,
    Material.GOLD_ORE: 80,
}

# Forge cycle (ticks). T2 -> T3.
const FORGE_TICKS: Dictionary = {
    Material.BRICK: 40,
    Material.IRON_INGOT: 80,
    Material.GOLD_INGOT: 160,
}

# Recipe maps
const SMELT_RECIPE: Dictionary = {
    Material.STONE: Material.BRICK,
    Material.IRON_ORE: Material.IRON_INGOT,
    Material.GOLD_ORE: Material.GOLD_INGOT,
}
const FORGE_RECIPE: Dictionary = {
    Material.BRICK: Material.BLOCK,
    Material.IRON_INGOT: Material.IRON_BAR,
    Material.GOLD_INGOT: Material.GOLD_BAR,
}

# Display names (HUD-facing)
const DISPLAY_NAME: Dictionary = {
    Material.STONE: "Stone", Material.BRICK: "Brick", Material.BLOCK: "Block",
    Material.IRON_ORE: "Iron Ore", Material.IRON_INGOT: "Iron Ingot", Material.IRON_BAR: "Iron Bar",
    Material.GOLD_ORE: "Gold Ore", Material.GOLD_INGOT: "Gold Ingot", Material.GOLD_BAR: "Gold Bar",
}

const TIER_1_MATERIALS: Array[Material] = [Material.STONE, Material.IRON_ORE, Material.GOLD_ORE]
const TIER_2_MATERIALS: Array[Material] = [Material.BRICK, Material.IRON_INGOT, Material.GOLD_INGOT]
const TIER_3_MATERIALS: Array[Material] = [Material.BLOCK, Material.IRON_BAR, Material.GOLD_BAR]
```

- [ ] **Step 3**: Verify it parses

Use `mcp__godot-ai__script_manage` op `read` on the new file. Confirm Godot reports no parse errors via `mcp__godot-ai__logs_read` after the editor refreshes.

- [ ] **Step 4**: Sanity check that all 9 materials appear in TIER, all 3 T1s in LOADER_EMIT_TICKS, etc. Spot-read the file.

- [ ] **Step 5**: Commit

```bash
git add scripts/factory/material_defs.gd
git commit -m "feat(factory): add MaterialDefs — single source of truth for materials and timings"
```

---

## Task 2: FactoryWorld autoload skeleton

**Files:**
- Create: `scripts/factory/factory_world.gd`

This is the autoload that owns the cell registry and runs the 10 Hz tick. In this task we set up the skeleton — registry + tick driver. Belt and building logic plug in later.

- [ ] **Step 1**: Write `factory_world.gd`

```gdscript
extends Node
## Autoload. Owns the cell registry and the 10 Hz simulation tick.

const TICK_HZ: float = 10.0
const TICK_DT: float = 1.0 / TICK_HZ

signal tick_emitted(tick_index: int)
signal cell_registered(cell: Vector3i, owner: Node3D)
signal cell_unregistered(cell: Vector3i)

var _cells: Dictionary = {}              # Vector3i -> Node3D (belt cell or building footprint owner)
var _tick_accumulator: float = 0.0
var _tick_index: int = 0

func _ready() -> void:
    set_process(true)

func _process(delta: float) -> void:
    _tick_accumulator += delta
    while _tick_accumulator >= TICK_DT:
        _tick_accumulator -= TICK_DT
        _tick_index += 1
        tick_emitted.emit(_tick_index)

# --- Cell registry API ---

func is_cell_free(cell: Vector3i) -> bool:
    return not _cells.has(cell)

func get_cell_owner(cell: Vector3i) -> Node3D:
    return _cells.get(cell, null)

func register_cell(cell: Vector3i, owner: Node3D) -> bool:
    if _cells.has(cell):
        push_warning("FactoryWorld: cell %s already registered" % cell)
        return false
    _cells[cell] = owner
    cell_registered.emit(cell, owner)
    return true

func unregister_cell(cell: Vector3i) -> void:
    if not _cells.has(cell):
        return
    _cells.erase(cell)
    cell_unregistered.emit(cell)

# Stubs — implemented in later tasks (Task 13/16):
func place(_kind: StringName, _origin_cell: Vector3i, _rotation_steps: int) -> bool:
    push_warning("FactoryWorld.place not yet implemented")
    return false

func remove(_cell: Vector3i) -> void:
    push_warning("FactoryWorld.remove not yet implemented")

# --- Tick introspection (debug) ---
func get_tick_index() -> int:
    return _tick_index
```

- [ ] **Step 2**: Verify it parses (`mcp__godot-ai__logs_read` after save).

- [ ] **Step 3**: Commit

```bash
git add scripts/factory/factory_world.gd
git commit -m "feat(factory): add FactoryWorld autoload skeleton with 10 Hz tick"
```

---

## Task 3: Register FactoryWorld autoload

**Files:**
- Modify: `project.godot` (autoload section, lines 18–23)

Order matters: per spec, `FactoryWorld` must come **before** `BuildController` (which we add in Task 13).

- [ ] **Step 1**: Read current `[autoload]` section.

- [ ] **Step 2**: Insert `FactoryWorld="*res://scripts/factory/factory_world.gd"` **after** `Admin=` line and **before** the `[editor_plugins]` section.

Final `[autoload]` block:
```
[autoload]

_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"
Atmosphere="*res://scripts/atmosphere.gd"
Admin="*res://scripts/admin.gd"
FactoryWorld="*res://scripts/factory/factory_world.gd"
```

(BuildController gets added in Task 13.)

- [ ] **Step 3**: Verify Godot loads cleanly

Use `mcp__godot-ai__editor_state` to confirm editor is responsive. Use `mcp__godot-ai__logs_read` to confirm no autoload errors.

- [ ] **Step 4**: Commit

```bash
git add project.godot
git commit -m "feat(factory): register FactoryWorld autoload"
```

---

## Task 4 [P:A]: Item entity + 9 item scenes

**Files:**
- Create: `scripts/factory/item.gd`
- Create: `scenes/factory/item_stone.tscn` through `item_gold_bar.tscn` (9 scenes)

Item is a Node3D with a small mesh, pooled. While moving between cells it lerps its visual position; logically it always "owns" one cell.

- [ ] **Step 1**: Write `scripts/factory/item.gd`

```gdscript
class_name FactoryItem
extends Node3D
## A single material item riding on belts. Pooled — never directly freed.

@export var material_id: int = -1   # MaterialDefs.Material enum

var _current_cell: Vector3i
var _prev_cell_center: Vector3
var _current_cell_center: Vector3
var _move_start_time: float = 0.0
var _move_duration: float = 0.0   # 0 = stationary

func _ready() -> void:
    set_process(true)

func _process(_delta: float) -> void:
    if _move_duration <= 0.0:
        global_position = _current_cell_center
        return
    var now: float = Time.get_ticks_msec() / 1000.0
    var t: float = clamp((now - _move_start_time) / _move_duration, 0.0, 1.0)
    global_position = _prev_cell_center.lerp(_current_cell_center, t)

func place_at(cell: Vector3i, world_center: Vector3) -> void:
    _current_cell = cell
    _current_cell_center = world_center
    _prev_cell_center = world_center
    _move_duration = 0.0
    global_position = world_center

func begin_move_to(target_cell: Vector3i, target_center: Vector3, duration_sec: float) -> void:
    _prev_cell_center = _current_cell_center
    _current_cell = target_cell
    _current_cell_center = target_center
    _move_start_time = Time.get_ticks_msec() / 1000.0
    _move_duration = duration_sec

func current_cell() -> Vector3i:
    return _current_cell
```

- [ ] **Step 2**: Create 9 item scenes

Each scene = `Node3D` (root, script = `item.gd`, `material_id` set to the matching enum int) + `MeshInstance3D` child with a small primitive (use `BoxMesh` 0.3³ for now, color-coded via a `StandardMaterial3D`):

| File | material_id | Albedo color |
|---|---|---|
| item_stone.tscn | 0 (STONE) | gray (0.6, 0.6, 0.6) |
| item_brick.tscn | 1 (BRICK) | red-brown (0.7, 0.35, 0.25) |
| item_block.tscn | 2 (BLOCK) | dark gray (0.4, 0.4, 0.4) |
| item_iron_ore.tscn | 3 (IRON_ORE) | rust (0.55, 0.4, 0.3) |
| item_iron_ingot.tscn | 4 (IRON_INGOT) | steel (0.7, 0.7, 0.75) |
| item_iron_bar.tscn | 5 (IRON_BAR) | bright steel (0.85, 0.85, 0.9) |
| item_gold_ore.tscn | 6 (GOLD_ORE) | dull gold (0.7, 0.6, 0.2) |
| item_gold_ingot.tscn | 7 (GOLD_INGOT) | gold (0.95, 0.8, 0.3) |
| item_gold_bar.tscn | 8 (GOLD_BAR) | bright gold (1.0, 0.85, 0.4) |

Use `mcp__godot-ai__scene_manage` op `create` and `mcp__godot-ai__node_create` to build each scene. Save with `mcp__godot-ai__scene_save`.

- [ ] **Step 3**: Verify by opening `item_stone.tscn` in editor and screenshotting

Use `mcp__godot-ai__scene_open` then `mcp__godot-ai__editor_screenshot`. Eyeball: should be a small gray cube at origin.

- [ ] **Step 4**: Commit

```bash
git add scripts/factory/item.gd scenes/factory/item_*.tscn
git commit -m "feat(factory): add FactoryItem + 9 material item scenes"
```

---

## Task 5 [P:A]: ItemPool

**Files:**
- Create: `scripts/factory/item_pool.gd`

Pool keyed by material_id. `acquire(material_id)` either rents a free instance or instantiates one. `release(item)` parents it under the pool root and hides it.

- [ ] **Step 1**: Write `scripts/factory/item_pool.gd`

```gdscript
class_name ItemPool
extends Node
## Per-material pool of FactoryItem instances. Created by FactoryWorld.

const ITEM_SCENE_PATHS: Dictionary = {
    0: "res://scenes/factory/item_stone.tscn",
    1: "res://scenes/factory/item_brick.tscn",
    2: "res://scenes/factory/item_block.tscn",
    3: "res://scenes/factory/item_iron_ore.tscn",
    4: "res://scenes/factory/item_iron_ingot.tscn",
    5: "res://scenes/factory/item_iron_bar.tscn",
    6: "res://scenes/factory/item_gold_ore.tscn",
    7: "res://scenes/factory/item_gold_ingot.tscn",
    8: "res://scenes/factory/item_gold_bar.tscn",
}

var _free: Dictionary = {}     # material_id -> Array[FactoryItem]
var _scenes: Dictionary = {}   # material_id -> PackedScene (cached)

func _ready() -> void:
    for mid: int in ITEM_SCENE_PATHS:
        _free[mid] = []
        _scenes[mid] = load(ITEM_SCENE_PATHS[mid]) as PackedScene

func acquire(material_id: int) -> FactoryItem:
    var pool: Array = _free.get(material_id, [])
    var item: FactoryItem
    if pool.is_empty():
        item = (_scenes[material_id] as PackedScene).instantiate() as FactoryItem
        add_child(item)
    else:
        item = pool.pop_back() as FactoryItem
    item.visible = true
    item.set_process(true)
    return item

func release(item: FactoryItem) -> void:
    item.visible = false
    item.set_process(false)
    _free[item.material_id].append(item)
```

- [ ] **Step 2**: Add ItemPool child to FactoryWorld

Modify `factory_world.gd` `_ready()` to instantiate and add an `ItemPool` child:
```gdscript
var item_pool: ItemPool

func _ready() -> void:
    item_pool = ItemPool.new()
    item_pool.name = "ItemPool"
    add_child(item_pool)
    set_process(true)
```

- [ ] **Step 3**: Verify by adding a temporary debug call

Add to `factory_world.gd` `_ready()` end:
```gdscript
var test_item: FactoryItem = item_pool.acquire(0)
test_item.place_at(Vector3i.ZERO, Vector3.ZERO)
print("ItemPool sanity: acquired stone item at ", test_item.global_position)
```
Run main scene via `mcp__godot-ai__project_run`, check `mcp__godot-ai__logs_read` for the print line. **Then remove the temporary debug code** and commit without it.

- [ ] **Step 4**: Commit

```bash
git add scripts/factory/item_pool.gd scripts/factory/factory_world.gd
git commit -m "feat(factory): add ItemPool, hook into FactoryWorld"
```

---

## Task 6 [P:A]: BeltGraph

**Files:**
- Create: `scripts/factory/belt_graph.gd`

Pure logic. Reads cell registry, computes per-cell input/output neighbours, runs the reverse-BFS ordering, applies T-junction round-robin.

- [ ] **Step 1**: Write `scripts/factory/belt_graph.gd`

```gdscript
class_name BeltGraph
extends RefCounted
## Pure graph logic over FactoryWorld._cells. Mutates only round-robin state.

const HORIZONTAL_OFFSETS: Array[Vector3i] = [
    Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
    Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# Per-cell round-robin counter (incremented on successful flow when multiple outputs/inputs).
var _round_robin: Dictionary = {}    # Vector3i -> int

# Cached BFS depth: Vector3i -> int. Recomputed on graph mutation.
var _depth_cache: Dictionary = {}
var _cache_dirty: bool = true

func mark_dirty() -> void:
    _cache_dirty = true

# Returns list of (input_cells, output_cells) for this cell, derived from neighbours.
# Each neighbour declares "I am an output of cell X" via its facing.
# Buildings declare via input/output face metadata.
func neighbours_of(cell: Vector3i, world_cells: Dictionary) -> Dictionary:
    var inputs: Array[Vector3i] = []
    var outputs: Array[Vector3i] = []
    for off: Vector3i in HORIZONTAL_OFFSETS:
        var n_cell: Vector3i = cell + off
        if not world_cells.has(n_cell):
            continue
        var owner: Node3D = world_cells[n_cell]
        var role: int = _neighbour_role_relative_to(n_cell, owner, cell)
        # role: -1 = input to cell, +1 = output of cell, 0 = no connection
        if role == -1:
            inputs.append(n_cell)
        elif role == +1:
            outputs.append(n_cell)
    return {"inputs": inputs, "outputs": outputs}

# Returns -1 if neighbour feeds INTO `from_cell`, +1 if it RECEIVES from `from_cell`, 0 if neither.
func _neighbour_role_relative_to(neighbour_cell: Vector3i, neighbour_owner: Node3D, from_cell: Vector3i) -> int:
    if neighbour_owner.has_method("get_output_cells"):
        # Building: outputs cells point to the cell directly outside their output face
        var bld_outputs: Array = neighbour_owner.get_output_cells()
        if bld_outputs.has(from_cell):
            return -1   # building outputs INTO from_cell (so neighbour is an input source for from_cell)
        var bld_inputs: Array = neighbour_owner.get_input_cells() if neighbour_owner.has_method("get_input_cells") else []
        if bld_inputs.has(from_cell):
            return +1
        return 0
    if neighbour_owner.has_method("get_facing"):
        # Belt: facing is a Vector3i unit vector pointing FROM this belt TO its output
        var facing: Vector3i = neighbour_owner.get_facing()
        if neighbour_cell + facing == from_cell:
            return -1   # neighbour's output is from_cell, so neighbour feeds in
        # input side is opposite
        if neighbour_cell - facing == from_cell:
            return +1   # neighbour's input is from_cell, so from_cell feeds INTO neighbour
        return 0
    return 0

# Round-robin output choice when multiple outputs are valid.
# Increments counter only on success (caller calls confirm_flow on success).
func choose_output(from_cell: Vector3i, candidate_outputs: Array[Vector3i]) -> Vector3i:
    if candidate_outputs.is_empty():
        return from_cell    # caller treats this as "no output"
    if candidate_outputs.size() == 1:
        return candidate_outputs[0]
    var counter: int = _round_robin.get(from_cell, 0)
    return candidate_outputs[counter % candidate_outputs.size()]

func confirm_flow(from_cell: Vector3i) -> void:
    _round_robin[from_cell] = _round_robin.get(from_cell, 0) + 1

# Reverse-BFS: returns Array[Vector3i] of belt cells in tick-processing order (sinks first).
func compute_tick_order(world_cells: Dictionary, belt_cells: Array[Vector3i]) -> Array[Vector3i]:
    if not _cache_dirty:
        return _cached_order_for(belt_cells)
    _depth_cache.clear()
    var sinks: Array[Vector3i] = []
    for c: Vector3i in belt_cells:
        var n: Dictionary = neighbours_of(c, world_cells)
        # A sink: no output neighbours that are belts (output is a building or off-the-end)
        var has_belt_output: bool = false
        for out_cell: Vector3i in n.outputs:
            var ow: Node3D = world_cells.get(out_cell, null)
            if ow != null and ow.has_method("get_facing"):
                has_belt_output = true
                break
        if not has_belt_output:
            sinks.append(c)
            _depth_cache[c] = 0
    # BFS backwards along input edges
    var frontier: Array[Vector3i] = sinks.duplicate()
    var depth: int = 0
    while not frontier.is_empty():
        depth += 1
        var next_frontier: Array[Vector3i] = []
        for c: Vector3i in frontier:
            var n: Dictionary = neighbours_of(c, world_cells)
            for in_cell: Vector3i in n.inputs:
                var ow: Node3D = world_cells.get(in_cell, null)
                if ow == null or not ow.has_method("get_facing"):
                    continue   # only process belt inputs
                var existing: int = _depth_cache.get(in_cell, -1)
                if existing == -1 or existing > depth:
                    _depth_cache[in_cell] = depth
                    next_frontier.append(in_cell)
        frontier = next_frontier
    _cache_dirty = false
    return _cached_order_for(belt_cells)

func _cached_order_for(belt_cells: Array[Vector3i]) -> Array[Vector3i]:
    var sortable: Array = []
    for c: Vector3i in belt_cells:
        var d: int = _depth_cache.get(c, 999999)   # cycles get INF, processed last
        sortable.append([d, c])
    sortable.sort_custom(func(a, b): return a[0] < b[0])
    var result: Array[Vector3i] = []
    for entry: Array in sortable:
        result.append(entry[1])
    return result
```

- [ ] **Step 2**: Verify it parses. Use `mcp__godot-ai__logs_read`.

- [ ] **Step 3**: Commit

```bash
git add scripts/factory/belt_graph.gd
git commit -m "feat(factory): add BeltGraph (per-cell flow direction + reverse-BFS tick order)"
```

---

## Task 7: BeltCell + 3 belt scenes

**Files:**
- Create: `scripts/factory/belt_cell.gd`
- Create: `scenes/factory/belt_straight.tscn`, `belt_corner.tscn`, `belt_t.tscn`

- [ ] **Step 1**: Write `scripts/factory/belt_cell.gd`

```gdscript
class_name BeltCell
extends Node3D
## A single placed belt piece. Owns at most one FactoryItem.

enum Kind { STRAIGHT, CORNER, T }

@export var kind: int = Kind.STRAIGHT
@export var facing: Vector3i = Vector3i(0, 0, 1)   # unit vector toward output side

var cell: Vector3i               # set by FactoryWorld on placement
var occupant: FactoryItem = null # current item (or null)
var settle_ticks: int = 0        # ticks remaining before occupant can advance (BELT_SPEED_TICKS on arrival)
var blocked_ticks: int = 0       # ticks the occupant has been waiting at this cell unable to advance (Task 22)

func get_facing() -> Vector3i:
    return facing

func set_cell_and_facing(c: Vector3i, f: Vector3i) -> void:
    cell = c
    facing = f
    rotation = _facing_to_basis_y_rot(f)

func _facing_to_basis_y_rot(f: Vector3i) -> Vector3:
    # Convert Vector3i facing to Y-axis rotation in radians.
    if f == Vector3i(0, 0, 1):
        return Vector3.ZERO
    if f == Vector3i(1, 0, 0):
        return Vector3(0, -PI / 2, 0)
    if f == Vector3i(0, 0, -1):
        return Vector3(0, PI, 0)
    if f == Vector3i(-1, 0, 0):
        return Vector3(0, PI / 2, 0)
    return Vector3.ZERO

func cell_center_world() -> Vector3:
    return Vector3(cell.x + 0.5, cell.y + 0.1, cell.z + 0.5)

func is_free() -> bool:
    return occupant == null

func place_item(item: FactoryItem) -> void:
    occupant = item
    settle_ticks = 10   # FactoryWorld.BELT_SPEED_TICKS — defined in Task 8
    blocked_ticks = 0
    item.place_at(cell, cell_center_world())

func receive_moving_item(item: FactoryItem, prev_center: Vector3, duration_sec: float) -> void:
    occupant = item
    settle_ticks = 10
    blocked_ticks = 0
    item._prev_cell_center = prev_center   # keep visual continuity
    item.begin_move_to(cell, cell_center_world(), duration_sec)

func clear_item() -> void:
    occupant = null
    settle_ticks = 0
    blocked_ticks = 0

func can_advance_now() -> bool:
    return occupant != null and settle_ticks <= 0

func tick_settle() -> void:
    if settle_ticks > 0:
        settle_ticks -= 1
```

- [ ] **Step 2**: Create `belt_straight.tscn`

Root: `BeltCell` (script attached, `kind = 0`). Children:
- `MeshInstance3D` with a `BoxMesh` 1×0.1×1, dark gray material. (Body)
- `MeshInstance3D` with a small `BoxMesh` 0.3×0.05×0.1 placed at `Z = 0.4` (arrow indicating facing).

- [ ] **Step 3**: Create `belt_corner.tscn`

Root: `BeltCell` (`kind = 1`). Children: similar to straight but with an L-shaped arrangement of two `BoxMesh`es.

- [ ] **Step 4**: Create `belt_t.tscn`

Root: `BeltCell` (`kind = 2`). Children: T-shaped arrangement of two `BoxMesh`es.

- [ ] **Step 5**: Verify by opening each scene in the editor + screenshotting.

- [ ] **Step 6**: Commit

```bash
git add scripts/factory/belt_cell.gd scenes/factory/belt_*.tscn
git commit -m "feat(factory): add BeltCell + 3 belt scenes (straight/corner/T)"
```

---

## Task 8: Wire belt simulation into FactoryWorld tick

**Files:**
- Modify: `scripts/factory/factory_world.gd`

Add belt advancement logic to the 10 Hz tick. Building logic comes in later tasks.

- [ ] **Step 1**: Add belt-related state and methods to `factory_world.gd`

```gdscript
# Add to top of file (after existing consts):
const BELT_SPEED_TICKS: int = 10   # 1 cell per second at 10 Hz

var graph: BeltGraph

# Add to _ready():
graph = BeltGraph.new()

# Add new method, called from tick_emitted:
func _on_tick(_idx: int) -> void:
    _tick_belts()

# After _ready, connect:
# tick_emitted.connect(_on_tick)

func _tick_belts() -> void:
    var belt_cells: Array[Vector3i] = []
    for c: Vector3i in _cells:
        var owner: Node3D = _cells[c]
        if owner is BeltCell:
            belt_cells.append(c)
    if belt_cells.is_empty():
        return
    # Phase 1: settle ticks decrement for every belt cell.
    for c: Vector3i in belt_cells:
        (_cells[c] as BeltCell).tick_settle()
    # Phase 2: advancement, in reverse-BFS order (sinks first).
    var ordered: Array[Vector3i] = graph.compute_tick_order(_cells, belt_cells)
    for c: Vector3i in ordered:
        var bc: BeltCell = _cells[c] as BeltCell
        if not bc.can_advance_now():
            continue   # either empty or item still in transit
        var n: Dictionary = graph.neighbours_of(c, _cells)
        if n.outputs.is_empty():
            bc.blocked_ticks += 1   # Task 22: dead-end drop trigger
            continue
        var target: Vector3i = graph.choose_output(c, n.outputs)
        var target_owner: Node3D = _cells.get(target, null)
        if target_owner == null:
            bc.blocked_ticks += 1
            continue
        var moved: bool = false
        if target_owner is BeltCell:
            var tbc: BeltCell = target_owner as BeltCell
            if tbc.is_free():
                var item: FactoryItem = bc.occupant
                bc.clear_item()
                tbc.receive_moving_item(item, bc.cell_center_world(), BELT_SPEED_TICKS * TICK_DT)
                moved = true
        elif target_owner is Building:
            var bld: Building = target_owner as Building
            if target in bld.get_input_cells() and bld.try_accept_item(bc.occupant, c):
                bc.clear_item()
                moved = true
        if moved:
            graph.confirm_flow(c)
        else:
            bc.blocked_ticks += 1

# Also: cell_registered / unregistered should mark graph dirty:
# In register_cell / unregister_cell, add:
#     if graph != null: graph.mark_dirty()
```

- [ ] **Step 2**: Connect signal in `_ready()`:
```gdscript
tick_emitted.connect(_on_tick)
```

- [ ] **Step 3**: Manual smoke test

Create a temporary test scene: instantiate 3 `belt_straight.tscn`, place them in a row at (0,0,0), (0,0,1), (0,0,2), all facing +Z. Manually call `FactoryWorld.register_cell` for each. Place a stone item on the first belt via `acquire` + `place_item`. Run main scene, verify the item visibly hops cell-to-cell once per second via screenshots at 0s, 1s, 2s, 3s. Then **delete the temporary scene** before commit.

- [ ] **Step 4**: Commit

```bash
git add scripts/factory/factory_world.gd
git commit -m "feat(factory): wire belt advancement into 10 Hz tick"
```

---

## Task 9: Building base class

**Files:**
- Create: `scripts/factory/building.gd`

- [ ] **Step 1**: Write `scripts/factory/building.gd`

```gdscript
class_name Building
extends Node3D
## Shared base for Loader, Smelter, Forge.

enum Status { IDLE, WORKING, OUTPUT_BLOCKED, INPUT_JAMMED, OVERFLOWING }

signal item_emitted(material_id: int)
signal status_changed(status: int)

@export var footprint_size: Vector2i = Vector2i(2, 2)   # cells in X,Z
@export var rotation_steps: int = 0                     # 0..3, applied in 90° steps around +Y

var origin_cell: Vector3i        # set on placement; "front-left" cell of the footprint
var status: int = Status.IDLE :
    set(v):
        if status != v:
            status = v
            status_changed.emit(v)

# Subclasses override these:
func get_input_cells() -> Array[Vector3i]:
    return []
func get_output_cells() -> Array[Vector3i]:
    return []
func get_footprint_cells() -> Array[Vector3i]:
    var cells: Array[Vector3i] = []
    for x: int in footprint_size.x:
        for z: int in footprint_size.y:
            cells.append(origin_cell + Vector3i(x, 0, z))
    return cells

# Called by FactoryWorld on each tick.
func tick(_tick_index: int) -> void:
    pass

# Called by FactoryWorld when an item arrives at one of our input cells.
# Return true to accept (we take ownership), false to reject (item stays put).
func try_accept_item(_item: FactoryItem, _from_cell: Vector3i) -> bool:
    return false

# Helper: given a local-space offset in the 0-rotation frame, return the world cell.
func cell_for_local_offset(local: Vector3i) -> Vector3i:
    var rotated: Vector3i = _rotate_offset(local, rotation_steps)
    return origin_cell + rotated

func _rotate_offset(v: Vector3i, steps: int) -> Vector3i:
    var s: int = steps & 3
    var x: int = v.x
    var z: int = v.z
    for _i: int in s:
        var nx: int = -z
        var nz: int = x
        x = nx
        z = nz
    return Vector3i(x, v.y, z)
```

- [ ] **Step 2**: Verify parse.

- [ ] **Step 3**: Commit

```bash
git add scripts/factory/building.gd
git commit -m "feat(factory): add Building base class (state machine + footprint helpers)"
```

---

## Task 10 [P:B]: Loader

**Files:**
- Create: `scripts/factory/loader.gd`
- Create: `scenes/factory/loader.tscn`

- [ ] **Step 1**: Write `scripts/factory/loader.gd`

```gdscript
class_name Loader
extends Building
## Player-fed hopper that emits one selected material onto its output belt.

const HOPPER_CAP: int = 999

signal hopper_changed(material_id: int, new_count: int)

var hopper: Dictionary = {}     # material_id -> int
var selected_material: int = MaterialDefs.Material.STONE
var _cycle_remaining_ticks: int = 0

func _ready() -> void:
    footprint_size = Vector2i(2, 2)
    for mid: int in MaterialDefs.TIER_1_MATERIALS:
        hopper[mid] = 0

func get_input_cells() -> Array[Vector3i]:
    return []

func get_output_cells() -> Array[Vector3i]:
    # Single output cell, on the "front" face (one cell forward of the footprint center, rotated).
    return [cell_for_local_offset(Vector3i(0, 0, footprint_size.y))]

func deposit(material_id: int, amount: int) -> int:
    # Returns amount actually accepted (capped at HOPPER_CAP).
    var current: int = hopper.get(material_id, 0)
    var new_amount: int = min(current + amount, HOPPER_CAP)
    var accepted: int = new_amount - current
    hopper[material_id] = new_amount
    hopper_changed.emit(material_id, new_amount)
    return accepted

func tick(_tick_index: int) -> void:
    if hopper.get(selected_material, 0) <= 0:
        status = Status.IDLE
        return
    if _cycle_remaining_ticks > 0:
        _cycle_remaining_ticks -= 1
        status = Status.WORKING
        return
    # Cycle done — try to emit.
    var out_cells: Array[Vector3i] = get_output_cells()
    if out_cells.is_empty():
        status = Status.OUTPUT_BLOCKED
        return
    var out_cell: Vector3i = out_cells[0]
    var owner: Node3D = FactoryWorld.get_cell_owner(out_cell)
    if not (owner is BeltCell) or not (owner as BeltCell).is_free():
        status = Status.OUTPUT_BLOCKED
        return
    # Emit
    var item: FactoryItem = FactoryWorld.item_pool.acquire(selected_material)
    var belt: BeltCell = owner as BeltCell
    belt.place_item(item)
    hopper[selected_material] -= 1
    hopper_changed.emit(selected_material, hopper[selected_material])
    item_emitted.emit(selected_material)
    _cycle_remaining_ticks = MaterialDefs.LOADER_EMIT_TICKS[selected_material]
    status = Status.WORKING
```

- [ ] **Step 2**: Create `scenes/factory/loader.tscn`

Root: `Loader` (script attached). Children:
- `MeshInstance3D` with `BoxMesh` 2×1.5×2 (body), placed at local `(1, 0.75, 1)` so it sits within the 2×2 footprint with origin at corner.
- `MeshInstance3D` "output port" — small box at the front face indicator. Name it `OutputPort` for animation hooks (Task 19).
- `MeshInstance3D` "hopper opening" — top face indicator.

- [ ] **Step 3**: Verify scene loads and script attaches.

- [ ] **Step 4**: Commit

```bash
git add scripts/factory/loader.gd scenes/factory/loader.tscn
git commit -m "feat(factory): add Loader (hopper-fed emitter)"
```

---

## Task 11 [P:B]: Smelter

**Files:**
- Create: `scripts/factory/smelter.gd`
- Create: `scenes/factory/smelter.tscn`

- [ ] **Step 1**: Write `scripts/factory/smelter.gd`

```gdscript
class_name Smelter
extends Building

@export var recipe_input: int = MaterialDefs.Material.STONE   # one of TIER_1_MATERIALS

var _input_item: FactoryItem = null
var _cycle_remaining_ticks: int = 0
var _input_material: int = -1   # the material being processed in the current cycle

func _ready() -> void:
    footprint_size = Vector2i(2, 2)

func get_input_cells() -> Array[Vector3i]:
    return [cell_for_local_offset(Vector3i(0, 0, -1))]   # one cell behind footprint origin row

func get_output_cells() -> Array[Vector3i]:
    return [cell_for_local_offset(Vector3i(0, 0, footprint_size.y))]

func try_accept_item(item: FactoryItem, _from_cell: Vector3i) -> bool:
    if _input_item != null:
        return false
    _input_item = item
    return true

func tick(_tick_index: int) -> void:
    # Currently working?
    if _cycle_remaining_ticks > 0:
        _cycle_remaining_ticks -= 1
        status = Status.WORKING
        return
    # Cycle done — emit T2 if we were working
    if _input_material != -1:
        if not _try_emit():
            status = Status.OUTPUT_BLOCKED
            return
        _input_material = -1
    # Try to start a new cycle if we have an input
    if _input_item == null:
        status = Status.IDLE
        return
    if _input_item.material_id != recipe_input:
        status = Status.INPUT_JAMMED
        return
    _input_material = _input_item.material_id
    FactoryWorld.item_pool.release(_input_item)
    _input_item = null
    _cycle_remaining_ticks = MaterialDefs.SMELTER_TICKS[_input_material]
    status = Status.WORKING

func _try_emit() -> bool:
    var out_material: int = MaterialDefs.SMELT_RECIPE[_input_material]
    var out_cells: Array[Vector3i] = get_output_cells()
    if out_cells.is_empty():
        return false
    var out_cell: Vector3i = out_cells[0]
    var owner: Node3D = FactoryWorld.get_cell_owner(out_cell)
    if owner == null or not (owner is BeltCell):
        return false
    var belt: BeltCell = owner as BeltCell
    if not belt.is_free():
        return false
    var item: FactoryItem = FactoryWorld.item_pool.acquire(out_material)
    belt.place_item(item)
    item_emitted.emit(out_material)
    return true
```

- [ ] **Step 2**: Create `scenes/factory/smelter.tscn`

Root: `Smelter`. Children: orange-tinted `BoxMesh` 2×2×2 body + `InputPort` mesh on back face + `OutputPort` mesh on front face + an inner emissive "fire" mesh visible during WORKING (driven later in Task 19).

- [ ] **Step 3**: Verify.

- [ ] **Step 4**: Commit

```bash
git add scripts/factory/smelter.gd scenes/factory/smelter.tscn
git commit -m "feat(factory): add Smelter (T1->T2 with recipe selector)"
```

---

## Task 12 [P:B]: Forge

**Files:**
- Create: `scripts/factory/forge.gd`
- Create: `scenes/factory/forge.tscn`

Effectively the same as Smelter but with T2->T3 recipes, 3×3 footprint, and overflow-tracking hooks (filled in Task 21).

- [ ] **Step 1**: Write `scripts/factory/forge.gd`

```gdscript
class_name Forge
extends Building

@export var recipe_input: int = MaterialDefs.Material.BRICK   # one of TIER_2_MATERIALS

var _input_item: FactoryItem = null
var _cycle_remaining_ticks: int = 0
var _input_material: int = -1

func _ready() -> void:
    footprint_size = Vector2i(3, 3)

func get_input_cells() -> Array[Vector3i]:
    return [cell_for_local_offset(Vector3i(1, 0, -1))]   # center of back row

func get_output_cells() -> Array[Vector3i]:
    return [cell_for_local_offset(Vector3i(1, 0, footprint_size.y))]   # center of front row

func try_accept_item(item: FactoryItem, _from_cell: Vector3i) -> bool:
    if _input_item != null:
        return false
    _input_item = item
    return true

func tick(_tick_index: int) -> void:
    if _is_overflowing():
        status = Status.OVERFLOWING
        return
    if _cycle_remaining_ticks > 0:
        _cycle_remaining_ticks -= 1
        status = Status.WORKING
        return
    if _input_material != -1:
        if not _try_emit():
            status = Status.OUTPUT_BLOCKED
            return
        _input_material = -1
    if _input_item == null:
        status = Status.IDLE
        return
    if _input_item.material_id != recipe_input:
        status = Status.INPUT_JAMMED
        return
    _input_material = _input_item.material_id
    FactoryWorld.item_pool.release(_input_item)
    _input_item = null
    _cycle_remaining_ticks = MaterialDefs.FORGE_TICKS[_input_material]
    status = Status.WORKING

func _try_emit() -> bool:
    var out_material: int = MaterialDefs.FORGE_RECIPE[_input_material]
    var out_cells: Array[Vector3i] = get_output_cells()
    if out_cells.is_empty():
        return false
    var out_cell: Vector3i = out_cells[0]
    var owner: Node3D = FactoryWorld.get_cell_owner(out_cell)
    if owner == null or not (owner is BeltCell):
        return false
    var belt: BeltCell = owner as BeltCell
    if not belt.is_free():
        return false
    var item: FactoryItem = FactoryWorld.item_pool.acquire(out_material)
    belt.place_item(item)
    item_emitted.emit(out_material)
    return true

# Stub — implemented in Task 21
func _is_overflowing() -> bool:
    return false
```

- [ ] **Step 2**: Create `scenes/factory/forge.tscn` — large 3×3 footprint, tall body, dark/heavy color.

- [ ] **Step 3**: Verify.

- [ ] **Step 4**: Commit

```bash
git add scripts/factory/forge.gd scenes/factory/forge.tscn
git commit -m "feat(factory): add Forge (T2->T3 with recipe selector + overflow stub)"
```

---

## Task 12.5: Wire building tick into FactoryWorld

**Files:**
- Modify: `scripts/factory/factory_world.gd`

(Belt-to-building input routing is already handled in Task 8's `_tick_belts`. This task only adds the building tick.)

- [ ] **Step 1**: In `_on_tick`, after `_tick_belts()`, add `_tick_buildings()`:

```gdscript
func _on_tick(_idx: int) -> void:
    _tick_belts()
    _tick_buildings()

func _tick_buildings() -> void:
    var seen: Dictionary = {}     # building -> true (avoid double-tick of multi-cell footprints)
    for c: Vector3i in _cells:
        var owner: Node3D = _cells[c]
        if owner is Building and not seen.has(owner):
            seen[owner] = true
            (owner as Building).tick(_tick_index)
```

- [ ] **Step 2**: Manual smoke test — build a temporary mini line in code (1 loader, 2 belts, 1 smelter) and verify items flow at the correct ~1-cell-per-second rate (NOT 10× faster — verify the settle_ticks gating in Task 8 is working).

- [ ] **Step 3**: Commit

```bash
git add scripts/factory/factory_world.gd
git commit -m "feat(factory): tick buildings each sim step"
```

---

## Task 13 [P:C]: BuildController autoload + ghost overlay

**Files:**
- Create: `scripts/factory/build_controller.gd`
- Create: `scenes/factory/ghost_overlay.tscn`

- [ ] **Step 1**: Write `scripts/factory/build_controller.gd`

```gdscript
extends Node
## Autoload. Owns build mode state, ghost preview, raycast, place/remove dispatch.

enum Tool { LOADER, SMELTER, FORGE, BELT }
enum BeltSubKind { STRAIGHT, CORNER, T }

signal active_changed(active: bool)
signal selection_changed(tool: int, sub: int)

const RAYCAST_LENGTH: float = 50.0

var active: bool = false :
    set(v):
        if active != v:
            active = v
            active_changed.emit(v)
var current_tool: int = Tool.LOADER
var current_belt_sub: int = BeltSubKind.STRAIGHT
var ghost_rotation_steps: int = 0

var _ghost_node: Node3D = null
var _player: Node3D = null
var _player_camera: Camera3D = null

func _ready() -> void:
    set_process(true)

func bind_player(player: Node3D, camera: Camera3D) -> void:
    _player = player
    _player_camera = camera

func _process(_delta: float) -> void:
    if not active or _player_camera == null:
        return
    _update_ghost_position()

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("build_toggle"):
        active = not active
        if not active and _ghost_node != null:
            _ghost_node.queue_free()
            _ghost_node = null
        return
    if not active:
        return
    if event.is_action_pressed("build_slot_1"):
        current_tool = Tool.LOADER
        selection_changed.emit(current_tool, current_belt_sub)
        _refresh_ghost()
    elif event.is_action_pressed("build_slot_2"):
        current_tool = Tool.SMELTER
        selection_changed.emit(current_tool, current_belt_sub)
        _refresh_ghost()
    elif event.is_action_pressed("build_slot_3"):
        current_tool = Tool.FORGE
        selection_changed.emit(current_tool, current_belt_sub)
        _refresh_ghost()
    elif event.is_action_pressed("build_slot_4"):
        current_tool = Tool.BELT
        selection_changed.emit(current_tool, current_belt_sub)
        _refresh_ghost()
    elif event.is_action_pressed("build_rotate"):
        if current_tool == Tool.BELT:
            current_belt_sub = (current_belt_sub + 1) % 3
            selection_changed.emit(current_tool, current_belt_sub)
        else:
            ghost_rotation_steps = (ghost_rotation_steps + 1) & 3
        _refresh_ghost()
    elif event.is_action_pressed("build_place"):
        _try_place()
    elif event.is_action_pressed("build_remove"):
        _try_remove()

func _update_ghost_position() -> void:
    var cell: Vector3i = _raycast_to_cell()
    if cell == Vector3i(-2147483648, -2147483648, -2147483648):
        return
    if _ghost_node == null:
        _refresh_ghost()
    if _ghost_node != null:
        _ghost_node.global_position = Vector3(cell.x + 0.5, cell.y + 0.1, cell.z + 0.5)
        _ghost_node.set_meta("target_cell", cell)
        _ghost_node.set_meta("placeable", _is_placeable_at(cell))
        _apply_ghost_color(_ghost_node.get_meta("placeable"))

func _raycast_to_cell() -> Vector3i:
    var space_state: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
    var from: Vector3 = _player_camera.global_position
    var to: Vector3 = from + (-_player_camera.global_basis.z) * RAYCAST_LENGTH
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
    query.collide_with_areas = false
    var hit: Dictionary = space_state.intersect_ray(query)
    if hit.is_empty():
        return Vector3i(-2147483648, -2147483648, -2147483648)
    var p: Vector3 = hit.position
    return Vector3i(floori(p.x), floori(p.y), floori(p.z))

const WORLD_RADIUS_CELLS: int = 150   # 300m island radius from spec
const WORLD_Y_MIN: int = -50
const WORLD_Y_MAX: int = 100

func _is_placeable_at(cell: Vector3i) -> bool:
    var footprint: Array[Vector3i] = _ghost_footprint(cell)
    var terrain: VoxelTerrain = get_tree().current_scene.find_child("VoxelTerrain", true, false) as VoxelTerrain
    var tool: VoxelTool = terrain.get_voxel_tool() if terrain != null else null
    for c: Vector3i in footprint:
        # (a) world bounds
        if c.y < WORLD_Y_MIN or c.y > WORLD_Y_MAX:
            return false
        if c.x * c.x + c.z * c.z > WORLD_RADIUS_CELLS * WORLD_RADIUS_CELLS:
            return false
        # (b) cell not already registered
        if not FactoryWorld.is_cell_free(c):
            return false
        # (c) supported by non-air voxel directly below
        if tool != null:
            var below: int = tool.get_voxel(Vector3i(c.x, c.y - 1, c.z))
            if below == 0:
                return false   # nothing solid under this cell
    return true

func _ghost_footprint(origin: Vector3i) -> Array[Vector3i]:
    var size: Vector2i = _tool_footprint_size()
    var cells: Array[Vector3i] = []
    for x: int in size.x:
        for z: int in size.y:
            cells.append(origin + Vector3i(x, 0, z))
    return cells

func _tool_footprint_size() -> Vector2i:
    match current_tool:
        Tool.LOADER, Tool.SMELTER:
            return Vector2i(2, 2)
        Tool.FORGE:
            return Vector2i(3, 3)
        _:
            return Vector2i(1, 1)

func _refresh_ghost() -> void:
    if _ghost_node != null:
        _ghost_node.queue_free()
        _ghost_node = null
    var scene_path: String = _ghost_scene_path()
    if scene_path == "":
        return
    var ps: PackedScene = load(scene_path)
    _ghost_node = ps.instantiate()
    _ghost_node.set_process(false)   # ghost shouldn't tick its game logic
    get_tree().current_scene.add_child(_ghost_node)

func _ghost_scene_path() -> String:
    match current_tool:
        Tool.LOADER: return "res://scenes/factory/loader.tscn"
        Tool.SMELTER: return "res://scenes/factory/smelter.tscn"
        Tool.FORGE: return "res://scenes/factory/forge.tscn"
        Tool.BELT:
            match current_belt_sub:
                BeltSubKind.STRAIGHT: return "res://scenes/factory/belt_straight.tscn"
                BeltSubKind.CORNER: return "res://scenes/factory/belt_corner.tscn"
                BeltSubKind.T: return "res://scenes/factory/belt_t.tscn"
    return ""

func _apply_ghost_color(placeable: bool) -> void:
    var col: Color = Color(0.3, 1.0, 0.3, 0.5) if placeable else Color(1.0, 0.3, 0.3, 0.5)
    for child: Node in _ghost_node.find_children("*", "MeshInstance3D"):
        var mi: MeshInstance3D = child as MeshInstance3D
        var mat: StandardMaterial3D = StandardMaterial3D.new()
        mat.albedo_color = col
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mi.material_override = mat

func _try_place() -> void:
    if _ghost_node == null or not _ghost_node.has_meta("placeable") or not _ghost_node.get_meta("placeable"):
        return
    var origin_cell: Vector3i = _ghost_node.get_meta("target_cell")
    var kind_name: StringName = _tool_to_kind_name()
    FactoryWorld.place(kind_name, origin_cell, ghost_rotation_steps)

func _try_remove() -> void:
    var cell: Vector3i = _raycast_to_cell()
    if cell == Vector3i(-2147483648, -2147483648, -2147483648):
        return
    FactoryWorld.remove(cell)

func _tool_to_kind_name() -> StringName:
    match current_tool:
        Tool.LOADER: return &"loader"
        Tool.SMELTER: return &"smelter"
        Tool.FORGE: return &"forge"
        Tool.BELT:
            match current_belt_sub:
                BeltSubKind.STRAIGHT: return &"belt_straight"
                BeltSubKind.CORNER: return &"belt_corner"
                BeltSubKind.T: return &"belt_t"
    return &""
```

- [ ] **Step 2**: `ghost_overlay.tscn` is just an empty wrapper Node3D for now (we instantiate building scenes directly as ghosts). Skip the file or create a one-line empty Node3D scene if you want a placeholder.

- [ ] **Step 3**: Verify parse.

- [ ] **Step 4**: Commit

```bash
git add scripts/factory/build_controller.gd
git commit -m "feat(factory): add BuildController autoload (build mode, ghost, raycast, place/remove dispatch)"
```

---

## Task 14: Build hotbar UI

(Sequential — depends on Task 13's BuildController API.)


**Files:**
- Create: `scripts/factory/build_hotbar.gd`
- Create: `scenes/factory/build_hotbar.tscn`

- [ ] **Step 1**: Write `build_hotbar.gd`

```gdscript
extends Control
## Visible only when BuildController.active is true. Shows 4 tool slots + belt sub-row.

@onready var _slot_labels: Array = [
    $Panel/HBox/Slot1, $Panel/HBox/Slot2, $Panel/HBox/Slot3, $Panel/HBox/Slot4,
]
@onready var _belt_sub: Control = $Panel/BeltSub
@onready var _belt_sub_labels: Array = [
    $Panel/BeltSub/HBox/Sub1, $Panel/BeltSub/HBox/Sub2, $Panel/BeltSub/HBox/Sub3,
]

func _ready() -> void:
    BuildController.active_changed.connect(_on_active_changed)
    BuildController.selection_changed.connect(_on_selection_changed)
    visible = BuildController.active
    _refresh()

func _on_active_changed(active: bool) -> void:
    visible = active

func _on_selection_changed(_tool: int, _sub: int) -> void:
    _refresh()

func _refresh() -> void:
    for i: int in _slot_labels.size():
        var lbl: Label = _slot_labels[i]
        lbl.modulate = Color.YELLOW if BuildController.current_tool == i else Color.WHITE
    _belt_sub.visible = (BuildController.current_tool == BuildController.Tool.BELT)
    if _belt_sub.visible:
        for i: int in _belt_sub_labels.size():
            var lbl: Label = _belt_sub_labels[i]
            lbl.modulate = Color.YELLOW if BuildController.current_belt_sub == i else Color.WHITE
```

- [ ] **Step 2**: Build `build_hotbar.tscn` in editor

Tree:
```
Control (script attached, anchors: bottom-center)
└── Panel
    ├── HBox
    │   ├── Slot1 (Label "[1] Loader")
    │   ├── Slot2 (Label "[2] Smelter")
    │   ├── Slot3 (Label "[3] Forge")
    │   └── Slot4 (Label "[4] Belt")
    └── BeltSub
        └── HBox
            ├── Sub1 (Label "[R] Straight")
            ├── Sub2 (Label "Corner")
            └── Sub3 (Label "T")
```

- [ ] **Step 3**: Add `build_hotbar.tscn` as a child of `main.tscn` (so it persists across the game).

- [ ] **Step 4**: Verify by toggling build mode (after Task 15) and watching the hotbar appear/hide.

- [ ] **Step 5**: Commit

```bash
git add scripts/factory/build_hotbar.gd scenes/factory/build_hotbar.tscn scenes/main.tscn
git commit -m "feat(factory): add build mode hotbar UI"
```

---

## Task 15: Register input actions + autoload BuildController

**Files:**
- Modify: `project.godot`

- [ ] **Step 1**: Add to `[input]` section:

```ini
build_toggle={
"deadzone": 0.5,
"events": [Object(InputEventKey,"physical_keycode":66)]   ; B
}
build_place={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"button_index":1)]   ; LMB
}
build_remove={
"deadzone": 0.5,
"events": [Object(InputEventKey,"physical_keycode":88)]   ; X (modifier — checked alongside LMB by BuildController if needed)
}
build_rotate={
"deadzone": 0.5,
"events": [Object(InputEventKey,"physical_keycode":82)]   ; R
}
build_slot_1={
"deadzone": 0.5,
"events": [Object(InputEventKey,"physical_keycode":49)]   ; 1
}
build_slot_2={
"deadzone": 0.5,
"events": [Object(InputEventKey,"physical_keycode":50)]   ; 2
}
build_slot_3={
"deadzone": 0.5,
"events": [Object(InputEventKey,"physical_keycode":51)]   ; 3
}
build_slot_4={
"deadzone": 0.5,
"events": [Object(InputEventKey,"physical_keycode":52)]   ; 4
}
machine_interact={
"deadzone": 0.5,
"events": [Object(InputEventKey,"physical_keycode":69)]   ; E
}
```

(Note: `build_place` shares LMB with the existing `mine` action — `BuildController` only handles it when `active == true`, so player input handlers should suppress mining when build mode is on.)

- [ ] **Step 2**: Add to `[autoload]` section after `FactoryWorld=`:

```
BuildController="*res://scripts/factory/build_controller.gd"
```

- [ ] **Step 3**: Find the script that currently handles the `mine` action — it's `scripts/miner.gd` per the project survey, but verify with `mcp__godot-ai__script_manage` op `read` first. Modify it to early-return on `mine` action if `BuildController.active`. Also: BuildController treats `build_remove` (X) and `build_place` (LMB) as separate actions — to honor the spec's "hold X + LMB" intent, gate `_try_remove()` on `Input.is_action_pressed("build_remove")` being true at the moment of LMB click instead of treating X as its own trigger. Update `_input` in BuildController accordingly:

```gdscript
elif event.is_action_pressed("build_place"):
    if Input.is_action_pressed("build_remove"):
        _try_remove()
    else:
        _try_place()
```

(Remove the standalone `elif event.is_action_pressed("build_remove"): _try_remove()` branch.)

- [ ] **Step 4**: Run main scene, verify B toggles build mode (check `mcp__godot-ai__logs_read` for any errors and that `BuildController.active` flips).

- [ ] **Step 5**: Commit

```bash
git add project.godot scripts/miner.gd
git commit -m "feat(factory): register build mode input actions + BuildController autoload"
```

---

## Task 16: FactoryWorld.place() and remove() implementations

**Files:**
- Modify: `scripts/factory/factory_world.gd`

- [ ] **Step 1**: Implement `place()` and `remove()`

```gdscript
const KIND_TO_SCENE: Dictionary = {
    &"loader": "res://scenes/factory/loader.tscn",
    &"smelter": "res://scenes/factory/smelter.tscn",
    &"forge": "res://scenes/factory/forge.tscn",
    &"belt_straight": "res://scenes/factory/belt_straight.tscn",
    &"belt_corner": "res://scenes/factory/belt_corner.tscn",
    &"belt_t": "res://scenes/factory/belt_t.tscn",
}

func place(kind: StringName, origin_cell: Vector3i, rotation_steps: int) -> bool:
    var scene_path: String = KIND_TO_SCENE.get(kind, "")
    if scene_path == "":
        return false
    var ps: PackedScene = load(scene_path)
    var node: Node3D = ps.instantiate()
    get_tree().current_scene.add_child(node)
    var cells_to_register: Array[Vector3i] = []
    if node is Building:
        var bld: Building = node as Building
        bld.origin_cell = origin_cell
        bld.rotation_steps = rotation_steps
        bld.global_position = Vector3(origin_cell.x, origin_cell.y, origin_cell.z)
        bld.rotation = Vector3(0, -PI / 2 * rotation_steps, 0)
        cells_to_register = bld.get_footprint_cells()
    elif node is BeltCell:
        var bc: BeltCell = node as BeltCell
        var facing: Vector3i = _auto_facing_for(origin_cell, bc.kind)
        bc.set_cell_and_facing(origin_cell, facing)
        bc.global_position = Vector3(origin_cell.x, origin_cell.y, origin_cell.z)
        cells_to_register = [origin_cell]
    # Register
    for c: Vector3i in cells_to_register:
        if not register_cell(c, node):
            push_error("FactoryWorld.place: cell collision at %s — rolling back" % c)
            for c2: Vector3i in cells_to_register:
                unregister_cell(c2)
            node.queue_free()
            return false
    if graph != null:
        graph.mark_dirty()
    _auto_flatten(cells_to_register, origin_cell.y)
    return true

func remove(cell: Vector3i) -> void:
    var owner: Node3D = get_cell_owner(cell)
    if owner == null:
        return
    var to_remove: Array[Vector3i] = []
    if owner is Building:
        var bld: Building = owner as Building
        to_remove = bld.get_footprint_cells()
        # TODO Task 22: drop items in input/output cells; refund hopper if Loader
    elif owner is BeltCell:
        to_remove = [(owner as BeltCell).cell]
        # TODO Task 22: drop occupant if any
    for c: Vector3i in to_remove:
        unregister_cell(c)
    owner.queue_free()
    if graph != null:
        graph.mark_dirty()

func _auto_facing_for(_cell: Vector3i, _kind: int) -> Vector3i:
    # TODO Task 16.1 (below): scan neighbours and pick facing.
    return Vector3i(0, 0, 1)

func _auto_flatten(cells: Array[Vector3i], target_y: int) -> void:
    # Carve flat: clear 3 voxels of headroom above each footprint cell,
    # and ensure a solid voxel exists directly under each footprint cell.
    var terrain: VoxelTerrain = get_tree().current_scene.find_child("VoxelTerrain", true, false) as VoxelTerrain
    if terrain == null:
        push_warning("FactoryWorld._auto_flatten: no VoxelTerrain found; skipping carve")
        return
    var tool: VoxelTool = terrain.get_voxel_tool()
    tool.channel = VoxelBuffer.CHANNEL_TYPE
    const SOLID_VOXEL: int = 1   # whatever the project's default ground material is — adjust if different
    const AIR: int = 0
    for c: Vector3i in cells:
        # Clear headroom above
        for dy: int in range(0, 4):
            tool.set_voxel(Vector3i(c.x, target_y + dy, c.z), AIR)
        # Ensure support below — fill if currently air
        var below_pos: Vector3i = Vector3i(c.x, target_y - 1, c.z)
        if tool.get_voxel(below_pos) == AIR:
            tool.set_voxel(below_pos, SOLID_VOXEL)
```

- [ ] **Step 2**: Manual test

Enter build mode (B), select Loader (1), place at a clear spot (LMB) — verify the loader appears, console shows no errors, voxel terrain is carved flat above it. Press X+LMB on the loader — verify it disappears and cells unregister (use `mcp__godot-ai__node_find` to confirm).

- [ ] **Step 3**: Commit

```bash
git add scripts/factory/factory_world.gd
git commit -m "feat(factory): implement place/remove with footprint registration + auto-flatten"
```

---

## Task 16.1: Belt auto-orientation

**Files:**
- Modify: `scripts/factory/factory_world.gd` (the `_auto_facing_for` stub)

- [ ] **Step 1**: Implement `_auto_facing_for`:

```gdscript
func _auto_facing_for(cell: Vector3i, kind: int) -> Vector3i:
    var off: Array[Vector3i] = [
        Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
        Vector3i(0, 0, 1), Vector3i(0, 0, -1),
    ]
    var connected: Array[Vector3i] = []
    for o: Vector3i in off:
        if _cells.has(cell + o):
            connected.append(o)
    if connected.is_empty():
        return Vector3i(0, 0, 1)   # default forward
    if kind == BeltCell.Kind.STRAIGHT:
        # Prefer the axis with 2 collinear neighbours
        for axis: Vector3i in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
            if connected.has(axis) and connected.has(-axis):
                return axis   # output toward +axis
        return connected[0]   # else output toward whichever neighbour we have
    if kind == BeltCell.Kind.CORNER:
        # Pick the perpendicular neighbour as the output side
        if connected.size() >= 2:
            return connected[1]
        return connected[0]
    if kind == BeltCell.Kind.T:
        # 3 neighbours: the "single" axis is the trunk; output is the trunk side.
        if connected.size() == 3:
            for axis: Vector3i in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
                if connected.has(axis) and connected.has(-axis):
                    # The other axis is the trunk
                    var trunk_axis: Vector3i = Vector3i(0, 0, 1) if axis == Vector3i(1, 0, 0) else Vector3i(1, 0, 0)
                    if connected.has(trunk_axis):
                        return trunk_axis
                    return -trunk_axis
        return connected[0]
    return Vector3i(0, 0, 1)
```

- [ ] **Step 2**: Re-orient existing belt neighbours when graph changes

In `register_cell` and `unregister_cell`, after the existing logic, scan the 4 horizontal neighbours of the affected cell. For any neighbour that is a `BeltCell`, recompute its facing and re-apply:

```gdscript
func _reorient_belt_neighbours(cell: Vector3i) -> void:
    var off: Array[Vector3i] = [
        Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
        Vector3i(0, 0, 1), Vector3i(0, 0, -1),
    ]
    for o: Vector3i in off:
        var n_cell: Vector3i = cell + o
        var n_owner: Node3D = _cells.get(n_cell, null)
        if n_owner is BeltCell:
            var bc: BeltCell = n_owner as BeltCell
            var new_facing: Vector3i = _auto_facing_for(n_cell, bc.kind)
            if new_facing != bc.facing:
                bc.set_cell_and_facing(n_cell, new_facing)

# Add to register_cell, after cell_registered.emit():
_reorient_belt_neighbours(cell)

# Add to unregister_cell, after cell_unregistered.emit():
_reorient_belt_neighbours(cell)
```

- [ ] **Step 3**: Place 3 straight belts in a row, verify they all face the same direction (use `mcp__godot-ai__node_get_properties` on each belt to read `facing`). Then place a building at the end of the row and verify the closest belt re-orients toward the building's input cell. Then remove the building and verify the belt's facing reverts.

- [ ] **Step 4**: Commit

```bash
git add scripts/factory/factory_world.gd
git commit -m "feat(factory): belt auto-orientation on placement + re-orient neighbours on graph change"
```

---

## Task 17 [P:C]: MachineUI recipe panel

**Files:**
- Create: `scripts/factory/machine_ui.gd`
- Create: `scenes/factory/machine_ui.tscn`

- [ ] **Step 1**: Write `machine_ui.gd`

```gdscript
extends Control
## Modal recipe panel. Bound to one Building at a time.

@onready var _name_label: Label = $Panel/Vbox/Name
@onready var _status_label: Label = $Panel/Vbox/Status
@onready var _input_label: Label = $Panel/Vbox/InputRow/Label
@onready var _output_label: Label = $Panel/Vbox/OutputRow/Label
@onready var _recipe_select: OptionButton = $Panel/Vbox/RecipeSelect
@onready var _deposit_panel: Control = $Panel/Vbox/DepositPanel

var _bound_building: Building = null

func _ready() -> void:
    visible = false
    _recipe_select.item_selected.connect(_on_recipe_selected)

func bind_to(building: Building) -> void:
    _bound_building = building
    visible = true
    _populate_recipes()
    _refresh()
    if building.has_signal("status_changed"):
        building.status_changed.connect(_on_status_changed)
    if building is Loader:
        _deposit_panel.visible = true
        _refresh_deposit_panel()
    else:
        _deposit_panel.visible = false

func unbind() -> void:
    if _bound_building != null and _bound_building.status_changed.is_connected(_on_status_changed):
        _bound_building.status_changed.disconnect(_on_status_changed)
    _bound_building = null
    visible = false

func _populate_recipes() -> void:
    _recipe_select.clear()
    if _bound_building is Loader:
        for mid: int in MaterialDefs.TIER_1_MATERIALS:
            _recipe_select.add_item(MaterialDefs.DISPLAY_NAME[mid], mid)
    elif _bound_building is Smelter:
        for mid: int in MaterialDefs.SMELT_RECIPE:
            var label: String = "%s -> %s" % [MaterialDefs.DISPLAY_NAME[mid], MaterialDefs.DISPLAY_NAME[MaterialDefs.SMELT_RECIPE[mid]]]
            _recipe_select.add_item(label, mid)
    elif _bound_building is Forge:
        for mid: int in MaterialDefs.FORGE_RECIPE:
            var label: String = "%s -> %s" % [MaterialDefs.DISPLAY_NAME[mid], MaterialDefs.DISPLAY_NAME[MaterialDefs.FORGE_RECIPE[mid]]]
            _recipe_select.add_item(label, mid)

func _on_recipe_selected(idx: int) -> void:
    var mid: int = _recipe_select.get_item_id(idx)
    if _bound_building is Loader:
        (_bound_building as Loader).selected_material = mid
    elif _bound_building is Smelter:
        (_bound_building as Smelter).recipe_input = mid
    elif _bound_building is Forge:
        (_bound_building as Forge).recipe_input = mid

func _on_status_changed(status: int) -> void:
    _status_label.text = "Status: %s" % Building.Status.find_key(status)

func _refresh() -> void:
    _name_label.text = _bound_building.get_class()
    _status_label.text = "Status: %s" % Building.Status.find_key(_bound_building.status)

func _refresh_deposit_panel() -> void:
    # Build 3 rows: Stone / Iron Ore / Gold Ore, each with "Deposit 10" + "Deposit All" buttons.
    # Reads player Miner counters (existing fields: stone, iron, gold).
    for child: Node in _deposit_panel.get_children():
        child.queue_free()
    var miner: Node = get_tree().get_first_node_in_group("player_miner")
    if miner == null:
        push_warning("MachineUI: no player_miner node found in group")
        return
    var loader: Loader = _bound_building as Loader
    var rows: Array = [
        [MaterialDefs.Material.STONE, "stone"],
        [MaterialDefs.Material.IRON_ORE, "iron"],
        [MaterialDefs.Material.GOLD_ORE, "gold"],
    ]
    for row: Array in rows:
        var mid: int = row[0]
        var miner_field: String = row[1]
        var hbox: HBoxContainer = HBoxContainer.new()
        var label: Label = Label.new()
        var hopper_count: int = loader.hopper.get(mid, 0)
        var inv_count: int = miner.get(miner_field)
        label.text = "%s — Inv: %d / Hopper: %d" % [MaterialDefs.DISPLAY_NAME[mid], inv_count, hopper_count]
        hbox.add_child(label)
        var btn_10: Button = Button.new()
        btn_10.text = "+10"
        btn_10.pressed.connect(func() -> void: _do_deposit(mid, miner_field, 10))
        hbox.add_child(btn_10)
        var btn_all: Button = Button.new()
        btn_all.text = "All"
        btn_all.pressed.connect(func() -> void: _do_deposit(mid, miner_field, 999999))
        hbox.add_child(btn_all)
        _deposit_panel.add_child(hbox)

func _do_deposit(material_id: int, miner_field: String, requested: int) -> void:
    var miner: Node = get_tree().get_first_node_in_group("player_miner")
    if miner == null or _bound_building == null:
        return
    var loader: Loader = _bound_building as Loader
    var available: int = miner.get(miner_field)
    var to_deposit: int = min(requested, available)
    if to_deposit <= 0:
        return
    var accepted: int = loader.deposit(material_id, to_deposit)
    miner.set(miner_field, available - accepted)
    if miner.has_signal("inventory_changed"):
        miner.inventory_changed.emit()
    _refresh_deposit_panel()

func _input(event: InputEvent) -> void:
    if not visible:
        return
    if event.is_action_pressed("ui_cancel"):
        unbind()
        accept_event()
```

- [ ] **Step 2**: Build `machine_ui.tscn` with the node tree the script expects (Panel > VBox > Name, Status, InputRow > Label, OutputRow > Label, RecipeSelect, DepositPanel).

- [ ] **Step 3**: Add `machine_ui.tscn` to `main.tscn`.

- [ ] **Step 4**: Wire access points:
  - In `scenes/main.tscn`, add `machine_ui.tscn` to the group `machine_ui` (Inspector → Node → Groups).
  - In the existing player scene (`scenes/player.tscn`), add the player's `Miner` child node to the group `player_miner` so MachineUI can find it for deposits.
  - In `scripts/player.gd` (or wherever `machine_interact` action is checked), on press: raycast forward 3m, if hit collider's parent (or the collider itself) is a `Building`, call `get_tree().get_first_node_in_group("machine_ui").bind_to(that_building)`.

- [ ] **Step 5**: Verify by placing a smelter, walking up, pressing E — panel opens, recipe selector populated, Esc closes.

- [ ] **Step 6**: Commit

```bash
git add scripts/factory/machine_ui.gd scenes/factory/machine_ui.tscn scenes/main.tscn scripts/player.gd
git commit -m "feat(factory): MachineUI recipe panel + E to interact"
```

---

## Task 18 [P:C]: Extend inventory_hud.gd for 9 counters

**Files:**
- Modify: `scripts/inventory_hud.gd`
- Modify: `scripts/miner.gd`

- [ ] **Step 1**: Read current `miner.gd` and `inventory_hud.gd` to see the existing flat-int counters.

- [ ] **Step 2**: Add T2 and T3 counters to `Miner` (`brick`, `block`, `iron_ingot`, `iron_bar`, `gold_ingot`, `gold_bar`) plus a generic `add_material(material_id, amount)` helper. Keep existing `stone`/`iron`/`gold` field names to avoid breaking other callers; rename HUD labels only.

- [ ] **Step 3**: Update `inventory_hud.gd` to show 3 rows × 3 columns:
```
T1: Stone: 0   Iron Ore: 0   Gold Ore: 0
T2: Brick: 0   Iron Ingot: 0  Gold Ingot: 0
T3: Block: 0   Iron Bar: 0    Gold Bar: 0
```
Connect to the existing `inventory_changed` signal (or add new signals for the new fields if appropriate).

- [ ] **Step 4**: Verify in main scene — HUD shows all 9 counters; mining stone increments the first counter as before.

- [ ] **Step 5**: Commit

```bash
git add scripts/inventory_hud.gd scripts/miner.gd
git commit -m "feat(factory): extend inventory + HUD to 9 counters (T1/T2/T3)"
```

---

## Task 19 [P:D]: Procedural animations (idle bob + glow + emit pulse)

**Files:**
- Modify: `scripts/factory/building.gd`
- Modify: each building scene to ensure they have an `OutputPort` named child + an emissive material on the body

- [ ] **Step 1**: In `building.gd`, add:

```gdscript
@export var idle_bob_amplitude: float = 0.02
@export var idle_bob_freq_hz: float = 4.0

var _bob_origin_y: float
var _body_mesh: MeshInstance3D = null
var _output_port: MeshInstance3D = null
var _emissive_material: StandardMaterial3D = null

func _ready() -> void:
    _bob_origin_y = position.y
    _body_mesh = find_child("Body", true, false) as MeshInstance3D
    _output_port = find_child("OutputPort", true, false) as MeshInstance3D
    if _body_mesh != null and _body_mesh.get_surface_override_material(0) is StandardMaterial3D:
        _emissive_material = _body_mesh.get_surface_override_material(0) as StandardMaterial3D
    item_emitted.connect(_on_emit_pulse)
    set_process(true)

func _process(delta: float) -> void:
    var working: bool = (status == Status.WORKING)
    if working:
        position.y = _bob_origin_y + sin(Time.get_ticks_msec() / 1000.0 * TAU * idle_bob_freq_hz) * idle_bob_amplitude
    else:
        position.y = lerp(position.y, _bob_origin_y, delta * 5.0)
    if _emissive_material != null:
        var target: float = 1.0 if working else 0.0
        _emissive_material.emission_energy_multiplier = lerp(
            _emissive_material.emission_energy_multiplier, target, delta * 5.0)

func _on_emit_pulse(_material_id: int) -> void:
    if _output_port == null:
        return
    var tw: Tween = create_tween()
    tw.tween_property(_output_port, "scale", Vector3.ONE * 1.2, 0.075)
    tw.tween_property(_output_port, "scale", Vector3.ONE, 0.075)
```

- [ ] **Step 2**: Update each building scene to:
- Name the body `MeshInstance3D` `Body`
- Give Body a `StandardMaterial3D` with `emission_enabled = true`
- Have a child `OutputPort` `MeshInstance3D` near the output face

- [ ] **Step 3**: Verify visually: place a loader, deposit 10 stone, watch it bob + glow when WORKING and pulse on each emit.

- [ ] **Step 4**: Commit

```bash
git add scripts/factory/building.gd scenes/factory/loader.tscn scenes/factory/smelter.tscn scenes/factory/forge.tscn
git commit -m "feat(factory): procedural building animations (bob + glow + emit pulse)"
```

---

## Task 20 [P:D]: Audio stubs

**Files:**
- Modify: each building scene (loader/smelter/forge) — add `AudioStreamPlayer3D` children
- Modify: `scripts/factory/building.gd`

- [ ] **Step 1**: Add to each building scene:
- `AudioStreamPlayer3D` named `HumLoop` (no stream assigned for now — silent stub)
- `AudioStreamPlayer3D` named `EmitClick` (no stream assigned — silent stub)

- [ ] **Step 2**: In `building.gd`, control them based on status / item_emitted:

```gdscript
@onready var _hum_loop: AudioStreamPlayer3D = find_child("HumLoop", true, false) as AudioStreamPlayer3D
@onready var _emit_click: AudioStreamPlayer3D = find_child("EmitClick", true, false) as AudioStreamPlayer3D

# In status setter (or _process):
func _update_audio() -> void:
    if _hum_loop == null: return
    var should_play: bool = (status == Status.WORKING)
    if should_play and not _hum_loop.playing and _hum_loop.stream != null:
        _hum_loop.play()
    elif not should_play and _hum_loop.playing:
        _hum_loop.stop()

# In _on_emit_pulse(material_id: int):
if _emit_click != null and _emit_click.stream != null:
    var tier: int = MaterialDefs.TIER.get(material_id, 1)
    _emit_click.pitch_scale = 0.8 + 0.2 * tier   # T1 = 1.0, T2 = 1.2, T3 = 1.4
    _emit_click.play()
```

- [ ] **Step 3**: Check `assets/audio/` for any existing usable hum/clunk sounds; if found, assign them. Else leave silent.

- [ ] **Step 4**: Commit

```bash
git add scripts/factory/building.gd scenes/factory/loader.tscn scenes/factory/smelter.tscn scenes/factory/forge.tscn
git commit -m "feat(factory): audio stubs (silent until assets land)"
```

---

## Task 21 [P:D]: Forge overflow tracking

**Files:**
- Modify: `scripts/factory/forge.gd`

- [ ] **Step 1**: Implement `_is_overflowing()`:

```gdscript
const OVERFLOW_RADIUS: float = 5.0
const OVERFLOW_CAP: int = 50

func _is_overflowing() -> bool:
    var drops: Node = get_tree().get_first_node_in_group("factory_drops")
    if drops == null:
        return false
    var count: int = 0
    var origin: Vector3 = global_position
    for child: Node in drops.get_children():
        if child is RigidBody3D:
            if (child as RigidBody3D).global_position.distance_to(origin) <= OVERFLOW_RADIUS:
                count += 1
                if count > OVERFLOW_CAP:
                    return true
    return false
```

(Drops are created in Task 22; this code tolerates the missing group node returning false.)

- [ ] **Step 2**: Verify forge still functions normally (no overflow yet since Task 22 hasn't shipped drops).

- [ ] **Step 3**: Commit

```bash
git add scripts/factory/forge.gd
git commit -m "feat(factory): forge overflow detection (counts physics drops in 5m radius)"
```

---

## Task 22 [P:D]: Belt removal item-drop + dead-end drops

**Files:**
- Modify: `scripts/factory/factory_world.gd`
- Create: `scenes/factory/factory_drop.tscn`

- [ ] **Step 1**: Create `scenes/factory/factory_drop.tscn`

Root: `RigidBody3D`. Children: `MeshInstance3D` (small box, color set via script based on material_id), `CollisionShape3D` (small `BoxShape3D`). Add to group `factory_drops`. Script `factory_drop.gd`:

```gdscript
class_name FactoryDrop
extends RigidBody3D

@export var material_id: int = -1

func _ready() -> void:
    add_to_group("factory_drops")
    # color the mesh based on material_id (lookup in MaterialDefs)
```

- [ ] **Step 2**: In `factory_world.gd`, add helper:

```gdscript
func spawn_drop(material_id: int, world_pos: Vector3, impulse: Vector3 = Vector3.ZERO) -> void:
    var ps: PackedScene = load("res://scenes/factory/factory_drop.tscn")
    var drop: FactoryDrop = ps.instantiate()
    drop.material_id = material_id
    get_tree().current_scene.add_child(drop)
    drop.global_position = world_pos
    if impulse != Vector3.ZERO:
        drop.apply_central_impulse(impulse)
```

- [ ] **Step 3**: In `_tick_belts`, after the advancement loop, scan for cells with `blocked_ticks >= 2` (item has been waiting too long with no output). For each such cell, spawn a drop and recycle the item:

```gdscript
# After the per-cell advancement loop in _tick_belts:
const DEAD_END_DROP_THRESHOLD: int = 2

for c: Vector3i in belt_cells:
    var bc: BeltCell = _cells[c] as BeltCell
    if bc.occupant != null and bc.blocked_ticks >= DEAD_END_DROP_THRESHOLD:
        var item: FactoryItem = bc.occupant
        var mid: int = item.material_id
        var drop_pos: Vector3 = bc.cell_center_world() + Vector3(bc.facing.x, 0, bc.facing.z) * 0.5
        var impulse: Vector3 = Vector3(bc.facing.x, 0.5, bc.facing.z) * 0.5
        bc.clear_item()
        item_pool.release(item)
        spawn_drop(mid, drop_pos, impulse)
```

- [ ] **Step 4**: Update `remove()` to drop items + refund hopper:

```gdscript
func remove(cell: Vector3i) -> void:
    var owner: Node3D = get_cell_owner(cell)
    if owner == null:
        return
    var to_remove: Array[Vector3i] = []
    if owner is Building:
        var bld: Building = owner as Building
        to_remove = bld.get_footprint_cells()
        # Refund Loader hopper to player Miner
        if bld is Loader:
            var loader: Loader = bld as Loader
            var miner: Node = get_tree().get_first_node_in_group("player_miner")
            if miner != null:
                if loader.hopper.get(MaterialDefs.Material.STONE, 0) > 0:
                    miner.set("stone", miner.get("stone") + loader.hopper[MaterialDefs.Material.STONE])
                if loader.hopper.get(MaterialDefs.Material.IRON_ORE, 0) > 0:
                    miner.set("iron", miner.get("iron") + loader.hopper[MaterialDefs.Material.IRON_ORE])
                if loader.hopper.get(MaterialDefs.Material.GOLD_ORE, 0) > 0:
                    miner.set("gold", miner.get("gold") + loader.hopper[MaterialDefs.Material.GOLD_ORE])
                if miner.has_signal("inventory_changed"):
                    miner.inventory_changed.emit()
        # Drop items in input/output cells
        for cell_to_check: Vector3i in (bld.get_input_cells() + bld.get_output_cells()):
            var n_owner: Node3D = get_cell_owner(cell_to_check)
            if n_owner is BeltCell:
                var bc: BeltCell = n_owner as BeltCell
                if bc.occupant != null:
                    var item: FactoryItem = bc.occupant
                    var mid: int = item.material_id
                    bc.clear_item()
                    item_pool.release(item)
                    spawn_drop(mid, bc.cell_center_world() + Vector3(0, 0.3, 0))
    elif owner is BeltCell:
        var bc: BeltCell = owner as BeltCell
        to_remove = [bc.cell]
        if bc.occupant != null:
            var item: FactoryItem = bc.occupant
            var mid: int = item.material_id
            bc.clear_item()
            item_pool.release(item)
            spawn_drop(mid, bc.cell_center_world() + Vector3(0, 0.3, 0))
    for c2: Vector3i in to_remove:
        unregister_cell(c2)
    owner.queue_free()
    if graph != null:
        graph.mark_dirty()
```

- [ ] **Step 5**: Add player pickup: in `scripts/player.gd`, add an `Area3D` child to the player (or use the existing one) configured to detect bodies on the `factory_drops` group. On `body_entered`, if body is a `FactoryDrop`, add to the player's `Miner` counters (use the new T2/T3 fields from Task 18) and queue_free the drop.

- [ ] **Step 6**: Verify: build a loader→1 belt→nothing line, deposit 10 stone, watch stones drop off the belt edge as physics objects, walk over them and confirm pickup credits inventory.

- [ ] **Step 7**: Commit

```bash
git add scripts/factory/factory_world.gd scenes/factory/factory_drop.tscn scripts/factory/factory_drop.gd scripts/player.gd
git commit -m "feat(factory): dead-end drops + belt-removal drops + hopper refund + player pickup"
```

---

## Task 23: Final integration tests

**Files:**
- (No files to commit unless bugs are found.)

Run the 8 manual tests from the spec:

- [ ] **Test 1 — stone end-to-end**: Place 1 Loader → 3 belts → Smelter → 3 belts → Forge → 3 belts dead-ending. Deposit 10 stone. Verify 10 Blocks pile at end. Document with screenshots.

- [ ] **Test 2 — recipe mismatch**: While running, switch Smelter recipe to Iron Ingot. Verify Stone item sits at Smelter input, status badge in MachineUI shows `INPUT_JAMMED`, Forge goes IDLE.

- [ ] **Test 3 — T merger**: 2 Loaders → T → 1 Smelter. Both Loaders deposit different times; Smelter never starves while either has stock.

- [ ] **Test 4 — T splitter**: 1 Loader → T → 2 Smelters. Verify alternating output.

- [ ] **Test 5 — optimal layout**: Full 1:2:4. Run for 60s. Verify zero idle ticks at any building.

- [ ] **Test 6 — belt removed mid-flow**: Pull a belt out from under an item. Item drops cleanly.

- [ ] **Test 7 — build mode UX**: B toggle, ghost colors, R rotate, X+LMB removes correctly.

- [ ] **Test 8 — overflow**: Forge with no destination, run loader 5 min, verify OVERFLOWING after 50 drops, picking up resumes.

- [ ] **Soak test**: 4 parallel optimal lines (1 stone, 2 iron, 1 gold), 5 minutes. Eyeball: framerate ≥ 60fps, no item desync, no vanishes.

- [ ] **Commit any bug fixes found during testing as separate commits.**

---

## Done criteria

- All 8 manual tests pass.
- Soak test runs ≥ 5 minutes at ≥ 60fps without item desync or vanishes.
- No item ever overlaps another in a cell (verified by reading `BeltCell.occupant` for all belts at random tick samples).
- Design doc and plan committed to repo.
