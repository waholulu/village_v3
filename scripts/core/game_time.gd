class_name GameTime
extends Node

enum Phase { DAY, NIGHT }
enum Season { SPRING, SUMMER, AUTUMN, WINTER }

signal day_started(day: int)
signal night_started(day: int)
signal season_changed(season: Season)

var day: int = 1
var phase: Phase = Phase.DAY
var tick: int = 0
var current_season: Season = Season.SPRING

var _day_duration: float = 10.0
var _night_duration: float = 5.0
var _days_per_season: int = 5
var _timer: float = 0.0

func setup(day_duration: float, night_duration: float, days_per_season: int) -> void:
	_day_duration = day_duration
	_night_duration = night_duration
	_days_per_season = days_per_season

func _process(delta: float) -> void:
	tick += 1
	_timer += delta
	var current_duration: float = _day_duration if phase == Phase.DAY else _night_duration
	if _timer >= current_duration:
		_timer = 0.0
		_advance_phase()

func _advance_phase() -> void:
	if phase == Phase.DAY:
		phase = Phase.NIGHT
		night_started.emit(day)
	else:
		phase = Phase.DAY
		day += 1
		var new_season: Season = _compute_season(day)
		if new_season != current_season:
			current_season = new_season
			season_changed.emit(current_season)
		day_started.emit(day)

func _compute_season(d: int) -> Season:
	return ((d - 1) / _days_per_season) % 4

func get_phase_name() -> String:
	return "Day" if phase == Phase.DAY else "Night"

func get_season_name() -> String:
	return ["Spring", "Summer", "Autumn", "Winter"][int(current_season)]

func get_time_left() -> float:
	var current_duration: float = _day_duration if phase == Phase.DAY else _night_duration
	return current_duration - _timer
