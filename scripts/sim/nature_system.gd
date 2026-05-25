class_name NatureSystem
extends RefCounted

var wildlife_food: int = 0
var _balance: BalanceData
var _pending_regrowth: Array[Dictionary] = []
var _last_update_day: int = 1

func setup(balance: BalanceData) -> void:
	_balance = balance
	wildlife_food = balance.wildlife_food_start
	_pending_regrowth.clear()
	_last_update_day = 1

func record_harvest(tile_type: int, pos: Vector2i, day: int) -> void:
	if tile_type != WorldGenerator.TileType.TREE and tile_type != WorldGenerator.TileType.BERRY_BUSH:
		return
	_pending_regrowth.append({
		"type": tile_type,
		"origin": pos,
		"day": day
	})

func update_day(day: int, world_gen: WorldGenerator) -> Array[Dictionary]:
	_last_update_day = day
	var changes: Array[Dictionary] = []
	_grow_wildlife()
	var remaining: Array[Dictionary] = []
	for record in _pending_regrowth:
		var tile_type: int = record["type"]
		var age: int = day - int(record["day"])
		var required_age := _required_age_for(tile_type)
		if age < required_age:
			remaining.append(record)
			continue
		if _count_for(world_gen, tile_type) >= _max_for(tile_type):
			remaining.append(record)
			continue
		var planted := _try_regrow(record, world_gen)
		if planted.is_empty():
			remaining.append(record)
		else:
			changes.append(planted)
	_pending_regrowth = remaining
	return changes

func consume_wildlife_food(amount: int) -> int:
	var consumed := mini(wildlife_food, amount)
	wildlife_food -= consumed
	return consumed

func get_pending_count(tile_type: int) -> int:
	var count := 0
	for record in _pending_regrowth:
		if int(record["type"]) == tile_type:
			count += 1
	return count

func get_summary() -> Dictionary:
	return {
		"wildlife_food": wildlife_food,
		"pending_trees": get_pending_count(WorldGenerator.TileType.TREE),
		"pending_berry_bushes": get_pending_count(WorldGenerator.TileType.BERRY_BUSH),
		"last_update_day": _last_update_day
	}

func to_save_data() -> Dictionary:
	var pending: Array[Dictionary] = []
	for record in _pending_regrowth:
		var origin: Vector2i = record["origin"]
		pending.append({
			"type": record["type"],
			"x": origin.x,
			"y": origin.y,
			"day": record["day"]
		})
	return {
		"wildlife_food": wildlife_food,
		"pending_regrowth": pending,
		"last_update_day": _last_update_day
	}

func load_save_data(data: Dictionary) -> void:
	wildlife_food = data.get("wildlife_food", wildlife_food)
	_last_update_day = data.get("last_update_day", _last_update_day)
	_pending_regrowth.clear()
	for record in data.get("pending_regrowth", []):
		_pending_regrowth.append({
			"type": int(record["type"]),
			"origin": Vector2i(record["x"], record["y"]),
			"day": int(record["day"])
		})

func _grow_wildlife() -> void:
	wildlife_food = mini(
		_balance.wildlife_food_capacity,
		wildlife_food + _balance.wildlife_food_regrowth_per_day
	)

func _required_age_for(tile_type: int) -> int:
	if tile_type == WorldGenerator.TileType.TREE:
		return _balance.nature_tree_regrowth_days
	return _balance.nature_berry_regrowth_days

func _max_for(tile_type: int) -> int:
	if tile_type == WorldGenerator.TileType.TREE:
		return _balance.nature_max_trees
	return _balance.nature_max_berry_bushes

func _count_for(world_gen: WorldGenerator, tile_type: int) -> int:
	return world_gen.count_tiles_of_type(tile_type)

func _try_regrow(record: Dictionary, world_gen: WorldGenerator) -> Dictionary:
	var tile_type: int = record["type"]
	var origin: Vector2i = record["origin"]
	for candidate in world_gen.get_regrowth_candidates(origin):
		world_gen.set_tile(candidate.x, candidate.y, tile_type)
		return {
			"pos": candidate,
			"type": tile_type
		}
	return {}
