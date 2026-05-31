class_name VillagerAgent
extends RefCounted

enum State { IDLE, MOVING_TO_TARGET }
enum Status { HEALTHY, TIRED, INJURED, SICK, DEAD }

var id: int
var name: String
var job: String = "farmer"
var tile_position: Vector2i
var state: State = State.IDLE
var status: Status = Status.HEALTHY
var current_task_id: int = -1
var hunger: int = 0

var _path: Array[Vector2i] = []
var _move_timer: float = 0.0

func _init(p_id: int, p_name: String, start_pos: Vector2i, p_job: String = "farmer") -> void:
	id = p_id
	name = p_name
	job = p_job
	tile_position = start_pos

func pick_best_task(board: TaskBoard, store: ResourceStore, gt: GameTime, scorer: UtilityScorer, policy: String = "") -> Task:
	if not can_work():
		return null
	var open_tasks = board.get_open_tasks()
	if open_tasks.is_empty():
		return null
	var best_task: Task = null
	var best_score: float = -INF
	for task in open_tasks:
		var s: float = scorer.score_task(self, task, store, gt, policy)
		if s > best_score:
			best_score = s
			best_task = task
	return best_task

func set_task(task: Task) -> void:
	if not can_work():
		return
	current_task_id = task.id
	state = State.MOVING_TO_TARGET

func clear_task() -> void:
	current_task_id = -1
	state = State.IDLE
	# Wipe transient movement so an idle villager doesn't appear "mid-walk"
	# from a cancelled task's leftover path on the next debug snapshot.
	_path.clear()
	_move_timer = 0.0

func get_state_name() -> String:
	return State.keys()[state]

func get_status_name() -> String:
	return Status.keys()[status].to_lower()

func get_job_name() -> String:
	return job

func can_work() -> bool:
	return status != Status.INJURED and status != Status.SICK and status != Status.DEAD

func tick_movement(delta: float, path: Array[Vector2i], move_interval: float) -> bool:
	if not can_work():
		return false
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
