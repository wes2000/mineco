extends GutTest
## Tests for SaveGame.migrate_v1_to_v2 — the v1 (flat single-player) to v2
## (world + per-player partitioned) save migration introduced in
## multiplayer Phase 1. Migration is a pure function so we exercise it with
## hand-built dictionaries and assert structure/equality directly.

const SaveGame := preload("res://scripts/save_game.gd")

# --- Fixtures ---------------------------------------------------------------

func _make_full_v1_blob() -> Dictionary:
	# Representative v1 blob — every top-level key collect_state() emits at
	# SAVE_VERSION=1, populated with sample data so we can assert that each
	# block lands intact in its v2 partition.
	return {
		"version": 1,
		"player": {
			"position": [12.5, 4.0, -3.25],
			"rotation_y": 1.57,
			"current_tool": "pickaxe",
		},
		"miner": {
			"materials": {"copper": 4, "iron": 2},
			"gold_currency": 1234,
			"has_boat": true,
			"carves": [],
		},
		"contracts": {
			"level": 3,
			"xp": 87,
			"available": [{"id": "c_1"}, {"id": "c_2"}],
			"active": [{"id": "c_1", "progress": 0.5}],
		},
		"claims": {
			"level": 2,
			"xp": 42,
			"owned_id": "claim_north",
			"owned_mined": 17,
		},
		"map": {
			"explored": [[0, 0], [1, 0], [0, 1]],
			"explored_cell_count": 3,
		},
		"factory": {
			"buildings": [{"id": "smelter_1", "pos": [10, 0, 10]}],
			"links": [{"from": "smelter_1", "to": "chest_1"}],
		},
		"build_controller": {
			"quickbar": ["smelter", "chest", "", "", ""],
		},
		"stats": {
			"perks": {"toughness": 1},
			"sources": {"rank_2": {"max_health": 5}},
		},
		"passive_tree": {
			"ranks": {"haste": 1, "vigor": 2},
		},
		"unlocks": {
			"blueprints": ["smelter", "assembler"],
		},
		"company": {
			"rank": 2,
			"lifetime_gold": 9001,
			"_gold_baseline_set": true,
		},
		"ore_deposits": {
			"dep_a": {"stage": 1, "hp": 80},
			"dep_b": {"stage": 0, "hp": 100},
		},
		"island_encounters": {
			"island_1": {"cleared": true, "kills": 5, "reward_claimed": true},
		},
	}


# --- Full v1 -> v2 partitioning -------------------------------------------

func test_full_v1_blob_migrates_to_v2_with_correct_partitioning() -> void:
	var v1: Dictionary = _make_full_v1_blob()
	var migrated: Dictionary = SaveGame.migrate_v1_to_v2(v1, "local")

	assert_eq(int(migrated["version"]), 2, "version bumped to 2")
	assert_true(migrated.has("world"), "v2 has world block")
	assert_true(migrated.has("players"), "v2 has players block")

	var world: Dictionary = migrated["world"]
	assert_eq(world["map"], v1["map"], "world.map equals v1.map")
	assert_eq(world["factory"], v1["factory"], "world.factory equals v1.factory")
	assert_eq(world["ore_deposits"], v1["ore_deposits"], "world.ore_deposits equals v1.ore_deposits")
	assert_eq(world["island_encounters"], v1["island_encounters"], "world.island_encounters equals v1.island_encounters")
	assert_eq(world["contracts"], v1["contracts"], "world.contracts equals v1.contracts (host-only in Phase 1)")
	assert_eq(world["claims"], v1["claims"], "world.claims equals v1.claims (host-only in Phase 1)")

	var players: Dictionary = migrated["players"]
	assert_true(players.has("local"), "players block keyed by local_steam_id parameter")
	var profile: Dictionary = players["local"]
	assert_eq(profile["player"], v1["player"], "profile.player equals v1.player")
	assert_eq(profile["miner"], v1["miner"], "profile.miner equals v1.miner")
	assert_eq(profile["build_controller"], v1["build_controller"], "profile.build_controller equals v1.build_controller")
	assert_eq(profile["stats"], v1["stats"], "profile.stats equals v1.stats")
	assert_eq(profile["passive_tree"], v1["passive_tree"], "profile.passive_tree equals v1.passive_tree")
	assert_eq(profile["unlocks"], v1["unlocks"], "profile.unlocks equals v1.unlocks")
	assert_eq(profile["company"], v1["company"], "profile.company equals v1.company")


# --- Idempotency ----------------------------------------------------------

func test_v2_blob_passes_through_unchanged() -> void:
	var v2: Dictionary = {
		"version": 2,
		"world": {
			"map": {"explored": []},
			"factory": {"buildings": []},
			"ore_deposits": {},
			"island_encounters": {},
			"contracts": {"level": 1},
			"claims": {"level": 1},
		},
		"players": {
			"76561198000000000": {
				"player": {"position": [0, 0, 0]},
				"miner": {"materials": {}},
				"build_controller": {"quickbar": []},
				"stats": {},
				"passive_tree": {},
				"unlocks": {},
				"company": {},
			},
		},
	}
	var result: Dictionary = SaveGame.migrate_v1_to_v2(v2, "local")
	assert_eq(result, v2, "v2 blob returned unchanged")


# --- Sparse v1 ------------------------------------------------------------

func test_sparse_v1_blob_migrates_with_defaults_for_missing_keys() -> void:
	# Only player + miner present — everything else must default to {} so
	# the apply path can safely call .has() on each block.
	var sparse: Dictionary = {
		"version": 1,
		"player": {"position": [1, 2, 3]},
		"miner": {"gold_currency": 5},
	}
	var migrated: Dictionary = SaveGame.migrate_v1_to_v2(sparse, "local")

	assert_eq(int(migrated["version"]), 2, "sparse v1 still bumped to 2")
	var world: Dictionary = migrated["world"]
	assert_eq(world["map"], {}, "missing map defaults to empty dict")
	assert_eq(world["factory"], {}, "missing factory defaults to empty dict")
	assert_eq(world["ore_deposits"], {}, "missing ore_deposits defaults to empty dict")
	assert_eq(world["island_encounters"], {}, "missing island_encounters defaults to empty dict")
	assert_eq(world["contracts"], {}, "missing contracts defaults to empty dict")
	assert_eq(world["claims"], {}, "missing claims defaults to empty dict")

	var profile: Dictionary = migrated["players"]["local"]
	assert_eq(profile["player"], {"position": [1, 2, 3]}, "player carried through")
	assert_eq(profile["miner"], {"gold_currency": 5}, "miner carried through")
	assert_eq(profile["build_controller"], {}, "missing build_controller defaults to empty dict")
	assert_eq(profile["stats"], {}, "missing stats defaults to empty dict")
	assert_eq(profile["passive_tree"], {}, "missing passive_tree defaults to empty dict")
	assert_eq(profile["unlocks"], {}, "missing unlocks defaults to empty dict")
	assert_eq(profile["company"], {}, "missing company defaults to empty dict")


# --- Steam ID parameter ---------------------------------------------------

func test_local_steam_id_parameter_keys_the_player_profile() -> void:
	var v1: Dictionary = _make_full_v1_blob()
	var migrated: Dictionary = SaveGame.migrate_v1_to_v2(v1, "99999")

	assert_true(migrated["players"].has("99999"), "profile keyed under provided steam id")
	assert_false(migrated["players"].has("local"), "default 'local' key NOT present when explicit id passed")
	var profile: Dictionary = migrated["players"]["99999"]
	assert_eq(profile["player"], v1["player"], "profile under custom key still has player block")
	assert_eq(profile["miner"], v1["miner"], "profile under custom key still has miner block")


func test_blob_with_missing_version_field_is_treated_as_v1() -> void:
	var no_version: Dictionary = {"player": {"position": [1.0, 2.0, 3.0]}, "miner": {"gold_currency": 42}}
	var migrated: Dictionary = SaveGame.migrate_v1_to_v2(no_version, "local")
	assert_eq(int(migrated["version"]), 2)
	assert_eq(migrated["players"]["local"]["player"], no_version["player"])
	assert_eq(migrated["players"]["local"]["miner"], no_version["miner"])
