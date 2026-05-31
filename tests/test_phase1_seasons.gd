extends GutTest

# Phase 1 regression tests: season system, food split, winter pressure.

# --- Season advancement ---

func test_season_advances_through_year() -> void:
	var gt: GameTime = add_child_autoqfree(GameTime.new())
	gt.setup(10.0, 5.0, 5)
	# Advance to day 6 (Summer)
	for i in range(10):
		gt._advance_phase()
	assert_eq(gt.current_season, GameTime.Season.SUMMER, "Day 6 should be Summer")
	# Advance to day 11 (Autumn)
	for i in range(10):
		gt._advance_phase()
	assert_eq(gt.current_season, GameTime.Season.AUTUMN, "Day 11 should be Autumn")
	# Advance to day 16 (Winter)
	for i in range(10):
		gt._advance_phase()
	assert_eq(gt.current_season, GameTime.Season.WINTER, "Day 16 should be Winter")

# --- Fresh-first consumption ---

func test_food_split_consumes_fresh_first() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(10, 2, 3)  # fresh=2, stored=0
	sim.store.add_resource("stored_food", 2)  # fresh=2, stored=2, total=4
	sim.resolve_night()  # 3 villagers * 1 = 3 food consumed
	assert_eq(sim.store.get_resource("fresh_food"), 0, "Fresh food consumed first")
	assert_eq(sim.store.get_resource("stored_food"), 1, "Stored used only after fresh depleted")

# --- Flat fresh-food spoilage ---

func test_fresh_food_spoils_stored_does_not() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(10, 10, 1)
	sim._balance.fresh_food_spoilage_per_night = 1
	sim.store.add_resource("stored_food", 10)  # fresh=10, stored=10
	sim._apply_food_spoilage()
	assert_eq(sim.store.get_resource("fresh_food"), 9, "Fresh food should spoil by 1")
	assert_eq(sim.store.get_resource("stored_food"), 10, "Stored food never spoils")

# --- Gather food yields fresh food ---

func test_gather_food_yields_fresh_food() -> void:
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	balance.day_duration_seconds = 0.2
	balance.night_duration_seconds = 0.05
	balance.villager_move_interval = 0.005
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	var bushes := wg.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH)
	assert_gt(bushes.size(), 0, "need at least one bush")
	var bush_pos: Vector2i = bushes[0]
	var before: int = sim.store.get_resource("fresh_food")
	var task: Task = sim.board.create_task("gather_food", bush_pos, 0)
	task.approach_tile = wg.find_walkable_adjacent(bush_pos)
	sim.board.claim_task(task.id, sim.villagers[0].id)
	sim.villagers[0].set_task(task)
	sim.villagers[0].tile_position = task.approach_tile
	sim._execute_task_at_target(sim.villagers[0])
	assert_gt(sim.store.get_resource("fresh_food"), before, "gather_food must yield fresh_food")
	assert_eq(sim.store.get_resource("stored_food"), sim.store.get_resource("stored_food"),
		"stored_food unchanged by gather_food")

# --- Winter wood multiplier ---

func test_winter_campfire_wood_multiplier() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(20, 10, 1)
	# Summer night: standard consumption (wood_consumed_by_campfire_per_night=2)
	sim.game_time.current_season = GameTime.Season.SUMMER
	sim.resolve_night()
	var summer_consumed: int = 20 - sim.store.get_resource("wood")
	# Reset and do Winter night
	sim.setup_for_test(20, 10, 1)
	sim.game_time.current_season = GameTime.Season.WINTER
	sim.resolve_night()
	var winter_consumed: int = 20 - sim.store.get_resource("wood")
	assert_gt(winter_consumed, summer_consumed,
		"Winter should consume more wood than Summer")

# --- Winter disables gather_food task generation ---

func test_winter_disables_gather_food_tasks() -> void:
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	balance.day_duration_seconds = 0.2
	balance.night_duration_seconds = 0.05
	balance.villager_move_interval = 0.005
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	# Force Winter season and low food to trigger gather_food normally
	sim.game_time.current_season = GameTime.Season.WINTER
	sim.store.consume_resource("fresh_food", 999)
	sim.store.consume_resource("stored_food", 999)
	sim._generate_tasks()
	var gather_count := 0
	for task in sim.board._tasks:
		if task.type == "gather_food":
			gather_count += 1
	assert_eq(gather_count, 0, "gather_food must not be generated in Winter")

# --- Winter skips regrowth ---

func test_winter_skips_regrowth() -> void:
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	balance.nature_berry_regrowth_days = 1
	balance.nature_tree_regrowth_days = 1
	var wg := WorldGenerator.new()
	wg.generate_fixed()
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	# Harvest a bush so there's a pending regrowth
	var bushes := wg.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH)
	assert_gt(bushes.size(), 0)
	var bush_pos := bushes[0]
	var task: Task = sim.board.create_task("gather_food", bush_pos, 0)
	task.approach_tile = wg.find_walkable_adjacent(bush_pos)
	sim.board.claim_task(task.id, sim.villagers[0].id)
	sim.villagers[0].set_task(task)
	sim.villagers[0].tile_position = task.approach_tile
	sim._execute_task_at_target(sim.villagers[0])
	assert_eq(wg.get_tile(bush_pos.x, bush_pos.y), WorldGenerator.TileType.GRASS)
	# Advance 2 winter days — regrowth_days=1 but winter skips regrowth
	for d in range(1, 3):
		var no_blocked: Array[Vector2i] = []
		sim.nature.update_day(d, wg, no_blocked, GameTime.Season.WINTER)
	assert_eq(wg.get_tile(bush_pos.x, bush_pos.y), WorldGenerator.TileType.GRASS,
		"Berry bush must not regrow during Winter")

# --- Win condition: survive one full year ---

func test_win_condition_fires_after_full_year() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(10, 0, 1)
	sim._balance.days_per_season = 1
	sim.game_time.setup(0.001, 0.001, 1)
	watch_signals(sim)
	# Win fires at day > 4 with days_per_season=1; advance 8 phases = 4 days
	for i in range(10):
		sim.game_time._advance_phase()
	assert_signal_emitted(sim, "game_won", "Game should be won after one full year")

# --- Save/load preserves food split ---

func test_save_load_preserves_food_split() -> void:
	var balance := BalanceData.new()
	balance.starting_wood = 10
	balance.starting_fresh_food = 4
	balance.starting_stored_food = 7
	balance.villager_count = 1
	balance.starting_population_capacity = 3
	balance.day_duration_seconds = 10.0
	balance.night_duration_seconds = 5.0
	balance.days_per_season = 5
	var wg := WorldGenerator.new()
	wg.generate_fixed()
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	var sm := SaveManager.new()
	sm.save(sim)
	# Mutate so we can tell if load restores
	sim.store.consume_resource("fresh_food", 999)
	sim.store.consume_resource("stored_food", 999)
	assert_true(sm.load_into(sim))
	assert_eq(sim.store.get_resource("fresh_food"), 4, "fresh_food restored from save")
	assert_eq(sim.store.get_resource("stored_food"), 7, "stored_food restored from save")
