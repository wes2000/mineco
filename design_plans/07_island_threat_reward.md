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
# 07 Island Threat And Reward System

## Goal

Make offshore claim islands exciting, dangerous, and replayable. Higher-tier islands should offer better ore and rewards but require better gear, perks, and preparation.

## Existing Systems To Inspect

- `res://scripts/island_voxel_generator.gd`
- `res://scripts/ore_generator.gd`
- `res://scripts/claim_def.gd`
- `res://scripts/claim_vendor_board.gd`
- `res://scripts/claim_vendor_ui.gd`
- `res://scripts/boat.gd`
- Combat system from item 06
- Save/load from item 01

## Player Value

Claim islands become mini-adventures: sail there, scout, fight enemies, mine valuable ore, maybe build an outpost, then return for rewards.

## Design

Extend island definitions with threat and reward metadata:

```gdscript
{
  "id": "ironback",
  "name": "Ironback",
  "tier": 3,
  "threat": 3,
  "enemy_budget": 8,
  "reward_tags": ["iron_rich", "blueprint_chance"]
}
```

Enemy tiers:

- Tier 1: 2-3 weak melee enemies
- Tier 2: more melee, one guard
- Tier 3: mixed melee/ranged
- Tier 4: elite enemies, camp
- Tier 5: boss/mini-boss plus guards

Rewards:

- More ore deposits
- Gold bounty for clearing enemies
- Blueprint chance
- Rare chest
- Passive tree refund/shard later
- Outpost bonuses

## Island State

Track per-island:

- enemies_spawned
- enemies_killed
- cleared
- chest_claimed
- last_respawn_time or respawn counter
- beacon_built if construction exists

For v1, state can reset on new claim unless save/load supports island state.

## Implementation Scope

1. Add island encounter definitions.
2. Add enemy spawn points generated from island center/radius.
3. Spawn enemies when island terrain is ready or when player gets nearby.
4. Enemies should not spawn on unowned locked islands unless the player can visit/fight before buying. Decide rule:
   - Recommended: enemies spawn on all claim islands, but mining remains locked until owned.
5. Add clear reward when all enemies on an island are defeated.
6. Add UI feedback: "Ironback cleared +500g" or pickup feed message.
7. Save cleared/chest state if save/load exists.
8. If beacon exists, cleared islands with beacon should stay safe longer.

## Enemy Placement

Use deterministic random seeded by island id. Sample points inside island ellipse and use the island height function to place enemies above terrain.

Avoid spawning enemies:

- Underwater
- Too close to dock/ocean edge
- Inside ore deposits
- In impossible steep terrain if detectable

## Acceptance Criteria

- Claim islands spawn enemies by tier.
- Player can clear enemies and receive a reward.
- Higher-tier islands feel more dangerous.
- Mining lock still respects claim ownership.
- Enemy state does not break when leaving/returning by boat.

## Risks

- Enemy navigation on voxel islands may be tricky. Start with simple steering/chase rather than full navmesh if needed.
- Spawning too many enemies can hurt FPS. Use small encounter budgets.

## Agent Prompt Add-On

Implement island threat/reward encounters using existing claim island metadata. Spawn tiered enemies on offshore islands, reward clearing them, and preserve claim mining rules. Keep enemy AI simple and reliable on voxel terrain.

