# Development Plan - Hybrid Event Roguelike MVP

This document is the tactical plan for the current work cycle. For strategic
guardrails and anti-features, see `ROADMAP.md`. For exact current runtime
behavior, keep using `simulation_rules.md`; that file should be updated only
as implementation phases land. For repeatable balance/headless checks, use
`docs/headless_balance_pipeline.md` and `tools/headless_audit.ps1`.

The product direction is:

> Village survival pressure + event choices + automatic resolution roguelike,
> using the existing map, pathfinding, and villager AI as a light execution
> layer.

The player is the village elder. The player does not directly control
villagers. The player chooses one weekly policy, handles event choices, watches
villagers carry out simple work on the map, and tries to get the village
through the first winter.

The correction from the previous plan is important: do not throw away working
map/pathfinding/AI code. Keep it, but cap what it is allowed to become.

Current tuning workflow: run `.\tools\headless_audit.ps1 -Strict` after any
default balance or simulation-rule change. The audit must keep the default
preset winning on day 61, monitor anomalies at 0, negative task claims near
zero, and cancellation bursts bounded. Hard preset audits are useful reports
but hard is allowed to lose.

One implementation principle matters more than the exact class names below:
do not build a second simulation beside the current one. Prefer adapting
`VillageSimulation`, `ResourceStore`, `GameTime`, `TaskBoard`, and
`SimulationSnapshot` before adding new state holders. New RefCounted helpers
are fine when they remove complexity from the orchestrator; parallel game
state is not.

---

## MVP Contract

### Run length

- One run lasts 60 days.
- Seasons are fixed at 15 days each:
  - Spring: days 1-15
  - Summer: days 16-30
  - Autumn: days 31-45
  - Winter: days 46-60
- Win: finish day 60 with no loss condition active.

### Loss conditions

The game is lost when any of these become true:

- `population <= 0`
- `food == 0` for 3 consecutive daily resolutions
- `morale == 0` for 3 consecutive daily resolutions
- `security == 0` for 3 consecutive daily resolutions

All streak counters reset immediately when the tracked resource rises above
zero.

### Strategic resources

The MVP has exactly 5 player-facing resources:

| Resource | Role |
|---|---|
| `population` | Number of living villagers. |
| `food` | Daily survival pressure. |
| `wood` | Project, defense, and winter pressure. |
| `security` | Protection against outside threats. |
| `morale` | Internal stability and survival pressure. |

Do not add gold, tools, herbs, stone, knowledge, faith, noble relations, trade
relations, or inventory items in the MVP.

Implementation detail: existing code may temporarily still have lower-level
state such as hunger or fresh/stored food during migration. The final MVP UI
and rules should present the five resources above unless a later design
decision explicitly replaces one.

Do not keep two authoritative resource stores. During migration, either adapt
`ResourceStore` to expose the five strategic resources or provide a thin
projection from legacy values. The player-facing values must have one source
of truth by the end of the phase that introduces them.

### Villagers

Villagers remain lightweight agents on the map, but their gameplay identity is
only 4 fields:

| Field | Example |
|---|---|
| `name` | Mira |
| `job` | Farmer |
| `status` | Healthy |
| `trait` | Hardworking |

Allowed statuses:

- `healthy`
- `tired`
- `injured`
- `sick`
- `dead`

Allowed implementation-only state:

- stable id
- map position
- current path
- current task id
- movement timer

Do not add mood values, personal hunger values, family links, marriage, birth,
aging, skill trees, or relationship networks. If existing hunger remains while
migrating, treat it as legacy survival plumbing, not a design surface to grow.

Migration rule: the current MVP target is 5 visible villager agents matching
the strategic `population` default. Population, visible living villagers, and
death tracking should stay in sync; the old 10/3 mismatch is no longer an
accepted migration state.

### Jobs

The MVP has exactly 5 jobs:

| Job | Primary effect |
|---|---|
| Farmer | Stable food production. |
| Hunter | Food production with injury risk. |
| Woodcutter | Wood production. |
| Guard | Security production. |
| Herbalist | Heals injured or sick villagers. |

Do not add blacksmiths, priests, merchants, miners, cooks, teachers, or other
jobs in the MVP.

### Retained spatial layer

Keep the existing map, pathfinding, and villager movement, with these limits:

- One village map only.
- No player building placement sandbox.
- No pathfinding puzzles as gameplay.
- No multiple maps or world travel.
- No per-villager schedules.
- No second AI layer beyond task scoring and movement.
- No combat movement system.
- No resource inventory by tile or container.

The map should make the automatic work readable: villagers walk to simple work
targets, gather, chop, hunt, repair, guard, or rest. It should not become the
main strategy layer.

### Tasks and AI

The existing task board and villager AI can stay, but must be constrained:

- Tasks are generated from policy, events, survival pressure, or simple
  projects.
- Task types stay capped at 10.
- Scoring stays one-layer and deterministic.
- Villagers keep the two-state movement model unless there is a very strong
  reason to change it.
- No need locks, anti-oscillation cooldowns, routines, shifts, or GOAP-style
  planning.
- If a proposed rule requires special-case AI suppression, redesign the rule.

The AI is an execution detail for the elder's decisions, not the main game.

### Weekly policies

The player chooses exactly one policy per week. No sliders, percentages, or
per-villager orders.

| Policy | Intended pressure |
|---|---|
| Food First | More food from farmers and hunters; small security and morale cost. |
| Wood First | More wood from woodcutters; lower food and morale. |
| Defense First | More security from guards; consumes wood; small morale gain. |
| Rest First | More morale and recovery; lower food and wood output. |
| Explore Forest | Chance for food, wood, or new villagers; risk events; security cost. |

Policies may affect:

- task generation weights
- task output
- task risk
- daily resource modifiers
- event weights

Policies may not create new subsystems.

### Daily resolution

Each day uses the existing visual simulation where useful, but the strategic
order stays fixed:

1. Consume food.
2. Generate or weight work from the current policy.
3. Let villagers execute simple tasks on the map.
4. Convert completed work into resource changes.
5. Resolve recovery for injured or sick villagers.
6. Roll for at most one event.
7. Apply short-term effects.
8. Update logs, streak counters, season, win, and loss state.

Use the existing day/night clock as the cadence. Do not add a separate weekly
or daily scheduler on top of it. A reasonable migration shape is: day start
creates policy-weighted tasks, villagers act during the day, night resolution
turns completed work and unresolved pressure into the daily summary.

The player-facing result is a daily summary, for example:

```text
Day 12, Summer
Food +6
Wood +3
Security -1
Morale +1
Event: Hunters found wolf tracks near the forest edge.
```

Do not require the player to inspect paths, task queues, or individual work
orders to understand why the day resolved the way it did.

### Events

The MVP ships with 25 event cards:

| Category | Count |
|---|---:|
| Weather | 5 |
| Beasts | 5 |
| Disease | 5 |
| Food | 5 |
| Villager conflict | 5 |

Each event card has one uniform shape:

- `id`
- `category`
- `title`
- `description`
- `options` A/B/C
- immediate result per option
- optional single short-term effect

Short-term effects are allowed only when they are easy to display and expire
automatically, for example: "for the next 3 days, food production -2".

Do not add event chains, hidden quest state, or multi-card story arcs in the
MVP.

### Projects

Formal building placement remains out of scope. The existing construction
system can be reused only as simple map-visible projects:

| Project | Cost | Completion effect |
|---|---:|---|
| Repair Fence | 20 wood | Security +15 |
| Expand Granary | 15 wood | Food cap +30, only if caps exist by then. |
| Repair Longhouse | 25 wood | Population cap +5, only if caps exist by then. |

Projects may have a map marker and villager pathing. They are not a building
tree, zoning system, or placement UI.

---

## Migration Strategy

The current codebase already contains useful systems: map generation,
pathfinding, task boards, villager movement, wildlife, construction, save/load,
HUD, debug overlay, and tests.

The migration should preserve useful infrastructure while changing the design
center:

1. Keep map/pathfinding/AI running.
2. Add the strategic 60-day run rules around them.
3. Let policies and events drive task generation and outputs.
4. Remove or hide rules that create simulation depth without improving the
   elder-choice loop.

Do not expand map, pathfinding, building, wildlife, or AI while migrating
unless that change directly supports policies, events, or daily summaries.

---

## Phase 0 - Planning Pivot

Goal: replace the old expansion plan with this hybrid event roguelike plan.

Scope:

- Update `DEVELOPMENT_PLAN.md`.
- Update `ROADMAP.md`.
- Leave `simulation_rules.md` as current runtime documentation until code
  actually changes.
- Do not touch implementation files in this phase.

Done when:

- The roadmap says map, pathfinding, and AI are retained but capped.
- The tactical plan defines the 60-day, 5-resource, 5-job, 5-policy,
  25-event-card scope.
- The current runtime docs have not been rewritten to claim behavior that the
  game does not yet implement.

---

## Phase 1 - Strategic Run State

Goal: create the smallest deterministic 60-day strategic state while keeping
the existing map simulation available.

Expected files / touch points:

- Prefer extending existing `BalanceData`, `GameTime`, `ResourceStore`,
  `VillageSimulation`, and `SimulationSnapshot`.
- Add `scripts/sim/strategic_state.gd` only if it is a small value object or
  snapshot, not a second runtime simulation.
- Add `scripts/sim/villager_record.gd` only if adapting current
  `VillagerAgent` directly would make the agent carry too much strategic data.
- Add `scripts/sim/season_defs.gd` only if `GameTime` would otherwise grow
  awkward enum/string conversion code.
- focused tests under `tests/`

Rules:

- Initial default state:
  - population: 5
  - food: 40
  - wood: 25
  - security: 50
  - morale: 60
  - day: 1 / 60
  - season: Spring
- Seasons derive from day number only.
- Resource values clamp at zero.
- Loss streak counters track food, security, and morale separately.
- Dead villagers remain in the villager list with `status = dead`; they do
  not contribute to work.
- Map position and task state are implementation state, not extra gameplay
  fields.
- Default start uses 5 visible villagers and strategic population 5. Births
  and deaths should keep both counts aligned.

Tests:

- `test_initial_strategic_state_matches_mvp_defaults`
- `test_season_ranges_are_15_days_each`
- `test_win_after_resolving_day_60`
- `test_population_zero_loses_immediately`
- `test_zero_food_loses_after_3_consecutive_days`
- `test_zero_morale_loses_after_3_consecutive_days`
- `test_zero_security_loses_after_3_consecutive_days`
- `test_zero_streak_resets_when_resource_recovers`

Done when:

- The strategic run state passes tests.
- Existing map/pathfinding tests still pass if they are touched.
- `simulation_rules.md` gains a clearly marked section for implemented
  strategic state rules.
- HUD and debug overlay show living population and dead count without treating
  mismatch as a normal migration phase.

---

## Phase 2 - Policy To Task Bridge

Goal: make weekly policies drive the existing task and AI loop without adding
a second AI layer.

Expected files:

- `scripts/sim/policy_defs.gd`
- `scripts/sim/job_defs.gd`
- small changes to current task generation / scorer files
- focused tests under `tests/`

Rules:

- Policy changes are allowed only on days 1, 8, 15, 22, 29, 36, 43, 50,
  and 57.
- If the player has not selected a new policy, the previous policy continues.
- Food consumption happens before work output.
- Healthy villagers contribute full output.
- Tired villagers contribute reduced output.
- Injured, sick, and dead villagers do not work.
- Hunters can produce food but can become injured.
- Herbalists can recover injured or sick villagers.
- All random rolls use a fixed seed passed through the run state.
- Existing pathfinding is used only to reach simple task targets.
- Jobs do not create a second AI system. A villager's job affects task
  eligibility, task score, output, and risk; it does not add a private routine
  or behavior tree.

Tests:

- One test for each policy's core modifier.
- One test for each job's production or recovery rule.
- `test_daily_resolution_consumes_food_before_production`
- `test_policy_only_changes_on_week_boundary`
- `test_policy_changes_task_weights_not_ai_layers`
- `test_tired_villager_has_reduced_output`
- `test_injured_sick_dead_villagers_do_not_work`
- `test_hunter_injury_roll_is_deterministic_with_seed`
- `test_herbalist_recovery_roll_is_deterministic_with_seed`

Done when:

- A 60-day headless run can resolve with the map simulation enabled.
- Villagers visibly execute simple work, but the player can understand results
  from the daily summary.
- All simulation rules added in this phase are documented in
  `simulation_rules.md`.

---

## Phase 3 - Event Cards

Goal: make events the primary source of roguelike variation.

Expected files:

- `data/events.json`
- `scripts/sim/event_deck.gd`
- `scripts/sim/event_effects.gd`
- focused tests under `tests/`

Rules:

- Exactly 25 MVP event cards.
- Event categories are weather, beasts, disease, food, and villager conflict.
- Every event has exactly 2 or 3 player options.
- Every option has an immediate result.
- An option may have at most one short-term effect.
- Short-term effects have explicit duration in days and expire automatically.
- At most one event can trigger per day.
- Event selection is deterministic under the run seed.
- Event effects may modify strategic resources, villager status, task output,
  task risk, or policy/event weights.
- Event effects may not spawn a new AI subsystem.
- Disease events may set `status = sick` or apply a short-term production /
  morale penalty. They may not add contagion, immunity, diagnosis, medicine
  inventory, or a disease simulation.

Tests:

- `test_event_file_contains_25_cards`
- `test_event_categories_have_5_cards_each`
- `test_event_options_have_immediate_results`
- `test_event_option_has_at_most_one_short_term_effect`
- `test_short_term_effect_expires_after_duration`
- `test_at_most_one_event_per_day`
- `test_event_draw_is_deterministic_with_seed`
- One focused test for each event effect type.

Done when:

- The event deck can be loaded from JSON.
- Every event effect has a test.
- Event result text can be included in daily logs.

---

## Phase 4 - Playable UI, Logs, Debug, Save/Load

Goal: expose the hybrid loop in a small playable shell.

Expected files:

- existing HUD and debug overlay files, adjusted only where needed
- `scripts/core/save_manager.gd`, only if save schema changes
- existing world view, villager view, and pathfinding remain available

UI requirements:

- First screen shows current day, season, resources, selected policy, map, and
  daily log.
- Weekly policy choice is visible only when a policy can be changed.
- Event choices are modal or otherwise blocking; the day cannot continue until
  an option is selected.
- Debug overlay shows run seed, active policy, active short-term effects,
  loss streak counters, villager records, active tasks, and pathing anomalies.

Save/load requirements:

- Save includes strategic run state, villagers, policy, active effects,
  pending event, and enough RNG state to keep the next day deterministic.
- Save may include map/task state only if that state cannot be safely
  regenerated.
- Load restores enough state that the next daily resolution is deterministic.
- No schema version is required during MVP migration unless old saves must be
  supported.

Tests:

- `test_save_load_preserves_strategic_state`
- `test_save_load_preserves_villagers`
- `test_save_load_preserves_policy_and_effects`
- `test_loaded_run_resolves_next_day_deterministically`
- Debug overlay smoke test still passes.
- Existing pathfinding and monitor tests still pass where applicable.
- Save schema contains one authoritative strategic resource set, not both
  legacy and new values unless a temporary migration fallback is explicitly
  tested.

Done when:

- The game runs without errors.
- Relevant tests pass.
- Debug overlay works with strategic and spatial state.
- Map/pathfinding/AI serve the elder-choice loop instead of competing with it.

---

## Phase 5 - Balance And MVP Lock

Goal: make the first winter survivable but tense, then stop.

Balance targets:

- Default run should be winnable with reasonable policy choices.
- Random events should sometimes force hard choices but not create unavoidable
  losses from a healthy state.
- Winter should be the most dangerous season.
- Explore Forest should be tempting but risky.
- Rest First should be a real recovery tool, not a wasted week.
- Watching villagers move should clarify the day, not hide the strategic
  result.

Verification:

- Run at least 20 deterministic seeds through headless.
- Confirm at least some wins and some losses under automated policy scripts.
- Confirm all 25 event cards can appear across seeded runs.
- Confirm no resource or streak counter goes negative.
- Confirm debug overlay still reports useful strategic and pathing state.

Done when:

- MVP scope is locked.
- `simulation_rules.md` fully reflects the implemented hybrid rules.
- `project_overview.md` is updated to describe the new game.
- Old roadmap language about expanding into a map sandbox, complex AI,
  building placement, detailed wildlife simulation, or complex economy is
  removed or marked legacy.

---

## Out Of Scope For MVP

Do not build these in the first version:

- Player-directed unit control
- Map expansion beyond the existing small village board
- Building placement sandbox
- Room systems
- Equipment systems
- Item inventories
- Trade systems
- Diplomacy systems
- Tech trees
- Religion factions
- Class systems
- Law systems
- Marriage or birth
- Child growth
- Villager relationship networks
- Detailed combat
- Enemy AI beyond event/resource pressure
- Multiple villages
- Complex economy
- GOAP, ECS, behavior trees, or utility stacks beyond the existing simple
  scorer

If one of these seems necessary, first prove that the policy + event + light
map execution loop cannot carry the experience without it.

---

## Definition Of Done

A phase is done only if:

- Game or headless target runs without errors.
- Relevant GUT tests pass.
- Debug overlay still works when the phase touches live state.
- Existing map/pathfinding/AI tests still pass when those systems are touched.
- No unrelated files changed.
- Every implemented simulation rule is documented in
  `docs/simulation_rules.md`.

Documentation-only phases do not require a GUT run, but their final response
must say that no runtime verification was needed.
