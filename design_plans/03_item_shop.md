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
# 03 Item Shop

## Goal

Add a gold shop where players buy meaningful gear upgrades: pickaxes, scanners, weapons later, and utility items. This creates an early and mid-game gold sink before the passive tree becomes large.

## Existing Systems To Inspect

- `res://scripts/vendor_ui.gd`
- `res://scripts/boat_vendor_ui.gd`
- `res://scripts/town_spawner.gd`
- `res://scripts/npc.gd`
- `res://scripts/miner.gd`
- `res://scripts/player.gd`
- `res://scripts/shovel.gd`
- `res://scripts/scanner_overlay.gd`
- `res://scripts/bottom_hud.gd`
- `res://scripts/player_stats.gd` if item 02 exists

## Player Value

After selling ore or completing contracts, players need exciting purchases. The shop should make gold feel valuable every run.

## Design

Add a new shop NPC or extend an existing vendor with tabs. A separate item shop NPC is cleaner.

Create a data catalog, likely `res://scripts/shop_item_defs.gd`, with definitions like:

```gdscript
{
  "id": "pickaxe_copper",
  "name": "Copper Pickaxe",
  "category": "pickaxe",
  "price": 250,
  "requires": [],
  "modifiers": [
    {"stat": PlayerStats.MINING_DAMAGE_MULT, "op": "mul", "value": 1.15}
  ],
  "description": "Hits ore harder."
}
```

Suggested v1 items:

Pickaxes:
- Copper Pickaxe: 250g, +15% mining damage
- Iron Pickaxe: 900g, +35% mining damage
- Gold-Tipped Pickaxe: 2500g, +60% mining damage, +10% swing stamina efficiency
- Deepcore Pickaxe: 8000g, +100% mining damage, +15% dig radius

Scanners:
- Tuned Scanner: 500g, +25% range
- Fast Sweep Scanner: 1200g, +35% ping speed
- Material Lock Scanner: 3500g, faster target cycling / future rare detection

Utility:
- Work Boots: 700g, +8% sprint movement
- Survey Pack: 1000g, +2m pickup radius
- Boat Rudder Kit: 1500g, +20% boat speed

Weapons can be listed but disabled until combat is implemented.

## Implementation Scope

1. Add shop item definitions.
2. Add player-owned purchase state to `Miner` or a new `PlayerProgress` autoload.
3. Add `res://scripts/item_shop_ui.gd` and `res://scenes/item_shop_ui.tscn`.
4. Add an item shop NPC in `TownSpawner`.
5. On purchase, subtract `gold_currency`, mark item owned, and register stat modifiers.
6. For mutually exclusive equipment like pickaxes/scanners, support equip buttons.
7. Save owned/equipped items if save/load exists.

## UI/UX

Shop should show:

- Item name
- Category
- Price
- Owned/equipped state
- Requirement text if locked
- Buy/equip button
- Current gold

Avoid huge descriptions. The stat effect should be readable at a glance.

## Progression Rules

Use prerequisite chains to avoid overwhelming the player:

- Iron Pickaxe requires Copper Pickaxe.
- Gold-Tipped Pickaxe requires Iron Pickaxe.
- Deepcore Pickaxe requires Gold-Tipped Pickaxe and maybe claim vendor level 3.

## Acceptance Criteria

- Player can open item shop with `E` near the shop NPC.
- Buying an item subtracts gold and immediately affects gameplay.
- Owned/equipped state persists if save/load is implemented.
- Buttons disable correctly when unaffordable, owned, or locked.
- Shop does not interfere with sell vendor, boat vendor, contracts, or claims.

## Risks

- Multiple vendors use similar modal patterns. Reuse patterns but avoid copy-paste bugs in group names.
- If item effects write directly to player fields, later passive perks will conflict. Use `PlayerStats` if available.

## Agent Prompt Add-On

Implement the item shop as a data-driven gold sink with owned/equipped state. Start with pickaxe, scanner, and utility items that affect existing gameplay through `PlayerStats` or equivalent. Add a shop NPC and UI, persist purchases if save/load exists, and verify buying an upgrade changes actual play.

