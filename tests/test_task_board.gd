extends GutTest

var board: TaskBoard

func before_each() -> void:
	board = TaskBoard.new()

func test_create_task_returns_task() -> void:
	var task = board.create_task("gather_food", Vector2i(3, 4), 0)
	assert_not_null(task)

func test_created_task_has_correct_type() -> void:
	var task = board.create_task("gather_food", Vector2i(3, 4), 0)
	assert_eq(task.type, "gather_food")

func test_created_task_is_open() -> void:
	var task = board.create_task("chop_tree", Vector2i(1, 1), 0)
	assert_eq(task.status, Task.Status.OPEN)

func test_created_task_has_correct_tile() -> void:
	var task = board.create_task("gather_food", Vector2i(7, 3), 0)
	assert_eq(task.target_tile, Vector2i(7, 3))

func test_claim_task_returns_true() -> void:
	var task = board.create_task("chop_tree", Vector2i(1, 1), 0)
	assert_true(board.claim_task(task.id, 1))

func test_claim_task_sets_status_claimed() -> void:
	var task = board.create_task("chop_tree", Vector2i(1, 1), 0)
	board.claim_task(task.id, 1)
	assert_eq(task.status, Task.Status.CLAIMED)

func test_claim_task_sets_claimed_by() -> void:
	var task = board.create_task("chop_tree", Vector2i(1, 1), 0)
	board.claim_task(task.id, 42)
	assert_eq(task.claimed_by, 42)

func test_one_task_cannot_be_claimed_twice() -> void:
	var task = board.create_task("chop_tree", Vector2i(1, 1), 0)
	board.claim_task(task.id, 1)
	assert_false(board.claim_task(task.id, 2))

func test_second_claim_does_not_change_owner() -> void:
	var task = board.create_task("chop_tree", Vector2i(1, 1), 0)
	board.claim_task(task.id, 1)
	board.claim_task(task.id, 2)
	assert_eq(task.claimed_by, 1)

func test_complete_task() -> void:
	var task = board.create_task("gather_food", Vector2i(5, 5), 0)
	board.claim_task(task.id, 1)
	board.complete_task(task.id)
	assert_eq(task.status, Task.Status.COMPLETED)

func test_cancel_task() -> void:
	var task = board.create_task("gather_food", Vector2i(5, 5), 0)
	board.cancel_task(task.id)
	assert_eq(task.status, Task.Status.CANCELLED)

func test_get_open_tasks_excludes_claimed() -> void:
	var t1 = board.create_task("gather_food", Vector2i(1, 1), 0)
	var t2 = board.create_task("chop_tree", Vector2i(2, 2), 0)
	board.claim_task(t1.id, 1)
	var open = board.get_open_tasks()
	assert_eq(open.size(), 1)
	assert_eq(open[0].id, t2.id)

func test_get_open_tasks_empty_when_all_claimed() -> void:
	var t1 = board.create_task("gather_food", Vector2i(1, 1), 0)
	board.claim_task(t1.id, 1)
	assert_eq(board.get_open_tasks().size(), 0)

func test_count_by_status_open() -> void:
	board.create_task("gather_food", Vector2i(1, 1), 0)
	board.create_task("chop_tree", Vector2i(2, 2), 0)
	assert_eq(board.count_by_status(Task.Status.OPEN), 2)

func test_count_by_status_completed() -> void:
	var t = board.create_task("gather_food", Vector2i(1, 1), 0)
	board.claim_task(t.id, 1)
	board.complete_task(t.id)
	assert_eq(board.count_by_status(Task.Status.COMPLETED), 1)

func test_has_open_task_of_type_true() -> void:
	board.create_task("gather_food", Vector2i(1, 1), 0)
	assert_true(board.has_open_task_of_type("gather_food"))

func test_has_open_task_of_type_false_when_claimed() -> void:
	var t = board.create_task("gather_food", Vector2i(1, 1), 0)
	board.claim_task(t.id, 1)
	assert_false(board.has_open_task_of_type("gather_food"))

func test_has_active_task_of_type_true_when_claimed() -> void:
	var t = board.create_task("build_house", Vector2i(8, 5), 0)
	board.claim_task(t.id, 1)
	assert_true(board.has_active_task_of_type("build_house"))

func test_has_active_task_of_type_false_when_completed() -> void:
	var t = board.create_task("build_house", Vector2i(8, 5), 0)
	board.claim_task(t.id, 1)
	board.complete_task(t.id)
	assert_false(board.has_active_task_of_type("build_house"))

func test_has_task_for_tile_true_when_open() -> void:
	board.create_task("gather_food", Vector2i(7, 3), 0)
	assert_true(board.has_task_for_tile(Vector2i(7, 3)))

func test_has_task_for_tile_still_true_when_claimed() -> void:
	var t = board.create_task("gather_food", Vector2i(7, 3), 0)
	board.claim_task(t.id, 1)
	assert_true(board.has_task_for_tile(Vector2i(7, 3)))

func test_has_task_for_tile_false_when_completed() -> void:
	var t = board.create_task("gather_food", Vector2i(7, 3), 0)
	board.claim_task(t.id, 1)
	board.complete_task(t.id)
	assert_false(board.has_task_for_tile(Vector2i(7, 3)))

func test_task_approach_tile_defaults_to_target() -> void:
	var t = board.create_task("chop_tree", Vector2i(1, 1), 0)
	assert_eq(t.approach_tile, Vector2i(1, 1))

func test_task_approach_tile_can_be_overridden() -> void:
	var t = board.create_task("chop_tree", Vector2i(1, 1), 0)
	t.approach_tile = Vector2i(2, 1)
	assert_eq(t.approach_tile, Vector2i(2, 1))
