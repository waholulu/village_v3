extends GutTest

func test_tilemap_builds_atlas_for_all_tile_types() -> void:
	var wg := WorldGenerator.new()
	wg.generate_fixed()
	var tilemap: TileMapController = add_child_autoqfree(TileMapController.new())
	tilemap.setup(wg)
	assert_not_null(tilemap.tile_set)
	var source := tilemap.tile_set.get_source(0) as TileSetAtlasSource
	assert_not_null(source)
	for i in range(TileMapController.TILE_COLORS.size()):
		assert_true(source.has_tile(Vector2i(i, 0)))

func test_tilemap_uses_project_tilesheet_when_available() -> void:
	var wg := WorldGenerator.new()
	wg.generate_fixed()
	var tilemap: TileMapController = add_child_autoqfree(TileMapController.new())
	tilemap.setup(wg)
	var source := tilemap.tile_set.get_source(0) as TileSetAtlasSource
	var image := source.texture.get_image()
	var center := image.get_pixel(18, 18)
	assert_ne(center, TileMapController.TILE_COLORS[0], "Generated tilesheet should replace the flat color fallback")

func test_tilemap_populates_cells_from_world() -> void:
	var wg := WorldGenerator.new()
	wg.generate_fixed()
	var tilemap: TileMapController = add_child_autoqfree(TileMapController.new())
	tilemap.setup(wg)
	assert_eq(tilemap.get_cell_atlas_coords(WorldGenerator.HUT_POS), Vector2i(WorldGenerator.TileType.HUT, 0))
	assert_eq(tilemap.get_cell_atlas_coords(WorldGenerator.CAMPFIRE_POS), Vector2i(WorldGenerator.TileType.CAMPFIRE, 0))
