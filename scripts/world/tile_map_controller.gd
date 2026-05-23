class_name TileMapController
extends TileMapLayer

const TILE_SIZE: int = 48
const TILE_COLORS: Array[Color] = [
	Color(0.3, 0.65, 0.2),   # 0 GRASS
	Color(0.1, 0.35, 0.1),   # 1 TREE
	Color(0.55, 0.1, 0.65),  # 2 BERRY_BUSH
	Color(0.5, 0.3, 0.1),    # 3 HUT
	Color(1.0, 0.5, 0.0),    # 4 CAMPFIRE
	Color(0.15, 0.15, 0.15), # 5 BLOCKED
]

func setup(world_gen: WorldGenerator) -> void:
	var ts = TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var source = TileSetAtlasSource.new()
	var img = Image.create(TILE_SIZE * 6, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for tile_idx in range(6):
		var color = TILE_COLORS[tile_idx]
		for py in range(TILE_SIZE):
			for px in range(TILE_SIZE):
				var edge = (px == 0 or px == TILE_SIZE - 1 or py == 0 or py == TILE_SIZE - 1)
				var draw_color = color.darkened(0.2) if edge else color
				img.set_pixel(tile_idx * TILE_SIZE + px, py, draw_color)
	source.texture = ImageTexture.create_from_image(img)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for i in range(6):
		source.create_tile(Vector2i(i, 0))
	ts.add_source(source, 0)
	tile_set = ts

	for y in range(WorldGenerator.GRID_SIZE):
		for x in range(WorldGenerator.GRID_SIZE):
			var tile_type: int = world_gen.get_tile(x, y)
			set_cell(Vector2i(x, y), 0, Vector2i(tile_type, 0))

func refresh_tile(pos: Vector2i, tile_type: int) -> void:
	set_cell(pos, 0, Vector2i(tile_type, 0))
