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
		"villagers": [],
		"tasks": []
	}
	for v in sim.villagers:
		data["villagers"].append({
			"id": v.id,
			"name": v.name,
			"tile_x": v.tile_position.x,
			"tile_y": v.tile_position.y,
			"state": v.get_state_name(),
			"current_task_id": v.current_task_id
		})
	for t in sim.board._tasks:
		data["tasks"].append({
			"id": t.id,
			"type": t.type,
			"target_x": t.target_tile.x,
			"target_y": t.target_tile.y,
			"status": Task.Status.keys()[t.status],
			"claimed_by": t.claimed_by
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
	sim.game_time.day = data["day"]
	sim.game_time.tick = data["tick"]
	sim.game_time.phase = GameTime.Phase.DAY if data["phase"] == "Day" else GameTime.Phase.NIGHT
	for i in range(sim.villagers.size()):
		if i < data["villagers"].size():
			var vd = data["villagers"][i]
			sim.villagers[i].tile_position = Vector2i(vd["tile_x"], vd["tile_y"])
	print("Loaded from ", SAVE_PATH)
	return true
