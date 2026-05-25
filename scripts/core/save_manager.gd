class_name SaveManager
extends RefCounted

const SAVE_PATH = "user://save.json"

func save(sim: VillageSimulation) -> void:
	var data = {
		"day": sim.game_time.day,
		"phase": sim.game_time.get_phase_name(),
		"tick": sim.game_time.tick,
		"wood": sim.store.get_resource("wood"),
		"food": sim.store.get_resource("food"),
		"campfire_out_nights": sim.campfire_out_nights,
		"hungry_villagers": sim.hungry_villagers,
		"population_capacity": sim.population_capacity,
		"nature": sim.nature.to_save_data() if sim.nature else {},
		"villagers": [],
		"tasks": [],
		"houses": []
	}
	for v in sim.villagers:
		data["villagers"].append({
			"id": v.id,
			"name": v.name,
			"tile_x": v.tile_position.x,
			"tile_y": v.tile_position.y,
			"state": v.get_state_name(),
			"hunger": v.hunger,
			"current_task_id": v.current_task_id
		})
	for t in sim.board._tasks:
		data["tasks"].append({
			"id": t.id,
			"type": t.type,
			"target_x": t.target_tile.x,
			"target_y": t.target_tile.y,
			"approach_x": t.approach_tile.x,
			"approach_y": t.approach_tile.y,
			"status": Task.Status.keys()[t.status],
			"claimed_by": t.claimed_by
		})
	for house_pos in sim.world_gen.get_tiles_of_type(WorldGenerator.TileType.HOUSE):
		data["houses"].append({
			"x": house_pos.x,
			"y": house_pos.y
		})
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("Saved to ", SAVE_PATH)

func load_into(sim: VillageSimulation) -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("No save file found at " + SAVE_PATH)
		return false
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Save file parse error")
		return false
	var data: Dictionary = json.get_data()
	sim.store.setup(data["wood"], data["food"])
	sim.campfire_out_nights = data["campfire_out_nights"]
	sim.hungry_villagers = data["hungry_villagers"]
	sim.population_capacity = data.get("population_capacity", sim.population_capacity)
	if sim.nature != null:
		sim.nature.load_save_data(data.get("nature", {}))
	sim.game_time.day = data["day"]
	sim.game_time.tick = data["tick"]
	sim.game_time.phase = GameTime.Phase.DAY if data["phase"] == "Day" else GameTime.Phase.NIGHT
	while sim.villagers.size() < data["villagers"].size():
		sim._add_villager()
	while sim.villagers.size() > data["villagers"].size():
		sim.villagers.remove_at(sim.villagers.size() - 1)
	var max_id := 0
	for i in range(sim.villagers.size()):
		if i < data["villagers"].size():
			var vd = data["villagers"][i]
			sim.villagers[i].id = vd["id"]
			sim.villagers[i].name = vd["name"]
			var loaded_pos := Vector2i(vd["tile_x"], vd["tile_y"])
			if sim.world_gen.is_in_bounds(loaded_pos) and sim.world_gen.is_walkable(loaded_pos.x, loaded_pos.y):
				sim.villagers[i].tile_position = loaded_pos
			else:
				sim.villagers[i].tile_position = sim.find_valid_spawn_tile(i)
			sim.villagers[i].hunger = vd.get("hunger", 0)
			max_id = maxi(max_id, sim.villagers[i].id)
	sim._next_villager_id = max_id + 1
	for site in sim.world_gen.build_sites:
		sim.world_gen.set_tile(site.x, site.y, WorldGenerator.TileType.BUILD_SITE)
		if sim.pathfinding:
			sim.pathfinding.set_point_walkable(site, false)
		sim.tile_changed.emit(site, WorldGenerator.TileType.BUILD_SITE)
	for house in data.get("houses", []):
		var pos := Vector2i(house["x"], house["y"])
		sim.world_gen.set_tile(pos.x, pos.y, WorldGenerator.TileType.HOUSE)
		if sim.pathfinding:
			sim.pathfinding.set_point_walkable(pos, true)
		sim.tile_changed.emit(pos, WorldGenerator.TileType.HOUSE)
	sim.population_changed.emit(sim.villagers.size(), sim.population_capacity)
	sim.hunger_changed.emit(sim.hungry_villagers)
	sim.run_monitor_check()
	print("Loaded from ", SAVE_PATH)
	return true
