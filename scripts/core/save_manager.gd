class_name SaveManager
extends RefCounted

const SAVE_PATH = "user://save.json"

func save(sim: VillageSimulation) -> void:
	# Snapshot the full grid; building counters, building positions, and
	# resource-tile positions are all derivable from it. Tasks and per-villager
	# state are intentionally NOT saved — F9 resets in-flight work to IDLE and
	# the next tick rebuilds the task list against the loaded world.
	var data = {
		"day": sim.game_time.day,
		"phase": sim.game_time.get_phase_name(),
		"tick": sim.game_time.tick,
		"wood": sim.store.get_resource("wood"),
		"fresh_food": sim.store.get_resource("fresh_food"),
		"stored_food": sim.store.get_resource("stored_food"),
		"strategic_resources": {
			"population": sim.store.get_resource("population"),
			"food": sim.store.get_resource("food"),
			"wood": sim.store.get_resource("wood"),
			"security": sim.store.get_resource("security"),
			"morale": sim.store.get_resource("morale"),
		},
		"zero_streaks": {
			"food": sim.zero_food_days,
			"morale": sim.zero_morale_days,
			"security": sim.zero_security_days,
		},
		"campfire_out_nights": sim.campfire_out_nights,
		"population_capacity": sim.population_capacity,
		"active_policy": sim.active_policy,
		"wolf_threat_count": sim._wolf_threat_count,
		"nature": sim.nature.to_save_data() if sim.nature else {},
		"villagers": [],
		"tiles": _serialize_grid(sim.world_gen),
	}
	for v in sim.villagers:
		data["villagers"].append({
			"id": v.id,
			"name": v.name,
			"tile_x": v.tile_position.x,
			"tile_y": v.tile_position.y,
			"hunger": v.hunger,
			"job": v.job,
			"status": v.get_status_name(),
		})
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("Saved to ", SAVE_PATH)

func _serialize_grid(world_gen: WorldGenerator) -> Array:
	var rows: Array = []
	for y in range(WorldGenerator.HEIGHT):
		var row: Array = []
		for x in range(WorldGenerator.WIDTH):
			row.append(int(world_gen.get_tile(x, y)))
		rows.append(row)
	return rows

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

	# Resources first — store.setup() emits stock_changed so HUD refreshes.
	# Backward compat: pre-Phase-1 saves with "food" key load as fresh_food.
	var fresh_food: int = data.get("fresh_food", data.get("food", 0))
	var stored_food: int = data.get("stored_food", 0)
	sim.store.setup(data["wood"], fresh_food, stored_food)
	var strategic_resources: Dictionary = data.get("strategic_resources", {})
	sim.store.setup_strategic(
		strategic_resources.get("population", sim.store.get_resource("population")),
		strategic_resources.get("food", sim.store.get_resource("food")),
		strategic_resources.get("wood", sim.store.get_resource("wood")),
		strategic_resources.get("security", sim.store.get_resource("security")),
		strategic_resources.get("morale", sim.store.get_resource("morale"))
	)
	var zero_streaks: Dictionary = data.get("zero_streaks", {})
	sim.zero_food_days = zero_streaks.get("food", 0)
	sim.zero_morale_days = zero_streaks.get("morale", 0)
	sim.zero_security_days = zero_streaks.get("security", 0)
	sim.campfire_out_nights = data["campfire_out_nights"]
	sim.population_capacity = data.get("population_capacity", sim.population_capacity)
	sim.active_policy = data.get("active_policy", sim.active_policy)
	sim._wolf_threat_count = data.get("wolf_threat_count", 0)
	if sim.nature != null:
		sim.nature.load_save_data(data.get("nature", {}))
	sim.game_time.day = data["day"]
	sim.game_time.tick = data["tick"]
	sim.game_time.phase = GameTime.Phase.DAY if data["phase"] == "Day" else GameTime.Phase.NIGHT

	# Restore the world grid. set_tile keeps WorldGenerator._tile_index in
	# sync; the pathfinding rebuild below picks up the new walkability.
	_restore_grid(sim, data.get("tiles", []))

	# Building counters are derived from the restored grid — never persisted,
	# never drifting from tile counts.
	sim._fence_count = sim.world_gen.count_tiles_of_type(WorldGenerator.TileType.FENCE)
	sim._watchtower_count = sim.world_gen.count_tiles_of_type(WorldGenerator.TileType.WATCHTOWER)
	sim._storage_count = sim.world_gen.count_tiles_of_type(WorldGenerator.TileType.STORAGE)

	# Drop the live task board — tasks regenerate next tick against the loaded
	# world. Villagers reset to IDLE so they re-decide instead of resuming a
	# task that may no longer be valid.
	sim.board = TaskBoard.new()
	_restore_villagers(sim, data["villagers"])

	# Rebuild pathfinding from the restored world so AStar reflects loaded
	# walls / build_sites / harvested tiles.
	if sim.pathfinding != null:
		sim.pathfinding.setup(sim.world_gen)

	# Broadcast every tile so the tilemap controller, debug overlay, and any
	# other tile_changed listeners redraw against the loaded grid.
	for y in range(WorldGenerator.HEIGHT):
		for x in range(WorldGenerator.WIDTH):
			sim.tile_changed.emit(Vector2i(x, y), sim.world_gen.get_tile(x, y))

	sim.population_changed.emit(sim.villagers.size(), sim.population_capacity)
	sim._update_hungry_count()  # derives + emits hunger_changed
	sim.run_monitor_check()
	print("Loaded from ", SAVE_PATH)
	return true

func _restore_grid(sim: VillageSimulation, tiles: Array) -> void:
	if tiles.is_empty():
		return  # nothing to do; caller already warned via parse
	for y in range(WorldGenerator.HEIGHT):
		if y >= tiles.size():
			break
		var row: Array = tiles[y]
		for x in range(WorldGenerator.WIDTH):
			if x >= row.size():
				break
			sim.world_gen.set_tile(x, y, int(row[x]))

func _restore_villagers(sim: VillageSimulation, entries: Array) -> void:
	while sim.villagers.size() < entries.size():
		sim._add_villager()
	while sim.villagers.size() > entries.size():
		sim.villagers.remove_at(sim.villagers.size() - 1)
	var max_id := 0
	for i in range(sim.villagers.size()):
		var vd: Dictionary = entries[i]
		var v: VillagerAgent = sim.villagers[i]
		v.id = vd["id"]
		v.name = vd["name"]
		var loaded_pos := Vector2i(vd["tile_x"], vd["tile_y"])
		if sim.world_gen.is_in_bounds(loaded_pos) and sim.world_gen.is_walkable(loaded_pos.x, loaded_pos.y):
			v.tile_position = loaded_pos
		else:
			v.tile_position = sim.find_valid_spawn_tile(i)
		v.hunger = vd.get("hunger", 0)
		v.job = vd.get("job", JobDefs.default_for_index(i))
		v.status = _status_from_name(vd.get("status", "healthy"))
		# Reset every transient: villager re-decides on next tick instead of
		# resuming a task that may not exist (board was just emptied).
		v.state = VillagerAgent.State.IDLE
		v.current_task_id = -1
		v._path.clear()
		v._move_timer = 0.0
		max_id = maxi(max_id, v.id)
	sim._next_villager_id = max_id + 1

func _status_from_name(status_name: String) -> VillagerAgent.Status:
	match status_name.to_lower():
		"tired":
			return VillagerAgent.Status.TIRED
		"injured":
			return VillagerAgent.Status.INJURED
		"sick":
			return VillagerAgent.Status.SICK
		"dead":
			return VillagerAgent.Status.DEAD
	return VillagerAgent.Status.HEALTHY
