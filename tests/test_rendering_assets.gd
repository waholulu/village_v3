extends GutTest

func test_wildlife_assets_are_square_tile_sized() -> void:
	for path in ["res://assets/wildlife_v2/deer.png", "res://assets/wildlife_v2/wolf.png"]:
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

func test_feature_assets_follow_grid_footprint_limits() -> void:
	var expected := {
		"tree.png": Vector2i(32, 48),
		"hut.png": Vector2i(48, 48),
		"house.png": Vector2i(48, 48),
		"watchtower.png": Vector2i(32, 48),
		"storage.png": Vector2i(48, 48),
	}
	for file_name in expected:
		var texture := load("res://assets/features/" + file_name) as Texture2D
		assert_not_null(texture)
		assert_eq(Vector2i(texture.get_width(), texture.get_height()), expected[file_name])

func test_feature_view_anchors_hut_bottom_center_to_grid() -> void:
	var wg := WorldGenerator.new()
	wg.generate_fixed()
	var view: FeatureView = add_child_autoqfree(FeatureView.new())
	view.setup(wg)
	var sprite := view._sprites[WorldGenerator.HUT_POS] as Sprite2D
	assert_eq(sprite.position.y + sprite.texture.get_height(), float((WorldGenerator.HUT_POS.y + 1) * FeatureView.TILE_SIZE))
	assert_eq(sprite.position.x + sprite.texture.get_width() / 2.0, float(WorldGenerator.HUT_POS.x * FeatureView.TILE_SIZE + FeatureView.TILE_SIZE / 2.0))
