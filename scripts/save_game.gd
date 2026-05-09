extends Node
## Autoload. Owns serialize/deserialize of the player-visible game state to
## user://savegame.json. Each subsystem implements get_save_data() /
## apply_save_data(data) and we just orchestrate. The save format carries a
## `version` int so we can migrate later — older or missing saves are
## ignored and the game starts fresh.

const SAVE_PATH: String = "user://savegame.json"
const SAVE_VERSION: int = 2
const AUTOSAVE_INTERVAL_SEC: float = 60.0

signal save_completed
signal load_completed
signal save_failed(reason: String)

var _autosave_timer: float = 0.0
var _quitting: bool = false

# --- Migration --------------------------------------------------------------

## v1 -> v2: partition the flat single-player save into world (shared) and
## players (per-steam-id profile) blocks. Phase 1 keeps contracts/claims under
## world because they remain host-only systems for guests; Phase 2 will split
## them into per-player active state vs. shared availability/ownership.
##
## Pure function — no scene access, safe to call from tests.
static func migrate_v1_to_v2(blob: Dictionary, local_steam_id: String) -> Dictionary:
	if int(blob.get("version", 1)) >= 2:
		return blob
	var world: Dictionary = {
		"map":               blob.get("map", {}),
		"factory":           blob.get("factory", {}),
		"ore_deposits":      blob.get("ore_deposits", {}),
		"island_encounters": blob.get("island_encounters", {}),
		"contracts":         blob.get("contracts", {}),
		"claims":            blob.get("claims", {}),
	}
	var profile: Dictionary = {
		"player":           blob.get("player", {}),
		"miner":            blob.get("miner", {}),
		"build_controller": blob.get("build_controller", {}),
		"stats":            blob.get("stats", {}),
		"passive_tree":     blob.get("passive_tree", {}),
		"unlocks":          blob.get("unlocks", {}),
		"company":          blob.get("company", {}),
	}
	return {
		"version": 2,
		"world": world,
		"players": {local_steam_id: profile},
	}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # autosave keeps ticking when paused
	get_tree().auto_accept_quit = false
	set_process(true)
	# Auto-load if there's a save. Deferred to give the main scene + town
	# spawner + vendor NPCs time to come up.
	call_deferred("_auto_load_when_ready")

func _process(delta: float) -> void:
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL_SEC:
		_autosave_timer = 0.0
		# Only autosave once the world is up and at least the player exists,
		# otherwise we save an empty/uninitialized state on top of a real one.
		if _scene_ready_for_save():
			save_now()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _quitting and _scene_ready_for_save():
			_quitting = true
			save_now()
		get_tree().quit()

# --- Public API -------------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if not has_save():
		return
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		dir.remove("savegame.json")

func save_now() -> bool:
	var data: Dictionary = collect_state()
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		var err: int = FileAccess.get_open_error()
		save_failed.emit("Could not open save file (error %d)" % err)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	save_completed.emit()
	_show_toast("Game saved")
	return true

func load_now() -> bool:
	if not has_save():
		return false
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("SaveGame.load_now: malformed save, ignoring")
		return false
	var data: Dictionary = parsed
	# Forward-migrate older saves so MP/SP saves of any vintage load cleanly.
	# `local_id` here is "local" — the offline sentinel used until Net
	# autoload lands in Task 4. Once Net exists, this picks up the real
	# steam id via /root/Net.local_player_id().
	var local_id: String = "local"
	if has_node("/root/Net"):
		local_id = $"/root/Net".local_player_id()
	if int(data.get("version", 0)) < 2:
		data = migrate_v1_to_v2(data, local_id)
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("SaveGame.load_now: version mismatch (file=%s expected=%d), ignoring" % [data.get("version"), SAVE_VERSION])
		return false
	apply_state(data)
	load_completed.emit()
	_show_toast("Game loaded")
	return true

# --- State collection / application ----------------------------------------

func collect_state() -> Dictionary:
	var data: Dictionary = {"version": SAVE_VERSION}
	# Player + miner
	var player: Node = _get_player()
	if player != null and player.has_method("get_save_data"):
		data["player"] = player.get_save_data()
	var miner: Node = _get_miner()
	if miner != null and miner.has_method("get_save_data"):
		data["miner"] = miner.get_save_data()
	# Vendor boards (per-NPC)
	var contract_npc: Node = get_tree().get_first_node_in_group("contract_vendor_npcs")
	if contract_npc != null:
		var cb: Node = contract_npc.get("contract_board") as Node
		if cb != null and cb.has_method("get_save_data"):
			data["contracts"] = cb.get_save_data()
	var claim_npc: Node = get_tree().get_first_node_in_group("claim_vendor_npcs")
	if claim_npc != null:
		var clb: Node = claim_npc.get("claim_board") as Node
		if clb != null and clb.has_method("get_save_data"):
			data["claims"] = clb.get_save_data()
	# Map exploration
	if MapData != null and MapData.has_method("get_save_data"):
		data["map"] = MapData.get_save_data()
	# Factory
	if FactoryWorld != null and FactoryWorld.has_method("get_save_data"):
		data["factory"] = FactoryWorld.get_save_data()
	# Build controller (quickbar bindings)
	if BuildController != null and BuildController.has_method("get_save_data"):
		data["build_controller"] = BuildController.get_save_data()
	# Progression stats (perks, equipment modifiers, etc).
	var ps: Node = get_node_or_null("/root/PlayerStats")
	if ps != null and ps.has_method("get_save_data"):
		data["stats"] = ps.get_save_data()
	# Passive tree perk ranks.
	var pt: Node = get_node_or_null("/root/PassiveTree")
	if pt != null and pt.has_method("get_save_data"):
		data["passive_tree"] = pt.get_save_data()
	# Blueprint unlocks (additive — older saves without this block load with
	# the unlock set empty, which is the default state for a fresh game).
	var unlocks: Node = get_node_or_null("/root/Unlocks")
	if unlocks != null and unlocks.has_method("get_save_data"):
		data["unlocks"] = unlocks.get_save_data()
	# Company rank + lifetime stats. Older saves without this block load with
	# rank 1 / zeroed counters which is the fresh-game default.
	var company: Node = get_node_or_null("/root/CompanyProgress")
	if company != null and company.has_method("get_save_data"):
		data["company"] = company.get_save_data()
	# Ore deposits (only the non-depleted ones; the absence of an id means
	# that deposit was fully mined out before save).
	var deposits: Dictionary = {}
	for n: Node in get_tree().get_nodes_in_group("ore_deposits"):
		if not (n is OreDeposit):
			continue
		var dep: OreDeposit = n
		if dep.deposit_id == "":
			continue
		deposits[dep.deposit_id] = dep.get_save_data()
	data["ore_deposits"] = deposits
	# Per-island enemy encounter state (cleared / kill counts / reward
	# claimed). Owned by the IslandEncounters node in main.tscn — older
	# saves without this block leave every island freshly populated.
	var island_enc: Node = get_tree().get_first_node_in_group("island_encounters")
	if island_enc != null and island_enc.has_method("get_save_data"):
		data["island_encounters"] = island_enc.get_save_data()
	return data

func apply_state(data: Dictionary) -> void:
	# If we got a v2 (world + players[steam_id]) blob, flatten it for the
	# existing apply path. Phase 2 will rewrite this function to read
	# directly from data["world"]/data["players"][local_steam_id] so guests
	# can apply just their own profile while host owns world state.
	if data.has("world") and data.has("players"):
		var flat: Dictionary = {}
		for k: Variant in data["world"]:
			flat[k] = data["world"][k]
		var pids: Array = data["players"].keys()
		if not pids.is_empty():
			var profile: Dictionary = data["players"][pids[0]]
			for k: Variant in profile:
				flat[k] = profile[k]
		flat["version"] = 2
		data = flat
	# Order: simple-state owners first, then factory (which adds nodes to the
	# scene), then position the player so spawn-gate logic doesn't fight us.
	# Tell CompanyProgress to flush its gold-delta baseline BEFORE the miner's
	# apply_save fires gold_currency_changed — otherwise the loaded balance
	# would be misread as fresh income. Full company-state restore happens
	# later (after PlayerStats reloads its modifier sources).
	var company_pre: Node = get_node_or_null("/root/CompanyProgress")
	if company_pre != null and company_pre.has_method("set"):
		company_pre.set("_gold_baseline_set", false)
	var miner: Node = _get_miner()
	if miner != null and data.has("miner") and miner.has_method("apply_save_data"):
		miner.apply_save_data(data["miner"])
	var contract_npc: Node = get_tree().get_first_node_in_group("contract_vendor_npcs")
	if contract_npc != null and data.has("contracts"):
		var cb: Node = contract_npc.get("contract_board") as Node
		if cb != null and cb.has_method("apply_save_data"):
			cb.apply_save_data(data["contracts"])
	var claim_npc: Node = get_tree().get_first_node_in_group("claim_vendor_npcs")
	if claim_npc != null and data.has("claims"):
		var clb: Node = claim_npc.get("claim_board") as Node
		if clb != null and clb.has_method("apply_save_data"):
			clb.apply_save_data(data["claims"])
	if MapData != null and data.has("map") and MapData.has_method("apply_save_data"):
		MapData.apply_save_data(data["map"])
	if FactoryWorld != null and data.has("factory") and FactoryWorld.has_method("apply_save_data"):
		FactoryWorld.apply_save_data(data["factory"])
	# Build controller — restore quickbar bindings (defaults if absent).
	if BuildController != null and data.has("build_controller") and BuildController.has_method("apply_save_data"):
		BuildController.apply_save_data(data["build_controller"])
	# Stats applied early so any system that re-reads them (Stamina recomputes
	# its effective max) sees the right values when their state restores.
	var ps: Node = get_node_or_null("/root/PlayerStats")
	if ps != null and data.has("stats") and ps.has_method("apply_save_data"):
		ps.apply_save_data(data["stats"])
	# Passive tree perk ranks. Older saves without this block leave the tree
	# at all-zero ranks, so existing saves keep working.
	var pt: Node = get_node_or_null("/root/PassiveTree")
	if pt != null and data.has("passive_tree") and pt.has_method("apply_save_data"):
		pt.apply_save_data(data["passive_tree"])
	# Blueprint unlocks. Absent block = empty unlock set; perfectly fine for
	# saves predating brief 08.
	var unlocks: Node = get_node_or_null("/root/Unlocks")
	if unlocks != null and data.has("unlocks") and unlocks.has_method("apply_save_data"):
		unlocks.apply_save_data(data["unlocks"])
	# Company rank + lifetime stats. apply re-stamps the rank-modifier sources
	# on PlayerStats internally so the bonuses come back without double-stack.
	# Runs after PlayerStats reloads its sources so the rank_N entries from
	# the save take precedence and our explicit re-stamp here is the
	# idempotent fallback for older saves that didn't carry them.
	var company: Node = get_node_or_null("/root/CompanyProgress")
	if company != null and data.has("company") and company.has_method("apply_save_data"):
		company.apply_save_data(data["company"])
	# Player position last — applying it before world_ready can be overwritten
	# by the SpawnGate. By the time we run apply_state we're past world_ready.
	var player: Node = _get_player()
	if player != null and data.has("player") and player.has_method("apply_save_data"):
		player.apply_save_data(data["player"])
	# Ore deposit state — restore stage/hp on existing deposits and free any
	# that were fully mined (their ids are absent from the saved dict).
	if data.has("ore_deposits"):
		_apply_ore_deposit_state(data["ore_deposits"])
	# Per-island enemy encounter state. Forwarded immediately even if the
	# encounters node hasn't spawned yet — it stashes the data until its
	# world_ready hook fires and uses it to skip cleared islands.
	if data.has("island_encounters"):
		var island_enc: Node = get_tree().get_first_node_in_group("island_encounters")
		if island_enc != null and island_enc.has_method("apply_save_data"):
			island_enc.call("apply_save_data", data["island_encounters"])
	# Replay terrain carves so the dug-out tunnels come back. Best-effort —
	# chunks must be loaded; the autosave/load will trigger the player's
	# nearby chunks first which covers the main case.
	var miner_for_carves: Node = _get_miner()
	if miner_for_carves != null and miner_for_carves.has_method("replay_carves"):
		miner_for_carves.call("replay_carves")

func _apply_ore_deposit_state(saved: Dictionary) -> void:
	for n: Node in get_tree().get_nodes_in_group("ore_deposits"):
		if not (n is OreDeposit):
			continue
		var dep: OreDeposit = n
		if dep.deposit_id == "":
			continue
		if saved.has(dep.deposit_id):
			dep.apply_save_data(saved[dep.deposit_id])
		else:
			# Not in save → was fully depleted before the save was written.
			dep.queue_free()

# --- Helpers ----------------------------------------------------------------

func _get_player() -> Node:
	return get_node_or_null("/root/Main/Player")

func _get_miner() -> Node:
	return get_tree().get_first_node_in_group("player_miner")

func _scene_ready_for_save() -> bool:
	# Don't try to save during the title-card seconds before Main is up.
	return get_tree().current_scene != null and _get_player() != null

func _auto_load_when_ready() -> void:
	if not has_save():
		return
	# Wait for the player to spawn (Main scene up + spawn gate finished).
	var deadline: float = 30.0
	var elapsed: float = 0.0
	while _get_player() == null and elapsed < deadline:
		await get_tree().create_timer(0.2).timeout
		elapsed += 0.2
	if _get_player() == null:
		push_warning("SaveGame: player never appeared, skipping auto-load")
		return
	# Wait for the town NPCs that own the vendor boards. Town spawner waits
	# 1.5s past world_ready then does its own async ground sampling — pad a
	# little. Save still loads without these (just skips contracts/claims)
	# once we time out, so the player isn't blocked indefinitely.
	deadline = 15.0
	elapsed = 0.0
	while elapsed < deadline:
		var have_contract: bool = get_tree().get_first_node_in_group("contract_vendor_npcs") != null
		var have_claim: bool = get_tree().get_first_node_in_group("claim_vendor_npcs") != null
		if have_contract and have_claim:
			break
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25
	load_now()
	# Reset the autosave clock so we don't immediately overwrite with whatever
	# the player does in the first second after restoring.
	_autosave_timer = 0.0

func _show_toast(text: String) -> void:
	var feed: Node = get_tree().get_first_node_in_group("pickup_feed")
	if feed != null and feed.has_method("add_text_message"):
		feed.add_text_message(text)
