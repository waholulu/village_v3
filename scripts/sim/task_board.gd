class_name TaskBoard
extends RefCounted

var _tasks: Array[Task] = []
var _next_id: int = 1

func create_task(type: String, target_tile: Vector2i, tick: int) -> Task:
	var task = Task.new(_next_id, type, target_tile, tick)
	_next_id += 1
	_tasks.append(task)
	return task

func claim_task(task_id: int, villager_id: int) -> bool:
	var task = get_task(task_id)
	if task == null or task.status != Task.Status.OPEN:
		return false
	task.status = Task.Status.CLAIMED
	task.claimed_by = villager_id
	return true

func complete_task(task_id: int) -> void:
	var task = get_task(task_id)
	if task:
		task.status = Task.Status.COMPLETED

func cancel_task(task_id: int) -> void:
	var task = get_task(task_id)
	if task:
		task.status = Task.Status.CANCELLED

func get_task(task_id: int) -> Task:
	for t in _tasks:
		if t.id == task_id:
			return t
	return null

func get_open_tasks() -> Array[Task]:
	return _tasks.filter(func(t: Task) -> bool: return t.status == Task.Status.OPEN)

func has_open_task_of_type(type: String) -> bool:
	for t in _tasks:
		if t.type == type and t.status == Task.Status.OPEN:
			return true
	return false

func has_task_for_tile(tile: Vector2i) -> bool:
	for t in _tasks:
		if t.target_tile == tile and (t.status == Task.Status.OPEN or t.status == Task.Status.CLAIMED):
			return true
	return false

func count_by_status(status: Task.Status) -> int:
	var count = 0
	for t in _tasks:
		if t.status == status:
			count += 1
	return count

func clear_stale() -> void:
	_tasks = _tasks.filter(func(t: Task) -> bool:
		return t.status == Task.Status.OPEN or t.status == Task.Status.CLAIMED
	)
