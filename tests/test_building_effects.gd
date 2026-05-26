extends GutTest

var sim: VillageSimulation
var wg: WorldGenerator
var pf: PathfindingService

func before_each() -> void:
	var balance := BalanceData.new()
	balance.starting_wood = 10
	balance.starting_food = 8
	balance.villager_count = 3
	balance.starting_population_capacity = 3
	balance.day_duration_seconds = 10.0
	balance.night_duration_seconds = 5.0
	balance.days_to_win = 7
	balance.wolf_hunger_disruption = 10  # high raw damage so mitigation is visible
	balance.food_base_capacity = 20
	balance.food_capacity_per_storage = 10
	balance.food_spoilage_divisor = 4
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

func test_food_spoils_above_cap() -> void:
	# food = 40, no storage (cap=20) → spoil ceil((40-20)/4) = 5 → remaining 35
	sim.store.add_resource("food", 32)  # 8 starting + 32 = 40
	sim._apply_food_spoilage()
	assert_eq(sim.store.get_resource("food"), 35)

func test_storage_raises_food_cap() -> void:
	# food = 38, 2 storages (cap = 20 + 20 = 40) → no spoilage
	sim._storage_count = 2
	sim.store.add_resource("food", 30)  # 8 + 30 = 38
	sim._apply_food_spoilage()
	assert_eq(sim.store.get_resource("food"), 38)

func test_food_at_cap_does_not_spoil() -> void:
	# food = 20 == cap → no spoilage
	sim.store.add_resource("food", 12)  # 8 + 12 = 20
	sim._apply_food_spoilage()
	assert_eq(sim.store.get_resource("food"), 20)
