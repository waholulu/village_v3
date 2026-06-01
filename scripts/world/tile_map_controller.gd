class_name TileMapController
extends TileMapLayer

const DisplayMetrics = preload("res://scripts/world/display_metrics.gd")
const TILE_SIZE: int = DisplayMetrics.TILE_SIZE
const TILE_SHEET_PATH := "res://assets/tiles/campfire_tilesheet_32.png"
const INVALID_TILE := Vector2i(-1, -1)
const TILE_COLORS: Array[Color] = [
	Color(0.3, 0.65, 0.2),   # 0 GRASS
	Color(0.1, 0.35, 0.1),   # 1 TREE
	Color(0.55, 0.1, 0.65),  # 2 BERRY_BUSH
	Color(0.5, 0.3, 0.1),    # 3 HUT
	Color(1.0, 0.5, 0.0),    # 4 CAMPFIRE
	Color(0.15, 0.15, 0.15), # 5 BLOCKED
	Color(0.45, 0.42, 0.35), # 6 BUILD_SITE
	Color(0.72, 0.46, 0.22), # 7 HOUSE
	Color(0.55, 0.40, 0.20), # 8 FENCE — dark brown
	Color(0.40, 0.40, 0.45), # 9 WATCHTOWER — slate grey
	Color(0.65, 0.50, 0.30), # 10 STORAGE — tan
]

var _selected_tile: Vector2i = INVALID_TILE

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
	queue_redraw()

func refresh_tile(pos: Vector2i, tile_type: int) -> void:
	set_cell(pos, 0, Vector2i(tile_type, 0))
	queue_redraw()

func set_selected_tile(pos: Vector2i) -> void:
	_selected_tile = pos if _is_valid_tile(pos) else INVALID_TILE
	queue_redraw()

func clear_selected_tile() -> void:
	_selected_tile = INVALID_TILE
	queue_redraw()

func get_selected_tile() -> Vector2i:
	return _selected_tile

func _draw() -> void:
	if not _is_valid_tile(_selected_tile):
		return
	var rect := Rect2(Vector2(_selected_tile) * TILE_SIZE, Vector2.ONE * TILE_SIZE)
	draw_rect(rect, Color(1.0, 0.93, 0.35, 0.18), true)
	draw_rect(rect.grow(1.0), Color(1.0, 0.93, 0.35, 0.95), false, 2.0)

func _load_tile_texture() -> Texture2D:
	if ResourceLoader.exists(TILE_SHEET_PATH):
		var tex := load(TILE_SHEET_PATH) as Texture2D
		if tex != null \
			and tex.get_width() >= TILE_SIZE * TILE_COLORS.size() \
			and tex.get_height() >= TILE_SIZE:
			return tex
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

func _is_valid_tile(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < WorldGenerator.WIDTH and pos.y < WorldGenerator.HEIGHT
