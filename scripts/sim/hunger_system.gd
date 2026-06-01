class_name HungerSystem
extends RefCounted

# Per-night hunger resolution as a pure function.
# Consumes unified food, drawing fresh_food before stored_food. Mutates villager.hunger
# and resource store but emits no signals — caller logs and emits.

static func resolve(villagers: Array, store: ResourceStore,
		balance: BalanceData) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var per_night: int = balance.food_consumed_per_villager_per_night
	for v in villagers:
		if v.status == VillagerAgent.Status.DEAD:
			results.append({
				"villager": v.name,
				"fed": false,
				"skipped_dead": true,
				"hunger_before": v.hunger,
				"hunger_after": v.hunger,
				"food_before": store.get_resource("food"),
				"food_after": store.get_resource("food"),
				"consumed_fresh": 0,
				"consumed_stored": 0,
			})
			continue
		var before: int = v.hunger
		var food_before: int = store.get_resource("food")
		var consumed: Dictionary = store.consume_food(per_night)
		var total_consumed: int = consumed["total"]
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
			"food_before": food_before,
			"food_after": store.get_resource("food"),
			"consumed_fresh": consumed["fresh"],
			"consumed_stored": consumed["stored"],
		})
	return results

static func count_hungry(villagers: Array) -> int:
	var count := 0
	for v in villagers:
		if v.status != VillagerAgent.Status.DEAD and v.hunger > 0:
			count += 1
	return count

static func anyone_starved(villagers: Array, max_hunger: int) -> bool:
	for v in villagers:
		if v.status != VillagerAgent.Status.DEAD and v.hunger >= max_hunger:
			return true
	return false
