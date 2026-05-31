extends GutTest

var sim: VillageSimulation
var wg: WorldGenerator
var pf: PathfindingService

func before_each() -> void:
	var balance := BalanceData.new()
	balance.starting_wood = 10
	balance.starting_fresh_food = 8
	balance.starting_stored_food = 0
	balance.villager_count = 1
	balance.starting_population_capacity = 3
	balance.day_duration_seconds = 10.0
	balance.night_duration_seconds = 5.0
	balance.days_per_season = 5
	wg = WorldGenerator.new()
	wg.generate_fixed()
	pf = PathfindingService.new()
	pf.setup(wg)
	sim = add_child_autoqfree(VillageSimulation.new())
	sim.setup(balance, wg, pf)

func test_load_out_of_bounds_villager_position_resets_to_valid_spawn() -> void:
	_write_save_with_villager_position(Vector2i(WorldGenerator.WIDTH, WorldGenerator.HEIGHT))
	var loaded := SaveManager.new().load_into(sim)
	assert_true(loaded)
	var pos := sim.villagers[0].tile_position
	assert_true(wg.is_in_bounds(pos))
	assert_true(wg.is_walkable(pos.x, pos.y))

func test_load_unwalkable_villager_position_resets_to_valid_spawn() -> void:
	var tree_pos := wg.get_tiles_of_type(WorldGenerator.TileType.TREE)[0]
	_write_save_with_villager_position(tree_pos)
	var loaded := SaveManager.new().load_into(sim)
	assert_true(loaded)
	var pos := sim.villagers[0].tile_position
	assert_ne(pos, tree_pos)
	assert_true(wg.is_in_bounds(pos))
	assert_true(wg.is_walkable(pos.x, pos.y))

func _write_save_with_villager_position(pos: Vector2i) -> void:
	# Uses backward-compat save format (old "food" key, no "tiles").
	# load_into handles both: fresh_food = data.get("fresh_food", data.get("food", 0))
	# and _restore_grid skips gracefully when "tiles" is absent.
	var data = {
		"day": 1,
		"phase": "Day",
		"tick": 0,
		"wood": 10,
		"food": 8,
		"campfire_out_nights": 0,
		"hungry_villagers": 0,
		"population_capacity": 3,
		"villagers": [
			{
				"id": 1,
				"name": "Alice",
				"tile_x": pos.x,
				"tile_y": pos.y,
				"state": "IDLE",
				"hunger": 0,
				"current_task_id": -1
			}
		],
		"tasks": [],
		"houses": []
	}
	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
