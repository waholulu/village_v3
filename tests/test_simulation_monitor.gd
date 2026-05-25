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
	wg = WorldGenerator.new()
	wg.generate_fixed()
	pf = PathfindingService.new()
	pf.setup(wg)
	sim = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)

func test_initial_simulation_has_no_anomalies() -> void:
	assert_eq(sim.run_monitor_check().size(), 0)

func test_villager_out_of_bounds_is_reported() -> void:
	sim.villagers[0].tile_position = Vector2i(WorldGenerator.WIDTH, 0)
	assert_true(_has_code(sim.run_monitor_check(), "villager_out_of_bounds"))

func test_villager_on_unwalkable_tile_is_reported() -> void:
	var tree_pos := wg.get_tiles_of_type(WorldGenerator.TileType.TREE)[0]
	sim.villagers[0].tile_position = tree_pos
	assert_true(_has_code(sim.run_monitor_check(), "villager_on_unwalkable_tile"))

func test_path_out_of_bounds_is_reported() -> void:
	sim.villagers[0]._path = [sim.villagers[0].tile_position, Vector2i(-1, 0)]
	assert_true(_has_code(sim.run_monitor_check(), "path_out_of_bounds"))

func test_task_approach_out_of_bounds_is_reported() -> void:
	var task := sim.board.create_task("gather_food", Vector2i(3, 3), 0)
	task.approach_tile = Vector2i(WorldGenerator.WIDTH, WorldGenerator.HEIGHT)
	assert_true(_has_code(sim.run_monitor_check(), "task_approach_out_of_bounds"))

func test_task_approach_unwalkable_is_reported() -> void:
	var tree_pos := wg.get_tiles_of_type(WorldGenerator.TileType.TREE)[0]
	var task := sim.board.create_task("gather_food", Vector2i(3, 3), 0)
	task.approach_tile = tree_pos
	assert_true(_has_code(sim.run_monitor_check(), "task_approach_unwalkable"))

func test_claimed_task_missing_villager_is_reported() -> void:
	var task := sim.board.create_task("gather_food", Vector2i(3, 3), 0)
	sim.board.claim_task(task.id, 999)
	assert_true(_has_code(sim.run_monitor_check(), "claimed_task_missing_villager"))

func test_claimed_task_unassigned_is_reported() -> void:
	var task := sim.board.create_task("gather_food", Vector2i(3, 3), 0)
	sim.board.claim_task(task.id, sim.villagers[0].id)
	assert_true(_has_code(sim.run_monitor_check(), "claimed_task_unassigned"))

func test_villager_missing_task_is_reported() -> void:
	sim.villagers[0].current_task_id = 999
	sim.villagers[0].state = VillagerAgent.State.MOVING_TO_TARGET
	assert_true(_has_code(sim.run_monitor_check(), "villager_task_missing_task"))

func test_villager_task_not_claimed_is_reported() -> void:
	var task := sim.board.create_task("gather_food", Vector2i(3, 3), 0)
	sim.villagers[0].set_task(task)
	assert_true(_has_code(sim.run_monitor_check(), "villager_task_not_claimed"))

func test_villager_task_claim_mismatch_is_reported() -> void:
	var task := sim.board.create_task("gather_food", Vector2i(3, 3), 0)
	sim.board.claim_task(task.id, sim.villagers[1].id)
	sim.villagers[0].set_task(task)
	assert_true(_has_code(sim.run_monitor_check(), "villager_task_claim_mismatch"))

func test_idle_villager_with_task_is_reported() -> void:
	var task := sim.board.create_task("gather_food", Vector2i(3, 3), 0)
	sim.villagers[0].current_task_id = task.id
	assert_true(_has_code(sim.run_monitor_check(), "villager_idle_with_task"))

func test_negative_resource_is_reported() -> void:
	sim.store.add_resource("wood", -11)
	assert_true(_has_code(sim.run_monitor_check(), "negative_resource"))

func test_population_over_capacity_is_reported() -> void:
	sim.population_capacity = 2
	assert_true(_has_code(sim.run_monitor_check(), "population_over_capacity"))

func test_monitor_signal_emits_when_anomalies_change() -> void:
	watch_signals(sim)
	sim.villagers[0].tile_position = Vector2i(-1, 0)
	sim.run_monitor_check()
	assert_signal_emitted(sim, "monitor_anomalies_changed")

func test_food_survival_risk_when_no_food_source_available() -> void:
	sim.store.consume_resource("food", sim.store.get_resource("food"))
	sim.nature.wildlife_food = 0
	for bush in wg.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH):
		wg.set_tile(bush.x, bush.y, WorldGenerator.TileType.GRASS)
	assert_true(_has_code(sim.run_monitor_check(), "food_survival_risk"))

func test_wood_survival_risk_when_no_tree_available() -> void:
	sim.store.consume_resource("wood", sim.store.get_resource("wood"))
	for tree in wg.get_tiles_of_type(WorldGenerator.TileType.TREE):
		wg.set_tile(tree.x, tree.y, WorldGenerator.TileType.GRASS)
	assert_true(_has_code(sim.run_monitor_check(), "wood_survival_risk"))

func test_moving_villager_without_path_is_reported() -> void:
	sim.villagers[0].state = VillagerAgent.State.MOVING_TO_TARGET
	assert_true(_has_code(sim.run_monitor_check(), "moving_villager_without_path"))

func _has_code(anomalies: Array[Dictionary], code: String) -> bool:
	for anomaly in anomalies:
		if anomaly.get("code", "") == code:
			return true
	return false
