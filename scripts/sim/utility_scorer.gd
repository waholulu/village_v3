class_name UtilityScorer
extends RefCounted

func score_task(villager: VillagerAgent, task: Task, store: ResourceStore, _gt: GameTime, policy: String = "") -> float:
	# `_gt` retained for caller compatibility (and future time-of-day modifiers)
	# but currently unused — all scoring is need + distance, day/night
	# behavioral switches are encoded as scorer arms not as gt.phase reads.
	var score: float = 0.0
	var food: int = store.get_total_food()
	var wood: int = store.get_resource("wood")
	# Distance to approach tile, not target. Villager actually walks to
	# approach_tile (target may be non-walkable like a tree or build_site).
	var dist: float = float((villager.tile_position - task.approach_tile).length())

	match task.type:
		"gather_food":
			score += maxf(0.0, 10.0 - float(food)) * 3.0
		"hunt_deer":
			score += maxf(0.0, 10.0 - float(food)) * 2.8
		"chop_tree":
			score += maxf(0.0, 10.0 - float(wood)) * 2.0
		"build_house":
			score += 25.0
		"build_watchtower":
			score += 20.0
		"build_fence":
			score += 15.0
		"build_storage":
			score += 12.0
		"guard_watch":
			score += maxf(0.0, 60.0 - float(store.get_resource("security"))) * 1.0
		"tend_villager":
			score += 18.0

	score -= dist * 0.5
	score *= JobDefs.task_score_multiplier(villager.job, task.type)
	if policy != "":
		score *= PolicyDefs.task_score_multiplier(policy, task.type)
	return score
