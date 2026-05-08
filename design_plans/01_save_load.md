# Agent Coding Prompt

You are working on the Godot 4.6 project "Mine Co." through the available Godot MCP/project files.

Your task is to implement this design brief only. Do not expand scope beyond this brief unless required to make the feature work cleanly.

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
# 01 Save And Load

## Goal

Add reliable persistent progression before the game grows more systems. Mine Co. already has gold, inventory, vendors, contracts, land claims, boat ownership, map exploration, and factories. The player needs to trust that every session matters.

## Existing Systems To Inspect

- `res://scripts/miner.gd`
- `res://scripts/player.gd`
- `res://scripts/contract_board.gd`
- `res://scripts/claim_vendor_board.gd`
- `res://scripts/map_data.gd`
- `res://scripts/factory/factory_world.gd`
- `res://scripts/factory/build_controller.gd`
- `res://scripts/factory/building.gd`
- `res://scripts/factory/loader.gd`
- `res://scripts/factory/smelter.gd`
- `res://scripts/factory/forge.gd`
- `res://scenes/main.tscn`

## Player Value

The player can quit after buying a boat, clearing ore, building a small factory, or earning gold, then return later with the same progress. This is foundational for replay value and for every future progression system.

## Design

Create a save autoload, likely `SaveGame`, responsible for serializing and restoring the game state. Use JSON or Godot `ConfigFile`; JSON is easier to inspect and debug. Save to `user://savegame.json`.

Save data should include a `version` integer so future migrations are possible.

Recommended save shape:

```gdscript
{
  "version": 1,
  "player": {
    "position": [x, y, z],
    "rotation_y": value,
    "current_tool": int
  },
  "miner": {
    "materials": {
      "stone": int,
      "brick": int,
      "block": int,
      "iron": int,
      "iron_ingot": int,
      "iron_bar": int,
      "gold": int,
      "gold_ingot": int,
      "gold_bar": int
    },
    "gold_currency": int,
    "has_boat": bool
  },
  "contracts": {
    "level": int,
    "xp": int,
    "available": Array,
    "active": Array
  },
  "claims": {
    "level": int,
    "xp": int,
    "owned_id": String,
    "owned_mined": Dictionary
  },
  "map": {
    "explored": PackedByteArray or compact string,
    "explored_cell_count": int
  },
  "factory": {
    "buildings": Array,
    "links": Array
  }
}
```

## Implementation Scope

1. Add `res://scripts/save_game.gd` as an autoload.
2. Add `save_now()`, `load_now()`, `has_save()`, `delete_save()`, `collect_state()`, and `apply_state()`.
3. Add lightweight `get_save_data()` and `apply_save_data(data)` methods to systems that own state.
4. Save on pause menu button if one exists, and also autosave on quit / periodic interval.
5. Load after the main scene is ready, not before nodes exist. Use deferred apply or wait for `SpawnGate.world_ready` if necessary for player/factory placement.
6. Persist enough factory state to rebuild placed buildings and links. Include kind, origin cell, rotation, machine recipe, hopper contents, queues, and links between building ids/port indices.

## Factory Persistence Recommendation

Add stable runtime ids to placed buildings:

```gdscript
var save_id: String = ""
```

When placing a building, assign a unique id. When loading, instantiate all buildings first, then restore belt links by resolving source/destination building id and port index.

For v1, it is acceptable to skip in-flight belt items and only persist buildings, hoppers, recipes, and queued materials. Avoid trying to preserve exact moving item positions in the first implementation.

## UI/UX

Add simple feedback:

- "Game saved" toast in the pickup feed or a small HUD message.
- Main menu is not required yet.
- Pause menu should expose Save and maybe "Save and Quit" if the scene already has buttons.

## Acceptance Criteria

- Starting a fresh game creates no errors.
- Player inventory, gold currency, boat ownership, contract state, claim state, and placed factory buildings survive restart.
- Loading does not duplicate vendors, ore generators, or factory buildings.
- If save data is missing or old, the game starts cleanly.
- Save file version is present.

## Risks

- Applying factory save too early can fail if `current_scene` is not ready.
- Generated ore deposits are not currently tracked as depleted. If depleted ore should persist, add a later ore-state save. For v1, prioritize player economy and buildings.
- Map exploration uses an image/byte array; this may need compact encoding.

## Agent Prompt Add-On

Implement save/load as the first durable progression layer. Keep the save format versioned and practical. Focus on player economy, vendor progression, land claim state, map exploration if feasible, and factory placements. Add small save feedback, run the main scene, and report any state you intentionally did not persist.

