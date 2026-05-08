# Agent Coding Prompt

You are working on the Godot 4.6 project "Mine Co." through the available Godot MCP/project files.

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
# 04 Passive Tree V1

## Goal

Add a passive tree that spends gold for permanent perks. The tree should deepen progression, create long-term goals, and make each gold milestone exciting.

## Existing Systems To Inspect

- `res://scripts/miner.gd`
- `res://scripts/player_stats.gd`
- `res://scripts/bottom_hud.gd`
- `res://scripts/pause_menu.gd`
- `res://scripts/vendor_ui.gd`
- `res://scripts/contract_board.gd`
- `res://scripts/factory/material_defs.gd`
- Save/load from item 01

## Player Value

The player always has a reason to earn more gold, even after buying tools. The tree should provide "one more run" motivation: one more contract, one more island, one more upgrade.

## Design

Create six branches:

1. Mining
2. Exploration
3. Automation
4. Combat
5. Economy
6. Construction

Use a data-driven perk catalog:

```gdscript
{
  "id": "mining_damage_1",
  "name": "Sharper Edge",
  "branch": "mining",
  "cost": 250,
  "requires": [],
  "max_rank": 3,
  "modifiers_per_rank": [
    {"stat": PlayerStats.MINING_DAMAGE_MULT, "op": "mul", "value": 1.10}
  ]
}
```

Costs should climb fast enough to preserve goals:

- Tier 1: 150-500g
- Tier 2: 800-2000g
- Tier 3: 3500-8000g
- Tier 4: 12000-25000g

## Suggested V1 Perks

Mining:
- Sharper Edge: +10% mining damage per rank, 3 ranks
- Wider Bite: +10% dig radius per rank, 2 ranks
- Efficient Swing: -10% stamina cost per rank, 2 ranks
- Ore Sense: +5% ore chunk yield chance later, v1 can add +1 ore every N chunks

Exploration:
- Longer Sweep: +20% scanner range per rank, 3 ranks
- Fast Radar: +15% scanner sweep speed per rank, 2 ranks
- Trailblazer: +15% map reveal radius
- Boat Handling: +15% boat speed per rank, 2 ranks

Automation:
- Warm Machines: +10% factory speed per rank, 3 ranks
- Deep Hoppers: +100 loader hopper capacity per rank
- Belt Tuning: +15% belt item speed per rank
- Smooth Output: +1 machine output queue capacity later

Combat:
- Tough Skin: +10 max health per rank
- Heavy Hit: +15% weapon damage per rank
- Guarded Miner: +10% damage reduction later
- Bounty Sense: enemies drop more gold later

Economy:
- Better Deals: +5% sell value per rank, 3 ranks
- Contract Negotiator: +10% contract reward per rank
- Extra Active Contract: unlock active contract slot +1
- Claim Discount: -10% claim purchase price

Construction:
- Cheaper Builds: -5% build cost per rank
- Builder Reach: +5m build ray range
- Outpost Planner: unlock storage/workbench building category
- Reinforced Structures: structures resist raids/weather later

## Implementation Scope

1. Add perk definitions file.
2. Add `PassiveTree` autoload or node to track ranks purchased.
3. Connect purchased perks to `PlayerStats`.
4. Create `passive_tree_ui.tscn` and `passive_tree_ui.gd`.
5. Add keybind or pause menu button to open the tree.
6. Spend `Miner.gold_currency` on purchase.
7. Persist purchased ranks.

## UI/UX

For v1, do not overbuild a giant visual graph. A tabbed branch view is enough:

- Branch tabs
- Perk rows/cards with icon placeholder, rank, cost, effect, buy button
- Gold display
- Locked requirements shown clearly

Later this can become a spatial node tree.

## Acceptance Criteria

- Player can open the passive tree.
- Buying perks costs gold and increases rank.
- Perk effects immediately alter gameplay through `PlayerStats`.
- Locked perks stay locked until requirements are met.
- Perk ranks persist if save/load exists.

## Risks

- Too many tiny perks can feel like spreadsheet work. Prioritize noticeable effects.
- If costs are too cheap, the tree gets consumed instantly. Start slightly expensive and tune down.

## Agent Prompt Add-On

Implement Passive Tree V1 as a data-driven gold upgrade system with six branches and clear rank/cost/effect UI. Use `PlayerStats` for effects and save purchased ranks. Keep the UI simple but fully usable.

