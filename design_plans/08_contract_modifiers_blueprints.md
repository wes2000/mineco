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
# 08 Contract Modifiers And Blueprint Rewards

## Goal

Make contracts more varied and make them feed long-term unlocks. Contracts should be more than "turn in items for gold"; they should push different playstyles and reward progression.

## Existing Systems To Inspect

- `res://scripts/contract_board.gd`
- `res://scripts/contract_ui.gd`
- `res://scripts/contracts_overlay.gd`
- `res://scripts/miner.gd`
- `res://scripts/factory/material_defs.gd`
- Item shop/passive tree if implemented
- Save/load from item 01

## Player Value

The player gets rotating goals that change what they mine, build, or process. Blueprints create exciting unlock moments.

## Design

Add contract modifiers:

- Rush Order: higher reward, expires after time
- Bulk Order: large quantity, high XP
- Refined Goods: requires T2/T3 items, better reward
- Local Buyer: bonus for specific material
- Dangerous Delivery: requires island material or enemy clear
- Factory Quota: reward bonus if delivered processed goods

Contract shape extension:

```gdscript
{
  "items": [[material_id, count]],
  "reward_gold": int,
  "xp": int,
  "modifier": "rush_order",
  "expires_at": float,
  "blueprint_chance": 0.10,
  "required_flags": []
}
```

Blueprints:

- Unlock advanced build pieces
- Unlock machines
- Unlock weapon tiers
- Unlock shop items
- Unlock passive tree branch nodes

Keep blueprint state in a central unlock registry:

```gdscript
Unlocks.has("machine_crusher")
Unlocks.unlock("machine_crusher")
```

## Implementation Scope

1. Add `Unlocks` autoload or equivalent.
2. Add blueprint definitions.
3. Extend `ContractBoard._generate()` to sometimes assign modifiers.
4. Modify reward calculation based on modifier.
5. Add optional expiration for rush contracts.
6. Add turn-in reward roll for blueprints.
7. Update contract UI to show modifier, bonus, and blueprint chance/reward.
8. Persist active contract modifiers and unlocked blueprints.

## Suggested Blueprint Rewards

Early:

- Storage Crate
- Workbench
- Tuned Scanner
- Iron Pickaxe

Mid:

- Fast Smelter
- Advanced Belt
- Reinforced Wall
- Crossbow/Pistol

Late:

- Crusher machine
- Auto-seller
- Beacon
- Deepcore Pickaxe

## Acceptance Criteria

- Contracts can generate with visible modifiers.
- Modified contracts pay correctly.
- Expiring contracts are handled cleanly.
- Blueprint unlocks can be awarded and persisted.
- Locked shop/build/passive content can check `Unlocks`.

## Risks

- Too many contract variants can confuse players. Start with 3 modifier types.
- Expiration timers should not punish players too hard. Make rush orders optional and rewarding.

## Agent Prompt Add-On

Extend contracts with modifiers and blueprint rewards. Add a central unlock registry, update generation/reward/UI, and persist unlocked blueprints. Start with a small set of high-impact modifiers.

