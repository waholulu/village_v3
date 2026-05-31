extends GutTest

var wg: WorldGenerator

func before_each() -> void:
	wg = WorldGenerator.new()
	wg.generate_fixed()

func test_grid_matches_static_dimensions() -> void:
	assert_eq(wg.grid.size(), WorldGenerator.HEIGHT)
	assert_eq(wg.grid[0].size(), WorldGenerator.WIDTH)

func test_campfire_at_balanced_position() -> void:
	assert_eq(wg.get_tile(WorldGenerator.CAMPFIRE_POS.x, WorldGenerator.CAMPFIRE_POS.y),
		WorldGenerator.TileType.CAMPFIRE)

func test_hut_placed() -> void:
	assert_eq(wg.get_tile(WorldGenerator.HUT_POS.x, WorldGenerator.HUT_POS.y),
		WorldGenerator.TileType.HUT)

func test_trees_placed() -> void:
	var trees = wg.get_tiles_of_type(WorldGenerator.TileType.TREE)
	assert_gt(trees.size(), 0)

func test_berry_bushes_placed() -> void:
	var bushes = wg.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH)
	assert_gt(bushes.size(), 0)

func test_build_sites_placed() -> void:
	var sites = wg.get_tiles_of_type(WorldGenerator.TileType.BUILD_SITE)
	assert_gt(sites.size(), 0)

func test_same_seed_generates_same_grid() -> void:
	var a := WorldGenerator.new()
	var b := WorldGenerator.new()
	a.generate_fixed(99, 20, 12, 10)
	b.generate_fixed(99, 20, 12, 10)
	assert_eq(_grid_signature(a), _grid_signature(b))

func test_different_seed_changes_grid() -> void:
	var a := WorldGenerator.new()
	var b := WorldGenerator.new()
	a.generate_fixed(99, 20, 12, 10)
	b.generate_fixed(100, 20, 12, 10)
	assert_ne(_grid_signature(a), _grid_signature(b))

func test_generated_resource_counts_follow_balance() -> void:
	var custom := WorldGenerator.new()
	custom.generate_fixed(50, 22, 13, 9)
	assert_eq(custom.count_tiles_of_type(WorldGenerator.TileType.TREE), 22)
	assert_eq(custom.count_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH), 13)

func test_resource_approaches_are_reachable_from_hut() -> void:
	assert_true(wg.all_resource_approaches_reachable())

func test_house_is_walkable_after_construction() -> void:
	var site = wg.find_next_build_site()
	wg.set_tile(site.x, site.y, WorldGenerator.TileType.HOUSE)
	assert_true(wg.is_walkable(site.x, site.y))

func test_out_of_bounds_returns_blocked() -> void:
	assert_eq(wg.get_tile(-1, 0), WorldGenerator.TileType.BLOCKED)
	assert_eq(wg.get_tile(WorldGenerator.WIDTH, 0), WorldGenerator.TileType.BLOCKED)
	assert_eq(wg.get_tile(0, WorldGenerator.HEIGHT), WorldGenerator.TileType.BLOCKED)

func test_is_in_bounds() -> void:
	assert_true(wg.is_in_bounds(Vector2i(0, 0)))
	assert_true(wg.is_in_bounds(Vector2i(WorldGenerator.WIDTH - 1, WorldGenerator.HEIGHT - 1)))
	assert_false(wg.is_in_bounds(Vector2i(-1, 0)))
	assert_false(wg.is_in_bounds(Vector2i(WorldGenerator.WIDTH, 0)))

func test_grass_is_walkable() -> void:
	# A tile adjacent to HUT is always cleared by _can_place_resource_tile, so
	# it's guaranteed walkable regardless of where the village sits on the map.
	var near_hut: Vector2i = WorldGenerator.HUT_POS + Vector2i(1, 0)
	assert_true(wg.is_walkable(near_hut.x, near_hut.y))

func test_tree_is_not_walkable() -> void:
	var trees = wg.get_tiles_of_type(WorldGenerator.TileType.TREE)
	assert_false(wg.is_walkable(trees[0].x, trees[0].y))

func test_hut_is_walkable() -> void:
	assert_true(wg.is_walkable(WorldGenerator.HUT_POS.x, WorldGenerator.HUT_POS.y))

func test_campfire_is_walkable() -> void:
	assert_true(wg.is_walkable(WorldGenerator.CAMPFIRE_POS.x, WorldGenerator.CAMPFIRE_POS.y))

func test_find_walkable_adjacent_for_tree_returns_grass() -> void:
	var trees = wg.get_tiles_of_type(WorldGenerator.TileType.TREE)
	var adj = wg.find_walkable_adjacent(trees[0])
	assert_ne(adj, Vector2i(-1, -1))
	assert_true(wg.is_walkable(adj.x, adj.y))

func test_find_walkable_adjacent_for_isolated_returns_sentinel() -> void:
	# Pick an isolated test cell, then surround it with TREE on all 4 sides.
	var center := WorldGenerator.HUT_POS + Vector2i(5, 5)
	wg.set_tile(center.x, center.y - 1, WorldGenerator.TileType.TREE)
	wg.set_tile(center.x, center.y + 1, WorldGenerator.TileType.TREE)
	wg.set_tile(center.x - 1, center.y, WorldGenerator.TileType.TREE)
	wg.set_tile(center.x + 1, center.y, WorldGenerator.TileType.TREE)
	var adj = wg.find_walkable_adjacent(center)
	assert_eq(adj, Vector2i(-1, -1))

func _grid_signature(world_gen: WorldGenerator) -> String:
	var parts: Array[String] = []
	for y in range(WorldGenerator.HEIGHT):
		for x in range(WorldGenerator.WIDTH):
			parts.append(str(world_gen.get_tile(x, y)))
	return ",".join(parts)
