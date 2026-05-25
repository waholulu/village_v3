extends GutTest

func test_default_seed_survives_seven_days_without_monitor_anomalies() -> void:
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

	watch_signals(sim)

	await wait_until(
		func() -> bool:
			return get_signal_emit_count(sim, "game_won") > 0 or get_signal_emit_count(sim, "game_lost") > 0,
		8.0,
		0.05,
		"Simulation should finish"
	)

	assert_signal_emitted(sim, "game_won", "Default deterministic run should survive to the day 8 win condition")
	assert_signal_not_emitted(sim, "game_lost")
	assert_eq(sim.run_monitor_check().size(), 0)
	assert_gte(sim.store.get_resource("wood"), 0)
	assert_gte(sim.store.get_resource("food"), 0)
	for v in sim.villagers:
		assert_lt(v.hunger, balance.max_hunger)
