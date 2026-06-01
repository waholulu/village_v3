extends GutTest

var sim: VillageSimulation

func before_each() -> void:
	sim = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(10, 8, 3)

func test_night_consumes_food_per_villager() -> void:
	sim.resolve_night()
	assert_eq(sim.store.get_resource("fresh_food"), 5)
	assert_eq(sim.store.get_resource("food"), 5)

func test_night_feeding_uses_authoritative_food_pool() -> void:
	sim.setup_for_test(10, 0, 3)
	sim.store.set_resource("food", 3)
	sim.resolve_night()
	assert_eq(sim.hungry_villagers, 0)
	assert_eq(sim.store.get_resource("food"), 0)
	assert_eq(sim.store.get_total_food(), 0)

func test_night_consumes_wood_for_campfire() -> void:
	sim.resolve_night()
	assert_eq(sim.store.get_resource("wood"), 8)

func test_food_shortage_tracks_hungry_villagers() -> void:
	sim.setup_for_test(10, 1, 3)
	sim.resolve_night()
	assert_eq(sim.store.get_resource("fresh_food"), 0)
	assert_eq(sim.hungry_villagers, 2)

func test_fed_villager_hunger_decreases() -> void:
	sim.setup_for_test(10, 1, 1)
	sim.villagers[0].hunger = 2
	sim.resolve_night()
	assert_eq(sim.villagers[0].hunger, 1)
	assert_eq(sim.hungry_villagers, 1)

func test_unfed_villager_hunger_increases() -> void:
	sim.setup_for_test(10, 0, 1)
	sim.resolve_night()
	assert_eq(sim.villagers[0].hunger, 1)
	assert_eq(sim.hungry_villagers, 1)

func test_starvation_loses_game() -> void:
	watch_signals(sim)
	sim.setup_for_test(10, 0, 1)
	sim.villagers[0].hunger = 2
	sim.resolve_night()
	assert_signal_emitted(sim, "game_lost")

func test_food_does_not_go_negative() -> void:
	sim.setup_for_test(10, 0, 3)
	sim.resolve_night()
	assert_gte(sim.store.get_resource("fresh_food"), 0)

func test_campfire_out_counter_increases_when_no_wood() -> void:
	sim.setup_for_test(0, 8, 3)
	sim.resolve_night()
	assert_eq(sim.campfire_out_nights, 1)

func test_campfire_out_counter_resets_when_wood_present() -> void:
	sim.setup_for_test(0, 8, 3)
	sim.resolve_night()
	sim.store.add_resource("wood", 10)
	sim.resolve_night()
	assert_eq(sim.campfire_out_nights, 0)

func test_game_lost_after_two_campfire_out_nights() -> void:
	watch_signals(sim)
	sim.setup_for_test(0, 10, 3)
	sim.resolve_night()
	sim.resolve_night()
	assert_signal_emitted(sim, "game_lost")

func test_game_not_lost_after_one_campfire_out_night() -> void:
	watch_signals(sim)
	sim.setup_for_test(0, 10, 3)
	sim.resolve_night()
	assert_signal_not_emitted(sim, "game_lost")

func test_game_won_signal_forwarded() -> void:
	watch_signals(sim)
	sim.game_time.setup(0.001, 0.001, 1)
	sim._balance.days_per_season = 1
	for i in range(14):
		sim.game_time._advance_phase()
	assert_signal_emitted(sim, "game_won")

func test_setup_for_test_is_idempotent() -> void:
	sim.setup_for_test(5, 5, 3)
	assert_eq(sim.villagers.size(), 3, "Villager array must not accumulate across setup calls")
	assert_eq(sim.store.get_resource("wood"), 5)
	assert_eq(sim.store.get_resource("fresh_food"), 5)
	assert_eq(sim.campfire_out_nights, 0)
