class_name Task
extends RefCounted

enum Status { OPEN, CLAIMED, COMPLETED, CANCELLED }

var id: int
var type: String
var target_tile: Vector2i     # the resource cell (often non-walkable, e.g. tree)
var approach_tile: Vector2i   # where the villager must stand to act; defaults to target_tile
var status: Status = Status.OPEN
var claimed_by: int = -1

func _init(p_id: int, p_type: String, p_target: Vector2i) -> void:
	id = p_id
	type = p_type
	target_tile = p_target
	approach_tile = p_target  # caller overrides via `task.approach_tile = adj` if needed
