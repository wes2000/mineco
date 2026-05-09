# Multiplayer Phase 4 — Remaining Systems Implementation Plan (Structural)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to re-elaborate this structural plan into bite-sized TDD tasks **after Phase 3 ships**. The structural form below locks the task list, file list, and acceptance criteria. Phase 4 covers four loosely-coupled groups (A: per-player progression, B: building-pieces / advanced machines, C: combat, D: party/prestige); when re-elaborating, each group can be its own focused execution sub-plan.

**Goal:** Wire all remaining roadmap systems for multiplayer so a 2–4 player session can play the full game end-to-end with no host-only gates anywhere.

**Architecture:** No new netcode infrastructure required for Groups A, B, D — all reuse Phase-1 through Phase-3 patterns. Group C (combat) is the only group with genuinely new netcode: enemy AI replication, damage validation, death/respawn, loot drops, and client-side hit prediction.

**Tech Stack:** unchanged.

**Spec section:** [Phase 4 in design doc](../specs/2026-05-08-multiplayer-design.md#phase-4--remaining-systems-multiplayer)

**Prerequisites:**
- Phase 3 complete (`mp-phase-3-complete` tag pushed and 2-human playtest passed).
- Save schema is at version 4.
- For each Group, the corresponding single-player roadmap feature has landed (or is being landed alongside this phase). If a feature isn't yet in the single-player game (e.g., `06_combat_weapons_v1.md` hasn't been implemented), Phase-4 work for that group is deferred until it does.

---

## File Structure

### Created
| File | Group | Responsibility |
|---|---|---|
| `res://scripts/net/save_migration_v4_to_v5.gd` | All | Schema additions for stats, passive tree, prestige, enemies, loot drops. |
| `res://scripts/net/combat_net.gd` | C | Damage RPCs, death/respawn, loot pickup. |
| `res://scripts/net/enemy_replication.gd` | C | Enemy spawner integration with `MultiplayerSpawner`; AI host-only; transform sync via `MultiplayerSynchronizer`. |
| `res://scenes/remote_enemy.tscn` | C | If a separate "remote-only" enemy visual is needed; otherwise a Synchronizer on the existing enemy scene is enough. |
| `res://scripts/net/loot_drop.gd` | C | World-spawned loot entity with pickup RPC. |
| `res://tests/gut/test_save_migration_v4_to_v5.gd` | All | |
| `res://tests/gut/test_passive_tree_validation.gd` | A | Host re-validates client-claimed passive effects. |
| `res://tests/gut/test_combat_damage_resolution.gd` | C | Damage formula deterministic on host. |
| `res://tests/gut/test_combat_friendly_fire_toggle.gd` | C | Friendly-fire flag respected. |

### Modified (depends on which roadmap features have landed)
| File | Group | What changes |
|---|---|---|
| `res://scripts/player_stats.gd` (if exists by then) | A | Replicate per-player stats only to owner; persist in `players[steam_id].stats`. |
| `res://scripts/item_shop_ui.gd` (if exists) | A | Same vendor-style RPC pattern as Phase 2 vendors. |
| `res://scripts/passive_tree.gd` (if exists) | A | Per-player; modifiers re-validated by host on every damage/mining roll. |
| `res://scripts/contract_modifiers.gd` (if exists) | A | Per-player data attached to contract assignment record. |
| Building-pieces / utility scripts (per `05_building_pieces_and_base_utility.md`) | B | Reuse Phase-3 building RPC pipeline. Storage crates get `open_to_party` flag. |
| Factory advanced-machines scripts (per `09_factory_upgrades_advanced_machines.md`) | B | New building kinds plug into existing place/configure/sim pipeline; no new MP infrastructure. |
| `res://scripts/player.gd` | C | Health component, damage receive, death/respawn, weapon equip RPC. |
| `res://scripts/weapons/*.gd` (if exists) | C | Damage application via host-side damage formula. |
| `res://scripts/enemies/*.gd` (if exists) | C | AI runs on host only; transform replicated to peers within ~50m. |
| `res://scripts/save_game.gd` | All | Bump SAVE_VERSION to 5; chain v4→v5 migration. |
| `MULTIPLAYER.md` | All | Update active phase + finally remove the "host-only" feature list (everything works for guests). |

---

## Group A — "Just save it" (negligible netcode)

Per-player progression with no inter-player dependency. Lives in `players[steam_id]`, replicated only to its owner.

### Task list

#### Save migration v4 → v5 (TDD first)
1. Failing test for `migrate_v4_to_v5`: adds `players[steam_id].stats`, `players[steam_id].passive_tree`, `players[steam_id].prestige` defaults. Adds `world.enemies` and `world.loot_drops` defaults if those subsystems are landing.
2. Implement migration. Bump SAVE_VERSION to 5.
3. Round-trip a real Phase-3 save through migration.
4. Commit.

#### Per-player stats (`02_progression_stats_core.md`)
1. Read the stats file. Move stats container from singleton to per-steam-id keyed by `Net.local_player_id()`.
2. Stats RPCs (gain XP, level up) are owner-only — host validates the gain source and tells the owner.
3. Persist in player profile.
4. Commit.

#### Item shop (`03_item_shop.md`)
1. Reuse the Phase-2 vendor RPC pattern. The item shop is just another vendor.
2. Persist purchased items + remaining stock in world section if shop is shared, or per-player profile if shop is per-player.
3. Commit.

#### Passive tree (`04_passive_tree_v1.md`)
1. Per-player tree state in profile.
2. Allocate node: `request_allocate_node(node_id)` → host validates available points + prerequisites → grants node → tells owner.
3. Effect application: when a damage / mining / etc. roll happens server-side, host reads the actor's passive tree from profile and applies modifiers — clients never compute these locally for trust-related rolls.
4. Unit test: a client claiming a non-allocated effect cannot trigger it (host re-validates).
5. Commit.

#### Contract modifiers (`08_contract_modifiers_blueprints.md`)
1. Per-player; attached to contract assignment record.
2. Reroll/blueprint actions go through the existing contract RPC pipeline.
3. Commit.

---

## Group B — Builds on Phase 3 framework

### Building pieces (`05_building_pieces_and_base_utility.md`)
1. Walls / foundations / lamps / storage crates plug into the Phase-3 `request_place_building` flow with their own building kinds.
2. Storage crates expose the same `open_to_party` toggle pattern, plus interaction RPCs `request_chest_input` / `request_chest_output` that mirror factory hopper handlers.
3. A "base ownership zone" is just a claim, which is already shared mining / individual ownership from Phase 2.
4. Commit per kind.

### Factory advanced machines (`09_factory_upgrades_advanced_machines.md`)
1. New machine kinds register with `factory_world.gd`'s existing kind table.
2. Recipes go through the existing `request_configure_building` RPC.
3. No new MP infrastructure.
4. Commit per kind.

---

## Group C — Combat (genuinely new netcode)

This is the largest sub-group and warrants the most attention when re-elaborating into TDD tasks.

### Lobby toggles
1. Add lobby settings to `Net.host_session()`:
   - `friendly_fire: bool` (default false)
   - `hardcore_death: bool` (default false; if true, players drop their inventory on death)
2. Settings are part of the lobby data; clients read on join.
3. Commit.

### Player health + death
1. Add `health: float` to player profile + replicate to all peers (visible health bars).
2. `request_damage_player(target_steam_id, amount, source)` — host-only callable by attack handlers.
3. On `health <= 0`: broadcast `player_died(steam_id)`, ragdoll animation, respawn timer.
4. After respawn timer: spawn at owner's claim (if any) or default spawn; restore health.
5. If `hardcore_death`, drop inventory as world loot.
6. Unit test: damage formula deterministic; `friendly_fire=false` blocks player→player damage.
7. Commit.

### Enemy spawning + AI
1. Host owns `EnemySpawner`. Add `MultiplayerSpawner` for enemy entities at the world root.
2. AI ticks only on host. Each enemy has a `MultiplayerSynchronizer` for transform + animation state.
3. Proximity-LOD: enemies > 50m from a peer don't replicate transform updates to that peer (still simulate on host, but client renders them frozen at last-known position or doesn't render at all).
4. Late-join: snapshot includes all live enemies.
5. Commit.

### Damage RPCs
1. `request_attack(target_kind, target_id, weapon_id)` from client → host computes damage using attacker's passive tree + weapon stats → applies → broadcasts `damage_dealt(target_id, amount, source_peer_id)` for hit-feedback (numbers, particles, hit sound).
2. **Client-side hit prediction**: client immediately plays "hit confirmed" feedback locally on swing; host validation may roll it back if the swing would have missed (e.g., target moved). Roll-back is a "hit denied" RPC that suppresses the local feedback.
3. Unit test: damage formula returns expected number for given weapon + attacker stats.
4. Commit.

### Loot drops
1. Enemy death → spawn `loot_drop` entity via `MultiplayerSpawner` with `kind`, `qty`, `dropped_by_steam_id` (for credit attribution).
2. `request_pickup(loot_id)` → host validates proximity + first-come-first-served → moves to player inventory + despawns loot.
3. Commit.

### Revive (only if `06_combat_weapons_v1.md` includes revive)
1. `request_revive(target_steam_id)` → host validates proximity + caster has revive item / cooldown ready → revives target with partial health.
2. Commit.

### Combat playtest gate
1. Two players fight the same enemy: each sees hits register without lag-feeling, gets individual XP/loot per design.
2. Friendly fire off: player→player attacks no-op.
3. Friendly fire on: player→player attacks register.
4. Death + respawn doesn't desync world state.
5. Commit.

---

## Group D — Party / prestige (`10_company_rank_prestige.md`)

Recommendation per spec: per-player rank, each player is their own company. Treat as Group A.
1. `players[steam_id].prestige` field holds the player's rank/prestige state.
2. RPCs are owner-only (host re-validates prestige unlocks when used).
3. Persist in profile. Commit.

A future "shared company" is explicitly deferred.

---

## Roadmap-ordering watchdog

Single-player roadmap features (02–10) may land *before* their multiplayer phase ships. To prevent silent regressions:
1. Add a checklist to the project's roadmap doc template (`design_plans/00_subagent_prompt_template.md`):
   - "MP notes: which phase wires this up. Add a `Net.is_host()` guard or RPC stub if it interacts with shared state."
2. Each new single-player feature lands either with a Phase-1-style host-only guard (until its MP phase arrives) OR with proper MP wiring inline (if its MP phase has already shipped).

---

## Test approach

| Surface | Test type |
|---|---|
| Save migration v4→v5 | GUT unit |
| Stats / passive-tree per-player isolation | GUT unit |
| Damage formula determinism | GUT unit |
| Friendly-fire toggle | GUT unit |
| Enemy proximity-LOD | GUT unit |
| Combat end-to-end (responsiveness) | 2-human playtest with focus on hit-register feel |
| Death + respawn | 2-human playtest |
| Hardcore mode (drop on death) | 2-human playtest |
| All Groups end-to-end | 2-human playtest covering full game loop |

---

## Risks specific to Phase 4

- **Combat netcode user-visible quality bar.** "I hit but it didn't register" feels worse than vendor lag does. Mitigation: client-side hit prediction with host correction; ensure damage RPC reliable + low-latency.
- **Roadmap ordering**: late-bound features (passive tree, factory upgrades) might land *before* their MP phase ships. Use the watchdog above.
- **Instanced encounters**: `07_island_threat_reward.md` may introduce boss rooms. Instancing in MP is its own design call — flag for a future spec if it goes that direction. Don't ship Phase 4 with half-implemented instancing.
- **Save bloat**: per-player stats + passive tree + prestige can balloon save size with 4 players. Validate `user://savegame.json` stays under a few MB even with mature progression.

---

## Acceptance criteria (lifted from spec)

- All Phase-4 systems work end-to-end with 2+ players in a single session without single-player fallback.
- Combat: two players fighting same enemy each see hits, get individual XP/loot per the design's rules, can revive each other (if revive lands).
- Death/respawn doesn't desync the world.
- All Phase-4 additions round-trip through save/load.

---

## Phase 4 Done When

- [ ] All tasks above complete (for whichever Groups apply given roadmap state)
- [ ] All acceptance criteria pass in 2-human playtest
- [ ] All GUT tests pass
- [ ] Single-player parity verified
- [ ] Save migration v1→…→v5 verified
- [ ] `mp-phase-4-complete` tag pushed
- [ ] `MULTIPLAYER.md` updated — "host-only feature list" is removed (no remaining gates)
- [ ] No remaining "Host only — coming soon" tooltips anywhere in the game
