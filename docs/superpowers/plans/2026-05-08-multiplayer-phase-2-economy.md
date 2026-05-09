# Multiplayer Phase 2 — Core Economy Implementation Plan (Structural)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to re-elaborate this structural plan into bite-sized TDD tasks **after Phase 1 ships**. The structural form below locks the task list, file list, and acceptance criteria; exact code references are deliberately deferred until the Phase-1 foundation is real.

**Goal:** Each player runs their own economy in the shared world. Vendors, contracts, claims, and boats all work for guests. Factories remain host-only.

**Architecture:** Builds on Phase 1's `Net` autoload, `NetUtils`, and bundled save schema. All new flows follow the same request → host validate → broadcast pattern. No new networking infrastructure beyond per-system RPC handlers.

**Tech Stack:** unchanged from Phase 1.

**Spec section:** [Phase 2 in design doc](../specs/2026-05-08-multiplayer-design.md#phase-2--core-economy-multiplayer)

**Prerequisites:**
- Phase 1 complete (`mp-phase-1-complete` tag pushed).
- 2-human playtest of Phase 1 passed.
- Save file format is at version 2.

---

## File Structure

### Created
| File | Responsibility |
|---|---|
| `res://scripts/net/economy_net.gd` | Stateless namespace for the four economy RPC families (vendor, contract, claim, boat). |
| `res://scripts/net/save_migration_v2_to_v3.gd` | Save schema migration: claim ownership, contract assignments, boats array, per-player level/xp. |
| `res://scripts/boat.gd` (likely already exists; promote to per-player owned) | Owner-aware drive/passenger logic. |
| `res://scenes/boat.tscn` (likely already exists; add `MultiplayerSynchronizer`) | |
| `res://tests/gut/test_save_migration_v2_to_v3.gd` | |
| `res://tests/gut/test_vendor_race.gd` | Two simultaneous purchase requests for the last item. |
| `res://tests/gut/test_contract_assignment.gd` | Assignment serialization + double-claim prevention. |
| `res://tests/gut/test_claim_owner_bonus.gd` | Owner gets bonus credit when non-owner mines on their claim. |

### Modified
| File | What changes |
|---|---|
| `res://scripts/save_game.gd` | Bump SAVE_VERSION to 3. Add v2→v3 migration. Persist `world.claims[].owner_steam_id`, `world.claims[].mined_per_player`, `world.contracts.assignments`, `world.boats`, per-player level/xp. |
| `res://scripts/vendor_ui.gd` | Replace local-only buy/sell with `request_vendor_buy/sell` RPCs. Remove the Phase-1 host-only guard. UI is per-player local; transactions are host-resolved. |
| `res://scripts/vendor_data.gd` (or wherever vendor stock lives) | Stock owned by host; clients receive `vendor_stock_changed` broadcasts. |
| `res://scripts/contract_board.gd` | Replace local-only claim/turn-in with RPC pattern. Track per-contract `assigned_to_steam_id`. Remove Phase-1 host-only guard. |
| `res://scripts/claim_vendor_board.gd` | Replace local-only buy with `request_buy_claim`. Remove Phase-1 host-only guard. Add owner-bonus credit on mining hits. |
| `res://scripts/miner.gd` | When granting materials from a mining hit, also credit owner-bonus to the claim owner if the cell is on a claimed parcel. |
| `res://scripts/player.gd` (or wherever boat purchase + entry is handled) | Replace local boat with per-player owned boats. Allow passengering on others' boats. Remove Phase-1 host-only guard on purchase. |
| `res://scenes/boat.tscn` | Add `MultiplayerSynchronizer` for transform; gate `drive_input` on `is_multiplayer_authority`. |
| `res://scripts/ui/multiplayer_menu.gd` (roster) | Show contract level + claim level per peer. Gold remains hidden. |
| `MULTIPLAYER.md` | Update "active phase" + working/locked feature lists. |

---

## Task list (in execution order)

### Pre-Phase Setup
- [ ] Branch `feat/multiplayer-phase-2` off main after Phase 1 merges.
- [ ] Verify Phase 1 ships clean: `git checkout mp-phase-1-complete` boots, single-player works, MP works.
- [ ] Confirm any save files in user testing have been migrated to v2.

### Save migration v2 → v3 (TDD — pure logic, do this first)
1. Write failing test for `migrate_v2_to_v3` covering:
   - v2 blob → v3 shape (claims gain `owner_steam_id`/`mined_per_player`, contracts gain `assignments`, boats list defaults to empty if not present, players gain `contract_level/xp` and `claim_level/xp` if absent).
   - v3 blob passes through unchanged.
   - Empty/sparse blobs default safely.
2. Implement `migrate_v2_to_v3` as a static method on `save_game.gd`.
3. Wire into `load_now()` — sequential migration `v1→v2→v3`.
4. Bump `SAVE_VERSION` constant to 3.
5. Round-trip a real Phase-1 save through migration.
6. Commit.

### Vendors usable by all
1. Read `vendor_ui.gd` and the data layer that holds vendor stock.
2. Move stock from per-vendor-instance to a host-owned `world.vendors` map keyed by vendor id.
3. Add `request_vendor_buy(vendor_id, item_id, qty)` and `request_vendor_sell(...)` (RPC, any_peer → host).
4. Host validates: vendor exists, stock available, requester gold sufficient (buy) or inventory sufficient (sell).
5. On success: host updates stock + per-player gold + per-player materials; broadcasts `vendor_stock_changed(vendor_id, new_stock)`; tells the requester `vendor_buy_resolved(success, gold_delta, inventory_delta)`.
6. On failure: tells requester `vendor_buy_resolved(false, 0, {}, reason)` with reason string ("out_of_stock" / "insufficient_gold" / etc.).
7. Remove the Phase-1 host-only guard from vendor entry points.
8. Unit test: simulate two clients requesting the last unit of an item; assert exactly one succeeds, the other gets "out_of_stock".
9. Manual playtest: two players buy/sell at same vendor; balances diverge correctly.
10. Commit.

### Contracts board usable by all
1. Read `contract_board.gd`. Note the data shape for available/active contracts.
2. Move available list to host-owned `world.contracts.available`. Move per-player active list to per-player profile. Add `world.contracts.assignments[contract_id] = steam_id`.
3. Add `request_claim_contract(contract_id)`, `request_turn_in_contract(contract_id)`.
4. Host validates: contract exists, not already assigned (claim) or assigned to requester with quota met (turn-in).
5. On claim: assign + broadcast `contract_assigned(contract_id, steam_id)`. UI shows it as "claimed by Alice" for non-owners and "claimed by you" for owner; turn-in button visible only to owner.
6. On turn-in: validate inventory, deduct, grant rewards (gold + xp + level-up if applicable), free the contract slot, broadcast `contract_completed(contract_id, steam_id)`.
7. Remove Phase-1 host-only guard.
8. Unit test: assignment serialization round-trip, double-claim prevention.
9. Playtest: A claims, B sees it gone; only A turns in.
10. Commit.

### Claims with shared mining + owner bonus
1. Read `claim_vendor_board.gd` and the claim-tracking code in `miner.gd` (the "owned_id"/"owned_mined" pattern).
2. Refactor claims to a host-owned `world.claims[claim_id]` dict with `owner_steam_id` and `mined_per_player` map.
3. Add `request_buy_claim(claim_id)`. Host validates gold + availability → assigns ownership → broadcasts `claim_purchased(claim_id, owner_steam_id)`.
4. In the host-side mining-hit handler from Phase 1 (`_apply_mine_hit_authoritative`), look up the cell's claim. If the cell is in a claimed parcel:
   - Increment `world.claims[claim_id].mined_per_player[mining_player_steam_id]`.
   - If mining player ≠ claim owner, grant the owner a small XP/gold owner-bonus (use a tunable in `material_defs.gd` or a new `economy_constants.gd`).
   - Tell the owner `owner_bonus_received(claim_id, gold, xp)` so their UI flashes a notification.
5. Remove Phase-1 host-only guard on claim board.
6. Unit test: owner-bonus is applied when a non-owner mines on a claimed parcel; not applied when the owner mines on their own.
7. Playtest: A buys claim, B mines on it, A sees their owner-bonus flash and gold tick up.
8. Commit.

### Boats per player
1. Read existing boat code (likely `boat.gd` and how the player buys/enters the boat).
2. Refactor: instead of "the player has a boat (singleton)", the world owns an array of boats, each with `owner_steam_id`. A player has at most one boat.
3. Add `MultiplayerSynchronizer` to `boat.tscn` syncing transform + driver-occupied state. Authority: when boat is driven, authority is the driver; otherwise host.
4. Add `request_buy_boat()` → host validates gold → spawns boat via `MultiplayerSpawner` keyed by owner steam id → broadcasts.
5. Boat enter: only owner can drive; anyone can passenger. Driving consumes movement input from authority peer.
6. Persist boats in `world.boats[]` and rebuild on load.
7. Remove Phase-1 host-only guard on boat purchase.
8. Playtest: each of two players buys a boat; both can drive their own; either can passenger on the other's.
9. Commit.

### Player gold replication
1. In `miner.gd`, gold becomes per-steam-id like materials are.
2. Gold updates RPC only to the owner (host calls `tell_peer(owner_peer_id, "_gold_changed_rpc", [new_amount])`).
3. Other players never receive others' gold values; HUD never displays others' gold.
4. Roster UI shows only contract level + claim level + ping.
5. Commit.

### Roster UI extension
1. Update `multiplayer_menu.gd` roster row format: `name — Contract Lv X — Claim Lv Y — Zms`.
2. Pull contract level + claim level from the host (broadcast on change) or via a small `request_player_summary(steam_id)` RPC.
3. Commit.

### Acceptance gate
1. Verify all spec acceptance criteria for Phase 2 with a 2-human playtest.
2. Verify save round-trips through v3 schema.
3. Verify single-player parity (no regressions).
4. Run all GUT tests.
5. Tag `mp-phase-2-complete`.
6. Update `MULTIPLAYER.md`.
7. Commit.

---

## Test approach

| Surface | Test type |
|---|---|
| Save migration v2→v3 | GUT unit |
| Vendor race (two clients buy last item) | GUT unit using stub Net |
| Contract assignment / double-claim prevention | GUT unit |
| Claim owner-bonus credit logic | GUT unit |
| Vendor / contract / claim end-to-end UX | 2-human playtest |
| Boats: per-player drive + cross-player passenger | 2-human playtest |
| Single-player parity | Solo playthrough checklist |

---

## Risks specific to Phase 2

- **Race conditions** on shared resources (last contract, last vendor stock unit). Mitigation: every client request is reliable RPC to host; host serializes; host's response is the source of truth.
- **Save migration on long-lived saves**: Phase-1 saves don't have any of the new fields. Migration must default safely (unowned claims = available, no contract assignments = empty map, no boats array = empty list).
- **Owner-bonus tuning**: getting the bonus too generous makes claims pay-to-win for popular spots; too stingy makes claims worthless. Lock a default in `economy_constants.gd` and surface via Admin autoload for live tuning.
- **Boat authority handoff**: if driver leaves while in the boat, authority needs to fall back to host cleanly. Add an explicit `_release_drive_authority()` on disconnect.

---

## Acceptance criteria (lifted from spec)

- Two players in the same world each independently mine, sell to a vendor, watch their own gold rise without interference.
- If both try to buy the last item from a vendor, exactly one succeeds and the other gets a clean "out of stock" message.
- Player A claims a contract; Player B sees the contract become unavailable in real time. Only A can turn it in.
- Player A buys a claim; Player B can still mine on it; A gets the owner-bonus credit.
- Boats: two players each own a boat; a third can passenger.
- Save/load round-trips all of the above, including which contracts each player has active.

---

## Phase 2 Done When

- [ ] All tasks above complete
- [ ] All acceptance criteria pass in 2-human playtest
- [ ] All GUT tests pass
- [ ] Single-player parity verified
- [ ] Save migration v1→v2→v3 verified
- [ ] `mp-phase-2-complete` tag pushed
- [ ] `MULTIPLAYER.md` updated to mark Phase 2 shipped and Phase 3 active
