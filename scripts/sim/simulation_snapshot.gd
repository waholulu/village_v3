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
	var food_needed: int = sim.villagers.size() * sim._balance.food_consumed_per_villager_per_night
	var wood_needed: int = sim._balance.wood_consumed_by_campfire_per_night
	var total_food: int = sim.store.get_total_food()
	var risk := {
		"food_shortfall": maxi(0, food_needed - total_food),
		"wood_shortfall": maxi(0, wood_needed - sim.store.get_resource("wood")),
		"monitor_anomalies": sim.monitor_anomalies.size(),
	}
	var days_to_win: int = sim.get_days_to_win()
	return {
		"day": sim.game_time.day,
		"days_to_win": days_to_win,
		"season": sim.game_time.get_season_name() if sim.game_time else "Spring",
		"phase": sim.game_time.get_phase_name(),
		"tick": sim.game_time.tick,
		"time_left": sim.game_time.get_time_left(),
		"active_policy": sim.active_policy,
		"active_policy_name": PolicyDefs.get_display_name(sim.active_policy),
		"wood": sim.store.get_resource("wood"),
		"strategic_food": sim.store.get_resource("food"),
		"security": sim.store.get_resource("security"),
		"morale": sim.store.get_resource("morale"),
		"fresh_food": sim.store.get_resource("fresh_food"),
		"stored_food": sim.store.get_resource("stored_food"),
		"total_food": total_food,
		"population": sim.get_strategic_population(),
		"visible_population": sim.get_visible_population(),
		"population_mismatch": sim.has_population_mismatch(),
		"population_capacity": sim.population_capacity,
		"hungry": sim.hungry_villagers,
		"campfire_out": sim.campfire_out_nights,
		"zero_streaks": {
			"food": sim.zero_food_days,
			"morale": sim.zero_morale_days,
			"security": sim.zero_security_days,
		},
		"tasks": tasks,
		"nature": sim.get_nature_summary(),
		"risk": risk,
		"ai_status": "Attention" if risk.food_shortfall > 0 or risk.wood_shortfall > 0 or risk.monitor_anomalies > 0 else "Stable",
	}
