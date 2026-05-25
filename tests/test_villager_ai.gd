extends GutTest

func _make_context(wood: int, food: int, phase_night: bool = false) -> Dictionary:
	var store = ResourceStore.new()
	store.setup(wood, food)
	var board = TaskBoard.new()
	var gt = add_child_autoqfree(GameTime.new())
	gt.setup(10.0, 5.0, 7)
	if phase_night:
		gt._advance_phase()
	var scorer = UtilityScorer.new()
	return {"store": store, "board": board, "gt": gt, "scorer": scorer}

func test_pick_food_task_when_food_low() -> void:
	var ctx = _make_context(10, 3)
	ctx.board.create_task("gather_food", Vector2i(3, 3), 0)
	ctx.board.create_task("chop_tree", Vector2i(5, 5), 0)
	var villager = VillagerAgent.new(1, "Alice", Vector2i(6, 6))
	var chosen = villager.pick_best_task(ctx.board, ctx.store, ctx.gt, ctx.scorer)
	assert_not_null(chosen)
	assert_eq(chosen.type, "gather_food")

func test_pick_wood_task_when_wood_low() -> void:
	var ctx = _make_context(2, 10)
	ctx.board.create_task("gather_food", Vector2i(3, 3), 0)
	ctx.board.create_task("chop_tree", Vector2i(5, 5), 0)
	var villager = VillagerAgent.new(1, "Bob", Vector2i(6, 6))
	var chosen = villager.pick_best_task(ctx.board, ctx.store, ctx.gt, ctx.scorer)
	assert_not_null(chosen)
	assert_eq(chosen.type, "chop_tree")

func test_returns_null_when_no_open_tasks() -> void:
	var ctx = _make_context(10, 10)
	var villager = VillagerAgent.new(1, "Carol", Vector2i(6, 6))
	var chosen = villager.pick_best_task(ctx.board, ctx.store, ctx.gt, ctx.scorer)
	assert_null(chosen)

func test_return_home_at_night_beats_everything() -> void:
	var ctx = _make_context(10, 10, true)  # night phase
	ctx.board.create_task("return_home", Vector2i(4, 5), 0)
	ctx.board.create_task("gather_food", Vector2i(3, 3), 0)
	var villager = VillagerAgent.new(1, "Dave", Vector2i(6, 6))
	var chosen = villager.pick_best_task(ctx.board, ctx.store, ctx.gt, ctx.scorer)
	assert_eq(chosen.type, "return_home")

func test_starts_idle() -> void:
	var villager = VillagerAgent.new(1, "Eve", Vector2i(5, 5))
	assert_eq(villager.state, VillagerAgent.State.IDLE)

func test_set_task_changes_state_to_moving() -> void:
	var villager = VillagerAgent.new(1, "Frank", Vector2i(5, 5))
	var board = TaskBoard.new()
	var task = board.create_task("gather_food", Vector2i(3, 3), 0)
	board.claim_task(task.id, villager.id)
	villager.set_task(task)
	assert_eq(villager.state, VillagerAgent.State.MOVING_TO_TARGET)
	assert_eq(villager.current_task_id, task.id)

func test_gather_wildlife_scores_as_food_source() -> void:
	var ctx = _make_context(10, 0)
	ctx.board.create_task("gather_wildlife", WorldGenerator.HUT_POS, 0)
	ctx.board.create_task("chop_tree", Vector2i(5, 5), 0)
	var villager = VillagerAgent.new(1, "Gale", Vector2i(6, 6))
	var chosen = villager.pick_best_task(ctx.board, ctx.store, ctx.gt, ctx.scorer)
	assert_not_null(chosen)
	assert_eq(chosen.type, "gather_wildlife")
