extends GutTest

func _setup_world_sim(balance: BalanceData) -> VillageSimulation:
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	return sim

func test_initial_strategic_state_matches_mvp_defaults() -> void:
	var balance := BalanceData.new()
	var sim := _setup_world_sim(balance)
	assert_eq(sim.store.get_resource("population"), 5)
	assert_eq(sim.store.get_resource("food"), 50)
	assert_eq(sim.store.get_resource("wood"), 25)
	assert_eq(sim.store.get_resource("security"), 50)
	assert_eq(sim.store.get_resource("morale"), 60)
	assert_eq(sim.game_time.day, 1)
	assert_eq(sim.get_days_to_win(), 60)
	assert_eq(sim.game_time.current_season, GameTime.Season.SPRING)
	assert_eq(sim.get_visible_population(), 5)
	assert_false(sim.has_population_mismatch())

func test_season_ranges_are_15_days_each() -> void:
	var gt: GameTime = add_child_autoqfree(GameTime.new())
	gt.setup(10.0, 5.0, 15)
	assert_eq(gt._compute_season(1), GameTime.Season.SPRING)
	assert_eq(gt._compute_season(15), GameTime.Season.SPRING)
	assert_eq(gt._compute_season(16), GameTime.Season.SUMMER)
	assert_eq(gt._compute_season(30), GameTime.Season.SUMMER)
	assert_eq(gt._compute_season(31), GameTime.Season.AUTUMN)
	assert_eq(gt._compute_season(45), GameTime.Season.AUTUMN)
	assert_eq(gt._compute_season(46), GameTime.Season.WINTER)
	assert_eq(gt._compute_season(60), GameTime.Season.WINTER)

func test_win_after_resolving_day_60() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 3)
	sim._balance.days_per_season = 15
	sim.game_time.setup(0.001, 0.001, 15)
	sim.game_time.day = 60
	watch_signals(sim)
	sim.game_time._advance_phase()
	sim.game_time._advance_phase()
	assert_signal_emitted(sim, "game_won")

func test_population_zero_loses_immediately() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 3)
	watch_signals(sim)
	sim.apply_strategic_resource_delta("population", -999)
	assert_signal_emitted(sim, "game_lost")

func test_zero_food_loses_after_3_consecutive_days() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 3)
	sim.store.set_resource("food", 0)
	watch_signals(sim)
	sim._resolve_strategic_daily_state()
	sim._resolve_strategic_daily_state()
	assert_signal_not_emitted(sim, "game_lost")
	sim._resolve_strategic_daily_state()
	assert_signal_emitted(sim, "game_lost")

func test_zero_morale_loses_after_3_consecutive_days() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 3)
	sim.store.set_resource("morale", 0)
	watch_signals(sim)
	sim._resolve_strategic_daily_state()
	sim._resolve_strategic_daily_state()
	assert_signal_not_emitted(sim, "game_lost")
	sim._resolve_strategic_daily_state()
	assert_signal_emitted(sim, "game_lost")

func test_zero_security_loses_after_3_consecutive_days() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 3)
	sim.store.set_resource("security", 0)
	watch_signals(sim)
	sim._resolve_strategic_daily_state()
	sim._resolve_strategic_daily_state()
	assert_signal_not_emitted(sim, "game_lost")
	sim._resolve_strategic_daily_state()
	assert_signal_emitted(sim, "game_lost")

func test_zero_streak_resets_when_resource_recovers() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 3)
	sim.store.set_resource("food", 0)
	sim._resolve_strategic_daily_state()
	sim._resolve_strategic_daily_state()
	assert_eq(sim.zero_food_days, 2)
	sim.store.set_resource("food", 1)
	sim._resolve_strategic_daily_state()
	assert_eq(sim.zero_food_days, 0)

func test_dead_villager_remains_listed_but_does_not_work() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 1)
	sim.villagers[0].status = VillagerAgent.Status.DEAD
	var task := sim.board.create_task("gather_food", Vector2i(3, 3), 0)
	sim._tick_villagers(1.0)
	assert_eq(sim.villagers.size(), 1)
	assert_eq(sim.villagers[0].status, VillagerAgent.Status.DEAD)
	assert_eq(sim.villagers[0].current_task_id, -1)
	assert_eq(task.status, Task.Status.OPEN)

func test_dead_villager_releases_existing_task() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 1)
	var task := sim.board.create_task("gather_food", Vector2i(3, 3), 0)
	sim.board.claim_task(task.id, sim.villagers[0].id)
	sim.villagers[0].set_task(task)
	sim.villagers[0].status = VillagerAgent.Status.DEAD
	sim._tick_villagers(1.0)
	assert_eq(sim.villagers[0].current_task_id, -1)
	assert_eq(task.status, Task.Status.CANCELLED)

func test_starvation_kills_one_villager_without_ending_run_when_others_live() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 3)
	sim.store.consume_resource("fresh_food", 999)
	sim.villagers[0].hunger = sim._balance.max_hunger - 1
	watch_signals(sim)
	sim.resolve_night()
	assert_eq(sim.villagers[0].status, VillagerAgent.Status.DEAD)
	assert_eq(sim.store.get_resource("population"), 2)
	assert_eq(sim.get_visible_population(), 2)
	assert_eq(get_signal_emit_count(sim, "game_lost"), 0)

func test_last_starving_villager_still_loses_run() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 1)
	sim.store.consume_resource("fresh_food", 999)
	sim.villagers[0].hunger = sim._balance.max_hunger - 1
	watch_signals(sim)
	sim.resolve_night()
	assert_eq(sim.villagers[0].status, VillagerAgent.Status.DEAD)
	assert_eq(sim.store.get_resource("population"), 0)
	assert_signal_emitted(sim, "game_lost")

func test_game_lost_emits_only_once_across_repeated_resolutions() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 3)
	sim.store.set_resource("food", 0)
	watch_signals(sim)
	# Three zero-food days trip the loss; subsequent resolutions must not re-emit.
	for i in range(6):
		sim._resolve_strategic_daily_state()
	assert_eq(get_signal_emit_count(sim, "game_lost"), 1)
	assert_true(sim.is_game_over())

func test_game_over_blocks_further_resolution() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 3)
	watch_signals(sim)
	sim.end_game_lost("test")
	# Once latched, end_game_won must not flip the outcome or emit.
	sim.end_game_won()
	assert_eq(get_signal_emit_count(sim, "game_lost"), 1)
	assert_eq(get_signal_emit_count(sim, "game_won"), 0)

func test_game_won_latches_after_win_day() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 40, 3)
	sim._balance.days_per_season = 15
	sim.game_time.setup(0.001, 0.001, 15)
	sim.game_time.day = 60
	watch_signals(sim)
	# Cross into day 61 (win), then keep advancing days — game_won fires once.
	for i in range(8):
		sim.game_time._advance_phase()
	assert_eq(get_signal_emit_count(sim, "game_won"), 1)
	assert_true(sim.is_game_over())
