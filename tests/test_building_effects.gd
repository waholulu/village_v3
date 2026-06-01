extends GutTest

var sim: VillageSimulation
var wg: WorldGenerator
var pf: PathfindingService

func before_each() -> void:
	var balance := BalanceData.new()
	balance.starting_wood = 10
	balance.starting_fresh_food = 8
	balance.starting_stored_food = 0
	balance.starting_food = 8
	balance.villager_count = 3
	balance.starting_population_capacity = 3
	balance.day_duration_seconds = 10.0
	balance.night_duration_seconds = 5.0
	balance.days_per_season = 5
	balance.wolf_hunger_disruption = 10  # high raw damage so mitigation is visible
	balance.fence_wolf_damage_reduction = 0.10
	wg = WorldGenerator.new()
	wg.generate_fixed()
	pf = PathfindingService.new()
	pf.setup(wg)
	sim = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)

func test_fence_reduces_wolf_disruption() -> void:
	# raw=10, 2 fences → 10 * 0.9^2 = 8.1 → round 8
	sim._fence_count = 2
	sim._watchtower_count = 0
	var hunger_before: int = sim.villagers[0].hunger + sim.villagers[1].hunger + sim.villagers[2].hunger
	sim._apply_wolf_disruption()
	var hunger_after: int = sim.villagers[0].hunger + sim.villagers[1].hunger + sim.villagers[2].hunger
	assert_eq(hunger_after - hunger_before, 8, "Expected 8 hunger added with 2 fences")

func test_watchtower_halves_disruption() -> void:
	# raw=10, watchtower halves to 5, no fences → 5
	sim._watchtower_count = 1
	sim._fence_count = 0
	var before: int = sim.villagers[0].hunger + sim.villagers[1].hunger + sim.villagers[2].hunger
	sim._apply_wolf_disruption()
	var after: int = sim.villagers[0].hunger + sim.villagers[1].hunger + sim.villagers[2].hunger
	assert_eq(after - before, 5)

func test_watchtower_and_fences_stack() -> void:
	# raw=10 → watchtower halves to 5 → 3 fences: 5 * 0.9^3 = 3.645 → round 4
	sim._watchtower_count = 1
	sim._fence_count = 3
	var before: int = sim.villagers[0].hunger + sim.villagers[1].hunger + sim.villagers[2].hunger
	sim._apply_wolf_disruption()
	var after: int = sim.villagers[0].hunger + sim.villagers[1].hunger + sim.villagers[2].hunger
	assert_eq(after - before, 4)

func test_fresh_food_spoils_by_flat_amount_per_night() -> void:
	# fresh_food_spoilage_per_night=1 (default); flat spoilage regardless of stock
	sim.store.add_resource("fresh_food", 10)  # 8 starting + 10 = 18
	sim._apply_food_spoilage()
	assert_eq(sim.store.get_resource("fresh_food"), 17)  # 18 - 1 = 17
	assert_eq(sim.store.get_resource("stored_food"), 0)  # stored unchanged
