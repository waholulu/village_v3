extends GutTest

func _make_balance(seed: int = 4312) -> BalanceData:
	var b := BalanceData.new()
	b.world_seed = seed
	b.world_tree_count = 20
	b.world_berry_bush_count = 12
	b.world_blocked_count = 10
	b.world_noise_frequency = 0.08
	b.world_noise_forest_threshold = 0.30
	b.world_noise_rocky_threshold = -0.30
	b.world_starting_area_radius = 5
	b.world_cellular_smoothing_passes = 2
	return b

func test_noise_tree_count_matches_balance() -> void:
	var wg := WorldGenerator.new()
	var b := _make_balance()
	wg.generate_from_balance(b)
	assert_eq(wg.count_tiles_of_type(WorldGenerator.TileType.TREE), b.world_tree_count)

func test_noise_berry_count_matches_balance() -> void:
	var wg := WorldGenerator.new()
	var b := _make_balance()
	wg.generate_from_balance(b)
	assert_eq(wg.count_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH), b.world_berry_bush_count)

func test_noise_blocked_count_within_tolerance() -> void:
	var wg := WorldGenerator.new()
	var b := _make_balance()
	wg.generate_from_balance(b)
	var actual := wg.count_tiles_of_type(WorldGenerator.TileType.BLOCKED)
	# Cellular automata may cause slight drift; allow ±2
	assert_gte(actual, b.world_blocked_count - 2)
	assert_lte(actual, b.world_blocked_count + 2)

func test_noise_same_seed_deterministic() -> void:
	var wg1 := WorldGenerator.new()
	var wg2 := WorldGenerator.new()
	var b := _make_balance(9999)
	wg1.generate_from_balance(b)
	wg2.generate_from_balance(b)
	for y in range(WorldGenerator.HEIGHT):
		for x in range(WorldGenerator.WIDTH):
			assert_eq(wg1.get_tile(x, y), wg2.get_tile(x, y),
				"Mismatch at (%d,%d)" % [x, y])

func test_noise_different_seed_differs() -> void:
	var wg1 := WorldGenerator.new()
	var wg2 := WorldGenerator.new()
	wg1.generate_from_balance(_make_balance(1111))
	wg2.generate_from_balance(_make_balance(2222))
	var diffs := 0
	for y in range(WorldGenerator.HEIGHT):
		for x in range(WorldGenerator.WIDTH):
			if wg1.get_tile(x, y) != wg2.get_tile(x, y):
				diffs += 1
	assert_gt(diffs, 10, "Two different seeds should produce clearly different grids")

func test_noise_all_resources_reachable() -> void:
	var wg := WorldGenerator.new()
	wg.generate_from_balance(_make_balance())
	assert_true(wg.all_resource_approaches_reachable(),
		"All tree/bush tiles must have a reachable adjacent walkable tile")

func test_noise_starting_area_clear() -> void:
	var wg := WorldGenerator.new()
	var b := _make_balance()
	wg.generate_from_balance(b)
	var r := b.world_starting_area_radius
	for y in range(WorldGenerator.HEIGHT):
		for x in range(WorldGenerator.WIDTH):
			var pos := Vector2i(x, y)
			if (pos - WorldGenerator.HUT_POS).length_squared() <= r * r:
				var t := wg.get_tile(x, y)
				assert_ne(t, WorldGenerator.TileType.TREE,
					"TREE in starting area at (%d,%d)" % [x, y])
				assert_ne(t, WorldGenerator.TileType.BLOCKED,
					"BLOCKED in starting area at (%d,%d)" % [x, y])
				assert_ne(t, WorldGenerator.TileType.BERRY_BUSH,
					"BERRY_BUSH in starting area at (%d,%d)" % [x, y])

func test_noise_hut_and_campfire_placed() -> void:
	var wg := WorldGenerator.new()
	wg.generate_from_balance(_make_balance())
	assert_eq(wg.get_tile(WorldGenerator.HUT_POS.x, WorldGenerator.HUT_POS.y),
		WorldGenerator.TileType.HUT)
	assert_eq(wg.get_tile(WorldGenerator.CAMPFIRE_POS.x, WorldGenerator.CAMPFIRE_POS.y),
		WorldGenerator.TileType.CAMPFIRE)
