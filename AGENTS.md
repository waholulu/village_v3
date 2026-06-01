# Tiny Campfire Village — Agent Instructions

## Project goal
Small Godot 4 MVP for testing an agent-friendly game development workflow.

Hybrid village survival roguelike:
- Player is the village elder.
- Player chooses one weekly policy and resolves event choices.
- Villagers remain autonomous and use the existing map, pathfinding, and task AI as a light execution layer.
- Target MVP: 60 days, 5 player-facing resources, 5 jobs, 5 weekly policies, 25 event cards.
- Survive through day 60 = win.
- Lose if population reaches 0, or food/morale/security stays at 0 for 3 consecutive daily resolutions.

## Technology
- Godot 4.6, GDScript
- TileMapLayer, AStarGrid2D
- GUT for tests, JSON for save/load

## Non-negotiables
- Keep MVP small. No external AI frameworks. No ECS. No GOAP.
- Preserve useful existing map/pathfinding/AI work, but do not expand it into a map sandbox or complex colony sim.
- Simulation logic must be separate from rendering.
- Prefer deterministic behavior (fixed seed).
- Every simulation rule must have a test.
- Do not change unrelated files.

## Architecture
- scripts/core: events, balance, time, resources, save/load
- scripts/world: map generation, tilemap, pathfinding
- scripts/sim: villagers, tasks, simulation orchestration
- scripts/ui: HUD and debug overlay

## Definition of done
A task is done only if:
- Game runs without errors.
- Relevant tests pass.
- Balance/simulation-rule changes pass `.\tools\headless_audit.ps1 -Strict`.
- Debug overlay still works.
- No unrelated files changed.
- Changed rules documented in docs/simulation_rules.md.
- New or changed tuning workflow is documented in docs/headless_balance_pipeline.md.
