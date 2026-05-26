class_name WorldGenerator
extends RefCounted

const WIDTH: int = 40
const HEIGHT: int = 27
const HUT_POS: Vector2i = Vector2i(4, 5)
const CAMPFIRE_POS: Vector2i = Vector2i(6, 6)

enum TileType { GRASS, TREE, BERRY_BUSH, HUT, CAMPFIRE, BLOCKED, BUILD_SITE, HOUSE, FENCE, WATCHTOWER, STORAGE }

var grid: Array = []
# Per-type position index kept in sync with `grid` via set_tile().
# Lookups go from O(W*H) scan to O(1); iteration callers get a duplicate so
# the cache cannot be mutated externally (e.g. _cellular_smooth_blocked sorts).
var _tile_index: Dictionary = {}
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
	# Place fixed-position tiles BEFORE reachability passes — build_sites are
	# non-walkable BUILD_SITE tiles, and if reachability is checked before
	# they're laid down, a site landing on a corridor can strand a resource.
	set_tile(CAMPFIRE_POS.x, CAMPFIRE_POS.y, TileType.CAMPFIRE)
	set_tile(HUT_POS.x, HUT_POS.y, TileType.HUT)
	for pos in build_sites:
		set_tile(pos.x, pos.y, TileType.BUILD_SITE)
	_repair_resource_access()
	_ensure_reachable_resources()

func generate_from_balance(balance: BalanceData) -> void:
	last_seed = balance.world_seed
	_fill_grass()

	var noise_map := _generate_noise_map(balance.world_seed, balance.world_noise_frequency)
	var rng := RandomNumberGenerator.new()
	rng.seed = balance.world_seed
	var clear_sq: int = balance.world_starting_area_radius * balance.world_starting_area_radius

	# --- BLOCKED (rocky outcrops) ---
	var rocky_candidates: Array[Vector2i] = []
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var pos := Vector2i(x, y)
			if noise_map[y][x] < balance.world_noise_rocky_threshold \
					and _can_place_resource_tile(pos, clear_sq):
				rocky_candidates.append(pos)
	_shuffle(rocky_candidates, rng)
	var blocked_to_place := balance.world_blocked_count
	for i in range(mini(blocked_to_place, rocky_candidates.size())):
		set_tile(rocky_candidates[i].x, rocky_candidates[i].y, TileType.BLOCKED)
		blocked_to_place -= 1
	# fallback for any shortfall
	if blocked_to_place > 0:
		_place_clustered_tiles(TileType.BLOCKED, blocked_to_place, rng, 4)
	_cellular_smooth_blocked(rng, balance.world_blocked_count, balance.world_cellular_smoothing_passes)

	# --- TREE (forest zones) ---
	var forest_candidates: Array[Vector2i] = []
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var pos := Vector2i(x, y)
			if noise_map[y][x] > balance.world_noise_forest_threshold \
					and _can_place_resource_tile(pos, clear_sq):
				forest_candidates.append(pos)
	_shuffle(forest_candidates, rng)
	var trees_to_place := balance.world_tree_count
	for i in range(mini(trees_to_place, forest_candidates.size())):
		set_tile(forest_candidates[i].x, forest_candidates[i].y, TileType.TREE)
		trees_to_place -= 1
	if trees_to_place > 0:
		_place_clustered_tiles(TileType.TREE, trees_to_place, rng, 6)

	# --- BERRY_BUSH (meadow zones — mid-range noise) ---
	var meadow_low := balance.world_noise_rocky_threshold + 0.15
	var meadow_high := balance.world_noise_forest_threshold - 0.15
	var meadow_candidates: Array[Vector2i] = []
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var pos := Vector2i(x, y)
			var n: float = noise_map[y][x]
			if n >= meadow_low and n <= meadow_high \
					and _can_place_resource_tile(pos, clear_sq):
				meadow_candidates.append(pos)
	_shuffle(meadow_candidates, rng)
	var bushes_to_place := balance.world_berry_bush_count
	for i in range(mini(bushes_to_place, meadow_candidates.size())):
		set_tile(meadow_candidates[i].x, meadow_candidates[i].y, TileType.BERRY_BUSH)
		bushes_to_place -= 1
	if bushes_to_place > 0:
		_place_clustered_tiles(TileType.BERRY_BUSH, bushes_to_place, rng, 4)

	# Place fixed-position tiles BEFORE reachability passes — see generate_fixed
	# for the rationale (build_sites can strand resources if added after repair).
	set_tile(CAMPFIRE_POS.x, CAMPFIRE_POS.y, TileType.CAMPFIRE)
	set_tile(HUT_POS.x, HUT_POS.y, TileType.HUT)
	for pos in build_sites:
		set_tile(pos.x, pos.y, TileType.BUILD_SITE)
	_repair_resource_access()
	_ensure_reachable_resources()

func _generate_noise_map(seed: int, frequency: float) -> Array:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.seed = seed
	fnl.frequency = frequency
	var map: Array = []
	for y in range(HEIGHT):
		var row: Array = []
		for x in range(WIDTH):
			row.append(fnl.get_noise_2d(float(x), float(y)))
		map.append(row)
	return map

func _can_place_resource_tile(pos: Vector2i, clear_radius_sq: int = 9) -> bool:
	if not is_in_bounds(pos):
		return false
	if get_tile(pos.x, pos.y) != TileType.GRASS:
		return false
	if pos in build_sites:
		return false
	if pos.distance_squared_to(HUT_POS) <= clear_radius_sq:
		return false
	if pos.distance_squared_to(CAMPFIRE_POS) <= clear_radius_sq:
		return false
	if pos.x == 0 or pos.y == 0 or pos.x == WIDTH - 1 or pos.y == HEIGHT - 1:
		return false
	return true

func _cellular_smooth_blocked(rng: RandomNumberGenerator, target: int, passes: int) -> void:
	for _pass in range(passes):
		var changes: Array[Array] = []
		for y in range(1, HEIGHT - 1):
			for x in range(1, WIDTH - 1):
				var pos := Vector2i(x, y)
				var is_blocked := (get_tile(x, y) == TileType.BLOCKED)
				var blocked_neighbors := 0
				for n in _neighbors4(pos):
					if get_tile(n.x, n.y) == TileType.BLOCKED:
						blocked_neighbors += 1
				if not is_blocked and blocked_neighbors >= 3:
					changes.append([x, y, TileType.BLOCKED])
				elif is_blocked and blocked_neighbors <= 1 \
						and pos not in build_sites \
						and pos != HUT_POS and pos != CAMPFIRE_POS:
					changes.append([x, y, TileType.GRASS])
		for c in changes:
			# Use set_tile (not direct grid write) so _tile_index stays in sync.
			# Direct writes here previously desynced the index, breaking every
			# get_tiles_of_type / count_tiles_of_type downstream of generation.
			set_tile(c[0], c[1], c[2])

	# Trim excess blocked tiles back to target (remove most-isolated first)
	var current_blocked := get_tiles_of_type(TileType.BLOCKED)
	if current_blocked.size() > target:
		# Sort by number of blocked neighbors (ascending) — isolated ones removed first
		current_blocked.sort_custom(func(a, b):
			var na := 0
			var nb := 0
			for n in _neighbors4(a):
				if get_tile(n.x, n.y) == TileType.BLOCKED: na += 1
			for n in _neighbors4(b):
				if get_tile(n.x, n.y) == TileType.BLOCKED: nb += 1
			return na < nb)
		var to_remove := current_blocked.size() - target
		for i in range(to_remove):
			var p := current_blocked[i]
			if p not in build_sites and p != HUT_POS and p != CAMPFIRE_POS:
				set_tile(p.x, p.y, TileType.GRASS)

	# Top-up deficit (place at random GRASS tiles)
	current_blocked = get_tiles_of_type(TileType.BLOCKED)
	if current_blocked.size() < target:
		var deficit := target - current_blocked.size()
		_place_clustered_tiles(TileType.BLOCKED, deficit, rng, 3)

func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _fill_grass() -> void:
	grid = []
	_tile_index.clear()
	for t in TileType.values():
		_tile_index[t] = ([] as Array[Vector2i])
	var grass_index: Array[Vector2i] = _tile_index[TileType.GRASS]
	for y in range(HEIGHT):
		var row: Array = []
		for x in range(WIDTH):
			row.append(TileType.GRASS)
			grass_index.append(Vector2i(x, y))
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
		if _can_place_resource_tile(pos):
			set_tile(pos.x, pos.y, type)
			placed += 1

func _pick_free_tile(rng: RandomNumberGenerator) -> Vector2i:
	for i in range(200):
		var pos := Vector2i(rng.randi_range(1, WIDTH - 2), rng.randi_range(1, HEIGHT - 2))
		if _can_place_resource_tile(pos):
			return pos
	return Vector2i(WIDTH / 2, HEIGHT / 2)

func _repair_resource_access() -> void:
	for type in [TileType.TREE, TileType.BERRY_BUSH]:
		for pos in get_tiles_of_type(type):
			if find_walkable_adjacent(pos) == Vector2i(-1, -1):
				for n in _neighbors4(pos):
					if is_in_bounds(n) and n not in build_sites and n != HUT_POS and n != CAMPFIRE_POS:
						set_tile(n.x, n.y, TileType.GRASS)
						break

func _ensure_reachable_resources() -> void:
	# After _repair_resource_access every resource has a walkable neighbour,
	# but BLOCKED rings can still cut some neighbours off from HUT. Cut one
	# BLOCKED on the closest path to HUT per iteration; safety cap prevents
	# unbounded loops if the world is pathologically partitioned.
	var safety := 50
	while safety > 0 and not all_resource_approaches_reachable():
		safety -= 1
		if not _open_one_blocked_toward_hut():
			break

func _open_one_blocked_toward_hut() -> bool:
	# Locate one stranded resource adjacency tile, BFS toward HUT through any
	# in-bounds neighbour, and clear the nearest BLOCKED on the path. Returns
	# true if we changed something, false if no progress is possible.
	var stranded_adj: Vector2i = Vector2i(-1, -1)
	for type in [TileType.TREE, TileType.BERRY_BUSH]:
		for pos in get_tiles_of_type(type):
			var adj := find_walkable_adjacent(pos)
			if adj == Vector2i(-1, -1):
				continue
			if not is_reachable_from_hut(adj):
				stranded_adj = adj
				break
		if stranded_adj != Vector2i(-1, -1):
			break
	if stranded_adj == Vector2i(-1, -1):
		return false
	# BFS from stranded_adj through *any* tile, tracking parents, until we land
	# on a tile that IS reachable from HUT. Then walk parents back and clear
	# the first BLOCKED encountered.
	var parents: Dictionary = {stranded_adj: stranded_adj}
	var queue: Array[Vector2i] = [stranded_adj]
	var bridge: Vector2i = Vector2i(-1, -1)
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current != stranded_adj and is_walkable(current.x, current.y) and is_reachable_from_hut(current):
			bridge = current
			break
		for n in _neighbors4(current):
			if not is_in_bounds(n) or parents.has(n):
				continue
			parents[n] = current
			queue.append(n)
	if bridge == Vector2i(-1, -1):
		return false
	# Walk back from bridge to stranded_adj; the first BLOCKED we hit becomes GRASS.
	var step: Vector2i = bridge
	while step != stranded_adj:
		if get_tile(step.x, step.y) == TileType.BLOCKED \
				and step not in build_sites and step != HUT_POS and step != CAMPFIRE_POS:
			set_tile(step.x, step.y, TileType.GRASS)
			return true
		step = parents[step]
	# Path didn't cross a BLOCKED — fall back to clearing any BLOCKED adjacent
	# to stranded_adj as a safety net.
	for n in _neighbors4(stranded_adj):
		if is_in_bounds(n) and get_tile(n.x, n.y) == TileType.BLOCKED \
				and n not in build_sites and n != HUT_POS and n != CAMPFIRE_POS:
			set_tile(n.x, n.y, TileType.GRASS)
			return true
	return false

func set_tile(x: int, y: int, type: TileType) -> void:
	if not is_in_bounds(Vector2i(x, y)):
		return
	var old_type: int = grid[y][x]
	if old_type == type:
		return
	grid[y][x] = type
	var pos := Vector2i(x, y)
	if _tile_index.has(old_type):
		_tile_index[old_type].erase(pos)
	if not _tile_index.has(type):
		_tile_index[type] = ([] as Array[Vector2i])
	_tile_index[type].append(pos)

func get_tile(x: int, y: int) -> TileType:
	if not is_in_bounds(Vector2i(x, y)):
		return TileType.BLOCKED
	return grid[y][x]

func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < WIDTH and pos.y >= 0 and pos.y < HEIGHT

func get_tiles_of_type(type: TileType) -> Array[Vector2i]:
	# Duplicate so callers can sort / iterate-with-set_tile safely without
	# corrupting the index (set_tile mutates the live array on mismatch).
	if _tile_index.has(type):
		return _tile_index[type].duplicate()
	return ([] as Array[Vector2i])

func count_tiles_of_type(type: TileType) -> int:
	if _tile_index.has(type):
		return _tile_index[type].size()
	return 0

func get_resource_counts() -> Dictionary:
	return {
		"trees": count_tiles_of_type(TileType.TREE),
		"berry_bushes": count_tiles_of_type(TileType.BERRY_BUSH)
	}

func is_walkable(x: int, y: int) -> bool:
	var t: TileType = get_tile(x, y)
	return t == TileType.GRASS or t == TileType.HUT or t == TileType.CAMPFIRE or t == TileType.HOUSE \
		or t == TileType.FENCE or t == TileType.WATCHTOWER or t == TileType.STORAGE

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
