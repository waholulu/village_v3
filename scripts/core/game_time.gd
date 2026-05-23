class_name GameTime
extends Node

enum Phase { DAY, NIGHT }

signal day_started(day: int)
signal night_started(day: int)
signal game_won()

var day: int = 1
var phase: Phase = Phase.DAY
var tick: int = 0

var _day_duration: float = 10.0
var _night_duration: float = 5.0
var _days_to_win: int = 7
var _timer: float = 0.0

func setup(day_duration: float, night_duration: float, days_to_win: int) -> void:
	_day_duration = day_duration
	_night_duration = night_duration
	_days_to_win = days_to_win

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
		if day > _days_to_win:
			game_won.emit()
		else:
			day_started.emit(day)

func get_phase_name() -> String:
	return "Day" if phase == Phase.DAY else "Night"

func get_time_left() -> float:
	var current_duration: float = _day_duration if phase == Phase.DAY else _night_duration
	return current_duration - _timer
