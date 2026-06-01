# Simulation Rules

Authoritative current behavior. If code and this doc disagree, **the code
wins** — but the doc is wrong and must be updated. Codex / Claude / future
contributors will build on these rules; do not let them drift.

For higher-level project framing and the multi-phase outline, see
`ROADMAP.md`. For the architectural separations and signal flow, see
`CLAUDE.md`.

## Resources

- Strategic MVP resources now exist in `ResourceStore`: `population`, `food`,
  `wood`, `security`, and `morale`. Default strategic start is population 5,
  food 40, wood 25, security 50, morale 60.
- Resource values clamp at zero on direct set/add/consume paths.
- `food` is the authoritative food total. `fresh_food` and `stored_food` are
  compatibility buckets for spoilage, logs, and save/load; their sum is kept
  equal to `food` by `ResourceStore`.
- The default preset starts with `fresh_food = 4`; `stored_food` is reconciled
  from the authoritative starting `food` total.
- `wildlife_food` no longer exists — deer are full `WildlifeAgent` entities
  with positions, not an integer counter.

## Strategic Run State

- One MVP run lasts 60 days. `days_per_season = 15`, and the win day is
  `days_per_season * 4`.
- Seasons derive only from day number:
  - Spring: days 1-15
  - Summer: days 16-30
  - Autumn: days 31-45
  - Winter: days 46-60
- Win: after resolving day 60, the next day transition emits `game_won`.
- Loss: `population <= 0` emits `game_lost`.
- Default preset starts with 5 strategic population, 5 living villagers on the
  map, and `starting_population_capacity = 5`.
- Loss streak counters track `food`, `morale`, and `security` separately.
  If any stays at 0 for 3 consecutive daily strategic resolutions, the run
  is lost. A resource rising above 0 resets only its own streak.
- Villager agents now expose MVP status values: `healthy`, `tired`,
  `injured`, `sick`, and `dead`. New villagers start `healthy`.
- `injured`, `sick`, and `dead` villagers cannot claim, receive, execute, or
  contribute work. `tired` villagers can work at reduced strategic output.
- `dead` villagers remain in the villager list.
- When population growth is enabled, births increase both the living villager
  list and strategic `population`, so the default simulation no longer treats
  visible/strategic population mismatch as normal.

## Policies And Jobs

- Phase 2 policy/job bridge is now partially implemented. The active policy
  defaults to `food_first`.
- Policy changes are accepted only on days 1, 8, 15, 22, 29, 36, 43, 50,
  and 57. Invalid policy ids are rejected, and non-boundary attempts keep the
  previous policy.
- Implemented policies:
  - `food_first`: boosts food output and food task scores.
  - `wood_first`: boosts wood output and chop-tree task scores.
  - `defense_first`: boosts security output and guard / defense task scores.
  - `rest_first`: boosts recovery output and tend-villager task scores.
  - `explore_forest`: boosts hunter / forest food and wood output.
- Visible villagers receive deterministic MVP jobs in this order, repeating:
  farmer, hunter, woodcutter, guard, herbalist.
- Job effects currently apply to strategic daily output and task scoring:
  - Farmer: produces food and prefers `gather_food`.
  - Hunter: produces food, prefers `hunt_deer`, and can become injured from a
    deterministic daily risk roll.
  - Woodcutter: produces wood and prefers `chop_tree`.
  - Guard: produces security and prefers guard / defense tasks.
  - Herbalist: can recover one injured or sick villager with a deterministic
    daily roll.
- Each day start resolves the Phase 2 strategic bridge before loss-streak
  checks: apply visible-villager job output modified by status and policy.
  Food is consumed by the nightly per-villager hunger pass, not by a second
  abstract daily drain.
- The daily bridge uses deterministic hash rolls based on `world_seed`, day,
  villager id, and roll tag. It does not use global random state.
- Resource tasks now also update the matching strategic resource:
  `gather_food` and `hunt_deer` add strategic `food`, and `chop_tree` adds
  strategic `wood`.
- Successful daily food jobs add their full food output to `stored_food`, which
  also increases authoritative `food`. Map harvesting and hunting add
  `fresh_food`, which also increases authoritative `food`.
- This bridge is still a migration layer: fresh/stored buckets remain active
  for spoilage flavor and backwards-compatible saves, but they no longer form a
  second food economy.

## World

- Default 60×40 grid (v3.1; was 40×27 in v3.0). Generation is
  deterministic from `world_seed`.
- Default `HUT_POS = (15, 18)`, `CAMPFIRE_POS = (17, 19)`. All four —
  `world_width`, `world_height`, `hut_pos_x/y`, `campfire_pos_x/y` —
  are balance keys. `WorldGenerator` exposes them as static vars set
  at the start of `generate_from_balance`, so `WorldGenerator.WIDTH`
  / `HUT_POS` call sites keep working.
- Tile types: `GRASS`, `TREE`, `BERRY_BUSH`, `HUT`, `CAMPFIRE`, `BLOCKED`,
  `BUILD_SITE`, `HOUSE`, `FENCE`, `WATCHTOWER`, `STORAGE`.
- Walkable: GRASS, HUT, CAMPFIRE, HOUSE, FENCE, WATCHTOWER, STORAGE.
- Non-walkable: TREE, BERRY_BUSH, BLOCKED, BUILD_SITE.
- `WorldGenerator._tile_index` is the source of truth for
  `get_tiles_of_type` / `count_tiles_of_type`. **Every grid mutation goes
  through `set_tile`** so the index stays consistent.
- Generation order: place resources → place HUT / CAMPFIRE / build_sites
  → `_repair_resource_access()` → `_ensure_reachable_resources()`. Build
  sites are placed BEFORE reachability so the check sees the real
  topology.

## Time

- `GameTime` advances DAY ⇄ NIGHT on a timer. Durations from balance:
  `day_duration_seconds`, `night_duration_seconds`.
- Initial DAY phase emits no `day_started` signal (subsequent days do).
- Win: after day 60 resolves and `day` advances to 61, `VillageSimulation`
  emits `game_won`.

## Tasks

Task types currently in the simulation (in priority order under default
balance):

- `build_house`, `build_watchtower`, `build_fence`, `build_storage`:
  created by `ConstructionPlanner` at day_start. Scored as flat bonuses
  (25 / 20 / 15 / 12) minus distance × 0.5.
- `gather_food`: created per nearby BERRY_BUSH when
  `food < food_low_threshold`, capped by
  `max_open_resource_tasks_per_type` active gather tasks.
- `chop_tree`: created per nearby TREE when `wood < wood_low_threshold`,
  capped by `max_open_resource_tasks_per_type` active chop tasks.
- `hunt_deer`: created when `food < food_surplus_threshold` and a deer is
  within `deer_hunt_radius` of HUT (default preset: 40). Existing OPEN hunt
  tasks are cancelled only when their target deer is no longer at that tile,
  the deer has moved outside the hunt radius, the approach tile becomes
  invalid, or food reaches `food_surplus_threshold`. CLAIMED hunters finish
  their current run; if the deer is gone when they arrive, the hunt resolves
  as `deer_escaped`.
- `guard_watch`: created by `defense_first` while security is below 60.
  Completed guard work adds strategic security.
- `tend_villager`: created by `rest_first` when any villager is injured or
  sick. Completed herbalist work can recover one villager and add morale.

**No more `return_home` or `refuel_campfire` tasks.** Those were
placeholders removed in the Phase C cleanup. Codex / Claude must NOT
re-introduce them — they're listed in ROADMAP.md's anti-features by
implication (no second-tier scheduling).

### Asymmetric thresholds

- Create gather_food when `food < food_low_threshold` (default 6).
- Cancel open gather_food when `food >= food_surplus_threshold` (default 20).
- Same pattern for chop_tree with `wood_low/surplus_threshold`.
- The gap between low and surplus lets idle villagers consume existing
  OPEN tasks instead of going idle the moment stock crosses the floor.
- Resource task generation considers nearest resources first and keeps at most
  `max_open_resource_tasks_per_type` active tasks per resource type (default
  12) so the board does not flood with the entire map's trees/bushes.

### Task lifecycle

- `Task.Status`: OPEN → CLAIMED → COMPLETED | CANCELLED.
- `board.clear_stale()` runs at every day_start to purge
  COMPLETED/CANCELLED entries so the list stays bounded.
- Bulk cancellations (`_cancel_open_tasks_of_type`) emit one
  `task_cancelled` log event per affected task, with the reason field
  (`stale_at_day_start`, `food_above_surplus_threshold`, etc.).

## Villager AI

- Two-state machine: `IDLE` / `MOVING_TO_TARGET`. No third state allowed.
- `pick_best_task` scans all OPEN tasks via `UtilityScorer.score_task`,
  takes the highest. Pure function, no oscillation prevention needed
  because no priority loops exist.
- Distance penalty in scoring uses `task.approach_tile`, not
  `target_tile`. For non-walkable targets the approach tile is where the
  villager actually goes.
- `pick_best_task` returns null when there are no open tasks, or when every
  available task has a negative score — villager stays IDLE that tick.
  Zero-score tasks remain claimable.
- `clear_task()` resets `state`, `current_task_id`, `_path`, and
  `_move_timer` — no transient state leaks across tasks.

## Wildlife

`NatureSystem` owns `animals: Array[WildlifeAgent]` plus regrowth.

### Deer

- Spawn near BERRY_BUSHes after day 1 (`deer_spawn_per_day` per eligible
  day, capped by `deer_max_count`).
- Move 1 random walkable neighbor per day_start.
- Hunted via `hunt_deer` task; gives `food_per_deer` food (default preset:
  3 before job/status/policy modifiers).
- Despawn: deer have no max age (only wolves do).

### Wolves

- Spawn in TREE clusters at distance ≥ 10 from HUT, starting from
  `wolf_spawn_day`, every `wolf_spawn_interval_days` days, capped at
  `wolf_max_count`.
- Move toward HUT one tile per day_start, via `PathfindingService` if
  available (falls back to cardinal-step if pathfinding is null —
  e.g. tests). They route around BLOCKED tiles.
- Despawn after `wolf_max_age_days` days.

### Wolf threat

- `nature.check_wolf_threat(campfire_out_nights)` returns true when
  `campfire_out_nights > 0` AND any wolf is within `wolf_threat_radius`.
- Checked once at night_started, after `resolve_night`.
- Triggers `_apply_wolf_disruption`: picks one villager (RNG diversified
  by day + threat_count + village size), applies
  `wolf_hunger_disruption` hunger after mitigation, increments
  `_wolf_threat_count`.
- **Starvation re-checked after wolf damage** so a wolf-pushed overflow can
  kill that villager immediately. The run is only lost if that death reduces
  strategic population to 0 (or other existing loss streak rules later fire).

### Regrowth

- Records harvested TREE / BERRY_BUSH tiles. Trees regrow after
  `nature_tree_regrowth_days`, bushes after
  `nature_berry_regrowth_days`.
- Regrowth respects `nature_max_trees` / `nature_max_berry_bushes` caps
  and skips tiles currently occupied by a villager or as a task's
  approach tile.
- Regrown tiles update pathfinding to non-walkable.

## Buildings

Four buildings, data-driven via `BuildingDefs.BUILDINGS`:

| Building | Cost | Priority | Trigger (in `ConstructionPlanner._condition_met`) | Effect |
|---|---|---|---|---|
| House | 8 wood | 1 | `population_growth_enabled` AND villagers >= capacity | `population_capacity += population_capacity_per_house` |
| Watchtower | 6 wood | 2 | `day >= 4` AND not yet built | Halves wolf damage before fence mitigation |
| Fence | 2 wood | 3 | wolves present AND `_wolf_threat_count > 0` AND `_fence_count < 8` | Each fence multiplies remaining wolf damage by `1 - fence_wolf_damage_reduction` |
| Storage | 4 wood | 4 | food near or above current cap | Increases food spoilage cap by `food_capacity_per_storage` |

- One building planned per day_start (`ConstructionPlanner.plan` returns
  one decision at most). Wood budget is checked first; building is skipped
  if unaffordable.
- `_apply_food_spoilage` runs at night: food above
  `food_base_capacity + storage_count * food_capacity_per_storage` spoils
  by `(excess) / food_spoilage_divisor` per night (rounded up).

## Night resolution

In `_on_night_started`:

1. `_resolve_hunger`: each villager eats
   `food_consumed_per_villager_per_night` from authoritative `food`, drawing
   fresh food before stored food. If fed, hunger -= 1 (clamped 0); else hunger
   += 1. If a villager's hunger reaches `max_hunger`, that villager is marked
   `dead`, released from work, and strategic `population` decreases by 1.
2. Campfire wood consumption: `wood_consumed_by_campfire_per_night`.
   If shortfall, `campfire_out_nights += 1`. If `campfire_out_nights >=
   max_campfire_out_nights` (default preset: 3), emit `game_lost("Campfire out for N
   consecutive nights")`.
3. `_apply_food_spoilage` against storage capacity.
4. `nature.check_wolf_threat` → if true, `_apply_wolf_disruption`
   (which re-checks starvation after damage and may kill one villager).

## Difficulty presets

- `data/balance.json` is the default preset.
- `data/balance_hard.json` is the hard preset.
- Selected via headless runner CLI: `-- preset=hard`. UI play always
  uses default.
- Hard preset adjusts keys to force wolf threat and scarcity paths to fire
  during the 60-day run; it is allowed to lose.

## Save / load

- `SaveManager.save()` writes the full current grid as `tiles`, plus
  legacy food fields, grouped strategic resources, active policy,
  zero-resource streaks, day/phase, villager positions + hunger + names +
  job + status, and
  `_wolf_threat_count`. **No tasks, no buildings list, no derived
  building counters** — all reconstructed from the grid.
- `load_into()`:
  - Sets legacy resources via `store.setup()` and strategic resources via
    `store.setup_strategic()`; both emit `stock_changed` so HUD refreshes.
  - Restores `zero_food_days`, `zero_morale_days`, and
    `zero_security_days`.
  - Restores active policy.
  - Restores grid via `world_gen.set_tile()` for each cell.
  - Recomputes `_fence_count` / `_watchtower_count` / `_storage_count`
    from tile counts.
  - Drops the task board (`sim.board = TaskBoard.new()`); tasks
    regenerate next tick.
  - Resets every villager to IDLE with empty path; keeps position +
    hunger + name + id + job + status.
  - Rebuilds pathfinding from scratch (`pf.setup(wg)`).
  - Emits `tile_changed` for every cell so renderers redraw.
- No schema version field. Format is still mutating; pre-Phase-B saves
  will load with the legacy field set ignored (graceful but resources may
  drift — re-save immediately after load to migrate).

## Monitor

`SimulationMonitor.check(sim)` returns `Array[Dictionary]` of anomalies
with `code`, `severity`, `message`. Runs after state-change events
(night resolution, day start, build, regrowth, save load) immediately
and via per-frame throttling (every 5 frames) during `_tick_villagers`.
Anomalies it currently reports:

- `villager_out_of_bounds`, `villager_on_unwalkable_tile`,
  `path_out_of_bounds`, `path_on_unwalkable_tile`
- `villager_idle_with_task`, `villager_task_missing_task`,
  `villager_task_not_claimed`, `villager_task_claim_mismatch`,
  `moving_villager_without_path`
- `task_target_out_of_bounds`, `task_approach_out_of_bounds`,
  `task_approach_unwalkable`
- `claimed_task_missing_villager`, `claimed_task_unassigned`
- `negative_resource`, `population_over_capacity`
- `food_survival_risk`, `wood_survival_risk` (only when no reachable
  alternative exists)
- `task_backlog_high` (active task count > `monitor_task_backlog_warning`)

## Action log (JSONL)

`ActionLogger` writes one JSON object per line to
`user://run_<timestamp>.jsonl` in headless runs. Used for post-run audits.
Events include: `task_claimed`, `task_completed`, `task_cancelled` (with
reason), `built`, `construction_planned`, `wolf_threat`,
`wolf_threat_mitigated`, `night_hunger`, `campfire_ok`/`campfire_out`,
`food_spoiled`, `regrowth`, `deer_spawned`, `wolf_spawned`,
`wolf_despawned`, `run_summary`. The logger is never above 50 lines —
do not grow it.

## Headless Balance Audit

Run `tools/headless_audit.ps1` after balance or simulation-rule changes. It
executes the deterministic headless runner, parses the raw Godot log plus JSONL
action log, and emits `.godot/headless_audit/<run>/audit_report.json` with
result, resource ranges, negative task claims, cancellation bursts, death
counts/rates, population mismatch, and gate results. Default preset audits also
run a fixed 10-seed sweep (`4312..4321`) and gate on both win count and
winning average death rate. `HeadlessRunner` accepts `seed=<int>` on the CLI
for single-seed reproduction. See `docs/headless_balance_pipeline.md` for the
repeatable tuning loop.

## Debug snapshot

- F3 in live play opens DebugOverlay (read-only view of monitor +
  per-villager state).
- Left click selects a tile for a read-only inspector panel showing terrain,
  occupants, wildlife, and task relations. Clicking HUD panels does not select
  world tiles, and clicking outside the map clears selection.
- HUD shows day/phase, wood, food, population with dead count, security,
  morale, nature counts, task counts, monitor status, and the tile inspector.
- Both HUD and DebugOverlay are pure signal-driven — no per-frame
  polling of simulation state.
