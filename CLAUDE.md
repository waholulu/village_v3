# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

**Run all tests (headless):**
```powershell
& "E:\godot\Godot_v4.6.3-stable_win64.exe" --headless --path "E:\godot\tiny-campfire-village" -s res://addons/gut/gut_cmdln.gd -- -gdir=res://tests -ginclude_subdirs -gexit
```

**Run a single test file:**
```powershell
& "E:\godot\Godot_v4.6.3-stable_win64.exe" --headless --path "E:\godot\tiny-campfire-village" -s res://addons/gut/gut_cmdln.gd -- -gdir=res://tests -gtest=res://tests/test_night_resolution.gd -gexit
```

**Import new scripts (required after adding/renaming files, before tests will recognize new class_names):**
```powershell
& "E:\godot\Godot_v4.6.3-stable_win64.exe" --headless --path "E:\godot\tiny-campfire-village" --import
```

**Run headless simulation (full game, fast timers):**
```powershell
& "E:\godot\Godot_v4.6.3-stable_win64.exe" --headless --path "E:\godot\tiny-campfire-village" -s res://scripts/core/headless_runner.gd
```

**Launch game:**
```powershell
& "E:\godot\Godot_v4.6.3-stable_win64.exe" --path "E:\godot\tiny-campfire-village"
```

After adding any new `.gd` file with `class_name`, always run `--import` before running tests, or GUT will report the class as not found.

## Architecture

### Separation of concerns

Simulation logic (`scripts/sim/`, `scripts/core/`, `scripts/world/`) extends `RefCounted` or `Node` but contains **no rendering code**. Rendering (`scripts/world/tile_map_controller.gd`, `scripts/world/villager_view.gd`) reads simulation state but never mutates it. `scenes/main/main.gd` is the only wiring point between the two layers.

### Signal flow

```
VillageSimulation signals → main.gd handlers → rendering/Events
```

- `VillageSimulation.tile_changed(pos, new_type)` → `_tilemap.refresh_tile(pos, type)` — one tile refresh per world mutation, not a full redraw
- `VillageSimulation.store.stock_changed` → `Events.stock_changed` → HUD
- `VillageSimulation.population_changed` / `hunger_changed` → HUD update methods
- `GameTime.night_started` / `day_started` → `Events` (forwarded from main)
- `Events` autoload (`scripts/core/events.gd`) carries only signals that have both an emitter and a listener in the UI layer

### The simulation tick

`VillageSimulation._process(delta)` runs every frame during DAY only:
1. `_generate_tasks()` — creates tasks per-tick when thresholds are unmet; `has_task_for_tile()` deduplicates per resource tile
2. `_tick_villagers(delta)` — each IDLE villager claims the highest-scoring open task, computes a path to `task.approach_tile` (not `target_tile`), cancels if path is empty; MOVING_TO_TARGET villagers advance along their path
3. `run_monitor_check()` — `SimulationMonitor` scans for anomalies; emits `monitor_anomalies_changed` only when the anomaly list changes

### Why `approach_tile` vs `target_tile`

`AStarGrid2D.get_id_path` returns `[]` if the endpoint is solid. Trees, berry bushes, and build sites are non-walkable. Every resource task carries two positions: `target_tile` (the resource cell) and `approach_tile` (the adjacent walkable cell the villager actually navigates to). `WorldGenerator.find_walkable_adjacent()` resolves this; tasks where no adjacent walkable tile exists are silently dropped.

### Mutation order in `_execute_task_at_target`

Always: `world_gen.set_tile` → `pathfinding.set_point_walkable` → `tile_changed.emit` → `store.add_resource`. Listeners on `tile_changed` read `world_gen` and must see the new state.

### Population growth

`VillageSimulation.population_capacity` starts at `balance.starting_population_capacity`. Building a `HOUSE` tile adds `population_capacity_per_house`. Each day start, `_grow_population_if_possible()` spawns a new villager if `villagers.size() < population_capacity` and enough food exists. The `build_house` task targets a `BUILD_SITE` tile; the approach tile is a walkable neighbor.

### Hunger system

Each night, each villager is fed individually; if food is insufficient a villager gains `+1 hunger`. Hunger decrements by 1 when fed. If any villager reaches `max_hunger`, `game_lost` fires immediately. `hungry_villagers` counts villagers with `hunger > 0`.

### Idempotent test setup

`VillageSimulation.setup_for_test(wood, food, villager_count)` always calls `_reset_state()` first, which clears `villagers`, frees the old `GameTime` node, and zeroes all counters. This makes `before_each` safe to call multiple times without state accumulation.

### Key constants

`WorldGenerator.WIDTH = 40`, `WorldGenerator.HEIGHT = 27`. `HUT_POS = Vector2i(4, 5)`, `CAMPFIRE_POS = Vector2i(6, 6)`.

### Balance tuning

All numeric parameters live in `data/balance.json` and are loaded into `BalanceData` at startup. `BalanceData` uses `set(key, value)` reflection — adding a new parameter requires adding both a property to the class and a key to the JSON file.

### Adding a new task type

1. Add the type string to `UtilityScorer.score_task` match block
2. Handle the type in `VillageSimulation._execute_task_at_target` match block
3. Add task generation logic in `_generate_tasks` (day-time generation only — there are no night-time tasks; `_on_night_started` is for resolution, not creation)
4. If the target tile is non-walkable, use `_try_create_resource_task` (handles approach tile + dedup automatically)

For buildings specifically, the planner already covers the create + score steps via the `BuildingDefs` table — see Phase 0 plan. Do **not** add `return_home` or `refuel_campfire`-style placeholder tasks; they were removed and the anti-feature list in `ROADMAP.md` prohibits resurrection.

### SimulationMonitor

`scripts/sim/simulation_monitor.gd` is a passive checker invoked via `run_monitor_check()`. It returns `Array[Dictionary]` with keys `code`, `severity` (`"warning"/"error"/"critical"`), `message`. The debug overlay (F3) shows up to 4 anomalies sorted by severity. The monitor runs after every state-mutating operation.
