class_name VillagerView
extends Node2D

const TILE_SIZE: int = 36
const VILLAGER_TEXTURE_PATHS: Array[String] = [
	"res://assets/villagers/villager_yellow.png",
	"res://assets/villagers/villager_blue.png",
	"res://assets/villagers/villager_red.png",
]

var _villagers: Array[VillagerAgent] = []
var _sprites: Array[Sprite2D] = []
var _textures: Array[Texture2D] = []

func setup(villagers: Array[VillagerAgent]) -> void:
	_villagers = villagers
	for sprite in _sprites:
		sprite.queue_free()
	_sprites.clear()
	_sync_sprites()

func _process(_delta: float) -> void:
	_sync_sprites()
	for i in range(_villagers.size()):
		var v = _villagers[i]
		_sprites[i].position = Vector2(v.tile_position) * TILE_SIZE + Vector2(6, 6)

func _sync_sprites() -> void:
	while _sprites.size() < _villagers.size():
		var sprite = Sprite2D.new()
		sprite.texture = _get_villager_texture(_sprites.size())
		sprite.centered = false
		add_child(sprite)
		_sprites.append(sprite)

func _get_villager_texture(index: int) -> Texture2D:
	if _textures.is_empty():
		for path in VILLAGER_TEXTURE_PATHS:
			var texture := load(path) as Texture2D
			if texture == null:
				_textures.append(_make_fallback_texture())
			else:
				_textures.append(texture)
	return _textures[index % _textures.size()]

func _make_fallback_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.9, 0.2, 1.0))
	return ImageTexture.create_from_image(image)
