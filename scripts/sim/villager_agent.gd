class_name VillagerAgent
extends RefCounted

enum State { IDLE, MOVING_TO_TARGET }

var id: int
var name: String
var tile_position: Vector2i
var state: State = State.IDLE
var current_task_id: int = -1
var hunger: int = 0

var _path: Array[Vector2i] = []
var _move_timer: float = 0.0

func _init(p_id: int, p_name: String, start_pos: Vector2i) -> void:
	id = p_id
	name = p_name
	tile_position = start_pos

func pick_best_task(board: TaskBoard, store: ResourceStore, gt: GameTime, scorer: UtilityScorer) -> Task:
	var open_tasks = board.get_open_tasks()
	if open_tasks.is_empty():
		return null
	var best_task: Task = null
	var best_score: float = -INF
	for task in open_tasks:
		var s: float = scorer.score_task(self, task, store, gt)
		if s > best_score:
			best_score = s
			best_task = task
	return best_task

func set_task(task: Task) -> void:
	current_task_id = task.id
	state = State.MOVING_TO_TARGET

func clear_task() -> void:
	current_task_id = -1
	state = State.IDLE

func get_state_name() -> String:
	return State.keys()[state]

func tick_movement(delta: float, path: Array[Vector2i], move_interval: float) -> bool:
	if path.is_empty():
		return false
	_move_timer += delta
	# Consume accumulated time in steps so large deltas (e.g. time_scale > 1)
	# don't stall villagers at one tile per frame.
	while _move_timer >= move_interval:
		_move_timer -= move_interval
		if path.size() > 1:
			tile_position = path[1]
			path.remove_at(0)
		else:
			tile_position = path[0]
			path.clear()
			return true
	return false
