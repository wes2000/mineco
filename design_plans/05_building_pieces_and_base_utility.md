# Agent Coding Prompt

You are working on the Godot 4.6 project "Mine Co." through the available Godot MCP/project files.

Your task is to implement this design brief only.

Important project context:
- Main scene: `res://scenes/main.tscn`
- Player scene: `res://scenes/player.tscn`
- Core scripts include:
  - `res://scripts/player.gd`
  - `res://scripts/miner.gd`
  - `res://scripts/stamina.gd`
  - `res://scripts/vendor_ui.gd`
  - `res://scripts/contract_board.gd`
  - `res://scripts/claim_vendor_board.gd`
  - `res://scripts/island_voxel_generator.gd`
  - `res://scripts/ore_generator.gd`
  - `res://scripts/factory/build_controller.gd`
  - `res://scripts/factory/factory_world.gd`
  - `res://scripts/factory/material_defs.gd`
- Existing autoloads include `BuildController`, `FactoryWorld`, `MapData`, and `Admin`.
- Existing gameplay already includes mining, gold currency, vendors, contracts, land claims, boats, scanner, minimap/fog, and basic factories.

Working rules:
- First inspect the relevant existing files listed in the brief.
- Preserve existing behavior unless the brief explicitly changes it.
- Prefer data-driven definitions for items, perks, recipes, costs, and unlocks.
- Keep the implementation small enough to review.
- Add clear signals/APIs where systems need to talk to each other.
- Do not hardcode UI-only state as the source of truth.
- Do not break current mining, vendor, contract, claim, boat, scanner, map, or factory flows.
- If persistence is involved, make sure new state is saved and loaded.
- When finished, provide:
  1. Files changed.
  2. What was implemented.
  3. How to test it in the editor/game.
  4. Known gaps or follow-up work.

Acceptance bar:
- The game should run from `res://scenes/main.tscn` without parser errors.
- The feature should be usable by a player, not just present in code.
- UI should show enough feedback that the player understands what happened.
- The implementation should create hooks for later roadmap items instead of blocking them.

Now implement the design brief below.

---
# 05 Building Pieces And Base Utility

## Goal

Add foundations, walls, roofs, doors, storage, workbench, and factory floors. Construction should give players a reason to build a home/factory, not just place decorative parts.

## Existing Systems To Inspect

- `res://scripts/factory/build_controller.gd`
- `res://scripts/factory/factory_world.gd`
- `res://scripts/factory/building.gd`
- `res://scenes/factory/*.tscn`
- `res://scripts/factory/material_defs.gd`
- `res://scripts/miner.gd`
- `res://scripts/inventory_overlay.gd`
- Save/load from item 01

## Player Value

The player can turn an island claim into a base. A base should support automation, storage, upgrades, and future defense.

## Design

Expand build mode into categories:

- Factory Machines: loader, smelter, forge, belt, merger, splitter
- Structure: foundation, wall, roof, door, window
- Utility: storage crate, workbench, lamp, beacon

Building pieces should use materials, not just be free:

- Foundation: stone/block
- Wall: brick/block
- Roof: brick/iron bar
- Door: iron ingot/iron bar
- Storage: wood later, for now iron/stone
- Workbench: iron ingot + block
- Lamp: iron bar + gold ingot
- Beacon: gold bar + iron bar

## Gameplay Function

Foundations:
- Create valid flat build cells.
- Optional: machines must be on foundations for speed bonus.

Walls/Roofs:
- Future protection from enemies/weather.
- Current v1: enclosed structures can grant small factory speed or storage bonus.

Storage:
- Stores material counts separately from player inventory.
- Player can deposit/withdraw.
- Later machines can input/output to storage.

Workbench:
- Opens upgrade/crafting UI.
- Later used for weapons/tools.

Beacon:
- Marks a claimed island as an outpost.
- Future: slows enemy respawns.
- Current v1: map marker and teleport candidate later.

## Implementation Scope

1. Add build piece definitions with kind, scene path, footprint, cost, category.
2. Update `BuildController` to support categories and more than six tools, likely with cycling or UI selection.
3. Add simple scenes for foundation/wall/roof/door/storage/workbench/lamp/beacon.
4. Add material cost validation before placement.
5. On placement, subtract materials.
6. On removal, refund partial materials, likely 50-75%.
7. Persist placed structures.
8. Add storage crate UI for deposit/withdraw.

## Build Controller Recommendation

The current hotbar is slot-based. Avoid stuffing every piece into number keys. Add a build menu overlay:

- `B` toggles build mode.
- Number keys select current quickbar entries.
- A build catalog UI lets player choose category/item.
- Current selected item feeds existing ghost placement code.

## Acceptance Criteria

- Player can place and remove foundation/wall/roof/door pieces.
- Placement checks material costs.
- Storage crate can hold at least stone, iron ore, gold ore, and processed materials.
- Workbench/beacon can be placed even if their deeper functions are minimal.
- Existing factory placement still works.
- Structures persist if save/load exists.

## Risks

- Building collision can become frustrating on uneven voxel terrain. Foundations should auto-flatten or snap forgivingly.
- If material costs block early experimentation, make basic foundations cheap.

## Agent Prompt Add-On

Expand build mode with structural and utility pieces that cost materials. Keep existing factory placement intact. Add foundations, walls, roofs, storage, and workbench as usable game objects, with persistence and simple UI where needed.

