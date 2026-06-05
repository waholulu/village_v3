# Project Overview

One-page reference for Tiny Campfire Village. For the strategic direction
(phases, anti-features, guardrails) see `ROADMAP.md`. For exact runtime
behavior see `docs/simulation_rules.md`. For architecture / signal flow
see `CLAUDE.md`. For repeatable headless tuning, see
`docs/headless_balance_pipeline.md`.

## Goal

A small, observable, deterministic Godot 4 village survival MVP:

- Strategic village state starts with population 5, food 50, wood 25,
  security 50, and morale 60.
- 5 visible villagers remain autonomous as the execution layer for the
  policy/event MVP, matching strategic population at default start.
- Survive through day 60 to win. The win signal fires after the day 60
  resolution, on day 61.
- Lose when strategic population reaches 0, or when food, morale, or
  security stays at 0 for 3 consecutive daily resolutions.
- Legacy hunger, campfire, wildlife, and construction systems still run
  during the migration and remain covered by their existing tests.

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
& "E:\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "E:\godot\tiny-campfire-village" -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# Default headless smoke
& "E:\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "E:\godot\tiny-campfire-village" -s res://scripts/core/headless_runner.gd

# Hard preset headless
& "E:\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "E:\godot\tiny-campfire-village" -s res://scripts/core/headless_runner.gd -- preset=hard

# Repeatable default balance audit with gates
.\tools\headless_audit.ps1 -Strict

# Hard preset audit report (hard is allowed to lose)
.\tools\headless_audit.ps1 -Preset hard

# Live play
& "E:\godot\Godot_v4.6.3-stable_win64.exe" --path "E:\godot\tiny-campfire-village"
```

After adding any new `.gd` with a `class_name`, run `--import` first.

## Test And Audit Status

Latest run: **292 GUT tests, all passing**. Default strict headless audit
passes with a day 61 win, 0 monitor anomalies, `14/20` sweep wins,
`6/20` sweep losses, winning average death rate `0.3857`, all 25 event cards
covered, and 0 negative resource/streak findings. Every simulation rule
change must land with a focused test and a strict audit pass — see Phase A/B/C/D regression tests
(`tests/test_phase_*_*.gd`) as templates.

## Controls (live play)

- F3 — toggle debug overlay
- F5 — save to `user://save.json`
- F9 — load from `user://save.json` (resets in-flight tasks; villagers
  return to IDLE; resource HUD refreshes via signal)
- WASD / arrow keys — pan the map camera
- Right mouse drag or middle mouse drag — pan the map camera
- Left mouse click — inspect a map tile
- HUD speed buttons or number keys 1/2/3 — set simulation speed to 1x/2x/4x

## Directory map

- `data/` — balance JSON (default + presets)
- `docs/` — this file, `simulation_rules.md`,
  `headless_balance_pipeline.md`, `ROADMAP.md`, `DEVELOPMENT_PLAN.md`
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
| `ResourceStore` | Strategic resources plus legacy fresh/stored food with `stock_changed` signal |
| `WorldGenerator` | Deterministic 60×40 grid + `_tile_index` cache + reachability guarantees |
| `PathfindingService` | `AStarGrid2D` wrapper |
| `Task` / `TaskBoard` | Task data + status transitions + `clear_stale()` |
| `UtilityScorer` | Pure function — `score_task(v, t, store, _gt) -> float` |
| `VillagerAgent` | Two-state movement plus coarse MVP status/work eligibility |
| `WildlifeAgent` | Deer / wolf entity |
| `NatureSystem` | Wildlife + regrowth + wolf threat check |
| `BuildingDefs` | Data table for 4 building types |
| `ConstructionPlanner` | One-decision-per-day site picker |
| `VillageSimulation` | Orchestrator + signal source |
| `SimulationMonitor` | Anomaly checker (no state mutation) |
| `ActionLogger` | JSONL writer for headless audits |
| `SaveManager` | Full-grid snapshot, strategic resources, zero streaks, villager status, idle reset on load |

## Balance highlights (default preset)

| Key | Value |
|---|---|
| starting_population / starting_food | 5 / 50 |
| starting_wood / starting_security / starting_morale | 25 / 50 / 60 |
| visible villagers / strategic run length | 5 / 60 days |
| wood_per_tree / food_per_bush | 4 / 3 |
| food / wood low_threshold | 6 / 6 |
| food / wood surplus_threshold | 20 / 12 |
| policy_food_task_target / policy_wood_task_target | 60 / 31 |
| hunter_injury_chance / herbalist_recovery_chance | 25% / 30% |
| max_campfire_out_nights | 5 |
| max_hunger | 3 |
| wolf_threat_radius | 10 |

Full schema in `scripts/core/balance_data.gd`.

## What's deliberately NOT here

- No personal need systems beyond legacy hunger; villager status is a
  coarse MVP health/work-eligibility flag, not a mood or schedule model.
- No routines / schedules / shifts.
- No skills / XP / tools-with-durability.
- No combat system; wolf attacks still use the legacy survival track.
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
- Headless strict audit + tests must stay green between commits when default
  balance or simulation rules change.
- When updating any sim rule, also update `simulation_rules.md` in the
  same commit. Codex / Claude trust that doc.
