extends CanvasLayer

@onready var _panel: Panel = $Panel
@onready var _lbl: Label = $Panel/LblDebug

var _sim: VillageSimulation

func setup(sim: VillageSimulation) -> void:
	_sim = sim

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_panel.visible = not _panel.visible

func _process(_delta: float) -> void:
	if not _panel.visible or _sim == null:
		return
	_lbl.text = _build_debug_text()

func _build_debug_text() -> String:
	var gt = _sim.game_time
	var lines: Array[String] = []
	lines.append("=== DEBUG (F3) ===")
	lines.append("Day: %d / %d" % [gt.day, 7])
	lines.append("Phase: %s" % gt.get_phase_name())
	lines.append("Tick: %d" % gt.tick)
	lines.append("Time left: %.1fs" % gt.get_time_left())
	lines.append("")
	lines.append("Wood: %d" % _sim.store.get_resource("wood"))
	lines.append("Food: %d" % _sim.store.get_resource("food"))
	lines.append("Hungry: %d" % _sim.hungry_villagers)
	lines.append("Campfire out: %d" % _sim.campfire_out_nights)
	lines.append("")
	lines.append("Tasks open: %d" % _sim.board.count_by_status(Task.Status.OPEN))
	lines.append("Tasks claimed: %d" % _sim.board.count_by_status(Task.Status.CLAIMED))
	lines.append("Tasks done: %d" % _sim.board.count_by_status(Task.Status.COMPLETED))
	lines.append("")
	for v in _sim.villagers:
		var task_info = "none"
		if v.current_task_id != -1:
			var t = _sim.board.get_task(v.current_task_id)
			if t:
				task_info = "%s@(%d,%d)" % [t.type, t.target_tile.x, t.target_tile.y]
		lines.append("%s: %s" % [v.name, v.get_state_name()])
		lines.append("  task: %s" % task_info)
		lines.append("  pos: (%d,%d)" % [v.tile_position.x, v.tile_position.y])
	return "\n".join(lines)
