extends SceneTree

var _finished := false
var _logger: ActionLogger

func _init() -> void:
	# Optional preset arg: `-- preset=hard` selects `data/balance_hard.json`.
	# Anything else (or no arg) loads the default `data/balance.json`.
	var preset_name: String = _parse_preset_arg()
	var balance_path: String = "res://data/balance.json"
	if preset_name != "":
		balance_path = "res://data/balance_%s.json" % preset_name

	print("=== Headless Simulation Start (preset=%s) ===" % (preset_name if preset_name != "" else "default"))

	# Run at 100× real time so 7 game-days complete in ~0.2 real seconds.
	# time_scale scales _process delta, so GameTime and villager move timers
	# both advance proportionally — behaviour is identical to real-time play.
	Engine.time_scale = 100.0
	Engine.max_fps = 0

	var balance = BalanceData.new()
	if not balance.load_from_file(balance_path):
		push_error("Preset not found: %s — falling back to default" % balance_path)
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

	_logger = ActionLogger.new()
	var dt := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var log_path := "user://run_%s.jsonl" % dt
	_logger.open(log_path)
	sim.set_logger(_logger)
	print("Logging to: %s" % log_path)
	print("  (local path: %s)" % (OS.get_user_data_dir() + "/run_%s.jsonl" % dt))

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
		_close_logger(sim, "WIN")
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
		_close_logger(sim, "LOSS: " + reason)
		quit(1)
	)

	# Timeout guard: if no result after 30s real time, report
	var timer = Timer.new()
	timer.wait_time = 30.0 * Engine.time_scale
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func():
		print("RESULT: TIMEOUT - simulation did not finish in 30s")
		_print_snapshot("TIMEOUT", sim)
		_close_logger(sim, "TIMEOUT")
		quit(2)
	)
	root.add_child(timer)

	print("Simulating %d days (fast mode)..." % balance.days_to_win)

func _parse_preset_arg() -> String:
	# Args after `--` are surfaced by get_cmdline_user_args(); we accept the
	# form `preset=<name>` or a positional `<name>` if it's the only user arg.
	var user_args := OS.get_cmdline_user_args()
	for arg in user_args:
		if arg.begins_with("preset="):
			return arg.substr(7).strip_edges()
	if user_args.size() == 1 and not user_args[0].is_empty():
		return user_args[0].strip_edges()
	return ""

func _close_logger(sim: VillageSimulation, result: String) -> void:
	if _logger == null:
		return
	var nature := sim.get_nature_summary()
	var villager_data: Array[Dictionary] = []
	for v in sim.villagers:
		villager_data.append({"name": v.name, "id": v.id, "hunger": v.hunger})
	_logger.log_event({
		"event": "run_summary",
		"result": result,
		"day": sim.game_time.day,
		"wood": sim.store.get_resource("wood"),
		"food": sim.store.get_resource("food"),
		"population": sim.villagers.size(),
		"deer_count": nature.get("deer_count", 0),
		"wolf_count": nature.get("wolf_count", 0),
		"villagers": villager_data
	})
	_logger.close()
	print("Log saved: %d events → %s" % [_logger.get_count(), _logger.get_path()])

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
	print("  nature deer=%d wolves=%d pending_trees=%d pending_berries=%d ai=%s" % [
		nature.get("deer_count", 0),
		nature.get("wolf_count", 0),
		nature.get("pending_trees", 0),
		nature.get("pending_berry_bushes", 0),
		sim.get_snapshot().get("ai_status", "Unknown")
	])
	print("  buildings houses=%d fences=%d towers=%d storage=%d" % [
		sim.world_gen.count_tiles_of_type(WorldGenerator.TileType.HOUSE) if sim.world_gen else 0,
		sim._fence_count, sim._watchtower_count, sim._storage_count
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
