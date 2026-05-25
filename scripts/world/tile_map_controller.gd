class_name TileMapController
extends TileMapLayer

const TILE_SIZE: int = 36
const TILE_SHEET_PATH := "res://assets/tiles/campfire_tilesheet_36.png"
const TILE_COLORS: Array[Color] = [
	Color(0.3, 0.65, 0.2),   # 0 GRASS
	Color(0.1, 0.35, 0.1),   # 1 TREE
	Color(0.55, 0.1, 0.65),  # 2 BERRY_BUSH
	Color(0.5, 0.3, 0.1),    # 3 HUT
	Color(1.0, 0.5, 0.0),    # 4 CAMPFIRE
	Color(0.15, 0.15, 0.15), # 5 BLOCKED
	Color(0.45, 0.42, 0.35), # 6 BUILD_SITE
	Color(0.72, 0.46, 0.22), # 7 HOUSE
]

func setup(world_gen: WorldGenerator) -> void:
	var ts = TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var source = TileSetAtlasSource.new()
	source.texture = _load_tile_texture()
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for i in range(TILE_COLORS.size()):
		source.create_tile(Vector2i(i, 0))
	ts.add_source(source, 0)
	tile_set = ts

	for y in range(WorldGenerator.HEIGHT):
		for x in range(WorldGenerator.WIDTH):
			var tile_type: int = world_gen.get_tile(x, y)
			set_cell(Vector2i(x, y), 0, Vector2i(tile_type, 0))

func refresh_tile(pos: Vector2i, tile_type: int) -> void:
	set_cell(pos, 0, Vector2i(tile_type, 0))

func _load_tile_texture() -> Texture2D:
	if FileAccess.file_exists(TILE_SHEET_PATH):
		var image := Image.new()
		if image.load(TILE_SHEET_PATH) == OK \
			and image.get_width() >= TILE_SIZE * TILE_COLORS.size() \
			and image.get_height() >= TILE_SIZE:
			return ImageTexture.create_from_image(image)
	return ImageTexture.create_from_image(_make_fallback_tilesheet())

func _make_fallback_tilesheet() -> Image:
	var img = Image.create(TILE_SIZE * TILE_COLORS.size(), TILE_SIZE, false, Image.FORMAT_RGBA8)
	for tile_idx in range(TILE_COLORS.size()):
		var color = TILE_COLORS[tile_idx]
		for py in range(TILE_SIZE):
			for px in range(TILE_SIZE):
				var edge = (px == 0 or px == TILE_SIZE - 1 or py == 0 or py == TILE_SIZE - 1)
				var draw_color = color.darkened(0.2) if edge else color
				img.set_pixel(tile_idx * TILE_SIZE + px, py, draw_color)
	return img
