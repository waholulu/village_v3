extends GutTest

var wg: WorldGenerator
var pf: PathfindingService

func before_each() -> void:
	wg = WorldGenerator.new()
	wg.generate_fixed()
	pf = PathfindingService.new()
	pf.setup(wg)

func test_path_from_a_to_b_is_not_empty() -> void:
	var path = pf.get_path(Vector2i(5, 5), Vector2i(7, 7))
	assert_gt(path.size(), 0)

func test_path_starts_at_origin() -> void:
	var path = pf.get_path(Vector2i(5, 5), Vector2i(7, 7))
	assert_eq(path[0], Vector2i(5, 5))

func test_path_ends_at_destination() -> void:
	var path = pf.get_path(Vector2i(5, 5), Vector2i(7, 7))
	assert_eq(path[path.size() - 1], Vector2i(7, 7))

func test_path_to_same_tile_is_single_element() -> void:
	var path = pf.get_path(Vector2i(5, 5), Vector2i(5, 5))
	assert_eq(path.size(), 1)

func test_path_does_not_go_through_tree() -> void:
	var path = pf.get_path(Vector2i(5, 5), Vector2i(7, 7))
	for step in path:
		assert_ne(wg.get_tile(step.x, step.y), WorldGenerator.TileType.TREE)

func test_update_walkability_allows_new_path() -> void:
	var tree_pos = wg.get_tiles_of_type(WorldGenerator.TileType.TREE)[0]
	var approach = wg.find_walkable_adjacent(tree_pos)
	assert_ne(approach, Vector2i(-1, -1))
	var original_path = pf.get_path(approach, tree_pos)
	assert_eq(original_path.size(), 0)
	pf.set_point_walkable(tree_pos, true)
	var path = pf.get_path(approach, tree_pos)
	assert_gt(path.size(), 0)
	assert_true(path.has(tree_pos), "Path should now traverse the previously blocked tile")

func test_path_to_solid_endpoint_is_empty() -> void:
	var tree_pos = wg.get_tiles_of_type(WorldGenerator.TileType.TREE)[0]
	var path = pf.get_path(Vector2i(5, 5), tree_pos)
	assert_eq(path.size(), 0)

func test_constructed_house_is_walkable() -> void:
	var site = wg.find_next_build_site()
	wg.set_tile(site.x, site.y, WorldGenerator.TileType.HOUSE)
	pf.set_point_walkable(site, true)
	var path = pf.get_path(Vector2i(5, 5), site)
	assert_gt(path.size(), 0)
	assert_eq(path[path.size() - 1], site)

func test_out_of_bounds_start_returns_empty_path() -> void:
	var path = pf.get_path(Vector2i(-1, 0), Vector2i(5, 5))
	assert_eq(path.size(), 0)

func test_out_of_bounds_end_returns_empty_path() -> void:
	var path = pf.get_path(Vector2i(5, 5), Vector2i(WorldGenerator.WIDTH, 0))
	assert_eq(path.size(), 0)

func test_set_point_walkable_ignores_out_of_bounds() -> void:
	pf.set_point_walkable(Vector2i(-1, 0), true)
	pf.set_point_walkable(Vector2i(WorldGenerator.WIDTH, WorldGenerator.HEIGHT), false)
	pass_test("Out-of-bounds walkability updates should not error")
