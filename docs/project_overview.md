# Project Overview

One-page reference for Tiny Campfire Village. For the strategic direction
(phases, anti-features, guardrails) see `ROADMAP.md`. For exact runtime
behavior see `docs/simulation_rules.md`. For architecture / signal flow
see `CLAUDE.md`.

## Goal

A small, observable, deterministic Godot 4 village simulation:

- 3 villagers, autonomous, no direct player control.
- Survive past day 7 to win.
- Lose when any villager reaches `max_hunger` (default 3) **or** when
  campfire stays out for `max_campfire_out_nights` consecutive nights
  (default 2).
- A `hard` balance preset exercises wolf threats; the default preset
  produces a comfortable run.

## Tech stack

- Engine: Godot 4.6
- Language: GDScript (warnings-as-errors typing convention)
- Rendering: `TileMapLayer` + per-entity `Sprite2D`
- Pathfinding: `AStarGrid2D` wrapped by `PathfindingService`
- Tests: GUT 9.6
- Save: JSON at `user://save.json`
- Balance: JSON at `data/balance.json` (default) and
  `data/balance_hard.json` (hard preset)

## Run commands

The exact commands live in `CLAUDE.md`. Common ones:

```powershell
# Tests
& "E:\godot\Godot_v4.6.3-stable_win64.exe" --headless --path "E:\godot\tiny-campfire-village" -s res://addons/gut/gut_cmdln.gd -- -gdir=res://tests -ginclude_subdirs -gexit

# Default headless smoke (~7s real time)
& "E:\godot\Godot_v4.6.3-stable_win64.exe" --headless --path "E:\godot\tiny-campfire-village" -s res://scripts/core/headless_runner.gd

# Hard preset headless
& "E:\godot\Godot_v4.6.3-stable_win64.exe" --headless --path "E:\godot\tiny-campfire-village" -s res://scripts/core/headless_runner.gd -- preset=hard

# Live play
& "E:\godot\Godot_v4.6.3-stable_win64.exe" --path "E:\godot\tiny-campfire-village"
```

After adding any new `.gd` with a `class_name`, run `--import` first.

## Test status

Latest run: **188 GUT tests, all passing**. Default headless completes
day 8 win with 0 monitor anomalies. Every simulation rule change must
land with a focused test — see Phase A/B/C/D regression tests
(`tests/test_phase_*_*.gd`) as templates.

## Controls (live play)

- F3 — toggle debug overlay
- F5 — save to `user://save.json`
- F9 — load from `user://save.json` (resets in-flight tasks; villagers
  return to IDLE; resource HUD refreshes via signal)

## Directory map

- `data/` — balance JSON (default + presets)
- `docs/` — this file, `simulation_rules.md`, `ROADMAP.md`,
  `DEVELOPMENT_PLAN.md`
- `scenes/` — `main`, `ui`, `world`
- `scripts/core/` — balance, time, resources, save/load, headless
  runner, action logger, global events
- `scripts/world/` — world generation, pathfinding, tile rendering,
  villager / wildlife sprite layers
- `scripts/sim/` — task board, villager AI, utility scorer,
  construction planner, building defs, nature system, simulation
  orchestrator, monitor
- `scripts/ui/` — HUD, debug overlay
- `tests/` — GUT tests

## High-level architecture

Simulation is fully separated from rendering:

1. `main.gd` wires `BalanceData`, `WorldGenerator`,
   `PathfindingService`, and `VillageSimulation` together.
2. `VillageSimulation` owns mutable state (resources, time, tasks,
   villagers, buildings, wildlife reference, monitor).
3. Renderers (`TileMapController`, `VillagerView`, `WildlifeView`, HUD,
   DebugOverlay) **only read** simulation state via signals and getters.
4. `Events` autoload carries UI-facing signals
   (`stock_changed`, `day_started`, `night_started`, `game_won`,
   `game_lost`). All other signals are direct sim → listener.

`CLAUDE.md` is the authoritative source for mutation order (set_tile →
set_point_walkable → tile_changed.emit → store.add_resource) and the
`approach_tile` vs `target_tile` distinction.

## Important classes

| Class | Responsibility |
|---|---|
| `BalanceData` | Reflectively loads tunable values; warns on unknown keys |
| `GameTime` | Day/night phase + signals |
| `ResourceStore` | wood/food with `stock_changed` signal |
| `WorldGenerator` | Deterministic 40×27 grid + `_tile_index` cache + reachability guarantees |
| `PathfindingService` | `AStarGrid2D` wrapper |
| `Task` / `TaskBoard` | Task data + status transitions + `clear_stale()` |
| `UtilityScorer` | Pure function — `score_task(v, t, store, _gt) -> float` |
| `VillagerAgent` | Two-state machine (IDLE / MOVING_TO_TARGET) |
| `WildlifeAgent` | Deer / wolf entity |
| `NatureSystem` | Wildlife + regrowth + wolf threat check |
| `BuildingDefs` | Data table for 4 building types |
| `ConstructionPlanner` | One-decision-per-day site picker |
| `VillageSimulation` | Orchestrator + signal source |
| `SimulationMonitor` | Anomaly checker (no state mutation) |
| `ActionLogger` | JSONL writer for headless audits |
| `SaveManager` | Full-grid snapshot + idle reset on load |

## Balance highlights (default preset)

| Key | Value |
|---|---|
| starting_wood / starting_food | 10 / 8 |
| villager_count / days_to_win | 3 / 7 |
| wood_per_tree / food_per_bush | 3 / 2 |
| food / wood low_threshold | 6 / 6 |
| food / wood surplus_threshold | 12 / 12 |
| max_campfire_out_nights | 2 |
| max_hunger | 3 |
| wolf_threat_radius | 8 |

Full schema in `scripts/core/balance_data.gd`.

## What's deliberately NOT here

- No needs beyond hunger (no mood, tiredness, cold).
- No routines / schedules / shifts.
- No skills / XP / tools-with-durability.
- No combat system; wolf attacks reuse the hunger track.
- No mod loader, scripting API, multi-map, or save-format versioning.

These are listed exhaustively in `ROADMAP.md`'s anti-features section and
are binding.

## Development rules

- Every new simulation rule ships with a GUT test.
- Per-file cap: 600 lines. `village_simulation.gd` currently ~600;
  splitting is the next refactor when crossed.
- `task` types capped at 10 (currently 7).
- No state lock primitives. If thrashing requires a lock, the priority
  graph is wrong.
- Balance is the only knob for behavior tuning — no magic numbers in
  `.gd`.
- Headless run + tests must stay green between commits.
- When updating any sim rule, also update `simulation_rules.md` in the
  same commit. Codex / Claude trust that doc.
