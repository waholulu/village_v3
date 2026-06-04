extends GutTest

func _setup_world_sim() -> VillageSimulation:
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	var pf := PathfindingService.new()
	pf.setup(wg)
	var sim: VillageSimulation = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)
	return sim

func _find_selectable_world_point(main_scene: Node2D) -> Vector2:
	var viewport_size := main_scene.get_viewport_rect().size
	for y in range(0, int(viewport_size.y), 24):
		for x in range(0, int(viewport_size.x), 24):
			var point := Vector2(x, y)
			if main_scene._hud.is_screen_point_over_ui(point):
				continue
			main_scene._clear_selected_tile()
			main_scene._handle_left_click(point)
			if main_scene.has_selected_tile():
				return point
	main_scene._clear_selected_tile()
	return Vector2(-1, -1)

func test_inspect_tile_reports_resource_tile_details() -> void:
	var sim := _setup_world_sim()
	var trees := sim.world_gen.get_tiles_of_type(WorldGenerator.TileType.TREE)
	assert_gt(trees.size(), 0)
	var info := sim.inspect_tile(trees[0])
	assert_true(info["in_bounds"])
	assert_eq(info["tile_name"], "Tree")
	assert_eq(info["feature_kind"], "resource")
	assert_eq(info["feature_label"], "Wood source")
	assert_false(info["walkable"])

func test_inspect_tile_includes_villagers_animals_and_tasks() -> void:
	var sim := _setup_world_sim()
	var pos := WorldGenerator.CAMPFIRE_POS
	sim.villagers[0].tile_position = pos
	sim.nature.animals.append(WildlifeAgent.new(999, WildlifeAgent.Kind.DEER, pos, 1))
	sim.board.create_task("guard_watch", pos, 0)
	var info := sim.inspect_tile(pos)
	var villager_names: Array[String] = []
	for villager_info in info["villagers"]:
		villager_names.append(villager_info["name"])
	assert_eq(info["tile_name"], "Campfire")
	assert_true(sim.villagers[0].name in villager_names)
	assert_eq(info["animals"].size(), 1)
	assert_eq(info["animals"][0]["kind_name"], "Deer")
	assert_eq(info["tasks"].size(), 1)
	assert_eq(info["tasks"][0]["relation"], "target+approach")

func test_inspect_tile_reports_approach_relation_for_resource_tasks() -> void:
	var sim := _setup_world_sim()
	var tree_pos := sim.world_gen.get_tiles_of_type(WorldGenerator.TileType.TREE)[0]
	var approach := sim.world_gen.find_walkable_adjacent(tree_pos)
	var task := sim.board.create_task("chop_tree", tree_pos, 0)
	task.approach_tile = approach
	var target_info := sim.inspect_tile(tree_pos)
	var approach_info := sim.inspect_tile(approach)
	assert_eq(target_info["tasks"][0]["relation"], "target")
	assert_eq(approach_info["tasks"][0]["relation"], "approach")

func test_clicking_hud_does_not_select_tile_and_clicking_outside_map_clears_selection() -> void:
	var main_scene: Node2D = add_child_autoqfree(preload("res://scenes/main/main.tscn").instantiate())
	var window := main_scene.get_window()
	if window != null:
		window.size = Vector2i(1280, 720)
	await wait_process_frames(2)
	main_scene._hud._choose_policy(PolicyDefs.FOOD_FIRST)
	main_scene._handle_left_click(Vector2(10, 10))
	assert_false(main_scene.has_selected_tile())
	var world_point := _find_selectable_world_point(main_scene)
	assert_ne(world_point, Vector2(-1, -1))
	assert_true(main_scene.has_selected_tile())
	assert_eq(main_scene.get_selected_tile(), main_scene._tilemap.get_selected_tile())
	main_scene._handle_left_click(Vector2(-50, -50))
	assert_false(main_scene.has_selected_tile())

func test_mouse_wheel_over_hud_does_not_zoom_world() -> void:
	var main_scene: Node2D = add_child_autoqfree(preload("res://scenes/main/main.tscn").instantiate())
	await wait_process_frames(2)
	main_scene._hud._choose_policy(PolicyDefs.FOOD_FIRST)
	main_scene._set_camera_zoom(1)
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(20, 20)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	main_scene._input(wheel)
	assert_eq(main_scene.get_camera_zoom_multiplier(), 1)
