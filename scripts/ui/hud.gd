extends CanvasLayer

const PixelThemeScript = preload("res://scripts/ui/pixel_theme.gd")
const AlertRulesScript = preload("res://scripts/ui/alert_rules.gd")
const MAX_LOG_LINES := 6

@onready var _panel: Panel = $Panel
@onready var _lbl_day: Label = $Panel/TopRow/LblDay
@onready var _lbl_wood: Label = $Panel/TopRow/LblWood
@onready var _lbl_food: Label = $Panel/TopRow/LblFood
@onready var _lbl_population: Label = $Panel/TopRow/LblPopulation
@onready var _lbl_hungry: Label = $Panel/TopRow/LblHungry
@onready var _lbl_campfire: Label = $Panel/TopRow/LblCampfire
@onready var _lbl_speed: Label = $Panel/TopRow/LblSpeed
@onready var _btn_speed_1: Button = $Panel/TopRow/BtnSpeed1
@onready var _btn_speed_2: Button = $Panel/TopRow/BtnSpeed2
@onready var _btn_speed_4: Button = $Panel/TopRow/BtnSpeed4
@onready var _btn_speed_10: Button = $Panel/TopRow/BtnSpeed10
@onready var _lbl_policy: Label = $Panel/BottomRow/LblPolicy
@onready var _lbl_effects: Label = $Panel/BottomRow/LblEffects
@onready var _lbl_tasks: Label = $Panel/BottomRow/LblTasks
@onready var _lbl_construction: Label = $Panel/BottomRow/LblConstruction
@onready var _lbl_nature: Label = $Panel/BottomRow/LblNature
@onready var _lbl_ai: Label = $Panel/BottomRow/LblAI
@onready var _lbl_status: Label = $Panel/BottomRow/LblStatus
@onready var _alert_panel: Panel = $AlertPanel
@onready var _lbl_alerts: Label = $AlertPanel/LblAlerts
@onready var _inspector_panel: Panel = $InspectorPanel
@onready var _lbl_tile_title: Label = $InspectorPanel/LblTileTitle
@onready var _lbl_tile_body: Label = $InspectorPanel/LblTileBody
@onready var _log_panel: Panel = $LogPanel
@onready var _lbl_log: Label = $LogPanel/LblLog
@onready var _modal_dim: ColorRect = $ModalDim
@onready var _policy_panel: Panel = $PolicyPanel
@onready var _event_panel: Panel = $EventPanel
@onready var _event_options: VBoxContainer = $EventPanel/Options
@onready var _result_panel: Panel = $ResultPanel

var _sim: VillageSimulation
var _saved_speed := 1.0
var _is_blocking := false
var _blocking_enabled := false
var _log_lines: Array[String] = []
var _activity_alerts: Array[Dictionary] = []

func _ready() -> void:
	_apply_theme()
	Events.stock_changed.connect(_on_stock_changed)
	Events.day_started.connect(_on_day_started)
	Events.night_started.connect(_on_night_started)
	Events.game_won.connect(_on_game_won)
	Events.game_lost.connect(_on_game_lost)
	Events.speed_changed.connect(_on_speed_changed)
	_btn_speed_1.pressed.connect(_set_speed.bind(1.0))
	_btn_speed_2.pressed.connect(_set_speed.bind(2.0))
	_btn_speed_4.pressed.connect(_set_speed.bind(4.0))
	_btn_speed_10.pressed.connect(_set_speed.bind(10.0))
	$PolicyPanel/Choices/Food.pressed.connect(_choose_policy.bind(PolicyDefs.FOOD_FIRST))
	$PolicyPanel/Choices/Wood.pressed.connect(_choose_policy.bind(PolicyDefs.WOOD_FIRST))
	$PolicyPanel/Choices/Defense.pressed.connect(_choose_policy.bind(PolicyDefs.DEFENSE_FIRST))
	$PolicyPanel/Choices/Rest.pressed.connect(_choose_policy.bind(PolicyDefs.REST_FIRST))
	$PolicyPanel/Choices/Explore.pressed.connect(_choose_policy.bind(PolicyDefs.EXPLORE_FOREST))
	$ResultPanel/BtnResultContinue.pressed.connect(_continue_after_result)
	_on_speed_changed(Engine.time_scale)
	get_viewport().size_changed.connect(_layout_for_viewport)
	_layout_for_viewport()

func setup(sim: VillageSimulation) -> void:
	_sim = sim
	sim.population_changed.connect(_on_population_changed)
	sim.hunger_changed.connect(_on_hunger_changed)
	sim.wildlife_changed.connect(_on_wildlife_changed)
	sim.monitor_anomalies_changed.connect(_on_monitor_anomalies_changed)
	sim.game_time.clock_changed.connect(_on_clock_changed)
	sim.game_time.day_started.connect(_refresh_tasks_label.unbind(1))
	sim.game_time.night_started.connect(_on_night_started_refresh)
	sim.event_pending.connect(_on_event_pending)
	sim.event_resolved.connect(_on_event_resolved)
	sim.policy_changed.connect(_on_policy_changed)
	sim.daily_summary.connect(_on_daily_summary)
	sim.activity_logged.connect(_on_activity_logged)
	_refresh_all()
	_add_log("Day %d: The village wakes beside the fire." % sim.game_time.day)

func enable_blocking_choices() -> void:
	_blocking_enabled = true
	call_deferred("_sync_blocking_state")

func sync_after_load() -> void:
	_refresh_all()
	call_deferred("_sync_blocking_state")

func _apply_theme() -> void:
	var pixel_theme := PixelThemeScript.build()
	for child in get_children():
		if child is Control:
			(child as Control).theme = pixel_theme
	$PolicyPanel/Title.add_theme_color_override("font_color", PixelThemeScript.FIRE)
	$EventPanel/LblEventTitle.add_theme_color_override("font_color", PixelThemeScript.FIRE)
	$ResultPanel/LblResultTitle.add_theme_color_override("font_color", PixelThemeScript.FIRE)
	$AlertPanel/LblAlertTitle.add_theme_color_override("font_color", PixelThemeScript.DANGER)
	$AlertPanel/LblAlerts.add_theme_color_override("font_color", PixelThemeScript.INK)

func _layout_for_viewport() -> void:
	var size := get_viewport().get_visible_rect().size
	_panel.position = Vector2(8, 8)
	_panel.size = Vector2(maxf(640.0, size.x - 16.0), 96)
	$Panel/TopRow.size.x = _panel.size.x - 24.0
	$Panel/BottomRow.size.x = _panel.size.x - 24.0
	$ModalDim.position = Vector2.ZERO
	$ModalDim.size = size
	_alert_panel.size = Vector2(402, 142)
	_alert_panel.position = Vector2(maxf(8.0, size.x - _alert_panel.size.x - 8.0), 116)
	var inspector_y := 116.0
	if _alert_panel.visible:
		inspector_y = _alert_panel.position.y + _alert_panel.size.y + 8.0
	_inspector_panel.position = Vector2(maxf(8.0, size.x - 410.0), inspector_y)
	_log_panel.position = Vector2(8, maxf(330.0, size.y - 250.0))
	for modal in [_policy_panel, _event_panel, _result_panel]:
		modal.position = (size - modal.size) * 0.5

func _refresh_all() -> void:
	if _sim == null:
		return
	_lbl_wood.text = "WOOD %d" % _sim.store.get_resource("wood")
	_lbl_food.text = "FOOD %d" % _sim.store.get_resource("food")
	_lbl_hungry.text = "SECURITY %d" % _sim.store.get_resource("security")
	_lbl_campfire.text = "MORALE %d" % _sim.store.get_resource("morale")
	_refresh_population_label()
	_refresh_time_label()
	_refresh_policy_label()
	_refresh_effects_label()
	_refresh_tasks_label()
	_refresh_construction_label()
	_on_wildlife_changed(_sim.nature.get_animals_as_dicts() if _sim.nature else [])
	_on_monitor_anomalies_changed(_sim.monitor_anomalies)
	_refresh_alerts()
	clear_tile_inspector()

func _on_stock_changed(resource_name: String, amount: int) -> void:
	match resource_name:
		"wood": _lbl_wood.text = "WOOD %d" % amount
		"food": _lbl_food.text = "FOOD %d" % amount
		"population": _refresh_population_label()
		"security": _lbl_hungry.text = "SECURITY %d" % amount
		"morale": _lbl_campfire.text = "MORALE %d" % amount
	_refresh_alerts()

func _on_day_started(_day: int) -> void:
	_refresh_time_label()
	_refresh_effects_label()
	_refresh_alerts()
	call_deferred("_sync_blocking_state")

func _on_night_started(_day: int) -> void:
	_refresh_time_label()
	_refresh_alerts()

func _on_clock_changed(_day: int, _phase: GameTime.Phase, _minute_of_day: int) -> void:
	_refresh_time_label()

func _refresh_time_label() -> void:
	if _sim != null and _sim.game_time != null:
		_lbl_day.text = _sim.game_time.get_day_clock_label()

func _on_night_started_refresh(_day: int) -> void:
	_refresh_tasks_label()

func _on_population_changed(_current: int, _capacity: int) -> void:
	_refresh_population_label()
	_refresh_construction_label()
	_refresh_alerts()

func _on_hunger_changed(_hungry_count: int) -> void:
	if _sim != null:
		_lbl_hungry.text = "SECURITY %d" % _sim.store.get_resource("security")

func _refresh_population_label() -> void:
	if _sim != null:
		_lbl_population.text = "POP %d/%d" % [_sim.get_strategic_population(), _sim.population_capacity]

func _on_wildlife_changed(_animals: Array) -> void:
	pass

func _on_monitor_anomalies_changed(anomalies: Array[Dictionary]) -> void:
	_lbl_status.text = "!" if not anomalies.is_empty() else ""
	_lbl_status.add_theme_color_override("font_color", PixelThemeScript.DANGER)
	_refresh_alerts()

func _refresh_tasks_label() -> void:
	if _sim != null:
		_lbl_tasks.text = "Tasks %d open / %d active" % [
			_sim.board.count_by_status(Task.Status.OPEN),
			_sim.board.count_by_status(Task.Status.CLAIMED),
		]

func _refresh_construction_label() -> void:
	if _sim == null:
		return
	var construction: Dictionary = _sim.get_snapshot().get("construction", {})
	var counts: Dictionary = construction.get("counts", {})
	var active_project: Dictionary = construction.get("active_project", {})
	if not active_project.is_empty():
		_lbl_construction.text = "Project: %s" % active_project.get("label", "Build")
		return
	_lbl_construction.text = "Builds H%d F%d T%d S%d" % [
		counts.get("houses", 0),
		counts.get("fences", 0),
		counts.get("watchtowers", 0),
		counts.get("storage", 0),
	]

func _refresh_policy_label() -> void:
	if _sim != null:
		_lbl_policy.text = "Policy: %s" % PolicyDefs.get_display_name(_sim.active_policy)

func _refresh_effects_label() -> void:
	if _sim == null or _sim.active_event_effects.is_empty():
		_lbl_effects.text = "Effects: none"
		return
	var parts: Array[String] = []
	for effect in _sim.active_event_effects:
		parts.append("%s (%dd)" % [effect.get("label", effect.get("type", "effect")), effect.get("remaining_days", 0)])
	_lbl_effects.text = "Effects: " + ", ".join(parts)

func _refresh_alerts() -> void:
	if _sim == null:
		_alert_panel.visible = false
		_lbl_alerts.text = ""
		return
	_prune_activity_alerts()
	var alerts: Array[Dictionary] = AlertRulesScript.build(_sim.get_snapshot(), _sim.monitor_anomalies, _activity_alerts)
	_alert_panel.visible = not alerts.is_empty()
	if alerts.is_empty():
		_lbl_alerts.text = ""
	else:
		var lines: Array[String] = []
		for alert in alerts:
			lines.append(_format_alert_line(alert))
		_lbl_alerts.text = "\n".join(lines)
	_layout_for_viewport()

func _prune_activity_alerts() -> void:
	if _sim == null or _sim.game_time == null:
		return
	var current_day := _sim.game_time.day
	var kept: Array[Dictionary] = []
	for alert in _activity_alerts:
		if int(alert.get("day", current_day)) >= current_day - 1:
			kept.append(alert)
	_activity_alerts = kept

func _format_alert_line(alert: Dictionary) -> String:
	var marker := "!"
	if String(alert.get("severity", "warning")) == "critical":
		marker = "!!"
	return "%s %s - %s" % [
		marker,
		alert.get("title", "Alert"),
		alert.get("message", ""),
	]

func _set_speed(speed: float) -> void:
	if _is_blocking:
		return
	Engine.time_scale = speed
	Events.speed_changed.emit(speed)

func _on_speed_changed(speed: float) -> void:
	_lbl_speed.text = "Speed: %dx" % int(speed)
	for pair in [[_btn_speed_1, 1.0], [_btn_speed_2, 2.0], [_btn_speed_4, 4.0], [_btn_speed_10, 10.0]]:
		(pair[0] as Button).disabled = _is_blocking or is_equal_approx(speed, pair[1])

func _sync_blocking_state() -> void:
	if _sim == null or not _blocking_enabled:
		return
	if _sim.can_change_policy():
		_show_policy_panel()
	elif _sim.has_pending_event():
		_show_event_panel(_sim.pending_event)
	else:
		_end_blocking()

func _begin_blocking() -> void:
	if not _is_blocking:
		_saved_speed = Engine.time_scale if Engine.time_scale > 0.0 else 1.0
	_is_blocking = true
	Engine.time_scale = 0.0
	_modal_dim.visible = true
	_on_speed_changed(0.0)

func _end_blocking() -> void:
	if not _is_blocking:
		return
	_policy_panel.visible = false
	_event_panel.visible = false
	_result_panel.visible = false
	_modal_dim.visible = false
	_is_blocking = false
	Engine.time_scale = _saved_speed
	Events.speed_changed.emit(_saved_speed)

func _show_policy_panel() -> void:
	_begin_blocking()
	_policy_panel.visible = true
	_event_panel.visible = false
	_result_panel.visible = false

func _choose_policy(policy: String) -> void:
	if _sim == null or not _sim.set_policy(policy):
		return
	_policy_panel.visible = false
	_refresh_policy_label()
	_sync_blocking_state()

func _on_policy_changed(policy: String, day: int) -> void:
	_refresh_policy_label()
	_add_log("Day %d: Policy set to %s." % [day, PolicyDefs.get_display_name(policy)])

func _on_event_pending(_event: Dictionary) -> void:
	if not _blocking_enabled:
		return
	call_deferred("_sync_blocking_state")

func _show_event_panel(event: Dictionary) -> void:
	_begin_blocking()
	_policy_panel.visible = false
	_result_panel.visible = false
	_event_panel.visible = true
	$EventPanel/LblCategory.text = String(event.get("category", "event")).to_upper()
	$EventPanel/LblEventTitle.text = event.get("title", "Event")
	$EventPanel/LblEventText.text = event.get("text", "")
	for child in _event_options.get_children():
		_event_options.remove_child(child)
		child.queue_free()
	for option in event.get("options", []):
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 72)
		button.text = "%s\n%s" % [option.get("label", "Choose"), _format_effect_preview(option)]
		button.pressed.connect(_choose_event_option.bind(str(option.get("id", ""))))
		_event_options.add_child(button)

func _format_effect_preview(option: Dictionary) -> String:
	var parts: Array[String] = []
	for effect in option.get("immediate", []):
		if effect.get("type", "") == "resource_delta":
			parts.append("%s %+d" % [String(effect.get("resource", "")).capitalize(), int(effect.get("amount", 0))])
		elif effect.get("type", "") == "villager_status":
			parts.append("Villager: %s" % effect.get("status", "affected"))
	var short_term = option.get("short_term", null)
	if short_term is Dictionary:
		parts.append("%s for %dd" % [short_term.get("label", "Short-term effect"), short_term.get("duration_days", 1)])
	return " | ".join(parts)

func _choose_event_option(option_id: String) -> void:
	if _sim == null:
		return
	var result := _sim.resolve_pending_event(option_id)
	if not result.get("ok", false):
		return
	_event_panel.visible = false
	_result_panel.visible = true
	$ResultPanel/LblResultText.text = "%s\n\n%s" % [result.get("option_label", ""), result.get("result_text", "")]
	_refresh_effects_label()

func _on_event_resolved(result: Dictionary) -> void:
	_add_log("Day %d: %s - %s" % [_sim.game_time.day, result.get("event_title", "Event"), result.get("option_label", "")])

func _continue_after_result() -> void:
	_result_panel.visible = false
	_sync_blocking_state()

func _on_daily_summary(summary: Dictionary) -> void:
	_add_log("Day %d: +%d food, +%d wood, +%d security, +%d morale." % [
		summary.get("day", 0), summary.get("food", 0), summary.get("wood", 0),
		summary.get("security", 0), summary.get("morale", 0),
	])
	_refresh_alerts()

func _on_activity_logged(entry: Dictionary) -> void:
	match String(entry.get("event", "")):
		"construction_planned":
			_add_log("%s planned." % String(entry.get("building", "building")).capitalize())
			_refresh_tasks_label()
			_refresh_construction_label()
		"villager_born":
			_add_log("%s joined the village." % entry.get("name", "A villager"))
		"villager_died":
			_add_log("%s died: %s." % [entry.get("villager", "A villager"), entry.get("reason", "unknown cause")])
			_add_activity_alert("death_%s" % entry.get("id", _activity_alerts.size()), "critical", "Villager died", String(entry.get("villager", "A villager")))
		"built":
			_add_log("%s completed a %s." % [entry.get("villager", "A villager"), entry.get("building", "building")])
			_refresh_tasks_label()
			_refresh_construction_label()
		"campfire_out":
			_add_log("The campfire went out.")
		"wolf_threat":
			_add_log("Wolves threatened the village.")
			_add_activity_alert("wolf_threat_%d" % _activity_alerts.size(), "critical", "Wolf threat", String(entry.get("disrupted_villager", "A villager")))
	_refresh_alerts()

func _add_log(text: String) -> void:
	if text.is_empty():
		return
	_log_lines.push_front(text)
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines.resize(MAX_LOG_LINES)
	_lbl_log.text = "\n".join(_log_lines)

func _add_activity_alert(id: String, severity: String, title: String, message: String) -> void:
	var day := _sim.game_time.day if _sim != null and _sim.game_time != null else 0
	_activity_alerts.push_front({
		"id": id,
		"severity": severity,
		"title": title,
		"message": message,
		"day": day,
	})
	if _activity_alerts.size() > AlertRulesScript.MAX_ALERTS:
		_activity_alerts.resize(AlertRulesScript.MAX_ALERTS)

func _on_game_won() -> void:
	_show_end_state("THE VILLAGE SURVIVES", "You kept the campfire burning through day 60.")

func _on_game_lost(reason: String) -> void:
	_show_end_state("THE CAMPFIRE FADES", reason)

func _show_end_state(title: String, body: String) -> void:
	_begin_blocking()
	_policy_panel.visible = false
	_event_panel.visible = false
	_result_panel.visible = true
	$ResultPanel/LblResultTitle.text = title
	$ResultPanel/LblResultText.text = body
	$ResultPanel/BtnResultContinue.visible = false

func update_tile_inspector(info: Dictionary) -> void:
	if info.is_empty() or not info.get("in_bounds", false):
		clear_tile_inspector()
		return
	_inspector_panel.visible = true
	_lbl_tile_title.text = "Tile (%d, %d) - %s" % [info["x"], info["y"], info["tile_name"]]
	_lbl_tile_body.text = "%s | Walkable: %s\nVillagers: %s\nAnimals: %s\nTasks: %s" % [
		info.get("feature_label", "Unknown"),
		"Yes" if info.get("walkable", false) else "No",
		_format_tile_entries(info.get("villagers", []), "name", "None"),
		_format_tile_entries(info.get("animals", []), "kind_name", "None"),
		_format_task_entries(info.get("tasks", [])),
	]

func clear_tile_inspector() -> void:
	_inspector_panel.visible = false
	_lbl_tile_title.text = "Tile Inspector"
	_lbl_tile_body.text = "Click a tile to inspect it."

func is_screen_point_over_ui(screen_pos: Vector2) -> bool:
	for control in [_panel, _alert_panel, _inspector_panel, _log_panel, _policy_panel, _event_panel, _result_panel]:
		if control.visible and control.get_global_rect().has_point(screen_pos):
			return true
	return _modal_dim.visible

func is_blocking() -> bool:
	return _is_blocking

func _format_tile_entries(entries: Array, label_key: String, fallback: String) -> String:
	if entries.is_empty():
		return fallback
	var parts: Array[String] = []
	for entry in entries:
		var label := String(entry.get(label_key, "Unknown"))
		if entry.has("status"):
			label += " (%s)" % entry.get("status", "")
		parts.append(label)
	return ", ".join(parts)

func _format_task_entries(tasks: Array) -> String:
	if tasks.is_empty():
		return "None"
	var parts: Array[String] = []
	for task in tasks:
		parts.append("%s [%s]" % [task.get("type", "task"), task.get("status", "open")])
	return ", ".join(parts)

func _get_main_panel() -> Panel:
	return _panel
