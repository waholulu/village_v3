extends GutTest

# Regression tests for the Phase A consistency-bug fixes. Each test maps
# 1:1 to a finding in the static code review.

# --- A1: cellular smoothing keeps _tile_index in sync ---

func test_tile_index_consistent_with_grid_after_generation() -> void:
	# Walk every cell once and compare the index-derived count to a raw scan.
	# Pre-fix the cellular-smoothing pass wrote to grid directly, so BLOCKED
	# counts diverged from get_tiles_of_type's index-backed reading.
	var wg := WorldGenerator.new()
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	wg.generate_from_balance(balance)
	var types := [
		WorldGenerator.TileType.GRASS, WorldGenerator.TileType.TREE,
		WorldGenerator.TileType.BERRY_BUSH, WorldGenerator.TileType.BLOCKED,
		WorldGenerator.TileType.HUT, WorldGenerator.TileType.CAMPFIRE,
		WorldGenerator.TileType.BUILD_SITE,
	]
	for t in types:
		var indexed: int = wg.count_tiles_of_type(t)
		var raw := 0
		for y in range(WorldGenerator.HEIGHT):
			for x in range(WorldGenerator.WIDTH):
				if wg.grid[y][x] == t:
					raw += 1
		assert_eq(indexed, raw,
			"tile_index out of sync with grid for type %d (indexed=%d raw=%d)" % [t, indexed, raw])

# --- A2: gather_food updates pathfinding after turning bush -> grass ---

func test_gather_food_makes_target_tile_walkable_in_pathfinding() -> void:
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	balance.day_duration_seconds = 0.2
	balance.night_duration_seconds = 0.05
	balance.villager_move_interval = 0.005
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	# Find any bush, harvest it directly via _execute_task_at_target.
	var bushes := wg.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH)
	assert_gt(bushes.size(), 0, "expected at least one bush from default gen")
	var bush_pos: Vector2i = bushes[0]
	var task: Task = sim.board.create_task("gather_food", bush_pos, 0)
	task.approach_tile = wg.find_walkable_adjacent(bush_pos)
	sim.villagers[0].set_task(task)
	sim.board.claim_task(task.id, sim.villagers[0].id)
	sim.villagers[0].tile_position = task.approach_tile
	sim._execute_task_at_target(sim.villagers[0])
	# Tile is now GRASS — pathfinding should let us route through it.
	assert_eq(wg.get_tile(bush_pos.x, bush_pos.y), WorldGenerator.TileType.GRASS)
	var path: Array[Vector2i] = pf.get_path(WorldGenerator.HUT_POS, bush_pos)
	assert_gt(path.size(), 0, "pathfinding should reach a harvested bush tile")

# --- A3: wolf disruption checks starvation immediately ---

func test_wolf_disruption_emits_game_lost_when_pushing_past_max_hunger() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(10, 8, 1)
	sim._balance.wolf_hunger_disruption = 1
	sim.villagers[0].hunger = sim._balance.max_hunger - 1
	watch_signals(sim)
	sim._apply_wolf_disruption()
	assert_signal_emitted(sim, "game_lost",
		"wolf-pushed hunger overflow must emit game_lost on the spot")

# --- A4: _reset_state restores _task_gen_enabled to true ---

func test_task_gen_enabled_resets_to_true_after_test_setup() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(10, 8, 3)
	assert_false(sim._task_gen_enabled, "setup_for_test should disable task gen")
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	balance.day_duration_seconds = 0.2
	balance.night_duration_seconds = 0.05
	balance.villager_move_interval = 0.005
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	sim.setup(balance, wg, pf)
	assert_true(sim._task_gen_enabled,
		"real setup() must re-enable task gen even if instance was used for tests")

# --- A5: ResourceStore.setup emits stock_changed for all three resources ---

func test_resource_store_setup_emits_signals() -> void:
	var store := ResourceStore.new()
	watch_signals(store)
	store.setup(7, 3, 0)
	assert_signal_emit_count(store, "stock_changed", 3)
	# Sanity: all amounts match.
	assert_eq(store.get_resource("wood"), 7)
	assert_eq(store.get_resource("fresh_food"), 3)
	assert_eq(store.get_resource("stored_food"), 0)

# --- A6: build_sites placed before reachability check ---

func test_build_sites_walkability_after_generation() -> void:
	# Pre-fix, build_sites were placed AFTER _ensure_reachable_resources, so
	# a build_site on a corridor could strand resources. Now they go first,
	# so reachability sees the real (build_site-blocked) topology.
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	# All build_sites should be BUILD_SITE tile type post-generation, and
	# none should be walkable (they're solid until built into a House etc.).
	for site in wg.build_sites:
		assert_eq(wg.get_tile(site.x, site.y),
			WorldGenerator.TileType.BUILD_SITE,
			"build_site at (%d,%d) should be BUILD_SITE" % [site.x, site.y])
		assert_false(wg.is_walkable(site.x, site.y),
			"build_site at (%d,%d) should be non-walkable" % [site.x, site.y])
	# And the post-fix reachability check sees them, so every resource must
	# still be reachable.
	assert_true(wg.all_resource_approaches_reachable(),
		"every tree/bush must have a HUT-reachable approach after generation")
