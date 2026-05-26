class_name WildlifeAgent
extends RefCounted

enum Kind { DEER, WOLF }

var id: int
var kind: Kind
var tile_position: Vector2i
var spawn_day: int
var age_days: int = 0

func _init(p_id: int, p_kind: Kind, p_pos: Vector2i, p_day: int) -> void:
	id = p_id
	kind = p_kind
	tile_position = p_pos
	spawn_day = p_day
