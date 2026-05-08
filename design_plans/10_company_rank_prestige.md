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
# 10 Company Rank And Prestige

## Goal

Add a long-term meta progression layer after the core loop is fun. This should give committed players a reason to keep playing once they own strong gear, claims, factories, and passive perks.

## Existing Systems To Inspect

- Save/load from item 01
- `res://scripts/miner.gd`
- Passive tree from item 04
- Item shop from item 03
- Contract modifiers/unlocks from item 08
- Factory upgrades from item 09
- Claim system from item 07

## Player Value

The player is not just mining randomly; they are growing Mine Co. as a company. Rank gives prestige, goals, and new starts with meaningful bonuses.

## Design

Add Company Rank as milestone progression first. Add full prestige/reset only after balancing.

Company Rank XP sources:

- Gold earned
- Contracts completed
- Claims cleared/released
- Enemy camps cleared
- Factory goods produced
- Blueprints found

Ranks:

1. Prospector
2. Claim Holder
3. Foreman
4. Island Operator
5. Industrialist
6. Mine Co. Director

Rank rewards:

- New shop stock
- Passive tree branch unlocks
- Factory machine unlocks
- Higher contract levels
- Cosmetic title
- Small permanent stat bonus

## Prestige Design

Only add reset once the game has enough content. A prestige should be optional and meaningful:

The player can "Incorporate a New Branch" and reset:

- Gold
- Inventory
- claims
- local factories
- maybe shop equipment

Keep:

- Company rank prestige level
- permanent prestige tokens
- discovered blueprints maybe
- cosmetics/titles

Prestige tokens buy company policies:

- +5% all sell value
- +5% mining damage
- +5% factory speed
- start with scanner
- start with boat discount
- +1 contract slot
- reveal nearest claim island

## Implementation Scope

1. Add `CompanyProgress` autoload.
2. Track lifetime stats:
   - lifetime_gold_earned
   - contracts_completed
   - claims_cleared
   - enemies_defeated
   - factory_items_produced
3. Add rank thresholds and rewards.
4. Emit progress events from existing systems.
5. Add company panel UI.
6. Gate content using rank where appropriate.
7. Save company progress.
8. Add prestige only as a disabled/hidden design hook unless enough content exists.

## UI/UX

Company panel should show:

- Current rank
- XP/progress to next rank
- Lifetime stats
- Next unlocks
- Prestige section locked until max rank

## Acceptance Criteria

- Company rank increases from normal play.
- Rank rewards unlock content or apply stats.
- Progress persists.
- Existing systems emit progress without tight coupling.
- Prestige is not forced or disruptive.

## Risks

- Reset prestige too early can make the game feel punishing.
- Lifetime counters must not double count after loading.
- Rank rewards should not replace moment-to-moment upgrades; they should complement them.

## Agent Prompt Add-On

Implement company rank as a long-term meta progression layer. Track lifetime stats from normal play, award ranks, unlock content, and persist progress. Do not implement a full reset prestige unless the brief explicitly asks for it; add only safe hooks.

