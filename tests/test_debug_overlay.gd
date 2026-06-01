extends GutTest

func test_f3_toggles_debug_overlay_and_renders_current_snapshot() -> void:
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup_for_test(25, 12, 3)
	var overlay: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/debug_overlay.tscn").instantiate())
	overlay.setup(sim)
	var panel: Panel = overlay.get_node("Panel")
	var label: Label = overlay.get_node("Panel/LblDebug")
	assert_false(panel.visible)

	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_F3
	overlay._input(event)
	assert_true(panel.visible)

	overlay._process(0.0)
	assert_string_contains(label.text, "=== DEBUG (F3) ===")
	assert_string_contains(label.text, "Living / dead:")

	overlay._input(event)
	assert_false(panel.visible)
