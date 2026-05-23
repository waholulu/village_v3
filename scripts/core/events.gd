extends Node

# Global signal bus. Only signals that have at least one emitter AND at least
# one listener live here. Task-* signals are intentionally omitted from the MVP
# — TaskBoard state is polled directly by the debug overlay.

signal stock_changed(resource_name: String, amount: int)
signal day_started(day: int)
signal night_started(day: int)
signal game_won()
signal game_lost(reason: String)
