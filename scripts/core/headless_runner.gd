extends SceneTree

var _finished := false

func _init() -> void:
	print("=== Headless Simulation Start ===")

	var balance = BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	balance.day_duration_seconds = 2.0
	balance.night_duration_seconds = 0.5
	balance.villager_move_interval = 0.05

	var wg = WorldGenerator.new()
	wg.generate_from_balance(balance)

	var pf = PathfindingService.new()
	pf.setup(wg)

	var sim = VillageSimulation.new()
	root.add_child(sim)
	sim.setup(balance, wg, pf)
	_print_snapshot("START", sim)

	sim.game_time.night_started.connect(func(_day: int):
		if not _finished:
			_print_snapshot("NIGHT_RESOLVED", sim)
	)
	sim.game_time.day_started.connect(func(_day: int):
		if not _finished:
			_print_snapshot("DAY_STARTED", sim)
	)
	sim.monitor_anomalies_changed.connect(func(anomalies: Array[Dictionary]):
		if not _finished:
			_print_monitor(anomalies)
	)

	sim.game_won.connect(func():
		_finished = true
		print("RESULT: WIN on day %d" % sim.game_time.day)
		_print_snapshot("FINAL", sim)
		print("Final wood: %d, food: %d" % [
			sim.store.get_resource("wood"),
			sim.store.get_resource("food")
		])
		quit(0)
	)
	sim.game_lost.connect(func(reason: String):
		_finished = true
		print("RESULT: LOSS - %s" % reason)
		_print_snapshot("FINAL", sim)
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
		print("RESULT: TIMEOUT - simulation did not finish in 30s")
		_print_snapshot("TIMEOUT", sim)
		quit(2)
	)
	root.add_child(timer)

	print("Simulating %d days (fast mode)..." % balance.days_to_win)

func _print_snapshot(label: String, sim: VillageSimulation) -> void:
	print(
		"%s | day=%d phase=%s tick=%d time_left=%.2f wood=%d food=%d population=%d/%d hungry=%d campfire_out=%d tasks(open=%d claimed=%d done=%d cancelled=%d) anomalies=%d" % [
			label,
			sim.game_time.day,
			sim.game_time.get_phase_name(),
			sim.game_time.tick,
			sim.game_time.get_time_left(),
			sim.store.get_resource("wood"),
			sim.store.get_resource("food"),
			sim.villagers.size(),
			sim.population_capacity,
			sim.hungry_villagers,
			sim.campfire_out_nights,
			sim.board.count_by_status(Task.Status.OPEN),
			sim.board.count_by_status(Task.Status.CLAIMED),
			sim.board.count_by_status(Task.Status.COMPLETED),
			sim.board.count_by_status(Task.Status.CANCELLED),
			sim.monitor_anomalies.size()
		]
	)
	var nature := sim.get_nature_summary()
	print("  nature wildlife=%d pending_trees=%d pending_berries=%d ai=%s" % [
		nature.get("wildlife_food", 0),
		nature.get("pending_trees", 0),
		nature.get("pending_berry_bushes", 0),
		sim.get_snapshot().get("ai_status", "Unknown")
	])
	for v in sim.villagers:
		print("  %s id=%d state=%s pos=(%d,%d) hunger=%d task=%s" % [
			v.name,
			v.id,
			v.get_state_name(),
			v.tile_position.x,
			v.tile_position.y,
			v.hunger,
			_describe_task(sim, v.current_task_id)
		])
	if not sim.monitor_anomalies.is_empty():
		_print_monitor(sim.monitor_anomalies)

func _describe_task(sim: VillageSimulation, task_id: int) -> String:
	if task_id == -1:
		return "none"
	var task := sim.board.get_task(task_id)
	if task == null:
		return "missing:%d" % task_id
	return "%d:%s:%s target=(%d,%d) approach=(%d,%d)" % [
		task.id,
		task.type,
		Task.Status.keys()[task.status],
		task.target_tile.x,
		task.target_tile.y,
		task.approach_tile.x,
		task.approach_tile.y
	]

func _print_monitor(anomalies: Array[Dictionary]) -> void:
	if anomalies.is_empty():
		print("MONITOR: OK")
		return
	print("MONITOR: %d anomal%s" % [anomalies.size(), "y" if anomalies.size() == 1 else "ies"])
	for anomaly in anomalies:
		print("  [%s] %s - %s" % [
			anomaly.get("severity", "warning"),
			anomaly.get("code", "unknown"),
			anomaly.get("message", "")
		])
