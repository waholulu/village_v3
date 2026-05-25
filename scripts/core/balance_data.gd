class_name BalanceData
extends RefCounted

var starting_wood: int = 10
var starting_food: int = 8
var villager_count: int = 3
var days_to_win: int = 7
var wood_per_tree: int = 3
var food_per_bush: int = 2
var food_consumed_per_villager_per_night: int = 1
var wood_consumed_by_campfire_per_night: int = 2
var food_low_threshold: int = 6
var wood_low_threshold: int = 6
var wood_campfire_urgent_threshold: int = 4
var time_left_urgent_seconds: float = 3.0
var day_duration_seconds: float = 10.0
var night_duration_seconds: float = 5.0
var max_campfire_out_nights: int = 2
var villager_move_interval: float = 0.5
var starting_population_capacity: int = 3
var population_growth_enabled: bool = false
var house_wood_cost: int = 8
var population_capacity_per_house: int = 2
var food_required_for_new_villager: int = 2
var max_hunger: int = 3
var world_seed: int = 4312
var world_tree_count: int = 32
var world_berry_bush_count: int = 18
var world_blocked_count: int = 18
var nature_tree_regrowth_days: int = 2
var nature_berry_regrowth_days: int = 1
var nature_max_trees: int = 36
var nature_max_berry_bushes: int = 24
var wildlife_food_start: int = 2
var wildlife_food_regrowth_per_day: int = 1
var wildlife_food_capacity: int = 8
var food_per_wildlife: int = 2
var monitor_min_food_nights: int = 1
var monitor_min_wood_nights: int = 1
var monitor_task_backlog_warning: int = 40

func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("BalanceData: file not found at " + path)
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("BalanceData: JSON parse error in " + path)
		return false
	var data: Dictionary = json.get_data()
	for key in data:
		if key in self:
			set(key, data[key])
	return true
