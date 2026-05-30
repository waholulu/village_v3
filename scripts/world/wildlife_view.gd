class_name WildlifeView
extends Node2D

const DisplayMetrics = preload("res://scripts/world/display_metrics.gd")
const TILE_SIZE: int = DisplayMetrics.TILE_SIZE
const DEER_TEXTURE_PATH := "res://assets/wildlife/deer.png"
const WOLF_TEXTURE_PATH := "res://assets/wildlife/wolf.png"

var _animals: Array[Dictionary] = []
var _sprites: Array[Sprite2D] = []
var _deer_texture: Texture2D
var _wolf_texture: Texture2D

func setup_animals(animals: Array[Dictionary]) -> void:
	_animals = animals
	_sync_sprites()

func _process(_delta: float) -> void:
	for i in range(_animals.size()):
		if i >= _sprites.size():
			break
		var a: Dictionary = _animals[i]
		_sprites[i].position = Vector2(a["x"], a["y"]) * TILE_SIZE

func _sync_sprites() -> void:
	while _sprites.size() > _animals.size():
		_sprites[-1].queue_free()
		_sprites.remove_at(_sprites.size() - 1)
	while _sprites.size() < _animals.size():
		var sprite := Sprite2D.new()
		sprite.centered = false
		add_child(sprite)
		_sprites.append(sprite)
	# Refresh textures for ALL sprites every sync — otherwise an animal removed
	# from the middle of `_animals` would leave a stale-kind sprite at that
	# index (e.g. a wolf texture rendering a newly-shifted-in deer).
	for i in range(_sprites.size()):
		var kind: int = int(_animals[i].get("kind", 0))
		_sprites[i].texture = _get_texture(kind)

func _get_texture(kind: int) -> Texture2D:
	if kind == WildlifeAgent.Kind.WOLF:
		if _wolf_texture == null:
			_wolf_texture = _load_square_texture(WOLF_TEXTURE_PATH, Color(0.5, 0.5, 0.55, 1.0))
		return _wolf_texture
	if _deer_texture == null:
		_deer_texture = _load_square_texture(DEER_TEXTURE_PATH, Color(0.76, 0.6, 0.42, 1.0))
	return _deer_texture

func _load_square_texture(path: String, fallback_color: Color) -> Texture2D:
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null and texture.get_width() == TILE_SIZE and texture.get_height() == TILE_SIZE:
			return texture
	return _make_color_texture(fallback_color)

func _make_color_texture(color: Color) -> Texture2D:
	var image := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
