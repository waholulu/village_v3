class_name JobDefs
extends RefCounted

const FARMER := "farmer"
const HUNTER := "hunter"
const WOODCUTTER := "woodcutter"
const GUARD := "guard"
const HERBALIST := "herbalist"

const ALL := [
	FARMER,
	HUNTER,
	WOODCUTTER,
	GUARD,
	HERBALIST,
]

static func default_for_index(index: int) -> String:
	return ALL[index % ALL.size()]

static func get_display_name(job: String) -> String:
	match job:
		FARMER:
			return "Farmer"
		HUNTER:
			return "Hunter"
		WOODCUTTER:
			return "Woodcutter"
		GUARD:
			return "Guard"
		HERBALIST:
			return "Herbalist"
	return "Unknown"

static func output_type_for_job(job: String) -> String:
	match job:
		FARMER, HUNTER:
			return "food"
		WOODCUTTER:
			return "wood"
		GUARD:
			return "security"
		HERBALIST:
			return "recovery"
	return ""

static func base_output(job: String) -> int:
	match job:
		FARMER:
			return 2
		HUNTER:
			return 2
		WOODCUTTER:
			return 2
		GUARD:
			return 2
		HERBALIST:
			return 1
	return 0

static func task_score_multiplier(job: String, task_type: String) -> float:
	match job:
		FARMER:
			return 1.5 if task_type == "gather_food" else 0.9
		HUNTER:
			return 1.5 if task_type == "hunt_deer" else 0.9
		WOODCUTTER:
			return 1.5 if task_type == "chop_tree" else 0.9
		GUARD:
			return 1.5 if task_type == "guard_watch" or task_type == "build_fence" or task_type == "build_watchtower" else 0.9
		HERBALIST:
			return 1.5 if task_type == "tend_villager" else 0.9
	return 1.0

static func status_output_multiplier(status: int) -> float:
	match status:
		VillagerAgent.Status.TIRED:
			return 0.5
		VillagerAgent.Status.INJURED, VillagerAgent.Status.SICK, VillagerAgent.Status.DEAD:
			return 0.0
	return 1.0
