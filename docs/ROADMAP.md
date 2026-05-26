# Roadmap

High-level outline of where the project is going, what is permanently out of
scope, and the discipline that keeps it from re-becoming v2.

For the **detailed plan for the phase currently being worked on**, see
`DEVELOPMENT_PLAN.md`. This file is the strategic frame; that one is the
tactical plan.

---

## Lessons from v2 (`waholulu/medival_village_v2`)

The previous attempt at this game (Python+Pygame) accreted complexity until it
stopped being debuggable. The concrete data:

| v2 artifact | Size | What it tells us |
|---|---|---|
| `ai_system.py` | ~1,700 lines | Priority-interrupt AI with 600-tick "need-locks" to prevent oscillation; three separate hunger-suppression conditions per (need × action) pair. |
| `action_system.py` | ~800 lines, 14 actions | Per-action state dicts; duplicate `_handle_build_drop` / `_handle_build` methods (unfinished refactor). |
| `diagnostic_logger.py` | ~600 lines | Two-tier logger with dedup cooldowns and hourly snapshots — built because the simulation was opaque without it. |
| `issues.md` | 11 open issues | 6/11 were state-desync debugging bugs; 3/11 were architectural smells (cold accumulating without decay, AI ignoring routine schedules, AI assigning unreachable tasks). |
| Roadmap phases | 6 planned | Phases 5–6 (society, lifecycle) never started; v4.1 was a 3-day pure stability sprint after Phase 4 dumped needs+seasons+agriculture+routines all at once. |

**Root cause**: layered AI (need priority + routine schedule + job queue + 14
action handlers), each layer added separately, never properly integrated. Each
new feature required overrides in earlier layers to prevent regressions until
no one understood the whole stack.

---

## Hard guardrails (apply to every phase)

Violating any of these is the early signal that v3 is becoming v2.

1. **File size cap: 600 lines.** `village_simulation.gd` is currently 585.
   Splitting it (candidates: `BuildingSystem`, `HungerSystem`, `WolfSystem`)
   is preferred over adding more.
2. **One scorer arm per task type.** No "if action == X then ignore need Y"
   suppression rules. If the scorer can't express it, the design is wrong.
3. **Action types capped at 10.** Currently 7. New action must justify why
   it can't be a parameter of an existing one.
4. **No state lock primitives.** No "need-lock", "anti-oscillation",
   "cooldown to prevent thrashing". Those mean your priority graph has a
   cycle; find it and remove it.
5. **No new global system without removing one.** Current systems:
   `Pathfinding`, `Nature`, `Construction`, `Monitor`. Adding a 5th means
   merging two or proving the 5th is fundamentally different.
6. **No second tier of AI scheduling.** No routines, shifts, "during
   harvest season do X." Period-dependent behavior is a scorer-input change,
   not a new layer.
7. **JSONL logger stays under 50 lines.** Need richer diagnostics? Write a
   one-shot script that consumes the JSONL externally — don't grow the
   in-sim logger.
8. **Every new balance value goes in `balance.json` (or a sibling preset
   file).** No magic numbers in `.gd`.
9. **`168 tests` + headless smoke must stay green between commits.** No
   "stabilization sprints" allowed. Broken smoke ≠ mergeable.
10. **Anti-features list is binding.** See below.

---

## Anti-features (permanently out of scope)

Each entry is here because v2 implemented or planned it, and either it was
the root of a major bug or the reason the project stalled.

| Feature | Why excluded |
|---|---|
| Generational lifecycle (births, aging, inheritance) | v2 Phase 6, never started. Adds a second time scale (lifespans) interacting with day/night/seasons. |
| Disease / illness mechanics | Second-tier need that interacts with hunger, cold, fatigue. |
| Mood / happiness need | v2 had hunger + tiredness + mood + cold; cold-without-decay (v2 issue #9) showed the integration cost. Hunger is enough. |
| Tiredness / sleep cycles | v2 issues #3, #4 (SLEEPING state ignored; sleep flag leaks). Adds a second time-of-day constraint on top of day/night phase. |
| Routines / schedules per villager | v2 issue #11 — "decoupled from AI by definition." Day/night phase is the only schedule. |
| Skills with XP progression | v2 had 4 skill trees; none changed how the game played meaningfully. |
| Tool durability / inventory items as entities | v2 partially implemented and abandoned. Wood is wood; no wooden-axe-with-durability. |
| Per-villager personalities / traits | Trait × action interaction matrix is O(n²). |
| Trading / external NPCs | A second economy. |
| Combat / direct player control | Game is observation. Don't blur the line. |
| Multiple maps / world transitions | One map. |
| Mod loader / scripting API | Premature platform thinking before the game proves itself. |

If a feature is *almost* on this list, treat that as the answer.

---

## Phases overview

Each phase has a **definition of done** that is a single observable, not a
list of subtasks. Finishing a phase means **stopping** and deciding whether
the next one is worth doing.

### Phase 0 — Baseline ✅ done

7-day survival loop, utility AI, day/night, hunger, wood/food economy,
deer/wolf wildlife, 4 building types, reachability-safe world gen, JSONL
audit log, 168 tests, headless WIN day 8.

### Phase 1 — Difficulty presets ⬅ **current**

The default balance never lets the campfire fail, so the wolf-threat path,
fence mitigation, and watchtower mitigation are all dormant code.

**Done when**: a `hard` preset exists, the headless run loaded against it
produces at least one `wolf_threat` event in JSONL within 7 days, the
existing 168 tests still pass against the default preset, and a new test
exercises the hard preset's threat path.

See `DEVELOPMENT_PLAN.md` for the detailed plan.

**Stop and reassess if**: making hard mode work requires changing any `.gd`
file beyond `headless_runner.gd` (preset selection) and possibly a small
balance-loader tweak. If business logic changes, behavior wasn't actually
parameterized — fix that before continuing.

### Phase 2 — Win-condition variants

Today the only win is "survive 7 days." Add one variant (pick one, not all):

- Survive N days where N is a balance value
- Build all 4 building types
- Stockpile threshold (food + wood ≥ target by deadline)

Implement as a `WinCondition` resource referenced from `BalanceData`, not as
a new global system. The existing `game_won` signal stays the only
completion signal.

**Done when**: swapping the win condition in balance is a one-line change;
all old tests still pass; a new test exists per variant.

**Stop and reassess if**: implementing a variant requires touching
`village_simulation.gd._on_day_started` for anything other than asking the
WinCondition object whether the game is over. That would be adding a layer.

### Phase 3 — Visible wolf attack

Wolves currently disrupt by adding hunger, which is invisible to the player.
Replace with: when `wolf_threat` fires, the wolf sprite moves onto a
villager's tile, the villager loses a hunger/hp point, the wolf retreats.

Constraints:
- **Reuse `hunger`** as the damage track. Do not add HP.
- **No `CombatSystem`.** The resolution is a one-shot animation/log event,
  not a combat loop.

**Done when**: in a hard-mode headless run, every `wolf_threat` JSONL event
is preceded by a new `wolf_attacked` event with the chosen villager's id;
in live play the wolf sprite visibly approaches before the hunger change.

**Stop and reassess if**: this needs a third state on `VillagerAgent`
(today: IDLE, MOVING_TO_TARGET). A "fleeing" or "stunned" state means we
just opened the door to a combat loop.

### Phase 4 — Save / load polish

Save format works but has duplication: `_fence_count` is stored AND derivable
from `world_gen.count_tiles_of_type(FENCE)`. Same for watchtower and storage.
Tighten: derive on load, drop the stored counters, keep a single source of
truth.

**Done when**: save → quit → reload produces a byte-identical JSON snapshot
on the next save; an assertion in `SaveManager.load_into` confirms counters
match tile counts.

**Stop and reassess if**: save/load grows past 200 lines. Today it's 128.
Growth past 200 means we're storing derived state.

### Phase 5 — STOP HERE (deliberate)

After Phase 4 the game is feature-complete by the original brief: a small,
observable, deterministic village survives a fixed challenge under a balance
config you can edit.

There is no Phase 5. If you find yourself sketching one, re-read the
anti-features list and ask which entry it falls under. If none, ask whether
it pays for its complexity *in playable minutes*, not in "systems that
could compose."

---

## Total scope estimate

| Phase | Net new code | Risk |
|---|---|---|
| 1 — Difficulty presets | ~50 lines + 1 JSON file | Low — additive, no business logic touched |
| 2 — Win conditions | ~80 lines | Low–Medium — touches one signal handler |
| 3 — Visible wolf attack | ~120 lines | Medium — first inter-system animation handoff |
| 4 — Save/load polish | net **negative** (~ −30 lines) | Low — removes duplication |
| **Total beyond Phase 0** | **~ +250 lines** | |

v2's roadmap was 6 phases of feature accumulation, each adding more than the
previous, with nothing ever removed. This roadmap is 4 small phases plus a
hard stop. The anti-features list is longer than the feature list, and that
is the point.

---

## Recurring discipline (every commit)

- Run 168 tests + headless smoke before committing (commands in `CLAUDE.md`).
- New `var X` on `village_simulation.gd`? Ask if it could live on
  `VillagerAgent`, `Task`, `BuildingDefs`, or `BalanceData`. The sim is for
  *coordination*, not state hoarding.
- Test names containing `_regression` / `_bug_fix` → file under the system
  they test, not a regression bucket. v2 had four separate regression test
  files. Don't.
- Comments like "// hack: ..." or "// workaround for ..." must link to a
  current-phase issue. Drifting workarounds are how complexity ratchets up.
- Re-read `MEMORY.md` when resuming after a break.
