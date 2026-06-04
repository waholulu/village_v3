# Code Review — 2026-06-04

Review of the simulation core (`scripts/sim/`, `scripts/core/`, `scripts/world/`)
for correctness, performance, and maintainability. Findings are grouped by
confidence and ordered by value. Nothing in this document has been applied —
it is a backlog for the maintainer to action, because the GUT suite and
`tools/headless_audit.ps1` (Windows + Godot) could not be run in the review
environment, and `CLAUDE.md` requires both to gate any rule/balance change.

## Summary

The codebase is in good shape. Layer separation (sim / render / UI) is clean,
game-over signals are correctly latched (`_game_over`), test setup is
idempotent (`_reset_state`), and the inline rationale comments are unusually
good. No correctness bugs were found in the night, hunger, campfire, spoilage,
or scoring paths. The items below are encapsulation, tunability, and minor
efficiency improvements — not defects.

### False alarms checked and dismissed

These looked suspicious on a first pass but are correct as written, recorded
here so they aren't re-flagged later:

- `VillageSimulation._anomalies_equal` (lines 218–228) — element-wise compare is
  correct.
- `_cancel_tasks_with_stale_approach` line 529 — `status != OPEN and not
  was_claimed` correctly processes only OPEN/CLAIMED tasks.
- `_tick_villagers` single-point path — when a villager is already on its
  `approach_tile`, `get_path` returns a 1-element path; `VillagerAgent.tick_movement`
  (lines 81–84) arrives correctly on the next move interval. Not a stuck state.
- `HungerSystem.resolve` partial-feed — a villager fed less than the full
  ration still gains hunger (`fed = total_consumed == per_night`). Intentional.

---

## Findings

### 1. `TaskBoard._tasks` is read directly across the simulation — code-smell

`TaskBoard` deliberately hides `_tasks` behind methods
(`get_open_tasks`, `has_active_task_of_type`, `has_task_for_tile`,
`count_by_status`). But `VillageSimulation` bypasses that API and iterates the
private array directly in at least six places:

- `_update_nature_for_day` — `village_simulation.gd:505`
- `_cancel_tasks_with_stale_approach` — `village_simulation.gd:527`
- `_cancel_stale_hunt_tasks` — `village_simulation.gd:547`
- `_cancel_open_tasks_of_type` — `village_simulation.gd:594`
- `_count_active_tasks_of_type` — `village_simulation.gd:708`
- `inspect_tile` — `village_simulation.gd:911`

It also reads `board._tasks.size()` deltas to detect whether a task was created
(`_try_create_resource_tasks_limited`, lines 672–675), which is brittle.

**Suggested fix (behavior-preserving):** add query/mutation helpers to
`TaskBoard` and route the sim through them, e.g.:

- `count_active_of_type(type) -> int`
- `for_each_active(callable)` or `get_active_tasks() -> Array[Task]`
- `cancel_open_of_type(type) -> Array[Task]` (returns cancelled tasks so the
  caller can log)
- have `_try_create_resource_task` return a `bool` so callers stop diffing
  `.size()`.

This is a pure refactor (no rule change), but still needs the GUT suite run to
certify it, since several task tests assert board state.

### 2. `ResourceStore` add/set food asymmetry is undocumented — code-smell

- `set_resource("food", x)` → `_set_food_total` splits across fresh/stored
  (`resource_store.gd:30–32`).
- `add_resource("food", x)` → routes entirely to `stored_food`
  (`resource_store.gd:43–45`).

This is almost certainly intentional (strategic/event food gains are durable,
non-spoiling stores), but the divergence is surprising and unguarded. A future
caller could reasonably expect `add` and `set` to treat `"food"` the same way.

**Suggested fix:** a one-line comment on `add_resource` stating that strategic
`"food"` deltas intentionally land in `stored_food` (non-spoiling), referencing
the spoilage rule in `night_resolution.gd`. No behavior change.

### 3. `UtilityScorer` weights are hardcoded, not in `BalanceData` — tunability

`score_task` (`utility_scorer.gd:15–47`) uses magic constants for every task
type: `10.0`, `* 3.0`, `+ 8.0`, `build_house 25.0`, `build_watchtower 20.0`,
`build_fence 15.0`, `build_storage 12.0`, `tend_villager 18.0`, the `0.5`
distance penalty, etc.

Every other tuning knob in the game lives in `data/balance.json` →
`BalanceData`, so these are the one set of behavioral parameters that can't be
tuned without editing code. Hoisting them into `BalanceData` (new properties +
JSON keys, per the "Balance tuning" section of `CLAUDE.md`) would make scoring
auditable and tweakable.

**Caveat:** this changes default balance, so it is gated on
`.\tools\headless_audit.ps1 -Strict` passing (win on day 61, anomalies 0, etc.).
Do not land without that.

### 4. `TaskBoard.get_task` is an O(n) linear scan — minor performance

`get_task` (`task_board.gd:32–36`) scans `_tasks` on every
`claim_task` / `complete_task` / `cancel_task`. With the per-type task caps
(low tens of tasks) this is negligible today. Only worth an `id → Task`
dictionary if a profiler ever shows it; the dictionary would add maintenance
cost to `create_task` and `clear_stale`.

### 5. `BalanceData` reflective `set(key, value)` loader — robustness (informational)

`load_from_file` uses `set(key, data[key])` reflection. This is the documented
pattern (`CLAUDE.md` "Balance tuning") and keeps the loader generic, but it
silently no-ops on typos (a JSON key with no matching property is ignored) and
does no int/float coercion. Not a bug — just be aware that a misspelled balance
key fails silently rather than loudly. A future hardening step could warn on
unknown keys.

---

## Recommended order of work

1. **#2** — one-line doc comment, zero risk.
2. **#1** — `TaskBoard` encapsulation refactor; run GUT suite to certify.
3. **#3** — scorer weights → `BalanceData`; gate on `headless_audit -Strict`.
4. **#4 / #5** — only if profiling / robustness concerns arise; low priority.
