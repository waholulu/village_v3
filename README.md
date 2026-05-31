# Tiny Campfire Village

A small Godot 4 village survival MVP.

Current codebase: a map-based autonomous villager survival prototype.
Current product direction: a hybrid event roguelike where the player is the
village elder, chooses weekly policies, resolves events, and watches villagers
carry out simple work through the existing map/pathfinding/AI layer.

## Running
Open project in Godot 4.6 and press F5.

## Tests
```
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -- -gdir=res://tests -gexit
```

## Docs
- Project overview: `docs/project_overview.md`
- Simulation rules: `docs/simulation_rules.md`
- Roadmap: `docs/ROADMAP.md`
- Current development plan: `docs/DEVELOPMENT_PLAN.md`

## Controls
- F3: toggle debug overlay
- F5: save game
- F9: load game

## Goal
Target MVP: survive 60 days through the first winter. Keep the MVP small:
5 player-facing resources, 5 jobs, 5 weekly policies, 25 event cards, one
readable village map, and no complex colony-sim systems.
