class_name WorldGenerator
extends RefCounted

const GRID_SIZE: int = 12

enum TileType { GRASS, TREE, BERRY_BUSH, HUT, CAMPFIRE, BLOCKED }

var grid: Array = []

func generate_fixed() -> void:
	grid = []
	for y in range(GRID_SIZE):
		var row: Array = []
		for x in range(GRID_SIZE):
			row.append(TileType.GRASS)
		grid.append(row)

	set_tile(6, 6, TileType.CAMPFIRE)
	set_tile(4, 5, TileType.HUT)

	for pos in [[1,1],[2,1],[1,3],[9,2],[10,2],[9,4],[3,9],[4,9],[8,8],[10,10]]:
		set_tile(pos[0], pos[1], TileType.TREE)

	for pos in [[7,2],[8,3],[2,7],[3,8],[9,7]]:
		set_tile(pos[0], pos[1], TileType.BERRY_BUSH)

	for pos in [[0,0],[11,0],[0,11],[11,11],[5,3],[6,9]]:
		set_tile(pos[0], pos[1], TileType.BLOCKED)

func set_tile(x: int, y: int, type: TileType) -> void:
	if x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE:
		grid[y][x] = type

func get_tile(x: int, y: int) -> TileType:
	if x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE:
		return TileType.BLOCKED
	return grid[y][x]

func get_tiles_of_type(type: TileType) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if grid[y][x] == type:
				result.append(Vector2i(x, y))
	return result

func is_walkable(x: int, y: int) -> bool:
	var t: TileType = get_tile(x, y)
	return t == TileType.GRASS or t == TileType.HUT or t == TileType.CAMPFIRE

func find_walkable_adjacent(tile: Vector2i) -> Vector2i:
	# Returns a walkable 4-neighbor of `tile`, or Vector2i(-1, -1) if none exist.
	# Used for chop_tree / gather_food tasks where the target itself is non-walkable.
	var dirs := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	for d in dirs:
		var n: Vector2i = tile + d
		if is_walkable(n.x, n.y):
			return n
	return Vector2i(-1, -1)
