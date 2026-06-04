class_name VillageSimulation
extends Node

const SimulationMonitorScript = preload("res://scripts/sim/simulation_monitor.gd")
const NatureSystemScript = preload("res://scripts/sim/nature_system.gd")
const SimulationSnapshotScript = preload("res://scripts/sim/simulation_snapshot.gd")
const NightResolutionScript = preload("res://scripts/sim/night_resolution.gd")
const WolfThreatSystemScript = preload("res://scripts/sim/wolf_threat_system.gd")
const PolicyResolverScript = preload("res://scripts/sim/policy_resolver.gd")
const TaskResolutionScript = preload("res://scripts/sim/task_resolution.gd")
const EventDeckScript = preload("res://scripts/sim/event_deck.gd")
const EventEffectsScript = preload("res://scripts/sim/event_effects.gd")

signal game_won()
signal game_lost(reason: String)
signal tile_changed(pos: Vector2i, new_type: int)
signal population_changed(current: int, capacity: int)
signal hunger_changed(hungry_count: int)
signal monitor_anomalies_changed(anomalies: Array[Dictionary])
signal wildlife_changed(animals: Array[Dictionary])
signal event_pending(event: Dictionary)
signal event_resolved(result: Dictionary)
signal policy_changed(policy: String, day: int)
signal daily_summary(summary: Dictionary)
signal activity_logged(entry: Dictionary)

var store: ResourceStore
var game_time: GameTime
var board: TaskBoard
var world_gen: WorldGenerator
var pathfinding: PathfindingService
var scorer: UtilityScorer
var monitor: RefCounted
var nature: RefCounted
var event_deck: RefCounted
var _planner: ConstructionPlanner

var villagers: Array[VillagerAgent] = []
var monitor_anomalies: Array[Dictionary] = []
var hungry_villagers: int = 0
var campfire_out_nights: int = 0
var population_capacity: int = 3
var zero_food_days: int = 0
var zero_morale_days: int = 0
var zero_security_days: int = 0
var active_policy: String = PolicyDefs.default_policy()
var last_policy_choice_day: int = 0
var pending_event: Dictionary = {}
var active_event_effects: Array[Dictionary] = []
var last_event_result: Dictionary = {}
var last_event_day: int = 0
var _fence_count: int = 0
var _watchtower_count: int = 0
var _storage_count: int = 0
# Counts how many times wolves actually closed in on the village while the
# campfire was out. Drives reactive fence construction so the planner doesn't
# waste wood on perimeter defense before any real threat occurs.
var _wolf_threat_count: int = 0

var _balance: BalanceData
var _task_gen_enabled: bool = true
# Latches once the run ends so game_won / game_lost fire exactly once. Without
# it, _on_day_started re-emits game_won every day after the win day, and a night
# that kills several villagers can emit game_lost once per death.
var _game_over: bool = false
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
	var entry := data.duplicate(true)
	if not entry.has("tick"):
		entry["tick"] = game_time.tick if game_time else 0
	if not entry.has("day"):
		entry["day"] = game_time.day if game_time else 0
	if not entry.has("phase"):
		entry["phase"] = game_time.get_phase_name() if game_time else ""
	activity_logged.emit(entry.duplicate(true))
	if _logger == null:
		return
	_logger.log_event(entry)

func setup(balance: BalanceData, p_world_gen: WorldGenerator, p_pathfinding: PathfindingService) -> void:
	_reset_state()
	_balance = balance
	world_gen = p_world_gen
	pathfinding = p_pathfinding

	store = ResourceStore.new()
	store.setup(balance.starting_wood, balance.starting_fresh_food, balance.starting_stored_food)
	store.setup_strategic(
		balance.starting_population,
		balance.starting_food,
		balance.starting_wood,
		balance.starting_security,
		balance.starting_morale
	)

	game_time = GameTime.new()
	game_time.setup(balance.day_duration_seconds, balance.night_duration_seconds, balance.days_per_season)
	add_child(game_time)
	game_time.night_started.connect(_on_night_started)
	game_time.day_started.connect(_on_day_started)

	board = TaskBoard.new()
	scorer = UtilityScorer.new()
	monitor = SimulationMonitorScript.new()
	nature = NatureSystemScript.new()
	nature.setup(balance, p_pathfinding)
	event_deck = EventDeckScript.new()
	if not event_deck.load_from_file("res://data/events.json"):
		push_warning("VillageSimulation: event deck disabled because data/events.json failed to load")
	_planner = ConstructionPlanner.new()
	population_capacity = balance.starting_population_capacity

	for i in range(balance.villager_count):
		_add_villager()
	run_monitor_check()

func setup_for_test(wood: int, food: int, villager_count: int) -> void:
	_reset_state()
	var balance = BalanceData.new()
	balance.starting_wood = wood
	balance.villager_count = villager_count
	balance.days_per_season = 5
	balance.food_consumed_per_villager_per_night = 1
	balance.wood_consumed_by_campfire_per_night = 2
	balance.max_campfire_out_nights = 2
	balance.fresh_food_spoilage_per_night = 0  # disable spoilage in unit tests
	balance.starting_population_capacity = villager_count
	balance.population_capacity_per_house = 2
	balance.food_required_for_new_villager = 2
	balance.max_hunger = 3
	balance.wolf_spawn_day = 999
	balance.wolf_threat_radius = 0
	balance.deer_max_count = 0
	balance.deer_spawn_per_day = 0
	balance.food_per_deer = 3

	store = ResourceStore.new()
	store.setup(wood, food, 0)  # all food as fresh_food in test scenarios
	store.setup_strategic(villager_count, food, wood, 50, 60)

	game_time = GameTime.new()
	game_time.setup(10.0, 5.0, balance.days_per_season)
	add_child(game_time)
	game_time.night_started.connect(_on_night_started)
	game_time.day_started.connect(_on_day_started)


	board = TaskBoard.new()
	scorer = UtilityScorer.new()
	monitor = SimulationMonitorScript.new()
	nature = NatureSystemScript.new()
	nature.setup(balance)
	event_deck = EventDeckScript.new()
	event_deck.load_from_file("res://data/events.json")
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
	population_capacity = 5
	zero_food_days = 0
	zero_morale_days = 0
	zero_security_days = 0
	active_policy = PolicyDefs.default_policy()
	last_policy_choice_day = 0
	pending_event.clear()
	active_event_effects.clear()
	last_event_result.clear()
	last_event_day = 0
	_fence_count = 0
	_watchtower_count = 0
	_storage_count = 0
	_wolf_threat_count = 0
	_monitor_throttle_counter = 0
	_game_over = false
	_next_villager_id = 1
	# Default-on; setup_for_test() flips it to false after _reset_state runs.
	# Without this reset, a reused instance could leak the test setting into a
	# real setup() call and silently disable task generation.
	_task_gen_enabled = true
	monitor = null
	nature = null
	event_deck = null
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

func resolve_night() -> void:
	NightResolutionScript.resolve(self)
	run_monitor_check()

func _apply_food_spoilage() -> void:
	# Thin wrapper kept on the sim because test_building_effects.gd exercises
	# the spoilage formula in isolation. The full per-night sequence (hunger →
	# campfire → spoilage) lives in NightResolution.resolve().
	NightResolutionScript.apply_food_spoilage(self)

func end_game_won() -> void:
	if _game_over:
		return
	_game_over = true
	game_won.emit()

func end_game_lost(reason: String) -> void:
	if _game_over:
		return
	_game_over = true
	game_lost.emit(reason)

func is_game_over() -> bool:
	return _game_over

func _on_night_started(_day: int) -> void:
	if _game_over:
		return
	resolve_night()
	if nature != null and nature.check_wolf_threat(campfire_out_nights):
		_apply_wolf_disruption()

func _apply_wolf_disruption() -> void:
	# Thin wrapper kept on the sim because test_building_effects.gd and
	# test_phase_a_fixes.gd exercise wolf damage in isolation. The body lives
	# in WolfThreatSystem so the file stays under the 600-line guardrail.
	WolfThreatSystemScript.apply_disruption(self)

func _on_day_started(_day: int) -> void:
	if _game_over:
		return
	_expire_event_effects_before_day(_day)
	var policy_summary := _resolve_policy_daily_resources()
	_resolve_strategic_daily_state()
	if _game_over:
		# A strategic loss streak fired during daily resolution above.
		return
	# Win when the player survives through the final MVP day.
	if _day > get_days_to_win():
		end_game_won()
		return
	_draw_event_for_day(_day)
	_decrement_event_effects_after_day(_day)
	policy_summary["day"] = _day
	policy_summary["policy"] = active_policy
	policy_summary["policy_name"] = PolicyDefs.get_display_name(active_policy)
	policy_summary["resources"] = {
		"population": store.get_resource("population"),
		"food": store.get_resource("food"),
		"wood": store.get_resource("wood"),
		"security": store.get_resource("security"),
		"morale": store.get_resource("morale"),
	}
	daily_summary.emit(policy_summary)
	# Purge COMPLETED/CANCELLED tasks so the board doesn't accumulate forever.
	# Only OPEN/CLAIMED tasks survive — those are the only ones the planner
	# and scorer ever look at anyway.
	board.clear_stale()
	_update_nature_for_day(_day)
	if nature != null:
		wildlife_changed.emit(nature.get_animals_as_dicts())
	_cancel_stale_hunt_tasks()
	_run_construction_planner()
	_grow_population_if_possible()

func get_days_to_win() -> int:
	return _balance.days_per_season * 4

func get_strategic_population() -> int:
	return store.get_resource("population") if store else 0

func get_living_villagers() -> Array[VillagerAgent]:
	var living: Array[VillagerAgent] = []
	for v in villagers:
		if v.status != VillagerAgent.Status.DEAD:
			living.append(v)
	return living

func get_living_population() -> int:
	return get_living_villagers().size()

func get_dead_population() -> int:
	return maxi(0, villagers.size() - get_living_population())

func get_visible_population() -> int:
	return get_living_population()

func has_population_mismatch() -> bool:
	return get_strategic_population() != get_visible_population()

func can_change_policy(day: int = -1) -> bool:
	var check_day: int = day
	if check_day < 0 and game_time != null:
		check_day = game_time.day
	return PolicyDefs.can_change_on_day(check_day) and last_policy_choice_day != check_day

func set_policy(policy: String) -> bool:
	if not PolicyDefs.is_valid(policy):
		return false
	if not can_change_policy():
		return false
	active_policy = policy
	last_policy_choice_day = game_time.day if game_time != null else 1
	policy_changed.emit(active_policy, last_policy_choice_day)
	_log({
		"event": "policy_selected",
		"policy": active_policy,
		"policy_name": PolicyDefs.get_display_name(active_policy),
	})
	return true

func has_pending_event() -> bool:
	return not pending_event.is_empty()

func resolve_pending_event(option_id: String) -> Dictionary:
	if pending_event.is_empty():
		return {
			"ok": false,
			"error": "no_pending_event",
			"option_id": option_id,
		}
	var event_id: String = str(pending_event.get("id", ""))
	var result: Dictionary = EventEffectsScript.apply_option(self, pending_event, option_id)
	if not bool(result.get("ok", false)):
		return result
	pending_event = {}
	last_event_result = result.duplicate(true)
	last_event_day = game_time.day if game_time != null else last_event_day
	_log({
		"event": "event_resolved",
		"event_id": event_id,
		"option_id": option_id,
		"title": result.get("event_title", ""),
		"result_text": result.get("result_text", ""),
		"short_term_started": not (result.get("short_term_started", {}) as Dictionary).is_empty(),
	})
	event_resolved.emit(last_event_result.duplicate(true))
	run_monitor_check()
	return last_event_result.duplicate(true)

func apply_strategic_resource_delta(resource_name: String, delta: int) -> void:
	store.add_resource(resource_name, delta)
	if resource_name == "population":
		_emit_population_changed()
		if store.get_resource("population") <= 0:
			end_game_lost("Population reached 0")

func mark_villager_dead(villager: VillagerAgent, reason: String) -> void:
	if villager == null or villager.status == VillagerAgent.Status.DEAD:
		return
	if villager.current_task_id != -1 and board != null:
		board.cancel_task(villager.current_task_id)
	villager.status = VillagerAgent.Status.DEAD
	villager.clear_task()
	apply_strategic_resource_delta("population", -1)
	_update_hungry_count()
	_log({
		"event": "villager_died",
		"villager": villager.name,
		"id": villager.id,
		"reason": reason,
		"population": get_strategic_population(),
		"living_population": get_living_population(),
		"hunger": villager.hunger,
	})
	run_monitor_check()

func _resolve_policy_daily_resources() -> Dictionary:
	return PolicyResolverScript.resolve_daily(self)

func _modified_output_amount(v: VillagerAgent, output_type: String, base: int) -> int:
	return PolicyResolverScript.modified_output_amount(self, v, output_type, base)

func _find_recoverable_villager() -> VillagerAgent:
	return PolicyResolverScript.find_recoverable_villager(self)

func _roll_percent(tag: String, villager_id: int) -> int:
	return PolicyResolverScript.roll_percent(self, tag, villager_id)

func _resolve_strategic_daily_state() -> void:
	if store == null or _balance == null:
		return
	if store.get_resource("population") <= 0:
		end_game_lost("Population reached 0")
		return
	zero_food_days = _update_zero_streak("food", zero_food_days)
	zero_morale_days = _update_zero_streak("morale", zero_morale_days)
	zero_security_days = _update_zero_streak("security", zero_security_days)
	var limit: int = _balance.zero_resource_loss_days
	if zero_food_days >= limit:
		end_game_lost("Food stayed at 0 for %d days" % zero_food_days)
	elif zero_morale_days >= limit:
		end_game_lost("Morale stayed at 0 for %d days" % zero_morale_days)
	elif zero_security_days >= limit:
		end_game_lost("Security stayed at 0 for %d days" % zero_security_days)

func _update_zero_streak(resource_name: String, current_streak: int) -> int:
	if store.get_resource(resource_name) <= 0:
		return current_streak + 1
	return 0

func _draw_event_for_day(day: int) -> void:
	if event_deck == null or has_pending_event() or last_event_day == day:
		return
	if day < 3 or day % 3 != 0:
		return
	var event: Dictionary = event_deck.draw_for_day(_balance.world_seed, day, active_event_effects)
	if event.is_empty():
		return
	pending_event = event
	last_event_day = day
	_log({
		"event": "event_drawn",
		"event_id": pending_event.get("id", ""),
		"category": pending_event.get("category", ""),
		"title": pending_event.get("title", ""),
	})
	event_pending.emit(pending_event.duplicate(true))

func _expire_event_effects_before_day(day: int) -> void:
	if active_event_effects.is_empty():
		return
	var kept: Array[Dictionary] = []
	for effect in active_event_effects:
		if int(effect.get("remaining_days", 0)) > 0:
			kept.append(effect)
			continue
		_log({
			"event": "event_effect_expired",
			"type": effect.get("type", ""),
			"source_event_id": effect.get("source_event_id", ""),
			"label": effect.get("label", ""),
			"day": day,
		})
	active_event_effects = kept

func _decrement_event_effects_after_day(day: int) -> void:
	for effect in active_event_effects:
		if EventEffectsScript.effect_is_active(effect, day):
			effect["remaining_days"] = maxi(0, int(effect.get("remaining_days", 0)) - 1)
			effect["last_applied_day"] = day

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
	var season: int = int(game_time.current_season) if game_time else 0
	var changes: Array[Dictionary] = nature.update_day(day, world_gen, blocked, season)
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

func _cancel_stale_hunt_tasks() -> void:
	if nature == null:
		return
	for task in board._tasks:
		if task.type != "hunt_deer" or task.status != Task.Status.OPEN:
			continue
		var reason := _hunt_task_invalid_reason(task)
		if reason == "":
			continue
		board.cancel_task(task.id)
		_log({"event": "task_cancelled", "task": task.type,
			"reason": reason, "task_id": task.id})

func _hunt_task_invalid_reason(task: Task) -> String:
	if nature.find_animal_at(task.target_tile, WildlifeAgent.Kind.DEER) == null:
		return "deer_no_longer_at_target"
	var dist: float = Vector2(task.target_tile).distance_to(Vector2(WorldGenerator.HUT_POS))
	if dist > float(_balance.deer_hunt_radius):
		return "deer_out_of_hunt_radius"
	if not world_gen.is_in_bounds(task.approach_tile):
		return "hunt_approach_out_of_bounds"
	if not world_gen.is_walkable(task.approach_tile.x, task.approach_tile.y):
		return "hunt_approach_unwalkable"
	return ""

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
	var total_food: int = store.get_resource("food")
	var wood: int = store.get_resource("wood")
	var season: GameTime.Season = game_time.current_season if game_time else GameTime.Season.SPRING
	# Cancel surplus open tasks only once stock crosses the *surplus* threshold,
	# or the active policy's higher task target. Between low and cancel target,
	# existing OPEN tasks remain available so policy intent can keep villagers
	# visibly working without changing the AI state machine.
	if total_food >= _food_task_cancel_threshold():
		_cancel_open_tasks_of_type("gather_food", "food_above_surplus_threshold")
		_cancel_open_tasks_of_type("hunt_deer", "food_above_surplus_threshold")
	if wood >= _wood_task_cancel_threshold():
		_cancel_open_tasks_of_type("chop_tree", "wood_above_surplus_threshold")
	# Berry bushes go dormant in winter — no gather_food tasks in winter season.
	var food_task_limit := _food_task_generation_limit(total_food)
	if food_task_limit > 0 and season != GameTime.Season.WINTER:
		_try_create_resource_tasks_limited(
			"gather_food",
			world_gen.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH),
			food_task_limit
		)
	# Hunt only while food is below surplus. Existing OPEN hunt tasks are
	# cancelled once food is plentiful; CLAIMED hunters finish their current run.
	var hunt_task_limit := _hunt_task_generation_limit(total_food)
	if hunt_task_limit > 0:
		_try_create_hunt_tasks_limited(hunt_task_limit)
	var wood_task_limit := _wood_task_generation_limit(wood)
	if wood_task_limit > 0:
		_try_create_resource_tasks_limited(
			"chop_tree",
			world_gen.get_tiles_of_type(WorldGenerator.TileType.TREE),
			wood_task_limit
		)
	if active_policy == PolicyDefs.DEFENSE_FIRST and store.get_resource("security") < 60:
		_try_create_walkable_task("guard_watch", WorldGenerator.CAMPFIRE_POS)
	if active_policy == PolicyDefs.REST_FIRST and _find_recoverable_villager() != null:
		_try_create_walkable_task("tend_villager", WorldGenerator.HUT_POS)
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

func _try_create_resource_tasks_limited(task_type: String, target_tiles: Array[Vector2i], limit_override: int = -1) -> void:
	var limit: int = maxi(1, limit_override if limit_override > 0 else _balance.max_open_resource_tasks_per_type)
	var active_count := _count_active_tasks_of_type(task_type)
	if active_count >= limit:
		return
	var candidates := target_tiles.duplicate()
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := a.distance_squared_to(WorldGenerator.HUT_POS)
		var db := b.distance_squared_to(WorldGenerator.HUT_POS)
		if da == db:
			return a.y < b.y if a.x == b.x else a.x < b.x
		return da < db
	)
	for target_tile in candidates:
		if active_count >= limit:
			return
		var before := board._tasks.size()
		_try_create_resource_task(task_type, target_tile)
		if board._tasks.size() > before:
			active_count += 1

func _try_create_hunt_tasks_limited(limit_override: int = -1) -> void:
	if nature == null:
		return
	var limit: int = maxi(1, limit_override if limit_override > 0 else _balance.max_open_resource_tasks_per_type)
	var active_count := _count_active_tasks_of_type("hunt_deer")
	if active_count >= limit:
		return
	var candidates: Array[WildlifeAgent] = []
	for animal in nature.animals:
		var a: WildlifeAgent = animal as WildlifeAgent
		if a == null or a.kind != WildlifeAgent.Kind.DEER:
			continue
		var dist: float = Vector2(a.tile_position).distance_to(Vector2(WorldGenerator.HUT_POS))
		if dist <= float(_balance.deer_hunt_radius) and not board.has_task_for_tile(a.tile_position):
			candidates.append(a)
	candidates.sort_custom(func(a: WildlifeAgent, b: WildlifeAgent) -> bool:
		var da := a.tile_position.distance_squared_to(WorldGenerator.HUT_POS)
		var db := b.tile_position.distance_squared_to(WorldGenerator.HUT_POS)
		if da == db:
			return a.tile_position.y < b.tile_position.y if a.tile_position.x == b.tile_position.x else a.tile_position.x < b.tile_position.x
		return da < db
	)
	for deer in candidates:
		if active_count >= limit:
			return
		# target == approach (Task._init defaults approach_tile to target).
		board.create_task("hunt_deer", deer.tile_position, game_time.tick)
		active_count += 1

func _count_active_tasks_of_type(task_type: String) -> int:
	var count := 0
	for task in board._tasks:
		if task.type == task_type and (task.status == Task.Status.OPEN or task.status == Task.Status.CLAIMED):
			count += 1
	return count

func _policy_wants_food_tasks() -> bool:
	return active_policy == PolicyDefs.FOOD_FIRST or active_policy == PolicyDefs.EXPLORE_FOREST

func _policy_wants_wood_tasks() -> bool:
	return active_policy == PolicyDefs.WOOD_FIRST or active_policy == PolicyDefs.EXPLORE_FOREST

func _food_task_cancel_threshold() -> int:
	return _balance.policy_food_task_target if _policy_wants_food_tasks() else _balance.food_surplus_threshold

func _wood_task_cancel_threshold() -> int:
	return _balance.policy_wood_task_target if _policy_wants_wood_tasks() else _balance.wood_surplus_threshold

func _food_task_generation_limit(total_food: int) -> int:
	if total_food < _balance.food_low_threshold:
		return _balance.max_open_resource_tasks_per_type
	if _policy_wants_food_tasks() and total_food < _balance.policy_food_task_target:
		return _balance.max_policy_open_tasks_per_type
	return 0

func _hunt_task_generation_limit(total_food: int) -> int:
	if total_food < _balance.food_surplus_threshold:
		return _balance.max_open_resource_tasks_per_type
	if _policy_wants_food_tasks() and total_food < _balance.policy_food_task_target:
		return _balance.max_policy_open_tasks_per_type
	return 0

func _wood_task_generation_limit(wood: int) -> int:
	if wood < _balance.wood_low_threshold:
		return _balance.max_open_resource_tasks_per_type
	if _policy_wants_wood_tasks() and wood < _balance.policy_wood_task_target:
		return _balance.max_policy_open_tasks_per_type
	return 0

func _try_create_walkable_task(task_type: String, target_tile: Vector2i) -> void:
	if board.has_active_task_of_type(task_type):
		return
	if world_gen == null or not world_gen.is_in_bounds(target_tile):
		return
	if not world_gen.is_walkable(target_tile.x, target_tile.y):
		return
	board.create_task(task_type, target_tile, game_time.tick)

func _tick_villagers(delta: float) -> void:
	for v in villagers:
		if not v.can_work():
			if v.current_task_id != -1:
				board.cancel_task(v.current_task_id)
				v.clear_task()
			continue
		if v.state == VillagerAgent.State.IDLE:
			var task: Task = v.pick_best_task(board, store, game_time, scorer, active_policy)
			if task != null:
				var score: float = scorer.score_task(v, task, store, game_time, active_policy)
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
	TaskResolutionScript.execute_task_at_target(self, v)

func _grow_population_if_possible() -> void:
	if not _balance.population_growth_enabled:
		return
	if get_living_population() >= population_capacity:
		return
	var req: int = _balance.food_required_for_new_villager
	if store.get_resource("food") < req:
		return
	store.consume_food(req, false)
	var new_v: VillagerAgent = _add_villager()
	apply_strategic_resource_delta("population", 1)
	_log({"event": "villager_born", "name": new_v.name, "id": new_v.id,
		"food_consumed": _balance.food_required_for_new_villager,
		"population": get_strategic_population(), "capacity": population_capacity})
	run_monitor_check()

func _add_villager() -> VillagerAgent:
	var names = ["Alice", "Bob", "Carol", "Drew", "Eli", "Fern", "Gale", "Hana"]
	var idx := _next_villager_id - 1
	var name: String = names[idx] if idx < names.size() else "Villager %d" % _next_villager_id
	var pos: Vector2i = find_valid_spawn_tile(idx)
	var villager := VillagerAgent.new(_next_villager_id, name, pos, JobDefs.default_for_index(idx))
	_next_villager_id += 1
	villagers.append(villager)
	_emit_population_changed()
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
	hungry_villagers = HungerSystem.count_hungry(villagers)
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

func inspect_tile(pos: Vector2i) -> Dictionary:
	var info := {
		"in_bounds": false,
		"x": pos.x,
		"y": pos.y,
		"tile_type": -1,
		"tile_name": "Out of bounds",
		"walkable": false,
		"feature_kind": "void",
		"feature_label": "Out of bounds",
		"villagers": [],
		"animals": [],
		"tasks": [],
	}
	if world_gen == null or not world_gen.is_in_bounds(pos):
		return info
	var tile_type: int = world_gen.get_tile(pos.x, pos.y)
	info["in_bounds"] = true
	info["tile_type"] = tile_type
	info["tile_name"] = WorldGenerator.get_tile_type_name(tile_type)
	info["walkable"] = world_gen.is_walkable(pos.x, pos.y)
	match tile_type:
		WorldGenerator.TileType.TREE:
			info["feature_kind"] = "resource"
			info["feature_label"] = "Wood source"
		WorldGenerator.TileType.BERRY_BUSH:
			info["feature_kind"] = "resource"
			info["feature_label"] = "Food source"
		WorldGenerator.TileType.HUT, WorldGenerator.TileType.CAMPFIRE, WorldGenerator.TileType.HOUSE, WorldGenerator.TileType.FENCE, WorldGenerator.TileType.WATCHTOWER, WorldGenerator.TileType.STORAGE, WorldGenerator.TileType.BUILD_SITE:
			info["feature_kind"] = "building"
			info["feature_label"] = WorldGenerator.get_tile_type_name(tile_type)
		WorldGenerator.TileType.BLOCKED:
			info["feature_kind"] = "terrain"
			info["feature_label"] = "Rocky ground"
		_:
			info["feature_kind"] = "terrain"
			info["feature_label"] = WorldGenerator.get_tile_type_name(tile_type)
	for v in villagers:
		if v.tile_position != pos:
			continue
		info["villagers"].append({
			"id": v.id,
			"name": v.name,
			"job": v.job,
			"job_name": JobDefs.get_display_name(v.job),
			"status": v.get_status_name(),
			"alive": v.status != VillagerAgent.Status.DEAD,
		})
	if nature != null:
		for a in nature.animals:
			if a.tile_position != pos:
				continue
			info["animals"].append({
				"id": a.id,
				"kind": int(a.kind),
				"kind_name": "Wolf" if a.kind == WildlifeAgent.Kind.WOLF else "Deer",
			})
	if board != null:
		for task in board._tasks:
			if task.status != Task.Status.OPEN and task.status != Task.Status.CLAIMED:
				continue
			var relation := ""
			if task.target_tile == pos and task.approach_tile == pos:
				relation = "target+approach"
			elif task.target_tile == pos:
				relation = "target"
			elif task.approach_tile == pos:
				relation = "approach"
			if relation == "":
				continue
			info["tasks"].append({
				"id": task.id,
				"type": task.type,
				"status": Task.Status.keys()[task.status].to_lower(),
				"claimed_by": task.claimed_by,
				"relation": relation,
				"target_x": task.target_tile.x,
				"target_y": task.target_tile.y,
				"approach_x": task.approach_tile.x,
				"approach_y": task.approach_tile.y,
			})
	return info

func _emit_population_changed() -> void:
	population_changed.emit(get_visible_population(), population_capacity)
