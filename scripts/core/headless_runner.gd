extends SceneTree

func _init() -> void:
	print("=== Headless Simulation Start ===")

	var balance = BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	balance.day_duration_seconds = 2.0
	balance.night_duration_seconds = 0.5
	balance.villager_move_interval = 0.05

	var wg = WorldGenerator.new()
	wg.generate_fixed()

	var pf = PathfindingService.new()
	pf.setup(wg)

	var sim = VillageSimulation.new()
	root.add_child(sim)
	sim.setup(balance, wg, pf)

	sim.game_won.connect(func():
		print("RESULT: WIN on day %d" % sim.game_time.day)
		print("Final wood: %d, food: %d" % [
			sim.store.get_resource("wood"),
			sim.store.get_resource("food")
		])
		quit(0)
	)
	sim.game_lost.connect(func(reason: String):
		print("RESULT: LOSS — %s" % reason)
		print("Day: %d, wood: %d, food: %d" % [
			sim.game_time.day,
			sim.store.get_resource("wood"),
			sim.store.get_resource("food")
		])
		quit(1)
	)

	# Timeout guard: if no result after 30s real time, report
	var timer = Timer.new()
	timer.wait_time = 30.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func():
		print("RESULT: TIMEOUT — simulation did not finish in 30s")
		quit(2)
	)
	root.add_child(timer)

	print("Simulating %d days (fast mode)..." % balance.days_to_win)
