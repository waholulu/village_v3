class_name ConstructionPlanner
extends RefCounted

const RING_BOUNDS: Dictionary = {
	"ring_1_2": [1, 2],
	"ring_2_5": [2, 5],
	"ring_4_5": [4, 5],
}

# Decide what (if anything) to build next. Called once per day_started.
# Returns {} when no construction is needed or possible.
func plan(sim: VillageSimulation) -> Dictionary:
	var wood: int = sim.store.get_resource("wood")
	for key in BuildingDefs.PRIORITY_ORDER:
		var def: Dictionary = BuildingDefs.BUILDINGS[key]
		if wood < def.wood_cost:
			continue
		if sim.board.has_active_task_of_type(def.task_type):
			continue
		if _count_existing(sim, def.tile_type) >= def.max_count and def.max_count != -1:
			continue
		if not _condition_met(key, sim):
			continue
		var pos: Vector2i = _find_site(key, sim)
		if pos == Vector2i(-1, -1):
			continue
		return {
			"type": key,
			"pos": pos,
			"task_type": def.task_type,
			"tile_type": def.tile_type,
			"wood_cost": def.wood_cost,
		}
	return {}

func _condition_met(key: String, sim: VillageSimulation) -> bool:
	match key:
		"house":
			return sim._balance.population_growth_enabled \
				and sim.get_living_population() >= sim.population_capacity
		"fence":
			# Wait for wolves to prove they're a real threat before fortifying —
			# avoids wasting wood on perimeter defense when the campfire never
			# fails (in which case _apply_wolf_disruption never fires).
			return sim._fence_count < 8 and _has_wolves(sim) and sim._wolf_threat_count > 0
		"watchtower":
			return sim.game_time != null and sim.game_time.day >= 4 and sim._watchtower_count == 0
		"storage":
			# Storage protects fresh surplus; stable stored food already lives in
			# the unified food pool and should not force an opening build. The
			# max_count cap is enforced by plan() via _count_existing, so this
			# only gates on the surplus trigger.
			return sim.store.get_resource("fresh_food") >= sim._balance.food_surplus_threshold
	return false

func _has_wolves(sim: VillageSimulation) -> bool:
	if sim.nature == null:
		return false
	for a in sim.nature.animals:
		if a.kind == WildlifeAgent.Kind.WOLF:
			return true
	return false

func _count_existing(sim: VillageSimulation, tile_type: int) -> int:
	if sim.world_gen == null:
		return 0
	return sim.world_gen.count_tiles_of_type(tile_type)

func _find_site(key: String, sim: VillageSimulation) -> Vector2i:
	# House special-case: try pre-placed build_sites first to preserve
	# test_village_growth.gd behaviour (no surprise relocations).
	if key == "house":
		var pre: Vector2i = sim.world_gen.find_next_build_site()
		if pre != Vector2i(-1, -1):
			return pre
	var def: Dictionary = BuildingDefs.BUILDINGS[key]
	var bounds: Array = RING_BOUNDS[def.placement]
	# Spread same-type buildings around the village by preferring tiles that
	# maximise distance to existing instances. For first-of-kind, falls through
	# to first valid candidate.
	return _ring_search(sim, bounds[0], bounds[1], def.tile_type)

func _ring_search(sim: VillageSimulation, min_dist: int, max_dist: int, spread_from_tile: int) -> Vector2i:
	var hut: Vector2i = WorldGenerator.HUT_POS
	var candidates: Array[Vector2i] = []
	for r in range(min_dist, max_dist + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if max(abs(dx), abs(dy)) != r:
					continue
				var pos: Vector2i = hut + Vector2i(dx, dy)
				if not sim.world_gen.is_in_bounds(pos):
					continue
				if sim.world_gen.get_tile(pos.x, pos.y) != WorldGenerator.TileType.GRASS:
					continue
				if pos in sim.world_gen.build_sites:
					continue
				if sim.world_gen.find_walkable_adjacent(pos) == Vector2i(-1, -1):
					continue
				candidates.append(pos)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	var existing: Array[Vector2i] = sim.world_gen.get_tiles_of_type(spread_from_tile)
	if existing.is_empty():
		return candidates[0]
	# Pick the candidate whose nearest existing same-type tile is farthest away.
	var best: Vector2i = candidates[0]
	var best_min_dist: float = -1.0
	for c in candidates:
		var min_d: float = INF
		for e in existing:
			var d: float = Vector2(c - e).length()
			if d < min_d:
				min_d = d
		if min_d > best_min_dist:
			best_min_dist = min_d
			best = c
	return best
