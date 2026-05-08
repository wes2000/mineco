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
# 02 Progression Stats Core

## Goal

Create one central stats/progression API that passive perks, shops, equipment, enemies, factories, and buildings can all read from. This prevents every feature from inventing its own upgrade math.

## Existing Systems To Inspect

- `res://scripts/player.gd`
- `res://scripts/miner.gd`
- `res://scripts/stamina.gd`
- `res://scripts/shovel.gd`
- `res://scripts/scanner_overlay.gd`
- `res://scripts/boat.gd`
- `res://scripts/factory/material_defs.gd`
- `res://scripts/factory/loader.gd`
- `res://scripts/factory/smelter.gd`
- `res://scripts/factory/forge.gd`

## Player Value

Upgrades should be immediately felt. A better pickaxe hits harder. A stamina perk lets the player sprint longer. A scanner perk finds ore from farther away. This system makes all later progression satisfying and consistent.

## Design

Add a `PlayerStats` autoload or node. It should expose final computed stats from base values plus modifiers.

Recommended base stats:

```gdscript
mining_damage_mult = 1.0
mining_swing_speed_mult = 1.0
dig_radius_mult = 1.0
stamina_max_bonus = 0
stamina_regen_mult = 1.0
sprint_speed_mult = 1.0
scanner_range_mult = 1.0
scanner_ping_speed_mult = 1.0
pickup_radius_bonus = 0.0
sell_value_mult = 1.0
contract_reward_mult = 1.0
factory_speed_mult = 1.0
boat_speed_mult = 1.0
health_max_bonus = 0
weapon_damage_mult = 1.0
build_cost_mult = 1.0
```

Use additive and multiplicative modifiers. Keep the first version simple:

```gdscript
func get_stat(stat_name: StringName) -> float
func add_modifier(source_id: StringName, stat_name: StringName, op: StringName, value: float) -> void
func remove_source(source_id: StringName) -> void
signal stats_changed
```

Examples:

- Passive tree adds permanent modifiers.
- Equipment shop adds modifiers from currently owned/equipped item.
- Temporary buffs can later add timed modifier sources.

## Implementation Scope

1. Add `res://scripts/player_stats.gd` as an autoload.
2. Create clear stat constants to avoid typo-heavy string calls.
3. Wire current systems to read stats:
   - `Shovel` or `Miner` uses mining damage multiplier.
   - `Stamina` uses max and regen modifiers.
   - `Player` uses sprint speed modifier.
   - `ScannerOverlay` uses range and ping interval modifiers.
   - `VendorUI` or economy path uses sell multiplier.
   - `ContractBoard.turn_in()` uses contract reward multiplier.
   - Factory machines use factory speed multiplier.
   - `Boat` uses boat speed multiplier.
4. Add save/load methods for permanent modifier sources if item 01 exists.

## Recommended Pattern

Avoid scattering math like this:

```gdscript
damage = base_damage * 1.2 * 1.15
```

Instead:

```gdscript
damage = base_damage * PlayerStats.get_stat(PlayerStats.MINING_DAMAGE_MULT)
```

For stats that are bonuses:

```gdscript
max_stamina = base_max + int(PlayerStats.get_stat(PlayerStats.STAMINA_MAX_BONUS))
```

## UI/UX

No major UI is required for this step, but add a debug method or admin print that can show final stats. Later UIs will use it.

## Acceptance Criteria

- Existing game still feels the same with default stats.
- Changing a stat in `PlayerStats` visibly affects the corresponding system.
- Passive tree/shop systems can later register modifiers without editing miner/player/factory logic again.
- Stats are not stored only in UI nodes.

## Risks

- Retrofitting too many systems at once can cause bugs. Prioritize mining damage, stamina, scanner range, sell value, and factory speed first.
- Be careful with factory tick timing. Multipliers should not create zero or negative cycle durations.

## Agent Prompt Add-On

Implement a central `PlayerStats` progression API and wire the highest-value existing systems to it while preserving default gameplay. Keep the stat API data-driven and future-friendly. Do not build the passive tree yet; only create the shared stat foundation.

