extends GutTest

# v3.1 Phase 0B: WIDTH / HEIGHT / HUT_POS / CAMPFIRE_POS are balance-driven
# static vars. generate_from_balance() applies them before any tile placement
# so all downstream call sites see the same dimensions used during generation.

func after_each() -> void:
	# Restore v3.1 defaults so later tests don't see leaked dimensions.
	WorldGenerator.WIDTH = 60
	WorldGenerator.HEIGHT = 40
	WorldGenerator.HUT_POS = Vector2i(15, 18)
	WorldGenerator.CAMPFIRE_POS = Vector2i(17, 19)

func test_world_dimensions_load_from_balance() -> void:
	var balance := BalanceData.new()
	balance.world_width = 50
	balance.world_height = 30
	balance.hut_pos_x = 12
	balance.hut_pos_y = 14
	balance.campfire_pos_x = 14
	balance.campfire_pos_y = 15
	balance.world_seed = 4312
	balance.world_tree_count = 20
	balance.world_berry_bush_count = 10
	balance.world_blocked_count = 10
	balance.world_noise_frequency = 0.08
	balance.world_starting_area_radius = 5
	balance.world_cellular_smoothing_passes = 2
	balance.world_noise_forest_threshold = 0.30
	balance.world_noise_rocky_threshold = -0.30
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	assert_eq(WorldGenerator.WIDTH, 50)
	assert_eq(WorldGenerator.HEIGHT, 30)
	assert_eq(wg.grid.size(), 30)
	assert_eq(wg.grid[0].size(), 50)

func test_hut_and_campfire_load_from_balance() -> void:
	var balance := BalanceData.new()
	balance.world_width = 50
	balance.world_height = 30
	balance.hut_pos_x = 12
	balance.hut_pos_y = 14
	balance.campfire_pos_x = 14
	balance.campfire_pos_y = 15
	balance.world_seed = 4312
	balance.world_tree_count = 20
	balance.world_berry_bush_count = 10
	balance.world_blocked_count = 10
	balance.world_noise_frequency = 0.08
	balance.world_starting_area_radius = 5
	balance.world_cellular_smoothing_passes = 2
	balance.world_noise_forest_threshold = 0.30
	balance.world_noise_rocky_threshold = -0.30
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	assert_eq(WorldGenerator.HUT_POS, Vector2i(12, 14))
	assert_eq(WorldGenerator.CAMPFIRE_POS, Vector2i(14, 15))
	# And the tiles actually exist where balance said they should be.
	assert_eq(wg.get_tile(12, 14), WorldGenerator.TileType.HUT)
	assert_eq(wg.get_tile(14, 15), WorldGenerator.TileType.CAMPFIRE)

func test_default_balance_produces_60x40_map() -> void:
	var balance := BalanceData.new()
	balance.load_from_file("res://data/balance.json")
	var wg := WorldGenerator.new()
	wg.generate_from_balance(balance)
	assert_eq(WorldGenerator.WIDTH, 60)
	assert_eq(WorldGenerator.HEIGHT, 40)
	assert_eq(WorldGenerator.HUT_POS, Vector2i(15, 18))
	assert_eq(WorldGenerator.CAMPFIRE_POS, Vector2i(17, 19))
