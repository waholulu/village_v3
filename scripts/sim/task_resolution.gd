class_name TaskResolution
extends RefCounted

static func execute_task_at_target(sim: VillageSimulation, v: VillagerAgent) -> void:
	var task = sim.board.get_task(v.current_task_id)
	if task == null:
		v.clear_task()
		return
	match task.type:
		"chop_tree":
			_complete_chop_tree(sim, v, task)
		"gather_food":
			_complete_gather_food(sim, v, task)
		"hunt_deer":
			_complete_hunt_deer(sim, v, task)
		"guard_watch":
			_complete_guard_watch(sim, v)
		"tend_villager":
			_complete_tend_villager(sim, v)
		"build_house", "build_fence", "build_watchtower", "build_storage":
			if not _execute_build(sim, v, task):
				return
	sim.board.complete_task(task.id)
	v.clear_task()

static func _complete_chop_tree(sim: VillageSimulation, v: VillagerAgent, task: Task) -> void:
	if sim.nature:
		sim.nature.record_harvest(WorldGenerator.TileType.TREE, task.target_tile, sim.game_time.day)
	sim.world_gen.set_tile(task.target_tile.x, task.target_tile.y, WorldGenerator.TileType.GRASS)
	if sim.pathfinding:
		sim.pathfinding.set_point_walkable(task.target_tile, true)
	sim.tile_changed.emit(task.target_tile, WorldGenerator.TileType.GRASS)
	var wood_gained: int = sim._modified_output_amount(v, "wood", sim._balance.wood_per_tree)
	sim.store.add_resource("wood", wood_gained)
	sim._log({"event": "task_completed", "villager": v.name, "task": "chop_tree",
		"wood_gained": wood_gained, "wood_total": sim.store.get_resource("wood")})

static func _complete_gather_food(sim: VillageSimulation, v: VillagerAgent, task: Task) -> void:
	if sim.nature:
		sim.nature.record_harvest(WorldGenerator.TileType.BERRY_BUSH, task.target_tile, sim.game_time.day)
	sim.world_gen.set_tile(task.target_tile.x, task.target_tile.y, WorldGenerator.TileType.GRASS)
	if sim.pathfinding:
		sim.pathfinding.set_point_walkable(task.target_tile, true)
	sim.tile_changed.emit(task.target_tile, WorldGenerator.TileType.GRASS)
	var food_gained: int = sim._modified_output_amount(v, "food", sim._balance.food_per_bush)
	sim.store.add_resource("fresh_food", food_gained)
	sim.store.add_resource("food", food_gained)
	sim._log({"event": "task_completed", "villager": v.name, "task": "gather_food",
		"food_gained": food_gained, "fresh_food_total": sim.store.get_resource("fresh_food")})

static func _complete_hunt_deer(sim: VillageSimulation, v: VillagerAgent, task: Task) -> void:
	if sim.nature == null:
		return
	var deer: WildlifeAgent = sim.nature.find_animal_at(task.target_tile, WildlifeAgent.Kind.DEER)
	if deer != null:
		sim.nature.remove_animal(deer.id)
		var deer_food: int = sim._modified_output_amount(v, "food", sim._balance.food_per_deer)
		sim.store.add_resource("fresh_food", deer_food)
		sim.store.add_resource("food", deer_food)
		sim.wildlife_changed.emit(sim.nature.get_animals_as_dicts())
		sim._log({"event": "deer_hunted", "villager": v.name, "deer_id": deer.id,
			"pos": [task.target_tile.x, task.target_tile.y],
			"food_gained": deer_food, "fresh_food_total": sim.store.get_resource("fresh_food")})
	else:
		sim._log({"event": "deer_escaped", "villager": v.name,
			"pos": [task.target_tile.x, task.target_tile.y]})

static func _complete_guard_watch(sim: VillageSimulation, v: VillagerAgent) -> void:
	var security_gained: int = sim._modified_output_amount(v, "security", JobDefs.base_output(JobDefs.GUARD))
	sim.store.add_resource("security", security_gained)
	sim._log({"event": "task_completed", "villager": v.name, "task": "guard_watch",
		"security_gained": security_gained, "security_total": sim.store.get_resource("security")})

static func _complete_tend_villager(sim: VillageSimulation, v: VillagerAgent) -> void:
	var target := sim._find_recoverable_villager()
	if target != null and sim._roll_percent("herbalist_recovery", v.id) < PolicyResolver.modified_recovery_chance(sim):
		target.status = VillagerAgent.Status.HEALTHY
		var morale_gained: int = sim._modified_output_amount(v, "morale", JobDefs.base_output(JobDefs.HERBALIST))
		sim.store.add_resource("morale", morale_gained)
		sim._log({"event": "task_completed", "villager": v.name, "task": "tend_villager",
			"target": target.name, "morale_gained": morale_gained})

static func _execute_build(sim: VillageSimulation, v: VillagerAgent, task: Task) -> bool:
	var key: String = task.type.replace("build_", "")
	var def: Dictionary = BuildingDefs.BUILDINGS[key]
	if not sim.store.has_enough("wood", def.wood_cost):
		sim.board.cancel_task(task.id)
		v.clear_task()
		sim._log({"event": "task_cancelled", "villager": v.name, "task": task.type,
			"reason": "insufficient_wood"})
		return false
	sim.store.consume_resource("wood", def.wood_cost)
	sim.world_gen.set_tile(task.target_tile.x, task.target_tile.y, def.tile_type)
	if sim.pathfinding:
		sim.pathfinding.set_point_walkable(task.target_tile, true)
	_apply_building_effect(sim, key)
	sim.tile_changed.emit(task.target_tile, def.tile_type)
	sim.population_changed.emit(sim.villagers.size(), sim.population_capacity)
	sim._log({"event": "built", "villager": v.name, "building": key,
		"pos": [task.target_tile.x, task.target_tile.y], "wood_spent": def.wood_cost})
	return true

static func _apply_building_effect(sim: VillageSimulation, key: String) -> void:
	match key:
		"house":
			sim.population_capacity += sim._balance.population_capacity_per_house
		"fence":
			sim._fence_count += 1
		"watchtower":
			sim._watchtower_count += 1
		"storage":
			sim._storage_count += 1
