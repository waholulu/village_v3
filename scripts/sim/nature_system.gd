class_name NatureSystem
extends RefCounted

var animals: Array = []         # Array[WildlifeAgent]
var _next_animal_id: int = 1
var _animal_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _balance: BalanceData
var _pathfinding: PathfindingService  # null = fall back to cardinal-step wolf movement
var _pending_regrowth: Array[Dictionary] = []
var _last_update_day: int = 1

# wildlife_food is now a computed property returning live deer count so that
# existing code reading nature.wildlife_food sees the animal-based count.
var wildlife_food: int:
	get: return _count_kind(WildlifeAgent.Kind.DEER)

func setup(balance: BalanceData, pathfinding: PathfindingService = null) -> void:
	_balance = balance
	_pathfinding = pathfinding
	animals.clear()
	_next_animal_id = 1
	_animal_rng.seed = balance.world_seed
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

func update_day(day: int, world_gen: WorldGenerator, blocked_positions: Array[Vector2i] = []) -> Array[Dictionary]:
	_last_update_day = day
	_age_and_despawn()
	if world_gen != null:
		_spawn_animals(day, world_gen)
		_move_animals(day, world_gen)

	var blocked: Dictionary = {}
	for p in blocked_positions:
		blocked[p] = true

	var changes: Array[Dictionary] = []
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
		var planted := _try_regrow(record, world_gen, blocked)
		if planted.is_empty():
			remaining.append(record)
		else:
			changes.append(planted)
	_pending_regrowth = remaining
	return changes

func get_pending_count(tile_type: int) -> int:
	var count := 0
	for record in _pending_regrowth:
		if int(record["type"]) == tile_type:
			count += 1
	return count

func get_summary() -> Dictionary:
	return {
		"wildlife_food": wildlife_food,
		"deer_count": _count_kind(WildlifeAgent.Kind.DEER),
		"wolf_count": _count_kind(WildlifeAgent.Kind.WOLF),
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
	var animal_data: Array[Dictionary] = []
	for a in animals:
		animal_data.append({
			"id": a.id,
			"kind": int(a.kind),
			"x": a.tile_position.x,
			"y": a.tile_position.y,
			"spawn_day": a.spawn_day,
			"age_days": a.age_days
		})
	return {
		"wildlife_food": wildlife_food,
		"pending_regrowth": pending,
		"last_update_day": _last_update_day,
		"animals": animal_data,
		"next_animal_id": _next_animal_id
	}

func load_save_data(data: Dictionary) -> void:
	_last_update_day = data.get("last_update_day", _last_update_day)
	_pending_regrowth.clear()
	for record in data.get("pending_regrowth", []):
		_pending_regrowth.append({
			"type": int(record["type"]),
			"origin": Vector2i(record["x"], record["y"]),
			"day": int(record["day"])
		})
	animals.clear()
	_next_animal_id = data.get("next_animal_id", 1)
	for d in data.get("animals", []):
		var a := WildlifeAgent.new(
			int(d["id"]),
			int(d["kind"]) as WildlifeAgent.Kind,
			Vector2i(int(d["x"]), int(d["y"])),
			int(d["spawn_day"])
		)
		a.age_days = int(d.get("age_days", 0))
		animals.append(a)

func find_animal_at(pos: Vector2i, kind: WildlifeAgent.Kind) -> WildlifeAgent:
	for a in animals:
		if a.tile_position == pos and a.kind == kind:
			return a
	return null

func remove_animal(animal_id: int) -> void:
	animals = animals.filter(func(a): return a.id != animal_id)

func get_animals_as_dicts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for a in animals:
		result.append({
			"id": a.id,
			"kind": int(a.kind),
			"x": a.tile_position.x,
			"y": a.tile_position.y
		})
	return result

func check_wolf_threat(campfire_out_nights: int) -> bool:
	if campfire_out_nights <= 0 or _balance == null or _balance.wolf_threat_radius <= 0:
		return false
	for a in animals:
		if a.kind == WildlifeAgent.Kind.WOLF:
			var apos: Vector2i = a.tile_position
			var dist: float = Vector2(apos).distance_to(Vector2(WorldGenerator.HUT_POS))
			if dist <= float(_balance.wolf_threat_radius):
				return true
	return false

# --- Private helpers ---

func _count_kind(k: WildlifeAgent.Kind) -> int:
	var count := 0
	for a in animals:
		if a.kind == k:
			count += 1
	return count

func _spawn_animals(day: int, world_gen: WorldGenerator) -> void:
	# Deer: spawn near berry bushes
	var deer_count := _count_kind(WildlifeAgent.Kind.DEER)
	if deer_count < _balance.deer_max_count:
		var spawned := 0
		var bushes := world_gen.get_tiles_of_type(WorldGenerator.TileType.BERRY_BUSH)
		if not bushes.is_empty():
			_animal_rng.seed = _balance.world_seed ^ (day * 17) ^ 1001
			var attempts := 0
			while spawned < _balance.deer_spawn_per_day \
					and deer_count + spawned < _balance.deer_max_count \
					and attempts < 20:
				attempts += 1
				var bush: Vector2i = bushes[_animal_rng.randi_range(0, bushes.size() - 1)]
				for n in world_gen._neighbors4(bush):
					if world_gen.is_walkable(n.x, n.y):
						animals.append(WildlifeAgent.new(_next_animal_id, WildlifeAgent.Kind.DEER, n, day))
						_next_animal_id += 1
						spawned += 1
						break

	# Wolves: spawn in forests, far from HUT, after wolf_spawn_day
	if day < _balance.wolf_spawn_day:
		return
	if (day - _balance.wolf_spawn_day) % _balance.wolf_spawn_interval_days != 0:
		return
	var wolf_count := _count_kind(WildlifeAgent.Kind.WOLF)
	if wolf_count >= _balance.wolf_max_count:
		return
	var trees := world_gen.get_tiles_of_type(WorldGenerator.TileType.TREE)
	if trees.is_empty():
		return
	_animal_rng.seed = _balance.world_seed ^ (day * 31) ^ 2002
	var attempts := 0
	var spawned_wolves := 0
	while spawned_wolves < _balance.wolf_spawn_count \
			and wolf_count + spawned_wolves < _balance.wolf_max_count \
			and attempts < 30:
		attempts += 1
		var tree: Vector2i = trees[_animal_rng.randi_range(0, trees.size() - 1)]
		if (tree - WorldGenerator.HUT_POS).length() < 10:
			continue
		for n in world_gen._neighbors4(tree):
			if world_gen.is_walkable(n.x, n.y):
				animals.append(WildlifeAgent.new(_next_animal_id, WildlifeAgent.Kind.WOLF, n, day))
				_next_animal_id += 1
				spawned_wolves += 1
				break

func _move_animals(day: int, world_gen: WorldGenerator) -> void:
	for a in animals:
		if a.kind == WildlifeAgent.Kind.DEER:
			_move_deer(a, day, world_gen)
		elif a.kind == WildlifeAgent.Kind.WOLF:
			_move_wolf(a, world_gen)

func _move_deer(a: WildlifeAgent, day: int, world_gen: WorldGenerator) -> void:
	_animal_rng.seed = _balance.world_seed ^ (day * 7) ^ a.id
	var neighbors := world_gen._neighbors4(a.tile_position)
	var walkable: Array[Vector2i] = []
	for n in neighbors:
		if world_gen.is_walkable(n.x, n.y):
			walkable.append(n)
	if not walkable.is_empty():
		a.tile_position = walkable[_animal_rng.randi_range(0, walkable.size() - 1)]

func _move_wolf(a: WildlifeAgent, world_gen: WorldGenerator) -> void:
	# Prefer the pathfinding service so wolves route around BLOCKED tiles;
	# without it they freeze the moment any cardinal step is solid.
	if _pathfinding != null:
		var path: Array[Vector2i] = _pathfinding.get_path(a.tile_position, WorldGenerator.HUT_POS)
		if path.size() >= 2:
			var step: Vector2i = path[1]
			if world_gen.is_in_bounds(step) and world_gen.is_walkable(step.x, step.y):
				a.tile_position = step
				return
	# Fallback: greedy cardinal step (also used by unit tests that don't
	# construct a PathfindingService).
	var hut := WorldGenerator.HUT_POS
	var dx: int = sign(hut.x - a.tile_position.x)
	var dy: int = sign(hut.y - a.tile_position.y)
	var candidates: Array[Vector2i] = []
	if dx != 0:
		candidates.append(a.tile_position + Vector2i(dx, 0))
	if dy != 0:
		candidates.append(a.tile_position + Vector2i(0, dy))
	for c in candidates:
		if world_gen.is_in_bounds(c) and world_gen.is_walkable(c.x, c.y):
			a.tile_position = c
			return

func _age_and_despawn() -> void:
	for a in animals:
		a.age_days += 1
	animals = animals.filter(func(a):
		if a.kind == WildlifeAgent.Kind.WOLF and a.age_days >= _balance.wolf_max_age_days:
			return false
		return true)

func _required_age_for(tile_type: int) -> int:
	if tile_type == WorldGenerator.TileType.TREE:
		return _balance.nature_tree_regrowth_days
	return _balance.nature_berry_regrowth_days

func _max_for(tile_type: int) -> int:
	if tile_type == WorldGenerator.TileType.TREE:
		return _balance.nature_max_trees
	return _balance.nature_max_berry_bushes

func _count_for(world_gen: WorldGenerator, tile_type: int) -> int:
	if world_gen == null:
		return 0
	return world_gen.count_tiles_of_type(tile_type)

func _try_regrow(record: Dictionary, world_gen: WorldGenerator, blocked: Dictionary = {}) -> Dictionary:
	if world_gen == null:
		return {}
	var tile_type: int = record["type"]
	var origin: Vector2i = record["origin"]
	for candidate in world_gen.get_regrowth_candidates(origin):
		# Skip candidates a villager is currently standing on — would trap them
		# on an unwalkable tile.
		if blocked.has(candidate):
			continue
		world_gen.set_tile(candidate.x, candidate.y, tile_type)
		return {
			"pos": candidate,
			"type": tile_type
		}
	return {}
