extends GutTest

var sim: VillageSimulation
var wg: WorldGenerator
var pf: PathfindingService

func before_each() -> void:
	var balance := BalanceData.new()
	balance.starting_wood = 8
	balance.starting_fresh_food = 0
	balance.starting_stored_food = 4
	balance.starting_food = 4
	balance.villager_count = 3
	balance.starting_population = 3
	balance.starting_population_capacity = 3
	balance.population_growth_enabled = true
	balance.population_capacity_per_house = 2
	balance.food_required_for_new_villager = 2
	wg = WorldGenerator.new()
	wg.generate_fixed()
	pf = PathfindingService.new()
	pf.setup(wg)
	sim = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	for villager in sim.villagers:
		villager.job = JobDefs.GUARD

func test_build_task_generated_when_population_at_capacity_and_wood_available() -> void:
	sim._run_construction_planner()
	assert_true(sim.board.has_active_task_of_type("build_house"))

func test_build_task_not_generated_without_enough_wood() -> void:
	sim.store.consume_resource("wood", 8)
	sim._run_construction_planner()
	assert_false(sim.board.has_active_task_of_type("build_house"))

func test_build_task_not_generated_when_population_growth_disabled() -> void:
	sim._balance.population_growth_enabled = false
	sim._run_construction_planner()
	assert_false(sim.board.has_active_task_of_type("build_house"))

func test_build_house_completion_consumes_wood_places_house_and_increases_capacity() -> void:
	var site := wg.find_next_build_site()
	var task := sim.board.create_task("build_house", site, 0)
	task.approach_tile = wg.find_walkable_adjacent(site)
	var villager := sim.villagers[0]
	sim.board.claim_task(task.id, villager.id)
	villager.set_task(task)
	sim._execute_task_at_target(villager)
	assert_eq(sim.store.get_resource("wood"), 0)
	assert_eq(wg.get_tile(site.x, site.y), WorldGenerator.TileType.HOUSE)
	assert_eq(sim.population_capacity, 5)
	assert_eq(task.status, Task.Status.COMPLETED)

func test_build_house_cancels_without_mutation_if_wood_spent_before_arrival() -> void:
	var site := wg.find_next_build_site()
	var task := sim.board.create_task("build_house", site, 0)
	task.approach_tile = wg.find_walkable_adjacent(site)
	var villager := sim.villagers[0]
	sim.board.claim_task(task.id, villager.id)
	villager.set_task(task)
	sim.store.consume_resource("wood", 8)
	sim._execute_task_at_target(villager)
	assert_eq(wg.get_tile(site.x, site.y), WorldGenerator.TileType.BUILD_SITE)
	assert_eq(sim.population_capacity, 3)
	assert_eq(task.status, Task.Status.CANCELLED)

func test_population_grows_on_day_start_when_capacity_and_food_allow() -> void:
	sim.population_capacity = 4
	sim._on_day_started(2)
	assert_eq(sim.villagers.size(), 4)
	assert_eq(sim.store.get_total_food(), 2)  # 4 stored - 2 consumed
	assert_eq(sim.store.get_resource("population"), 4)
	assert_false(sim.has_population_mismatch())

func test_population_does_not_grow_without_capacity() -> void:
	sim._on_day_started(2)
	assert_eq(sim.villagers.size(), 3)
	assert_eq(sim.store.get_total_food(), 4)
	assert_eq(sim.store.get_resource("population"), 3)

func test_population_does_not_grow_without_food() -> void:
	sim.population_capacity = 4
	sim.store.consume_resource("stored_food", 4)
	sim._on_day_started(2)
	assert_eq(sim.villagers.size(), 3)
	assert_eq(sim.store.get_resource("population"), 3)

func test_population_does_not_grow_when_population_growth_disabled() -> void:
	sim._balance.population_growth_enabled = false
	sim.population_capacity = 4
	sim._on_day_started(2)
	assert_eq(sim.villagers.size(), 3)
	assert_eq(sim.store.get_total_food(), 4)
	assert_eq(sim.store.get_resource("population"), 3)
