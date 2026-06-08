class_name SimulationSnapshot
extends RefCounted

static func build(sim: VillageSimulation) -> Dictionary:
	if sim == null:
		return {}
	var tasks := {
		"open": sim.board.count_by_status(Task.Status.OPEN),
		"claimed": sim.board.count_by_status(Task.Status.CLAIMED),
		"completed": sim.board.count_by_status(Task.Status.COMPLETED),
		"cancelled": sim.board.count_by_status(Task.Status.CANCELLED),
	}
	var food_needed: int = sim.get_living_population() * sim._balance.food_consumed_per_villager_per_night
	var wood_needed: int = sim._balance.wood_consumed_by_campfire_per_night
	var total_food: int = sim.store.get_total_food()
	var risk := {
		"food_shortfall": maxi(0, food_needed - total_food),
		"wood_shortfall": maxi(0, wood_needed - sim.store.get_resource("wood")),
		"monitor_anomalies": sim.monitor_anomalies.size(),
	}
	var pending_event := {}
	if sim.has_pending_event():
		pending_event = {
			"id": sim.pending_event.get("id", ""),
			"category": sim.pending_event.get("category", ""),
			"title": sim.pending_event.get("title", ""),
			"option_count": (sim.pending_event.get("options", []) as Array).size(),
		}
	var days_to_win: int = sim.get_days_to_win()
	return {
		"day": sim.game_time.day,
		"days_to_win": days_to_win,
		"season": sim.game_time.get_season_name() if sim.game_time else "Spring",
		"phase": sim.game_time.get_phase_name(),
		"tick": sim.game_time.tick,
		"time_left": sim.game_time.get_time_left(),
		"world_seed": sim._balance.world_seed,
		"active_policy": sim.active_policy,
		"active_policy_name": PolicyDefs.get_display_name(sim.active_policy),
		"last_policy_choice_day": sim.last_policy_choice_day,
		"can_change_policy": sim.can_change_policy(),
		"wood": sim.store.get_resource("wood"),
		"strategic_food": sim.store.get_resource("food"),
		"security": sim.store.get_resource("security"),
		"morale": sim.store.get_resource("morale"),
		"fresh_food": sim.store.get_resource("fresh_food"),
		"stored_food": sim.store.get_resource("stored_food"),
		"total_food": total_food,
		"population": sim.get_strategic_population(),
		"visible_population": sim.get_visible_population(),
		"dead_population": sim.get_dead_population(),
		"population_mismatch": sim.has_population_mismatch(),
		"population_capacity": sim.population_capacity,
		"hungry": sim.hungry_villagers,
		"campfire_out": sim.campfire_out_nights,
		"zero_streaks": {
			"food": sim.zero_food_days,
			"morale": sim.zero_morale_days,
			"security": sim.zero_security_days,
		},
		"zero_resource_loss_days": sim._balance.zero_resource_loss_days,
		"max_campfire_out_nights": sim._balance.max_campfire_out_nights,
		"pending_event": pending_event,
		"active_event_effects": sim.active_event_effects.duplicate(true),
		"last_event_result": sim.last_event_result.duplicate(true),
		"last_event_day": sim.last_event_day,
		"construction": _construction_snapshot(sim),
		"tasks": tasks,
		"nature": sim.get_nature_summary(),
		"risk": risk,
		"ai_status": "Attention" if risk.food_shortfall > 0 or risk.wood_shortfall > 0 or risk.monitor_anomalies > 0 else "Stable",
	}

static func _construction_snapshot(sim: VillageSimulation) -> Dictionary:
	var counts := {
		"houses": 0,
		"fences": sim._fence_count,
		"watchtowers": sim._watchtower_count,
		"storage": sim._storage_count,
	}
	if sim.world_gen != null:
		counts["houses"] = sim.world_gen.count_tiles_of_type(WorldGenerator.TileType.HOUSE)
	var active_project := {}
	if sim.board != null:
		for task in sim.board._tasks:
			if task.status != Task.Status.OPEN and task.status != Task.Status.CLAIMED:
				continue
			if not String(task.type).begins_with("build_"):
				continue
			var key: String = String(task.type).replace("build_", "")
			active_project = {
				"type": key,
				"label": _building_label(key),
				"task_type": task.type,
				"status": Task.Status.keys()[task.status].to_lower(),
				"x": task.target_tile.x,
				"y": task.target_tile.y,
			}
			break
	return {
		"counts": counts,
		"active_project": active_project,
		"has_active_project": not active_project.is_empty(),
	}

static func _building_label(key: String) -> String:
	match key:
		"house":
			return "House"
		"fence":
			return "Fence"
		"watchtower":
			return "Watchtower"
		"storage":
			return "Storage"
	return key.capitalize()
