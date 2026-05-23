class_name PathfindingService
extends RefCounted

var _astar: AStarGrid2D

func setup(world_gen: WorldGenerator) -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, WorldGenerator.GRID_SIZE, WorldGenerator.GRID_SIZE)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

	for y in range(WorldGenerator.GRID_SIZE):
		for x in range(WorldGenerator.GRID_SIZE):
			if not world_gen.is_walkable(x, y):
				_astar.set_point_solid(Vector2i(x, y), true)

func get_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if _astar == null:
		return []
	return _astar.get_id_path(from, to)

func set_point_walkable(pos: Vector2i, walkable: bool) -> void:
	_astar.set_point_solid(pos, not walkable)
