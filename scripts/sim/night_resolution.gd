class_name NightResolution
extends RefCounted

# Owns the night sequence: hunger → campfire → spoilage. Wolf threat is handled
# by the caller (VillageSimulation._on_night_started) because mitigation reads
# building counts and emits its own log events, and the test surface for wolves
# already targets VillageSimulation directly.

const HungerSystemScript = preload("res://scripts/sim/hunger_system.gd")

static func resolve(sim) -> void:
	_resolve_hunger(sim)
	_resolve_campfire(sim)
	apply_food_spoilage(sim)

static func _resolve_hunger(sim) -> void:
	var balance: BalanceData = sim._balance
	var results := HungerSystemScript.resolve(sim.villagers, sim.store, balance)
	for r in results:
		sim._log({
			"event": "night_hunger",
			"villager": r["villager"],
			"fed": r["fed"],
			"skipped_dead": r.get("skipped_dead", false),
			"hunger": r["hunger_after"],
			"hunger_delta": r["hunger_after"] - r["hunger_before"],
			"food_before": r["food_before"],
			"food_after": r["food_after"],
			"consumed_fresh": r["consumed_fresh"],
			"consumed_stored": r["consumed_stored"],
		})
	sim._update_hungry_count()
	for v in sim.villagers:
		if v.status != VillagerAgent.Status.DEAD and v.hunger >= balance.max_hunger:
			sim.mark_villager_dead(v, "starvation")

static func _resolve_campfire(sim) -> void:
	var balance: BalanceData = sim._balance
	var base_needed: int = balance.wood_consumed_by_campfire_per_night
	# Winter doubles wood consumption; campfire keeps the village warm in cold months.
	var season: GameTime.Season = GameTime.Season.SPRING
	if sim.game_time != null:
		season = sim.game_time.current_season
	var needed: int = base_needed
	if season == GameTime.Season.WINTER:
		needed = int(ceil(float(base_needed) * balance.winter_wood_consumption_multiplier))
	var consumed: int = sim.store.consume_resource("wood", needed)
	if consumed < needed:
		sim.campfire_out_nights += 1
		sim._log({
			"event": "campfire_out",
			"consecutive_nights": sim.campfire_out_nights,
			"wood_consumed": consumed,
			"wood_needed": needed,
		})
		if sim.campfire_out_nights >= balance.max_campfire_out_nights:
			sim.game_lost.emit("Campfire out for %d consecutive nights" % sim.campfire_out_nights)
	else:
		sim.campfire_out_nights = 0
		sim._log({"event": "campfire_ok", "wood_consumed": consumed})

# Public so VillageSimulation._apply_food_spoilage() can delegate without
# exposing the test surface to changes here.
static func apply_food_spoilage(sim) -> void:
	var balance: BalanceData = sim._balance
	var spoil: int = balance.fresh_food_spoilage_per_night
	if spoil <= 0:
		return
	var before: int = sim.store.get_resource("fresh_food")
	if before <= 0:
		return
	var actual_spoil: int = sim.store.spoil_fresh_food(spoil)
	sim._log({
		"event": "food_spoiled",
		"amount": actual_spoil,
		"remaining": sim.store.get_resource("fresh_food"),
	})
