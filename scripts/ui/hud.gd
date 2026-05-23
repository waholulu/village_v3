extends CanvasLayer

@onready var _lbl_day: Label = $Panel/LblDay
@onready var _lbl_wood: Label = $Panel/LblWood
@onready var _lbl_food: Label = $Panel/LblFood
@onready var _lbl_status: Label = $Panel/LblStatus

func _ready() -> void:
	Events.stock_changed.connect(_on_stock_changed)
	Events.day_started.connect(_on_day_started)
	Events.night_started.connect(_on_night_started)
	Events.game_won.connect(_on_game_won)
	Events.game_lost.connect(_on_game_lost)

func update_resources(wood: int, food: int) -> void:
	_lbl_wood.text = "Wood: %d" % wood
	_lbl_food.text = "Food: %d" % food

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
