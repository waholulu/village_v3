class_name PolicyDefs
extends RefCounted

const FOOD_FIRST := "food_first"
const WOOD_FIRST := "wood_first"
const DEFENSE_FIRST := "defense_first"
const REST_FIRST := "rest_first"
const EXPLORE_FOREST := "explore_forest"

const ALL := [
	FOOD_FIRST,
	WOOD_FIRST,
	DEFENSE_FIRST,
	REST_FIRST,
	EXPLORE_FOREST,
]

static func default_policy() -> String:
	return FOOD_FIRST

static func is_valid(policy: String) -> bool:
	return policy in ALL

static func can_change_on_day(day: int) -> bool:
	return day >= 1 and day <= 57 and (day - 1) % 7 == 0

static func get_display_name(policy: String) -> String:
	match policy:
		FOOD_FIRST:
			return "Food First"
		WOOD_FIRST:
			return "Wood First"
		DEFENSE_FIRST:
			return "Defense First"
		REST_FIRST:
			return "Rest First"
		EXPLORE_FOREST:
			return "Explore Forest"
	return "Unknown"

static func output_multiplier(policy: String, output_type: String) -> float:
	match policy:
		FOOD_FIRST:
			return 1.35 if output_type == "food" else 1.0
		WOOD_FIRST:
			return 1.35 if output_type == "wood" else 1.0
		DEFENSE_FIRST:
			return 1.35 if output_type == "security" else 1.0
		REST_FIRST:
			return 1.35 if output_type == "morale" or output_type == "recovery" else 1.0
		EXPLORE_FOREST:
			return 1.25 if output_type == "food" or output_type == "wood" else 1.0
	return 1.0

static func task_score_multiplier(policy: String, task_type: String) -> float:
	match policy:
		FOOD_FIRST:
			return 1.35 if task_type == "gather_food" or task_type == "hunt_deer" else 1.0
		WOOD_FIRST:
			return 1.35 if task_type == "chop_tree" else 1.0
		DEFENSE_FIRST:
			return 1.35 if task_type == "guard_watch" or task_type == "build_fence" or task_type == "build_watchtower" else 1.0
		REST_FIRST:
			return 1.35 if task_type == "tend_villager" else 1.0
		EXPLORE_FOREST:
			return 1.2 if task_type == "hunt_deer" or task_type == "chop_tree" else 1.0
	return 1.0

static func task_intent_bonus(policy: String, task_type: String) -> float:
	match policy:
		FOOD_FIRST:
			return 12.0 if task_type == "gather_food" or task_type == "hunt_deer" else 0.0
		WOOD_FIRST:
			return 10.0 if task_type == "chop_tree" else 0.0
		EXPLORE_FOREST:
			return 8.0 if task_type == "gather_food" or task_type == "hunt_deer" or task_type == "chop_tree" else 0.0
	return 0.0
