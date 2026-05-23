class_name UtilityScorer
extends RefCounted

func score_task(villager: VillagerAgent, task: Task, store: ResourceStore, gt: GameTime) -> float:
	var score: float = 0.0
	var food: int = store.get_resource("food")
	var wood: int = store.get_resource("wood")
	var dist: float = float((villager.tile_position - task.target_tile).length())

	match task.type:
		"gather_food":
			score += maxf(0.0, 10.0 - float(food)) * 3.0
		"chop_tree":
			score += maxf(0.0, 10.0 - float(wood)) * 2.0
		"refuel_campfire":
			score += maxf(0.0, 4.0 - float(wood)) * 5.0
			if gt.phase == GameTime.Phase.DAY and gt.get_time_left() < 3.0:
				score += 50.0
		"return_home":
			if gt.phase == GameTime.Phase.NIGHT:
				score += 100.0

	score -= dist * 0.5
	return score
