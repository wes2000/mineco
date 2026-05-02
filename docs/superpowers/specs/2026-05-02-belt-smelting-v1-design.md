# Belt-Driven Smelting v1 — Design

**Date:** 2026-05-02
**Status:** Approved (brainstorm complete)
**Author:** Claude (brainstormed with whann)

## Summary

Adds the first automation system to Mine Co.: three placeable production buildings (Loader, Smelter, Forge) connected by three belt piece types (Straight, 90° Corner, T-junction). Players deposit mined ore into a Loader, the line transports it through a Smelter (T1→T2) and Forge (T2→T3), and final products pile up as physics drops at the belt's end. Introduces the project's first placement system, first item-on-belt simulation, and first per-machine recipe UI. Single mega-spec covers all five new subsystems (placement, belt graph, item entities, machines, UI).

## Goals

1. Player can build a working ore-processing line end-to-end: deposit ore → automated processing → pile of finished products.
2. Optimal-throughput layout is teachable: **1 Loader : 2 Smelters : 4 Forges** for any ore type.
3. The simulation is deterministic, smooth, and scales to multiple parallel lines without framerate impact.
4. The placement system is reusable for future machines/buildings beyond this spec.

## Non-Goals

- Persistence (placed buildings/items reset on game restart, matching current project scope).
- Power, fuel, or other input requirements beyond ore.
- Storage chests or output containers (T3 outputs pile as physics drops).
- Inclined/vertical belts (defer to a later round).
- Tier-locking or research progression.
- Networked multiplayer.

## Player-facing summary

- **Press B** to enter build mode. Hotbar shows `[1] Loader [2] Smelter [3] Forge [4] Belt`. Press R to cycle belt sub-kind (Straight / Corner / T) or rotate building ghosts.
- Place buildings on voxel terrain — the footprint auto-flattens when placed.
- **Press E** while looking at a machine to open its recipe panel.
- **Loader**: deposit any of your mined ores into its internal hopper, then select which one to output.
- **Smelter**: select one of three recipes (`Stone→Brick`, `Iron Ore→Iron Ingot`, `Gold Ore→Gold Ingot`). Wrong materials at the input jam the line.
- **Forge**: same pattern for T2→T3 (`Brick→Block`, `Iron Ingot→Iron Bar`, `Gold Ingot→Gold Bar`).
- Final products fall off the end of an unconnected belt as physics drops; pick them up by walking over and interacting.

## Materials

| T1 (mined) | T2 (smelted) | T3 (forged) |
|---|---|---|
| Stone | Brick | Block |
| Iron Ore | Iron Ingot | Iron Bar |
| Gold Ore | Gold Ingot | Gold Bar |

Existing inventory HUD labels `Iron` / `Gold` rename to `Iron Ore` / `Gold Ore` for tier consistency. Internal enum names unchanged.

## Throughput model

All times measured in **simulation ticks**: 1 tick = 0.1s, simulation runs at 10 Hz.

| Material | Loader emit interval | Smelter cycle | Forge cycle |
|---|---|---|---|
| Stone | 10 ticks (1.0s) | 20 ticks (2.0s) → Brick | 40 ticks (4.0s) → Block |
| Iron Ore | 20 ticks (2.0s) | 40 ticks (4.0s) → Ingot | 80 ticks (8.0s) → Bar |
| Gold Ore | 40 ticks (4.0s) | 80 ticks (8.0s) → Ingot | 160 ticks (16.0s) → Bar |

Belt speed: **10 ticks per cell** (1 cell/sec) — same for all belts.

**Optimal layout for any ore = 1 Loader : 2 Smelters : 4 Forges** (each stage doubles its building count, since each stage's per-item time also doubles).

End-to-end output rate of an optimally-built line equals the loader's emit rate (steady state):
- Stone: 1 Block / sec
- Iron: 1 Iron Bar / 2 sec
- Gold: 1 Gold Bar / 4 sec

Rarity costs both in *building footprint* (the optimal layout is the same shape but each stage's cycle takes longer) AND in *end-to-end throughput* (rarer ore lines emit slower).

## Architecture

Eight units, communicating via signals and small typed APIs.

### Units

1. **`MaterialDefs`** (`scripts/factory/material_defs.gd`) — single source of truth for the 9 materials, their times, recipe maps, and tier lookups. Pure data, no nodes.
2. **`FactoryWorld`** (autoload, `scripts/factory/factory_world.gd`) — owns the cell registry (`Dictionary[Vector3i, Node3D]`), runs the 10 Hz simulation tick that drives belts and machines. Single tick source = no race conditions between belt and machine logic.
3. **`BeltGraph`** (`scripts/factory/belt_graph.gd`) — pure logic; given the cell registry, exposes `neighbour_in(cell)`, `neighbour_out(cell)`, junction queries. Holds per-T-junction round-robin counters. Knows nothing about visuals.
4. **`BeltCell`** (`scripts/factory/belt_cell.gd` on `scenes/factory/belt_*.tscn`) — one Node3D per placed belt piece. Holds `kind` (Straight/Corner/T), `facing`, current `Item` occupant, mesh. Auto-orients on place via neighbour scan.
5. **`Building`** (`scripts/factory/building.gd`) — base class with shared state machine. `Loader`, `Smelter`, `Forge` extend it.
6. **`Item`** (`scripts/factory/item.gd`, pooled) — visible mesh that rides cells. Holds `material_id`, current `cell`, `move_start_time`, `move_duration`. Per-frame `_process` lerps `position` between cell centers.
7. **`BuildController`** (autoload, `scripts/factory/build_controller.gd`) — handles B-toggle, hotbar input, ghost preview, raycast, validation, place/remove calls.
8. **`MachineUI`** (`scripts/factory/machine_ui.gd` on `scenes/factory/machine_ui.tscn`) — single shared modal `Control`. Bound to whichever `Building` the player interacted with most recently. Closes on Esc.

### Key invariants

- A cell is occupied by **at most one item** at any logical moment.
- A T-junction's role (merger vs splitter) is **derived** from neighbours each tick, never stored.
- All time measured in **sim ticks**; recipes and belt speed are integer ticks.
- `BeltGraph` mutates only on place/remove events; the 10 Hz tick reads it without mutating.

### Autoloads

Two new autoloads are added in `project.godot` alongside the existing `_mcp_game_helper`, `Atmosphere`, and `Admin`. **Order matters**: `FactoryWorld` must be registered **before** `BuildController` (BuildController calls `FactoryWorld.place()` / `remove()` and resolves the singleton at autoload time). Recommended order: `_mcp_game_helper`, `Atmosphere`, `Admin`, `FactoryWorld`, `BuildController`.

### File layout

```
scripts/factory/
  material_defs.gd       factory_world.gd     belt_graph.gd
  belt_cell.gd           building.gd          loader.gd
  smelter.gd             forge.gd             item.gd
  item_pool.gd           build_controller.gd  machine_ui.gd

scenes/factory/
  belt_straight.tscn  belt_corner.tscn  belt_t.tscn
  loader.tscn  smelter.tscn  forge.tscn
  item_stone.tscn  item_brick.tscn  item_block.tscn
  item_iron_ore.tscn  item_iron_ingot.tscn  item_iron_bar.tscn
  item_gold_ore.tscn  item_gold_ingot.tscn  item_gold_bar.tscn
  ghost_overlay.tscn  machine_ui.tscn  build_hotbar.tscn
```

## Belt graph & simulation

### Cell registry

`FactoryWorld._cells: Dictionary[Vector3i, Node3D]`. Keys are voxel cell coordinates (Y included so future inclined belts have a home). Values point back to the placed Node — for buildings with multi-cell footprints, every footprint cell points to the same `Building` instance.

### Auto-orientation on belt place

After registering a new belt cell, scan its 4 horizontal cell neighbours:

- **Straight**: align facing to whichever axis has 2 collinear belt-or-building neighbours. With 0 or 1 neighbours, default to player-facing axis.
- **Corner**: detect 2 perpendicular neighbours, bridge them. With other configurations, place with default facing — player can replace.
- **T**: with 3 neighbours, the "single" side is the trunk; the perpendicular pair are branches. With 2 neighbours, behaves as a corner using default trunk facing.

Re-orientation triggers when neighbours change. A belt's facing is recomputed when (a) it is first placed and (b) any of its 4 neighbours is placed or removed.

### Per-cell flow direction

Every cell has 0–N **input neighbours** and 0–N **output neighbours**, resolved deterministically:

- **Building neighbours**: a building cell that the building marks as an *output* face (Loader output, Smelter/Forge output) is an input neighbour to the adjacent belt; a building's *input* face is an output neighbour. Building input/output faces come from the building's `rotation`.
- **Belt neighbours**: an adjacent belt is an **input neighbour** if its `facing` vector points *into* this cell (i.e. its output side is on the shared edge); it is an **output neighbour** if its facing points *out* of this cell (its input side is on the shared edge).
- A cell with two adjacent belts both pointing inward is a *valid* merger (e.g. T-junction in merger configuration). Two belts both pointing outward is a *valid* splitter.
- Mismatches (e.g. two belts both pointing away from a Straight cell) leave the Straight with no valid in/out and it sits unused — flagged in the editor by a red edge highlight.

### T-junction role

A T-junction is just a cell with 3 connected neighbours. Its role is whatever falls out of the per-cell rules above:
- 2 input neighbours + 1 output neighbour → **merger** (round-robin between the 2 inputs).
- 1 input neighbour + 2 output neighbours → **splitter** (round-robin between the 2 outputs).
- Any other configuration (1+1, 3+0, 0+3) → unused / flagged as misconfigured.

The round-robin counter is per-T-cell, persists across ticks, and increments only on **successful** flow (so a blocked side does not advance the counter — the next available side wins next tick).

### Tick step (10 Hz, ordered)

1. **Building tick** — for each building: advance its internal timer. If timer expired and output cell is free → spawn output `Item` to output cell, reset state to IDLE. If input cell has a matching-recipe item → consume (free that cell), set state to WORKING with `timer = recipe_duration_ticks`.
2. **Belt tick** — see ordering algorithm below.

### Belt tick ordering algorithm

Each tick, iterate occupied belt cells in **reverse-BFS order from sinks**:

1. **Sinks** = cells whose only output neighbours are (a) building input cells, or (b) "off the end" (no output neighbour at all).
2. Run BFS *backwards* along input-edges from each sink, assigning each visited cell a depth (sinks = 0, one step back = 1, etc.). Cells reachable from multiple sinks take the minimum depth.
3. Process occupied cells **lowest depth first** (sinks before mid-belt before sources). This guarantees that any cell ahead of cell N has already been processed — so when cell N checks "is my output neighbour free?", the answer reflects the current tick's movement.
4. **Cycles** (e.g. player wires a loop) are unreachable from any sink and end up with depth = `INF`. They are processed last, in arbitrary order. Items in pure cycles will eventually all stall (no sink to drain into); this is by design and surfaces as a visible jam.
5. The BFS recomputes only when the belt graph mutates (place/remove); steady-state ticks reuse the cached order.

For each occupied cell whose item's `move_duration` has elapsed: query `BeltGraph.choose_output(cell)` (which applies T-junction round-robin if multiple output neighbours exist). If the chosen target cell is free, swap occupancy and set `move_start_time = now`, `move_duration = belt_speed_ticks * tick_dt`. The round-robin counter increments on success only.

### Item visual

Per-frame in `Item._process(delta)`:

```gdscript
var t: float = clamp((Time.get_ticks_msec() / 1000.0 - _move_start_time)
                     / _move_duration, 0.0, 1.0)
global_position = _prev_cell_center.lerp(_current_cell_center, t)
```

### Backpressure

Implicit. If `neighbour_out(cell)` is occupied, the item sits. A smelter "input jam" is just a recipe-mismatched item occupying its input cell.

### Items off a dead-end belt

A belt cell with no out-neighbour and an item that has failed to advance for ≥1 full tick: spawn a `RigidBody3D` drop at the cell's exit edge with a small forward impulse, recycle the `Item` Node3D back to the pool. Drops are persistent physics objects until the player picks them up.

**Forge overflow protection**: each forge counts physics drops within 5m of itself. If count > 50 → status `OVERFLOWING`, processing halts. Status clears when count drops back below 50 (player picks up some).

## Buildings

### Shared state machine (`Building` base class)

```
IDLE ──(input present + recipe match)──▶ WORKING
                                              │
                                              ├──(timer done + output free)──▶ emit, IDLE
                                              └──(timer done + output blocked)──▶ OUTPUT_BLOCKED
                                                                                       │
                                                                                       └──(output free)──▶ emit, IDLE

(Loader: no input states; emits when hopper has stock + output free)
(Any building: input cell occupied by mismatched item → INPUT_JAMMED)
(Forge only: drops within 5m > 50 → OVERFLOWING)
```

Status enum: `IDLE / WORKING / OUTPUT_BLOCKED / INPUT_JAMMED / OVERFLOWING`.

### Loader (`scripts/factory/loader.gd`)

- Footprint: 2×2 cells.
- No input cell. Internal hopper: `Dictionary[Material, int]`, cap 999 per material.
- Player deposits via `MachineUI` "Deposit ore" panel.
- Selected output material drives the cycle. Emits 1 item to output cell every `loader_emit_time_ticks(material)` ticks if hopper has ≥1 of selected material AND output cell is free.
- Output cell: 1 cell on the building's "front" face (rotation-dependent).

### Smelter (`scripts/factory/smelter.gd`)

- Footprint: 2×2 cells.
- 1 input cell on back face, 1 output cell on front face.
- Recipe: one of `Stone→Brick`, `Iron Ore→Iron Ingot`, `Gold Ore→Gold Ingot`.
- Consumes input only if material matches recipe; otherwise input cell stays occupied → `INPUT_JAMMED`.
- Cycle time = `smelt_time_ticks(input_material)`.

### Forge (`scripts/factory/forge.gd`)

- Footprint: 3×3 cells.
- Otherwise identical to Smelter, with T2→T3 recipes: `Brick→Block`, `Iron Ingot→Iron Bar`, `Gold Ingot→Gold Bar`.
- Cycle time = `forge_time_ticks(input_material)`.
- Tracks overflow as described above.

### Rotation

Player rotates ghost in 90° steps with **R** during placement; the chosen rotation determines which faces are input/output for that building.

### Animation hooks

`Building` base class fires `signal item_emitted()` on emit (drives output-port pulse animation). A `running: bool` property drives an emissive glow material parameter and a small idle bob.

## Build mode & placement

### Toggle

**B** flips `BuildController.active`. Esc also exits.

### While active

- Crosshair raycasts the voxel terrain to find a target cell. Ghost mesh renders at that cell.
- Hotbar (`build_hotbar.tscn`) visible at bottom of screen: `[1] Loader [2] Smelter [3] Forge [4] Belt`.
- Number keys 1–4 select the active item. When `4` (Belt) is selected, a sub-row appears: `[R] Straight | Corner | T`, R cycles between them.
- For buildings, R rotates the ghost in 90° steps.
- Ghost color: green = placeable, red = blocked.
- Validation: every footprint cell must (a) be in world bounds, (b) not already be in `FactoryWorld._cells`, (c) sit above non-air voxel terrain.
- **Left-click**: `FactoryWorld.place(kind, origin_cell, rotation)` → auto-flattens footprint via voxel sphere-carve to a flat surface at the target Y → registers cells → instantiates the building/belt scene.
- **Hold X + left-click** on a placed thing: `FactoryWorld.remove(cell)` → for buildings, drops items in input/output cells and refunds hopper contents to the player's inventory; for belts, items on the belt drop on the ground.

## UI

### Recipe panel (`machine_ui.tscn`, single shared `Control`)

Opened on **E** when the crosshair is on a machine within 3m. Modal — pauses player movement input but not the simulation.

- Header: machine name + status badge (color-coded by `IDLE / WORKING / OUTPUT_BLOCKED / INPUT_JAMMED / OVERFLOWING`).
- Input row: icon + count of current input material (or "N/A" for Loader).
- Output row: icon + count of current output material.
- Recipe `OptionButton`: lists the 3 recipes for that machine type.
- Loader-only deposit panel: for each ore in player inventory, +/- buttons + "Deposit all" + per-material count display.
- Esc or click-outside closes.

### Build hotbar (`build_hotbar.tscn`)

Visible only when build mode is on. 4 icon squares + key hints. Belt sub-row reveals when Belt is selected.

### Inventory HUD

Extend existing `inventory_hud.gd` to show 9 counters grouped by tier (T1 row, T2 row, T3 row). Rename existing `Iron` / `Gold` HUD labels to `Iron Ore` / `Gold Ore` for T1 consistency.

## Polish

### Animation (procedural — no skeletal anims)

- **Running**: ±2cm Y-bob at 4Hz on building mesh + emissive glow material parameter `glow_intensity` lerped to 1.0 when WORKING, 0.0 otherwise.
- **Emit pulse**: `Tween` scales the building's "output port" mesh from 1.0 → 1.2 → 1.0 over 0.15s on each `item_emitted()` signal.
- **Item drops**: physics handles itself (Jolt is already enabled).

### Audio

- Per-machine `AudioStreamPlayer3D` with looped low hum, volume tied to running state.
- One-shot "clunk" on each emit, pitched up by tier (T1 low → T3 high).
- Asset stubs silent until polish pass; reuse anything appropriate from `assets/audio/`.

## Edge cases

| Case | Behaviour |
|---|---|
| Belt removed mid-transit | Item drops as physics object at its current visual position |
| Building removed mid-cycle | In-flight item forfeit; hopper refunded to player inventory |
| Player inventory at cap when picking up | Drop persists; no despawn |
| Loader hopper at cap (999) | Reject deposit; deposit panel shows "Full" |
| Two T-junctions adjacent | Each owns its round-robin counter independently |
| Voxel terrain mined under a placed building | Building stays "floating" — no auto-collapse this spec |
| Recipe switched mid-cycle | Current cycle completes; subsequent cycles use new recipe |
| Belt placed disconnected from any building | Just sits; auto-orients to player facing |

## Testing approach

Manual tests (no test framework currently in project — matches existing pattern in `mining-mvp` and `mining-depth-r1` specs):

1. **Stone end-to-end**: 1 Loader → 3 belts → Smelter → 3 belts → Forge → 3 belts dead-ending. Deposit 10 stone. Verify: 10 Stone become 10 Bricks become 10 Blocks; Blocks pile at end as physics drops.
2. **Recipe mismatch**: switch Smelter recipe to Iron Ingot during a stone run → verify Stone item sits at input, Smelter status `INPUT_JAMMED`, downstream goes idle.
3. **T merger**: 2 Loaders → T → 1 Smelter → verify alternating consumption, Smelter never starves while either Loader has stock.
4. **T splitter**: 1 Loader → T → 2 Smelters → verify alternating output, both Smelters stay busy.
5. **Optimal layout**: 1 Loader → T-split to 2 Smelters → 2 T-splits to 4 Forges (full optimal topology). Run 60s. Verify zero idle ticks at any building (full pipeline saturation).
6. **Belt removed mid-flow**: pull a belt out from under an item → verify item drops cleanly, downstream backpressure clears.
7. **Build mode UX**: B toggles, ghost shows green/red correctly on slope/water/occupied cells, R rotates buildings + cycles belt sub-kind, X+click removes with proper refund.
8. **Forge overflow**: Forge with no output destination → run Loader for 5 minutes → verify pile builds up, Forge transitions to `OVERFLOWING` after 50 drops, picking up drops resumes work.

**Soak test**: 4 parallel optimal lines (1 Stone, 2 Iron, 1 Gold) running for 5 minutes. Eyeball: framerate ≥ 60fps, no item position desync, no items vanish.

**Done criteria**: all 8 manual tests pass; no item ever overlaps another in a cell; no item ever vanishes mid-flow; framerate ≥ 60fps with the soak test load.

## Out of scope (future rounds)

- Save/load persistence for placed buildings, belts, items, hopper contents.
- Inclined / vertical belt pieces.
- Storage / chest buildings as alternative to floor-pile output.
- Power, fuel, or coal input.
- Tool/research progression that gates buildings.
- Networking / multiplayer.
- Authored building animations (currently procedural).
- Curated audio (currently placeholder).
- Auto-collapse of buildings when their supporting voxel terrain is mined.
