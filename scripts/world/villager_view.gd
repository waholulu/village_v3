class_name VillagerView
extends Node2D

const TILE_SIZE: int = 48
const VILLAGER_COLORS: Array[Color] = [
	Color(1.0, 0.9, 0.2),
	Color(0.2, 0.8, 1.0),
	Color(1.0, 0.4, 0.4),
]

var _villagers: Array[VillagerAgent] = []
var _sprites: Array[ColorRect] = []

func setup(villagers: Array[VillagerAgent]) -> void:
	_villagers = villagers
	for i in range(villagers.size()):
		var rect = ColorRect.new()
		rect.size = Vector2(TILE_SIZE - 8, TILE_SIZE - 8)
		rect.color = VILLAGER_COLORS[i % VILLAGER_COLORS.size()]
		add_child(rect)
		_sprites.append(rect)

func _process(_delta: float) -> void:
	for i in range(_villagers.size()):
		var v = _villagers[i]
		_sprites[i].position = Vector2(v.tile_position) * TILE_SIZE + Vector2(4, 4)
