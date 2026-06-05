extends GutTest

# Phase B regression: save/load now snapshots the full world grid, derives
# building counters from tile counts, and resets in-flight task/villager
# state on load (no task restoration, villagers idle).

var sim: VillageSimulation
var wg: WorldGenerator
var pf: PathfindingService

func before_each() -> void:
	var balance := BalanceData.new()
	balance.starting_wood = 10
	balance.starting_fresh_food = 8
	balance.starting_stored_food = 0
	balance.villager_count = 3
	balance.starting_population_capacity = 3
	balance.day_duration_seconds = 10.0
	balance.night_duration_seconds = 5.0
	balance.days_per_season = 5
	wg = WorldGenerator.new()
	wg.generate_fixed()
	pf = PathfindingService.new()
	pf.setup(wg)
	sim = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)

func test_round_trip_preserves_grid_byte_for_byte() -> void:
	# Mutate world: turn a few trees into grass, simulate a built fence.
	var trees := wg.get_tiles_of_type(WorldGenerator.TileType.TREE)
	for i in range(min(3, trees.size())):
		wg.set_tile(trees[i].x, trees[i].y, WorldGenerator.TileType.GRASS)
	# Place a synthetic fence tile so building counts have something to derive.
	var fence_pos := Vector2i(0, 0)
	wg.set_tile(fence_pos.x, fence_pos.y, WorldGenerator.TileType.FENCE)
	var sm := SaveManager.new()
	sm.save(sim)
	# Snapshot the post-save grid for comparison.
	var pre_load_grid: Array = []
	for y in range(WorldGenerator.HEIGHT):
		var row: Array = []
		for x in range(WorldGenerator.WIDTH):
			row.append(int(wg.get_tile(x, y)))
		pre_load_grid.append(row)
	# Now mutate AGAIN (these mutations should be wiped by load).
	var bushes := wg.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH)
	if bushes.size() > 0:
		wg.set_tile(bushes[0].x, bushes[0].y, WorldGenerator.TileType.GRASS)
	assert_true(sm.load_into(sim))
	# Grid should match the saved snapshot exactly.
	for y in range(WorldGenerator.HEIGHT):
		for x in range(WorldGenerator.WIDTH):
			assert_eq(int(wg.get_tile(x, y)), int(pre_load_grid[y][x]),
				"tile (%d,%d) mismatch after load" % [x, y])

func test_load_clears_in_flight_tasks_and_idles_villagers() -> void:
	# Give villager 0 an active task and a path.
	var task: Task = sim.board.create_task("chop_tree", Vector2i(1, 1), 0)
	sim.board.claim_task(task.id, sim.villagers[0].id)
	sim.villagers[0].set_task(task)
	sim.villagers[0]._path = [Vector2i(1, 0), Vector2i(1, 1)]
	# Save (which doesn't persist task/path), then re-load.
	var sm := SaveManager.new()
	sm.save(sim)
	assert_true(sm.load_into(sim))
	assert_eq(sim.board._tasks.size(), 0,
		"load should drop the task board entirely")
	for v in sim.villagers:
		assert_eq(v.state, VillagerAgent.State.IDLE)
		assert_eq(v.current_task_id, -1)
		assert_eq(v._path.size(), 0)

func test_building_counters_derived_from_tiles_after_load() -> void:
	# Pre-load, set counters to garbage values to prove the load recomputes.
	wg.set_tile(0, 0, WorldGenerator.TileType.FENCE)
	wg.set_tile(0, 1, WorldGenerator.TileType.FENCE)
	wg.set_tile(0, 2, WorldGenerator.TileType.WATCHTOWER)
	sim._fence_count = 999
	sim._watchtower_count = 999
	sim._storage_count = 999
	var sm := SaveManager.new()
	sm.save(sim)
	# Corrupt them more before loading.
	sim._fence_count = 12345
	assert_true(sm.load_into(sim))
	assert_eq(sim._fence_count, 2,
		"fence count should equal tile count post-load, not stored value")
	assert_eq(sim._watchtower_count, 1)
	assert_eq(sim._storage_count, 0)

func test_load_emits_stock_changed_so_hud_refreshes() -> void:
	# A5 made ResourceStore.setup emit; verify the load path leans on it.
	watch_signals(sim.store)
	var sm := SaveManager.new()
	sm.save(sim)
	sm.load_into(sim)
	# Load refreshes legacy food fields and the strategic MVP resource set.
	assert_signal_emit_count(sim.store, "stock_changed", 11)

func test_save_file_omits_derived_fields() -> void:
	# Sanity: the new save schema should not bother persisting derived counters
	# or the in-flight task list — they're gone or recomputed.
	var sm := SaveManager.new()
	sm.save(sim)
	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.READ)
	var json := JSON.new()
	json.parse(file.get_as_text())
	var data: Dictionary = json.get_data()
	assert_false(data.has("tasks"), "tasks should not be persisted")
	assert_false(data.has("houses"), "buildings live in the grid now")
	assert_false(data.has("fence_count"), "derived from grid post-load")
	assert_true(data.has("tiles"), "grid snapshot is the source of truth")
	assert_true(data.has("fresh_food"), "Phase 1: food split into fresh + stored")
	assert_false(data.has("food"), "old 'food' key must not appear in new saves")
	assert_true(data.has("strategic_resources"), "strategic resources are saved as one grouped field")
	assert_true(data.has("phase_elapsed_seconds"), "current phase progress is required for deterministic load")
	assert_true(data.has("world_seed"), "run seed is required for deterministic load")

func test_save_load_preserves_strategic_state() -> void:
	sim.store.set_resource("population", 8)
	sim.store.set_resource("food", 17)
	sim.store.set_resource("security", 12)
	sim.store.set_resource("morale", 3)
	sim.zero_food_days = 2
	sim.zero_morale_days = 1
	sim.zero_security_days = 0
	var sm := SaveManager.new()
	sm.save(sim)
	sim.store.set_resource("population", 1)
	sim.store.set_resource("food", 1)
	sim.store.set_resource("security", 1)
	sim.store.set_resource("morale", 1)
	sim.zero_food_days = 0
	sim.zero_morale_days = 0
	assert_true(sm.load_into(sim))
	assert_eq(sim.store.get_resource("population"), 8)
	assert_eq(sim.store.get_resource("food"), 17)
	assert_eq(sim.store.get_resource("security"), 12)
	assert_eq(sim.store.get_resource("morale"), 3)
	assert_eq(sim.zero_food_days, 2)
	assert_eq(sim.zero_morale_days, 1)

func test_save_load_preserves_villager_status() -> void:
	sim.villagers[0].status = VillagerAgent.Status.DEAD
	var sm := SaveManager.new()
	sm.save(sim)
	sim.villagers[0].status = VillagerAgent.Status.HEALTHY
	assert_true(sm.load_into(sim))
	assert_eq(sim.villagers[0].status, VillagerAgent.Status.DEAD)

func test_save_load_preserves_clock_progress_and_derives_season() -> void:
	sim.game_time.restore_state(16, GameTime.Phase.NIGHT, 42, 2.5)
	var sm := SaveManager.new()
	sm.save(sim)
	sim.game_time.restore_state(1, GameTime.Phase.DAY, 0, 0.0)
	assert_true(sm.load_into(sim))
	assert_eq(sim.game_time.day, 16)
	assert_eq(sim.game_time.phase, GameTime.Phase.NIGHT)
	assert_eq(sim.game_time.tick, 42)
	assert_eq(sim.game_time.current_season, GameTime.Season.WINTER)
	assert_eq(sim.game_time.get_phase_elapsed_seconds(), 2.5)

func test_loaded_run_resolves_next_day_deterministically() -> void:
	sim.game_time.restore_state(5, GameTime.Phase.NIGHT, 77, 2.0)
	sim.active_policy = PolicyDefs.WOOD_FIRST
	sim.last_policy_choice_day = 1
	sim.last_event_day = 3
	sim.active_event_effects.append({
		"type": "output_multiplier",
		"output_type": "food",
		"multiplier": 0.5,
		"label": "Thin harvest",
		"duration_days": 2,
		"remaining_days": 2,
		"starts_on_day": 6,
	})
	var sm := SaveManager.new()
	sm.save(sim)

	sim.game_time._process(3.0)
	var expected := _daily_fingerprint()

	sim._balance.world_seed = 999999
	assert_true(sm.load_into(sim))
	sim.game_time._process(3.0)
	var actual := _daily_fingerprint()
	for key in expected:
		assert_eq(actual[key], expected[key], "Next-day state mismatch for %s" % key)

func _daily_fingerprint() -> Dictionary:
	var statuses: Array[String] = []
	for villager in sim.villagers:
		statuses.append(villager.get_status_name())
	return {
		"day": sim.game_time.day,
		"phase": sim.game_time.get_phase_name(),
		"season": sim.game_time.get_season_name(),
		"tick": sim.game_time.tick,
		"phase_elapsed_seconds": sim.game_time.get_phase_elapsed_seconds(),
		"world_seed": sim._balance.world_seed,
		"food": sim.store.get_resource("food"),
		"wood": sim.store.get_resource("wood"),
		"security": sim.store.get_resource("security"),
		"morale": sim.store.get_resource("morale"),
		"zero_food_days": sim.zero_food_days,
		"zero_morale_days": sim.zero_morale_days,
		"zero_security_days": sim.zero_security_days,
		"pending_event_id": sim.pending_event.get("id", ""),
		"last_event_day": sim.last_event_day,
		"active_event_effects": _active_effect_fingerprint(),
		"statuses": statuses,
	}

func _active_effect_fingerprint() -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	for effect in sim.active_event_effects:
		effects.append({
			"type": str(effect.get("type", "")),
			"label": str(effect.get("label", "")),
			"remaining_days": int(effect.get("remaining_days", 0)),
			"starts_on_day": int(effect.get("starts_on_day", 0)),
		})
	return effects
