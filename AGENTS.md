# Tiny Campfire Village — Agent Instructions

## Project goal
Small Godot 4 MVP for testing an agent-friendly game development workflow.

3 villagers, collect wood/food during the day, consume at night, keep campfire alive.
Survive 7 days = win. Campfire out 2 consecutive nights = lose.

## Technology
- Godot 4.6, GDScript
- TileMapLayer, AStarGrid2D
- GUT for tests, JSON for save/load

## Non-negotiables
- Keep MVP small. No external AI frameworks. No ECS. No GOAP.
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
- Debug overlay still works.
- No unrelated files changed.
- Changed rules documented in docs/simulation_rules.md.
