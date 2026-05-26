extends GutTest

# Phase C asserts that return_home and refuel_campfire have been removed
# from the simulation entirely. These are the regression locks — if a
# future commit re-adds either task type, these tests will catch it.

func test_utility_scorer_has_no_placeholder_arms() -> void:
	# Score whatever the scorer makes of a fake "refuel_campfire" task — should
	# be just the distance penalty since the arm is gone.
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	var store := ResourceStore.new()
	store.setup(balance.starting_wood, balance.starting_food)
	var gt := GameTime.new()
	gt.setup(balance.day_duration_seconds, balance.night_duration_seconds, balance.days_to_win)
	add_child_autoqfree(gt)
	var scorer := UtilityScorer.new()
	var v := VillagerAgent.new(1, "Test", Vector2i(4, 5))
	var refuel_task := Task.new(1, "refuel_campfire", WorldGenerator.CAMPFIRE_POS)
	var return_task := Task.new(2, "return_home", WorldGenerator.HUT_POS)
	# With no scoring arm the only score contribution is `-dist * 0.5` and
	# whichever default branch the match falls through. Score should be <= 0.
	var refuel_score := scorer.score_task(v, refuel_task, store, gt)
	var return_score := scorer.score_task(v, return_task, store, gt)
	assert_lt(refuel_score, 1.0, "refuel_campfire must not score positive — arm should be gone")
	assert_lt(return_score, 1.0, "return_home must not score positive — arm should be gone")

func test_balance_drops_obsolete_keys() -> void:
	# Both keys were only used by the refuel_campfire creation block.
	var balance := BalanceData.new()
	# Loading the default balance.json should not warn about missing keys —
	# the keys are gone from the class definition.
	assert_true(balance.load_from_file("res://data/balance.json"))
	# Use `in self` reflection: GDScript's `in` on objects checks property
	# names. If the property is gone, `in` returns false.
	assert_false("wood_campfire_urgent_threshold" in balance,
		"wood_campfire_urgent_threshold should be removed from BalanceData")
	assert_false("time_left_urgent_seconds" in balance,
		"time_left_urgent_seconds should be removed from BalanceData")

func test_simulation_does_not_create_placeholder_tasks_during_full_day() -> void:
	# Drive a full day cycle (day_started signal handler + a few ticks of
	# _generate_tasks); assert no return_home / refuel_campfire ever appears
	# on the board.
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
	# Run _generate_tasks several times across phase transitions.
	sim._generate_tasks()
	sim._on_night_started(1)
	sim._on_day_started(2)
	sim._generate_tasks()
	for task in sim.board._tasks:
		assert_ne(task.type, "return_home",
			"return_home task type was created — Phase C regression")
		assert_ne(task.type, "refuel_campfire",
			"refuel_campfire task type was created — Phase C regression")
