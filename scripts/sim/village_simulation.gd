class_name VillageSimulation
extends Node

signal game_won()
signal game_lost(reason: String)
signal tile_changed(pos: Vector2i, new_type: int)

var store: ResourceStore
var game_time: GameTime
var board: TaskBoard
var world_gen: WorldGenerator
var pathfinding: PathfindingService
var scorer: UtilityScorer

var villagers: Array[VillagerAgent] = []
var hungry_villagers: int = 0
var campfire_out_nights: int = 0

var _balance: BalanceData
var _task_gen_enabled: bool = true

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
	game_time.game_won.connect(_relay_game_won)

	board = TaskBoard.new()
	scorer = UtilityScorer.new()

	var start_positions = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6)]
	var names = ["Alice", "Bob", "Carol"]
	for i in range(balance.villager_count):
		villagers.append(VillagerAgent.new(i + 1, names[i], start_positions[i]))

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

	store = ResourceStore.new()
	store.setup(wood, food)

	game_time = GameTime.new()
	game_time.setup(10.0, 5.0, 7)
	add_child(game_time)
	game_time.night_started.connect(_on_night_started)
	game_time.game_won.connect(_relay_game_won)

	board = TaskBoard.new()
	scorer = UtilityScorer.new()
	_balance = balance
	_task_gen_enabled = false

	for i in range(villager_count):
		villagers.append(VillagerAgent.new(i + 1, "V%d" % i, Vector2i(5 + i, 5)))

func _reset_state() -> void:
	# Idempotent setup: clear collections and free any previous GameTime so
	# tests / hot-reloads don't accumulate villagers or duplicate Node children.
	villagers.clear()
	hungry_villagers = 0
	campfire_out_nights = 0
	if game_time != null and is_instance_valid(game_time):
		game_time.queue_free()
		game_time = null

func _relay_game_won() -> void:
	game_won.emit()

func resolve_night() -> void:
	var food_needed = villagers.size() * _balance.food_consumed_per_villager_per_night
	var food_consumed = store.consume_resource("food", food_needed)
	hungry_villagers = food_needed - food_consumed

	var wood_consumed = store.consume_resource("wood", _balance.wood_consumed_by_campfire_per_night)
	if wood_consumed < _balance.wood_consumed_by_campfire_per_night:
		campfire_out_nights += 1
		if campfire_out_nights >= _balance.max_campfire_out_nights:
			game_lost.emit("Campfire out for %d consecutive nights" % campfire_out_nights)
	else:
		campfire_out_nights = 0

func _on_night_started(_day: int) -> void:
	resolve_night()
	_generate_return_home_tasks()

func _generate_return_home_tasks() -> void:
	var hut_pos = Vector2i(4, 5)
	for v in villagers:
		if not board.has_open_task_of_type("return_home"):
			board.create_task("return_home", hut_pos, game_time.tick)

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
	if wood < _balance.wood_low_threshold:
		for tree_pos in world_gen.get_tiles_of_type(WorldGenerator.TileType.TREE):
			_try_create_resource_task("chop_tree", tree_pos)
	if wood < _balance.wood_campfire_urgent_threshold and game_time.get_time_left() < _balance.time_left_urgent_seconds:
		if not board.has_open_task_of_type("refuel_campfire"):
			# Campfire is walkable, so target == approach.
			board.create_task("refuel_campfire", Vector2i(6, 6), game_time.tick)

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
			world_gen.set_tile(task.target_tile.x, task.target_tile.y, WorldGenerator.TileType.GRASS)
			if pathfinding:
				pathfinding.set_point_walkable(task.target_tile, true)
			tile_changed.emit(task.target_tile, WorldGenerator.TileType.GRASS)
			store.add_resource("wood", _balance.wood_per_tree)
		"gather_food":
			world_gen.set_tile(task.target_tile.x, task.target_tile.y, WorldGenerator.TileType.GRASS)
			tile_changed.emit(task.target_tile, WorldGenerator.TileType.GRASS)
			store.add_resource("food", _balance.food_per_bush)
		"refuel_campfire", "return_home":
			# MVP placeholder — no per-villager side effect; campfire upkeep is
			# resolved automatically by resolve_night() against the global wood pool.
			pass
	board.complete_task(task.id)
	v.clear_task()
