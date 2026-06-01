extends CanvasLayer

@onready var _lbl_day: Label = $Panel/LblDay
@onready var _lbl_wood: Label = $Panel/LblWood
@onready var _lbl_food: Label = $Panel/LblFood
@onready var _lbl_population: Label = $Panel/LblPopulation
@onready var _lbl_hungry: Label = $Panel/LblHungry
@onready var _lbl_campfire: Label = $Panel/LblCampfire
@onready var _lbl_tasks: Label = $Panel/LblTasks
@onready var _lbl_nature: Label = $Panel/LblNature
@onready var _lbl_ai: Label = $Panel/LblAI
@onready var _lbl_status: Label = $Panel/LblStatus
@onready var _lbl_speed: Label = $Panel/LblSpeed
@onready var _btn_speed_1: Button = $Panel/BtnSpeed1
@onready var _btn_speed_2: Button = $Panel/BtnSpeed2
@onready var _btn_speed_4: Button = $Panel/BtnSpeed4
@onready var _inspector_panel: Panel = $InspectorPanel
@onready var _lbl_tile_title: Label = $InspectorPanel/LblTileTitle
@onready var _lbl_tile_body: Label = $InspectorPanel/LblTileBody

var _sim: VillageSimulation

func _ready() -> void:
	Events.stock_changed.connect(_on_stock_changed)
	Events.day_started.connect(_on_day_started)
	Events.night_started.connect(_on_night_started)
	Events.game_won.connect(_on_game_won)
	Events.game_lost.connect(_on_game_lost)
	Events.speed_changed.connect(_on_speed_changed)
	_btn_speed_1.pressed.connect(_set_speed.bind(1.0))
	_btn_speed_2.pressed.connect(_set_speed.bind(2.0))
	_btn_speed_4.pressed.connect(_set_speed.bind(4.0))
	_on_speed_changed(Engine.time_scale)

func setup(sim: VillageSimulation) -> void:
	_sim = sim
	# Connect directly to sim signals for the labels that don't have an Events
	# autoload entry. Everything is now event-driven; no per-frame polling.
	sim.population_changed.connect(_on_population_changed)
	sim.hunger_changed.connect(_on_hunger_changed)
	sim.wildlife_changed.connect(_on_wildlife_changed)
	sim.monitor_anomalies_changed.connect(_on_monitor_anomalies_changed)
	sim.game_time.day_started.connect(_refresh_tasks_label.unbind(1))
	sim.game_time.night_started.connect(_on_night_started_refresh)
	# Initial-state push so labels aren't blank before the first signal fires.
	_lbl_wood.text = "Wood: %d" % sim.store.get_resource("wood")
	_lbl_food.text = "Food: %d" % sim.store.get_resource("food")
	_refresh_population_label()
	_lbl_hungry.text = "Security: %d" % sim.store.get_resource("security")
	_lbl_campfire.text = "Morale: %d" % sim.store.get_resource("morale")
	_lbl_day.text = "Day %d — %s %s" % [sim.game_time.day, sim.game_time.get_season_name(), sim.game_time.get_phase_name()]
	_refresh_tasks_label()
	_on_wildlife_changed(sim.nature.get_animals_as_dicts() if sim.nature else [])
	_on_monitor_anomalies_changed(sim.monitor_anomalies)
	clear_tile_inspector()

func _on_stock_changed(resource_name: String, _amount: int) -> void:
	if resource_name == "wood":
		_lbl_wood.text = "Wood: %d" % _amount
	elif resource_name == "food":
		_lbl_food.text = "Food: %d" % _amount
	elif resource_name == "population":
		_refresh_population_label()
	elif resource_name == "security":
		_lbl_hungry.text = "Security: %d" % _amount
	elif resource_name == "morale":
		_lbl_campfire.text = "Morale: %d" % _amount

func _on_day_started(day: int) -> void:
	if _sim != null:
		_lbl_day.text = "Day %d — %s Day" % [day, _sim.game_time.get_season_name()]
	else:
		_lbl_day.text = "Day %d — Day" % day

func _on_night_started(day: int) -> void:
	if _sim != null:
		_lbl_day.text = "Day %d — %s Night" % [day, _sim.game_time.get_season_name()]
	else:
		_lbl_day.text = "Day %d — Night" % day

func _on_night_started_refresh(_day: int) -> void:
	# Tasks counter refreshes here too (cheap, infrequent).
	if _sim == null:
		return
	_lbl_campfire.text = "Morale: %d" % _sim.store.get_resource("morale")
	_refresh_tasks_label()

func _on_population_changed(_current: int, _capacity: int) -> void:
	_refresh_population_label()

func _on_hunger_changed(_hungry_count: int) -> void:
	if _sim != null:
		_lbl_hungry.text = "Security: %d" % _sim.store.get_resource("security")

func _refresh_population_label() -> void:
	if _sim == null:
		return
	var dead_count := _sim.get_dead_population()
	_lbl_population.text = "Pop: %d/%d  D%d" % [_sim.get_strategic_population(), _sim.population_capacity, dead_count]

func _on_wildlife_changed(animals: Array) -> void:
	var deer := 0
	var wolves := 0
	for a in animals:
		if a.get("kind", 0) == WildlifeAgent.Kind.WOLF:
			wolves += 1
		else:
			deer += 1
	var pending_t := 0
	var pending_b := 0
	if _sim != null and _sim.nature != null:
		pending_t = _sim.nature.get_pending_count(WorldGenerator.TileType.TREE)
		pending_b = _sim.nature.get_pending_count(WorldGenerator.TileType.BERRY_BUSH)
	_lbl_nature.text = "Nature: deer %d wolves %d, regrow T%d/B%d" % [deer, wolves, pending_t, pending_b]

func _on_monitor_anomalies_changed(anomalies: Array[Dictionary]) -> void:
	if _sim == null:
		_lbl_ai.text = ""
		return
	var food_needed: int = _sim.get_living_population() * _sim._balance.food_consumed_per_villager_per_night
	var wood_needed: int = _sim._balance.wood_consumed_by_campfire_per_night
	var food_short: int = maxi(0, food_needed - _sim.store.get_total_food())
	var wood_short: int = maxi(0, wood_needed - _sim.store.get_resource("wood"))
	var status: String = "Attention" if food_short > 0 or wood_short > 0 or anomalies.size() > 0 else "Stable"
	_lbl_ai.text = "AI: %s  risk F%d/W%d" % [status, food_short, wood_short]

func _refresh_tasks_label() -> void:
	if _sim == null:
		return
	var open: int = _sim.board.count_by_status(Task.Status.OPEN)
	var claimed: int = _sim.board.count_by_status(Task.Status.CLAIMED)
	_lbl_tasks.text = "Tasks: %d open / %d claimed" % [open, claimed]

func _on_game_won() -> void:
	_lbl_status.text = "YOU WIN!"
	_lbl_status.add_theme_color_override("font_color", Color.GREEN)

func _on_game_lost(reason: String) -> void:
	_lbl_status.text = "GAME OVER: " + reason
	_lbl_status.add_theme_color_override("font_color", Color.RED)

func _set_speed(speed: float) -> void:
	Engine.time_scale = speed
	Events.speed_changed.emit(speed)

func _on_speed_changed(speed: float) -> void:
	_lbl_speed.text = "Speed: %dx" % int(speed)
	_btn_speed_1.disabled = is_equal_approx(speed, 1.0)
	_btn_speed_2.disabled = is_equal_approx(speed, 2.0)
	_btn_speed_4.disabled = is_equal_approx(speed, 4.0)

func update_tile_inspector(info: Dictionary) -> void:
	if info.is_empty() or not info.get("in_bounds", false):
		clear_tile_inspector()
		return
	_lbl_tile_title.text = "Tile (%d, %d) — %s" % [info["x"], info["y"], info["tile_name"]]
	var villagers_text := _format_tile_entries(info.get("villagers", []), "name", "None")
	var animals_text := _format_tile_entries(info.get("animals", []), "kind_name", "None")
	var tasks_text := _format_task_entries(info.get("tasks", []))
	_lbl_tile_body.text = "Kind: %s | Walkable: %s\nVillagers: %s\nAnimals: %s\nTasks: %s" % [
		info.get("feature_label", "Unknown"),
		"Yes" if info.get("walkable", false) else "No",
		villagers_text,
		animals_text,
		tasks_text,
	]

func clear_tile_inspector() -> void:
	_lbl_tile_title.text = "Tile Inspector"
	_lbl_tile_body.text = "Click a tile to inspect its terrain, occupants, and tasks."

func is_screen_point_over_ui(screen_pos: Vector2) -> bool:
	for control in [_get_main_panel(), _inspector_panel]:
		if control != null and control.visible and control.get_global_rect().has_point(screen_pos):
			return true
	return false

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
		parts.append("%s [%s %s]" % [task.get("type", "task"), task.get("status", "open"), task.get("relation", "target")])
	return ", ".join(parts)

func _get_main_panel() -> Panel:
	return $Panel
