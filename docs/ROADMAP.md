# Roadmap

High-level outline of where the project is going, what is permanently out of
scope, and the discipline that keeps the MVP small.

For the tactical plan for the current work cycle, see
`DEVELOPMENT_PLAN.md`. For exact runtime behavior, see
`simulation_rules.md`.

---

## Product Direction

Tiny Campfire Village is now scoped as:

> Village survival pressure + event choices + automatic resolution roguelike,
> with the existing map, pathfinding, and villager AI kept as a constrained
> execution layer.

It is not a RimWorld-like simulation and not a map sandbox. The player is the
village elder. The player makes weekly strategic choices and event decisions;
villagers automatically carry out simple work on the map.

The target first complete version is:

- 5 player-facing resources
- 5 jobs
- 5 weekly policies
- 10 visible villagers by MVP lock
- 25 event cards
- 60-day survival goal
- one readable village map
- existing pathfinding for movement
- simple autonomous task AI

---

## Why The Hybrid Scope

The current codebase already has useful work: map generation, pathfinding,
villager movement, task scoring, wildlife, construction, HUD, debug overlay,
save/load, and tests. Throwing all of that away would waste working
infrastructure.

The risk is letting those systems define the game. The MVP should not become
a building sandbox, detailed colony sim, or multi-layer AI project. The map
and AI should make automatic daily work visible; the strategic game should
remain weekly policies, event choices, and survival pressure.

---

## Retained Systems

These are allowed in the MVP, with limits:

| System | Allowed role | Limit |
|---|---|---|
| Map | Shows the village and work targets. | One map, no map expansion loop. |
| Pathfinding | Moves villagers to simple tasks. | No pathfinding puzzles or new routing gameplay. |
| Villager AI | Chooses from generated tasks. | One scorer layer, no schedules or planning stacks. |
| Task board | Represents current work. | Tasks come from policies, events, survival pressure, or simple projects. |
| Wildlife | Provides event flavor and simple risk. | No enemy AI or combat loop. |
| Construction | Supports visible projects if needed. | No building tree or placement sandbox. |
| Debug overlay | Shows strategic and spatial state. | It must stay readable, not become a diagnostic platform. |

---

## Hard Guardrails

Violating any of these is an early signal that the project is expanding beyond
the MVP again.

1. **The map is support, not the game.** The player should understand the run
   from policy choices, event choices, resources, and daily logs.
2. **Pathfinding stays infrastructure.** It should answer "can this villager
   reach the work target?" and nothing more.
3. **AI stays one-layer.** No GOAP, ECS, behavior trees, routines, shifts,
   need locks, anti-oscillation cooldowns, or stacked scorers.
4. **No direct villager control.** The player chooses a weekly policy and
   event options only.
5. **Exactly 5 player-facing resources.** Population, food, wood, security,
   and morale. Replacing one requires removing one first.
6. **Exactly 5 jobs.** Farmer, hunter, woodcutter, guard, herbalist.
   Replacing one requires removing one first.
7. **Exactly 5 weekly policies.** Food First, Wood First, Defense First,
   Rest First, Explore Forest.
8. **Villagers have exactly 4 gameplay fields.** Name, job, status, trait.
   Position, path, task id, and movement timers are implementation state.
9. **Task types stay capped at 10.** New task types must replace or reuse an
   existing one unless there is a strong tested reason.
10. **Events stay flat.** Each event has immediate option results and at most
    one short-term effect. No chains, hidden quest state, or story graphs.
11. **Simulation stays separate from rendering.** Strategic resolution must
    run headless; rendering may visualize it.
12. **No parallel simulation cores.** Adapt the existing simulation before
    adding new state holders. A helper object is acceptable; a second
    authoritative run state is not.
13. **Every simulation rule has a test.** No numeric rule is "just balance" if
    code branches on it.
14. **No unrelated rewrites.** Existing map/pathfinding code may be adapted to
    the new loop, but not refactored for its own sake.
15. **Temporary population mismatch is allowed only during migration.** Phase
    1 may track `population = 10` while the map still shows 3 agents, but MVP
    lock requires 10 visible villagers or an explicit design revision.

---

## Anti-Features

These are out of scope for the MVP.

| Feature | Reason |
|---|---|
| Player-directed unit control | Breaks the elder role and turns the game into micro-management. |
| Map expansion loop | Turns one readable board into a spatial progression system. |
| Pathfinding as gameplay | Pulls attention away from policy and event choices. |
| Building placement sandbox | Reopens zoning, reachability, and tile-ownership complexity. |
| Room systems | Requires spatial ownership and path rules. |
| Equipment systems | Adds inventory and item identity. |
| Item inventory | The MVP economy is five integer resources. |
| Trade system | Adds another economy. Event rewards can cover the fantasy for now. |
| Diplomacy | Adds external faction state before the village loop is proven. |
| Tech tree | Long-term progression before the 60-day loop is balanced. |
| Religion factions | Adds politics and relationship state. |
| Class or law systems | Adds social simulation outside the MVP. |
| Marriage, birth, and child growth | Adds lifecycle simulation and a second time scale. |
| Relationship networks | Explodes event and trait interactions. |
| Detailed combat | Security is the abstraction. |
| Enemy AI | Threats are event and resource pressure, not tactical agents. |
| Multiple villages | Multiplies save, UI, map, and event scope. |
| Complex economy | Five resources are enough for the first version. |

### Explicitly deferred resources

Do not add gold, tools, herbs, stone, knowledge, faith, noble relations, or
trade relations in the MVP.

### Explicitly deferred jobs

Do not add blacksmiths, priests, merchants, miners, cooks, teachers, or other
jobs in the MVP.

---

## Target MVP Loop

1. Start with 10 villagers, five resources, and one small village map.
2. Choose one weekly policy.
3. Villagers automatically execute simple work on the map.
4. Resolve each day:
   - food consumption
   - job and policy production
   - injury or sickness recovery
   - event roll
   - daily log
   - win/loss checks
5. When an event appears, choose option A, B, or C.
6. Survive through day 60 to win.

The emotional texture comes from logs, events, and watching villagers carry
out simple work. It does not come from detailed simulation.

---

## Phases Overview

Each phase has one observable outcome. Finishing a phase means stopping and
checking whether the next phase is still worth doing.

### Phase 0 - Planning Pivot

Replace the old expansion plan with the hybrid event roguelike MVP plan.

Done when: `DEVELOPMENT_PLAN.md` and this roadmap retain map/pathfinding/AI
as capped support systems, and runtime rule docs are not falsely rewritten
ahead of implementation.

### Phase 1 - Strategic Run State

Create a deterministic 60-day strategic state with resources, seasons,
villagers, win condition, and loss streaks.

Done when: the strategic state is integrated with the existing simulation and
can be tested headlessly while preserving the existing map simulation. A
temporary 3-visible-agent / 10-population mismatch is acceptable if documented
and tested.

### Phase 2 - Policy To Task Bridge

Implement weekly policies by changing task generation, task weights, output,
risk, and daily summary rules.

Done when: a 60-day headless run can resolve through the policy loop with the
map and simple AI enabled.

### Phase 3 - Event Cards

Add the 25-card event deck, event options, immediate results, short-term
effects, and event logs.

Done when: every event card and effect type has a focused test, and seeded
runs draw events deterministically.

### Phase 4 - Playable Shell

Wire the hybrid simulation to HUD, event choice UI, debug overlay, map view,
and save/load.

Done when: the game can be played as an elder-choice survival roguelike while
still showing villagers moving and working.

### Phase 5 - Balance And MVP Lock

Tune the 60-day run, verify multiple deterministic seeds, update current
runtime docs, and stop feature work.

Done when: the MVP loop is playable, tested, documented, and still small.

---

## Total Scope Estimate

| Phase | Net code | Risk |
|---|---:|---|
| 1 - Strategic run state | +150 to +300 | Medium |
| 2 - Policy to task bridge | +200 to +400 | Medium |
| 3 - Event cards | +250 to +450 plus JSON | Medium |
| 4 - Playable shell | +200 to +400 | Medium |
| 5 - Balance and docs | Mostly data/docs | Low |

These estimates assume existing map/pathfinding/AI are reused rather than
expanded. If a phase starts requiring a new AI layer, detailed combat, building
placement, or a new economy, the design has drifted.

---

## Recurring Discipline

- Run relevant GUT tests before declaring an implementation phase done.
- Run the headless target after changes to daily resolution, save/load, AI
  task selection, or win/loss rules.
- Keep `simulation_rules.md` synchronized with implemented behavior, not
  future intent.
- Keep event, job, policy, and balance data readable enough that a designer
  can tune it without reading every system file.
- When a new idea appears, classify it as policy, event, job effect, simple
  task, resource change, visual feedback, or out of scope. If it does not fit
  one of those buckets, it is probably not MVP work.
