# Project Overview

This document is the current single-page reference for Tiny Campfire Village.
For exact simulation rule details, also read `docs/simulation_rules.md`.

## Goal
- Tiny Campfire Village is a small Godot 4.6 MVP for testing an agent-friendly game development workflow.
- The player starts with 3 villagers.
- Villagers gather wood and food during the day.
- At night, villagers consume food and the campfire consumes wood.
- Survive past day 7 to win.
- Lose if the campfire is out for 2 consecutive nights or any villager reaches hunger 3.

## Tech Stack
- Engine: Godot 4.6
- Language: GDScript
- Rendering: `TileMapLayer` plus simple `Sprite2D` villager views
- Pathfinding: `AStarGrid2D`
- Tests: GUT
- Save data: JSON at `user://save.json`
- Balance data: JSON at `data/balance.json`

## Run Commands
Open the project in Godot 4.6 and press F5.

Run all tests:
```powershell
E:\godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . -s res://addons/gut/gut_cmdln.gd -- -gdir=res://tests -gexit
```

In PowerShell, if Godot reports `Unknown arguments: ["//tests"]`, use:
```powershell
& 'E:\godot\Godot_v4.6.3-stable_win64_console.exe' --% --headless --path . -s res://addons/gut/gut_cmdln.gd -- -gdir=res://tests -gexit
```

Headless scene startup smoke test:
```powershell
& 'E:\godot\Godot_v4.6.3-stable_win64_console.exe' --% --headless --path . --quit-after 2
```

## Current Test Status
- Latest verified GUT run: 119 tests passing.
- Test suites cover time, resources, world generation, pathfinding, tasks, villagers, night resolution, population growth, save/load recovery, and simulation monitoring.
- Any new simulation rule should get a matching GUT test.

## Controls
- F3: toggle debug overlay.
- F5: save game to `user://save.json`.
- F9: load game from `user://save.json`.

## Directory Map
- `data`: tunable balance JSON.
- `docs`: project and rule documentation.
- `scenes/main`: main scene and bootstrapping script.
- `scenes/ui`: HUD and debug overlay scenes.
- `scenes/world`: world scene.
- `scripts/core`: events, balance loading, time, resources, save/load, headless runner.
- `scripts/world`: map generation, tile rendering, pathfinding, villager rendering.
- `scripts/sim`: simulation-only logic for villagers, tasks, scoring, orchestration, monitoring.
- `scripts/ui`: HUD and debug overlay scripts.
- `tests`: GUT tests.

## Architecture
Simulation logic is separate from rendering.

Core flow:
1. `scenes/main/main.gd` loads `BalanceData`, creates `WorldGenerator`, `PathfindingService`, and `VillageSimulation`.
2. `VillageSimulation` owns the live simulation state: resources, time, tasks, villagers, population, hunger, campfire state, and monitor.
3. `TileMapController`, `VillagerView`, `HUD`, and `DebugOverlay` observe or render simulation state.
4. `Events` is the global signal bus for high-level UI-facing events.

Rendering should not own gameplay rules. If a rule changes, update simulation code and tests first, then UI if needed.

## Important Classes
- `BalanceData`: loads tunable numeric values from `data/balance.json`.
- `GameTime`: advances day/night phases and emits win when day exceeds `days_to_win`.
- `ResourceStore`: stores wood and food and prevents normal consumption from going below zero.
- `WorldGenerator`: creates the deterministic 40x27 map and exposes tile queries.
- `PathfindingService`: wraps `AStarGrid2D`; out-of-bounds start/end returns an empty path.
- `Task`: data object for task type, target tile, approach tile, status, and claimant.
- `TaskBoard`: creates, claims, completes, cancels, counts, and deduplicates tasks.
- `UtilityScorer`: scores open tasks for villagers.
- `VillagerAgent`: simulation-only villager state, task selection, and tile-by-tile movement.
- `VillageSimulation`: main simulation orchestrator.
- `SimulationMonitor`: development-time invariant checker.
- `SaveManager`: saves and loads JSON state, including recovery for invalid villager positions.
- `DebugOverlay`: F3 panel with simulation and monitor information.

## World
- Map size: 40x27 tiles.
- Tile size: 36 pixels.
- Map pixel size: 1440x972.
- Window viewport: 1440x1032, large enough for the map plus HUD and debug panel.
- Hut position: `(4, 5)`.
- Campfire position: `(6, 6)`.
- Walkable tiles: grass, hut, campfire, house.
- Unwalkable tiles: trees, berry bushes, blocked tiles, build sites.
- Build sites become walkable only after construction converts them to houses.

## Balance Defaults
- Starting wood: 10.
- Starting food: 8.
- Starting villagers: 3.
- Days to win: 7.
- Wood per tree: 3.
- Food per bush: 2.
- Food consumed per villager per night: 1.
- Wood consumed by campfire per night: 2.
- Day duration: 10 seconds.
- Night duration: 5 seconds.
- Villager move interval: 0.5 seconds per path step.
- Starting population capacity: 3.
- House wood cost: 8.
- Capacity gained per house: 2.
- Food required for new villager: 2.
- Max hunger before loss: 3.

## Task Types
- `gather_food`: target is a berry bush; villager stands on a walkable adjacent `approach_tile`.
- `chop_tree`: target is a tree; villager stands on a walkable adjacent `approach_tile`.
- `refuel_campfire`: target and approach tile are the campfire.
- `return_home`: target and approach tile are the hut.
- `build_house`: target is a build site; villager stands on a walkable adjacent `approach_tile`.

## Simulation Monitor
The monitor is for development/debugging only. It reports anomalies but does not mutate state or cause win/loss.

It checks:
- Villager positions are in bounds.
- Villagers stand on walkable tiles.
- Villager paths contain only in-bounds, walkable tiles.
- Task targets and approach tiles are in bounds.
- Claimed tasks point to an existing villager.
- Resource stock is not negative.
- Population does not exceed population capacity.

`VillageSimulation` emits `monitor_anomalies_changed(anomalies)` when monitor output changes.
Each anomaly is a dictionary with `code`, `severity`, and `message`.
The F3 overlay shows `Monitor: OK` or the highest-priority anomalies.

## Save/Load Notes
- Save path: `user://save.json`.
- Saves include day, phase, tick, resources, campfire state, hunger count, population capacity, villagers, tasks, and houses.
- Loading a save resets any villager whose saved position is out of bounds or unwalkable to a valid spawn tile near the hut.
- Loading also reapplies build site and house walkability to pathfinding.
- After load, `VillageSimulation.run_monitor_check()` runs.

## Development Rules
- Keep the MVP small.
- No external AI frameworks.
- No ECS.
- No GOAP.
- Keep simulation rules separate from rendering.
- Prefer deterministic behavior.
- Every simulation rule needs a test.
- Do not change unrelated files.
- Update `docs/simulation_rules.md` when a rule changes.
