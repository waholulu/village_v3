class_name BalanceData
extends RefCounted

var starting_wood: int = 25
var starting_fresh_food: int = 4
var starting_stored_food: int = 8
var villager_count: int = 3
var starting_population: int = 10
var starting_food: int = 40
var starting_security: int = 50
var starting_morale: int = 60
var zero_resource_loss_days: int = 3
var days_per_season: int = 15
var wood_per_tree: int = 3
var food_per_bush: int = 2
var food_consumed_per_villager_per_night: int = 1
var wood_consumed_by_campfire_per_night: int = 2
var food_low_threshold: int = 6
var wood_low_threshold: int = 6
# Surplus thresholds gate when to *cancel* open tasks (vs. low_threshold which
# gates when to *create* them). The gap between low and surplus lets idle
# villagers keep working on existing OPEN tasks instead of going idle the
# moment stock crosses the low_threshold.
var food_surplus_threshold: int = 12
var wood_surplus_threshold: int = 12
var day_duration_seconds: float = 10.0
var night_duration_seconds: float = 5.0
var max_campfire_out_nights: int = 2
var winter_wood_consumption_multiplier: float = 1.5
var fresh_food_spoilage_per_night: int = 1
var villager_move_interval: float = 0.5
var starting_population_capacity: int = 3
var population_growth_enabled: bool = false
var house_wood_cost: int = 8
var population_capacity_per_house: int = 2
var food_required_for_new_villager: int = 2
var max_hunger: int = 3
var world_seed: int = 4312
# v3.1 default map: 60×40 (was 40×27 in v3.0). WorldGenerator reads these at
# the start of generate_from_balance() and applies them via static vars so
# existing WorldGenerator.WIDTH / HUT_POS call sites keep working.
var world_width: int = 60
var world_height: int = 40
var hut_pos_x: int = 15
var hut_pos_y: int = 18
var campfire_pos_x: int = 17
var campfire_pos_y: int = 19
var world_tree_count: int = 60
var world_berry_bush_count: int = 32
var world_blocked_count: int = 32
var nature_tree_regrowth_days: int = 2
var nature_berry_regrowth_days: int = 1
var nature_max_trees: int = 36
var nature_max_berry_bushes: int = 24
var monitor_min_food_nights: int = 1
var monitor_min_wood_nights: int = 1
var monitor_task_backlog_warning: int = 80

# Noise-based world generation
var world_noise_frequency: float = 0.08
var world_noise_forest_threshold: float = 0.30
var world_noise_rocky_threshold: float = -0.30
var world_starting_area_radius: int = 5
var world_cellular_smoothing_passes: int = 2

# Wildlife system
var deer_spawn_per_day: int = 1
var deer_max_count: int = 6
var food_per_deer: int = 3
var deer_hunt_radius: int = 14
var wolf_spawn_day: int = 4
var wolf_spawn_interval_days: int = 3
var wolf_spawn_count: int = 1
var wolf_max_count: int = 3
var wolf_max_age_days: int = 5
var wolf_threat_radius: int = 8
var wolf_hunger_disruption: int = 1

# Construction system
var fence_wolf_damage_reduction: float = 0.10  # multiplicative per fence

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
		else:
			# Catch JSON typos that today silently default. e.g. a balance file
			# with `wolf_threat_radious` (typo) would have shipped unnoticed.
			push_warning("BalanceData: unknown key '%s' in %s" % [key, path])
	return true
