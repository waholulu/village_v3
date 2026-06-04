extends CanvasLayer

const PixelThemeScript = preload("res://scripts/ui/pixel_theme.gd")

@onready var _panel: Panel = $Panel
@onready var _lbl: Label = $Panel/LblDebug

var _sim: VillageSimulation
var _monitor_anomalies: Array[Dictionary] = []

func _ready() -> void:
	_panel.theme = PixelThemeScript.build()

func setup(sim: VillageSimulation) -> void:
	_sim = sim
	_monitor_anomalies = sim.monitor_anomalies
	if not sim.monitor_anomalies_changed.is_connected(_on_monitor_anomalies_changed):
		sim.monitor_anomalies_changed.connect(_on_monitor_anomalies_changed)

func _on_monitor_anomalies_changed(anomalies: Array[Dictionary]) -> void:
	_monitor_anomalies = anomalies

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_panel.visible = not _panel.visible

func _process(_delta: float) -> void:
	if not _panel.visible or _sim == null:
		return
	_lbl.text = _build_debug_text()

func _build_debug_text() -> String:
	var snapshot := _sim.get_snapshot()
	var tasks: Dictionary = snapshot["tasks"]
	var nature: Dictionary = snapshot["nature"]
	var risk: Dictionary = snapshot["risk"]
	var zero_streaks: Dictionary = snapshot["zero_streaks"]
	var lines: Array[String] = []
	lines.append("=== DEBUG (F3) ===")
	lines.append("Day: %d / %d  %s" % [snapshot["day"], snapshot["days_to_win"], snapshot.get("season", "Spring")])
	lines.append("Phase: %s" % snapshot["phase"])
	lines.append("Policy: %s" % snapshot["active_policy_name"])
	lines.append("Tick: %d" % snapshot["tick"])
	lines.append("Time left: %.1fs" % snapshot["time_left"])
	lines.append("")
	lines.append("Wood: %d" % snapshot["wood"])
	lines.append("Food: %d" % snapshot["strategic_food"])
	lines.append("Security: %d" % snapshot["security"])
	lines.append("Morale: %d" % snapshot["morale"])
	lines.append("Population: %d / %d" % [snapshot["population"], snapshot["population_capacity"]])
	lines.append("Living / dead: %d / %d" % [snapshot["visible_population"], snapshot["dead_population"]])
	lines.append("Legacy food: %d+%d (total %d)" % [snapshot["fresh_food"], snapshot["stored_food"], snapshot["total_food"]])
	lines.append("Hungry: %d" % snapshot["hungry"])
	lines.append("Campfire out: %d" % snapshot["campfire_out"])
	lines.append("Zero streaks F/M/S: %d/%d/%d" % [
		zero_streaks["food"], zero_streaks["morale"], zero_streaks["security"]
	])
	lines.append("")
	var pending_event: Dictionary = snapshot.get("pending_event", {})
	if pending_event.is_empty():
		lines.append("Event: none pending")
	else:
		lines.append("Event: %s [%s]" % [pending_event.get("title", ""), pending_event.get("category", "")])
	lines.append("Active event effects: %d" % (snapshot.get("active_event_effects", []) as Array).size())
	var last_result: Dictionary = snapshot.get("last_event_result", {})
	if not last_result.is_empty():
		lines.append("Last event: %s / %s" % [last_result.get("event_title", ""), last_result.get("option_label", "")])
	lines.append("")
	lines.append("Tasks open: %d" % tasks["open"])
	lines.append("Tasks claimed: %d" % tasks["claimed"])
	lines.append("Tasks done: %d" % tasks["completed"])
	lines.append("Tasks cancelled: %d" % tasks["cancelled"])
	lines.append("")
	lines.append("NATURE")
	lines.append("Deer: %d  Wolves: %d" % [nature.get("deer_count", 0), nature.get("wolf_count", 0)])
	lines.append("Pending trees: %d" % nature.get("pending_trees", 0))
	lines.append("Pending berries: %d" % nature.get("pending_berry_bushes", 0))
	lines.append("")
	lines.append("BUILDINGS")
	lines.append("Houses: %d  Fences: %d  Towers: %d  Storage: %d" % [
		_sim.world_gen.count_tiles_of_type(WorldGenerator.TileType.HOUSE) if _sim.world_gen else 0,
		_sim._fence_count, _sim._watchtower_count, _sim._storage_count
	])
	lines.append("")
	lines.append("AI STATUS")
	lines.append("Status: %s" % snapshot["ai_status"])
	lines.append("Food shortfall: %d" % risk["food_shortfall"])
	lines.append("Wood shortfall: %d" % risk["wood_shortfall"])
	lines.append("")
	lines.append("MONITOR")
	if _monitor_anomalies.is_empty():
		lines.append("Monitor: OK")
	else:
		var sorted_anomalies := _monitor_anomalies.duplicate()
		sorted_anomalies.sort_custom(_sort_anomalies)
		lines.append("Monitor: %d anomal%s" % [_monitor_anomalies.size(), "y" if _monitor_anomalies.size() == 1 else "ies"])
		for i in range(mini(4, sorted_anomalies.size())):
			var anomaly: Dictionary = sorted_anomalies[i]
			lines.append("%s [%s]" % [anomaly.get("code", "unknown"), anomaly.get("severity", "warning")])
			lines.append("  %s" % anomaly.get("message", ""))
	lines.append("")
	for v in _sim.villagers:
		var task_info = "none"
		if v.current_task_id != -1:
			var t = _sim.board.get_task(v.current_task_id)
			if t:
				task_info = "%s@(%d,%d)" % [t.type, t.target_tile.x, t.target_tile.y]
		lines.append("%s: %s" % [v.name, v.get_state_name()])
		lines.append("  job: %s" % JobDefs.get_display_name(v.job))
		lines.append("  status: %s" % v.get_status_name())
		lines.append("  task: %s" % task_info)
		lines.append("  pos: (%d,%d)" % [v.tile_position.x, v.tile_position.y])
		lines.append("  hunger: %d" % v.hunger)
	return "\n".join(lines)

func _sort_anomalies(a: Dictionary, b: Dictionary) -> bool:
	return _severity_weight(a.get("severity", "")) > _severity_weight(b.get("severity", ""))

func _severity_weight(severity: String) -> int:
	match severity:
		"critical":
			return 3
		"error":
			return 2
		"warning":
			return 1
	return 0
