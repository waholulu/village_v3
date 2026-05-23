# Simulation Rules

## Resources
- Wood: starting=10, gained by chopping tree (+3 each)
- Food: starting=8, gained by harvesting berry bush (+2 each)
- Resources never go below 0

## Time
- Day: 10 seconds. Villagers gather.
- Night: 5 seconds. Resources consumed.

## Night resolution (runs once when night starts)
1. food_consumed = min(food, villager_count)
   hungry_villagers = villager_count - food_consumed
2. wood_consumed = min(wood, 2)
   if wood_consumed < 2: campfire_out_nights += 1
   else: campfire_out_nights = 0

## Win/loss
- Win: survive past day 7 (day becomes 8)
- Lose: campfire_out_nights >= 2

## Task generation rules (checked each tick during Day phase)
- food < 6 and no open gather_food task → create gather_food
- wood < 6 and no open chop_tree task → create chop_tree
- day phase with < 3s remaining and wood < 4 → create refuel_campfire
- night starts → create return_home for each villager

## Villager task scoring (UtilityScorer)
- gather_food: (10 - food) * 3 - distance * 0.5
- chop_tree:   (10 - wood) * 2 - distance * 0.5
- refuel_campfire: (4 - wood) * 5 + (time_left < 3 ? 50 : 0)
- return_home: 100 if Night else 0
