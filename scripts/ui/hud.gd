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
	_refresh_snapshot()

func _process(_delta: float) -> void:
	_refresh_snapshot()

func update_resources(wood: int, food: int) -> void:
	_lbl_wood.text = "Wood: %d" % wood
	_lbl_food.text = "Food: %d" % food

func update_population(current: int, capacity: int) -> void:
	_lbl_population.text = "Pop: %d/%d" % [current, capacity]

func update_hunger(hungry_count: int) -> void:
	_lbl_hungry.text = "Hungry: %d" % hungry_count

func update_campfire(out_nights: int) -> void:
	_lbl_campfire.text = "Campfire out: %d" % out_nights

func _refresh_snapshot() -> void:
	if _sim == null:
		return
	var snapshot := _sim.get_snapshot()
	_lbl_day.text = "Day %d/%d - %s" % [snapshot["day"], snapshot["days_to_win"], snapshot["phase"]]
	_lbl_wood.text = "Wood: %d" % snapshot["wood"]
	_lbl_food.text = "Food: %d" % snapshot["food"]
	_lbl_population.text = "Pop: %d/%d" % [snapshot["population"], snapshot["population_capacity"]]
	_lbl_hungry.text = "Hungry: %d" % snapshot["hungry"]
	_lbl_campfire.text = "Campfire out: %d" % snapshot["campfire_out"]
	var tasks: Dictionary = snapshot["tasks"]
	_lbl_tasks.text = "Tasks: %d open / %d claimed" % [tasks["open"], tasks["claimed"]]
	var nature: Dictionary = snapshot["nature"]
	_lbl_nature.text = "Nature: wildlife %d, regrow T%d/B%d" % [
		nature.get("wildlife_food", 0),
		nature.get("pending_trees", 0),
		nature.get("pending_berry_bushes", 0)
	]
	var risk: Dictionary = snapshot["risk"]
	_lbl_ai.text = "AI: %s  risk F%d/W%d" % [
		snapshot["ai_status"],
		risk["food_shortfall"],
		risk["wood_shortfall"]
	]

func _on_stock_changed(resource_name: String, amount: int) -> void:
	if resource_name == "wood":
		_lbl_wood.text = "Wood: %d" % amount
	elif resource_name == "food":
		_lbl_food.text = "Food: %d" % amount

func _on_day_started(day: int) -> void:
	_lbl_day.text = "Day %d — Day" % day

func _on_night_started(day: int) -> void:
	_lbl_day.text = "Day %d — Night" % day

func _on_game_won() -> void:
	_lbl_status.text = "YOU WIN!"
	_lbl_status.add_theme_color_override("font_color", Color.GREEN)

func _on_game_lost(reason: String) -> void:
	_lbl_status.text = "GAME OVER: " + reason
	_lbl_status.add_theme_color_override("font_color", Color.RED)
