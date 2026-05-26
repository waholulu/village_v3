class_name WildlifeView
extends Node2D

const TILE_SIZE: int = 36

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
		_sprites[i].position = Vector2(a["x"], a["y"]) * TILE_SIZE + Vector2(8, 8)

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
			_wolf_texture = _make_color_texture(Color(0.5, 0.5, 0.55, 1.0))
		return _wolf_texture
	if _deer_texture == null:
		_deer_texture = _make_color_texture(Color(0.76, 0.6, 0.42, 1.0))
	return _deer_texture

func _make_color_texture(color: Color) -> Texture2D:
	var image := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
