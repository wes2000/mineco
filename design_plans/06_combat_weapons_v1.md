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
# 06 Combat And Weapons V1

## Goal

Add the foundation for enemies, player health, weapons, damage, death/respawn, and combat feedback. This should be small but solid enough for island enemies in the next step.

## Existing Systems To Inspect

- `res://scripts/player.gd`
- `res://scripts/miner.gd`
- `res://scripts/shovel.gd`
- `res://scripts/bottom_hud.gd`
- `res://scripts/item_shop_ui.gd` if item 03 exists
- `res://scripts/player_stats.gd`
- `res://scripts/town_spawner.gd`

## Player Value

Combat adds danger and tension to exploration. The player should feel that better weapons and health upgrades let them attempt harder islands.

## Design

Add:

- Player health component
- Damageable interface/pattern
- Weapon definitions
- Basic melee weapon
- Basic ranged weapon optional
- Enemy health/damage API
- Respawn behavior

Weapon definition example:

```gdscript
{
  "id": "rusty_blade",
  "name": "Rusty Blade",
  "type": "melee",
  "damage": 12,
  "range": 2.3,
  "cooldown": 0.55,
  "knockback": 3.0
}
```

Starter weapons:

- Rusty Blade: cheap, short range
- Prospector Hammer: slower, higher damage
- Flint Pistol or Scrap Crossbow: ranged prototype, ammo-free cooldown-based for v1

## Implementation Scope

1. Add `health.gd` component or player health fields.
2. Add HUD health display.
3. Add `weapon_defs.gd`.
4. Add weapon controller under player/camera, similar to shovel/scanner.
5. Add hotbar slot for weapon if owned/equipped.
6. Add a simple `Damageable` convention:
   - `take_damage(amount, source_position, tags := {})`
   - `died` signal
7. Add one test dummy or simple enemy scene to verify damage.
8. Add shop integration for buying/equipping weapons if item shop exists.
9. Save equipped weapon.

## Controls

Options:

- Slot 4 as weapon in standard mode.
- LMB attacks when weapon equipped.
- If build mode uses slots, standard/build mode already switches hotbar sets.

## Combat Feel

Minimum feedback:

- Hit particles or flash
- Hit sound
- Enemy health reaction
- Floating damage number optional
- Player damage vignette or sound

## Death/Respawn

For v1:

- On death, fade/reposition to town spawn.
- Lose no items at first, or drop a small percentage of gold later.
- Restore health.

Do not create punishing loss yet. Early combat should invite learning.

## Acceptance Criteria

- Player has health and can take damage.
- Player can equip and use a weapon.
- Weapon can damage a test enemy/dummy.
- Health UI updates.
- Death respawns player cleanly.
- Combat stats read from `PlayerStats`.

## Risks

- Input conflicts with mining/building. Weapon attack should only fire when weapon equipped and build mode inactive.
- Adding too many weapon types now can delay island enemy gameplay. Keep v1 narrow.

## Agent Prompt Add-On

Implement the combat foundation: player health, weapon definitions, weapon equip/use, damageable enemies/dummies, health UI, and respawn. Keep it compatible with existing hotbar/build mode and `PlayerStats`.

