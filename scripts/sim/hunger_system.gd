class_name HungerSystem
extends RefCounted

# Per-night hunger resolution as a pure function.
# Consumes fresh_food first, falls back to stored_food. Mutates villager.hunger
# and resource store but emits no signals — caller logs and emits.

static func resolve(villagers: Array, store: ResourceStore,
		balance: BalanceData) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var per_night: int = balance.food_consumed_per_villager_per_night
	for v in villagers:
		var before: int = v.hunger
		var consumed_fresh: int = store.consume_resource("fresh_food", per_night)
		var remaining: int = per_night - consumed_fresh
		var consumed_stored: int = 0
		if remaining > 0:
			consumed_stored = store.consume_resource("stored_food", remaining)
		var total_consumed: int = consumed_fresh + consumed_stored
		var fed: bool = total_consumed == per_night
		if fed:
			v.hunger = maxi(0, v.hunger - 1)
		else:
			v.hunger += 1
		results.append({
			"villager": v.name,
			"fed": fed,
			"hunger_before": before,
			"hunger_after": v.hunger,
		})
	return results

static func count_hungry(villagers: Array) -> int:
	var count := 0
	for v in villagers:
		if v.hunger > 0:
			count += 1
	return count

static func anyone_starved(villagers: Array, max_hunger: int) -> bool:
	for v in villagers:
		if v.hunger >= max_hunger:
			return true
	return false
