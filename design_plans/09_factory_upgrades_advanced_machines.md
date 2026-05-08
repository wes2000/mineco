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
# 09 Factory Upgrades And Advanced Machines

## Goal

Make automation deeper and more rewarding. Factories should become a major replay hook where players optimize ore processing, unlock stronger machines, and produce high-value goods.

## Existing Systems To Inspect

- `res://scripts/factory/factory_world.gd`
- `res://scripts/factory/build_controller.gd`
- `res://scripts/factory/building.gd`
- `res://scripts/factory/loader.gd`
- `res://scripts/factory/smelter.gd`
- `res://scripts/factory/forge.gd`
- `res://scripts/factory/belt_link.gd`
- `res://scripts/factory/material_defs.gd`
- `res://scripts/factory/machine_ui.gd`
- `res://scenes/factory/*.tscn`
- Unlocks from item 08

## Player Value

Players who like optimization get a long-term reason to build, rearrange, unlock, and improve. Better factories turn mining effort into more value.

## Design

Add two progression layers:

1. Machine upgrades for existing buildings.
2. New advanced machines.

Existing machine upgrades:

- Loader Mk2: faster output, larger hopper
- Smelter Mk2: faster cycles, larger buffer
- Forge Mk2: faster cycles, less overflow risk
- Belt Mk2: faster item movement
- Splitter/Merger priority settings

Advanced machines:

- Crusher: stone -> gravel/dust or ore -> bonus yield
- Washer: ore -> chance of extra nuggets
- Auto-Seller: sells finished goods at reduced or upgraded rate
- Storage Silo: large material buffer
- Power Generator: boosts nearby machines

## Data Model

Machine upgrade state should live on each building:

```gdscript
var upgrade_level: int = 0
```

Machine definitions can include:

```gdscript
"upgrade_costs": [
  {"gold": 500, "materials": {MaterialDefs.MaterialId.IRON_INGOT: 5}},
  {"gold": 2000, "materials": {MaterialDefs.MaterialId.GOLD_INGOT: 3}}
]
```

## Implementation Scope

1. Add upgrade data to building/machine definitions.
2. Extend `MachineUI` with upgrade panel.
3. Apply upgrade levels to cycle times, capacity, speed, or output.
4. Save machine upgrade levels.
5. Add at least one advanced machine scene and script, preferably Crusher or Storage Silo.
6. Gate advanced machines behind `Unlocks`.
7. Add build catalog support if item 05 exists.

## First Advanced Machine Recommendation

Add Storage Silo first if storage is not already robust. It supports future machines and reduces frustration.

Add Crusher second:

- Input: stone/iron ore/gold ore
- Output: same material plus small chance of bonus unit, or new crushed material if you want more recipe depth.
- Keep v1 simple: crusher increases yield rather than adding too many new materials.

## Acceptance Criteria

- Existing machines can be upgraded through UI.
- Upgrade costs are paid from gold/materials.
- Upgrades visibly affect machine behavior.
- At least one advanced machine can be unlocked, placed, and used.
- Factory save/load preserves upgrade levels.

## Risks

- More materials can create inventory/UI bloat. Prefer yield/efficiency upgrades before adding many new item types.
- Auto-seller can bypass vendor/contracts. Balance it with lower sell rate or require upgrades.

## Agent Prompt Add-On

Implement factory upgrades and one advanced machine. Extend `MachineUI`, persist upgrade levels, use data-driven costs, and ensure upgrades clearly change factory throughput without breaking existing belts and machines.

