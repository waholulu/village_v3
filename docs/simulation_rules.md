# Simulation Rules

## Resources
- Wood: starting=10, gained by chopping tree (+3 each)
- Food: starting=8, gained by harvesting berry bush (+2 each)
- Wildlife food: starts at 2, grows by 1 at each day start, and is capped at 8.
- Completing a gather_wildlife task consumes 1 wildlife food and adds +2 food.
- Resources never go below 0

## World
- Fixed map size: 40x27 tiles.
- Map generation is deterministic from `world_seed`.
- The hut remains at `(4, 5)` and the campfire remains at `(6, 6)`.
- Trees, berry bushes, and blocked tiles are generated in small seeded clusters.
- Hut/campfire surroundings are kept clear enough for spawning and movement.
- Every generated tree and berry bush must have a walkable adjacent approach tile reachable from the hut.
- Starting hut and campfire are walkable.
- Trees, berry bushes, blocked tiles, and build sites are not walkable.
- Constructed houses are walkable.
- Pathfinding returns no path when the start or destination is outside the map.
- Walkability updates outside the map are ignored.

## Time
- Day: 10 seconds. Villagers gather.
- Night: 5 seconds. Resources consumed.

## Night resolution (runs once when night starts)
1. Villagers attempt to eat in stable ID order.
   - Fed villagers consume 1 food and reduce hunger by 1, minimum 0.
   - Unfed villagers gain 1 hunger.
   - hungry_villagers = villagers with hunger > 0.
   - Any villager at hunger >= 3 causes a loss.
2. wood_consumed = min(wood, 2)
   if wood_consumed < 2: campfire_out_nights += 1
   else: campfire_out_nights = 0

## Population and houses
- Starting population capacity: 3.
- Default MVP balance has population growth disabled, so the 7-day run stays at 3 villagers.
- If population growth is enabled, population is at capacity, wood >= 8, no active build_house task exists, and a build site exists, create a build_house task.
- Completing build_house consumes 8 wood, converts the build site to a house, and increases population capacity by 2.
- If wood is no longer available when the builder arrives, the build_house task is cancelled and the map does not change.
- At day start, if population growth is enabled, population < capacity, and food >= 2, consume 2 food and add 1 villager at the hut.

## Nature updates
- Chopping a tree records that tile for tree regrowth.
- Gathering a berry bush records that tile for berry regrowth.
- Tree regrowth is allowed after 2 day starts; berry regrowth is allowed after 1 day start.
- Regrowth prefers the original tile, then deterministic nearby grass candidates.
- Regrowth never overwrites hut, campfire, build sites, houses, blocked tiles, or occupied resource tiles.
- Regrowth is capped by `nature_max_trees` and `nature_max_berry_bushes`.
- Regrown trees and berry bushes become non-walkable and update pathfinding.

## Win/loss
- Win: survive past day 7 (day becomes 8)
- Lose: campfire_out_nights >= 2
- Lose: any villager reaches hunger >= 3

## Task generation rules (checked each tick during Day phase)
- food < 6 and no open gather_food task → create gather_food
- food < 6, wildlife_food > 0, and no active gather_wildlife task → create gather_wildlife at the hut
- wood < 6 and no open chop_tree task → create chop_tree
- day phase with < 3s remaining and wood < 4 → create refuel_campfire
- population growth enabled and population >= capacity and wood >= 8 and no active build_house task → create build_house
- night starts → create return_home for each villager
- day starts → cancel any open return_home tasks that were not completed overnight

## Villager task scoring (UtilityScorer)
- gather_food: (10 - food) * 3 - distance * 0.5
- gather_wildlife: (10 - food) * 2.5 - distance * 0.5
- chop_tree:   (10 - wood) * 2 - distance * 0.5
- refuel_campfire: (4 - wood) * 5 + (time_left < 3 ? 50 : 0)
- return_home: 100 if Night else 0
- build_house: 25 - distance * 0.5

## Development monitor
- The monitor reports anomalies only; it does not win, lose, or mutate the simulation.
- Villagers must stay inside the map and stand only on walkable tiles.
- Villager paths must contain only in-bounds, walkable tiles.
- Task target and approach tiles must stay inside the map.
- Task approach tiles must be walkable.
- Claimed tasks must point to an existing villager.
- Claimed tasks must be referenced by the villager that owns the claim.
- Villagers with a current task must reference an existing claimed task owned by that villager.
- Idle villagers cannot retain a current task id.
- Resource stock cannot be negative.
- Population cannot exceed population capacity.
- A moving villager with no path is reported.
- If food cannot cover the configured next-night buffer and no reachable food source exists, report `food_survival_risk`.
- If wood cannot cover the configured next-night buffer and no reachable tree exists, report `wood_survival_risk`.
- If active tasks exceed `monitor_task_backlog_warning`, report `task_backlog_high`.
- Loading a save resets any villager with an out-of-bounds or unwalkable position to a valid spawn tile near the hut.

## Debug snapshot
- HUD and F3 debug overlay read from the same simulation snapshot.
- Snapshot includes resources, population, hunger, campfire out nights, task counts, nature counts, shortfall risk, and AI status.
