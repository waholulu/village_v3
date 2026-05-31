extends GutTest

func _setup_world_sim() -> VillageSimulation:
	var balance := BalanceData.new()
	balance.villager_count = 3
	balance.hunter_injury_chance_percent = 0
	balance.herbalist_recovery_chance_percent = 100
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	return sim

func test_policy_only_changes_on_week_boundary() -> void:
	var sim := _setup_world_sim()
	sim.game_time.day = 1
	assert_true(sim.set_policy(PolicyDefs.WOOD_FIRST))
	assert_eq(sim.active_policy, PolicyDefs.WOOD_FIRST)
	sim.game_time.day = 2
	assert_false(sim.set_policy(PolicyDefs.DEFENSE_FIRST))
	assert_eq(sim.active_policy, PolicyDefs.WOOD_FIRST)
	sim.game_time.day = 8
	assert_true(sim.set_policy(PolicyDefs.DEFENSE_FIRST))
	assert_eq(sim.active_policy, PolicyDefs.DEFENSE_FIRST)

func test_invalid_policy_is_rejected() -> void:
	var sim := _setup_world_sim()
	assert_false(sim.set_policy("gold_first"))
	assert_eq(sim.active_policy, PolicyDefs.default_policy())

func test_defense_policy_generates_guard_task() -> void:
	var sim := _setup_world_sim()
	sim.active_policy = PolicyDefs.DEFENSE_FIRST
	sim.store.set_resource("security", 40)
	sim._generate_tasks()
	assert_true(sim.board.has_active_task_of_type("guard_watch"))

func test_rest_policy_generates_tend_task_for_injured_villager() -> void:
	var sim := _setup_world_sim()
	sim.active_policy = PolicyDefs.REST_FIRST
	sim.villagers[0].status = VillagerAgent.Status.INJURED
	sim._generate_tasks()
	assert_true(sim.board.has_active_task_of_type("tend_villager"))

func test_food_first_boosts_farmer_daily_food_output() -> void:
	var sim := _setup_world_sim()
	sim.villagers.resize(1)
	sim.villagers[0].job = JobDefs.FARMER
	sim.active_policy = PolicyDefs.FOOD_FIRST
	sim.store.set_resource("food", 10)
	var summary: Dictionary = sim._resolve_policy_daily_resources()
	assert_eq(summary["food_consumed"], 1)
	assert_eq(summary["food"], 3)
	assert_eq(sim.store.get_resource("food"), 12)

func test_wood_first_boosts_woodcutter_daily_output() -> void:
	var sim := _setup_world_sim()
	sim.villagers.resize(1)
	sim.villagers[0].job = JobDefs.WOODCUTTER
	sim.active_policy = PolicyDefs.WOOD_FIRST
	var before := sim.store.get_resource("wood")
	var summary: Dictionary = sim._resolve_policy_daily_resources()
	assert_eq(summary["wood"], 3)
	assert_eq(sim.store.get_resource("wood"), before + 3)

func test_defense_first_boosts_guard_daily_security_output() -> void:
	var sim := _setup_world_sim()
	sim.villagers.resize(1)
	sim.villagers[0].job = JobDefs.GUARD
	sim.active_policy = PolicyDefs.DEFENSE_FIRST
	var before := sim.store.get_resource("security")
	var summary: Dictionary = sim._resolve_policy_daily_resources()
	assert_eq(summary["security"], 3)
	assert_eq(sim.store.get_resource("security"), before + 3)

func test_rest_first_boosts_herbalist_recovery_morale_output() -> void:
	var sim := _setup_world_sim()
	sim.villagers.resize(2)
	sim.villagers[0].job = JobDefs.HERBALIST
	sim.villagers[1].status = VillagerAgent.Status.SICK
	sim.active_policy = PolicyDefs.REST_FIRST
	var before := sim.store.get_resource("morale")
	var summary: Dictionary = sim._resolve_policy_daily_resources()
	assert_eq(summary["recovered"], 1)
	assert_eq(sim.villagers[1].status, VillagerAgent.Status.HEALTHY)
	assert_eq(summary["morale"], 1)
	assert_eq(sim.store.get_resource("morale"), before + 1)

func test_explore_forest_boosts_hunter_daily_food_output() -> void:
	var sim := _setup_world_sim()
	sim.villagers.resize(1)
	sim.villagers[0].job = JobDefs.HUNTER
	sim.active_policy = PolicyDefs.EXPLORE_FOREST
	var summary: Dictionary = sim._resolve_policy_daily_resources()
	assert_eq(summary["food"], 3)

func test_tired_villager_has_reduced_output() -> void:
	var sim := _setup_world_sim()
	sim.villagers.resize(1)
	sim.villagers[0].job = JobDefs.FARMER
	sim.villagers[0].status = VillagerAgent.Status.TIRED
	sim.active_policy = PolicyDefs.WOOD_FIRST
	var summary: Dictionary = sim._resolve_policy_daily_resources()
	assert_eq(summary["food"], 1)

func test_injured_sick_dead_villagers_do_not_work() -> void:
	var sim := _setup_world_sim()
	sim.villagers.resize(3)
	sim.villagers[0].job = JobDefs.FARMER
	sim.villagers[1].job = JobDefs.WOODCUTTER
	sim.villagers[2].job = JobDefs.GUARD
	sim.villagers[0].status = VillagerAgent.Status.INJURED
	sim.villagers[1].status = VillagerAgent.Status.SICK
	sim.villagers[2].status = VillagerAgent.Status.DEAD
	var summary: Dictionary = sim._resolve_policy_daily_resources()
	assert_eq(summary["food"], 0)
	assert_eq(summary["wood"], 0)
	assert_eq(summary["security"], 0)

func test_hunter_injury_roll_is_deterministic_with_seed() -> void:
	var sim := _setup_world_sim()
	sim._balance.hunter_injury_chance_percent = 100
	sim.villagers.resize(1)
	sim.villagers[0].job = JobDefs.HUNTER
	var summary: Dictionary = sim._resolve_policy_daily_resources()
	assert_eq(summary["injured"], 1)
	assert_eq(sim.villagers[0].status, VillagerAgent.Status.INJURED)

func test_herbalist_recovery_roll_is_deterministic_with_seed() -> void:
	var sim := _setup_world_sim()
	sim._balance.herbalist_recovery_chance_percent = 100
	sim.villagers.resize(2)
	sim.villagers[0].job = JobDefs.HERBALIST
	sim.villagers[1].status = VillagerAgent.Status.INJURED
	var summary: Dictionary = sim._resolve_policy_daily_resources()
	assert_eq(summary["recovered"], 1)
	assert_eq(sim.villagers[1].status, VillagerAgent.Status.HEALTHY)

func test_policy_and_job_change_task_weights_without_new_ai_state() -> void:
	var sim := _setup_world_sim()
	var hunter := sim.villagers[0]
	hunter.job = JobDefs.HUNTER
	var hunt := sim.board.create_task("hunt_deer", hunter.tile_position + Vector2i(1, 0), 0)
	var chop := sim.board.create_task("chop_tree", hunter.tile_position + Vector2i(1, 0), 0)
	hunt.approach_tile = hunter.tile_position
	chop.approach_tile = hunter.tile_position
	var picked: Task = hunter.pick_best_task(sim.board, sim.store, sim.game_time, sim.scorer, PolicyDefs.EXPLORE_FOREST)
	assert_eq(picked.id, hunt.id)

func test_save_load_preserves_policy_and_jobs() -> void:
	var sim := _setup_world_sim()
	sim.active_policy = PolicyDefs.REST_FIRST
	sim.villagers[0].job = JobDefs.HERBALIST
	var save := SaveManager.new()
	save.save(sim)
	sim.active_policy = PolicyDefs.WOOD_FIRST
	sim.villagers[0].job = JobDefs.WOODCUTTER
	assert_true(save.load_into(sim))
	assert_eq(sim.active_policy, PolicyDefs.REST_FIRST)
	assert_eq(sim.villagers[0].job, JobDefs.HERBALIST)
