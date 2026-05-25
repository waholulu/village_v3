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
	var risk := {
		"food_shortfall": maxi(0, food_needed - sim.store.get_resource("food")),
		"wood_shortfall": maxi(0, wood_needed - sim.store.get_resource("wood")),
		"monitor_anomalies": sim.monitor_anomalies.size(),
	}
	return {
		"day": sim.game_time.day,
		"days_to_win": sim._balance.days_to_win,
		"phase": sim.game_time.get_phase_name(),
		"tick": sim.game_time.tick,
		"time_left": sim.game_time.get_time_left(),
		"wood": sim.store.get_resource("wood"),
		"food": sim.store.get_resource("food"),
		"population": sim.villagers.size(),
		"population_capacity": sim.population_capacity,
		"hungry": sim.hungry_villagers,
		"campfire_out": sim.campfire_out_nights,
		"tasks": tasks,
		"nature": sim.get_nature_summary(),
		"risk": risk,
		"ai_status": "Attention" if risk.food_shortfall > 0 or risk.wood_shortfall > 0 or risk.monitor_anomalies > 0 else "Stable",
	}
