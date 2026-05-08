# Subagent Coding Prompt Template

Use this prompt when assigning one implementation brief to an AI coding agent.

```text
You are working on the Godot 4.6 project "Mine Co." through the available Godot MCP/project files.

Your task is to implement the attached design brief only. Do not expand scope beyond that brief unless required to make the feature work cleanly.

Important project context:
- Main scene: res://scenes/main.tscn
- Player scene: res://scenes/player.tscn
- Core scripts include:
  - res://scripts/player.gd
  - res://scripts/miner.gd
  - res://scripts/stamina.gd
  - res://scripts/vendor_ui.gd
  - res://scripts/contract_board.gd
  - res://scripts/claim_vendor_board.gd
  - res://scripts/island_voxel_generator.gd
  - res://scripts/ore_generator.gd
  - res://scripts/factory/build_controller.gd
  - res://scripts/factory/factory_world.gd
  - res://scripts/factory/material_defs.gd
- Existing autoloads include BuildController, FactoryWorld, MapData, and Admin.
- Existing gameplay already includes mining, gold currency, vendors, contracts, land claims, boats, scanner, minimap/fog, and basic factories.

Working rules:
- First inspect the relevant existing files listed in the brief.
- Preserve existing behavior unless the brief explicitly changes it.
- Prefer data-driven definitions for items, perks, recipes, costs, and unlocks.
- Keep the implementation small enough to review.
- Add clear signals/APIs where systems need to talk to each other.
- Do not hardcode UI-only state as the source of truth.
- Do not break current mining, vendor, contract, claim, or factory flows.
- If persistence is involved, make sure new state is saved and loaded.
- When finished, provide:
  1. Files changed.
  2. What was implemented.
  3. How to test it in the editor/game.
  4. Known gaps or follow-up work.

Acceptance bar:
- The game should run from res://scenes/main.tscn without parser errors.
- The feature should be usable by a player, not just present in code.
- UI should show enough feedback that the player understands what happened.
- The implementation should create hooks for later roadmap items instead of blocking them.

Now implement this brief:
[PASTE ONE DESIGN_PLAN FILE HERE]
```

