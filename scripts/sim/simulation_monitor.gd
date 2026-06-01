class_name SimulationMonitor
extends RefCounted

func check(sim: VillageSimulation) -> Array[Dictionary]:
	var anomalies: Array[Dictionary] = []
	if sim == null:
		return anomalies
	_check_villagers(sim, anomalies)
	_check_tasks(sim, anomalies)
	_check_resources(sim, anomalies)
	_check_population(sim, anomalies)
	_check_survival_risk(sim, anomalies)
	return anomalies

func _check_villagers(sim: VillageSimulation, anomalies: Array[Dictionary]) -> void:
	if sim.world_gen == null:
		return
	for v in sim.villagers:
		if not sim.world_gen.is_in_bounds(v.tile_position):
			anomalies.append(_anomaly(
				"villager_out_of_bounds",
				"error",
				"%s is outside the map at (%d,%d)" % [v.name, v.tile_position.x, v.tile_position.y]
			))
			continue
		if not sim.world_gen.is_walkable(v.tile_position.x, v.tile_position.y):
			anomalies.append(_anomaly(
				"villager_on_unwalkable_tile",
				"error",
				"%s is standing on an unwalkable tile at (%d,%d)" % [v.name, v.tile_position.x, v.tile_position.y]
			))
		for step in v._path:
			if not sim.world_gen.is_in_bounds(step):
				anomalies.append(_anomaly(
					"path_out_of_bounds",
					"error",
					"%s has an out-of-bounds path step at (%d,%d)" % [v.name, step.x, step.y]
				))
			elif not sim.world_gen.is_walkable(step.x, step.y):
				anomalies.append(_anomaly(
					"path_on_unwalkable_tile",
					"error",
					"%s has an unwalkable path step at (%d,%d)" % [v.name, step.x, step.y]
				))
		if v.state == VillagerAgent.State.IDLE and v.current_task_id != -1:
			anomalies.append(_anomaly(
				"villager_idle_with_task",
				"error",
				"%s is idle but still references task %d" % [v.name, v.current_task_id]
			))
		if v.current_task_id != -1 and sim.board != null:
			var task := sim.board.get_task(v.current_task_id)
			if task == null:
				anomalies.append(_anomaly(
					"villager_task_missing_task",
					"error",
					"%s references missing task %d" % [v.name, v.current_task_id]
				))
			elif task.status != Task.Status.CLAIMED:
				anomalies.append(_anomaly(
					"villager_task_not_claimed",
					"error",
					"%s references task %d but it is %s" % [v.name, task.id, Task.Status.keys()[task.status]]
				))
			elif task.claimed_by != v.id:
				anomalies.append(_anomaly(
					"villager_task_claim_mismatch",
					"error",
					"%s references task %d claimed by villager %d" % [v.name, task.id, task.claimed_by]
				))
		if v.state == VillagerAgent.State.MOVING_TO_TARGET and v._path.is_empty():
			anomalies.append(_anomaly(
				"moving_villager_without_path",
				"warning",
				"%s is moving but has no path" % v.name
			))

func _check_tasks(sim: VillageSimulation, anomalies: Array[Dictionary]) -> void:
	if sim.world_gen == null or sim.board == null:
		return
	var villager_ids := {}
	for v in sim.villagers:
		villager_ids[v.id] = true
	for task in sim.board._tasks:
		# Completed/cancelled tasks are historical — their tiles may have been
		# legitimately mutated since (e.g. regrowth), so skip the geometry checks.
		if task.status != Task.Status.OPEN and task.status != Task.Status.CLAIMED:
			continue
		if not sim.world_gen.is_in_bounds(task.target_tile):
			anomalies.append(_anomaly(
				"task_target_out_of_bounds",
				"warning",
				"Task %d target is outside the map at (%d,%d)" % [task.id, task.target_tile.x, task.target_tile.y]
			))
		if not sim.world_gen.is_in_bounds(task.approach_tile):
			anomalies.append(_anomaly(
				"task_approach_out_of_bounds",
				"warning",
				"Task %d approach tile is outside the map at (%d,%d)" % [task.id, task.approach_tile.x, task.approach_tile.y]
			))
		elif not sim.world_gen.is_walkable(task.approach_tile.x, task.approach_tile.y):
			anomalies.append(_anomaly(
				"task_approach_unwalkable",
				"error",
				"Task %d approach tile is unwalkable at (%d,%d)" % [task.id, task.approach_tile.x, task.approach_tile.y]
			))
		if task.status == Task.Status.CLAIMED and not villager_ids.has(task.claimed_by):
			anomalies.append(_anomaly(
				"claimed_task_missing_villager",
				"error",
				"Task %d is claimed by missing villager %d" % [task.id, task.claimed_by]
			))
		elif task.status == Task.Status.CLAIMED and not _villager_has_task(sim, task.claimed_by, task.id):
			anomalies.append(_anomaly(
				"claimed_task_unassigned",
				"error",
				"Task %d is claimed by villager %d but no villager references it" % [task.id, task.claimed_by]
			))

func _check_resources(sim: VillageSimulation, anomalies: Array[Dictionary]) -> void:
	if sim.store == null:
		return
	for resource_name in sim.store._resources.keys():
		var amount: int = sim.store.get_resource(resource_name)
		if amount < 0:
			anomalies.append(_anomaly(
				"negative_resource",
				"error",
				"%s stock is negative: %d" % [resource_name, amount]
			))

func _check_population(sim: VillageSimulation, anomalies: Array[Dictionary]) -> void:
	if sim.get_living_population() > sim.population_capacity:
		anomalies.append(_anomaly(
			"population_over_capacity",
			"warning",
			"Population %d exceeds capacity %d" % [sim.get_living_population(), sim.population_capacity]
		))

func _check_survival_risk(sim: VillageSimulation, anomalies: Array[Dictionary]) -> void:
	if sim.store == null or sim._balance == null:
		return
	var food_needed := sim.get_living_population() * sim._balance.food_consumed_per_villager_per_night * sim._balance.monitor_min_food_nights
	if sim.store.get_total_food() < food_needed and not _has_available_food_source(sim):
		anomalies.append(_anomaly(
			"food_survival_risk",
			"warning",
			"Food stock cannot cover the next %d night(s), and no reachable food source is available" % sim._balance.monitor_min_food_nights
		))
	var wood_needed := sim._balance.wood_consumed_by_campfire_per_night * sim._balance.monitor_min_wood_nights
	if sim.store.get_resource("wood") < wood_needed and not _has_reachable_resource(sim, WorldGenerator.TileType.TREE):
		anomalies.append(_anomaly(
			"wood_survival_risk",
			"warning",
			"Wood stock cannot cover the next %d night(s), and no reachable tree is available" % sim._balance.monitor_min_wood_nights
		))
	var active_tasks := sim.board.count_by_status(Task.Status.OPEN) + sim.board.count_by_status(Task.Status.CLAIMED)
	if active_tasks > sim._balance.monitor_task_backlog_warning:
		anomalies.append(_anomaly(
			"task_backlog_high",
			"warning",
			"Active task backlog is %d" % active_tasks
		))

func _has_available_food_source(sim: VillageSimulation) -> bool:
	if sim.nature != null and sim.nature.wildlife_food > 0:
		return true
	return _has_reachable_resource(sim, WorldGenerator.TileType.BERRY_BUSH)

func _has_reachable_resource(sim: VillageSimulation, tile_type: int) -> bool:
	if sim.world_gen == null:
		return false
	for pos in sim.world_gen.get_tiles_of_type(tile_type):
		var adj := sim.world_gen.find_walkable_adjacent(pos)
		if adj != Vector2i(-1, -1) and sim.world_gen.is_reachable_from_hut(adj):
			return true
	return false

func _anomaly(code: String, severity: String, message: String) -> Dictionary:
	return {
		"code": code,
		"severity": severity,
		"message": message
	}

func _villager_has_task(sim: VillageSimulation, villager_id: int, task_id: int) -> bool:
	for v in sim.villagers:
		if v.id == villager_id and v.current_task_id == task_id:
			return true
	return false
