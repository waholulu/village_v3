class_name WolfThreatSystem
extends RefCounted

# Wolf-disruption resolver. Runs after the nightly hunger/campfire/spoilage
# sequence when nature.check_wolf_threat() returns true. Pulled out of
# VillageSimulation to keep the main file under the 600-line guardrail.
#
# Behaviour preserved exactly from the previous inline implementation:
# - Threat count increments regardless of mitigation (used by planner to gate
#   reactive fence construction)
# - Watchtower halves damage with rounding-up
# - Each fence multiplies by (1 - fence_wolf_damage_reduction)
# - RNG seed mixes day + threat count + village size for deterministic-but-
#   varying targeting
# - Starvation re-checked after damage so wolf-pushed overflow ends the game
#   immediately, not next night

static func apply_disruption(sim) -> void:
	if sim.villagers.is_empty():
		return
	sim._wolf_threat_count += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = sim.game_time.day * 31 + sim._wolf_threat_count * 7 + sim.villagers.size()
	var idx: int = rng.randi_range(0, sim.villagers.size() - 1)
	var raw: int = sim._balance.wolf_hunger_disruption
	var damage: int = raw
	if sim._watchtower_count > 0:
		damage = (damage + 1) / 2
	var fence_mult: float = pow(1.0 - sim._balance.fence_wolf_damage_reduction, float(sim._fence_count))
	damage = int(round(float(damage) * fence_mult))
	if damage <= 0:
		sim._log({
			"event": "wolf_threat_mitigated",
			"raw_damage": raw,
			"fences": sim._fence_count,
			"watchtowers": sim._watchtower_count,
		})
		return
	sim.villagers[idx].hunger += damage
	sim._log({
		"event": "wolf_threat",
		"disrupted_villager": sim.villagers[idx].name,
		"raw_damage": raw,
		"mitigated_damage": damage,
		"fences": sim._fence_count,
		"watchtowers": sim._watchtower_count,
		"new_hunger": sim.villagers[idx].hunger,
	})
	sim._update_hungry_count()
	if sim.villagers[idx].hunger >= sim._balance.max_hunger:
		sim.game_lost.emit("A villager starved")
