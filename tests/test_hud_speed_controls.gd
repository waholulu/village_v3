extends GutTest

var _previous_time_scale := 1.0

func before_each() -> void:
	_previous_time_scale = Engine.time_scale
	Engine.time_scale = 1.0

func after_each() -> void:
	Engine.time_scale = _previous_time_scale

func test_hud_speed_buttons_update_engine_time_scale() -> void:
	var hud: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	var btn_speed_2 := hud.get_node("Panel/TopRow/BtnSpeed2") as Button
	var lbl_speed := hud.get_node("Panel/TopRow/LblSpeed") as Label
	btn_speed_2.pressed.emit()
	assert_eq(Engine.time_scale, 2.0)
	assert_eq(lbl_speed.text, "Speed: 2x")

func test_speed_changed_signal_updates_hud_label() -> void:
	var hud: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	var lbl_speed := hud.get_node("Panel/TopRow/LblSpeed") as Label
	Events.speed_changed.emit(4.0)
	assert_eq(lbl_speed.text, "Speed: 4x")

func test_hud_setup_shows_day_clock_label() -> void:
	var sim := _setup_hud_sim()
	var hud: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	hud.setup(sim)
	var lbl_day := hud.get_node("Panel/TopRow/LblDay") as Label
	assert_eq(lbl_day.text, "Day 1 - Spring 06:00")

func test_hud_clock_signal_updates_day_label() -> void:
	var sim := _setup_hud_sim()
	var hud: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	hud.setup(sim)
	var lbl_day := hud.get_node("Panel/TopRow/LblDay") as Label
	sim.game_time._process(5.0)
	assert_eq(lbl_day.text, "Day 1 - Spring 12:00")

func test_hud_ten_x_button_updates_engine_time_scale() -> void:
	var hud: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	var btn_speed_10 := hud.get_node("Panel/TopRow/BtnSpeed10") as Button
	btn_speed_10.pressed.emit()
	assert_eq(Engine.time_scale, 10.0)
	assert_eq((hud.get_node("Panel/TopRow/LblSpeed") as Label).text, "Speed: 10x")

func test_policy_choice_blocks_and_restores_ten_x_speed() -> void:
	var sim := _setup_hud_sim()
	var hud = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	hud.setup(sim)
	Engine.time_scale = 10.0
	hud.enable_blocking_choices()
	hud._sync_blocking_state()
	assert_true(hud.is_blocking())
	assert_eq(Engine.time_scale, 0.0)
	hud._choose_policy(PolicyDefs.FOOD_FIRST)
	assert_false(hud.is_blocking())
	assert_eq(Engine.time_scale, 10.0)

func test_sync_after_load_refreshes_policy_and_effect_labels() -> void:
	var sim := _setup_hud_sim()
	var hud = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	hud.setup(sim)
	sim.active_policy = PolicyDefs.DEFENSE_FIRST
	sim.active_event_effects.append({
		"type": "resource_multiplier",
		"label": "Guarded",
		"remaining_days": 2,
	})
	hud.sync_after_load()
	assert_eq((hud.get_node("Panel/BottomRow/LblPolicy") as Label).text, "Policy: Defense First")
	assert_eq((hud.get_node("Panel/BottomRow/LblEffects") as Label).text, "Effects: Guarded (2d)")

func test_event_pending_keeps_policy_choice_as_first_blocking_modal() -> void:
	var sim := _setup_hud_sim()
	var hud = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	hud.setup(sim)
	hud.enable_blocking_choices()
	sim.pending_event = {"title": "Test event", "options": []}
	hud._on_event_pending(sim.pending_event)
	await wait_process_frames(1)
	assert_true((hud.get_node("PolicyPanel") as Panel).visible)
	assert_false((hud.get_node("EventPanel") as Panel).visible)

func test_event_option_rebuild_removes_old_buttons_immediately() -> void:
	var hud = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	var first_event := {"title": "First", "options": [{"id": "a", "label": "A"}]}
	var second_event := {"title": "Second", "options": [{"id": "b", "label": "B"}, {"id": "c", "label": "C"}]}
	hud._show_event_panel(first_event)
	hud._show_event_panel(second_event)
	assert_eq(hud.get_node("EventPanel/Options").get_child_count(), 2)

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
