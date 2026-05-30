extends GutTest

var _previous_time_scale := 1.0

func before_each() -> void:
	_previous_time_scale = Engine.time_scale
	Engine.time_scale = 1.0

func after_each() -> void:
	Engine.time_scale = _previous_time_scale

func test_hud_speed_buttons_update_engine_time_scale() -> void:
	var hud: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	var btn_speed_2 := hud.get_node("Panel/BtnSpeed2") as Button
	var lbl_speed := hud.get_node("Panel/LblSpeed") as Label
	btn_speed_2.pressed.emit()
	assert_eq(Engine.time_scale, 2.0)
	assert_eq(lbl_speed.text, "Speed: 2x")

func test_speed_changed_signal_updates_hud_label() -> void:
	var hud: CanvasLayer = add_child_autoqfree(preload("res://scenes/ui/hud.tscn").instantiate())
	var lbl_speed := hud.get_node("Panel/LblSpeed") as Label
	Events.speed_changed.emit(4.0)
	assert_eq(lbl_speed.text, "Speed: 4x")
