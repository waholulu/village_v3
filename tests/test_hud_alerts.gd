extends GutTest

const AlertRulesScript = preload("res://scripts/ui/alert_rules.gd")

func test_hud_alerts_show_zero_streak_and_monitor_anomaly() -> void:
	var sim := _setup_hud_sim()
	var hud: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	hud.setup(sim)
	sim.store.set_resource("food", 0)
	sim.zero_food_days = 2
	sim.monitor_anomalies = [{
		"code": "task_approach_unwalkable",
		"severity": "error",
		"message": "Task approach blocked",
	}]
	hud._refresh_alerts()
	var alert_panel := hud.get_node("AlertPanel") as Panel
	var lbl_alerts := hud.get_node("AlertPanel/LblAlerts") as Label
	assert_true(alert_panel.visible)
	assert_string_contains(lbl_alerts.text, "Food depleted")
	assert_string_contains(lbl_alerts.text, "Loss in 1 daily resolution")
	assert_string_contains(lbl_alerts.text, "Simulation warning")
	assert_string_contains(lbl_alerts.text, "Task approach blocked")

func test_hud_alert_stack_is_limited_to_four_lines() -> void:
	var sim := _setup_hud_sim()
	var hud: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	hud.setup(sim)
	sim.store.set_resource("population", 1)
	sim.store.set_resource("food", 0)
	sim.store.set_resource("morale", 0)
	sim.store.set_resource("security", 0)
	sim.store.set_resource("wood", 0)
	sim.zero_food_days = 2
	sim.zero_morale_days = 2
	sim.zero_security_days = 2
	sim.campfire_out_nights = sim._balance.max_campfire_out_nights - 1
	sim.monitor_anomalies = [{
		"code": "negative_resource",
		"severity": "error",
		"message": "Negative resource",
	}]
	hud._refresh_alerts()
	var text := (hud.get_node("AlertPanel/LblAlerts") as Label).text
	assert_lte(text.split("\n", false).size(), AlertRulesScript.MAX_ALERTS)

func test_alert_panel_pushes_tile_inspector_down() -> void:
	var sim := _setup_hud_sim()
	var hud: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	hud.setup(sim)
	sim.store.set_resource("food", 0)
	hud._refresh_alerts()
	hud.update_tile_inspector({
		"in_bounds": true,
		"x": 1,
		"y": 1,
		"tile_name": "Grass",
		"walkable": true,
		"feature_label": "Grass",
		"villagers": [],
		"animals": [],
		"tasks": [],
	})
	hud._layout_for_viewport()
	var alert_panel := hud.get_node("AlertPanel") as Panel
	var inspector_panel := hud.get_node("InspectorPanel") as Panel
	assert_true(alert_panel.visible)
	assert_true(inspector_panel.visible)
	assert_gt(inspector_panel.position.y, alert_panel.position.y + alert_panel.size.y)

func _setup_hud_sim() -> VillageSimulation:
	var balance := BalanceData.new()
	balance.villager_count = 1
	balance.starting_population = 1
	balance.starting_population_capacity = 1
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	return sim
