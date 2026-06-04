class_name VillagerView
extends Node2D

const DisplayMetrics = preload("res://scripts/world/display_metrics.gd")
const TILE_SIZE: int = DisplayMetrics.TILE_SIZE
const VILLAGER_TEXTURE_PATHS: Array[String] = [
	"res://assets/villagers_v2/farmer.png",
	"res://assets/villagers_v2/hunter.png",
	"res://assets/villagers_v2/woodcutter.png",
	"res://assets/villagers_v2/guard.png",
	"res://assets/villagers_v2/herbalist.png",
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
		_sprites[i].position = Vector2(v.tile_position) * TILE_SIZE
		_sprites[i].modulate = Color(0.55, 0.55, 0.55, 0.9) if v.status == VillagerAgent.Status.DEAD else Color.WHITE
		_sprites[i].z_index = v.tile_position.y * 10 + 6
		var marker := _sprites[i].get_node("Status") as Label
		marker.text = _status_marker(v.status)
		marker.visible = not marker.text.is_empty()

func _sync_sprites() -> void:
	# Shrink first so a smaller villager list (after F9 load) doesn't leave
	# stale sprites rendering at their last positions.
	while _sprites.size() > _villagers.size():
		_sprites[-1].queue_free()
		_sprites.remove_at(_sprites.size() - 1)
	while _sprites.size() < _villagers.size():
		var sprite = Sprite2D.new()
		sprite.texture = _get_villager_texture(_sprites.size())
		sprite.centered = false
		var marker := Label.new()
		marker.name = "Status"
		marker.position = Vector2(20, -7)
		marker.add_theme_color_override("font_color", Color("#f4e7c5"))
		marker.add_theme_color_override("font_outline_color", Color("#6b2424"))
		marker.add_theme_constant_override("outline_size", 3)
		sprite.add_child(marker)
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

func _status_marker(status: int) -> String:
	match status:
		VillagerAgent.Status.TIRED:
			return "z"
		VillagerAgent.Status.INJURED:
			return "!"
		VillagerAgent.Status.SICK:
			return "+"
		VillagerAgent.Status.DEAD:
			return "x"
	return ""

func _make_fallback_texture() -> Texture2D:
	var image := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.9, 0.2, 1.0))
	return ImageTexture.create_from_image(image)
