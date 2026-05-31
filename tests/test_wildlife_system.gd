extends GutTest

const NatureSystemScript = preload("res://scripts/sim/nature_system.gd")

var balance: BalanceData
var nature: RefCounted
var wg: WorldGenerator

func before_each() -> void:
	balance = BalanceData.new()
	balance.world_seed = 42
	balance.nature_tree_regrowth_days = 2
	balance.nature_berry_regrowth_days = 1
	balance.nature_max_trees = 40
	balance.nature_max_berry_bushes = 40
	balance.deer_spawn_per_day = 2
	balance.deer_max_count = 6
	balance.food_per_deer = 3
	balance.deer_hunt_radius = 14
	balance.wolf_spawn_day = 4
	balance.wolf_spawn_interval_days = 1
	balance.wolf_spawn_count = 1
	balance.wolf_max_count = 3
	balance.wolf_max_age_days = 5
	balance.wolf_threat_radius = 5
	balance.wolf_hunger_disruption = 1
	nature = NatureSystemScript.new()
	nature.setup(balance)
	wg = WorldGenerator.new()
	wg.generate_fixed(42, 10, 6, 4)

func test_deer_spawns_near_berry_bush() -> void:
	nature.update_day(1, wg)
	assert_gt(nature.wildlife_food, 0, "At least one deer should spawn near bushes on day 1")

func test_deer_count_caps_at_max() -> void:
	balance.deer_spawn_per_day = 10
	balance.deer_max_count = 3
	nature.setup(balance)
	for d in range(1, 10):
		nature.update_day(d, wg)
	assert_lte(nature.wildlife_food, 3, "Deer count must not exceed deer_max_count")

func test_deer_moves_one_tile_per_day() -> void:
	var deer := WildlifeAgent.new(1, WildlifeAgent.Kind.DEER, Vector2i(5, 5), 1)
	nature.animals.append(deer)
	var before: Vector2i = deer.tile_position
	nature.update_day(2, wg)
	var after: Vector2i = deer.tile_position
	var dist: int = (abs(after.x - before.x) + abs(after.y - before.y))
	assert_lte(dist, 1, "Deer should move at most 1 tile per day")

func test_wolf_absent_before_spawn_day() -> void:
	balance.wolf_spawn_day = 4
	nature.setup(balance)
	for d in range(1, 4):
		nature.update_day(d, wg)
	var wolf_count: int = 0
	for a in nature.animals:
		var animal: WildlifeAgent = a as WildlifeAgent
		if animal != null and animal.kind == WildlifeAgent.Kind.WOLF:
			wolf_count += 1
	assert_eq(wolf_count, 0, "No wolves should spawn before wolf_spawn_day")

func test_wolf_appears_on_spawn_day() -> void:
	balance.wolf_spawn_day = 4
	balance.wolf_spawn_interval_days = 1
	nature.setup(balance)
	for d in range(1, 5):
		nature.update_day(d, wg)
	var wolf_count: int = 0
	for a in nature.animals:
		var animal: WildlifeAgent = a as WildlifeAgent
		if animal != null and animal.kind == WildlifeAgent.Kind.WOLF:
			wolf_count += 1
	assert_gt(wolf_count, 0, "At least one wolf should appear on or after wolf_spawn_day")

func test_wolf_despawns_after_max_age() -> void:
	balance.wolf_max_age_days = 3
	nature.setup(balance)
	var wolf := WildlifeAgent.new(99, WildlifeAgent.Kind.WOLF, Vector2i(10, 10), 1)
	wolf.age_days = 2
	nature.animals.append(wolf)
	nature.update_day(5, wg)
	var still_alive := false
	for a in nature.animals:
		var animal: WildlifeAgent = a as WildlifeAgent
		if animal != null and animal.id == 99:
			still_alive = true
	assert_false(still_alive, "Wolf should despawn after reaching wolf_max_age_days")

func test_wolf_threat_true_when_close_and_campfire_out() -> void:
	balance.wolf_threat_radius = 5
	nature.setup(balance)
	var wolf_pos: Vector2i = WorldGenerator.HUT_POS + Vector2i(3, 0)
	var wolf := WildlifeAgent.new(1, WildlifeAgent.Kind.WOLF, wolf_pos, 1)
	nature.animals.append(wolf)
	assert_true(nature.check_wolf_threat(1), "Wolf within threat radius with campfire out should trigger threat")

func test_wolf_threat_false_when_campfire_burning() -> void:
	balance.wolf_threat_radius = 5
	nature.setup(balance)
	var wolf_pos: Vector2i = WorldGenerator.HUT_POS + Vector2i(3, 0)
	var wolf := WildlifeAgent.new(1, WildlifeAgent.Kind.WOLF, wolf_pos, 1)
	nature.animals.append(wolf)
	assert_false(nature.check_wolf_threat(0), "Wolf threat should be false when campfire is burning (campfire_out_nights == 0)")

func test_hunt_deer_gives_fresh_food() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(10, 0, 1)
	var deer := WildlifeAgent.new(1, WildlifeAgent.Kind.DEER, Vector2i(5, 5), 1)
	sim.nature.animals.append(deer)
	var food_before: int = sim.store.get_resource("fresh_food")
	var task: Task = sim.board.create_task("hunt_deer", deer.tile_position, 0)
	task.approach_tile = deer.tile_position
	sim.board.claim_task(task.id, sim.villagers[0].id)
	sim.villagers[0].set_task(task)
	sim.villagers[0].tile_position = deer.tile_position
	sim._execute_task_at_target(sim.villagers[0])
	assert_gt(sim.store.get_resource("fresh_food"), food_before, "Hunting a deer should increase fresh_food")

func test_hunt_deer_escaped_gives_no_food() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(10, 0, 1)
	var food_before: int = sim.store.get_resource("fresh_food")
	var task: Task = sim.board.create_task("hunt_deer", Vector2i(5, 5), 0)
	task.approach_tile = Vector2i(5, 5)
	sim.board.claim_task(task.id, sim.villagers[0].id)
	sim.villagers[0].set_task(task)
	sim.villagers[0].tile_position = Vector2i(5, 5)
	sim._execute_task_at_target(sim.villagers[0])
	assert_eq(sim.store.get_resource("fresh_food"), food_before, "Hunting an escaped deer should not change fresh_food")

func test_wildlife_changed_signal_emits() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	var wg_local := WorldGenerator.new()
	wg_local.generate_fixed()
	var pf := PathfindingService.new()
	pf.setup(wg_local)
	var bal := BalanceData.new()
	bal.starting_wood = 10
	bal.starting_fresh_food = 8
	bal.starting_stored_food = 0
	bal.villager_count = 2
	bal.starting_population_capacity = 2
	bal.day_duration_seconds = 10.0
	bal.night_duration_seconds = 5.0
	bal.days_per_season = 5
	sim.setup(bal, wg_local, pf)
	watch_signals(sim)
	sim._on_day_started(1)
	assert_signal_emitted(sim, "wildlife_changed")
