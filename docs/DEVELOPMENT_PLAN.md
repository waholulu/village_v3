# Development Plan — Phase 1: Difficulty Presets

For the full multi-phase outline, anti-features list, and guardrails, see
`ROADMAP.md`. This document is the tactical plan for the current phase only.

---

## Why this phase

The default balance produces a comfortable run: the campfire never lapses,
so `_apply_wolf_disruption()`, `fence_wolf_damage_reduction`, watchtower
halving, and `_wolf_threat_count`-gated fence construction are all dormant
code paths.

Two consequences:

1. **The wolf threat path is unverified end-to-end in real play.** It's
   covered by unit tests (`test_wildlife_system.gd`) and by a one-off A/B
   diagnostic we ran earlier (wolf at corner-trap, 14 days), but no
   integrated headless run has produced a `wolf_threat` event.

2. **Fence/watchtower construction never triggers.** The reactive fence
   condition (`_has_wolves(sim) AND _wolf_threat_count > 0`) by design
   never fires in default play. Their effects are dead code at runtime.

The fix is not to change defaults — the default difficulty is fine. It's
to add a **hard preset** that forces the campfire to fail at least once, so
the threat path can be exercised in a reproducible headless run.

This is also a sanity check on the codebase itself: if making the game
harder requires editing `.gd` files instead of just balance values, the
behavior wasn't actually parameterized and we have a problem to fix
*before* adding new features.

---

## Approach

**Side-by-side balance files**, not nested presets. Reasons:

- `BalanceData.load_from_file` is currently flat: `for key in data: if key
  in self: set(key, data[key])`. Nesting would require a parser rewrite.
- Diffing two flat JSON files in git is the cleanest way to see "what
  changed for hard mode."
- Players who edit balance see one schema, not a nested override system.

Concrete shape:

```
data/balance.json         # default — unchanged
data/balance_hard.json    # full file, identical schema, tuned values
```

`headless_runner.gd` accepts an optional preset name from
`OS.get_cmdline_args()`. If present, loads `balance_<name>.json` instead of
`balance.json`. Default behavior is unchanged.

```
godot --headless --path . -s res://scripts/core/headless_runner.gd -- preset=hard
```

(Godot passes args after `--` through to the script. We parse with a tiny
loop in `_init`.)

---

## Hard-mode design

Goal: at least one `wolf_threat` event must fire within 7 game-days,
**without making the game unwinnable** (we want a reproducible loss case
later, but Phase 1's ship criterion is just that the path fires).

Mental simulation against the current sim mechanics:

- Wolves spawn ≥ 10 tiles from HUT (hardcoded in `_spawn_animals`).
- A wolf at spawn moves 1 tile per day toward HUT (via pathfinding).
- `check_wolf_threat` requires `campfire_out_nights > 0` AND wolf within
  `wolf_threat_radius`.

So we need: (a) campfire fails at least one night, (b) at least one wolf
is within radius the same night.

Picked deltas (vs. default):

| Key | Default | Hard | Reason |
|---|---|---|---|
| `starting_wood` | 10 | 1 | Night 1 campfire eats 2, shortfall = 1, `campfire_out_nights` → 1 |
| `max_campfire_out_nights` | 2 | 4 | Don't lose immediately on the forced failure; let the game keep running so we can observe whether villagers recover |
| `starting_food` | 8 | 5 | Tighter food too, but still survivable for night 1 (3 villagers × 1 = 3 consumed) |
| `wolf_spawn_day` | 4 | 1 | Wolves present from day 1, so they can be in range by night 1 |
| `wolf_spawn_interval_days` | 3 | 2 | Slightly more frequent so a wolf is reliably nearby |
| `wolf_threat_radius` | 8 | 10 | Catches wolves at their spawn distance after one move |
| `wolf_hunger_disruption` | 1 | 2 | Threats matter when they fire |

Everything else (world gen, regrowth, building costs, surplus thresholds)
stays at default. **Smaller blast radius = easier to debug if hard mode
misbehaves.**

The expected day-1 trace under this preset:

```
Day 1 starts:
  _update_nature_for_day:
    _spawn_animals: 1 wolf at distance ~10 from HUT
    _move_animals: wolf moves 1 step → distance ~9
  (day phase runs normally)
Night 1:
  resolve_night: consume 2 wood, only 1 available → campfire_out_nights = 1
  check_wolf_threat(campfire_out_nights=1):
    wolf_threat_radius = 10
    wolf at distance ~9 ≤ 10 → returns true
  _apply_wolf_disruption:
    _wolf_threat_count → 1
    log "wolf_threat" event
    one villager loses 2 hunger
```

If this trace doesn't happen in practice, the bug is **interesting** and
we want to know — that's the whole point of the phase.

---

## Files touched

| File | Change | Estimated LOC |
|---|---|---|
| `data/balance_hard.json` | New file. Full schema, copied from `balance.json` with the 7 keys above changed. | +69 (the file itself, but new) |
| `scripts/core/headless_runner.gd` | Parse `preset=<name>` from `OS.get_cmdline_args()` after `--`. Choose balance path accordingly. Log which preset is active in the run header. | +15 |
| `tests/test_difficulty_preset.gd` | New GUT test. Load `balance_hard.json` via `BalanceData.load_from_file()`. Construct a sim with this balance. Run for a few in-game seconds (or call `resolve_night()` directly twice). Assert `sim._wolf_threat_count >= 1` and that the latest monitor anomalies list contains no `error`-severity entries. | +50 |
| `scripts/core/balance_data.gd` | None expected. If the hard preset surfaces a missing field, add the field — but it should be a no-op. | 0 |
| `scripts/sim/village_simulation.gd` | **No changes.** If you find yourself editing this, stop and read the "Stop and reassess" section in `ROADMAP.md` for Phase 1. | 0 |

Total: ~135 lines, of which 69 is a copied JSON.

---

## Test plan

Three layers of verification:

### 1. Unit test (`tests/test_difficulty_preset.gd`)

```gdscript
extends GutTest

func test_hard_preset_loads() -> void:
    var balance := BalanceData.new()
    assert_true(balance.load_from_file("res://data/balance_hard.json"))
    assert_eq(balance.starting_wood, 1)
    assert_eq(balance.wolf_spawn_day, 1)

func test_hard_preset_triggers_wolf_threat_within_3_nights() -> void:
    # Build a sim with the hard preset and step through enough nights to
    # exercise the threat path. We don't simulate the full day cycle here —
    # we drive resolve_night() directly after seeding a near-HUT wolf to
    # keep the test focused on the threat path, not pathfinding luck.
    ...
    assert_gte(sim._wolf_threat_count, 1)
```

The "drive directly" approach keeps this test deterministic and fast
(< 1 second). End-to-end pathfinding-and-spawn validation happens in
verification step 2 below.

### 2. Headless hard-mode run

```
godot --headless --path . -s res://scripts/core/headless_runner.gd -- preset=hard
```

Grep the resulting JSONL for `"event":"wolf_threat"`. Must find ≥ 1 within
7 days.

### 3. Default smoke test still passes

The existing 168 tests must stay green and the default-preset headless run
must still produce `RESULT: WIN on day 8` with 0 anomalies. Phase 1 is a
**purely additive** change; if anything regresses on the default path,
something was wired wrong.

---

## Definition of done

All three of the following:

1. ✅ Test `test_hard_preset_triggers_wolf_threat_within_3_nights` passes.
2. ✅ `--preset=hard` headless JSONL contains ≥ 1 `wolf_threat` event.
3. ✅ Default 168 tests + default headless WIN on day 8 still green.

If 1 and 2 fail in a "interesting" way (the path doesn't fire when it
should), **that is the actual deliverable of the phase** — we just
surfaced a real bug in the threat mechanism that was hidden by the
default balance. Document it, fix it, then ship.

---

## Out of scope for Phase 1

These are tempting and **not now**:

- `balance_easy.json` — only build it if a real reason emerges. Two
  presets are testable; three are an interface.
- A preset selector UI in live play — players can pass it on the launch
  command. Don't build a menu.
- Re-running the whole 168-test suite under hard mode — they encode
  default-preset behavior, which is fine; hard mode gets its own targeted
  test instead.
- Tweaking `_apply_wolf_disruption`, `check_wolf_threat`, or the planner's
  fence condition. Phase 1 *exercises* these; modifying them is Phase 2 or
  later if a bug forces it.

---

## After this phase

If Phase 1 ships clean, the natural next step is Phase 2 (win-condition
variants — see `ROADMAP.md`). If Phase 1 surfaces a bug in the wolf threat
path or fence/watchtower mitigation, fix it as part of this phase before
moving on — that bug existed silently for days under the default balance
and is the actual value Phase 1 delivers.

Either way, **stop after closing Phase 1.** Don't roll into Phase 2 in the
same session without a fresh decision to start it.
