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

var _sim: VillageSimulation

func _ready() -> void:
	Events.stock_changed.connect(_on_stock_changed)
	Events.day_started.connect(_on_day_started)
	Events.night_started.connect(_on_night_started)
	Events.game_won.connect(_on_game_won)
	Events.game_lost.connect(_on_game_lost)

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
	_on_population_changed(sim.villagers.size(), sim.population_capacity)
	_on_hunger_changed(sim.hungry_villagers)
	_lbl_campfire.text = "Campfire out: %d" % sim.campfire_out_nights
	_lbl_day.text = "Day %d/%d — %s" % [sim.game_time.day, sim._balance.days_to_win, sim.game_time.get_phase_name()]
	_refresh_tasks_label()
	_on_wildlife_changed(sim.nature.get_animals_as_dicts() if sim.nature else [])
	_on_monitor_anomalies_changed(sim.monitor_anomalies)

func _on_stock_changed(resource_name: String, amount: int) -> void:
	if resource_name == "wood":
		_lbl_wood.text = "Wood: %d" % amount
	elif resource_name == "food":
		_lbl_food.text = "Food: %d" % amount

func _on_day_started(day: int) -> void:
	if _sim != null:
		_lbl_day.text = "Day %d/%d — Day" % [day, _sim._balance.days_to_win]
	else:
		_lbl_day.text = "Day %d — Day" % day

func _on_night_started(day: int) -> void:
	if _sim != null:
		_lbl_day.text = "Day %d/%d — Night" % [day, _sim._balance.days_to_win]
	else:
		_lbl_day.text = "Day %d — Night" % day

func _on_night_started_refresh(_day: int) -> void:
	# Campfire counter only updates after night resolution, so refresh on night
	# transitions. Tasks counter refreshes here too (cheap, infrequent).
	if _sim == null:
		return
	_lbl_campfire.text = "Campfire out: %d" % _sim.campfire_out_nights
	_refresh_tasks_label()

func _on_population_changed(current: int, capacity: int) -> void:
	_lbl_population.text = "Pop: %d/%d" % [current, capacity]

func _on_hunger_changed(hungry_count: int) -> void:
	_lbl_hungry.text = "Hungry: %d" % hungry_count

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
	var food_needed: int = _sim.villagers.size() * _sim._balance.food_consumed_per_villager_per_night
	var wood_needed: int = _sim._balance.wood_consumed_by_campfire_per_night
	var food_short: int = maxi(0, food_needed - _sim.store.get_resource("food"))
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
