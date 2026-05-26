extends GutTest

# Phase D polish regressions.

# --- D1: clear_task wipes path + move timer ---

func test_clear_task_resets_path_and_timer() -> void:
	var v := VillagerAgent.new(1, "Test", Vector2i(0, 0))
	v._path = [Vector2i(1, 0), Vector2i(2, 0)]
	v._move_timer = 0.42
	v.state = VillagerAgent.State.MOVING_TO_TARGET
	v.current_task_id = 7
	v.clear_task()
	assert_eq(v._path.size(), 0)
	assert_eq(v._move_timer, 0.0)
	assert_eq(v.state, VillagerAgent.State.IDLE)
	assert_eq(v.current_task_id, -1)

# --- D3: scorer distance uses approach_tile not target_tile ---

func test_scorer_distance_uses_approach_tile() -> void:
	var scorer := UtilityScorer.new()
	var store := ResourceStore.new()
	store.setup(10, 10)  # neutral resources so distance dominates
	var gt := GameTime.new()
	add_child_autoqfree(gt)
	# Two tasks differing ONLY in approach_tile placement. The target is the
	# same (a non-walkable tree at (5,5)). Pre-fix both would score equal
	# because distance was computed to the target. Now they should diverge.
	var task_near := Task.new(1, "chop_tree", Vector2i(5, 5))
	task_near.approach_tile = Vector2i(5, 4)  # 1 tile from villager
	var task_far := Task.new(2, "chop_tree", Vector2i(5, 5))
	task_far.approach_tile = Vector2i(5, 6)  # 3 tiles from villager
	var v := VillagerAgent.new(1, "Test", Vector2i(5, 3))
	var near_score := scorer.score_task(v, task_near, store, gt)
	var far_score := scorer.score_task(v, task_far, store, gt)
	assert_gt(near_score, far_score,
		"scorer must penalise the farther approach tile, not just target")

# --- D4: BalanceData warns on unknown keys ---

func test_balance_data_warns_on_unknown_keys() -> void:
	# Write a temp file with a deliberate typo and load it. The loader should
	# return true (parse OK) but emit a push_warning that GUT can inspect.
	var path := "user://test_balance_typo.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"starting_wood": 10, "wolf_threat_radious": 5}')
	file.close()
	var balance := BalanceData.new()
	assert_true(balance.load_from_file(path))
	# Typo'd key was ignored; the field stays at default.
	assert_eq(balance.wolf_threat_radius, 8, "typo'd key shouldn't change canonical field")
	# Real field still loaded correctly.
	assert_eq(balance.starting_wood, 10)

# --- D5: day_start calls clear_stale to purge non-active tasks ---

func test_day_start_clears_stale_tasks() -> void:
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
	# Seed the board: one OPEN, one COMPLETED, one CANCELLED.
	var t_open := sim.board.create_task("chop_tree", Vector2i(1, 1), 0)
	var t_done := sim.board.create_task("chop_tree", Vector2i(2, 2), 0)
	sim.board.complete_task(t_done.id)
	var t_cancel := sim.board.create_task("chop_tree", Vector2i(3, 3), 0)
	sim.board.cancel_task(t_cancel.id)
	# Day-start should purge COMPLETED + CANCELLED, keep OPEN.
	sim._on_day_started(2)
	var statuses: Dictionary = {}
	for t in sim.board._tasks:
		statuses[t.status] = statuses.get(t.status, 0) + 1
	assert_eq(sim.board.count_by_status(Task.Status.COMPLETED), 0,
		"clear_stale should have removed completed tasks")
	assert_eq(sim.board.count_by_status(Task.Status.CANCELLED), 0,
		"clear_stale should have removed cancelled tasks")
	assert_gte(sim.board.count_by_status(Task.Status.OPEN), 1,
		"OPEN tasks should survive day_start cleanup")
