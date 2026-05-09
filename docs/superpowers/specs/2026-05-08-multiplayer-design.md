# Multiplayer Design — Mine Co.

**Date:** 2026-05-08
**Status:** Design (pre-implementation)
**Scope:** Add 2–4 player co-op to the Godot 4.6 project "Mine Co." across four sequential, independently-shippable phases.

## Goals & Non-Goals

### Goals
- Let 2–4 friends play Mine Co. together in a shared world.
- Each player keeps their own progression (inventory, gold, contract/claim XP, factory).
- Connect via Steam friends invites with native NAT traversal.
- Ship in four phases so each release can be tested before the next is built.
- Single-player remains fully playable and on parity at every release.

### Non-Goals (deferred indefinitely)
- Cross-world character travel ("Valheim profiles" model).
- Dedicated server hosting; persistent always-online worlds.
- Marketplaces, leaderboards, social systems beyond Steam friends.
- PvP combat (friendly-fire toggle is as far as we go).
- Mod/Workshop integration.
- Anti-cheat beyond basic sanity validation (this is friends-only co-op).

## Core decisions

| Decision | Choice |
|---|---|
| Multiplayer scope | Small co-op, 2–4 players |
| Sharing model | Shared world, individual progress (Valheim-style) |
| Claims & factories | Shared mining (anyone can mine anywhere); individual factories |
| Connection | Steam friends invites via GodotSteam (`SteamMultiplayerPeer`) |
| Save model | Bundled save: world + all player profiles in one file; character lives in the world it was created in |
| Authority | Listen-server, host-authoritative for all world state |
| Networking pattern | Approach C (Hybrid): `MultiplayerSpawner` + `MultiplayerSynchronizer` for entities/transforms; explicit `@rpc` for game-state events |

## Architecture overview

```
                 ┌──────────────────────────┐
                 │    HOST (player + sim)   │
                 │   FactoryWorld (auth)    │
                 │   IslandVoxelGenerator   │
                 │   ContractBoard / Claims │
                 │   Vendors / EnemySpawner │
                 │   SaveGame (bundled)     │
                 │   Net autoload           │
                 └────────────┬─────────────┘
                              │  SteamMultiplayerPeer
            ┌─────────────────┼──────────────────┐
            │                 │                  │
       ┌────┴─────┐      ┌────┴─────┐       ┌────┴─────┐
       │ Client A │      │ Client B │       │ Client C │
       │ (visual+ │      │ (visual+ │       │ (visual+ │
       │  input)  │      │  input)  │       │  input)  │
       └──────────┘      └──────────┘       └──────────┘
```

- Host runs **all** simulation: voxel/ore state, factory ticks, contract/claim/vendor logic, enemy AI.
- Clients render, accept input, and run **only** local-only systems (stamina, fog reveal, UI).
- All state-changing actions follow the **request → host validate → broadcast** pattern.

## Foundation (built once, used by all phases)

### Transport & lobby
- Add **GodotSteam** plugin (the SCons-built fork that exposes Steamworks). Use `SteamMultiplayerPeer` as the `MultiplayerAPI` peer. Steam app ID 480 (Spacewar) for development; replace with the project's real ID at launch.
- New autoload `Net` at `res://scripts/net/net.gd`. Owns:
  - The peer.
  - `host_session()`, `join_session(lobby_id)`, `leave_session()`.
  - `is_host()`, `local_player_id()`, peer-id ↔ Steam-id mapping.
  - Signals: `peer_connected(peer_id, steam_id)`, `peer_disconnected(peer_id)`, `session_ended(reason)`.
- New scene `res://scenes/ui/multiplayer_menu.tscn`. Buttons for Host / Join via Steam invite / Leave; live player roster.

### Authority model
- Host authoritative for: ore depletion, claims, contracts, vendor stock, factory simulation, enemies, day/night.
- Client authoritative for: local input intent (move direction, look angle, action button presses), local-only UI/camera state, local stamina.
- Every state-changing client action goes through `@rpc("any_peer", "call_local")` request → host validates → host applies → host broadcasts the resulting state delta with `@rpc("authority", "call_local", "reliable")`.

### Net abstraction layer
A thin module `res://scripts/net/net_utils.gd` wraps the patterns we'll reuse so gameplay code never touches `multiplayer.*` directly:
- `request_to_host(method_name: String, args: Array)` — client → host RPC wrapper.
- `broadcast(method_name: String, args: Array)` — host → all clients.
- `tell_peer(peer_id: int, method_name: String, args: Array)` — host → one peer.
- `is_host()`, `local_player_id()`.

### Player spawning
- `MultiplayerSpawner` on the world root spawns one of two scenes per peer:
  - Local peer: existing `Player` scene (camera, input, full HUD).
  - Remote peers: new `RemotePlayer` scene (mesh, animation tree, name tag, no camera, no input).
- `MultiplayerSynchronizer` on each player node syncs `position`, `rotation_y`, animation state, current_tool. ~20 Hz, unreliable for transform, reliable for tool changes.

### Save shape (bundled save)
Extends the schema from `design_plans/01_save_load.md`:
```gdscript
{
  "version": 2,
  "world": {
    "map": { "explored": ..., "explored_cell_count": int },
    "claims": {  # claim_id -> claim record
      "<claim_id>": {
        "level": int, "xp": int,
        "owner_steam_id": String,             # Phase 2+
        "mined_per_player": Dictionary,       # Phase 2+
      }
    },
    "contracts": {
      "available": Array,
      "assignments": Dictionary,              # contract_id -> steam_id (Phase 2+)
    },
    "vendors": { ... },                       # shared stock
    "boats": [ { owner_steam_id, position, rotation }, ... ],  # Phase 2+
    "factory": {
      "buildings": [ { ..., save_id, owner_steam_id, open_to_party } ],  # Phase 3+
      "links": [ ... ]
    },
    "enemies": { ... },                       # Phase 4
  },
  "players": {
    "<steam_id>": {
      "position": [x, y, z], "rotation_y": float,
      "current_tool": int,
      "materials": Dictionary,
      "gold_currency": int,
      "has_boat": bool,
      "contract_level": int, "contract_xp": int,
      "claim_level": int, "claim_xp": int,
      "passive_tree": ...,                    # Phase 4 if 04 lands
      "stats": ...,                           # Phase 4 if 02 lands
    }
  }
}
```
- Save is owned and written by **host only**. Clients never write the world save.
- Single-player save migrates: existing top-level state becomes `world` + a single entry in `players` keyed by the local Steam ID (or `"local"` if Steam isn't running).
- On graceful disconnect, host snapshots that client's player profile so they keep progress next session.

### Late-join state catch-up
When a peer joins mid-session, host calls `send_world_snapshot(peer_id)` which pushes:
- Map exploration mask.
- Claims ownership table.
- Contracts state.
- Vendor stock.
- All factory placements (Phase 3+).
- All enemies/loot drops (Phase 4).
- That peer's saved player profile if they've played here before; otherwise a fresh profile.

Client applies the snapshot before being released into the world (loading screen).

### Out-of-scope for foundation
- Anti-cheat / packet validation beyond basic sanity checks.
- Persistent character travel between worlds.
- Dedicated server.
- Voice chat (Steam handles externally).

## Phase 1 — Minimum viable co-op

**Goal:** Two friends in the same world; see each other move; mine the same ore; chat.

### What ships
- Entire foundation (Net, GodotSteam, lobby UI, save migration, player spawner, late-join snapshot for the systems Phase 1 touches).
- Replicated player movement & animation (incl. tool changes, name tag).
- Shared mining: client raycasts → `request_mine_hit(cell, tool)` → host applies damage → broadcasts `voxel_changed(cell, new_state)`. Drops go to the player who landed the killing hit.
- Per-player inventory of mined ore. Local UI; host RPCs `gained_material(peer_id, kind, amount)` to the right peer.
- Stamina is purely local (no replication).
- Map/fog: each peer reveals locally, periodically diffs newly-explored cells to host; host merges and rebroadcasts. Map is shared.
- Text chat: `request_chat(text)` → host → broadcast. HUD overlay, last 6 lines.
- Player roster (Tab key): name, ping. Gold hidden.

### Host-only systems in Phase 1 (locked for guests)
Vendors, contract board, claim vendor board, boat purchase, build mode/factory placement. Show "Host only — coming soon" tooltip on guest interaction. Guests can mine and walk through host's existing factory and watch belts run. Boats are not interactable for guests in Phase 1 — full boat multiplayer (passengering, multiple owned boats) lands in Phase 2.

### Save & load
- Host saves world + all player profiles bundled.
- Joining an existing world: profile loaded by steam_id if present; otherwise fresh.
- Single-player save auto-migrates on first MP session.
- Guests have no local save — progress lives in whichever host's world they last played.

### Acceptance criteria
- Host launches, invites a friend via Steam overlay, friend joins within ~5s.
- Both players see each other move smoothly with no visible warping under typical home internet.
- Both can swing tools and mine the same ore patch — patch depletes consistently for both.
- Each player keeps their own ore counts.
- If host quits, guests are cleanly disconnected with "Session ended".
- If guest quits, host continues; on reconnect inventory is restored.
- Single-player still works with no behavior change for solo players.

### Risks & mitigations
- **Voxel mining replication chattiness on large terrain.** RPC only on actual state transitions (voxel destroyed, ore tier changed), not per-frame.
- **Steam dev workflow.** Document the 480 app-id workflow + a `steam_appid.txt` file in the project root; `.gitignored` for real builds.
- **Late-join voxel snapshot size.** World generator is deterministic; send only modified-from-genseed diffs.

## Phase 2 — Core economy multiplayer

**Goal:** Each player runs their own economy. Vendors, gold, contracts, claims, boats all work for guests. Factories remain host-only.

### What's added
- **Per-player gold** keyed by steam_id on host; replicates only to its owner. Other players see name but not balance.
- **Vendors usable by all.**
  - Buy: `request_vendor_buy(vendor_id, item_id, qty)` → host validates inventory + gold + stock → commits → RPCs `vendor_buy_resolved(success, new_gold, inventory_delta, new_vendor_stock)`.
  - Stock is shared world state. Race for last item: host serializes — first wins, second gets "out of stock".
  - Vendor UI is local; no shared cursor.
- **Contracts board.**
  - Personal contracts only in Phase 2 (party-pooled deferred).
  - Available list is shared; claimed contracts marked taken globally.
  - `request_claim_contract(contract_id)` → host assigns to peer → broadcasts.
  - `request_turn_in_contract(contract_id)` → host validates inventory → applies rewards to that peer.
- **Claim vendor board.**
  - Claims are purchasable per-player; mining stays open to everyone.
  - Each claim stores `claimed_by_steam_id` + `mined_per_player` map.
  - Owner gets a small XP/gold "owner bonus" when anyone mines on their claim.
  - `request_buy_claim(claim_id)` → host validates gold + availability → assigns ownership → broadcasts.
- **Boats.** Each player can buy their own. Multiple boats spawn in world keyed by owner. Anyone can passenger; only owner can drive. Boats sync via `MultiplayerSynchronizer`.
- **Roster UI extended.** Name, contract level, claim level, ping. Gold still hidden.

### Save shape additions
- `world.claims[claim_id].owner_steam_id`, `world.claims[claim_id].mined_per_player`.
- `world.contracts.assignments[contract_id] = steam_id`.
- `world.boats[]`.
- `players[steam_id].contract_level/xp`, `claim_level/xp`, `has_boat`.

### Acceptance criteria
- Two players each independently mine, sell to a vendor, watch their own gold rise without interference.
- Both try to buy last item from a vendor: exactly one succeeds, other gets clean "out of stock".
- Player A claims a contract; B sees it become unavailable in real time; only A can turn it in.
- Player A buys a claim; B can still mine on it; A receives owner-bonus credit.
- Two players each own a boat; a third can passenger.
- Save/load round-trips all of the above, including which contracts each player has active.

### Risks & mitigations
- **Race conditions on shared resources.** Host-authoritative + reliable RPC; clients never self-validate.
- **Save migration from Phase-1 saves.** Existing claims have no `owner_steam_id`. Migration: unowned claims → available; pre-existing single-player owned claim → host's steam_id.

## Phase 3 — Factories multiplayer

**Goal:** Each player can place, run, and own their own factory. Others can walk through it, see machines working, see items moving on belts (visually plausible, not pixel-perfect), and deliver materials with permission.

### Authority for factories
- Host remains authoritative. `FactoryWorld` and `BuildController` autoloads tick only on host. Clients never simulate.
- Each placed building has `save_id` + `owner_steam_id` + `open_to_party: bool`.
- Owner can place/destroy/configure their own buildings.
- Anyone can interact with a building only if owner enabled `open_to_party` (default off).

### What replicates
- **Building placements.** `building_placed(building_data)`, `building_removed(save_id)`, `building_configured(save_id, recipe/etc)` — all reliable RPC, host-broadcast. Clients spawn/despawn visuals; no simulation locally.
- **Hopper / queue contents.** Snapshots (not deltas) at low rate (~2 Hz) only to peers within ~30m of that building. Out-of-range buildings sleep on clients.
- **Belt items (the hard part).**
  - Host streams a compact "belt summary" per belt to nearby clients: `[item_kind, fraction_along_belt]` array, ~5 Hz.
  - Clients lerp item visuals between consecutive summaries. No physics, no simulation client-side.
  - Belts > ~30m away send no updates; clients render last known state frozen.
- **Machine state.** idle/working/output-blocked/input-starved as a single byte, replicated only on transitions. Drives visual animation/particles.

### Player ↔ factory interaction
- "Drop item into hopper": `request_factory_input(save_id, item_id, qty)` → host validates proximity + permission + inventory → moves from inv to hopper.
- "Take from output": symmetric.
- "Toggle building open-to-party": owner-only RPC; host updates state + broadcasts.
- Build mode: client raycasts and shows ghost building locally. On confirm: `request_place_building(kind, cell, rotation, recipe)` → host validates collision/cost/ownership-of-cell → places + broadcasts.

### Constraints
- Two players cannot place buildings in the same cell. Host serializes; loser gets `place_failed("collision")`.
- Belts only connect to buildings of the same owner in Phase 3 (cross-owner links deferred).

### Bandwidth budget
- Movement/animation: ~1–2 KB/s per remote player.
- Factories: target ~5–10 KB/s per client even with a sizable factory in view, achieved via proximity sleep + low-rate snapshots.
- LOD fallback: if host saturates with 4 players each near 100+ buildings, drop belt summaries to 1 Hz beyond 15m.

### Save shape additions
- `world.factory.buildings[].owner_steam_id`, `world.factory.buildings[].open_to_party`.
- `world.factory.links[]` host-owned; ownership inferred from connected buildings.

### Acceptance criteria
- Two players each place independent factories on different parts of the map. Both run continuously on host. Each can see the other's factory when nearby.
- Belts move at consistent visual speed for everyone within range (no warping).
- Walking 50m away from a factory does not degrade FPS meaningfully (proximity sleep working).
- Save/restart preserves all buildings, ownership, links, hopper contents, recipes for both players.
- Race for same cell: exactly one placement succeeds.
- Late join: world with 200 buildings → all spawn within ~2–3 seconds before player release.

### Risks & mitigations
- **Host CPU.** Factory simulation is the heaviest workload. Multiplayer adds replication, not tick load. If saturated, factory ticks already use fixed-step updates and can be load-balanced.
- **Belt visual desync.** Items can appear to "jump" if summaries arrive late. Clients always lerp; ignore stale summaries.
- **Save migration from Phase 2.** Existing factory buildings have no `owner_steam_id`. Migration: assign all to host's steam_id.
- **Permission UX.** Getting "can my friend put coal in my smelter" right matters. A simple, discoverable per-building UI toggle.

### Deferred to Phase 4
- Cross-player belt links.
- Shared blueprints between players.
- Per-machine (not per-building) permissions.

## Phase 4 — Remaining systems multiplayer

After Phase 3 the foundation is mature. Remaining roadmap systems group by how much new netcode they need.

### Group A — "Just save it" (negligible netcode)
Per-player progression with no inter-player dependency. Lives in `players[steam_id]`, replicated to its owner only.
- `02_progression_stats_core.md` — per-player stats.
- `03_item_shop.md` — same pattern as vendors from Phase 2.
- `04_passive_tree_v1.md` — client computes effects locally; host re-validates effect numbers when used in damage RPC.
- `08_contract_modifiers_blueprints.md` — per-player data attached to the contract assignment record.

### Group B — Builds on Phase 3 framework
- `05_building_pieces_and_base_utility.md` — foundations, walls, lamps, storage crates. Reuses Phase-3 building-place RPC pipeline. Storage crates need shared-or-private toggle (mirror Phase-3 hopper permission flag).
- `09_factory_upgrades_advanced_machines.md` — new building kinds plug into the same place/configure/sim pipeline.

### Group C — Combat (genuinely new netcode)
Covers `06_combat_weapons_v1.md` + `07_island_threat_reward.md`.
- **Enemy spawning.** Host owns `EnemySpawner`. Enemies spawn via `MultiplayerSpawner`. Each has a `MultiplayerSynchronizer` for transform + animation state. Host runs AI; clients render only.
- **Damage.** `request_attack(target_kind, target_id, weapon_id)` from client → host computes damage using attacker's passive-tree modifiers → applies to target → broadcasts `damage_dealt(target_id, amount, source_peer_id)` for hit feedback.
- **Player death/respawn.** Host marks dead, broadcasts ragdoll, respawns at last claim or default spawn after a timer. Default: drop nothing on death (low-frustration co-op). Lobby toggle for "hardcore: drop everything".
- **Friendly fire.** Default off. Lobby setting.
- **Loot drops.** World entities spawned via `MultiplayerSpawner`. Anyone can pick up; pickup goes through host: `request_pickup(loot_id)`.
- **Combat range.** Enemies replicate transform at full rate to peers within ~50m, sleep otherwise (proximity-LOD).

### Group D — Party / prestige
`10_company_rank_prestige.md` — per-player rank. A "company" in MP is still each player individually. Defer "shared company" as a future optional feature. This puts prestige in Group A.

### Acceptance criteria
- All systems above work end-to-end with 2+ players in a single session without single-player fallback.
- Combat: two players fighting same enemy each see hits, get individual XP/loot credit per the design's rules, can revive each other (if revive lands in `06`).
- Death/respawn doesn't desync the world.
- All Phase 4 additions round-trip through save/load.

### Risks & mitigations
- **Combat netcode user-visible quality bar.** "I hit but it didn't register" feels worse than vendor lag. Mitigation: client-side hit prediction with host correction.
- **Roadmap ordering.** Late-bound features (passive tree, factory upgrades) might land *before* their MP phase ships. Plan: every new feature added to the single-player roadmap from Phase 1 onward includes a "MP notes" section in its design brief specifying which phase wires it up.
- **Instanced encounters.** `07_island_threat_reward.md` may introduce boss rooms / instances. Flag for a future spec if it goes that direction.

## Cross-cutting concerns

### Existing single-player save migration
`world.version` increments at each phase that changes shape (Phase 1 → v2, Phase 2 → v3, Phase 3 → v4, Phase 4 → v5). `SaveGame.load_now()` runs forward migrations sequentially.

### Testing strategy
- Each phase ships with a `tests/multiplayer/<phase>` folder containing scripted reproductions of the acceptance criteria where automatable.
- Manual playtest checklist per phase, run with at least 2 humans before declaring done.
- Synthetic bot client (a "headless guest" launched in another Godot instance on the same machine) for solo verification of replication.

### Bandwidth & performance budgets (per remote peer, steady state)
- Phase 1: ≤ 5 KB/s.
- Phase 2: ≤ 10 KB/s.
- Phase 3: ≤ 20 KB/s with factory in view.
- Phase 4: ≤ 30 KB/s in active combat.

### Code organization
- `res://scripts/net/net.gd` — autoload, peer & session.
- `res://scripts/net/net_utils.gd` — RPC helpers.
- `res://scripts/net/snapshot.gd` — late-join snapshot assembly.
- `res://scenes/ui/multiplayer_menu.tscn` — lobby UI.
- `res://scenes/remote_player.tscn` — non-local player visual.
- Per-system MP code lives next to the system: `vendor_ui.gd` adds RPC stubs; it does not move into a separate `vendor_net.gd`.

## Phase ordering & gating
Each phase is independently shippable and testable. Phase N+1 cannot start until Phase N's acceptance criteria pass and a 2-human playtest has signed off. After Phase 1 ships, `MULTIPLAYER.md` in the repo root tracks which phase is current and what's locked behind which phase for guests.
