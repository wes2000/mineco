# Mine Co. Multiplayer

**Current phase:** Phase 1 — MVP Co-op (in development on `feat/multiplayer-phase-1`)

## Working in Phase 1

- Steam friends-only lobbies via GodotSteam (4-player cap)
- Open the pause menu (Esc) → Game tab → **Multiplayer** section to host or leave a session, see the live roster, and read the invite hint
- Once hosting, friends invite via Steam overlay (Shift+Tab → Friends → right-click → Invite to Game)
- Replicated player movement + animation (each remote peer renders as a `RemotePlayer_<id>` instance)
- Shared mining: voxel carves and ore-deposit damage broadcast to peers so the world depletes consistently
- Shared map: the team's minimap fills in as anyone reveals new fog cells
- Late-join snapshot: a peer joining mid-session catches up on map fog, ore-deposit state, and host's voxel carves
- Text chat: Enter to type, last 6 messages render bottom-left

## Host-only in Phase 1 (locked for guests)

Guests will see a "*X* is host-only in Phase 1" toast on the pickup feed:

- Vendor UI
- Contract Board UI
- Claim Vendor UI
- Boat Vendor UI
- Item Shop UI
- Build mode

These unlock for guests in:

- **Phase 2** — Vendors, contracts, claims, boats
- **Phase 3** — Factories / build mode

## Steam app id

Currently uses Steam app id **480** (Spacewar — the public test app). Friends will see "Spacewar" in their Steam friends list while you're hosting; the actual lobby data carries `name = "Mine Co. session"`. Replace with the project's real app id at launch.

## Save format

Save format is at version 2 — bundled multiplayer shape with `world` (shared) and `players[steam_id]` (per-player) sections. Single-player saves migrate forward automatically. See `docs/superpowers/specs/2026-05-08-multiplayer-design.md` and `scripts/save_game.gd`'s `migrate_v1_to_v2` for details.

## Architecture references

- Spec: `docs/superpowers/specs/2026-05-08-multiplayer-design.md`
- Plans: `docs/superpowers/plans/2026-05-08-multiplayer-*.md`
- Net autoload: `scripts/net/net.gd`
- RPC helpers: `scripts/net/net_utils.gd`
- Late-join snapshot: `scripts/net/snapshot.gd`
- Chat autoload: `scripts/net/chat.gd`
- Host-only guard helper: `scripts/net/host_only_guard.gd`

## Known issues / Phase 1 trade-offs

- **Mining duping race**: shared mining uses state-broadcast (not host arbitration). If two peers hit the same chunk within network latency, both can score it. Acceptable for friend co-op; host arbitration is a Phase 2/3 follow-up if it surfaces in playtest.
- **GodotSteam API names**: `Steam.run_callbacks` is snake_case while most Matchmaking calls (`steamInit`, `joinLobby`, etc.) are camelCase. Verified against the installed binary's symbol table; `_NetSnapshot` and `_HostOnlyGuard` are accessed via `preload` constants in the autoloads to dodge Godot 4.6's class_name cache lag.
- **`addons/godotsteam_server/`** is gitignored — listen-server multiplayer uses only the client SDK. If you ever need the dedicated-server SDK (different game mode), re-install from the GodotSteam-Server releases.

## Design deviations from the original Phase 1 plan

These are intentional simplifications discovered during implementation; documenting them here so Phase 2 planning starts from accurate ground truth.

- **No `MultiplayerSynchronizer` on RemotePlayer / Player.** The plan called for spawner + synchronizer; the implementation uses spawner + explicit `Net.recv_remote_transform` RPC at 20 Hz instead. Reason: the static `/root/Main/Player` (kept to preserve SpawnGate, save_game, npc, town_spawner integrations) and the spawner-instantiated `RemotePlayer_<id>` aren't a mirror tree, which Synchronizer-based replication needs.
- **Transform RPC is unreliable for all four fields.** Spec said "unreliable for transform, reliable for tool changes." Implementation uses one unreliable RPC for `position` / `rotation.y` / `current_tool` / `animation_state`. Tool changes can be silently dropped, but the next 20 Hz tick corrects within ~50 ms — small visual glitch, not a correctness bug. Splitting into reliable + unreliable channels is a Phase 2 polish item if the glitch is visible.
- **Map diff RPC is direct broadcast (no host merge).** Plan had a host-merge step; implementation has each peer broadcast its newly-revealed cells directly to all others. Functionally equivalent for the no-anti-cheat world we're in; saves a hop.
- **NetUtils is preserved but currently unused.** All Phase-1 RPCs are simple broadcasts and route directly via `.rpc()` / `.rpc_id()`. NetUtils is for Phase 2's request → host validate → broadcast pattern (vendors, contracts, claims). See `scripts/net/net_utils.gd`'s docstring.
- **Multiplayer UI lives inside the existing pause menu Game tab**, not a standalone scene. Less infrastructure for a feature that's already 4 buttons + a roster.

## Repository size note

`addons/godotsteam/` vendors ~97 MB of platform binaries (Windows / Linux / macOS / Android, debug + release). This is in keeping with the project's pattern (`addons/zylann.voxel/` is similar, ~108 MB), but it does mean every clone pulls all platforms even though the project ships Windows-only currently. If repo size becomes a concern, options are: (a) trim non-Windows binaries on `main` and re-add at release time, (b) move the addon to Git LFS. Neither is urgent.
