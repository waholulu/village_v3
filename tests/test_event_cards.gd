extends GutTest

func _load_deck() -> EventDeck:
	var deck := EventDeck.new()
	assert_true(deck.load_from_file("res://data/events.json"))
	return deck

func _setup_world_sim(villager_count: int = 3) -> VillageSimulation:
	var balance := BalanceData.new()
	balance.villager_count = villager_count
	balance.starting_population = villager_count
	balance.starting_population_capacity = villager_count
	balance.hunter_injury_chance_percent = 0
	balance.herbalist_recovery_chance_percent = 100
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	return sim

func test_event_file_contains_25_cards() -> void:
	var deck := _load_deck()
	assert_eq(deck.events.size(), 25)
	assert_eq(deck.validate().size(), 0)

func test_event_categories_have_5_cards_each() -> void:
	var deck := _load_deck()
	var counts := {}
	for event in deck.events:
		var category: String = event.get("category", "")
		counts[category] = counts.get(category, 0) + 1
	for category in EventDeck.CATEGORIES:
		assert_eq(counts.get(category, 0), 5, "Expected 5 cards in " + category)

func test_event_options_have_immediate_results() -> void:
	var deck := _load_deck()
	for event in deck.events:
		var options: Array = event.get("options", [])
		assert_gte(options.size(), 2)
		assert_lte(options.size(), 3)
		for option in options:
			assert_false(str(option.get("result_text", "")).is_empty())
			assert_false((option.get("immediate", []) as Array).is_empty())

func test_event_option_has_at_most_one_short_term_effect() -> void:
	var deck := _load_deck()
	for event in deck.events:
		for option in event.get("options", []):
			var short_term = option.get("short_term", null)
			assert_true(short_term == null or short_term is Dictionary)

func test_event_draw_is_deterministic_with_seed() -> void:
	var deck := _load_deck()
	var first := deck.draw_for_day(4312, 3, [])
	var second := deck.draw_for_day(4312, 3, [])
	assert_false(first.is_empty())
	assert_eq(first.get("id", ""), second.get("id", ""))

func test_event_weight_multiplier_changes_draw_category_weights() -> void:
	var deck := _load_deck()
	var effects: Array[Dictionary] = []
	for category in EventDeck.CATEGORIES:
		if category == "weather":
			continue
		effects.append({
			"type": "event_weight_multiplier",
			"category": category,
			"multiplier": 0.0,
			"remaining_days": 1,
			"starts_on_day": 3,
		})
	var event := deck.draw_for_day(4312, 3, effects)
	assert_eq(event.get("category", ""), "weather")

func test_at_most_one_event_per_day() -> void:
	var sim := _setup_world_sim()
	sim.game_time.day = 3
	sim._draw_event_for_day(3)
	assert_true(sim.has_pending_event())
	var event_id: String = sim.pending_event.get("id", "")
	var option_id: String = (sim.pending_event.get("options", []) as Array)[0].get("id", "")
	var result := sim.resolve_pending_event(option_id)
	assert_true(result.get("ok", false))
	assert_false(sim.has_pending_event())
	sim._draw_event_for_day(3)
	assert_false(sim.has_pending_event())
	assert_eq(sim.last_event_result.get("event_id", ""), event_id)

func test_short_term_effect_expires_after_duration() -> void:
	var sim := _setup_world_sim(1)
	sim.active_event_effects.append({
		"type": "output_multiplier",
		"output_type": "food",
		"multiplier": 0.5,
		"duration_days": 1,
		"remaining_days": 1,
		"starts_on_day": 2,
	})
	assert_true(EventEffects.effect_is_active(sim.active_event_effects[0], 2))
	sim._decrement_event_effects_after_day(2)
	assert_eq(sim.active_event_effects[0]["remaining_days"], 0)
	sim._expire_event_effects_before_day(3)
	assert_eq(sim.active_event_effects.size(), 0)

func test_resource_delta_effect_changes_strategic_resource() -> void:
	var sim := _setup_world_sim(1)
	var before := sim.store.get_resource("morale")
	var event := _single_option_event([
		{ "type": "resource_delta", "resource": "morale", "amount": 3 }
	])
	var result := EventEffects.apply_option(sim, event, "a")
	assert_true(result.get("ok", false))
	assert_eq(sim.store.get_resource("morale"), before + 3)

func test_villager_status_effect_changes_target_status() -> void:
	var sim := _setup_world_sim(1)
	var event := _single_option_event([
		{ "type": "villager_status", "target": "first_healthy", "status": "sick" }
	])
	var result := EventEffects.apply_option(sim, event, "a")
	assert_true(result.get("ok", false))
	assert_eq(sim.villagers[0].status, VillagerAgent.Status.SICK)

func test_output_multiplier_effect_changes_daily_output() -> void:
	var sim := _setup_world_sim(1)
	sim.game_time.day = 2
	sim.villagers[0].job = JobDefs.FARMER
	sim.active_policy = PolicyDefs.WOOD_FIRST
	sim.active_event_effects.append({
		"type": "output_multiplier",
		"output_type": "food",
		"multiplier": 0.5,
		"duration_days": 1,
		"remaining_days": 1,
		"starts_on_day": 2,
	})
	var summary := sim._resolve_policy_daily_resources()
	assert_eq(summary["food"], 1)

func test_risk_delta_effect_changes_hunter_injury_roll() -> void:
	var sim := _setup_world_sim(1)
	sim.game_time.day = 2
	sim.villagers[0].job = JobDefs.HUNTER
	sim.active_event_effects.append({
		"type": "risk_delta",
		"risk_type": "hunter_injury",
		"amount": 100,
		"duration_days": 1,
		"remaining_days": 1,
		"starts_on_day": 2,
	})
	var summary := sim._resolve_policy_daily_resources()
	assert_eq(summary["injured"], 1)
	assert_eq(sim.villagers[0].status, VillagerAgent.Status.INJURED)

func test_save_load_preserves_pending_event_and_effects() -> void:
	var sim := _setup_world_sim(1)
	sim.pending_event = sim.event_deck.get_event("weather_01")
	sim.active_event_effects.append({
		"type": "output_multiplier",
		"output_type": "food",
		"multiplier": 0.9,
		"duration_days": 2,
		"remaining_days": 2,
		"starts_on_day": 4,
		"source_event_id": "weather_01",
	})
	sim.last_event_result = { "ok": true, "event_id": "weather_01", "option_id": "a" }
	sim.last_event_day = 3
	var save := SaveManager.new()
	save.save(sim)
	sim.pending_event.clear()
	sim.active_event_effects.clear()
	sim.last_event_result.clear()
	sim.last_event_day = 0
	assert_true(save.load_into(sim))
	assert_eq(sim.pending_event.get("id", ""), "weather_01")
	assert_eq(sim.active_event_effects.size(), 1)
	assert_eq(sim.active_event_effects[0].get("source_event_id", ""), "weather_01")
	assert_eq(sim.last_event_result.get("event_id", ""), "weather_01")
	assert_eq(sim.last_event_day, 3)

func _single_option_event(immediate: Array) -> Dictionary:
	return {
		"id": "test_event",
		"title": "Test Event",
		"options": [
			{
				"id": "a",
				"label": "Apply",
				"result_text": "Applied.",
				"immediate": immediate,
				"short_term": null,
			}
		]
	}
