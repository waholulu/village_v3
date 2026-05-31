extends GutTest

# Validates the difficulty presets:
# 1. The JSON files load and have the expected key values.
# 2. With the hard preset active, a wolf placed within threat radius causes
#    a wolf_threat to fire on night 1 (because starting_wood < campfire
#    consumption forces campfire_out_nights > 0 immediately).
# Together they prove the dormant wolf-threat / fence / watchtower paths
# are reachable under at least one shipped balance.

func test_hard_preset_loads_with_expected_values() -> void:
	var balance := BalanceData.new()
	assert_true(balance.load_from_file("res://data/balance_hard.json"),
		"balance_hard.json should load successfully")
	# Spot-check the key values for hard mode.
	assert_eq(balance.starting_wood, 1)
	assert_eq(balance.starting_fresh_food, 2)
	assert_eq(balance.starting_stored_food, 3)
	assert_eq(balance.wood_per_tree, 1)
	assert_eq(balance.wood_consumed_by_campfire_per_night, 12)
	assert_eq(balance.max_campfire_out_nights, 99)
	assert_eq(balance.wolf_spawn_day, 1)
	assert_eq(balance.wolf_spawn_interval_days, 1)
	assert_eq(balance.wolf_threat_radius, 999)
	assert_eq(balance.wolf_hunger_disruption, 1)

func test_default_preset_unchanged() -> void:
	# Strategic Phase 1 defaults plus the legacy fresh/stored migration split.
	var balance := BalanceData.new()
	assert_true(balance.load_from_file("res://data/balance.json"))
	assert_eq(balance.starting_wood, 25)
	assert_eq(balance.starting_fresh_food, 4)
	assert_eq(balance.starting_stored_food, 12)
	assert_eq(balance.starting_population, 10)
	assert_eq(balance.starting_food, 40)
	assert_eq(balance.starting_security, 50)
	assert_eq(balance.starting_morale, 60)
	assert_eq(balance.days_per_season, 15)
	assert_eq(balance.wolf_threat_radius, 8)

func test_hard_preset_triggers_wolf_threat_on_night_1() -> void:
	# Build a real sim with the hard preset and drive it through night 1.
	# Wolf placed manually within radius — the preset's wolf_spawn_day=1
	# would also spawn one naturally, but pinning the position keeps the
	# test deterministic.
	var balance := BalanceData.new()
	assert_true(balance.load_from_file("res://data/balance_hard.json"))
	balance.day_duration_seconds = 0.2
	balance.night_duration_seconds = 0.05
	balance.villager_move_interval = 0.005

	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)

	# Inject a wolf within threat radius (999) of HUT.
	var wolf_pos: Vector2i = WorldGenerator.HUT_POS + Vector2i(5, 0)
	var wolf := WildlifeAgent.new(99, WildlifeAgent.Kind.WOLF, wolf_pos, 1)
	sim.nature.animals.append(wolf)

	assert_eq(sim._wolf_threat_count, 0, "should start at 0")
	# Drive night 1 directly. resolve_night burns 12 wood from starting=1
	# → campfire_out_nights = 1 → check_wolf_threat returns true →
	# _apply_wolf_disruption increments the counter.
	sim._on_night_started(1)
	assert_gte(sim._wolf_threat_count, 1,
		"hard preset should fire wolf_threat on night 1")
	assert_eq(sim.campfire_out_nights, 1,
		"campfire should be out after night 1 with starting_wood=1")

func test_hard_preset_does_not_lose_immediately() -> void:
	# max_campfire_out_nights = 99 means one forced failure isn't a loss.
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance_hard.json")
	balance.day_duration_seconds = 0.2
	balance.night_duration_seconds = 0.05
	balance.villager_move_interval = 0.005

	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	watch_signals(sim)
	sim._on_night_started(1)
	assert_eq(get_signal_emit_count(sim, "game_lost"), 0,
		"one forced campfire failure should not end the game")
