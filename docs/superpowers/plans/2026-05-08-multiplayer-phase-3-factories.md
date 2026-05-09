# Multiplayer Phase 3 — Factories Implementation Plan (Structural)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to re-elaborate this structural plan into bite-sized TDD tasks **after Phase 2 ships**. The structural form below locks the task list, file list, and acceptance criteria; exact code references are deliberately deferred until Phase-2 lands and the actual factory code has been touched.

**Goal:** Each player can place, run, and own their own factory. Other players can walk through it, see machines working, see items moving on belts (visually plausible, not pixel-perfect), and deliver materials to it with permission.

**Architecture:** Host remains authoritative for *all* factory simulation — `FactoryWorld` and `BuildController` autoloads tick only on host. Clients never simulate. New work focuses on (a) per-building ownership + permission flag, (b) low-bandwidth visual replication of belt items via lerped summaries, (c) proximity-based LOD so distant factories don't tax bandwidth.

**Tech Stack:** unchanged.

**Spec section:** [Phase 3 in design doc](../specs/2026-05-08-multiplayer-design.md#phase-3--factories-multiplayer)

**Prerequisites:**
- Phase 2 complete (`mp-phase-2-complete` tag pushed and 2-human playtest passed).
- Save schema is at version 3.

---

## File Structure

### Created
| File | Responsibility |
|---|---|
| `res://scripts/net/factory_net.gd` | Stateless namespace for factory RPC families: place / remove / configure / hopper-input / hopper-output / toggle-permission / belt-summary. |
| `res://scripts/net/proximity_lod.gd` | Per-peer proximity tracking; tells host which buildings each peer is "near" so summaries are sent only to relevant peers. |
| `res://scripts/net/save_migration_v3_to_v4.gd` | Save schema migration for `owner_steam_id` + `open_to_party` on existing buildings. |
| `res://tests/gut/test_save_migration_v3_to_v4.gd` | |
| `res://tests/gut/test_belt_summary_serialization.gd` | Belt summary array round-trip. |
| `res://tests/gut/test_factory_place_collision.gd` | Two simultaneous placements on same cell — exactly one wins. |
| `res://tests/gut/test_factory_permission_gate.gd` | Non-owner blocked from interacting with `open_to_party=false` building. |

### Modified
| File | What changes |
|---|---|
| `res://scripts/factory/factory_world.gd` | Per-building `owner_steam_id` + `open_to_party`. Tick loop unchanged in shape but now emits "machine state changed" only on transitions; emits belt summaries on a fixed interval per peer-proximity. |
| `res://scripts/factory/build_controller.gd` | Replace local-only place/remove/configure with RPC pattern. On host, validate ownership/cost/collision. On client, render ghost building locally during build mode; only commit via host. |
| `res://scripts/factory/building.gd` | Add `owner_steam_id`, `open_to_party` fields. Per-building UI surface includes a "Open to party" toggle visible only to owner. |
| `res://scripts/factory/loader.gd` (and other input-receiving machines) | Accept items only when `open_to_party` or requester is owner. |
| `res://scripts/factory/smelter.gd`, `forge.gd` | Same permission gate on input/output interactions. |
| `res://scripts/save_game.gd` | SAVE_VERSION → 4. Add v3→v4 migration assigning `owner_steam_id = host's steam_id` to all existing buildings, default `open_to_party = false`. |
| `MULTIPLAYER.md` | Update active phase + working/locked feature lists. |

---

## Task list (in execution order)

### Pre-Phase Setup
- [ ] Branch `feat/multiplayer-phase-3` off main after Phase 2 merges.
- [ ] Confirm Phase 2 ships clean.
- [ ] Capture a baseline bandwidth profile of an active host's CPU/network with one factory of ~20 buildings — used to verify Phase 3's proximity-LOD pays off.

### Save migration v3 → v4 (TDD first)
1. Failing test: `migrate_v3_to_v4(blob, host_steam_id)` adds `owner_steam_id = host_steam_id` and `open_to_party = false` to every entry in `world.factory.buildings[]`.
2. Test: a building that already has `owner_steam_id` is left untouched (idempotency).
3. Test: empty/missing factory section defaults safely.
4. Implement migration; bump `SAVE_VERSION` to 4; chain into `load_now()`.
5. Round-trip a real Phase-2 save through migration.
6. Commit.

### Per-building ownership scaffolding
1. Read `factory/building.gd`. Add `owner_steam_id: String` and `open_to_party: bool` exports.
2. In `BuildController`'s place flow (Phase-1 host-only entry), record owner from request sender.
3. Persist both fields in `get_save_data` / `apply_save_data`.
4. Unit test: building.get_save_data round-trips both fields.
5. Commit.

### Building placement RPC
1. Convert `BuildController.enter_build_mode` / placement-confirm flow:
   - Build mode itself is purely client-side (ghost preview, raycast, snap-to-grid).
   - On confirm, send `request_place_building(kind, cell, rotation, recipe)` to host.
   - Host validates: cell is empty, requester has cost, kind is valid.
   - On success: place via existing factory_world API + broadcast `building_placed(building_data)`.
   - On collision/cost-fail: tell requester `place_failed(reason)`.
2. Clients render the building from the broadcast data (no simulation locally).
3. Unit test: two `request_place_building` calls in same tick on same cell → exactly one wins, other gets "collision".
4. Playtest: two players place separate factories on different parts of map.
5. Commit.

### Building remove / configure RPC
1. Same pattern as placement. `request_remove_building(save_id)`, `request_configure_building(save_id, recipe)`.
2. Host enforces: only owner can remove or configure.
3. Broadcast `building_removed` / `building_configured` on success.
4. Commit.

### Hopper / queue snapshot replication (proximity-aware)
1. Define a "building summary" structure: `{ save_id, hopper_contents: Dict, queue: Array, machine_state: byte }`.
2. On host, every 0.5s (2 Hz), for each peer, find buildings within ~30m and send `building_summary_batch_rpc(summaries)` reliable.
3. Clients apply summary to local building visual (no simulation).
4. Out-of-range buildings are not sent; clients show "?" or last-known frozen state.
5. Unit test: serialization round-trip of a 50-summary batch.
6. Playtest: walk near a factory and watch hopper UI update; walk away and confirm no further updates.
7. Commit.

### Belt visual replication via summaries
1. Define a belt summary: `{ belt_save_id, items: [{ kind, fraction }] }`.
2. On host, every 0.2s (5 Hz), for each peer, for belts within ~30m, send `belt_summary_batch_rpc`.
3. Clients lerp item visuals between consecutive summaries:
   - On receive, store `[items_prev, items_next, t_received]`.
   - In `_process(delta)`, lerp item position from prev fraction to next fraction over the inter-summary interval.
4. Beyond ~15m proximity, drop frequency to 1 Hz (LOD fallback).
5. Belts beyond 30m: clients render belt as visually static or empty.
6. Unit test: lerp interpolation produces expected fraction at midpoint.
7. Playtest: belts move at consistent visual speed for everyone; no warping.
8. Commit.

### Machine state transitions
1. On host, when a machine transitions between idle/working/output-blocked/input-starved, broadcast `machine_state_changed(save_id, new_state_byte)` reliable.
2. Clients update only the visual / particle / sound on that transition.
3. Don't poll state per tick — only emit on transition.
4. Commit.

### Player ↔ factory interactions (with permission)
1. Add `request_factory_input(save_id, item_id, qty)`, `request_factory_output(save_id, item_id, qty)`.
2. Host validates: requester proximity, requester inventory (input) or building output buffer (output), and permission (`requester == owner OR building.open_to_party`).
3. On success: move item between player inv and building hopper; broadcast updated summary.
4. Add the "Open to party" toggle to the per-building UI (owner-only). RPC: `request_toggle_party_access(save_id)`.
5. Unit test: non-owner blocked from `open_to_party=false` building; allowed when toggled true.
6. Playtest: A toggles on; B can drop coal in A's smelter.
7. Commit.

### Proximity LOD scaffolding
1. Implement `proximity_lod.gd`: tracks per-peer position, returns lists of "buildings near peer X" and "belts near peer X".
2. Used by both hopper-summary and belt-summary tasks above.
3. Unit test: a building 25m from peer A but 100m from peer B is in A's near-list, not B's.
4. Commit.

### Late-join factory snapshot extension
1. Extend `NetSnapshot.build` to include all buildings + links (full state, not summary form — late-join needs everything).
2. Snapshot apply on client spawns all building visuals before releasing the player into the world.
3. Verify late-join with a 200-building world completes within ~2-3 seconds.
4. Commit.

### Acceptance gate
1. 2-human playtest hits all spec acceptance criteria.
2. Bandwidth budget verified: ≤ 20 KB/s per peer with factory in view.
3. FPS doesn't degrade when walking 50m away from factory (proximity sleep working).
4. Same-cell placement race: exactly one wins.
5. Save round-trips at v4.
6. Single-player parity verified.
7. All GUT tests pass.
8. Tag `mp-phase-3-complete`.
9. Update MULTIPLAYER.md.
10. Commit.

---

## Test approach

| Surface | Test type |
|---|---|
| Save migration v3→v4 | GUT unit |
| Place collision race | GUT unit (stub host with two simulated requesters) |
| Belt summary serialization | GUT unit |
| Belt summary interpolation | GUT unit (numeric lerp test) |
| Permission gate | GUT unit |
| Proximity-LOD lookups | GUT unit |
| End-to-end factory replication | 2-human playtest |
| Bandwidth profiling | Manual with `multiplayer.get_peer(...).get_statistics()` or external tool |
| Late-join snapshot at scale | Manual with seeded world of 200 buildings |

---

## Risks specific to Phase 3

- **Host CPU**: factory simulation is the heaviest workload. Multiplayer adds replication overhead, not tick load. Mitigation: existing fixed-step ticks; if saturated, a follow-up can split ticks across frames. Track host frame time during playtest.
- **Belt visual desync**: items can appear to "jump" if summaries arrive late or out of order. Mitigation: clients always lerp; ignore stale summaries (compare a sequence number).
- **Save migration from Phase 2**: existing buildings have no `owner_steam_id`. Migration assigns them to host's steam_id. Edge case: a Phase-2 save that was started by a now-departed friend has no clean owner — migration falls back to current host.
- **Permission UX**: getting "can my friend put coal in my smelter" right requires a discoverable UI toggle. Make the building UI's first row the open/closed state with a clear icon.
- **Cross-player belt links**: explicitly out of scope for Phase 3 (deferred to Phase 4 polish). Reject any belt placement that would connect to a building of a different owner with a clear error.

---

## Acceptance criteria (lifted from spec)

- Two players each place independent factories on different parts of the map. Both factories run continuously on host. Each player can see the other's factory when nearby.
- Belts move at consistent visual speed for everyone within range (no warping/teleporting items).
- A player walks 50m away from a factory; FPS does not degrade meaningfully (proximity sleep working).
- Save/restart preserves all buildings, ownership, links, hopper contents, recipes for both players.
- Two players try to place a building in the same cell at the same instant — exactly one succeeds.
- Late join: a player joining after the world has 200 buildings sees them all spawn within ~2-3 seconds before being released to the world.

---

## Phase 3 Done When

- [ ] All tasks above complete
- [ ] All acceptance criteria pass in 2-human playtest
- [ ] All GUT tests pass
- [ ] Bandwidth ≤ 20 KB/s per peer with factory in view
- [ ] Single-player parity verified
- [ ] Save migration v1→v2→v3→v4 verified
- [ ] `mp-phase-3-complete` tag pushed
- [ ] `MULTIPLAYER.md` updated
