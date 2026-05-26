extends GutTest

const NatureSystemScript = preload("res://scripts/sim/nature_system.gd")

var balance: BalanceData
var nature: RefCounted
var wg: WorldGenerator

func before_each() -> void:
	balance = BalanceData.new()
	balance.nature_tree_regrowth_days = 2
	balance.nature_berry_regrowth_days = 1
	balance.nature_max_trees = 40
	balance.nature_max_berry_bushes = 40
	nature = NatureSystemScript.new()
	nature.setup(balance)
	wg = WorldGenerator.new()
	wg.generate_fixed(123, 10, 6, 4)

func test_tree_regrows_after_required_days() -> void:
	var tree := wg.get_tiles_of_type(WorldGenerator.TileType.TREE)[0]
	wg.set_tile(tree.x, tree.y, WorldGenerator.TileType.GRASS)
	nature.record_harvest(WorldGenerator.TileType.TREE, tree, 1)
	assert_eq(nature.update_day(2, wg).size(), 0)
	var changes: Array[Dictionary] = nature.update_day(3, wg)
	assert_eq(changes.size(), 1)
	assert_eq(wg.get_tile(changes[0]["pos"].x, changes[0]["pos"].y), WorldGenerator.TileType.TREE)

func test_berry_regrows_after_one_day() -> void:
	var bush := wg.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH)[0]
	wg.set_tile(bush.x, bush.y, WorldGenerator.TileType.GRASS)
	nature.record_harvest(WorldGenerator.TileType.BERRY_BUSH, bush, 1)
	var changes: Array[Dictionary] = nature.update_day(2, wg)
	assert_eq(changes.size(), 1)
	assert_eq(wg.get_tile(changes[0]["pos"].x, changes[0]["pos"].y), WorldGenerator.TileType.BERRY_BUSH)

func test_regrowth_respects_max_count() -> void:
	balance.nature_max_trees = wg.count_tiles_of_type(WorldGenerator.TileType.TREE) - 1
	var tree := wg.get_tiles_of_type(WorldGenerator.TileType.TREE)[0]
	wg.set_tile(tree.x, tree.y, WorldGenerator.TileType.GRASS)
	nature.record_harvest(WorldGenerator.TileType.TREE, tree, 1)
	var changes: Array[Dictionary] = nature.update_day(3, wg)
	assert_eq(changes.size(), 0)

func test_regrowth_does_not_overwrite_protected_tiles() -> void:
	nature.record_harvest(WorldGenerator.TileType.TREE, WorldGenerator.HUT_POS, 1)
	var changes: Array[Dictionary] = nature.update_day(3, wg)
	assert_eq(changes.size(), 1)
	assert_ne(changes[0]["pos"], WorldGenerator.HUT_POS)
	assert_eq(wg.get_tile(WorldGenerator.HUT_POS.x, WorldGenerator.HUT_POS.y), WorldGenerator.TileType.HUT)

func test_deer_count_increases_with_update_day() -> void:
	# deer_max_count defaults to 6; each update_day can spawn up to deer_spawn_per_day
	balance.deer_max_count = 6
	balance.deer_spawn_per_day = 2
	balance.world_seed = 123
	nature.setup(balance)
	nature.update_day(1, wg)
	nature.update_day(2, wg)
	nature.update_day(3, wg)
	assert_gt(nature.wildlife_food, 0, "At least one deer should have spawned after 3 days")

func test_remove_animal_decrements_wildlife_food() -> void:
	var deer := WildlifeAgent.new(99, WildlifeAgent.Kind.DEER, Vector2i(5, 5), 1)
	nature.animals.append(deer)
	assert_eq(nature.wildlife_food, 1)
	nature.remove_animal(99)
	assert_eq(nature.wildlife_food, 0)
