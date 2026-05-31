class_name PolicyResolver
extends RefCounted

static func resolve_daily(sim: VillageSimulation) -> Dictionary:
	if sim.store == null or sim._balance == null:
		return {}
	var summary := {
		"food_consumed": sim.store.consume_resource("food", sim._balance.strategic_food_consumed_per_day),
		"food": 0,
		"wood": 0,
		"security": 0,
		"morale": 0,
		"recovered": 0,
		"injured": 0,
	}
	for v in sim.villagers:
		if not v.can_work():
			continue
		var job_output: String = JobDefs.output_type_for_job(v.job)
		var base: int = JobDefs.base_output(v.job)
		var amount: int = modified_output_amount(sim, v, job_output, base)
		match job_output:
			"food":
				sim.store.add_resource("food", amount)
				summary["food"] += amount
				if v.job == JobDefs.HUNTER and roll_percent(sim, "hunter_injury", v.id) < sim._balance.hunter_injury_chance_percent:
					v.status = VillagerAgent.Status.INJURED
					summary["injured"] += 1
			"wood":
				sim.store.add_resource("wood", amount)
				summary["wood"] += amount
			"security":
				sim.store.add_resource("security", amount)
				summary["security"] += amount
			"recovery":
				var target := find_recoverable_villager(sim)
				if target != null and roll_percent(sim, "herbalist_recovery", v.id) < modified_recovery_chance(sim):
					target.status = VillagerAgent.Status.HEALTHY
					sim.store.add_resource("morale", amount)
					summary["morale"] += amount
					summary["recovered"] += 1
	return summary

static func modified_output_amount(sim: VillageSimulation, v: VillagerAgent, output_type: String, base: int) -> int:
	var amount: float = float(base)
	amount *= JobDefs.status_output_multiplier(v.status)
	amount *= PolicyDefs.output_multiplier(sim.active_policy, output_type)
	return maxi(0, int(round(amount)))

static func modified_recovery_chance(sim: VillageSimulation) -> int:
	return mini(100, int(round(float(sim._balance.herbalist_recovery_chance_percent) * PolicyDefs.output_multiplier(sim.active_policy, "recovery"))))

static func find_recoverable_villager(sim: VillageSimulation) -> VillagerAgent:
	for v in sim.villagers:
		if v.status == VillagerAgent.Status.INJURED or v.status == VillagerAgent.Status.SICK:
			return v
	return null

static func roll_percent(sim: VillageSimulation, tag: String, villager_id: int) -> int:
	var day: int = sim.game_time.day if sim.game_time != null else 1
	var seed: int = sim._balance.world_seed if sim._balance != null else 0
	var value := "%s:%d:%d:%d" % [tag, seed, day, villager_id]
	return absi(value.hash()) % 100
