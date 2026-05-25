class_name WorldGenerator
extends RefCounted

const WIDTH: int = 40
const HEIGHT: int = 27
const HUT_POS: Vector2i = Vector2i(4, 5)
const CAMPFIRE_POS: Vector2i = Vector2i(6, 6)

enum TileType { GRASS, TREE, BERRY_BUSH, HUT, CAMPFIRE, BLOCKED, BUILD_SITE, HOUSE }

var grid: Array = []
var build_sites: Array[Vector2i] = [
	Vector2i(8, 5),
	Vector2i(11, 6),
	Vector2i(14, 8),
	Vector2i(7, 11),
	Vector2i(21, 8),
	Vector2i(28, 13),
	Vector2i(34, 20),
	Vector2i(18, 22),
]
var last_seed: int = 4312

func generate_fixed(seed: int = 4312, tree_count: int = 32, berry_count: int = 18, blocked_count: int = 18) -> void:
	last_seed = seed
	_fill_grass()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	_place_clustered_tiles(TileType.BLOCKED, blocked_count, rng, 6)
	_place_clustered_tiles(TileType.TREE, tree_count, rng, 8)
	_place_clustered_tiles(TileType.BERRY_BUSH, berry_count, rng, 5)
	_repair_resource_access()

	set_tile(CAMPFIRE_POS.x, CAMPFIRE_POS.y, TileType.CAMPFIRE)
	set_tile(HUT_POS.x, HUT_POS.y, TileType.HUT)
	for pos in build_sites:
		set_tile(pos.x, pos.y, TileType.BUILD_SITE)

func generate_from_balance(balance: BalanceData) -> void:
	generate_fixed(
		balance.world_seed,
		balance.world_tree_count,
		balance.world_berry_bush_count,
		balance.world_blocked_count
	)

func _fill_grass() -> void:
	grid = []
	for y in range(HEIGHT):
		var row: Array = []
		for x in range(WIDTH):
			row.append(TileType.GRASS)
		grid.append(row)

func _place_clustered_tiles(type: TileType, target_count: int, rng: RandomNumberGenerator, cluster_count: int) -> void:
	var anchors: Array[Vector2i] = []
	for i in range(cluster_count):
		anchors.append(_pick_free_tile(rng))
	var placed := 0
	var attempts := 0
	while placed < target_count and attempts < target_count * 80:
		attempts += 1
		var anchor: Vector2i = anchors[rng.randi_range(0, anchors.size() - 1)]
		var radius := 1 + rng.randi_range(0, 3)
		var pos := Vector2i(
			clampi(anchor.x + rng.randi_range(-radius, radius), 0, WIDTH - 1),
			clampi(anchor.y + rng.randi_range(-radius, radius), 0, HEIGHT - 1)
		)
		if _can_place_natural_tile(pos):
			set_tile(pos.x, pos.y, type)
			placed += 1

func _pick_free_tile(rng: RandomNumberGenerator) -> Vector2i:
	for i in range(200):
		var pos := Vector2i(rng.randi_range(1, WIDTH - 2), rng.randi_range(1, HEIGHT - 2))
		if _can_place_natural_tile(pos):
			return pos
	return Vector2i(WIDTH / 2, HEIGHT / 2)

func _can_place_natural_tile(pos: Vector2i) -> bool:
	if not is_in_bounds(pos):
		return false
	if get_tile(pos.x, pos.y) != TileType.GRASS:
		return false
	if pos in build_sites:
		return false
	if pos.distance_squared_to(HUT_POS) <= 9 or pos.distance_squared_to(CAMPFIRE_POS) <= 9:
		return false
	if pos.x == 0 or pos.y == 0 or pos.x == WIDTH - 1 or pos.y == HEIGHT - 1:
		return false
	return true

func _repair_resource_access() -> void:
	for type in [TileType.TREE, TileType.BERRY_BUSH]:
		for pos in get_tiles_of_type(type):
			if find_walkable_adjacent(pos) == Vector2i(-1, -1):
				for n in _neighbors4(pos):
					if is_in_bounds(n) and n not in build_sites and n != HUT_POS and n != CAMPFIRE_POS:
						set_tile(n.x, n.y, TileType.GRASS)
						break

func set_tile(x: int, y: int, type: TileType) -> void:
	if is_in_bounds(Vector2i(x, y)):
		grid[y][x] = type

func get_tile(x: int, y: int) -> TileType:
	if not is_in_bounds(Vector2i(x, y)):
		return TileType.BLOCKED
	return grid[y][x]

func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < WIDTH and pos.y >= 0 and pos.y < HEIGHT

func get_tiles_of_type(type: TileType) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(HEIGHT):
		for x in range(WIDTH):
			if grid[y][x] == type:
				result.append(Vector2i(x, y))
	return result

func count_tiles_of_type(type: TileType) -> int:
	return get_tiles_of_type(type).size()

func get_resource_counts() -> Dictionary:
	return {
		"trees": count_tiles_of_type(TileType.TREE),
		"berry_bushes": count_tiles_of_type(TileType.BERRY_BUSH)
	}

func is_walkable(x: int, y: int) -> bool:
	var t: TileType = get_tile(x, y)
	return t == TileType.GRASS or t == TileType.HUT or t == TileType.CAMPFIRE or t == TileType.HOUSE

func find_next_build_site() -> Vector2i:
	for site in build_sites:
		if get_tile(site.x, site.y) == TileType.BUILD_SITE:
			return site
	return Vector2i(-1, -1)

func find_walkable_adjacent(tile: Vector2i) -> Vector2i:
	for n in _neighbors4(tile):
		if is_walkable(n.x, n.y):
			return n
	return Vector2i(-1, -1)

func get_regrowth_candidates(origin: Vector2i) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	if _can_regrow_at(origin):
		candidates.append(origin)
	var ring: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		Vector2i(0, 2), Vector2i(2, 0), Vector2i(0, -2), Vector2i(-2, 0),
	]
	for offset in ring:
		var pos: Vector2i = origin + offset
		if _can_regrow_at(pos):
			candidates.append(pos)
	return candidates

func _can_regrow_at(pos: Vector2i) -> bool:
	if not is_in_bounds(pos):
		return false
	if get_tile(pos.x, pos.y) != TileType.GRASS:
		return false
	if pos in build_sites or pos == HUT_POS or pos == CAMPFIRE_POS:
		return false
	return true

func is_reachable_from_hut(target: Vector2i) -> bool:
	if not is_in_bounds(target) or not is_walkable(target.x, target.y):
		return false
	var visited := {}
	var queue: Array[Vector2i] = [HUT_POS]
	visited[HUT_POS] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == target:
			return true
		for n in _neighbors4(current):
			if not visited.has(n) and is_in_bounds(n) and is_walkable(n.x, n.y):
				visited[n] = true
				queue.append(n)
	return false

func all_resource_approaches_reachable() -> bool:
	for type in [TileType.TREE, TileType.BERRY_BUSH]:
		for pos in get_tiles_of_type(type):
			var adj := find_walkable_adjacent(pos)
			if adj == Vector2i(-1, -1) or not is_reachable_from_hut(adj):
				return false
	return true

func _neighbors4(pos: Vector2i) -> Array[Vector2i]:
	return [
		pos + Vector2i(0, 1),
		pos + Vector2i(1, 0),
		pos + Vector2i(0, -1),
		pos + Vector2i(-1, 0),
	]
