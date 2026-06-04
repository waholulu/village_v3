extends GutTest

func test_tilemap_builds_deterministic_ground_variant_atlas() -> void:
	var wg := WorldGenerator.new()
	wg.generate_fixed()
	var tilemap: TileMapController = add_child_autoqfree(TileMapController.new())
	tilemap.setup(wg)
	assert_not_null(tilemap.tile_set)
	var source := tilemap.tile_set.get_source(0) as TileSetAtlasSource
	assert_not_null(source)
	for i in range(TileMapController.GROUND_VARIANT_COUNT):
		assert_true(source.has_tile(Vector2i(i, 0)))

func test_tilemap_uses_project_tilesheet_when_available() -> void:
	var wg := WorldGenerator.new()
	wg.generate_fixed()
	var tilemap: TileMapController = add_child_autoqfree(TileMapController.new())
	tilemap.setup(wg)
	var source := tilemap.tile_set.get_source(0) as TileSetAtlasSource
	var image := source.texture.get_image()
	assert_eq(image.get_height(), TileMapController.TILE_SIZE)
	assert_eq(image.get_width(), TileMapController.TILE_SIZE * TileMapController.GROUND_VARIANT_COUNT)
	var center := image.get_pixel(TileMapController.TILE_SIZE / 2, TileMapController.TILE_SIZE / 2)
	assert_ne(center, TileMapController.TILE_COLORS[0], "Generated tilesheet should replace the flat color fallback")

func test_tilemap_uses_grass_ground_under_features() -> void:
	var wg := WorldGenerator.new()
	wg.generate_fixed()
	var tilemap: TileMapController = add_child_autoqfree(TileMapController.new())
	tilemap.setup(wg)
	assert_lt(tilemap.get_cell_atlas_coords(WorldGenerator.HUT_POS).x, TileMapController.GROUND_VARIANT_COUNT)
	assert_lt(tilemap.get_cell_atlas_coords(WorldGenerator.CAMPFIRE_POS).x, TileMapController.GROUND_VARIANT_COUNT)

func test_display_tile_size_is_32_pixels() -> void:
	assert_eq(TileMapController.TILE_SIZE, 32)
