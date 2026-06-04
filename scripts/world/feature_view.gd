class_name FeatureView
extends Node2D

const DisplayMetrics = preload("res://scripts/world/display_metrics.gd")
const TILE_SIZE := DisplayMetrics.TILE_SIZE
const FEATURE_PATHS := {
	WorldGenerator.TileType.TREE: "res://assets/features/tree.png",
	WorldGenerator.TileType.BERRY_BUSH: "res://assets/features/berry.png",
	WorldGenerator.TileType.HUT: "res://assets/features/hut.png",
	WorldGenerator.TileType.CAMPFIRE: "res://assets/features/campfire.png",
	WorldGenerator.TileType.BLOCKED: "res://assets/features/rock.png",
	WorldGenerator.TileType.BUILD_SITE: "res://assets/features/build_site.png",
	WorldGenerator.TileType.HOUSE: "res://assets/features/house.png",
	WorldGenerator.TileType.FENCE: "res://assets/features/fence.png",
	WorldGenerator.TileType.WATCHTOWER: "res://assets/features/watchtower.png",
	WorldGenerator.TileType.STORAGE: "res://assets/features/storage.png",
}

var _sprites: Dictionary = {}
var _textures: Dictionary = {}
var _campfire_time := 0.0
var _campfire_frames: Array[Texture2D] = []
var _campfire_sprite: Sprite2D

func setup(world_gen: WorldGenerator) -> void:
	for child in get_children():
		child.queue_free()
	_sprites.clear()
	_campfire_sprite = null
	for y in range(WorldGenerator.HEIGHT):
		for x in range(WorldGenerator.WIDTH):
			refresh_tile(Vector2i(x, y), world_gen.get_tile(x, y))

func _process(delta: float) -> void:
	_campfire_time += delta
	if _campfire_frames.is_empty():
		for i in range(3):
			_campfire_frames.append(load("res://assets/features/campfire_%d.png" % i) as Texture2D)
	var frame := int(_campfire_time * 5.0) % _campfire_frames.size()
	if is_instance_valid(_campfire_sprite):
		_campfire_sprite.texture = _campfire_frames[frame]

func refresh_tile(pos: Vector2i, tile_type: int) -> void:
	if _sprites.has(pos):
		var old: Sprite2D = _sprites[pos]
		if old == _campfire_sprite:
			_campfire_sprite = null
		old.queue_free()
		_sprites.erase(pos)
	if tile_type == WorldGenerator.TileType.GRASS:
		return
	var texture := _get_texture(tile_type)
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = texture
	sprite.set_meta("tile_type", tile_type)
	sprite.position = Vector2(pos.x * TILE_SIZE + (TILE_SIZE - texture.get_width()) / 2.0, (pos.y + 1) * TILE_SIZE - texture.get_height())
	sprite.z_index = pos.y * 10 + 2
	add_child(sprite)
	_sprites[pos] = sprite
	if tile_type == WorldGenerator.TileType.CAMPFIRE:
		_campfire_sprite = sprite

func _get_texture(tile_type: int) -> Texture2D:
	if _textures.has(tile_type):
		return _textures[tile_type]
	var path: String = FEATURE_PATHS.get(tile_type, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	_textures[tile_type] = texture
	return texture
