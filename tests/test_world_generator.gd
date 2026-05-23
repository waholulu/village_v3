extends GutTest

var wg: WorldGenerator

func before_each() -> void:
	wg = WorldGenerator.new()
	wg.generate_fixed()

func test_grid_is_12x12() -> void:
	assert_eq(wg.grid.size(), 12)
	assert_eq(wg.grid[0].size(), 12)

func test_campfire_at_center() -> void:
	assert_eq(wg.get_tile(6, 6), WorldGenerator.TileType.CAMPFIRE)

func test_hut_placed() -> void:
	assert_eq(wg.get_tile(4, 5), WorldGenerator.TileType.HUT)

func test_trees_placed() -> void:
	var trees = wg.get_tiles_of_type(WorldGenerator.TileType.TREE)
	assert_gt(trees.size(), 0)

func test_berry_bushes_placed() -> void:
	var bushes = wg.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH)
	assert_gt(bushes.size(), 0)

func test_out_of_bounds_returns_blocked() -> void:
	assert_eq(wg.get_tile(-1, 0), WorldGenerator.TileType.BLOCKED)
	assert_eq(wg.get_tile(12, 0), WorldGenerator.TileType.BLOCKED)

func test_grass_is_walkable() -> void:
	assert_true(wg.is_walkable(5, 5))

func test_tree_is_not_walkable() -> void:
	var trees = wg.get_tiles_of_type(WorldGenerator.TileType.TREE)
	assert_false(wg.is_walkable(trees[0].x, trees[0].y))

func test_hut_is_walkable() -> void:
	assert_true(wg.is_walkable(4, 5))

func test_campfire_is_walkable() -> void:
	assert_true(wg.is_walkable(6, 6))

func test_find_walkable_adjacent_for_tree_returns_grass() -> void:
	var trees = wg.get_tiles_of_type(WorldGenerator.TileType.TREE)
	var adj = wg.find_walkable_adjacent(trees[0])
	assert_ne(adj, Vector2i(-1, -1))
	assert_true(wg.is_walkable(adj.x, adj.y))

func test_find_walkable_adjacent_for_isolated_returns_sentinel() -> void:
	wg.set_tile(5, 4, WorldGenerator.TileType.TREE)
	wg.set_tile(5, 6, WorldGenerator.TileType.TREE)
	wg.set_tile(4, 5, WorldGenerator.TileType.TREE)  # overrides hut for this test
	wg.set_tile(6, 5, WorldGenerator.TileType.TREE)
	var adj = wg.find_walkable_adjacent(Vector2i(5, 5))
	assert_eq(adj, Vector2i(-1, -1))
