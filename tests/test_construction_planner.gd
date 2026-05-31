extends GutTest

const ConstructionPlannerScript = preload("res://scripts/sim/construction_planner.gd")

var sim: VillageSimulation
var wg: WorldGenerator
var pf: PathfindingService
var planner: ConstructionPlanner

func before_each() -> void:
	var balance := BalanceData.new()
	balance.starting_wood = 20
	balance.starting_fresh_food = 4
	balance.starting_stored_food = 0
	balance.villager_count = 3
	balance.starting_population_capacity = 3
	balance.population_growth_enabled = true
	balance.day_duration_seconds = 10.0
	balance.night_duration_seconds = 5.0
	balance.days_per_season = 5
	wg = WorldGenerator.new()
	wg.generate_fixed()
	pf = PathfindingService.new()
	pf.setup(wg)
	sim = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	planner = ConstructionPlannerScript.new()

func test_planner_returns_empty_when_nothing_needed() -> void:
	# Disable population growth so house isn't triggered (default at-capacity setup).
	sim._balance.population_growth_enabled = false
	var decision: Dictionary = planner.plan(sim)
	assert_true(decision.is_empty(), "Expected no construction, got %s" % decision)

func test_house_planned_when_at_capacity() -> void:
	# Villagers (3) == capacity (3), wood available, growth enabled.
	var decision: Dictionary = planner.plan(sim)
	assert_eq(decision.get("type", ""), "house")
	assert_eq(decision.get("task_type", ""), "build_house")

func test_fence_planned_when_wolves_present() -> void:
	sim._balance.population_growth_enabled = false  # block house priority
	var wolf := WildlifeAgent.new(1, WildlifeAgent.Kind.WOLF, Vector2i(10, 10), 1)
	sim.nature.animals.append(wolf)
	sim._wolf_threat_count = 1  # fence is reactive — requires prior threat
	var decision: Dictionary = planner.plan(sim)
	assert_eq(decision.get("type", ""), "fence")

func test_watchtower_planned_after_day_4() -> void:
	sim._balance.population_growth_enabled = false
	# Need to advance game_time to day 4
	sim.game_time.day = 4
	var decision: Dictionary = planner.plan(sim)
	assert_eq(decision.get("type", ""), "watchtower")

func test_storage_planned_when_food_high() -> void:
	sim._balance.population_growth_enabled = false
	# food_surplus_threshold=12; add enough fresh_food to push total above it
	sim.store.add_resource("fresh_food", 18)  # 4 starting + 18 = 22 total
	var decision: Dictionary = planner.plan(sim)
	assert_eq(decision.get("type", ""), "storage")

func test_priority_order_house_beats_fence() -> void:
	# Both house (at capacity) and fence (wolves + prior threat) triggers active.
	var wolf := WildlifeAgent.new(1, WildlifeAgent.Kind.WOLF, Vector2i(10, 10), 1)
	sim.nature.animals.append(wolf)
	sim._wolf_threat_count = 1
	var decision: Dictionary = planner.plan(sim)
	assert_eq(decision.get("type", ""), "house", "House should beat fence by priority")

func test_planner_skips_when_no_wood() -> void:
	sim.store.consume_resource("wood", 20)  # drain wood
	var decision: Dictionary = planner.plan(sim)
	assert_true(decision.is_empty())
