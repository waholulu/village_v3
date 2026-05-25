class_name VillageSimulation
extends Node

const SimulationMonitorScript = preload("res://scripts/sim/simulation_monitor.gd")
const NatureSystemScript = preload("res://scripts/sim/nature_system.gd")
const SimulationSnapshotScript = preload("res://scripts/sim/simulation_snapshot.gd")

signal game_won()
signal game_lost(reason: String)
signal tile_changed(pos: Vector2i, new_type: int)
signal population_changed(current: int, capacity: int)
signal hunger_changed(hungry_count: int)
signal monitor_anomalies_changed(anomalies: Array[Dictionary])

var store: ResourceStore
var game_time: GameTime
var board: TaskBoard
var world_gen: WorldGenerator
var pathfinding: PathfindingService
var scorer: UtilityScorer
var monitor: RefCounted
var nature: RefCounted

var villagers: Array[VillagerAgent] = []
var monitor_anomalies: Array[Dictionary] = []
var hungry_villagers: int = 0
var campfire_out_nights: int = 0
var population_capacity: int = 3

var _balance: BalanceData
var _task_gen_enabled: bool = true
var _next_villager_id: int = 1

func setup(balance: BalanceData, p_world_gen: WorldGenerator, p_pathfinding: PathfindingService) -> void:
	_reset_state()
	_balance = balance
	world_gen = p_world_gen
	pathfinding = p_pathfinding

	store = ResourceStore.new()
	store.setup(balance.starting_wood, balance.starting_food)

	game_time = GameTime.new()
	game_time.setup(balance.day_duration_seconds, balance.night_duration_seconds, balance.days_to_win)
	add_child(game_time)
	game_time.night_started.connect(_on_night_started)
	game_time.day_started.connect(_on_day_started)
	game_time.game_won.connect(_relay_game_won)

	board = TaskBoard.new()
	scorer = UtilityScorer.new()
	monitor = SimulationMonitorScript.new()
	nature = NatureSystemScript.new()
	nature.setup(balance)
	population_capacity = balance.starting_population_capacity

	for i in range(balance.villager_count):
		_add_villager()
	run_monitor_check()

func setup_for_test(wood: int, food: int, villager_count: int) -> void:
	_reset_state()
	var balance = BalanceData.new()
	balance.starting_wood = wood
	balance.starting_food = food
	balance.villager_count = villager_count
	balance.days_to_win = 7
	balance.food_consumed_per_villager_per_night = 1
	balance.wood_consumed_by_campfire_per_night = 2
	balance.max_campfire_out_nights = 2
	balance.starting_population_capacity = villager_count
	balance.house_wood_cost = 8
	balance.population_capacity_per_house = 2
	balance.food_required_for_new_villager = 2
	balance.max_hunger = 3

	store = ResourceStore.new()
	store.setup(wood, food)

	game_time = GameTime.new()
	game_time.setup(10.0, 5.0, 7)
	add_child(game_time)
	game_time.night_started.connect(_on_night_started)
	game_time.day_started.connect(_on_day_started)
	game_time.game_won.connect(_relay_game_won)

	board = TaskBoard.new()
	scorer = UtilityScorer.new()
	monitor = SimulationMonitorScript.new()
	nature = NatureSystemScript.new()
	nature.setup(balance)
	_balance = balance
	_task_gen_enabled = false
	population_capacity = balance.starting_population_capacity

	for i in range(villager_count):
		_add_villager()
	run_monitor_check()

func _reset_state() -> void:
	# Idempotent setup: clear collections and free any previous GameTime so
	# tests / hot-reloads don't accumulate villagers or duplicate Node children.
	villagers.clear()
	hungry_villagers = 0
	campfire_out_nights = 0
	population_capacity = 3
	_next_villager_id = 1
	monitor = null
	nature = null
	monitor_anomalies.clear()
	if game_time != null and is_instance_valid(game_time):
		game_time.queue_free()
		game_time = null

func run_monitor_check() -> Array[Dictionary]:
	if monitor == null:
		return []
	var new_anomalies: Array[Dictionary] = monitor.check(self)
	if not _anomalies_equal(monitor_anomalies, new_anomalies):
		monitor_anomalies = new_anomalies
		monitor_anomalies_changed.emit(monitor_anomalies)
	return monitor_anomalies

func _anomalies_equal(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i].get("code", "") != b[i].get("code", ""):
			return false
		if a[i].get("severity", "") != b[i].get("severity", ""):
			return false
		if a[i].get("message", "") != b[i].get("message", ""):
			return false
	return true

func _relay_game_won() -> void:
	game_won.emit()

func resolve_night() -> void:
	_resolve_hunger()

	var wood_consumed = store.consume_resource("wood", _balance.wood_consumed_by_campfire_per_night)
	if wood_consumed < _balance.wood_consumed_by_campfire_per_night:
		campfire_out_nights += 1
		if campfire_out_nights >= _balance.max_campfire_out_nights:
			game_lost.emit("Campfire out for %d consecutive nights" % campfire_out_nights)
	else:
		campfire_out_nights = 0
	run_monitor_check()

func _resolve_hunger() -> void:
	for v in villagers:
		var consumed := store.consume_resource("food", _balance.food_consumed_per_villager_per_night)
		if consumed == _balance.food_consumed_per_villager_per_night:
			v.hunger = maxi(0, v.hunger - 1)
		else:
			v.hunger += 1
	_update_hungry_count()
	for v in villagers:
		if v.hunger >= _balance.max_hunger:
			game_lost.emit("A villager starved")
			return

func _on_night_started(_day: int) -> void:
	resolve_night()
	_generate_return_home_tasks()

func _on_day_started(_day: int) -> void:
	_cancel_open_tasks_of_type("return_home")
	_update_nature_for_day(_day)
	_grow_population_if_possible()

func _update_nature_for_day(day: int) -> void:
	if nature == null or world_gen == null:
		return
	var changes: Array[Dictionary] = nature.update_day(day, world_gen)
	for change in changes:
		var pos: Vector2i = change["pos"]
		var tile_type: int = change["type"]
		if pathfinding:
			pathfinding.set_point_walkable(pos, false)
		tile_changed.emit(pos, tile_type)
	run_monitor_check()

func _generate_return_home_tasks() -> void:
	for v in villagers:
		board.create_task("return_home", WorldGenerator.HUT_POS, game_time.tick)

func _cancel_open_tasks_of_type(task_type: String) -> void:
	for task in board._tasks:
		if task.type == task_type and task.status == Task.Status.OPEN:
			board.cancel_task(task.id)

func _process(delta: float) -> void:
	if game_time == null or game_time.phase == GameTime.Phase.NIGHT:
		return
	if _task_gen_enabled:
		_generate_tasks()
	_tick_villagers(delta)

func _generate_tasks() -> void:
	var food: int = store.get_resource("food")
	var wood: int = store.get_resource("wood")
	if food < _balance.food_low_threshold:
		for bush_pos in world_gen.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH):
			_try_create_resource_task("gather_food", bush_pos)
		if nature != null and nature.wildlife_food > 0 and not board.has_active_task_of_type("gather_wildlife"):
			board.create_task("gather_wildlife", WorldGenerator.HUT_POS, game_time.tick)
	if wood < _balance.wood_low_threshold:
		for tree_pos in world_gen.get_tiles_of_type(WorldGenerator.TileType.TREE):
			_try_create_resource_task("chop_tree", tree_pos)
	if wood < _balance.wood_campfire_urgent_threshold and game_time.get_time_left() < _balance.time_left_urgent_seconds:
		if not board.has_open_task_of_type("refuel_campfire"):
			# Campfire is walkable, so target == approach.
			board.create_task("refuel_campfire", WorldGenerator.CAMPFIRE_POS, game_time.tick)
	if _should_build_house():
		var site: Vector2i = world_gen.find_next_build_site()
		_try_create_resource_task("build_house", site)

func _should_build_house() -> bool:
	return _balance.population_growth_enabled \
		and villagers.size() >= population_capacity \
		and store.has_enough("wood", _balance.house_wood_cost) \
		and not board.has_active_task_of_type("build_house") \
		and world_gen.find_next_build_site() != Vector2i(-1, -1)

func _try_create_resource_task(task_type: String, target_tile: Vector2i) -> void:
	# Per-tile dedupe: don't queue the same tree/bush twice.
	if board.has_task_for_tile(target_tile):
		return
	var adj: Vector2i = world_gen.find_walkable_adjacent(target_tile)
	if adj == Vector2i(-1, -1):
		return
	var task = board.create_task(task_type, target_tile, game_time.tick)
	task.approach_tile = adj

func _tick_villagers(delta: float) -> void:
	for v in villagers:
		if v.state == VillagerAgent.State.IDLE:
			var task: Task = v.pick_best_task(board, store, game_time, scorer)
			if task != null:
				board.claim_task(task.id, v.id)
				v.set_task(task)
				var path: Array[Vector2i] = []
				if pathfinding:
					path = pathfinding.get_path(v.tile_position, task.approach_tile)
				if path.is_empty():
					# Unreachable target — cancel the task and go idle.
					board.cancel_task(task.id)
					v.clear_task()
				else:
					v._path = path
		elif v.state == VillagerAgent.State.MOVING_TO_TARGET:
			var arrived = v.tick_movement(delta, v._path, _balance.villager_move_interval)
			if arrived:
				_execute_task_at_target(v)
	run_monitor_check()

func _execute_task_at_target(v: VillagerAgent) -> void:
	var task = board.get_task(v.current_task_id)
	if task == null:
		v.clear_task()
		return
	# ORDER MATTERS: mutate the world (tile + pathfinding) FIRST, emit tile_changed,
	# THEN bump the resource counter. Listeners reading world_gen on tile_changed
	# must see the new tile, not the old one.
	match task.type:
		"chop_tree":
			if nature:
				nature.record_harvest(WorldGenerator.TileType.TREE, task.target_tile, game_time.day)
			world_gen.set_tile(task.target_tile.x, task.target_tile.y, WorldGenerator.TileType.GRASS)
			if pathfinding:
				pathfinding.set_point_walkable(task.target_tile, true)
			tile_changed.emit(task.target_tile, WorldGenerator.TileType.GRASS)
			store.add_resource("wood", _balance.wood_per_tree)
		"gather_food":
			if nature:
				nature.record_harvest(WorldGenerator.TileType.BERRY_BUSH, task.target_tile, game_time.day)
			world_gen.set_tile(task.target_tile.x, task.target_tile.y, WorldGenerator.TileType.GRASS)
			tile_changed.emit(task.target_tile, WorldGenerator.TileType.GRASS)
			store.add_resource("food", _balance.food_per_bush)
		"gather_wildlife":
			if nature:
				var gathered: int = nature.consume_wildlife_food(1)
				if gathered > 0:
					store.add_resource("food", gathered * _balance.food_per_wildlife)
		"build_house":
			if store.has_enough("wood", _balance.house_wood_cost):
				store.consume_resource("wood", _balance.house_wood_cost)
				world_gen.set_tile(task.target_tile.x, task.target_tile.y, WorldGenerator.TileType.HOUSE)
				if pathfinding:
					pathfinding.set_point_walkable(task.target_tile, true)
				population_capacity += _balance.population_capacity_per_house
				tile_changed.emit(task.target_tile, WorldGenerator.TileType.HOUSE)
				population_changed.emit(villagers.size(), population_capacity)
				run_monitor_check()
			else:
				board.cancel_task(task.id)
				v.clear_task()
				return
		"refuel_campfire", "return_home":
			# MVP placeholder — no per-villager side effect; campfire upkeep is
			# resolved automatically by resolve_night() against the global wood pool.
			pass
	board.complete_task(task.id)
	v.clear_task()

func _grow_population_if_possible() -> void:
	if not _balance.population_growth_enabled:
		return
	if villagers.size() >= population_capacity:
		return
	if not store.has_enough("food", _balance.food_required_for_new_villager):
		return
	store.consume_resource("food", _balance.food_required_for_new_villager)
	_add_villager()
	run_monitor_check()

func _add_villager() -> VillagerAgent:
	var names = ["Alice", "Bob", "Carol", "Drew", "Eli", "Fern", "Gale", "Hana"]
	var idx := _next_villager_id - 1
	var name: String = names[idx] if idx < names.size() else "Villager %d" % _next_villager_id
	var pos: Vector2i = find_valid_spawn_tile(idx)
	var villager := VillagerAgent.new(_next_villager_id, name, pos)
	_next_villager_id += 1
	villagers.append(villager)
	population_changed.emit(villagers.size(), population_capacity)
	return villager

func find_valid_spawn_tile(preferred_index: int = 0) -> Vector2i:
	var offsets = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(2, 1), Vector2i(0, 0)]
	if world_gen != null:
		for i in range(offsets.size()):
			var pos: Vector2i = WorldGenerator.HUT_POS + offsets[(preferred_index + i) % offsets.size()]
			if world_gen.is_in_bounds(pos) and world_gen.is_walkable(pos.x, pos.y):
				return pos
		for y in range(WorldGenerator.HEIGHT):
			for x in range(WorldGenerator.WIDTH):
				if world_gen.is_walkable(x, y):
					return Vector2i(x, y)
	return WorldGenerator.HUT_POS

func _update_hungry_count() -> void:
	var count := 0
	for v in villagers:
		if v.hunger > 0:
			count += 1
	hungry_villagers = count
	hunger_changed.emit(hungry_villagers)

func get_snapshot() -> Dictionary:
	return SimulationSnapshotScript.build(self)

func get_nature_summary() -> Dictionary:
	if nature == null:
		return {
			"wildlife_food": 0,
			"pending_trees": 0,
			"pending_berry_bushes": 0,
			"last_update_day": 0
		}
	return nature.get_summary()
