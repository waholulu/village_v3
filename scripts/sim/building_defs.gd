class_name BuildingDefs
extends RefCounted

# Central data table for buildable structures. Add a new building by adding
# an entry here + a one-line _condition_met arm in ConstructionPlanner +
# a one-line _apply_building_effect arm in VillageSimulation.
const BUILDINGS = {
	"house": {
		"task_type": "build_house",
		"tile_type": WorldGenerator.TileType.HOUSE,
		"wood_cost": 8,
		"placement": "ring_2_5",
		"priority": 1,
		"max_count": -1,
	},
	"watchtower": {
		"task_type": "build_watchtower",
		"tile_type": WorldGenerator.TileType.WATCHTOWER,
		"wood_cost": 6,
		"placement": "ring_4_5",
		"priority": 2,
		"max_count": 1,
	},
	"fence": {
		"task_type": "build_fence",
		"tile_type": WorldGenerator.TileType.FENCE,
		"wood_cost": 2,
		"placement": "ring_4_5",
		"priority": 3,
		"max_count": 8,
	},
	"storage": {
		"task_type": "build_storage",
		"tile_type": WorldGenerator.TileType.STORAGE,
		"wood_cost": 4,
		"placement": "ring_1_2",
		"priority": 4,
		"max_count": 4,
	},
}

# Priority order for iteration. Hard-coded so planner reads from one place.
const PRIORITY_ORDER: Array[String] = ["house", "watchtower", "fence", "storage"]
