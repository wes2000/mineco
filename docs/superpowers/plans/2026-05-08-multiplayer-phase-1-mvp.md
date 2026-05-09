# Multiplayer Phase 1 — MVP Co-op Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two friends can be in the same Mine Co. world, see each other move, mine the same ore, and chat. Vendors/contracts/claims/factories remain host-only; guests get a "Host only" tooltip on those.

**Architecture:** Listen-server using GodotSteam's `SteamMultiplayerPeer`. Host is authoritative for all world state. Approach C (Hybrid) — `MultiplayerSpawner` + `MultiplayerSynchronizer` for entities/transforms, explicit `@rpc` for game-state events. New autoload `Net` owns the peer + session lifecycle and exposes a thin `request_to_host` / `broadcast` API so gameplay code never touches `multiplayer.*` directly.

**Tech Stack:** Godot 4.6, GDScript, GodotSteam plugin (Steamworks SDK ≥ 1.58), GUT (Godot Unit Test) for unit tests.

**Spec:** [../specs/2026-05-08-multiplayer-design.md](../specs/2026-05-08-multiplayer-design.md) — Section "Foundation" + Section "Phase 1".

---

## File Structure

### Created
| File | Responsibility |
|---|---|
| `res://scripts/net/net.gd` | Autoload. Owns `SteamMultiplayerPeer`, session lifecycle, peer↔steam-id map, signals. |
| `res://scripts/net/net_utils.gd` | Stateless RPC helpers: `request_to_host`, `broadcast`, `tell_peer`, `is_host`, `local_player_id`. |
| `res://scripts/net/snapshot.gd` | Late-join snapshot assembly + apply. Used by host on peer-join and by clients on snapshot-receive. |
| `res://scripts/net/chat.gd` | Chat history buffer + RPC handlers. |
| `res://scripts/remote_player.gd` | Stripped non-local player visual. Mesh, animation tree, name tag, no camera/input. |
| `res://scenes/remote_player.tscn` | Scene for above. |
| `res://scenes/ui/multiplayer_menu.tscn` + `.gd` | Host / Join / Leave / roster UI. |
| `res://scenes/ui/chat_overlay.tscn` + `.gd` | HUD chat overlay (last 6 lines + input field). |
| `res://addons/godotsteam/...` | GodotSteam plugin (vendored or via plugin manager). |
| `steam_appid.txt` | Project root; contains `480` for dev. |
| `tests/gut/test_save_migration_v1_to_v2.gd` | Unit test for single-player → multiplayer save migration. |
| `tests/gut/test_net_authority.gd` | Unit test for `is_host()` / `local_player_id()` behavior. |
| `tests/gut/test_voxel_diff_apply.gd` | Unit test for late-join voxel diff serialization round-trip. |
| `tests/gut/test_chat_buffer.gd` | Unit test for chat history bounded buffer. |
| `MULTIPLAYER.md` | Repo root. "Phase 1 active. Vendors/contracts/claims/factories are host-only for guests." |

### Modified
| File | What changes |
|---|---|
| `res://scripts/save_game.gd` | Save schema bumps `version` 1 → 2. Adds `world` + `players[steam_id]` shape; migrates v1 saves on load. |
| `res://scripts/player.gd` | Wire `MultiplayerSynchronizer` config; ignore input when not local peer; expose mining-hit request. |
| `res://scripts/miner.gd` | `request_mine_hit(cell, tool)` host-side handler; `gained_material(peer_id, kind, amount)` RPC; per-player ore counts indexed by steam_id. |
| `res://scripts/island_voxel_generator.gd` | `apply_voxel_change(cell, new_state)` callable on clients (no-op simulation, only mesh/material update). |
| `res://scripts/map_data.gd` | Periodic exploration-diff RPC; merge logic on host. |
| `res://scripts/vendor_ui.gd` | If `not Net.is_host()` show "Host only" overlay and block interaction. |
| `res://scripts/contract_board.gd` | Same pattern. |
| `res://scripts/claim_vendor_board.gd` | Same pattern. |
| `res://scenes/main.tscn` | Add `MultiplayerSpawner` for players, `Net` autoload registration. |
| `res://project.godot` | Register `Net` autoload, add GodotSteam plugin, add input action `chat_open`. |
| `.gitignore` | Add `steam_appid.txt` (real production builds), Steam SDK build artifacts. |

---

## Pre-Phase Setup

### Task 0: Verify environment & branch

**Files:** none (environment only)

- [ ] **Step 1: Confirm Godot MCP session is connected**

Run via MCP: `mcp__godot-ai__session_manage(op="list")`
Expected: at least one session listed with the Mine Co. project path.

- [ ] **Step 2: Confirm current single-player baseline runs cleanly**

Run via MCP: `mcp__godot-ai__editor_state()`
Expected: editor reports ready, no script errors. Then `mcp__godot-ai__project_run()` and confirm `main.tscn` loads. Stop the run.

- [ ] **Step 3: Create a feature branch**

```bash
git checkout -b feat/multiplayer-phase-1
```

- [ ] **Step 4: Commit the spec + plan files**

```bash
git add docs/superpowers/specs/ docs/superpowers/plans/
git commit -m "docs(mp): add multiplayer spec + phase plans"
```

---

## Task 1: Add GodotSteam plugin

**Files:**
- Create: `res://addons/godotsteam/` (plugin tree)
- Create: `steam_appid.txt`
- Modify: `res://project.godot` — enable plugin
- Modify: `.gitignore` — exclude real-build steam_appid + Steam SDK binaries

- [ ] **Step 1: Install GodotSteam**

Use the GodotSteam release matching Godot 4.6 from https://github.com/GodotSteam/GodotSteam. Two install options — pick whichever the project already supports:
1. Drop `addons/godotsteam/` into the project (GDExtension build).
2. Use a GodotSteam-built editor binary.

For developer ergonomics across the team, prefer the GDExtension drop-in if available for 4.6.

- [ ] **Step 2: Add `steam_appid.txt`**

Write the file `steam_appid.txt` at project root with content `480` (Spacewar — public test app id).

- [ ] **Step 3: Enable plugin in project.godot**

Read `res://project.godot`, add to `[editor_plugins]` (or whatever the GodotSteam install instructions specify):
```
enabled=PackedStringArray("res://addons/godotsteam/plugin.cfg")
```

- [ ] **Step 4: Smoke test Steam initialization**

Create a temporary scene with a script that calls:
```gdscript
extends Node
func _ready():
    var ok = Steam.steamInit()
    print("Steam init: ", ok)
    print("Steam ID: ", Steam.getSteamID())
```
Run the scene. Expected: prints `Steam init: { status: 1 }` and a numeric Steam ID. If Steam isn't running locally, expected: prints failure code — that's fine, just confirm the addon is loaded.

Delete the temporary scene after.

- [ ] **Step 5: Update `.gitignore`**

Append:
```
# Steam — keep dev appid in repo, exclude shipped builds' real one if different
steam_sdk/
*.steam_internal
```

- [ ] **Step 6: Commit**

```bash
git add addons/godotsteam steam_appid.txt project.godot .gitignore
git commit -m "feat(mp): add GodotSteam plugin and dev app id 480"
```

---

## Task 2: Add GUT testing framework

**Files:**
- Create: `res://addons/gut/` (plugin tree)
- Create: `tests/gut/` directory
- Modify: `res://project.godot` — enable plugin

- [ ] **Step 1: Install GUT**

Drop the GUT addon (https://github.com/bitwes/Gut) into `res://addons/gut/`. Use the latest 4.x-compatible release.

- [ ] **Step 2: Enable in project.godot**

Same pattern as Task 1. Add to enabled `[editor_plugins]`.

- [ ] **Step 3: Configure test directory**

Create `res://.gutconfig.json`:
```json
{
  "dirs": ["res://tests/gut/"],
  "include_subdirs": true,
  "should_print_to_console": true,
  "log_level": 1
}
```

- [ ] **Step 4: Add a hello-world test**

Create `res://tests/gut/test_smoke.gd`:
```gdscript
extends GutTest

func test_truth():
    assert_true(true)
```

- [ ] **Step 5: Run GUT and confirm it passes**

In the editor, open the GUT panel and click Run. Expected: 1 test, 1 pass, 0 fail.
Or via MCP: `mcp__godot-ai__test_run({...})` if the project's test integration supports it.

- [ ] **Step 6: Commit**

```bash
git add addons/gut .gutconfig.json tests/gut/test_smoke.gd project.godot
git commit -m "test(mp): add GUT framework with smoke test"
```

---

## Task 3: Save schema migration v1 → v2 (TDD)

This is the lowest-risk piece of foundation to land first — it's pure logic, fully unit-testable, and unblocks the rest of Phase 1.

**Files:**
- Modify: `res://scripts/save_game.gd`
- Create: `res://tests/gut/test_save_migration_v1_to_v2.gd`

- [ ] **Step 1: Read current save_game.gd**

Run: `mcp__godot-ai__script_manage(op="read", params={"path": "res://scripts/save_game.gd"})`. Note the existing top-level keys, version constant, `collect_state()`, `apply_state()`, and the per-system `get_save_data()/apply_save_data()` calls.

- [ ] **Step 2: Write the failing migration test**

Create `res://tests/gut/test_save_migration_v1_to_v2.gd`:
```gdscript
extends GutTest

const SaveGameClass = preload("res://scripts/save_game.gd")

func _v1_save_blob() -> Dictionary:
    return {
        "version": 1,
        "player": {"position": [10.0, 5.0, -3.0], "rotation_y": 1.5, "current_tool": 2},
        "miner": {
            "materials": {"stone": 12, "iron": 4, "gold": 0},
            "gold_currency": 250,
            "has_boat": true,
        },
        "contracts": {"level": 3, "xp": 120, "available": [], "active": []},
        "claims": {"level": 2, "xp": 80, "owned_id": "claim_03", "owned_mined": {"claim_03": 14}},
        "map": {"explored": "", "explored_cell_count": 999},
        "factory": {"buildings": [], "links": []},
    }

func test_v1_blob_migrates_to_v2_shape():
    var migrated = SaveGameClass.migrate_v1_to_v2(_v1_save_blob(), "local")
    assert_eq(migrated["version"], 2)
    assert_has(migrated, "world")
    assert_has(migrated, "players")
    assert_eq(migrated["players"].size(), 1)
    assert_has(migrated["players"], "local")

func test_v1_player_data_routes_to_player_profile():
    var migrated = SaveGameClass.migrate_v1_to_v2(_v1_save_blob(), "local")
    var profile = migrated["players"]["local"]
    assert_eq(profile["position"], [10.0, 5.0, -3.0])
    assert_eq(profile["rotation_y"], 1.5)
    assert_eq(profile["current_tool"], 2)
    assert_eq(profile["materials"]["iron"], 4)
    assert_eq(profile["gold_currency"], 250)
    assert_eq(profile["has_boat"], true)
    assert_eq(profile["contract_level"], 3)
    assert_eq(profile["claim_level"], 2)

func test_v1_world_data_routes_to_world_section():
    var migrated = SaveGameClass.migrate_v1_to_v2(_v1_save_blob(), "local")
    var world = migrated["world"]
    assert_eq(world["map"]["explored_cell_count"], 999)
    assert_eq(world["factory"]["buildings"], [])

func test_v2_blob_passes_through_unchanged():
    var v2_blob = {"version": 2, "world": {}, "players": {}}
    var migrated = SaveGameClass.migrate_v1_to_v2(v2_blob, "local")
    assert_eq(migrated, v2_blob)

func test_missing_keys_default_safely():
    var sparse = {"version": 1, "miner": {"gold_currency": 5}}
    var migrated = SaveGameClass.migrate_v1_to_v2(sparse, "local")
    assert_has(migrated["players"], "local")
    assert_eq(migrated["players"]["local"]["gold_currency"], 5)
```

- [ ] **Step 3: Run test, confirm it fails**

Run GUT. Expected: `migrate_v1_to_v2` not defined → all five tests fail.

- [ ] **Step 4: Implement `migrate_v1_to_v2`**

Add to `save_game.gd`:
```gdscript
const SAVE_VERSION: int = 2

static func migrate_v1_to_v2(blob: Dictionary, local_steam_id: String) -> Dictionary:
    if blob.get("version", 1) >= 2:
        return blob
    var miner_block: Dictionary = blob.get("miner", {})
    var contracts_block: Dictionary = blob.get("contracts", {})
    var claims_block: Dictionary = blob.get("claims", {})
    var player_block: Dictionary = blob.get("player", {})
    var profile := {
        "position": player_block.get("position", [0.0, 0.0, 0.0]),
        "rotation_y": player_block.get("rotation_y", 0.0),
        "current_tool": player_block.get("current_tool", 0),
        "materials": miner_block.get("materials", {}),
        "gold_currency": miner_block.get("gold_currency", 0),
        "has_boat": miner_block.get("has_boat", false),
        "contract_level": contracts_block.get("level", 0),
        "contract_xp": contracts_block.get("xp", 0),
        "claim_level": claims_block.get("level", 0),
        "claim_xp": claims_block.get("xp", 0),
    }
    var world := {
        "map": blob.get("map", {"explored": "", "explored_cell_count": 0}),
        "claims": _claims_v1_to_v2(claims_block, local_steam_id),
        "contracts": {
            "available": contracts_block.get("available", []),
            "assignments": _contract_assignments_v1_to_v2(contracts_block, local_steam_id),
        },
        "vendors": {},
        "boats": _boats_v1_to_v2(miner_block, local_steam_id),
        "factory": blob.get("factory", {"buildings": [], "links": []}),
    }
    return {
        "version": 2,
        "world": world,
        "players": {local_steam_id: profile},
    }

static func _claims_v1_to_v2(claims_block: Dictionary, owner_id: String) -> Dictionary:
    # v1 had a single owned claim per player; v2 keys claims by id with owner_steam_id.
    var out := {}
    var owned_id: String = claims_block.get("owned_id", "")
    var owned_mined: Dictionary = claims_block.get("owned_mined", {})
    if owned_id != "":
        out[owned_id] = {
            "owner_steam_id": owner_id,
            "mined_per_player": {owner_id: owned_mined.get(owned_id, 0)},
        }
    return out

static func _contract_assignments_v1_to_v2(contracts_block: Dictionary, owner_id: String) -> Dictionary:
    var out := {}
    for c in contracts_block.get("active", []):
        var id: String = c.get("id", "") if c is Dictionary else ""
        if id != "":
            out[id] = owner_id
    return out

static func _boats_v1_to_v2(miner_block: Dictionary, owner_id: String) -> Array:
    if miner_block.get("has_boat", false):
        return [{"owner_steam_id": owner_id, "position": [0.0, 0.0, 0.0], "rotation": 0.0}]
    return []
```

- [ ] **Step 5: Run tests, confirm they pass**

Expected: 5 pass, 0 fail.

- [ ] **Step 6: Wire migration into `load_now()`**

In `save_game.gd`'s existing `load_now()` (or equivalent), after parsing JSON but before applying:
```gdscript
var local_id := Net.local_player_id() if has_node("/root/Net") else "local"
data = migrate_v1_to_v2(data, local_id)
```
(Use the autoload-safe access since `Net` may not exist yet at this exact load point — the `has_node` guard handles it.)

- [ ] **Step 7: Manual smoke test**

Create or use an existing v1 save by running single-player → quit. Then start the game with the new build. Expected: load succeeds, all single-player state preserved (gold, inventory, claim ownership, contracts).

- [ ] **Step 8: Commit**

```bash
git add scripts/save_game.gd tests/gut/test_save_migration_v1_to_v2.gd
git commit -m "feat(mp): migrate single-player save v1 to multiplayer-shape v2"
```

---

## Task 4: `Net` autoload skeleton (TDD where possible)

**Files:**
- Create: `res://scripts/net/net.gd`
- Create: `res://tests/gut/test_net_authority.gd`
- Modify: `res://project.godot` — register `Net` autoload

- [ ] **Step 1: Write failing tests for offline-default behavior**

Create `res://tests/gut/test_net_authority.gd`:
```gdscript
extends GutTest

const NetClass = preload("res://scripts/net/net.gd")

var _net: Node

func before_each():
    _net = NetClass.new()
    add_child_autofree(_net)

func test_offline_is_host_returns_true():
    # When no peer is set, the local instance is treated as the authority.
    assert_true(_net.is_host(), "Offline session should report local as host")

func test_offline_local_player_id_is_local_sentinel():
    assert_eq(_net.local_player_id(), "local")

func test_signal_definitions_exist():
    assert_true(_net.has_signal("peer_connected"))
    assert_true(_net.has_signal("peer_disconnected"))
    assert_true(_net.has_signal("session_ended"))
```

- [ ] **Step 2: Run tests, confirm they fail**

Expected: cannot preload `res://scripts/net/net.gd` (file missing).

- [ ] **Step 3: Create `Net` autoload**

Create `res://scripts/net/net.gd`:
```gdscript
extends Node

signal peer_connected(peer_id: int, steam_id: String)
signal peer_disconnected(peer_id: int)
signal session_ended(reason: String)

const LOCAL_SENTINEL: String = "local"

var _peer_to_steam: Dictionary = {}  # int -> String
var _is_online: bool = false

func is_host() -> bool:
    if not _is_online:
        return true
    return multiplayer.is_server()

func local_player_id() -> String:
    if not _is_online:
        return LOCAL_SENTINEL
    if Engine.has_singleton("Steam"):
        return str(Steam.getSteamID())
    return LOCAL_SENTINEL

func steam_id_for_peer(peer_id: int) -> String:
    return _peer_to_steam.get(peer_id, "")

# Stubs filled in by Tasks 5 + 6:
func host_session() -> Error:
    return ERR_UNAVAILABLE

func join_session(_lobby_id: int) -> Error:
    return ERR_UNAVAILABLE

func leave_session() -> void:
    pass
```

- [ ] **Step 4: Run tests, confirm they pass**

Expected: 3 pass.

- [ ] **Step 5: Register autoload in project.godot**

Add under `[autoload]`:
```
Net="*res://scripts/net/net.gd"
```
The `*` prefix makes it a singleton autoload available as `Net` from any script.

- [ ] **Step 6: Commit**

```bash
git add scripts/net/net.gd tests/gut/test_net_authority.gd project.godot
git commit -m "feat(mp): Net autoload skeleton with offline defaults"
```

---

## Task 5: Net session lifecycle — host & leave

**Files:**
- Modify: `res://scripts/net/net.gd`

- [ ] **Step 1: Read latest net.gd**

`mcp__godot-ai__script_manage(op="read", params={"path": "res://scripts/net/net.gd"})`.

- [ ] **Step 2: Implement `host_session()`**

Add to `net.gd`:
```gdscript
const LOBBY_TYPE_FRIENDS_ONLY := 1
const LOBBY_MAX_MEMBERS := 4

var _peer: SteamMultiplayerPeer = null
var _lobby_id: int = 0

func host_session() -> Error:
    if _is_online:
        return ERR_ALREADY_IN_USE
    if not _ensure_steam_initialized():
        return ERR_UNAVAILABLE
    _peer = SteamMultiplayerPeer.new()
    var err := _peer.create_lobby(LOBBY_TYPE_FRIENDS_ONLY, LOBBY_MAX_MEMBERS)
    if err != OK:
        push_error("Net: create_lobby failed: %s" % err)
        return err
    multiplayer.multiplayer_peer = _peer
    _is_online = true
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    Steam.lobby_created.connect(_on_lobby_created, CONNECT_ONE_SHOT)
    return OK

func leave_session() -> void:
    if not _is_online:
        return
    if _peer:
        _peer.close()
        _peer = null
    multiplayer.multiplayer_peer = null
    _peer_to_steam.clear()
    _is_online = false
    _lobby_id = 0
    if multiplayer.peer_connected.is_connected(_on_peer_connected):
        multiplayer.peer_connected.disconnect(_on_peer_connected)
    if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
        multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
    session_ended.emit("user_left")

func _on_peer_connected(peer_id: int) -> void:
    var steam_id := str(_peer.get_steam_id_from_peer_id(peer_id)) if _peer else ""
    _peer_to_steam[peer_id] = steam_id
    peer_connected.emit(peer_id, steam_id)

func _on_peer_disconnected(peer_id: int) -> void:
    _peer_to_steam.erase(peer_id)
    peer_disconnected.emit(peer_id)

func _on_lobby_created(connect_status: int, lobby_id: int) -> void:
    if connect_status == 1:
        _lobby_id = lobby_id
        Steam.setLobbyData(lobby_id, "name", "Mine Co. session")

func _ensure_steam_initialized() -> bool:
    if not Engine.has_singleton("Steam"):
        push_error("Net: Steam singleton missing — is GodotSteam loaded?")
        return false
    var status: Dictionary = Steam.steamInit()
    if status.get("status", 0) != 1:
        push_error("Net: steamInit failed: %s" % status)
        return false
    return true
```

> Note: the exact `SteamMultiplayerPeer` API names may differ slightly between GodotSteam versions. After writing this, cross-check with the version actually installed in Task 1 — if a method name differs, update accordingly. Do **not** redesign the surface; just rename calls.

- [ ] **Step 3: Manual smoke test (host only)**

Add a temporary print line at the bottom of `_ready()` of `net.gd`:
```gdscript
func _ready():
    print("Net autoload ready, online=", _is_online)
```
Run main.tscn. Expected: print appears once at startup, no errors.

Then run a tiny test scene that calls `Net.host_session()` and prints the result. Expected: returns `OK`, lobby gets created, no crash. Steam overlay (Shift+Tab) shows you're in a "Mine Co. session" lobby with 1/4 members.

Remove temp prints after.

- [ ] **Step 4: Commit**

```bash
git add scripts/net/net.gd
git commit -m "feat(mp): Net.host_session and leave_session via SteamMultiplayerPeer"
```

---

## Task 6: Net session lifecycle — join & friend-invite acceptance

**Files:**
- Modify: `res://scripts/net/net.gd`

- [ ] **Step 1: Read latest net.gd**

`mcp__godot-ai__script_manage(op="read", ...)`.

- [ ] **Step 2: Implement `join_session()` and the join-via-invite hook**

Add to `net.gd`:
```gdscript
func join_session(lobby_id: int) -> Error:
    if _is_online:
        return ERR_ALREADY_IN_USE
    if not _ensure_steam_initialized():
        return ERR_UNAVAILABLE
    Steam.joinLobby(lobby_id)
    Steam.lobby_joined.connect(_on_lobby_joined, CONNECT_ONE_SHOT)
    return OK

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
    if response != 1:
        push_error("Net: lobby join failed: %s" % response)
        session_ended.emit("join_failed")
        return
    _peer = SteamMultiplayerPeer.new()
    var host_steam_id: int = Steam.getLobbyOwner(lobby_id)
    var err := _peer.connect_lobby(lobby_id)
    if err != OK:
        push_error("Net: connect_lobby failed: %s" % err)
        session_ended.emit("join_failed")
        return
    multiplayer.multiplayer_peer = _peer
    _is_online = true
    _lobby_id = lobby_id
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)
    multiplayer.server_disconnected.connect(_on_server_disconnected, CONNECT_ONE_SHOT)

func _on_connected_to_server() -> void:
    pass  # snapshot apply happens in Task 13

func _on_server_disconnected() -> void:
    leave_session()
    session_ended.emit("host_disconnected")
```

Then connect the Steam friends-invite intake. Declare the signal at the top of the file with the other signals, and add the handlers:
```gdscript
signal invite_received(lobby_id: int)

# Add inside _ready() (alongside the existing Net signal wiring):
func _ready():
    Steam.lobby_invite.connect(_on_lobby_invite)
    Steam.join_requested.connect(_on_join_requested)

func _on_lobby_invite(_inviter: int, lobby_id: int, _game_id: int) -> void:
    # Always emit. UI listens (added in Task 12). If no listener has connected yet,
    # the signal is a no-op — auto-joining without UI confirmation could be hostile.
    invite_received.emit(lobby_id)

func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
    # Triggered when a friend right-clicks → "Join Game" in the Steam friends list.
    # This is an explicit user action so we join immediately.
    join_session(lobby_id)
```

- [ ] **Step 3: Manual smoke test (host + 1 friend)**

Run the host on machine A. Run the join client on machine B (or two Godot editor instances if Steam allows multi-login — usually requires separate accounts).
1. Host calls `Net.host_session()` → confirm OK.
2. Host invites friend via Steam friends list.
3. Friend right-clicks → Join Game.
4. Expected: friend's `Net._on_lobby_joined` fires, `_is_online` becomes true, host's `peer_connected` signal fires with the friend's steam id.

If solo testing without a second account: skip and verify in Task 14's playtest.

- [ ] **Step 4: Commit**

```bash
git add scripts/net/net.gd
git commit -m "feat(mp): Net.join_session via Steam invite and join_requested"
```

---

## Task 7: `NetUtils` RPC helpers

**Files:**
- Create: `res://scripts/net/net_utils.gd`

- [ ] **Step 1: Implement helpers**

Create `res://scripts/net/net_utils.gd`:
```gdscript
class_name NetUtils
extends RefCounted

# === RPC argument convention ===
# All RPC methods in Mine Co. multiplayer take a single `args: Array` parameter
# and unpack inside. This keeps the helper API uniform — every call site looks
# like `NetUtils.request_to_host(self, "_my_rpc", [arg1, arg2, arg3])`.
# Trade-off: less type-checking at call sites; gain: one helper signature
# covers every game-state RPC without per-method overloads or metaprogramming.
# The receiver always declares the RPC method as:
#     @rpc("any_peer", "call_local", "reliable")
#     func _my_rpc(args: Array) -> void:
#         var x = args[0]; var y = args[1]
#         ...
# When you call the local-host branch we use `target.callv(method_name, [args])`
# — note the wrapping array: `callv` expects an Array of positional arguments,
# and our single positional argument *is itself an Array*.

# Wraps the canonical request → host pattern. The receiver script owns the
# `@rpc("any_peer", "call_local")` annotation on `method_name`.
static func request_to_host(target: Node, method_name: String, args: Array) -> void:
    if not Net.is_host():
        target.rpc_id(1, method_name, args)
    else:
        target.callv(method_name, [args])

static func broadcast(target: Node, method_name: String, args: Array) -> void:
    if Net.is_host():
        target.rpc(method_name, args)
        target.callv(method_name, [args])
    else:
        push_error("NetUtils.broadcast called from non-host")

static func tell_peer(target: Node, peer_id: int, method_name: String, args: Array) -> void:
    if Net.is_host():
        target.rpc_id(peer_id, method_name, args)
    else:
        push_error("NetUtils.tell_peer called from non-host")
```

> The `args: Array` convention keeps RPC signatures uniform — receivers unpack as needed. Trade-off: less type checking than per-method args; gain: one helper covers every call site without metaprogramming.

- [ ] **Step 2: Commit**

```bash
git add scripts/net/net_utils.gd
git commit -m "feat(mp): NetUtils request_to_host/broadcast/tell_peer helpers"
```

---

## Task 8: `RemotePlayer` scene

**Files:**
- Create: `res://scripts/remote_player.gd`
- Create: `res://scenes/remote_player.tscn`

- [ ] **Step 1: Read existing player.gd and player.tscn structure**

`mcp__godot-ai__script_manage(op="read", params={"path": "res://scripts/player.gd"})`
`mcp__godot-ai__filesystem_manage(op="read_text", params={"path": "res://scenes/player.tscn"})`

Note the mesh node, animation tree path, and which inputs `player.gd` reads.

- [ ] **Step 2: Create remote_player.tscn**

Build a scene with:
- Root: `CharacterBody3D` (named `RemotePlayer`)
- Child: same mesh / skeleton / animation tree as `player.tscn`
- Child: `Label3D` for name tag (above head, billboarded)
- Child: `MultiplayerSynchronizer` configured to replicate:
  - `position` (transform sync, ~20 Hz, unreliable)
  - `rotation:y` (transform sync, ~20 Hz, unreliable)
  - `current_tool` (state sync, on-change, reliable)
  - `animation_state` (state sync, on-change, reliable)
- No camera, no input handling, no collision shape that prevents the local player from walking through (visual-only collision OK).

Use the editor to lay this out, save as `res://scenes/remote_player.tscn`.

- [ ] **Step 3: Create remote_player.gd**

```gdscript
extends CharacterBody3D

@export var steam_id: String = ""
@export var display_name: String = ""

var current_tool: int = 0
var animation_state: String = "idle"

@onready var _name_label: Label3D = $NameTag
@onready var _anim_tree: AnimationTree = $AnimationTree

func _ready() -> void:
    set_physics_process(false)  # purely replicated; no local sim
    _refresh_name_label()

func _process(_delta: float) -> void:
    _apply_animation_state()

func set_display_name(name: String) -> void:
    display_name = name
    _refresh_name_label()

func _refresh_name_label() -> void:
    if _name_label:
        _name_label.text = display_name if display_name != "" else "Player"

func _apply_animation_state() -> void:
    if _anim_tree and _anim_tree.has_method("travel"):
        var sm: AnimationNodeStateMachinePlayback = _anim_tree.get("parameters/playback")
        if sm and sm.get_current_node() != animation_state:
            sm.travel(animation_state)
```

- [ ] **Step 4: Smoke test**

Open `remote_player.tscn`, instantiate it in main.tscn temporarily at a fixed offset from the player, set `display_name = "TestRemote"`. Run. Expected: visible mesh with name tag floating above. Remove the temporary instantiation.

- [ ] **Step 5: Commit**

```bash
git add scripts/remote_player.gd scenes/remote_player.tscn
git commit -m "feat(mp): RemotePlayer scene with synced transform and animation"
```

---

## Task 9: Player spawning via `MultiplayerSpawner`

**Files:**
- Modify: `res://scenes/main.tscn`
- Modify: `res://scripts/player.gd`
- Create new logic in: `res://scripts/net/net.gd` (spawn coordinator)

- [ ] **Step 1: Read player.gd and main.tscn**

Read both via MCP. Note where `Player` is currently instanced in `main.tscn` and the `player.gd` `_ready()` setup.

- [ ] **Step 2: Add `MultiplayerSpawner` to main.tscn**

In the editor, add a `MultiplayerSpawner` node under the world root. Configure:
- `spawn_path`: the world root (where players go).
- `_spawnable_scenes`: include `res://scenes/player.tscn` and `res://scenes/remote_player.tscn`.
- `spawn_function`: the autoload Net's `spawn_player_for_peer` (set in Step 3).

- [ ] **Step 3: Add spawn coordination to Net**

Add to `net.gd`:
```gdscript
@export var player_scene_local: PackedScene = preload("res://scenes/player.tscn")
@export var player_scene_remote: PackedScene = preload("res://scenes/remote_player.tscn")

# Called by MultiplayerSpawner.
func spawn_player_for_peer(data: Dictionary) -> Node:
    var peer_id: int = data.get("peer_id", 0)
    var steam_id: String = data.get("steam_id", "")
    var display_name: String = data.get("display_name", "Player")
    var scene := player_scene_local if peer_id == multiplayer.get_unique_id() else player_scene_remote
    var node := scene.instantiate()
    node.name = "Player_%d" % peer_id
    node.set_multiplayer_authority(peer_id)
    if node.has_method("set_display_name"):
        node.set_display_name(display_name)
    if "steam_id" in node:
        node.steam_id = steam_id
    return node
```

When a peer connects (host side), call:
```gdscript
func _on_peer_connected(peer_id: int) -> void:
    var steam_id := str(_peer.get_steam_id_from_peer_id(peer_id)) if _peer else ""
    _peer_to_steam[peer_id] = steam_id
    peer_connected.emit(peer_id, steam_id)
    if Net.is_host():
        _spawn_player(peer_id, steam_id, _display_name_for(steam_id))

func _spawn_player(peer_id: int, steam_id: String, display_name: String) -> void:
    var spawner: MultiplayerSpawner = get_tree().current_scene.get_node_or_null("PlayerSpawner")
    if spawner:
        spawner.spawn({"peer_id": peer_id, "steam_id": steam_id, "display_name": display_name})

func _display_name_for(steam_id: String) -> String:
    if Engine.has_singleton("Steam"):
        return Steam.getFriendPersonaName(int(steam_id)) if steam_id.is_valid_int() else "Player"
    return "Player"
```

Also spawn the host's own player on `host_session()` success, and remove the static `Player` instance from `main.tscn` (replaced by spawner).

- [ ] **Step 4: Update player.gd**

Add at the top of `player.gd`:
```gdscript
@export var steam_id: String = ""

func _ready() -> void:
    # Existing _ready logic...
    if not is_multiplayer_authority():
        # Should not happen for the local Player scene, but guard anyway.
        set_process_input(false)
        set_physics_process(false)

func set_display_name(_n: String) -> void:
    pass  # local player doesn't show its own name tag
```

(Keep all existing logic; only add the authority guard at the top of `_ready` and the `set_display_name` shim.)

- [ ] **Step 5: Wire offline-mode self-spawn**

Net is an autoload, so its `_ready()` runs before the world scene exists. Don't try to access the spawner from `Net._ready()`. Instead, listen for the world scene becoming available:

```gdscript
func _ready():
    # ... existing Steam signal wiring ...
    get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
    # Spawn the local player once the PlayerSpawner appears in the active scene.
    if node.name == "PlayerSpawner" and not _has_spawned_offline:
        _has_spawned_offline = true
        if not _is_online:
            _spawn_player(1, LOCAL_SENTINEL, "Local")

var _has_spawned_offline: bool = false
```

Run main.tscn in single-player. Expected: Net offline, `_spawn_player` runs once when the spawner appears, the local Player is instantiated, no errors, player walks normally.

- [ ] **Step 6: Manual smoke test (host + guest)**

Start host on machine A. Join from machine B. Expected: both machines see two characters — local one with camera + input, remote one as a `RemotePlayer` with name tag.

- [ ] **Step 7: Commit**

```bash
git add scripts/net/net.gd scripts/player.gd scenes/main.tscn
git commit -m "feat(mp): MultiplayerSpawner-driven player spawning"
```

---

## Task 10: Shared mining via host-authoritative voxel changes

**Files:**
- Modify: `res://scripts/miner.gd`
- Modify: `res://scripts/island_voxel_generator.gd`

- [ ] **Step 1: Read miner.gd and island_voxel_generator.gd**

Read both via MCP. Note the existing mining hit signal/function (e.g., `_on_ore_hit(cell, tool)` or similar) and how the current single-player flow updates voxel state and grants materials.

- [ ] **Step 2: Convert client-side mining to a host request**

In `miner.gd`, find the function called when a player swings their tool against ore. Refactor it into:
```gdscript
# Local entry point — no longer mutates state directly.
func attempt_mine_hit(cell: Vector3i, tool: int) -> void:
    NetUtils.request_to_host(self, "_request_mine_hit_rpc", [cell, tool, Net.local_player_id()])

@rpc("any_peer", "call_local", "reliable")
func _request_mine_hit_rpc(args: Array) -> void:
    if not Net.is_host():
        return
    var cell: Vector3i = args[0]
    var tool: int = args[1]
    var requester_steam_id: String = args[2]
    var requester_peer_id: int = multiplayer.get_remote_sender_id()
    if requester_peer_id == 0:
        requester_peer_id = 1  # host self-call
    _apply_mine_hit_authoritative(cell, tool, requester_peer_id, requester_steam_id)

func _apply_mine_hit_authoritative(cell: Vector3i, tool: int, peer_id: int, steam_id: String) -> void:
    # Existing single-player logic moves here, but:
    # - voxel state changes go through IslandVoxelGenerator.apply_voxel_change_authoritative
    # - granted materials go via NetUtils.tell_peer(self, peer_id, "_gained_material_rpc", [kind, amount])
    var result := IslandVoxelGenerator.apply_voxel_change_authoritative(cell, tool)
    if result.depleted:
        NetUtils.broadcast(IslandVoxelGenerator, "_voxel_changed_rpc", [cell, result.new_state])
    if result.granted_kind != "":
        NetUtils.tell_peer(self, peer_id, "_gained_material_rpc", [steam_id, result.granted_kind, result.granted_amount])
```

- [ ] **Step 3: Add the `_gained_material_rpc` and update per-player materials map**

Refactor `miner.gd`'s materials state to be per-steam-id on the host, and only the local entry on each client:
```gdscript
var _materials_by_steam: Dictionary = {}  # steam_id -> Dictionary[kind -> int]

@rpc("authority", "call_local", "reliable")
func _gained_material_rpc(args: Array) -> void:
    var steam_id: String = args[0]
    var kind: String = args[1]
    var amount: int = args[2]
    var bag: Dictionary = _materials_by_steam.get(steam_id, {})
    bag[kind] = bag.get(kind, 0) + amount
    _materials_by_steam[steam_id] = bag
    if steam_id == Net.local_player_id():
        emit_signal("local_inventory_changed", bag)
```

Update existing single-player calls to read from `_materials_by_steam[Net.local_player_id()]` instead of a flat dictionary.

- [ ] **Step 4: Add `apply_voxel_change_authoritative` and `_voxel_changed_rpc` in island_voxel_generator.gd**

```gdscript
class_name IslandVoxelGenerator
# ...

func apply_voxel_change_authoritative(cell: Vector3i, tool: int) -> Dictionary:
    # Existing single-player damage/depletion logic returns:
    # {"depleted": bool, "new_state": int, "granted_kind": String, "granted_amount": int}
    return _apply_damage_internal(cell, tool)

@rpc("authority", "call_local", "reliable")
func _voxel_changed_rpc(args: Array) -> void:
    var cell: Vector3i = args[0]
    var new_state: int = args[1]
    _set_voxel_state_visual_only(cell, new_state)
```

The "visual only" path on clients must update the mesh + particle/SFX, but **not** re-run damage logic.

- [ ] **Step 5: Write a unit test for the voxel diff round-trip**

Create `res://tests/gut/test_voxel_diff_apply.gd`:
```gdscript
extends GutTest

func test_apply_visual_only_updates_state_dict():
    var gen = IslandVoxelGenerator.new()
    add_child_autofree(gen)
    gen._set_voxel_state_visual_only(Vector3i(1, 0, 1), 7)
    assert_eq(gen.get_voxel_state(Vector3i(1, 0, 1)), 7)

func test_apply_damage_authoritative_returns_result_shape():
    var gen = IslandVoxelGenerator.new()
    add_child_autofree(gen)
    gen.seed_ore_at(Vector3i(0, 0, 0), "iron", 3)
    var result = gen.apply_voxel_change_authoritative(Vector3i(0, 0, 0), 1)
    assert_has(result, "depleted")
    assert_has(result, "new_state")
    assert_has(result, "granted_kind")
    assert_has(result, "granted_amount")
```

(Adjust to match actual `IslandVoxelGenerator` API after reading the file.)

- [ ] **Step 6: Run all tests**

Expected: all pass.

- [ ] **Step 7: Manual smoke test, single-player**

Run main.tscn. Mine some ore. Expected: identical experience to before — no errors, materials counts go up, voxel depletes.

- [ ] **Step 8: Manual smoke test, host + guest**

Both players mine the same ore patch. Expected:
- Voxel depletion is consistent on both screens.
- Whichever player landed the killing hit gets the material; the other does not.
- Killing-hit attribution: host validates `multiplayer.get_remote_sender_id()` matches the requester.

- [ ] **Step 9: Commit**

```bash
git add scripts/miner.gd scripts/island_voxel_generator.gd tests/gut/test_voxel_diff_apply.gd
git commit -m "feat(mp): host-authoritative shared mining with per-player materials"
```

---

## Task 11: Map exploration diff replication

**Files:**
- Modify: `res://scripts/map_data.gd`

- [ ] **Step 1: Read map_data.gd**

`mcp__godot-ai__script_manage(op="read", params={"path": "res://scripts/map_data.gd"})`. Note current explored-cell representation (PackedByteArray or image) and how cells are revealed.

- [ ] **Step 2: Add periodic local-diff collection**

Add to `map_data.gd`:
```gdscript
var _local_explored_dirty: PackedInt32Array = PackedInt32Array()  # cell indices revealed this tick
var _diff_send_timer: float = 0.0
const DIFF_INTERVAL: float = 2.0  # seconds

func _process(delta: float) -> void:
    _diff_send_timer += delta
    if _diff_send_timer >= DIFF_INTERVAL:
        _diff_send_timer = 0.0
        _flush_local_diff()

func _flush_local_diff() -> void:
    if _local_explored_dirty.is_empty():
        return
    var diff = _local_explored_dirty
    _local_explored_dirty = PackedInt32Array()
    NetUtils.request_to_host(self, "_apply_explored_diff_rpc", [diff])

# Existing reveal call adds to _local_explored_dirty when a *new* cell is revealed.
func reveal_cell(idx: int) -> void:
    if _is_already_revealed(idx):
        return
    _set_revealed_locally(idx)
    _local_explored_dirty.append(idx)
```

- [ ] **Step 3: Host-side merge + broadcast**

```gdscript
@rpc("any_peer", "call_local", "reliable")
func _apply_explored_diff_rpc(args: Array) -> void:
    if not Net.is_host():
        return
    var diff: PackedInt32Array = args[0]
    for idx in diff:
        _set_revealed_world(idx)  # writes the world's shared mask
    NetUtils.broadcast(self, "_world_explored_diff_rpc", [diff])

@rpc("authority", "call_local", "reliable")
func _world_explored_diff_rpc(args: Array) -> void:
    var diff: PackedInt32Array = args[0]
    for idx in diff:
        _set_revealed_locally(idx)
```

- [ ] **Step 4: Manual smoke test, host + guest**

Two players walk in opposite directions. Expected:
- Within ~2 seconds, each player's minimap reveals the other's explored cells.
- Single-player still works (the diff RPC is a no-op when host self-calls and Net is offline).

- [ ] **Step 5: Commit**

```bash
git add scripts/map_data.gd
git commit -m "feat(mp): shared map exploration via periodic diff RPC"
```

---

## Task 12: Multiplayer menu UI

**Files:**
- Create: `res://scenes/ui/multiplayer_menu.tscn` + `multiplayer_menu.gd`
- Modify: existing pause menu / main menu (add a "Multiplayer" entry)

- [ ] **Step 1: Identify existing menu**

Read `res://scenes/main.tscn` and any pause-menu scene to find where to insert the entry.

- [ ] **Step 2: Build multiplayer_menu.tscn**

Layout:
- Title: "Multiplayer"
- Button: "Host session"
- Button: "Leave session" (visible only when online)
- Label: "Invite friends via Steam Shift+Tab → Friends → Invite to Game"
- Container: live player roster (one row per peer; name + ping)
- Button: "Back"

- [ ] **Step 3: Write multiplayer_menu.gd**

```gdscript
extends Control

@onready var _host_btn: Button = $VBox/HostBtn
@onready var _leave_btn: Button = $VBox/LeaveBtn
@onready var _roster: VBoxContainer = $VBox/Roster

func _ready() -> void:
    _host_btn.pressed.connect(_on_host_pressed)
    _leave_btn.pressed.connect(_on_leave_pressed)
    Net.peer_connected.connect(_refresh_roster)
    Net.peer_disconnected.connect(_refresh_roster)
    Net.session_ended.connect(_on_session_ended)
    _refresh_buttons()
    _refresh_roster()

func _on_host_pressed() -> void:
    var err := Net.host_session()
    if err != OK:
        push_error("Host failed: %s" % err)
    _refresh_buttons()

func _on_leave_pressed() -> void:
    Net.leave_session()
    _refresh_buttons()

func _on_session_ended(_reason: String) -> void:
    _refresh_buttons()
    _refresh_roster()

func _refresh_buttons() -> void:
    var online := Net.is_online()  # add this getter to Net
    _host_btn.visible = not online
    _leave_btn.visible = online

func _refresh_roster(_a := 0, _b := "") -> void:
    for child in _roster.get_children():
        child.queue_free()
    var label := Label.new()
    label.text = "%s (you)" % Net.local_player_id()
    _roster.add_child(label)
    for peer_id in Net._peer_to_steam.keys():
        var row := Label.new()
        var ping := multiplayer.get_peer(peer_id).get_average_ping_ms() if multiplayer.has_method("get_peer") else 0
        row.text = "%s — ping %dms" % [Net._peer_to_steam[peer_id], ping]
        _roster.add_child(row)
```

Add a public getter `Net.is_online()` returning `_is_online`.

- [ ] **Step 4: Wire from existing menu**

Add a "Multiplayer" button to the existing pause/main menu that opens `multiplayer_menu.tscn`.

- [ ] **Step 5: Manual smoke test**

Open menu → Host → confirm UI updates to show "Leave session". Have a friend join → roster shows them. Click Leave → state cleans up.

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/multiplayer_menu.tscn scripts/ui/multiplayer_menu.gd scripts/net/net.gd
git commit -m "feat(mp): multiplayer menu with host/leave and live roster"
```

---

## Task 13: Late-join world snapshot

**Files:**
- Create: `res://scripts/net/snapshot.gd`
- Modify: `res://scripts/net/net.gd` — call snapshot on peer-connected

- [ ] **Step 1: Implement snapshot.gd**

```gdscript
class_name NetSnapshot
extends RefCounted

# Builds a snapshot of all replicable Phase-1 world state to push to a joining peer.
static func build(world_root: Node) -> Dictionary:
    var snap := {
        "map_explored": _collect_map_explored(),
        "voxel_changes": _collect_voxel_diff_from_seed(),
        # Vendor / contract / claim / factory state intentionally omitted in Phase 1.
    }
    return snap

static func apply(world_root: Node, snap: Dictionary) -> void:
    if snap.has("map_explored"):
        MapData._apply_full_explored(snap["map_explored"])
    if snap.has("voxel_changes"):
        for change in snap["voxel_changes"]:
            IslandVoxelGenerator._set_voxel_state_visual_only(change.cell, change.state)

static func _collect_map_explored() -> PackedByteArray:
    return MapData.get_full_explored_bytes()

static func _collect_voxel_diff_from_seed() -> Array:
    return IslandVoxelGenerator.get_changed_from_seed()
```

You'll need to add the helpers `MapData.get_full_explored_bytes()`, `MapData._apply_full_explored(bytes)`, and `IslandVoxelGenerator.get_changed_from_seed()` if they don't exist. Each is a small accessor.

- [ ] **Step 2: Push snapshot from host on peer-connected**

In `Net._on_peer_connected`, after the existing logic:
```gdscript
if Net.is_host():
    _spawn_player(peer_id, steam_id, _display_name_for(steam_id))
    var snap := NetSnapshot.build(get_tree().current_scene)
    NetUtils.tell_peer(self, peer_id, "_receive_snapshot_rpc", [snap])

@rpc("authority", "call_local", "reliable")
func _receive_snapshot_rpc(args: Array) -> void:
    var snap: Dictionary = args[0]
    NetSnapshot.apply(get_tree().current_scene, snap)
```

- [ ] **Step 3: Add a "loading" overlay**

Show a simple "Joining session..." panel on the joining peer's screen between `_on_lobby_joined` success and `_receive_snapshot_rpc` apply. Hide once snapshot apply completes.

- [ ] **Step 4: Manual smoke test (host + late-joining guest)**

Host plays solo for 2 minutes — explores some terrain, mines several ore patches. Guest joins. Expected:
- Guest sees the same explored fog mask host has.
- Guest sees the same depleted ore patches.
- Loading overlay appears for ~1-2 seconds, then clears.

- [ ] **Step 5: Commit**

```bash
git add scripts/net/snapshot.gd scripts/net/net.gd
git commit -m "feat(mp): late-join world snapshot push"
```

---

## Task 14: Chat overlay

**Files:**
- Create: `res://scripts/net/chat.gd`
- Create: `res://scenes/ui/chat_overlay.tscn` + `.gd`
- Create: `res://tests/gut/test_chat_buffer.gd`
- Modify: `res://project.godot` — add input action `chat_open` (Enter)

- [ ] **Step 1: Add input action**

In project.godot's `[input]` section, add:
```
chat_open={
"deadzone": 0.5,
"events": [Object(InputEventKey,"keycode":4194309)]  # Enter
}
```

- [ ] **Step 2: Write failing test for chat buffer**

Create `res://tests/gut/test_chat_buffer.gd`:
```gdscript
extends GutTest

const ChatClass = preload("res://scripts/net/chat.gd")

var chat: Node

func before_each():
    chat = ChatClass.new()
    add_child_autofree(chat)

func test_buffer_keeps_last_six_messages():
    for i in range(10):
        chat._append_local("user", "msg_%d" % i)
    var lines := chat.get_recent_lines()
    assert_eq(lines.size(), 6)
    assert_eq(lines[0]["text"], "msg_4")
    assert_eq(lines[5]["text"], "msg_9")

func test_messages_have_timestamp_and_author():
    chat._append_local("Alice", "hello")
    var line = chat.get_recent_lines()[0]
    assert_eq(line["author"], "Alice")
    assert_eq(line["text"], "hello")
    assert_true(line.has("ts"))
```

- [ ] **Step 3: Run test, confirm it fails**

Expected: cannot preload chat.gd.

- [ ] **Step 4: Implement chat.gd**

```gdscript
extends Node

const MAX_LINES: int = 6
var _buffer: Array = []
signal new_message(line: Dictionary)

func send(text: String) -> void:
    if text.strip_edges() == "":
        return
    NetUtils.request_to_host(self, "_request_chat_rpc", [Net.local_player_id(), text])

@rpc("any_peer", "call_local", "reliable")
func _request_chat_rpc(args: Array) -> void:
    if not Net.is_host():
        return
    var author: String = args[0]
    var text: String = args[1]
    NetUtils.broadcast(self, "_broadcast_chat_rpc", [author, text, Time.get_unix_time_from_system()])

@rpc("authority", "call_local", "reliable")
func _broadcast_chat_rpc(args: Array) -> void:
    var author: String = args[0]
    var text: String = args[1]
    var ts: int = args[2]
    _append_local(author, text, ts)

func _append_local(author: String, text: String, ts: int = 0) -> void:
    var line := {"author": author, "text": text, "ts": ts}
    _buffer.append(line)
    while _buffer.size() > MAX_LINES:
        _buffer.pop_front()
    new_message.emit(line)

func get_recent_lines() -> Array:
    return _buffer.duplicate()
```

- [ ] **Step 5: Run tests, confirm they pass**

- [ ] **Step 6: Build chat_overlay.tscn**

A small CanvasLayer at bottom-left:
- VBoxContainer with 6 Labels for history
- LineEdit for input (hidden by default)
- Pressing `chat_open` shows the LineEdit + grabs focus
- Submitting calls `Chat.send(text)`; Escape cancels

Register `Chat` autoload pointing at `chat.gd`.

- [ ] **Step 7: Manual smoke test, host + guest**

Both players type messages. Expected: each sees both players' messages within 6-line buffer, name labels correct.

- [ ] **Step 8: Commit**

```bash
git add scripts/net/chat.gd scenes/ui/chat_overlay.tscn scripts/ui/chat_overlay.gd tests/gut/test_chat_buffer.gd project.godot
git commit -m "feat(mp): text chat with bounded history buffer"
```

---

## Task 15: Lock host-only systems for guests

**Files:**
- Modify: `res://scripts/vendor_ui.gd`
- Modify: `res://scripts/contract_board.gd`
- Modify: `res://scripts/claim_vendor_board.gd`
- Modify: `res://scripts/factory/build_controller.gd` (build mode entry point)
- Optional: shared "host_only_overlay" component

- [ ] **Step 1: Create a shared lockout helper**

Create `res://scripts/net/host_only_guard.gd`:
```gdscript
class_name HostOnlyGuard
extends RefCounted

# Returns true if the current peer should be blocked from interacting.
# Shows a tooltip if so.
static func block_if_guest(ui_root: Control, feature_name: String) -> bool:
    if Net.is_host():
        return false
    _show_toast(ui_root, "%s is host-only in Phase 1" % feature_name)
    return true

static func _show_toast(ui_root: Control, msg: String) -> void:
    var label := Label.new()
    label.text = msg
    label.position = Vector2(20, 20)
    ui_root.add_child(label)
    var tween := ui_root.create_tween()
    tween.tween_interval(2.0)
    tween.tween_callback(label.queue_free)
```

- [ ] **Step 2: Read each affected script and find the entry point**

For each of `vendor_ui.gd`, `contract_board.gd`, `claim_vendor_board.gd`, `build_controller.gd`, read via MCP and find the function called when the player opens or interacts (e.g., `_on_interact()`, `open_ui()`, `enter_build_mode()`).

- [ ] **Step 3: Insert guard at the top of each entry**

In each entry function, add at the very top:
```gdscript
if HostOnlyGuard.block_if_guest(self, "Vendor"):  # change name per system
    return
```

- [ ] **Step 4: Manual smoke test, host + guest**

Guest tries to open vendor → toast appears, UI does not open. Guest tries to use contract board → toast appears. Same for claim board, build mode.

Host can still use everything normally.

- [ ] **Step 5: Commit**

```bash
git add scripts/net/host_only_guard.gd scripts/vendor_ui.gd scripts/contract_board.gd scripts/claim_vendor_board.gd scripts/factory/build_controller.gd
git commit -m "feat(mp): lock vendor/contracts/claims/build for guests in Phase 1"
```

---

## Task 16: `MULTIPLAYER.md` repo doc

**Files:**
- Create: `MULTIPLAYER.md`

- [ ] **Step 1: Write the doc**

```markdown
# Mine Co. Multiplayer

**Current phase:** Phase 1 — MVP Co-op

**Working features in MP:**
- Steam friend invite to host's session (2-4 players)
- Replicated player movement, animation, name tags
- Shared mining (anyone can mine the same ore; killing hit gets the drop)
- Per-player inventory + gold (gold not yet usable in MP)
- Shared map exploration (helping the team see the world)
- Text chat (Enter)

**Host-only in Phase 1 (locked for guests):**
- Vendors
- Contract board
- Claim vendor board
- Boat purchase
- Build mode / factory placement

These will unlock for guests in Phase 2 (vendors/contracts/claims/boats) and Phase 3 (factories).

**Development:**
- Steam app id is 480 (Spacewar). Replace with the project's id at launch.
- GodotSteam plugin lives at `addons/godotsteam/`.
- See `docs/superpowers/specs/2026-05-08-multiplayer-design.md` for the full design.
```

- [ ] **Step 2: Commit**

```bash
git add MULTIPLAYER.md
git commit -m "docs(mp): MULTIPLAYER.md tracking active phase"
```

---

## Task 17: Single-player parity verification

**Files:** none (verification)

- [ ] **Step 1: Run main.tscn solo**

Launch via `mcp__godot-ai__project_run` with no Steam lobby. Play for ~5 minutes covering:
- Mining several ore types
- Selling at vendor
- Claiming a contract and turning in
- Buying a claim
- Riding the boat
- Placing a factory building
- Saving + reloading

Expected: all behave identically to pre-Phase-1 single-player.

- [ ] **Step 2: Verify v1 → v2 save migration with a real save**

If you have a single-player save from before Phase 1, copy it to `user://savegame.json` and load. Expected: clean load, all state preserved.

- [ ] **Step 3: Run all GUT tests**

Open GUT, run all. Expected: all pass.

- [ ] **Step 4: Commit if any incidental fixes were needed**

If any solo regression was found and fixed, commit it as `fix(mp): preserve single-player ... behavior`. If none, no commit needed.

---

## Task 18: Phase 1 acceptance playtest

**Files:** none (testing)

- [ ] **Step 1: Run a 2-human playtest**

With one teammate on a separate machine, hit each spec acceptance criterion:
- Host launches, invites friend via Steam overlay; friend joins within ~5s. ✅
- Both players see each other move smoothly with no visible warping under typical home internet. ✅
- Both can swing tools and mine the same ore patch — patch depletes consistently for both. ✅
- Each player keeps their own ore counts. ✅
- If host quits, guest is cleanly disconnected with "Session ended". ✅
- If guest quits, host continues; on reconnect inventory is restored. ✅
- Single-player still works — solo player sees no behavior change. ✅

- [ ] **Step 2: Document any deferred fixes**

If any criterion fails, add a Task 19 entry above and address it. Otherwise:

- [ ] **Step 3: Tag the release**

```bash
git tag mp-phase-1-complete
git push --tags
```

- [ ] **Step 4: Update MULTIPLAYER.md**

Mark Phase 1 as "✅ Shipped on YYYY-MM-DD" and add a "What's next" pointer to Phase 2's plan.

- [ ] **Step 5: Commit**

```bash
git add MULTIPLAYER.md
git commit -m "docs(mp): mark Phase 1 shipped"
```

---

## Phase 1 Done When

- [ ] All 18 tasks above are checked off
- [ ] All GUT unit tests pass
- [ ] 2-human playtest hits every spec acceptance criterion
- [ ] Single-player parity verified
- [ ] Save migration v1 → v2 verified with a real save file
- [ ] `mp-phase-1-complete` tag pushed
- [ ] `MULTIPLAYER.md` reflects completion
