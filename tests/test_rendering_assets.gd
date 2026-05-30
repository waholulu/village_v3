extends GutTest

func test_wildlife_assets_are_square_tile_sized() -> void:
	for path in ["res://assets/wildlife/deer.png", "res://assets/wildlife/wolf.png"]:
		var texture := load(path) as Texture2D
		assert_not_null(texture)
		assert_eq(texture.get_width(), WildlifeView.TILE_SIZE)
		assert_eq(texture.get_height(), WildlifeView.TILE_SIZE)

func test_wildlife_view_positions_on_tile_grid() -> void:
	var view: WildlifeView = add_child_autoqfree(WildlifeView.new())
	view.setup_animals([{"kind": WildlifeAgent.Kind.DEER, "x": 3, "y": 4}])
	view._process(0.0)
	var sprite := view.get_child(0) as Sprite2D
	assert_not_null(sprite)
	assert_eq(sprite.position, Vector2(3, 4) * WildlifeView.TILE_SIZE)

func test_villager_view_positions_on_tile_grid() -> void:
	var view: VillagerView = add_child_autoqfree(VillagerView.new())
	var villager := VillagerAgent.new(1, "Test", Vector2i(2, 5))
	var villagers: Array[VillagerAgent] = [villager]
	view.setup(villagers)
	view._process(0.0)
	var sprite := view.get_child(0) as Sprite2D
	assert_not_null(sprite)
	assert_eq(sprite.position, Vector2(2, 5) * VillagerView.TILE_SIZE)
