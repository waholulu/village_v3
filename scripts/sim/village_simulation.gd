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
signal wildlife_changed(animals: Array[Dictionary])

var store: ResourceStore
var game_time: GameTime
var board: TaskBoard
var world_gen: WorldGenerator
var pathfinding: PathfindingService
var scorer: UtilityScorer
var monitor: RefCounted
var nature: RefCounted
var _planner: ConstructionPlanner

var villagers: Array[VillagerAgent] = []
var monitor_anomalies: Array[Dictionary] = []
var hungry_villagers: int = 0
var campfire_out_nights: int = 0
var population_capacity: int = 3
var _fence_count: int = 0
var _watchtower_count: int = 0
var _storage_count: int = 0
# Counts how many times wolves actually closed in on the village while the
# campfire was out. Drives reactive fence construction so the planner doesn't
# waste wood on perimeter defense before any real threat occurs.
var _wolf_threat_count: int = 0

var _balance: BalanceData
var _task_gen_enabled: bool = true
var _next_villager_id: int = 1
# Throttle counter for the per-frame monitor check inside _tick_villagers.
# Eager checks on state-change events (night, day, build, regrowth, save load)
# bypass this so anomalies surface immediately for actual mutations.
var _monitor_throttle_counter: int = 0
const MONITOR_THROTTLE_FRAMES: int = 5
var _logger  # ActionLogger or null — set via set_logger(), never touched by tests

func set_logger(logger) -> void:
	_logger = logger

func _log(data: Dictionary) -> void:
	if _logger == null:
		return
	data["tick"] = game_time.tick if game_time else 0
	data["day"] = game_time.day if game_time else 0
	data["phase"] = game_time.get_phase_name() if game_time else ""
	_logger.log_event(data)

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
	nature.setup(balance, p_pathfinding)
	_planner = ConstructionPlanner.new()
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
	balance.wolf_spawn_day = 999
	balance.wolf_threat_radius = 0
	balance.deer_max_count = 0
	balance.deer_spawn_per_day = 0
	balance.food_per_deer = 3

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
	_planner = ConstructionPlanner.new()
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
	_fence_count = 0
	_watchtower_count = 0
	_storage_count = 0
	_wolf_threat_count = 0
	_monitor_throttle_counter = 0
	_next_villager_id = 1
	# Default-on; setup_for_test() flips it to false after _reset_state runs.
	# Without this reset, a reused instance could leak the test setting into a
	# real setup() call and silently disable task generation.
	_task_gen_enabled = true
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
		_log({"event": "campfire_out", "consecutive_nights": campfire_out_nights,
			"wood_consumed": wood_consumed, "wood_needed": _balance.wood_consumed_by_campfire_per_night})
		if campfire_out_nights >= _balance.max_campfire_out_nights:
			game_lost.emit("Campfire out for %d consecutive nights" % campfire_out_nights)
	else:
		campfire_out_nights = 0
		_log({"event": "campfire_ok", "wood_consumed": wood_consumed})
	_apply_food_spoilage()
	run_monitor_check()

func _apply_food_spoilage() -> void:
	var food_cap: int = _balance.food_base_capacity + _storage_count * _balance.food_capacity_per_storage
	var food: int = store.get_resource("food")
	if food <= food_cap:
		return
	var divisor: int = max(1, _balance.food_spoilage_divisor)
	var spoiled: int = int(ceil(float(food - food_cap) / float(divisor)))
	store.consume_resource("food", spoiled)
	_log({"event": "food_spoiled", "amount": spoiled,
		"above_cap": food - food_cap, "cap": food_cap, "remaining": store.get_resource("food")})

func _resolve_hunger() -> void:
	for v in villagers:
		var hunger_before: int = v.hunger
		var consumed := store.consume_resource("food", _balance.food_consumed_per_villager_per_night)
		var fed: bool = consumed == _balance.food_consumed_per_villager_per_night
		if fed:
			v.hunger = maxi(0, v.hunger - 1)
		else:
			v.hunger += 1
		_log({"event": "night_hunger", "villager": v.name, "fed": fed,
			"hunger": v.hunger, "hunger_delta": v.hunger - hunger_before})
	_update_hungry_count()
	for v in villagers:
		if v.hunger >= _balance.max_hunger:
			game_lost.emit("A villager starved")
			return

func _on_night_started(_day: int) -> void:
	resolve_night()
	if nature != null and nature.check_wolf_threat(campfire_out_nights):
		_apply_wolf_disruption()

func _apply_wolf_disruption() -> void:
	if villagers.is_empty():
		return
	# Count the threat regardless of mitigation — planner uses this to gate
	# fence construction so we only fortify after the wolves prove they're a
	# real problem.
	_wolf_threat_count += 1
	# Mix day + threat-count + village size so multi-strike days don't always
	# hit the same villager and population changes shift the target distribution.
	var rng := RandomNumberGenerator.new()
	rng.seed = game_time.day * 31 + _wolf_threat_count * 7 + villagers.size()
	var idx: int = rng.randi_range(0, villagers.size() - 1)
	var raw: int = _balance.wolf_hunger_disruption
	var damage: int = raw
	if _watchtower_count > 0:
		damage = (damage + 1) / 2  # halve (rounding up keeps damage >= 1 for raw=1)
	var fence_mult: float = pow(1.0 - _balance.fence_wolf_damage_reduction, float(_fence_count))
	damage = int(round(float(damage) * fence_mult))
	if damage <= 0:
		_log({"event": "wolf_threat_mitigated", "raw_damage": raw,
			"fences": _fence_count, "watchtowers": _watchtower_count})
		return
	villagers[idx].hunger += damage
	_log({"event": "wolf_threat", "disrupted_villager": villagers[idx].name,
		"raw_damage": raw, "mitigated_damage": damage,
		"fences": _fence_count, "watchtowers": _watchtower_count,
		"new_hunger": villagers[idx].hunger})
	_update_hungry_count()
	# Wolf damage runs AFTER _resolve_hunger's starvation check, so a wolf-pushed
	# overflow has to be re-checked here or the game would survive one extra night.
	if villagers[idx].hunger >= _balance.max_hunger:
		game_lost.emit("A villager starved")

func _on_day_started(_day: int) -> void:
	# Hunt tasks pinned to last-day's deer positions are stale by now.
	# return_home / refuel_campfire used to be cancelled here too but those
	# task types were removed in the Phase C cleanup (Codex/Claude: do not
	# resurrect them — see ROADMAP anti-features).
	_cancel_open_tasks_of_type("hunt_deer", "stale_at_day_start")
	# Purge COMPLETED/CANCELLED tasks so the board doesn't accumulate forever.
	# Only OPEN/CLAIMED tasks survive — those are the only ones the planner
	# and scorer ever look at anyway.
	board.clear_stale()
	_update_nature_for_day(_day)
	if nature != null:
		wildlife_changed.emit(nature.get_animals_as_dicts())
	_run_construction_planner()
	_grow_population_if_possible()

func _run_construction_planner() -> void:
	if _planner == null or not _task_gen_enabled:
		return
	var decision: Dictionary = _planner.plan(self)
	if decision.is_empty():
		return
	var pos: Vector2i = decision["pos"]
	world_gen.set_tile(pos.x, pos.y, WorldGenerator.TileType.BUILD_SITE)
	if pathfinding:
		pathfinding.set_point_walkable(pos, false)
	tile_changed.emit(pos, WorldGenerator.TileType.BUILD_SITE)
	var task: Task = board.create_task(decision["task_type"], pos, game_time.tick)
	task.approach_tile = world_gen.find_walkable_adjacent(pos)
	_log({"event": "construction_planned", "building": decision["type"],
		"pos": [pos.x, pos.y], "wood_cost": decision["wood_cost"]})

func _update_nature_for_day(day: int) -> void:
	if nature == null or world_gen == null:
		return
	var animals_before: Array[Dictionary] = nature.get_animals_as_dicts()
	var blocked: Array[Vector2i] = []
	for v in villagers:
		blocked.append(v.tile_position)
	for task in board._tasks:
		if task.status == Task.Status.OPEN or task.status == Task.Status.CLAIMED:
			blocked.append(task.approach_tile)
	var changes: Array[Dictionary] = nature.update_day(day, world_gen, blocked)
	for change in changes:
		var pos: Vector2i = change["pos"]
		var tile_type: int = change["type"]
		if pathfinding:
			pathfinding.set_point_walkable(pos, false)
		tile_changed.emit(pos, tile_type)
		var type_name: String = "tree" if tile_type == WorldGenerator.TileType.TREE else "berry_bush"
		_log({"event": "regrowth", "type": type_name, "pos": [pos.x, pos.y]})
	_cancel_tasks_with_stale_approach()
	_diff_log_animals(animals_before, nature.get_animals_as_dicts())
	run_monitor_check()

func _cancel_tasks_with_stale_approach() -> void:
	# Regrowth can plant a tree/bush on a tile that was already chosen as the
	# approach for another task — leaving the task pointing at an unwalkable
	# tile. Cancel both OPEN (free) and CLAIMED (release the villager) tasks
	# so monitor stays clean and the work can be re-scheduled next tick.
	for task in board._tasks:
		var was_claimed: bool = task.status == Task.Status.CLAIMED
		if task.status != Task.Status.OPEN and not was_claimed:
			continue
		if not world_gen.is_in_bounds(task.approach_tile):
			continue
		if world_gen.is_walkable(task.approach_tile.x, task.approach_tile.y):
			continue
		board.cancel_task(task.id)
		if was_claimed:
			for v in villagers:
				if v.current_task_id == task.id:
					v.clear_task()
		_log({"event": "task_cancelled", "task": task.type,
			"reason": "approach_unwalkable_after_regrowth",
			"approach": [task.approach_tile.x, task.approach_tile.y]})

func _diff_log_animals(before: Array[Dictionary], after: Array[Dictionary]) -> void:
	if _logger == null:
		return
	var before_ids: Dictionary = {}
	for a in before:
		before_ids[a["id"]] = a
	var after_ids: Dictionary = {}
	for a in after:
		after_ids[a["id"]] = a
	for id in after_ids:
		if not before_ids.has(id):
			var a: Dictionary = after_ids[id]
			var kind_name: String = "deer" if a["kind"] == WildlifeAgent.Kind.DEER else "wolf"
			_log({"event": kind_name + "_spawned", "id": a["id"], "pos": [a["x"], a["y"]]})
	for id in before_ids:
		if not after_ids.has(id):
			var a: Dictionary = before_ids[id]
			if a["kind"] == WildlifeAgent.Kind.WOLF:
				_log({"event": "wolf_despawned", "id": a["id"], "reason": "age"})

func _cancel_open_tasks_of_type(task_type: String, reason: String = "bulk_cancel") -> void:
	# Bulk-cancel every OPEN task of `task_type`. Emits one task_cancelled event
	# per affected task so audits can attribute cancellations to a cause
	# (day-start cleanup vs. surplus-driven). CLAIMED tasks are left alone so
	# in-flight work isn't interrupted.
	for task in board._tasks:
		if task.type == task_type and task.status == Task.Status.OPEN:
			board.cancel_task(task.id)
			_log({"event": "task_cancelled", "task": task.type,
				"reason": reason, "task_id": task.id})

func _process(delta: float) -> void:
	if game_time == null or game_time.phase == GameTime.Phase.NIGHT:
		return
	if _task_gen_enabled:
		_generate_tasks()
	_tick_villagers(delta)

func _generate_tasks() -> void:
	var food: int = store.get_resource("food")
	var wood: int = store.get_resource("wood")
	# Cancel surplus open tasks only once stock crosses the *surplus* threshold,
	# not the *low* threshold. Between low and surplus we leave existing OPEN
	# tasks alone so idle villagers can keep working — otherwise everyone goes
	# idle the instant we satisfy the survival floor.
	if food >= _balance.food_surplus_threshold:
		_cancel_open_tasks_of_type("gather_food", "food_above_surplus_threshold")
	if wood >= _balance.wood_surplus_threshold:
		_cancel_open_tasks_of_type("chop_tree", "wood_above_surplus_threshold")
	if food < _balance.food_low_threshold:
		for bush_pos in world_gen.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH):
			_try_create_resource_task("gather_food", bush_pos)
	# Hunt tasks generated whenever deer are in range regardless of food level.
	# Scorer deprioritises hunting when food is plentiful; tasks are cancelled
	# each day-start to avoid villagers chasing deer that have already moved.
	if nature != null:
		for animal in nature.animals:
			var a: WildlifeAgent = animal as WildlifeAgent
			if a == null or a.kind != WildlifeAgent.Kind.DEER:
				continue
			var dist: float = Vector2(a.tile_position).distance_to(Vector2(WorldGenerator.HUT_POS))
			if dist <= float(_balance.deer_hunt_radius) and not board.has_task_for_tile(a.tile_position):
				# target == approach (Task._init defaults approach_tile to target).
				board.create_task("hunt_deer", a.tile_position, game_time.tick)
	if wood < _balance.wood_low_threshold:
		for tree_pos in world_gen.get_tiles_of_type(WorldGenerator.TileType.TREE):
			_try_create_resource_task("chop_tree", tree_pos)
	# build_* tasks are created by ConstructionPlanner in _on_day_started.

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
				var score: float = scorer.score_task(v, task, store, game_time)
				board.claim_task(task.id, v.id)
				v.set_task(task)
				_log({"event": "task_claimed", "villager": v.name, "task": task.type,
					"target": [task.target_tile.x, task.target_tile.y], "score": snappedf(score, 0.01)})
				var path: Array[Vector2i] = []
				if pathfinding:
					path = pathfinding.get_path(v.tile_position, task.approach_tile)
				if path.is_empty():
					# Unreachable target — cancel the task and go idle.
					board.cancel_task(task.id)
					v.clear_task()
					_log({"event": "task_cancelled", "villager": v.name, "task": task.type,
						"reason": "unreachable", "target": [task.target_tile.x, task.target_tile.y]})
				else:
					v._path = path
		if v.state == VillagerAgent.State.MOVING_TO_TARGET:
			var arrived = v.tick_movement(delta, v._path, _balance.villager_move_interval)
			if arrived:
				_execute_task_at_target(v)
	# Per-frame monitor check is expensive (BFS-from-HUT per tree/bush) and the
	# anomaly list rarely flips between frames. State-change paths still call
	# run_monitor_check() eagerly; this is only the steady-state poll.
	_monitor_throttle_counter += 1
	if _monitor_throttle_counter >= MONITOR_THROTTLE_FRAMES:
		_monitor_throttle_counter = 0
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
			_log({"event": "task_completed", "villager": v.name, "task": "chop_tree",
				"wood_gained": _balance.wood_per_tree, "wood_total": store.get_resource("wood")})
		"gather_food":
			if nature:
				nature.record_harvest(WorldGenerator.TileType.BERRY_BUSH, task.target_tile, game_time.day)
			world_gen.set_tile(task.target_tile.x, task.target_tile.y, WorldGenerator.TileType.GRASS)
			if pathfinding:
				pathfinding.set_point_walkable(task.target_tile, true)
			tile_changed.emit(task.target_tile, WorldGenerator.TileType.GRASS)
			store.add_resource("food", _balance.food_per_bush)
			_log({"event": "task_completed", "villager": v.name, "task": "gather_food",
				"food_gained": _balance.food_per_bush, "food_total": store.get_resource("food")})
		"hunt_deer":
			if nature:
				var deer: WildlifeAgent = nature.find_animal_at(task.target_tile, WildlifeAgent.Kind.DEER)
				if deer != null:
					nature.remove_animal(deer.id)
					store.add_resource("food", _balance.food_per_deer)
					wildlife_changed.emit(nature.get_animals_as_dicts())
					_log({"event": "deer_hunted", "villager": v.name, "deer_id": deer.id,
						"pos": [task.target_tile.x, task.target_tile.y],
						"food_gained": _balance.food_per_deer, "food_total": store.get_resource("food")})
				else:
					_log({"event": "deer_escaped", "villager": v.name,
						"pos": [task.target_tile.x, task.target_tile.y]})
		"build_house", "build_fence", "build_watchtower", "build_storage":
			if not _execute_build(v, task):
				return
	board.complete_task(task.id)
	v.clear_task()

func _execute_build(v: VillagerAgent, task: Task) -> bool:
	# Returns false if the task was cancelled (caller must `return` to skip
	# the trailing complete_task call). Returns true on successful build.
	var key: String = task.type.replace("build_", "")
	var def: Dictionary = BuildingDefs.BUILDINGS[key]
	if not store.has_enough("wood", def.wood_cost):
		board.cancel_task(task.id)
		v.clear_task()
		_log({"event": "task_cancelled", "villager": v.name, "task": task.type,
			"reason": "insufficient_wood"})
		return false
	store.consume_resource("wood", def.wood_cost)
	world_gen.set_tile(task.target_tile.x, task.target_tile.y, def.tile_type)
	if pathfinding:
		# FENCE is walkable per design; all building tiles are walkable.
		pathfinding.set_point_walkable(task.target_tile, true)
	_apply_building_effect(key)
	tile_changed.emit(task.target_tile, def.tile_type)
	population_changed.emit(villagers.size(), population_capacity)
	_log({"event": "built", "villager": v.name, "building": key,
		"pos": [task.target_tile.x, task.target_tile.y], "wood_spent": def.wood_cost})
	# NOTE: don't call run_monitor_check() here — villager is still in MOVING
	# state with an emptied path until the caller clears it. _tick_villagers
	# calls run_monitor_check() at end of loop instead.
	return true

func _apply_building_effect(key: String) -> void:
	match key:
		"house":
			population_capacity += _balance.population_capacity_per_house
		"fence":
			_fence_count += 1
		"watchtower":
			_watchtower_count += 1
		"storage":
			_storage_count += 1

func _grow_population_if_possible() -> void:
	if not _balance.population_growth_enabled:
		return
	if villagers.size() >= population_capacity:
		return
	if not store.has_enough("food", _balance.food_required_for_new_villager):
		return
	store.consume_resource("food", _balance.food_required_for_new_villager)
	var new_v: VillagerAgent = _add_villager()
	_log({"event": "villager_born", "name": new_v.name, "id": new_v.id,
		"food_consumed": _balance.food_required_for_new_villager,
		"population": villagers.size(), "capacity": population_capacity})
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
