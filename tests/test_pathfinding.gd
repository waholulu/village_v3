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
	# (1,1) and (2,1) are both trees in the fixed layout. Making both walkable
	# allows the direct 3-step path (0,1)->(1,1)->(2,1).
	var tree_pos = Vector2i(1, 1)
	pf.set_point_walkable(tree_pos, true)
	pf.set_point_walkable(Vector2i(2, 1), true)
	var path = pf.get_path(Vector2i(0, 1), Vector2i(2, 1))
	assert_eq(path.size(), 3, "Direct path should be (0,1)->(1,1)->(2,1)")
	assert_true(path.has(tree_pos), "Path should now traverse the previously blocked tile")

func test_path_to_solid_endpoint_is_empty() -> void:
	var tree_pos = wg.get_tiles_of_type(WorldGenerator.TileType.TREE)[0]
	var path = pf.get_path(Vector2i(5, 5), tree_pos)
	assert_eq(path.size(), 0)
