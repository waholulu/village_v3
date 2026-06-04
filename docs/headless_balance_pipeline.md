# Headless Balance Pipeline

Use this loop whenever a balance or simulation-rule change should be checked
against a deterministic 60-day run.

## 1. Run The Audit

```powershell
.\tools\headless_audit.ps1
```

Useful variants:

```powershell
.\tools\headless_audit.ps1 -Preset hard
.\tools\headless_audit.ps1 -Strict
.\tools\headless_audit.ps1 -GodotPath E:\godot\Godot_v4.6.3-stable_win64_console.exe

# Reproduce one exact seed directly through the headless runner
& E:\godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . -s res://scripts/core/headless_runner.gd -- seed=4319
```

The script writes an ignored run folder under `.godot/headless_audit/` with:

- `godot.log`: raw headless stdout/stderr.
- `audit_report.json`: parsed metrics and pass/fail gates.
- `seed_<n>.log`: per-seed logs for the default preset sweep.
- The Godot JSONL path printed by `HeadlessRunner`.

Without `-Strict`, the script exits `0` after writing the report even if the
simulation loses; use `-Strict` when a CI-style pass/fail gate is wanted.

## 2. Read The Gates

Default gates are intentionally small and repeatable:

- Godot exits `0`.
- The default preset wins on day 61.
- Monitor anomalies stay at `0`.
- Final strategic food is not runaway-high.
- Negative task-claim rate stays near zero.
- Daily task-cancellation bursts stay bounded.
- Default preset sweep over seeds `4312..4321` wins at least `7/10`.
- Winning runs in that sweep average `20-40%` villager deaths.

The report also records per-run dead population, death rate, and whether
strategic and visible population diverged.

## 3. Adjust One Lever

Prefer one small change per loop:

- Survival pressure: `food_consumed_per_villager_per_night`.
- Food runaway or starvation softness: `deer_hunt_radius`, `food_per_deer`,
  `starting_food`, `food_surplus_threshold`, and daily food job output.
- Task noise: `max_open_resource_tasks_per_type`,
  `max_policy_open_tasks_per_type`, `policy_food_task_target`,
  `policy_wood_task_target`, task scoring thresholds.
- Threat pressure: wolf spawn/radius/disruption values, winter wood demand, and
  `max_campfire_out_nights`.

After a rule change, update `docs/simulation_rules.md` and add or update a GUT
test for the rule.

## 4. Verify

Run the focused tests for touched systems first, then the full deterministic
audit:

```powershell
& E:\godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . -s res://addons/gut/gut_cmdln.gd -- -gdir=res://tests -gexit
.\tools\headless_audit.ps1 -Strict
```

If `-Strict` fails, keep the report and tune the next smallest lever instead
of stacking unrelated changes. When the failure is in the death-rate gate,
inspect `audit_report.json -> seed_sweep` first; converting one high-death loss
into a win is often better than globally making every run harsher.
